# OpenShift Hackathon Workshop POC

This repository contains the Helm chart and configurations for deploying a self-contained, automated workshop environment on the **Red Hat Developer Sandbox**.

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

Deploy the entire environment (Gitea, starter repo, BuildConfigs, and Flask app routes) with a single command:

```bash
helm install workshop-poc charts/workshop
```

### Post-Install Automation
The Helm chart includes a post-install hook Job that:
1. Waits for Gitea to start.
2. Creates a public repository named `starter-flask-app` under the `workshop-admin` account.
3. Automatically sets up the `dev` branch.
4. Configures Gitea webhooks to trigger the respective OpenShift S2I BuildConfigs for `dev` (pushed to `dev`) and `prod` (pushed to the default branch).

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

To verify the automated build and deployment flow, simulate pushing code to Gitea:

1. **Clone the Gitea Repo locally:**
   ```bash
   git clone <GITEA_CONSOLE_URL>/workshop-admin/starter-flask-app.git
   cd starter-flask-app
   ```
   *(Enter Gitea credentials when prompted)*

2. **Add a Starter Flask App:**
   Create `app.py`:
   ```python
   from flask import Flask
   app = Flask(__name__)

   @app.route('/')
   def hello():
       return "Hello from OpenShift Hackathon Dev Branch!"

   if __name__ == '__main__':
       app.run(host='0.0.0.0', port=8080)
   ```

   Create `requirements.txt`:
   ```text
   Flask==3.0.3
   ```

3. **Verify Dev Deploy:**
   Check out to `dev` branch and push:
   ```bash
   git checkout -b dev
   git add app.py requirements.txt
   git commit -m "feat: initial dev flask app"
   git push origin dev
   ```

   This push automatically triggers the Dev build. You can track the build progress:
   ```bash
   oc get builds
   oc logs -f bc/workshop-poc-dev
   ```
   Once the build succeeds, the dev container rolls out. Refresh the **Dev App URL** to verify the hello message.

4. **Verify Prod Deploy:**
   Merge your changes to `main` (or the default branch `master`) and push:
   ```bash
   git checkout main
   git merge dev
   git push origin main
   ```
   This push triggers the Prod build. Track progress with `oc logs -f bc/workshop-poc-prod`. Once finished, verify the hello message on the **Prod App URL**.

---

## Teardown

To cleanly remove all resources from the sandbox:

```bash
helm uninstall workshop-poc
```
