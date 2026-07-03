# Workshop Deployment POC — Iterative Development TODO List

This document tracks the iterative tasks remaining to finalize and validate the OpenShift Hackathon Workshop Proof of Concept.

## Phase 1: Starter App Code Injection ✅ COMPLETE
- [x] **Inject Starter Files via Gitea API:**
  - Updated the Gitea post-install setup script ([gitea-setup-configmap.yaml](file:///Users/joemcconnell/Documents/Code/workshop-deploy/charts/workshop/templates/gitea-setup-configmap.yaml)) to call Gitea's Content API to write the initial files using pre-encoded base64 (to avoid shell indentation issues):
    - [x] `app.py` (Simple Flask application listening on port `8080`)
    - [x] `requirements.txt` (Flask dependency)
  - Both branches (`main` and `dev`) are pre-populated on install.
- [x] **Deploy & Verify Injection:**
  - Redeployed the Helm chart and verified Gitea initializes the repository with starter code.

## Phase 2: Webhook Trigger & Build Validation ✅ COMPLETE
- [x] **Verify Webhook Delivery:**
  - Fixed multiple Gitea webhook issues:
    - Added `GITEA__webhook__ALLOWED_HOST_LIST: "*"` to allow internal calls
    - Added `GITEA__webhook__SKIP_TLS_VERIFY: true` for self-signed certs
    - Switched webhook URL to external API server with Bearer token auth header
  - Push to `dev` branch now successfully triggers `bc/workshop-poc-dev`
- [x] **Verify S2I Build Execution:**
  - `workshop-poc-dev-2` built successfully from `ubi8/python-39` S2I builder.
- [x] **Verify Rolling Update:**
  - `workshop-poc-dev` deployment rolled out with new image; pod `1/1 Running`.
  - Dev app live at: `https://workshop-poc-dev-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com` → `Hello from OpenShift Hackathon!`

## Phase 3: Production Merge Flow Validation ✅ COMPLETE
- [x] **Simulate Merge to Main:**
  - Merged `dev` → `main` in the internal Gitea repo; prod webhook fired automatically.
- [x] **Verify Prod Build & Deploy:**
  - `workshop-poc-prod-1` built and pushed successfully.
  - `workshop-poc-prod` deployment rolled out; pod `1/1 Running`.
  - Prod app live at: `https://workshop-poc-prod-joseph-mcconnell-dev.apps.rm3.7wse.p1.openshiftapps.com` → `Hello from OpenShift Hackathon!`

## Phase 4: Hardening & Sandbox Optimization
- [x] **Configure PVC Retain/Cleanup:**
  - Verify that `helm uninstall` cleanly removes the PVC or leaves it depending on requirements.
- [x] **Prune Build History:**
  - Ensure sandbox quotas are respected by validating that old builds are pruned according to our `successfulBuildsHistoryLimit: 2` settings.
- [x] **Add Future Enhancements to `FUTURE.md`:**
  - Document post-POC ideas (such as multi-team tenancy, automated team onboarding, and enterprise registry integration).

## Phase 5: Code Review & Merging
- [ ] Push all local changes to the feature branch.
- [ ] Submit the branch for human review.
- [ ] Merge the approved `feature/environment-setup` branch into `main`.

