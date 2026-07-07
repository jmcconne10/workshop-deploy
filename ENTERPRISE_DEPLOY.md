# Enterprise Deployment Guide & Runbook

This guide outlines the steps required to deploy the workshop environment onto your company's internal production or enterprise OpenShift cluster using your private Nexus registry.

---

## Prerequisites

1. **Enterprise OpenShift CLI Access:**
   Ensure you are logged in to your target enterprise cluster:
   ```bash
   oc login --token=<INTERNAL_TOKEN> --server=https://api.openshift.company.com:6443
   ```
2. **Helm CLI:** Ensure `helm` is installed locally.
3. **Private Nexus Registry Credentials:**
   You will need the username, password/token, and domain for your internal Nexus registry.

---

## Step 1: Pre-Deployment Cluster Configuration

Before installing the Helm chart, configure your namespace with the necessary registry secrets.

1. **Create or Switch to the Target Project:**

   If you have permission to create your own projects, create one:
   ```bash
   oc new-project hackathon-workshop
   ```

   **If the project was pre-created for you** (common on locked-down enterprise
   clusters where you don't have the `self-provisioner` role to run `oc new-project`),
   skip the create step and just switch into the existing project instead:
   ```bash
   oc project <your-existing-project-name>
   ```
   Everything below — the pull secret, the service-account links, and the `helm install`
   in Step 3 — targets whichever project you're currently in, so no other changes are
   needed. The chart is namespace-relative and never hard-codes a project name; it deploys
   into the project you select here. (Do **not** pass `--create-namespace` to Helm — the
   project already exists.)
2. **Create the Private Registry Image Pull Secret:**
   This secret allows the cluster to pull the rootless Gitea and builder images from Nexus. Replace credentials below:
   ```bash
   oc create secret docker-registry nexus-registry-credentials \
     --docker-server=nexus.company.com \
     --docker-username="<NEXUS_USERNAME>" \
     --docker-password="<NEXUS_PASSWORD>" \
     --docker-email="<USER_EMAIL>"
   ```
3. **Link Secret to Service Accounts (Recommended):**
   Link the pull secret to the `default` and `builder` service accounts in the project so OpenShift can pull images automatically:
   ```bash
   oc secrets link default nexus-registry-credentials --for=pull
   oc secrets link builder nexus-registry-credentials --for=pull
   ```

---

## Step 2: Configure Enterprise Override Values

Edit the template [values-enterprise.yaml](values-enterprise.yaml) in the root of the project to match your infrastructure requirements:

1. **API Server (required):** Set `openshift.apiServer` to your enterprise cluster's API server URL. This ships blank in `values-enterprise.yaml` on purpose — if left unset, the Gitea webhook has no valid target and build triggers will fail. Pass it explicitly, e.g. `--set openshift.apiServer=https://api.openshift.company.com:6443`.
2. **Registry Domains:** Update the repository URLs to point to your Nexus domain (e.g. `nexus.company.com`).
3. **Storage Class:** Set `gitea.persistence.storageClass` to your company's storage provisioner (e.g. `gp3`, `thin`, `ocs-storagecluster-cephfs`).
4. **Resource Scale:** Customize CPU/Memory requests and limits to fit your team size.
5. **Replicas:** Set production application replica count to high availability levels (e.g., `replicas: 3`).

---

## Step 3: Install the Helm Chart

Run the Helm installation command from the repository root, passing the enterprise values file, your API server, and an OpenShift token. **The token is required** — Gitea's webhook and the chart's automatic initial-build trigger authenticate to the cluster with it, and without it both get an HTTP 403 (an empty token is treated as anonymous), so the dev/prod sites never get a build:

```bash
helm install workshop-poc charts/workshop -f values-enterprise.yaml \
  --set openshift.apiServer=https://api.openshift.company.com:6443 \
  --set openshift.token=$(oc whoami -t)
```

> `oc whoami -t` uses your current login token, which expires (often within hours on enterprise clusters). For a long-running or shared environment, create a dedicated **service-account token** with rights to trigger the BuildConfig webhooks and pass that instead, so builds keep working after your personal session expires.

---

## Step 4: Post-Deployment Verification

1. **Verify Pod Statuses:**
   Ensure Gitea starts up successfully:
   ```bash
   oc get pods
   ```
2. **Monitor the Gitea Setup Hook Job:**
   Verify that the post-install job successfully connects to Gitea, creates the repository, and configures the webhook paths:
   ```bash
   oc logs job/workshop-poc-gitea-setup
   ```
3. **Fetch Routes:**
   Retrieve the external URL addresses to access the consoles:
   ```bash
   # Gitea URL
   oc get route workshop-poc-gitea -o jsonpath='https://{.spec.host}{"\n"}'
   
   # Dev App URL
   oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}{"\n"}'
   
   # Prod App URL
   oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}{"\n"}'
   ```

---

## Troubleshooting Common Enterprise Issues

*   **Issue: `ImagePullBackOff` on Gitea or Builder image**
    *   *Fix:* Verify that the image pull secret `nexus-registry-credentials` is created correctly and linked to the `default` service account. Check events: `oc describe pod -l app=workshop-gitea`.
*   **Issue: Pod stuck in `Pending` state with `VolumeNotBound`**
    *   *Fix:* Your cluster may not support the default storage class or the storage class specified in `values-enterprise.yaml` is invalid. Check available storage classes with `oc get sc` and update `gitea.persistence.storageClass` accordingly.
*   **Issue: Webhook triggers failing (`401 Unauthorized` or `502 Bad Gateway`)**
    *   *Fix:* The setup Job registers Gitea's webhooks against your **external** cluster API server (`openshift.apiServer`), not the in-cluster `kubernetes.default.svc` address, and authenticates with `openshift.token`. A **401** almost always means the token is missing, wrong, or expired — re-install passing a valid `--set openshift.token=...` (or a longer-lived service-account token). A **502/connection error** usually means `openshift.apiServer` is wrong or unreachable from inside the cluster — confirm the URL matches `oc whoami --show-server`. Check the webhook delivery details in the Gitea repo UI (Settings → Webhooks) and the setup Job log (`oc logs job/<release>-gitea-setup`). SSL verification on the outbound call is intentionally bypassed in the hook script via `skip_verify: "1"`.
*   **Issue: `ImagePullBackOff` on the dev/prod app pod right after install**
    *   *Fix:* This is expected for the first ~1-2 minutes — the chart triggers an initial build automatically, and the pod can't pull an image until it finishes. Check `oc get builds` and `oc logs job/<release>-gitea-setup`; if the setup job's log shows it couldn't trigger the build (e.g. bad `openshift.token`/`openshift.apiServer`), fall back to `oc start-build <release>-dev` / `oc start-build <release>-prod` manually.
*   **Issue: Starter site renders in a plain/fallback font on an air-gapped network**
    *   *Fix:* Cosmetic only. The starter `app.py` links a web font from `fonts.googleapis.com`; with no outbound internet the browser silently falls back to a system font (Arial). The app is otherwise fully functional. To make it self-contained, remove or self-host the `<link href="https://fonts.googleapis.com/...">` tag in `charts/workshop/files/starter-app/app.py`.
