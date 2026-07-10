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
   This secret lets the cluster pull the S2I builder image from Nexus (and, if you mirror it, the UBI base image the git server is built from). Replace credentials below:
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
4. **Git server image build (air-gap note):**
   The git server runs a small UBI-based image (`git` + `httpd`) that the chart **builds
   in-cluster** from `charts/workshop/files/gitserver/Containerfile`. That build pulls
   `ubi9/ubi-minimal` and installs `git-core`/`httpd`, so it needs egress to Red Hat's
   image and package repositories at build time. On an air-gapped cluster, either mirror
   the UBI base image and repos, or pre-build the image and push it to your registry
   (wiring a pre-built image into the git server Deployment is on the roadmap — see
   [FUTURE.md](FUTURE.md)).

---

## Step 2: Configure Enterprise Override Values

Edit the template [values-enterprise.yaml](values-enterprise.yaml) in the root of the project to match your infrastructure requirements:

1. **API Server (required):** Set `openshift.apiServer` to your enterprise cluster's API server URL. This ships blank in `values-enterprise.yaml` on purpose — if left unset, the git server's build-trigger hook has no valid target and builds will never fire. Pass it explicitly, e.g. `--set openshift.apiServer=https://api.openshift.company.com:6443`.
2. **Registry Domains:** Update the repository URLs to point to your Nexus domain (e.g. `nexus.company.com`).
3. **Storage Class:** Set `gitServer.persistence.storageClass` to your company's storage provisioner (e.g. `gp3`, `thin`, `ocs-storagecluster-cephfs`).
4. **Resource Scale:** Customize CPU/Memory requests and limits to fit your team size.
5. **Replicas:** Set production application replica count to high availability levels (e.g., `replicas: 3`).

---

## Step 3: Install the Helm Chart

Run the Helm installation command from the repository root, passing the enterprise values file, your API server, and an OpenShift token. **The token is required** — the git server's `post-receive` hook (and the one-time initial-build trigger) authenticate to the cluster with it, and without it they get an HTTP 403 (an empty token is treated as anonymous), so the dev/prod sites never get a build:

```bash
helm install workshop-poc charts/workshop -f values-enterprise.yaml \
  --set openshift.apiServer=https://api.openshift.company.com:6443 \
  --set openshift.token=$(oc whoami -t)
```

> `oc whoami -t` uses your current login token, which expires (often within hours on enterprise clusters). For a long-running or shared environment, create a dedicated **service-account token** with rights to trigger the BuildConfig webhooks and pass that instead, so builds keep working after your personal session expires.

---

## Step 4: Post-Deployment Verification

1. **Verify Pod Statuses:**
   Confirm the git server image build completed and the git server pod is running:
   ```bash
   oc get builds        # workshop-poc-gitserver-1 should be Complete
   oc get pods          # workshop-poc-gitserver-... should be Running
   ```
2. **Check the git server startup log:**
   Confirm it initialized the bare repo, seeded the starter app, installed the
   `post-receive` hook, and triggered the initial dev/prod builds:
   ```bash
   oc logs deploy/workshop-poc-gitserver
   ```
   You should see the seed, then `Service reachability check returned HTTP 200`, then
   `triggered initial prod build (HTTP 200)` / `dev build (HTTP 200)`.
3. **Fetch Routes:**
   Retrieve the git clone URL and the app site URLs:
   ```bash
   # Git clone URL (append /git/<repoName>.git)
   oc get route workshop-poc-gitserver -o jsonpath='https://{.spec.host}/git/starter-flask-app.git{"\n"}'

   # Dev App URL
   oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}{"\n"}'

   # Prod App URL
   oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}{"\n"}'
   ```

---

## Troubleshooting Common Enterprise Issues

*   **Issue: The `workshop-poc-gitserver` image build fails**
    *   *Fix:* The build pulls `ubi9/ubi-minimal` and `microdnf install`s `git-core`/`httpd`, so it needs egress to Red Hat's image + package repositories. On an air-gapped cluster, mirror the UBI base image and repos (or supply a pre-built image). Check `oc logs build/workshop-poc-gitserver-1`.
*   **Issue: `ImagePullBackOff` on the builder image**
    *   *Fix:* Verify the `nexus-registry-credentials` pull secret is created and linked to the `builder` service account (Step 1). Check build events: `oc describe build workshop-poc-dev-1`.
*   **Issue: Pod stuck in `Pending` state with `VolumeNotBound`**
    *   *Fix:* Your cluster may not support the default storage class or the one set in `values-enterprise.yaml` is invalid. Check available classes with `oc get sc` and update `gitServer.persistence.storageClass` accordingly.
*   **Issue: A push doesn't trigger a build (`401 Unauthorized` / `403` / `502`)**
    *   *Fix:* The git server's `post-receive` hook calls the **external** cluster API server (`openshift.apiServer`) authenticated with `openshift.token`. A **401/403** means the token is missing, wrong, or expired — reinstall with a valid `--set openshift.token=...` (or a longer-lived service-account token). A **502/connection error** means `openshift.apiServer` is wrong or unreachable from inside the cluster — confirm it matches `oc whoami --show-server`. Inspect `oc logs deploy/<release>-gitserver` (startup trigger) and, for a participant push, the `remote:` lines the push prints. TLS verification on the outbound call is intentionally skipped (`curl -k`).
*   **Issue: `ImagePullBackOff` on the dev/prod app pod right after install**
    *   *Fix:* Expected for the first ~1-2 minutes — the git server triggers the initial builds automatically once it's serving, and the pod can't pull an image until the build finishes. Check `oc get builds` and `oc logs deploy/<release>-gitserver`; if the log shows the trigger failed (e.g. bad `openshift.token`/`openshift.apiServer`), fall back to `oc start-build <release>-dev` / `oc start-build <release>-prod` manually.
*   **Issue: Reinstall fails with "invalid ownership metadata" on `workshop-poc-oc-token`**
    *   *Fix:* You're upgrading from the old Gitea-based chart, which created some objects as Helm *hooks* that linger after `helm uninstall` without release-ownership metadata. Delete the leftovers before reinstalling: `oc delete secret workshop-poc-oc-token --ignore-not-found` (and any stray `oc delete configmap workshop-poc-gitea-setup --ignore-not-found`).
*   **Issue: Starter site renders in a plain/fallback font on an air-gapped network**
    *   *Fix:* Cosmetic only. The starter `app.py` links a web font from `fonts.googleapis.com`; with no outbound internet the browser silently falls back to a system font (Arial). The app is otherwise fully functional. To make it self-contained, remove or self-host the `<link href="https://fonts.googleapis.com/...">` tag in `charts/workshop/files/starter-app/app.py`.
