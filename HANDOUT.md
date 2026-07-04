# Hackathon Attendee Quick-Start Guide

Welcome to the Hackathon, sponsored by the EKHO Team! Below are your connection details, repository URL, and live environment websites.

---

## 1. Environment URLs

* **Gitea Code Repository Web UI:** [https://workshop-poc-gitea-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com](https://workshop-poc-gitea-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com)
* **Your Dev Web Site:** [https://workshop-poc-dev-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com](https://workshop-poc-dev-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com)
* **Your Prod Web Site:** [https://workshop-poc-prod-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com](https://workshop-poc-prod-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com)

### Gitea Login Credentials
* **Username:** `workshop-admin`
* **Password:** `WorkshopAdminPassword123!`

---

## 2. Working with Your Code

The deployment platform automatically builds and deploys your code. You do not need to touch OpenShift.

### Step 1: Clone the Repository
Clone your project's starter code from Gitea:
```bash
git clone https://workshop-poc-gitea-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com/workshop-admin/starter-flask-app.git
cd starter-flask-app
```
*(When prompted, enter the username `workshop-admin` and password `WorkshopAdminPassword123!`)*

### Step 2: Make Edits & Deploy to Dev
If this is your first time using git on this machine, set your identity once:
```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

To test changes, work on the `dev` branch:
```bash
# Switch to dev branch
git checkout dev

# Make changes to app.py (e.g., edit the hero heading text or the
# "Trigger Action" button label inside HTML_TEMPLATE)

# Commit and push
git add app.py
git commit -m "feat: customize the starter site"
git push origin dev
```
*(You'll be prompted for your Gitea username/password again for this push — same credentials as the clone step.)*

*Once pushed, OpenShift will automatically build and update your **Dev Web Site** in ~1-2 minutes.*

### Step 3: Release to Production
When your app is ready for production, merge to `main` and push:
```bash
# Switch to main and merge dev
git checkout main
git merge dev

# Push main
git push origin main
```
*This will trigger a production build and update your **Prod Web Site** automatically.*
