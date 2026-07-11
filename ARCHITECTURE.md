# Architecture

Technical reference for how the workshop environment is built. For install/usage
instructions see [README.md](README.md) and [WORKSHOP_GUIDE.md](WORKSHOP_GUIDE.md);
for the product goals see [hackathon-workshop-poc.md](hackathon-workshop-poc.md).

## Topology

Everything lives in a single OpenShift project and is installed by one Helm
release (`charts/workshop`). The git backend is a **bare git server on Red Hat UBI**
(`git` + `httpd` serving smart HTTP via `git-http-backend`) — no web UI and no
database; the repositories are just files on a PVC:

```
                     ┌──────────────────────────────────────┐
                     │   Git server (UBI: git + httpd)       │
                     │   Deployment + PVC + Route            │
                     │   bare repo: starter-flask-app        │
                     │   branches: main, dev (+ member1..N)  │
                     └──────────────────┬────────────────────┘
              git push "dev"            │            git push "main"
                        (server-side post-receive hook)
                  ┌─────────────────────┴─────────────────┐
                  ▼                                         ▼
        generic webhook (dev)                   generic webhook (prod)
                  │                                         │
                  ▼                                         ▼
   BuildConfig <fullname>-dev              BuildConfig <fullname>-prod
   (S2I, ubi8/python-39, git ref dev)      (S2I, ubi8/python-39, git ref main)
                  │                                         │
                  ▼                                         ▼
   ImageStream <fullname>-dev:latest       ImageStream <fullname>-prod:latest
                  │                                         │
                  ▼ (image.openshift.io/triggers)          ▼
   Deployment <fullname>-dev                Deployment <fullname>-prod
                  │                                         │
                  ▼                                         ▼
   Service + Route <fullname>-dev          Service + Route <fullname>-prod
```

`<fullname>` is the Helm release name by default (e.g. `workshop-poc`), via the
`workshop.fullname` helper in [`_helpers.tpl`](charts/workshop/templates/_helpers.tpl).

## Chart layout

```
charts/workshop/
  Chart.yaml
  values.yaml                        # sandbox-sized defaults
  files/
    starter-app/
      app.py                          # starter Flask website source (edit this directly)
      requirements.txt
    gitserver/
      Containerfile                   # UBI9 + git-core + httpd image build recipe
      start.sh                        # git server entrypoint (init/seed/hook/httpd)
  templates/
    _helpers.tpl                     # name/label helpers
    NOTES.txt                        # post-install output (git clone URL, app routes)
    oc-token-secret.yaml             # Secret holding openshift.token (normal resource)
    gitserver-buildconfig.yaml       # Docker build of the UBI git image from Containerfile
    gitserver-imagestream.yaml       # holds the built git-server image
    gitserver-deployment.yaml        # runs start.sh; mounts repo PVC + token + starter files
    gitserver-service.yaml           # :8080
    gitserver-route.yaml             # edge-TLS external clone/push
    gitserver-pvc.yaml               # bare repo storage
    gitserver-startup-configmap.yaml # carries start.sh
    gitserver-starter-configmap.yaml # carries the starter app.py/requirements.txt
    imagestreams.yaml                # dev + prod app ImageStreams
    buildconfigs.yaml                # dev + prod S2I BuildConfigs + webhook secret
    app-dev-deployment.yaml / app-prod-deployment.yaml
    app-dev-service.yaml / app-prod-service.yaml
    app-dev-route.yaml / app-prod-route.yaml
```

## Install-time sequence

Unlike the old Gitea backend, there are **no Helm hooks** — everything is created in
the normal install phase:

1. The `<fullname>-gitserver` **BuildConfig** (Docker strategy) builds the UBI git
   image from `files/gitserver/Containerfile` into the `<fullname>-gitserver`
   ImageStream. It has a `ConfigChange` trigger, so it builds on install.
2. The `<fullname>-gitserver` **Deployment** runs the built image; an
   `image.openshift.io/triggers` annotation rolls it once the image lands. It mounts the
   repo **PVC**, the `<fullname>-oc-token` **Secret** (as the `OC_TOKEN` env var), and the
   starter-files **ConfigMap**, then runs `start.sh`.
3. The dev/prod app **BuildConfigs**, **ImageStreams**, **Deployments**, **Services**,
   and **Routes** are created too, and wait for their images (which `start.sh` triggers).

The `<fullname>-oc-token` Secret is now a **normal resource** (not a hook), because the
git server Deployment needs the token available at deploy time.

### What `start.sh` does

Runs as the git server's entrypoint (`files/gitserver/start.sh`, mounted from a
ConfigMap). All values come from environment variables set by the Deployment, so the
script needs no Helm templating:

1. Configures and starts **`httpd`** (`git-http-backend` CGI on port 8080) in the
   background, so a build can clone the repo the moment it is triggered.
2. Initializes the **bare repo** `/var/git/<repoName>.git` on the PVC, with
   `http.receivepack`/`http.uploadpack` enabled and `HEAD` set to `main`.
3. **Seeds** `app.py` and `requirements.txt` (from the mounted starter ConfigMap) onto
   `main`, then creates `dev`. If `.Values.memberCount >= 2`, also creates `member1`..
   `memberN` off `dev` — this is done **before** the hook is installed, so these seed
   pushes do **not** fire any webhook.
4. Installs the server-side **`post-receive` hook** with the OC token and the dev/prod
   generic-webhook URLs baked in (Apache does not pass env to CGI children, so the values
   are written into the hook file). The hook routes: push to `dev` → dev BuildConfig
   webhook, push to `main` → prod webhook, any other branch (e.g. `memberN`) → no build.
5. Waits until the repo is reachable over the **Service** (HTTP 200 on
   `info/refs?service=git-upload-pack`), i.e. this pod is Ready and has a Service
   endpoint, then **triggers the initial dev and prod builds** by calling the same
   webhooks directly. Gating on Service reachability avoids a race where a build clones
   before the server is serving.
6. Leaves `httpd` running (`wait`).

Re-running is safe: the repo-init/seed block is guarded by `if [ ! -d <repo> ]`, so a
pod restart with a retained PVC skips straight to serving.

## Build → deploy wiring

- Each `Deployment` (`app-dev-deployment.yaml` / `app-prod-deployment.yaml`) carries an
  `image.openshift.io/triggers` annotation pointing at its `ImageStreamTag`. When the
  S2I build pushes a new image into the ImageStream, OpenShift patches the Deployment's
  pod template image directly — no separate `oc rollout` step or polling is needed.
- Containers pull from the in-cluster registry path
  (`image-registry.openshift-image-registry.svc:5000/<namespace>/<fullname>-<env>:latest`)
  rather than a public registry, so no pull secret is required for the app images.
- `BuildConfig` triggers are `type: Generic` (webhook-driven only) — there's no
  `ImageChange` or `ConfigChange` trigger. A build fires either from a participant's
  `git push` (via the `post-receive` hook) or from `start.sh`'s one-time gated call that
  covers the very first build.

## Configuration surface (`values.yaml`)

| Key | Purpose |
|---|---|
| `openshift.apiServer` | External API server URL the `post-receive` hook calls into |
| `openshift.token` | OC token for the build-trigger auth; set via `--set`, never committed |
| `gitServer.service.*`, `gitServer.resources`, `gitServer.persistence.*` | Git server service/sizing/storage |
| `gitServer.build.enabled` | Build the git image in-cluster (default `true`); set `false` to run a pre-built image |
| `gitServer.image.*` | Pre-built git server image (repo/tag/pullSecrets), used when `build.enabled: false` |
| `gitServer.admin.*` | Shared push credential enforced via htpasswd basic-auth on `git-receive-pack` (clone stays anonymous) |
| `starterApp.dev` / `starterApp.prod` | Replica count + resource requests/limits per environment |
| `memberCount` | Team size; if `>= 2`, `start.sh` pre-creates `member1`..`memberN` branches off `dev` (default `1` = solo, none created) |
| `build.builderImage` | S2I builder image (UBI8 Python 3.9 by default) |
| `build.successfulBuildsHistoryLimit` / `failedBuildsHistoryLimit` | Build pruning, kept low for sandbox quota |
| `build.repoName` | Name of the bare repo the git server serves |
| `build.webhookSecret` | Shared secret in the BuildConfig generic webhook path |

`values-enterprise.yaml` (repo root) overrides these for a non-sandbox cluster: Nexus
image repositories + `pullSecrets`, larger resource requests, a real storage class,
and `prod.replicas: 3`. See [ENTERPRISE_DEPLOY.md](ENTERPRISE_DEPLOY.md).

## Naming

All resource names derive from `workshop.fullname` (the release name, or
`<release>-<chart>` if the release name doesn't already contain the chart name — see
`_helpers.tpl`). With the documented `helm install workshop-poc charts/workshop`
this resolves to `workshop-poc`, so e.g. the dev Route is `workshop-poc-dev` and the
git server PVC is `workshop-poc-gitserver`.

## Known limitations (POC scope)

These are intentional for a single-namespace sandbox POC — see
[FUTURE.md](FUTURE.md) for the enterprise/multi-team roadmap:

- **No web UI.** The git server is a plain repository served over HTTP; participants
  work entirely from the command line (clone / commit / push). There is no code-browsing
  or repo-management UI.
- **Anonymous clone, authenticated push.** Cloning/fetching is anonymous (so the S2I
  BuildConfigs can clone the repo without credentials); pushing (`git-receive-pack`)
  requires the shared `gitServer.admin` credential, enforced by Apache basic-auth against
  an htpasswd Secret. Auth is a **shared** account, not per-user — per-user identity is
  future work (see [FUTURE.md](FUTURE.md)).
- **Single replica** for the git server and (by default) for prod; no HA. No database —
  repos are plain files on a `ReadWriteOnce` PVC.
- **The git image is built in-cluster** by default from `Containerfile`, which needs
  egress to Red Hat package repos at build time. Air-gapped clusters can set
  `gitServer.build.enabled: false` and supply a pre-built `gitServer.image` instead (see
  [ENTERPRISE_DEPLOY.md](ENTERPRISE_DEPLOY.md)).
- The BuildConfig webhook secret ships as a plaintext default in `values.yaml`, intended
  to be overridden per deployment rather than treated as a real secret.
- The `post-receive` hook calls the external API server with `curl -k` (TLS verification
  skipped) — acceptable for the sandbox's self-signed setup, not for a production cluster
  with a trusted CA.
- No `ClusterRole`/`ClusterRoleBindings` or other cluster-scoped resources — the chart
  only creates namespace-scoped objects, matching sandbox RBAC restrictions.
