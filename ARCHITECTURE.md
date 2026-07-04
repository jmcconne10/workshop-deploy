# Architecture

Technical reference for how the workshop environment is built. For install/usage
instructions see [README.md](README.md) and [WORKSHOP_GUIDE.md](WORKSHOP_GUIDE.md);
for the product goals see [hackathon-workshop-poc.md](hackathon-workshop-poc.md).

## Topology

Everything lives in a single OpenShift project and is installed by one Helm
release (`charts/workshop`):

```
                        ┌─────────────────────────────┐
                        │        Gitea (SQLite)        │
                        │  Deployment + PVC + Route     │
                        │  repo: starter-flask-app      │
                        │  branches: main, dev          │
                        └───────────┬───────────────────┘
                    push "dev"      │      push default branch
                                    │
                  ┌─────────────────┴─────────────────┐
                  ▼                                     ▼
        Gitea webhook (dev)                   Gitea webhook (prod)
                  │                                     │
                  ▼                                     ▼
   BuildConfig <fullname>-dev              BuildConfig <fullname>-prod
   (S2I, ubi8/python-39, git ref dev)      (S2I, ubi8/python-39, git ref main)
                  │                                     │
                  ▼                                     ▼
   ImageStream <fullname>-dev:latest       ImageStream <fullname>-prod:latest
                  │                                     │
                  ▼ (image.openshift.io/triggers)        ▼
   Deployment <fullname>-dev                Deployment <fullname>-prod
                  │                                     │
                  ▼                                     ▼
   Service + Route <fullname>-dev          Service + Route <fullname>-prod
```

`<fullname>` is the Helm release name by default (e.g. `workshop-poc`), via the
`workshop.fullname` helper in [`_helpers.tpl`](charts/workshop/templates/_helpers.tpl).

## Chart layout

```
charts/workshop/
  Chart.yaml
  values.yaml                    # sandbox-sized defaults
  templates/
    _helpers.tpl                 # name/label helpers
    NOTES.txt                    # post-install output (route names, admin creds)
    oc-token-secret.yaml         # Secret holding openshift.token (post-install hook)
    gitea-deployment.yaml        # Gitea container, admin user bootstrap in postStart
    gitea-service.yaml
    gitea-route.yaml
    gitea-pvc.yaml
    gitea-setup-configmap.yaml   # setup.sh script + base64-embedded starter app files
    gitea-setup-job.yaml         # runs setup.sh (post-install hook)
    imagestreams.yaml            # dev + prod ImageStreams
    buildconfigs.yaml            # dev + prod S2I BuildConfigs + webhook secret
    app-dev-deployment.yaml / app-prod-deployment.yaml
    app-dev-service.yaml / app-prod-service.yaml
    app-dev-route.yaml / app-prod-route.yaml
```

## Install-time sequence (Helm hooks)

Three resources are annotated as `helm.sh/hook: post-install`, ordered by
`helm.sh/hook-weight`:

1. **weight `"0"`** — `<fullname>-oc-token` Secret: stores `.Values.openshift.token`
   (passed via `--set openshift.token=...`, never committed to the repo).
2. **weight `"1"`** — `<fullname>-gitea-setup` ConfigMap: contains `setup.sh` and the
   pre-encoded base64 payloads for the starter app's `app.py` / `requirements.txt`.
3. **weight `"2"`** — `<fullname>-gitea-setup` Job: mounts the ConfigMap as a script and
   the token Secret as a volume, then runs `setup.sh` (image: `curlimages/curl`).

All three run after the Gitea Deployment/Service/Route/PVC and the BuildConfigs/
ImageStreams are created by the normal (non-hook) install phase, since Helm installs
hookless resources first, then runs post-install hooks in weight order.

### What `setup.sh` does

1. Polls `http://<fullname>-gitea:3000/api/v1/swagger` until Gitea answers.
2. Creates the `starter-flask-app` repo under the admin account (`auto_init: true`).
3. Reads the repo's actual default branch (`main` or `master` depending on Gitea's
   config) rather than assuming a name.
4. Uploads `app.py` and `requirements.txt` to that default branch via the Gitea
   Contents API (base64 payloads embedded in the ConfigMap to sidestep shell
   quoting/indentation issues).
5. Creates a `dev` branch from the default branch.
6. Registers two Gitea webhooks against the **external OpenShift API server**
   (`.Values.openshift.apiServer`), pointed at each BuildConfig's generic webhook
   endpoint (`.../buildconfigs/<fullname>-dev/webhooks/<webhookSecret>/generic`),
   authenticated with `Authorization: Bearer <oc token>` since the sandbox's RBAC
   rejects the unauthenticated in-cluster path Gitea would normally use.

Because every step is idempotent-ish (`|| echo "... might already exist"`), rerunning
`helm upgrade` or reinstalling is safe — failures to re-create existing objects don't
fail the Job.

## Build → deploy wiring

- Each `Deployment` (`app-dev-deployment.yaml` / `app-prod-deployment.yaml`) carries an
  `image.openshift.io/triggers` annotation pointing at its `ImageStreamTag`. When the
  S2I build pushes a new image into the ImageStream, OpenShift patches the Deployment's
  pod template image directly — no separate `oc rollout` step or polling is needed.
- Containers pull from the in-cluster registry path
  (`image-registry.openshift-image-registry.svc:5000/<namespace>/<fullname>-<env>:latest`)
  rather than a public registry, so no pull secret is required for the app images.
- `BuildConfig` triggers are `type: Generic` (webhook-driven only) — there's no
  `ImageChange` or `ConfigChange` trigger, so builds only happen in response to the
  Gitea webhook hitting the generic endpoint.

## Configuration surface (`values.yaml`)

| Key | Purpose |
|---|---|
| `openshift.apiServer` | External API server URL the Gitea webhook calls into |
| `openshift.token` | OC token for webhook auth; set via `--set`, never committed |
| `gitea.image.*`, `gitea.resources`, `gitea.persistence.*` | Gitea container/image/storage sizing |
| `gitea.admin.*` | Gitea admin username/password/email (also used as the repo owner) |
| `starterApp.dev` / `starterApp.prod` | Replica count + resource requests/limits per environment |
| `build.builderImage` | S2I builder image (UBI8 Python 3.9 by default) |
| `build.successfulBuildsHistoryLimit` / `failedBuildsHistoryLimit` | Build pruning, kept low for sandbox quota |
| `build.repoName` | Gitea repo name created by the setup Job |
| `build.webhookSecret` | Shared secret in the BuildConfig generic webhook path |

`values-enterprise.yaml` (repo root) overrides these for a non-sandbox cluster: Nexus
image repositories + `pullSecrets`, larger resource requests, a real storage class,
and `prod.replicas: 3`. See [ENTERPRISE_DEPLOY.md](ENTERPRISE_DEPLOY.md).

## Naming

All resource names derive from `workshop.fullname` (the release name, or
`<release>-<chart>` if the release name doesn't already contain the chart name — see
`_helpers.tpl`). With the documented `helm install workshop-poc charts/workshop`
this resolves to `workshop-poc`, so e.g. the dev Route is `workshop-poc-dev` and the
Gitea PVC is `workshop-poc-gitea`.

## Known limitations (POC scope)

These are intentional for a single-namespace sandbox POC — see
[FUTURE.md](FUTURE.md) for the enterprise/multi-team roadmap:

- Single replica for Gitea and (by default) for prod; no HA.
- SQLite backing store for Gitea — fine for one small repo, not for concurrent teams.
- Gitea admin password and the BuildConfig webhook secret ship as plaintext defaults
  in `values.yaml`, intended to be overridden per deployment rather than treated as
  real secrets.
- Gitea's `GITEA__webhook__SKIP_TLS_VERIFY: true` disables TLS verification for
  outbound webhook calls — acceptable for the sandbox's self-signed setup, not for a
  production cluster with a trusted CA.
- No `ClusterRole`/`ClusterRoleBindings` or other cluster-scoped resources — the chart
  only creates namespace-scoped objects, matching sandbox RBAC restrictions.
