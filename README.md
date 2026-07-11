# OpenShift Hackathon Workshop POC

This repository contains the Helm chart and configurations for deploying a self-contained, automated workshop environment on the **Red Hat Developer Sandbox**.

This README covers a single sandbox deployment. For other scenarios, see:
* [WORKSHOP_GUIDE.md](WORKSHOP_GUIDE.md) — organizer setup, the participant development flow, batch/multi-team provisioning, and teardown.
* [ENTERPRISE_DEPLOY.md](ENTERPRISE_DEPLOY.md) — deploying to an internal/enterprise cluster with a private Nexus registry.
* [ARCHITECTURE.md](ARCHITECTURE.md) — a technical breakdown of the chart's resources and the install/build/deploy flow.

## Prerequisites

1. **CLI Tools:** Ensure you have the OpenShift client (`oc`) and `helm` installed.
2. **Cluster Authentication:** Log in to your Red Hat Developer Sandbox namespace:
   ```bash
   oc login --token=<TOKEN> --server=<SERVER_URL>
   ```
   Alternatively, you can load variables from your local `.env` file (which is ignored by Git):
   ```bash
   export $(grep -v '^#' .env | xargs)
   oc login --token=$OPENSHIFT_TOKEN --server=$OPENSHIFT_SERVER
   ```

---

## Deployment

Deploy the entire environment (a UBI-based git server, starter repo, BuildConfigs, and Flask app routes) with a single command.
`openshift.apiServer`/`openshift.token` are required — without them, the git server's
`post-receive` hook (and the one-time initial-build trigger) get an HTTP 403 from the
API server (an empty token is treated as anonymous), so the dev/prod sites never get a build:

```bash
helm install workshop-poc charts/workshop \
  --set openshift.apiServer=$(oc whoami --show-server) \
  --set openshift.token=$(oc whoami -t)
```

### What Happens on Install
The chart builds a small UBI git-server image in-cluster (`git` + `httpd`), then the git server pod:
1. Initializes a **bare git repository** named `starter-flask-app` and seeds it with `app.py` + `requirements.txt`.
2. Creates the `dev` branch (and `member1`..`memberN` if `memberCount >= 2`).
3. Installs a server-side **`post-receive` hook** that triggers the OpenShift S2I BuildConfigs — push to `dev` builds/deploys **dev**, push to `main` builds/deploys **prod**.
4. Once it's serving over its Route, triggers the initial dev/prod builds so both sites come up automatically.

There is no web UI and no database — it's a plain git server. Cloning is anonymous; **pushing requires** the shared `gitServer.admin` credential (default `workshop-admin` / `WorkshopAdminPassword123!`).

---

## Verification & Testing the Flow

### 1. Retrieve Route URLs
Get the git clone URL and the Flask app URLs:
```bash
# Git clone URL (clone is anonymous; push needs the gitServer.admin credential)
oc get route workshop-poc-gitserver -o jsonpath='https://{.spec.host}/git/starter-flask-app.git{"\n"}'

# Get Dev App URL (runs from the dev branch)
oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}{"\n"}'

# Get Prod App URL (runs from the main branch)
oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}{"\n"}'
```

The git server is a plain repository (no web UI). Cloning is anonymous; pushing prompts for the shared `gitServer.admin` credential (default `workshop-admin` / `WorkshopAdminPassword123!`).

---

### 2. Simulate Hackathon Team Development

The repository is **already seeded** by the git server on startup — it contains `app.py`
(a small Flask site) and `requirements.txt`, and already has a `dev` branch. You don't
create these files; you edit what's there and push (git prompts for the shared push credential). To verify the
automated build-and-deploy flow:

1. **Clone the seeded repo locally** (use the git clone URL from step 1):
   ```bash
   git clone <GIT_CLONE_URL>
   cd starter-flask-app
   ```

2. **Verify Dev Deploy:** switch to the existing `dev` branch, make a visible edit, and push:
   ```bash
   git checkout dev
   # edit app.py — e.g. change the hero heading text so the change is easy to spot
   git add app.py
   git commit -m "feat: customize the dev site"
   git push origin dev
   ```
   This push automatically triggers the Dev build. Track it, then refresh the **Dev App URL**:
   ```bash
   oc get builds
   oc logs -f bc/workshop-poc-dev
   ```

3. **Verify Prod Deploy:** merge `dev` into the default branch (`main`) and push:
   ```bash
   git checkout main
   git merge dev
   git push origin main
   ```
   This triggers the Prod build (`oc logs -f bc/workshop-poc-prod`); once it finishes,
   verify the change on the **Prod App URL**.

> Teams with more than one developer should use the per-member-branch workflow instead
> of pushing `dev` directly — see [WORKSHOP_GUIDE.md](WORKSHOP_GUIDE.md) Part 2.

---

## Teardown

The most thorough cleanup is the `reset.sh` script — it runs `helm uninstall` **and**
removes the dynamically created build artifacts (Builds and build pods) that a bare
uninstall leaves behind:

```bash
./reset.sh
```

Or, to only remove the Helm-managed resources (leaving any leftover build artifacts):

```bash
helm uninstall workshop-poc
```
