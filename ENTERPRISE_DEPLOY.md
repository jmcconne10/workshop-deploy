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
   ```bash
   oc new-project hackathon-workshop
   ```
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

Edit the template [values-enterprise.yaml](file:///Users/joemcconnell/Documents/Code/workshop-deploy/values-enterprise.yaml) in the root of the project to match your infrastructure requirements:

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
    *   *Fix:* Verify that Gitea's internal webhook points to `https://kubernetes.default.svc`. Check Gitea logs for connection timeouts or SSL verification issues. (SSL verification is bypassed in the hook script by setting `skip_verify: "1"`).
*   **Issue: `ImagePullBackOff` on the dev/prod app pod right after install**
    *   *Fix:* This is expected for the first ~1-2 minutes — the chart triggers an initial build automatically, and the pod can't pull an image until it finishes. Check `oc get builds` and `oc logs job/<release>-gitea-setup`; if the setup job's log shows it couldn't trigger the build (e.g. bad `openshift.token`/`openshift.apiServer`), fall back to `oc start-build <release>-dev` / `oc start-build <release>-prod` manually.
