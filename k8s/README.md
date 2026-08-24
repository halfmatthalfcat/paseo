# Deploying a Paseo workspace

A password-protected Paseo daemon running inside a k3s cluster, reachable only over Tailscale,
managing an `opencode`/`claude-code` session against a target repo of your choice.

## In plain words

These commands turn on one small, always-on box that has a repo checked out and a warm build
cache, and that a phone, desktop, or terminal can reach — over the private network you already use
to reach your cluster, nowhere else, and never through Paseo's own hosted relay — to drive that
session without being at a terminal.

## Bootstrap (once)

1. Point `kubectl` at your cluster.

2. Create the namespace, the PVC, and the image-pull secret:

   ```sh
   kubectl apply -f k8s/namespace.yaml
   kubectl apply -f k8s/workspace-pvc.yaml
   kubectl -n paseo create secret docker-registry ghcr-pull \
     --docker-server=ghcr.io \
     --docker-username=<your-github-username> \
     --docker-password=<a GitHub PAT with read:packages scope> \
     --docker-email=<your-email>
   ```

3. Fill in the real secret values — never commit the result:

   ```sh
   cp k8s/paseo-secrets.example.yaml k8s/paseo-secrets.yaml
   ```

   Edit `k8s/paseo-secrets.yaml`:
   - `WORKSPACE_REPO_URL` — the repo this workspace checks out and serves, e.g.
     `https://github.com/<org>/<repo>.git`.
   - `OPENROUTER_API_KEY` — from the OpenRouter dashboard, if the target repo's agent config uses it.
   - `OPENCODE_API_KEY` — from [opencode.ai/auth](https://opencode.ai/auth); enables OpenCode language
     model access. Optional if your agent config routes through OpenRouter.
   - `GITHUB_TOKEN` — a fine-grained PAT scoped to the repo named by `WORKSPACE_REPO_URL`, with
     Contents: Read and write, Pull requests: Read and write.
   - `HEVY_API_KEY` — from [Hevy](https://www.hevy.com/), required for Hevy PRO. Feeds the `hevy`
     MCP server baked into the workspace image. Optional if you don't use Hevy.
   - `RENPHO_EMAIL` / `RENPHO_PASSWORD` — your [Renpho Health](https://renpho.com) app credentials
     (the blue-icon app, not the legacy Renpho app). Feeds the `renpho` MCP server. Optional if you
     don't use a Renpho scale.
   - `PASEO_PASSWORD` — choose a password; this is what stands between the workspace and anyone
     else on your tailnet.

   Apply it:

   ```sh
   kubectl apply -f k8s/paseo-secrets.yaml
   ```

4. Start the deployment and the service:

   ```sh
   kubectl apply -f k8s/paseo-deployment.yaml
   kubectl apply -f k8s/paseo-service.yaml
   kubectl -n paseo rollout status deployment/paseo --timeout=300s
   ```

## Migrating from a bare `paseo` pod

If an earlier bare `paseo` Pod (the pre-Deployment manifest) is running, delete it before applying
`k8s/paseo-deployment.yaml`. The Service selects on `app: paseo`, so a bare pod and the
Deployment's pods would both match and split traffic:

```sh
kubectl -n paseo delete pod paseo
```

The PVC is shared, so this is a swap, not a rebuild. Secrets carry over unchanged — the Deployment
reads the same `paseo-secrets` Secret the pod did.

## Day to day

Direct terminal access:

```sh
kubectl -n paseo exec -it deploy/paseo -- opencode
```

Pairing a Paseo client (mobile app, desktop app, or the `paseo` CLI itself): join the tailnet your
cluster belongs to, then add the workspace with your cluster's host and port `30767`. When the
client asks whether to enable the hosted relay, **decline it** — enter the address manually instead,
over Tailscale. Provide `PASEO_PASSWORD` from `k8s/paseo-secrets.yaml` when prompted.

The deployment runs a `docker:28-dind` sidecar (`k8s/paseo-deployment.yaml`), so `docker` works
from inside the `paseo` container's shell (`DOCKER_HOST` already points at it). The sidecar is
`privileged: true` — required for a Docker daemon to run at all — but it's scoped to its own
container in the pod, not the `paseo` container itself. Its `/var/lib/docker` is an `emptyDir`, not
the PVC, so any images/containers built there are lost on pod restart; only `/workspace` persists.

### Restart on failure

Two layers restart the workspace, and they cover different failures:

- **Container crash:** `restartPolicy: Always` makes the kubelet restart the crashed container in
  place. This was already true of the old bare Pod.
- **Pod gone:** if the pod is deleted, evicted, or the node restarts, the Deployment recreates it.
  A bare Pod had no controller, so a deleted pod stayed gone. This is the gap the Deployment closes.

Tear down a session without losing the cache:

```sh
kubectl -n paseo scale deployment/paseo --replicas=0
```

The PVC survives, so scaling back up starts from a warm cache and a `git pull` instead of a cold
clone and a full rebuild:

```sh
kubectl -n paseo scale deployment/paseo --replicas=1
```

Pick up a freshly published image (after `.github/workflows/workspace-image.yml` runs). The image
tag is `latest`, so the rollout pulls the new image:

```sh
kubectl -n paseo rollout restart deployment/paseo
```

## MCP servers in the workspace

The workspace image bakes in a global OpenCode config (`OPENCODE_CONFIG`) that registers three local
MCP servers, so any repo the workspace serves can use them:

- **`hevy`** — [hevy-mcp](https://github.com/chrisdoc/hevy-mcp) exposes the Hevy workout API
  (read, analyze, create, and update workouts, routines, exercises, and measurements). Needs the
  `HEVY_API_KEY` secret; a Hevy PRO subscription is required.
- **`monarch`** — [monarch-mcp-server](https://github.com/robcerda/monarch-mcp-server) exposes the
  Monarch Money personal-finance API (accounts, transactions, budgets, analytics).
- **`renpho`** — [renpho-mcp-server](https://github.com/StartupBros-com/renpho-mcp-server) exposes
  body-composition data from Renpho smart scales (weight, BMI, body fat %, muscle mass, trends).
  Needs the `RENPHO_EMAIL`/`RENPHO_PASSWORD` secrets; works with the **Renpho Health** app
  (blue icon).

These register via a baked-in `/usr/local/etc/opencode/opencode.json`; a repo's own
`.opencode/opencode.json` overrides them for that repo.

### Authenticating with Monarch

Monarch has no API key. Auth is interactive, done once from inside a session, and the logged-in
session **survives pod restarts** because its token file lives under `$HOME` (on the PVC):

1. From a client with the workspace paired, ask `opencode` to use the `monarch` MCP server's own
   tool:
   - `check_auth_status` — see whether a session already exists.
   - `monarch_login` — opens a secure form in the client UI to collect email/password (plus MFA or
     an email OTP if Monarch asks). Credentials never pass through the model — they flow
     client UI → server directly over MCP.
   - `monarch_login_with_token` — for SSO accounts that can't use password login: paste a session
     token copied from browser DevTools → Application → Local Storage → `app.monarchmoney.com`.
   - `monarch_logout` — clear the stored session.

2. On the first call, Monarch may email a verification code (new device/session) or prompt for a
   two-factor code — same flow as a normal login.

3. Afterwards, the tools that read data (`get_accounts`, `get_transactions`, …) work without
   re-authenticating. To re-authenticate later, just call `monarch_login` again.

The MCP-tool flow is the intended path for a headless container. The same login also works from the
`paseo` container's shell via `login_setup.py` in a clone of the monarch-mcp-server repo, but its
terminal prompts make the MCP flow the more convenient one here.

## Before trusting a new deployment: what to check, not assume

- **Whether `PASEO_PASSWORD` alone is enough to skip the interactive relay/QR prompt** in a
  container with no TTY. If the deployment's logs (`kubectl -n paseo logs deploy/paseo`) show the
  daemon waiting on a prompt instead of listening, check `paseo --help` and `paseo.sh/docs` for a
  non-interactive flag or additional env var.
- **Whether the daemon binds `0.0.0.0` by default.** If a second tailnet device cannot reach the
  cluster host on port `30767` at all (not even a TCP-level connection — check with
  `nc -zv <cluster-host> 30767` from that device) once the deployment is `Ready`, this is the first
  thing to check; it may need an explicit `--hostname 0.0.0.0`-equivalent flag on `paseo`.
- **Whether wrong credentials are actually rejected.** Pair a client with a deliberately wrong
  password first and confirm it is refused, *then* pair with the real `PASEO_PASSWORD` and confirm
  it succeeds. Confirming only the correct path works shows *a* path works, not that a wrong one is
  blocked.
- **Whether the MCP servers come up.** With a freshly rolled-out deployment, run `opencode` and
  check `opencode mcp list` — `hevy`, `monarch`, and `renpho` should appear. If a server errors, its
  logs show in the opencode logs; a common cause is a missing secret (e.g. `HEVY_API_KEY` unset, or
  `RENPHO_EMAIL`/`RENPHO_PASSWORD` wrong).
