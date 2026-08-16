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
   - `GITHUB_TOKEN` — a fine-grained PAT scoped to the repo named by `WORKSPACE_REPO_URL`, with
     Contents: Read and write, Pull requests: Read and write.
   - `PASEO_PASSWORD` — choose a password; this is what stands between the workspace and anyone
     else on your tailnet.

   Apply it:

   ```sh
   kubectl apply -f k8s/paseo-secrets.yaml
   ```

4. Start the pod and the service:

   ```sh
   kubectl apply -f k8s/paseo-pod.yaml
   kubectl apply -f k8s/paseo-service.yaml
   kubectl -n paseo wait --for=condition=Ready pod/paseo --timeout=300s
   ```

## Day to day

Direct terminal access:

```sh
kubectl -n paseo exec -it paseo -- opencode
```

Pairing a Paseo client (mobile app, desktop app, or the `paseo` CLI itself): join the tailnet your
cluster belongs to, then add the workspace with your cluster's host and port `30767`. When the
client asks whether to enable the hosted relay, **decline it** — enter the address manually instead,
over Tailscale. Provide `PASEO_PASSWORD` from `k8s/paseo-secrets.yaml` when prompted.

Tear down a session without losing the cache:

```sh
kubectl -n paseo delete pod paseo
```

The PVC survives, so the next `kubectl apply -f k8s/paseo-pod.yaml` starts from a warm cache and a
`git pull` instead of a cold clone and a full rebuild.

Pick up a freshly published image (after `.github/workflows/workspace-image.yml` runs):

```sh
kubectl -n paseo delete pod paseo
kubectl apply -f k8s/paseo-pod.yaml
```

## Before trusting a new deployment: what to check, not assume

- **Whether `PASEO_PASSWORD` alone is enough to skip the interactive relay/QR prompt** in a
  container with no TTY. If the pod's logs (`kubectl -n paseo logs paseo`) show the daemon waiting
  on a prompt instead of listening, check `paseo --help` and `paseo.sh/docs` for a non-interactive
  flag or additional env var.
- **Whether the daemon binds `0.0.0.0` by default.** If a second tailnet device cannot reach the
  cluster host on port `30767` at all (not even a TCP-level connection — check with
  `nc -zv <cluster-host> 30767` from that device) once the pod is `Ready`, this is the first thing
  to check; it may need an explicit `--hostname 0.0.0.0`-equivalent flag on `paseo`.
- **Whether wrong credentials are actually rejected.** Pair a client with a deliberately wrong
  password first and confirm it is refused, *then* pair with the real `PASEO_PASSWORD` and confirm
  it succeeds. Confirming only the correct path works shows *a* path works, not that a wrong one is
  blocked.
