# Workshop Deployment POC — Iterative Development TODO List

This document tracks the iterative tasks remaining to finalize and validate the OpenShift Hackathon Workshop Proof of Concept.

## Phase 1: Starter App Code Injection (Current Focus)
- [ ] **Inject Starter Files via Gitea API:**
  - Update the Gitea post-install setup script ([gitea-setup-configmap.yaml](file:///Users/joemcconnell/Documents/Code/workshop-deploy/charts/workshop/templates/gitea-setup-configmap.yaml)) to call Gitea's Content API (`POST /api/v1/repos/{owner}/{repo}/contents/{filepath}`) to write the initial files:
    - [ ] `app.py` (Simple Flask application listening on port `8080`)
    - [ ] `requirements.txt` (Flask dependency)
  - This ensures that when the Helm chart is installed, the Git repository is pre-populated with running starter code on both `main` and `dev` branches.
- [ ] **Deploy & Verify Injection:**
  - Redeploy the Helm chart and verify that Gitea initializes the repository with the code, allowing the initial BuildConfigs to run successfully.

## Phase 2: Webhook Trigger & Build Validation
- [ ] **Verify Webhook Delivery:**
  - Push a manual change to Gitea's `dev` branch and confirm that the Gitea webhook triggers the OpenShift generic webhook on `bc/workshop-poc-dev`.
  - Check the Gitea webhook delivery log (in the Gitea UI: Repository Settings -> Webhooks) and confirm a `200 OK` or `201 Created` status from `kubernetes.default.svc`.
- [ ] **Verify S2I Build Execution:**
  - Verify that the S2I build starts automatically and compiles the Python application.
  - Fix any build-time issues (e.g., missing dependencies, builder image access).
- [ ] **Verify Rolling Update:**
  - Check that the `workshop-poc-dev` deployment automatically rolls out the new image once the build finishes.

## Phase 3: Production Merge Flow Validation
- [ ] **Simulate Merge to Main:**
  - Simulate a pull request merge in Gitea from `dev` to `main` (or a direct push to `main`).
  - Verify that Gitea fires the production webhook.
- [ ] **Verify Prod Build & Deploy:**
  - Check that `bc/workshop-poc-prod` builds successfully and updates the production deployment.

## Phase 4: Hardening & Sandbox Optimization
- [ ] **Configure PVC Retain/Cleanup:**
  - Verify that `helm uninstall` cleanly removes the PVC or leaves it depending on requirements.
- [ ] **Prune Build History:**
  - Ensure sandbox quotas are respected by validating that old builds are pruned according to our `successfulBuildsHistoryLimit: 2` settings.
- [ ] **Add Future Enhancements to `FUTURE.md`:**
  - Document post-POC ideas (such as multi-team tenancy, automated team onboarding, and enterprise registry integration).

## Phase 5: Code Review & Merging
- [ ] Push all local changes to the feature branch.
- [ ] Submit the branch for human review.
- [ ] Merge the approved `feature/environment-setup` branch into `main`.
