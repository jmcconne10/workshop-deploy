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

1. **Registry Domains:** Update the repository URLs to point to your Nexus domain (e.g. `nexus.company.com`).
2. **Storage Class:** Set `gitea.persistence.storageClass` to your company's storage provisioner (e.g. `gp3`, `thin`, `ocs-storagecluster-cephfs`).
3. **Resource Scale:** Customize CPU/Memory requests and limits to fit your team size.
4. **Replicas:** Set production application replica count to high availability levels (e.g., `replicas: 3`).

---

## Step 3: Install the Helm Chart

Run the Helm installation command from the repository root, passing the enterprise values file:

```bash
helm install workshop-poc charts/workshop -f values-enterprise.yaml
```

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
