# paseo

Kubernetes deployment infrastructure for running a [Paseo](https://github.com/halfmatthalfcat/paseo)
(`@getpaseo/cli`) daemon as an always-on, password-protected remote dev workspace — reachable over
Tailscale, with a warm build cache and a checkout of whatever repo you point it at.

This repo builds and publishes two container images:

- **`paseo-workspace`** (`.github/workspace/`) — Node, `gh`, `claude-code`, `opencode-ai`, and the
  Paseo daemon itself. Clones/pulls the repo named by `WORKSPACE_REPO_URL` and runs `paseo start`
  against it. No language toolchain is baked in — the target repo's own setup provisions whatever
  it needs.
- **`paseo-runner`** (`.github/runner/`) — a self-hosted GitHub Actions runner image with a C
  toolchain, for projects that want CI on their own k3s capacity instead of GitHub-hosted runners.

Deploying a pod from these images onto a cluster is covered in [`k8s/README.md`](k8s/README.md).

## Layout

```
k8s/                     — namespace, PVC, pod, service, and secrets template
.github/workspace/       — workspace image Dockerfile + entrypoint.sh
.github/runner/          — self-hosted runner image Dockerfile
.github/workflows/       — builds + publishes both images to ghcr on push to main
```
