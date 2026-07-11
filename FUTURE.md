# Enterprise Scaling & Post-POC Roadmap

This document outlines the architectural enhancements and features needed to migrate the OpenShift Hackathon Workshop environment from the Single-Namespace POC (Red Hat Developer Sandbox) to a multi-tenant, enterprise-grade OpenShift cluster.

## 1. Multi-Team Workspace Separation
In the POC, all resources (the git server, Dev/Prod environments for the starter app) share a single namespace. In an enterprise environment, we must isolate each hackathon team.
- **Designated namespaces per team:**
  - `workshop-infra`: Hosts global services like the git server, DNS, or shared registries.
  - `team-<id>-dev`: Sandbox namespace for team development.
  - `team-<id>-prod`: Isolated environment for staging/production.
- **Network Policies:** Implement `NetworkPolicies` to forbid cross-namespace traffic between teams, ensuring they cannot access or disrupt other teams' workloads.

## 2. Automated Team Onboarding
Manually creating namespaces, secrets, and routes for each team is not scalable.
- **Custom Operator or Automation Controller:** Use an Ansible-based or Go-based operator (or an onboarding API) that:
  1. Initializes a git repository for each registered team.
  2. Provisions team namespaces (`dev`/`prod`).
  3. Deploys the team-specific starter app Helm chart.
  4. Mounts the required Kubernetes service account tokens for webhook triggers.
  5. Installs the git server's `post-receive` hook pointing at the team's BuildConfig webhooks.
- **Current state:** `orchestrate/provision_workshop.py` covers a lighter-weight version
  of steps 1–3 and 5 (a Python script, not an operator) for up to ~20 teams, one
  namespace per team, reusing the existing chart unmodified. It does **not** address
  step 4 as originally envisioned above: every team's git server `post-receive` hook
  currently authenticates to the OpenShift API using the *same* shared operator token (passed via
  `OC_TOKEN`), rather than a per-team scoped service account token. That's an accepted
  trade-off for workshop scale, but it means one leaked/misused token has a blast
  radius across every team's namespace. Per-team scoped tokens (a ServiceAccount +
  RoleBinding created alongside each team's namespace, restricted to triggering builds
  in that namespace only) would close this gap.

## 5. Build Capacity Planning for Live Events
Provisioning capacity (bursts of S2I builds while standing up N teams ahead of time) is
one thing; live capacity during the actual workshop is another. If many teams push code
around the same time mid-event, that's a separate burst of concurrent build pods the
provisioning tooling has no visibility into or control over — cluster capacity planning
for a live 20-team event should account for this separately from initial provisioning.

## 3. Corporate Security & Authentication
- **Git push authentication:** _Done (Phase 2)_ — pushing now requires a shared credential via htpasswd basic-auth (clone stays anonymous). **Still future:** per-user auth — front the git server with an auth proxy or integrate push auth with corporate identity (LDAP/Keycloak/AD) so pushes are attributed to individuals rather than a shared account.
- **Pre-built git server image (air-gap):** _Done (Phase 4)_ — `gitServer.build.enabled: false` + `gitServer.image.*` runs a pre-built image instead of building in-cluster; `values-enterprise.yaml` ships this as the default. **Still future:** automate building/mirroring that image into the customer registry as part of an enterprise install pipeline.
- **Secrets Management:** Transition from manual secret generation to an enterprise secrets manager (e.g., HashiCorp Vault or OpenShift GitOps/ArgoCD integration with external secrets).

## 4. Monitoring & Resource Controls
- **Quotas & Limits:** Set strict `ResourceQuotas` and `LimitRanges` on all team namespaces to prevent a single buggy application from consuming all cluster capacity.
- **Pruning Automation:** Keep builds pruned automatically to save storage space on host nodes.
