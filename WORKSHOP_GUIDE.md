# Hackathon Workshop Environment: Setup, Usage, & Teardown Guide

This guide is split into instructions for the **Workshop Organizer** (infrastructure setup and teardown) and the **Hackathon Participants** (developing and deploying code).

## Which setup do I need?

There are two ways to stand this up, depending on what you're running:

* **A single deployment** — one Gitea + dev + prod stack, e.g. for testing the chart
  or a one-person session. Follow **Part 1: Organizer Setup Guide (Single Deployment)**
  below.
* **A real multi-team workshop** (up to ~20 teams) — one fully isolated stack per
  team, provisioned in one batch, with a handout generated per team and a master
  roster of every team's URLs and credentials. Skip ahead to
  **Part 1B: Organizer Setup Guide (Batch / Multi-Team Workshops)**.

---

## Part 1: Organizer Setup Guide (Single Deployment)

### 1. Prerequisites
Before deploying, make sure you have:
* The OpenShift CLI (`oc`) and Helm CLI (`helm`) installed.
* Access to a Red Hat OpenShift namespace (such as the Developer Sandbox).

### 2. Login to OpenShift
Log in to the cluster using your token and server URL (retrieve this from the OpenShift Web Console):
```bash
oc login --token=<YOUR_TOKEN> --server=<YOUR_SERVER_URL>
```

### 3. Deploy the Environment
Deploy the Gitea server, starter repository, BuildConfigs, and routing templates using Helm:
```bash
helm install workshop-poc charts/workshop
```

### 4. Retrieve URLs & Generate the Attendee Handout
Wait about 1–2 minutes for the setup job to run, then run the handout generator —
it queries the three routes for you and writes a ready-to-share `HANDOUT.md`:
```bash
./generate-handout.sh
```
* **Gitea Admin Username:** `workshop-admin`
* **Gitea Admin Password:** `WorkshopAdminPassword123!`

Share the generated `HANDOUT.md` with the participant.

<details>
<summary>Just need the URLs yourself, without generating a handout?</summary>

```bash
# Retrieve Gitea UI URL
echo "Gitea URL: $(oc get route workshop-poc-gitea -o jsonpath='https://{.spec.host}')"

# Retrieve Dev Environment App URL
echo "Dev Web Site URL: $(oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}')"

# Retrieve Prod Environment App URL
echo "Prod Web Site URL: $(oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}')"
```
</details>

---

## Part 1B: Organizer Setup Guide (Batch / Multi-Team Workshops)

Use this instead of Part 1 when you're running a real workshop with multiple teams
(up to ~20). It uses `orchestrate/provision_workshop.py` to create one isolated
namespace and one full stack per team, then generates a per-team handout plus a master
roster of every team's URLs and credentials — no need to repeat Part 1 by hand for
each team.

**This targets a real enterprise OpenShift cluster, not the Developer Sandbox** — a
sandbox account only gets one namespace and its quotas aren't sized for 20 concurrent
stacks. See [ENTERPRISE_DEPLOY.md](ENTERPRISE_DEPLOY.md) for cluster prerequisites
(registry secrets, storage class, etc.) before running this at scale.

1. **Create a virtual environment and install the script's dependency:**
   ```bash
   python3 -m venv orchestrate/.venv
   source orchestrate/.venv/bin/activate
   pip install -r orchestrate/requirements.txt
   ```
   `orchestrate/.venv/` is gitignored. Re-run the `source` line (only) to reactivate
   it in a new shell — no need to recreate it or reinstall dependencies each time.
2. **Copy the example roster and fill in your event's details** (this file is
   gitignored — never commit real cluster/participant details):
   ```bash
   cp orchestrate/teams.example.yaml orchestrate/teams.local.yaml
   ```
   Edit `cluster.apiServer`, `cluster.valuesFile`, `cluster.namespacePrefix`, and the
   `teams` list (one `id` + `displayName` per team).
3. **Log in to the target cluster and set the webhook auth token** (same token model
   as the single-deployment flow — see Prerequisites above):
   ```bash
   oc login --token=<YOUR_TOKEN> --server=<YOUR_ENTERPRISE_SERVER>
   export OC_TOKEN=<YOUR_TOKEN>
   ```
4. **Dry-run first** to sanity-check the commands it would run, with no cluster changes:
   ```bash
   python orchestrate/provision_workshop.py orchestrate/teams.local.yaml --dry-run
   ```
5. **Smoke-test with 2–3 teams** before committing to the full roster — trim the
   `teams` list temporarily, or keep a separate small test file. Confirm each team's
   namespace, routes, and handout look right.
6. **Run for real** once satisfied:
   ```bash
   python orchestrate/provision_workshop.py orchestrate/teams.local.yaml
   ```
   Per-team handouts land in `orchestrate/output/teams.local/handouts/`, and the
   master roster (all teams' URLs + credentials) in
   `orchestrate/output/teams.local/roster.md` / `roster.csv`. These are gitignored —
   treat them as sensitive files for the duration of the event.
7. **Tear everything down** after the workshop:
   ```bash
   python orchestrate/provision_workshop.py orchestrate/teams.local.yaml --teardown
   ```

**Before running the full batch:** multiply `values-enterprise.yaml`'s per-team
resource requests by your team count and check against the target cluster's actual
available capacity — this is real infrastructure, not free sandbox quota.

---

## Part 2: Participant Development Guide

As a hackathon participant, you will push your application code to Gitea. The platform will automatically compile it, build a container image, and deploy it to OpenShift. **You never have to touch OpenShift directly.**

### 1. Clone the Starter Code
Clone the repository initialized for you in Gitea:
```bash
git clone <GITEA_URL>/workshop-admin/starter-flask-app.git
cd starter-flask-app
```
*Note: Enter the username `workshop-admin` and password `WorkshopAdminPassword123!` (or the credentials provided by the organizer) when prompted.*

### 2. View the Starter Code
The repository is pre-populated with:
* `app.py`: A simple Flask web application.
* `requirements.txt`: Python package dependencies.

### 3. Develop & Deploy to Dev
Checkout to the `dev` branch, modify the code, and push:
```bash
# Ensure you are on the dev branch
git checkout dev

# Make your edits to app.py (e.g., change the return message)
# Commit and push your changes
git add app.py
git commit -m "feat: customize web page message"
git push origin dev
```

**What happens next:**
* OpenShift automatically detects the push and starts building a new version of your application.
* Once the build completes, the **Dev Web Site URL** automatically updates with your new changes.

### 4. Release to Production
When your app is fully tested and ready for production, merge the code to `main` and push:
```bash
# Checkout main and merge dev
git checkout main
git merge dev

# Push main to Gitea
git push origin main
```

**What happens next:**
* OpenShift detects the push to `main` and triggers the Production build.
* Once completed, your live application is updated on the **Prod Web Site URL**.

---

## Part 3: Organizer Cleanup Guide

**Ran a multi-team batch (Part 1B)?** Don't use the steps below — tear down every
team's namespace and release with the batch script's teardown mode instead (Part 1B,
step 7):
```bash
python orchestrate/provision_workshop.py orchestrate/teams.local.yaml --teardown
```

The rest of this section is for a single deployment (Part 1). Once the hackathon is finished, you can cleanly delete the entire setup (including dynamically created builds and leftover pods) and prepare for a fresh install by running the automated cleanup script:

```bash
./reset.sh
```

Alternatively, you can clean up resources manually:

```bash
# Uninstall the Helm release
helm uninstall workshop-poc

# Clean up leftover build resources
oc delete builds -l app.kubernetes.io/name=workshop
oc delete pods -l openshift.io/build.name
```
