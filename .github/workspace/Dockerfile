# Paseo workspace image: Node + opencode-ai + gh + claude-code + docker CLI, checked out against a
# target repo and served over HTTP by k8s/paseo-deployment.yaml. Built + published by
# .github/workflows/workspace-image.yml.
#
# No language toolchain is baked in on purpose: this image is reused across projects with
# different languages and version pins. A target repo installs whatever it needs itself, the same
# way its own dev-tool bootstrap script already handles anything beyond what CI provides.
#
# Only the docker CLI ships here, not the daemon: k8s/paseo-deployment.yaml runs a docker:dind
# sidecar in the same pod and points DOCKER_HOST at it, so this container talks to that daemon
# instead of needing to run privileged itself. Python is the one toolchain exception, and only to
# host the monarch MCP server (a Python package); it lives in a venv and the server's interactive
# login writes its session to $HOME, i.e. the PVC. The renpho MCP server is a TypeScript package
# published only from source (not on npm), so it's cloned, built, and globally installed here.
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
      build-essential pkg-config git curl ca-certificates gnupg procps python3 python3-venv \
 && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
 && apt-get install -y --no-install-recommends nodejs \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main" \
      > /etc/apt/sources.list.d/claude-code.list \
 && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian trixie stable" \
      > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh claude-code docker-ce-cli \
 && npm install -g opencode-ai@1.18.15 \
 && npm install -g @getpaseo/cli@0.3.1 \
 && npm install -g hevy-mcp@6.1.5 \
 && git clone -q --depth 1 https://github.com/StartupBros-com/renpho-mcp-server.git /opt/renpho-mcp-server \
 && cd /opt/renpho-mcp-server \
 && git checkout -q f1182346cf332c96dca1cbe6462382638318d0d9 \
 && npm install --no-audit --no-fund --loglevel=error \
 && npm run build --loglevel=error \
 && npm install -g /opt/renpho-mcp-server --loglevel=error \
 && cd / \
 && python3 -m venv /opt/monarch-mcp-server \
 && /opt/monarch-mcp-server/bin/pip install --no-cache-dir \
      "monarch-mcp-server @ git+https://github.com/robcerda/monarch-mcp-server.git@ca6c1598c99a0ff1f7b7effbb2c9f518224eab44" \
      "mcp[cli]>=1.10.0,<2" \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Global opencode config registering the hevy, monarch, and renpho MCP servers. Wired in via the
# OPENCODE_CONFIG env var in k8s/paseo-deployment.yaml; a repo's own .opencode/opencode.json
# overrides it for that repo.
COPY opencode-global-config.json /usr/local/etc/opencode/opencode.json

EXPOSE 6767
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
