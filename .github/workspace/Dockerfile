# Paseo workspace image: Node + opencode-ai + gh + claude-code, checked out against a target repo
# and served over HTTP by k8s/paseo-pod.yaml. Built + published by
# .github/workflows/workspace-image.yml.
#
# No language toolchain is baked in on purpose: this image is reused across projects with
# different languages and version pins. A target repo installs whatever it needs itself, the same
# way its own dev-tool bootstrap script already handles anything beyond what CI provides.
#
# trixie (Debian 13) rather than bookworm (Debian 12): newer glibc means more prebuilt-binary tool
# releases install directly instead of falling back to a slow from-source build on a cold
# container. The base image digest below is the control that matters, exactly as it is for the
# runner image.
FROM debian:trixie-slim@sha256:3a39a0592364683e6bab97937b72cad5a8fa6dcbbee90edb3bb48c7f8e94f258

# anthropics/claude-code#9184: the workspace runs `claude-code` as root under Paseo, and
# `--dangerously-skip-permissions` (used for non-interactive provider calls) refuses to start
# in that posture without this opt-in. The container is reachable only over Tailscale, so the
# trust boundary the env var bypasses is already enforced at the network layer.
ENV IS_SANDBOX=1

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential pkg-config git curl ca-certificates gnupg procps \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
      > /etc/apt/sources.list.d/claude-code.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh claude-code \
 && npm install -g opencode-ai@1.18.15 \
 && npm install -g @getpaseo/cli@0.3.1 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 6767
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
