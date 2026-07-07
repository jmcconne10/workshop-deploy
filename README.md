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

Deploy the entire environment (Gitea, starter repo, BuildConfigs, and Flask app routes) with a single command.
`openshift.apiServer`/`openshift.token` are required — without them, Gitea's webhook and
the chart's automatic initial-build trigger both get an HTTP 403 from the API server
(an empty token is treated as anonymous), so the dev/prod sites never get a build:

```bash
helm install workshop-poc charts/workshop \
  --set openshift.apiServer=$(oc whoami --show-server) \
  --set openshift.token=$(oc whoami -t)
```

### Post-Install Automation
The Helm chart includes a post-install hook Job that:
1. Waits for Gitea to start.
2. Creates a public repository named `starter-flask-app` under the `workshop-admin` account.
3. Automatically sets up the `dev` branch.
4. Configures Gitea webhooks to trigger the respective OpenShift S2I BuildConfigs for `dev` (pushed to `dev`) and `prod` (pushed to the default branch).
5. Fires each BuildConfig's webhook trigger once directly, so the initial `dev`/`prod` images build automatically — the app.py/requirements.txt seeded above went in via Gitea's API rather than a real push, so there'd otherwise be no first build for the webhooks to react to.

---

## Verification & Testing the Flow

### 1. Retrieve Route URLs & Credentials
Get Gitea and Flask app URLs:
```bash
# Get Gitea Console URL
oc get route workshop-poc-gitea -o jsonpath='https://{.spec.host}{"\n"}'

# Get Dev App URL (runs from the dev branch)
oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}{"\n"}'

# Get Prod App URL (runs from the main branch)
oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}{"\n"}'
```

**Gitea Credentials:**
- **Username:** `workshop-admin`
- **Password:** `WorkshopAdminPassword123!`

---

### 2. Simulate Hackathon Team Development

The repository is **already seeded** by the post-install Job — it contains `app.py`
(a small Flask site) and `requirements.txt`, and already has a `dev` branch. You don't
create these files; you edit what's there and push. To verify the automated
build-and-deploy flow:

1. **Clone the seeded repo locally:**
   ```bash
   git clone <GITEA_CONSOLE_URL>/workshop-admin/starter-flask-app.git
   cd starter-flask-app
   ```
   *(Enter Gitea credentials when prompted)*

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
removes the dynamically created build artifacts (Builds, build pods, and the setup Job)
that a bare uninstall leaves behind:

```bash
./reset.sh
```

Or, to only remove the Helm-managed resources (leaving any leftover build artifacts):

```bash
helm uninstall workshop-poc
```
