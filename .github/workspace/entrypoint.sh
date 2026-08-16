#!/usr/bin/env bash
set -euo pipefail

: "${WORKSPACE_REPO_URL:?WORKSPACE_REPO_URL must be set (e.g. https://github.com/org/repo.git)}"
: "${GITHUB_TOKEN:?GITHUB_TOKEN must be set (git clone/pull and gh both need it)}"

REPO_NAME="$(basename "${WORKSPACE_REPO_URL}" .git)"
REPO_DIR="/workspace/${REPO_NAME}"

# HOME is redirected onto the pod's PVC (k8s/paseo-pod.yaml), the same way CARGO_HOME and
# PASEO_HOME are, so that per-provider session state written under $HOME (Claude Code's
# ~/.claude/projects transcripts, credentials, etc.) survives a container restart instead of
# living on the container's ephemeral overlay layer and vanishing on every OOM/crash restart.
mkdir -p "${HOME}"
chmod 700 "${HOME}"

git config --global credential.helper store
echo "https://x-access-token:${GITHUB_TOKEN}@github.com" > "${HOME}/.git-credentials"
git config --global user.name "paseo-bot"
git config --global user.email "paseo-bot@users.noreply.github.com"

if [ -d "${REPO_DIR}/.git" ]; then
  echo "entrypoint: existing checkout found, pulling"
  git -C "${REPO_DIR}" pull --ff-only \
    || echo "entrypoint: pull skipped (local commits, dirty tree, or untracked branch) — serving the existing checkout"
else
  echo "entrypoint: no checkout found, cloning"
  git clone "${WORKSPACE_REPO_URL}" "${REPO_DIR}"
fi

claude plugin marketplace add obra/superpowers-marketplace
claude plugin install superpowers@superpowers-marketplace

cd "${REPO_DIR}"

# paseo.pid is a lock file paseo writes on start and removes on graceful shutdown. PASEO_HOME lives
# on the pod's PVC, so it survives container restarts, but a hard kill (OOM, CrashLoopBackOff)
# leaves it behind. A fresh container can never have a legitimately running prior instance, so any
# pid file found at boot is stale by construction — remove it before starting or every subsequent
# restart refuses to start with "Another Paseo daemon is already running".
rm -f "${PASEO_HOME:-${HOME}/.paseo}/paseo.pid"

echo "entrypoint: starting paseo daemon on 0.0.0.0:6767"
# Bare `paseo` daemonizes (double-forks to the background) and the launcher process then exits,
# which kills the whole container since it's PID 1 here — hence --foreground. It also defaults to
# binding 127.0.0.1 and rejecting any Host header but "localhost", neither of which works when the
# k8s Service is what's actually reaching this port, hence --listen/--hostnames. --no-relay keeps
# the tailnet-only posture this repo's k8s/README.md documents.
exec paseo start --foreground --listen 0.0.0.0:6767 --hostnames true --no-relay
