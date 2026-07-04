#!/bin/bash
# Helper script to dynamically query OpenShift routes and generate a formatted HANDOUT.md for workshop attendees.

set -e

echo "=== Generating Attendee Handout ==="

# 1. Fetch hostnames from OpenShift routes
GITEA_HOST=$(oc get route workshop-poc-gitea -o jsonpath='{.spec.host}')
DEV_HOST=$(oc get route workshop-poc-dev -o jsonpath='{.spec.host}')
PROD_HOST=$(oc get route workshop-poc-prod -o jsonpath='{.spec.host}')

# 2. Define URLs
GITEA_URL="https://${GITEA_HOST}"
DEV_URL="https://${DEV_HOST}"
PROD_URL="https://${PROD_HOST}"
CLONE_URL="https://${GITEA_HOST}/workshop-admin/starter-flask-app.git"

# 3. Write HANDOUT.md
cat << EOF > HANDOUT.md
# Hackathon Attendee Quick-Start Guide

Welcome to the OpenShift Hackathon! Below are your connection details, repository URL, and live environment websites.

---

## 1. Environment URLs

* **Gitea Code Repository Web UI:** [${GITEA_URL}](${GITEA_URL})
* **Your Dev Web Site:** [${DEV_URL}](${DEV_URL})
* **Your Prod Web Site:** [${PROD_URL}](${PROD_URL})

### Gitea Login Credentials
* **Username:** \`workshop-admin\`
* **Password:** \`WorkshopAdminPassword123!\`

---

## 2. Working with Your Code

The deployment platform automatically builds and deploys your code. You do not need to touch OpenShift.

### Step 1: Clone the Repository
Clone your project's starter code from Gitea:
\`\`\`bash
git clone ${CLONE_URL}
cd starter-flask-app
\`\`\`
*(When prompted, enter the username \`workshop-admin\` and password \`WorkshopAdminPassword123!\`)*

### Step 2: Make Edits & Deploy to Dev
If this is your first time using git on this machine, set your identity once:
\`\`\`bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
\`\`\`

To test changes, work on the \`dev\` branch:
\`\`\`bash
# Switch to dev branch
git checkout dev

# Make changes to app.py (e.g., edit the hero heading text or the
# "Trigger Action" button label inside HTML_TEMPLATE)

# Commit and push
git add app.py
git commit -m "feat: customize the starter site"
git push origin dev
\`\`\`
*(You'll be prompted for your Gitea username/password again for this push — same credentials as the clone step.)*

*Once pushed, OpenShift will automatically build and update your **Dev Web Site** in ~1-2 minutes.*

### Step 3: Release to Production
When your app is ready for production, merge to \`main\` and push:
\`\`\`bash
# Switch to main and merge dev
git checkout main
git merge dev

# Push main
git push origin main
\`\`\`
*This will trigger a production build and update your **Prod Web Site** automatically.*
EOF

echo "SUCCESS: HANDOUT.md generated in the root directory!"
echo "You can share the contents of HANDOUT.md with your workshop attendees."
