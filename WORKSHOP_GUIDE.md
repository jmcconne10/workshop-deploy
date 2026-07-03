# Hackathon Workshop Environment: Setup, Usage, & Teardown Guide

This guide is split into instructions for the **Workshop Organizer** (infrastructure setup and teardown) and the **Hackathon Participants** (developing and deploying code).

---

## Part 1: Organizer Setup Guide

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

### 4. Retrieve URLs & Admin Credentials
Wait about 1–2 minutes for the setup job to run, then retrieve the hostnames:
```bash
# Retrieve Gitea UI URL
echo "Gitea URL: $(oc get route workshop-poc-gitea -o jsonpath='https://{.spec.host}')"

# Retrieve Dev Environment App URL
echo "Dev Web Site URL: $(oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}')"

# Retrieve Prod Environment App URL
echo "Prod Web Site URL: $(oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}')"
```

* **Gitea Admin Username:** `workshop-admin`
* **Gitea Admin Password:** `WorkshopAdminPassword123!`

Provide the Gitea URL and the corresponding App URLs to the participants.

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

Once the hackathon is finished, you can cleanly delete the entire setup (including dynamically created builds and leftover pods) and prepare for a fresh install by running the automated cleanup script:

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
