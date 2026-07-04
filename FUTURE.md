# Enterprise Scaling & Post-POC Roadmap

This document outlines the architectural enhancements and features needed to migrate the OpenShift Hackathon Workshop environment from the Single-Namespace POC (Red Hat Developer Sandbox) to a multi-tenant, enterprise-grade OpenShift cluster.

## 1. Multi-Team Workspace Separation
In the POC, all resources (Gitea, Dev/Prod environments for the starter app) share a single namespace. In an enterprise environment, we must isolate each hackathon team.
- **Designated namespaces per team:**
  - `workshop-infra`: Hosts global services like Gitea, DNS, or shared registries.
  - `team-<id>-dev`: Sandbox namespace for team development.
  - `team-<id>-prod`: Isolated environment for staging/production.
- **Network Policies:** Implement `NetworkPolicies` to forbid cross-namespace traffic between teams, ensuring they cannot access or disrupt other teams' workloads.

## 2. Automated Team Onboarding
Manually creating namespaces, secrets, and routes for each team is not scalable.
- **Custom Operator or Automation Controller:** Use an Ansible-based or Go-based operator (or an onboarding API) that:
  1. Creates Gitea organization/repositories for each registered team.
  2. Provisions team namespaces (`dev`/`prod`).
  3. Deploys the team-specific starter app Helm chart.
  4. Mounts the required Kubernetes service account tokens for webhook triggers.
  5. Configures Gitea webhooks pointing directly to the team's BuildConfigs.
- **Current state:** `orchestrate/provision_workshop.py` covers a lighter-weight version
  of steps 1–3 and 5 (a Python script, not an operator) for up to ~20 teams, one
  namespace per team, reusing the existing chart unmodified. It does **not** address
  step 4 as originally envisioned above: every team's Gitea webhook currently
  authenticates to the OpenShift API using the *same* shared operator token (passed via
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
- **OAuth2 Integration:** Integrate Gitea with corporate identity providers (via LDAP, Keycloak, or Active Directory) so teams can login with standard credentials.
- **Secrets Management:** Transition from manual secret generation to an enterprise secrets manager (e.g., HashiCorp Vault or OpenShift GitOps/ArgoCD integration with external secrets).

## 4. Monitoring & Resource Controls
- **Quotas & Limits:** Set strict `ResourceQuotas` and `LimitRanges` on all team namespaces to prevent a single buggy application from consuming all cluster capacity.
- **Pruning Automation:** Keep builds pruned automatically to save storage space on host nodes.
