# OpenShift Hackathon Workshop Environment — Proof of Concept

## Project Overview

Build an automated, self-contained workshop environment on OpenShift that can be stood up and torn down for hackathons. The end goal is a repeatable pattern where hackathon teams push code to a Git repo and their app automatically rebuilds and redeploys — **teams never need to touch or see OpenShift**.

This POC validates the pattern at minimal scale on the **Red Hat Developer Sandbox** before porting to the enterprise environment.

## Target Architecture (POC Scope)

Everything lives in a **single OpenShift project** (the sandbox provides one namespace):

1. **Gitea** — a lightweight, self-hosted Git service running as a container in the cluster
   - Deployment (or StatefulSet) with a persistent volume for repo storage
   - One starter repo containing the Flask app, with `main` and `dev` branches
2. **Starter App** — a simple Python Flask application
   - Two running instances: `dev` and `prod`
   - `dev` branch → dev deployment; `main` branch → prod deployment
3. **BuildConfigs** — OpenShift-native build automation (no separate CI/CD pipeline needed for POC)
   - Source-to-Image (S2I) builds using the Python builder image
   - Git webhook triggers from Gitea: push to `dev` rebuilds dev, merge to `main` rebuilds prod
   - ImageStreams for dev and prod images
4. **Helm Chart** — the whole environment (Gitea, repos, BuildConfigs, deployments, routes, services) deploys with a single `helm install`
   - Gitea repo/user creation handled via post-install hook Jobs calling the Gitea API
   - Git repo URLs, team names, replica counts, etc. parameterized as Helm values

## Full Vision (Post-POC, for context only — do not build now)

- ~5 hackathon teams, each with their own Gitea repo (main + dev branches)
- Each team gets dev and prod deployments wired to their repo
- One `helm install` stands up the entire hackathon; `helm uninstall` tears it down
- Runs on the enterprise OpenShift cluster with proper sizing

## Critical Constraint: Sandbox Resource Limits

The Red Hat Developer Sandbox has **tight resource quotas**. Everything must be sized to minimize consumption:

- Set explicit, small resource requests/limits on every container (e.g., Gitea ~100m CPU / 256Mi memory request; Flask app ~50m CPU / 128Mi memory)
- **Single replica** for everything — no HA, no autoscaling
- Use the smallest viable persistent volume for Gitea (1Gi is plenty for a POC repo)
- Use SQLite for Gitea's database — do NOT deploy PostgreSQL/MySQL
- Prune old builds and images (set `successfulBuildsHistoryLimit` / `failedBuildsHistoryLimit` low, e.g., 2)
- Prefer the sandbox's existing ImageStreams/builder images over pulling extra images
- If quota errors occur, scale down or consolidate rather than requesting more

## Success Criteria for the POC

1. `helm install` deploys Gitea + starter app + BuildConfigs into the sandbox project
2. Gitea is reachable via an OpenShift Route; starter repo exists with `main` and `dev` branches
3. Pushing a code change to `dev` in Gitea automatically triggers a rebuild and redeploy of the dev app
4. Merging `dev` → `main` automatically triggers a rebuild and redeploy of the prod app
5. `helm uninstall` cleanly removes everything

---

# Agent Guardrails (for Antigravity / AI coding agent)

Copy the section below into your agent's rules/context file (e.g., `AGENTS.md`, `GEMINI.md`, or equivalent).

## Git Workflow — Non-Negotiable

- **NEVER commit directly to `main`.** All work happens on feature branches.
- Branch naming: `feature/<short-description>` (e.g., `feature/gitea-deployment`, `fix/buildconfig-webhook`)
- One feature branch per logical unit of work. Keep branches small and focused.
- Commit early and often within a feature branch with clear, descriptive commit messages (imperative mood: "Add Gitea deployment template").
- When a feature is complete and tested, stop and present a summary of all changes on the branch for **human review and approval before merging to `main`**.
- The human approves at the **feature-branch/merge level** — you do NOT need approval for individual commits or small changes within a branch. Work autonomously within the branch.
- Never force-push, never rewrite history on `main`, never delete branches without confirmation.

## Autonomy Boundaries

Work autonomously (no approval needed) for:
- Creating/editing files within a feature branch
- Running `helm lint`, `helm template`, and dry-run validations
- Running read-only cluster commands (`oc get`, `oc describe`, `oc logs`, `oc status`)
- Iterating on templates until validation passes

Stop and ask for approval before:
- Merging any branch into `main`
- Running destructive cluster commands (`oc delete`, `helm uninstall`, anything that removes resources)
- Installing/upgrading to the live sandbox (`helm install` / `helm upgrade`) — the human runs these or explicitly approves
- Changing resource requests/limits upward
- Adding new external dependencies, images, or charts not already discussed

## Cluster Safety

- Assume the target is the **Red Hat Developer Sandbox** with strict quotas — see the resource constraints in the project brief above and honor them in every manifest.
- Never store credentials, tokens, or kubeconfig contents in the repo. Use Kubernetes Secrets and reference them; use placeholder values in committed files.
- All manifests must be namespace-relative — never hard-code the sandbox namespace; take it from Helm values or the release namespace.
- Do not create ClusterRoles, ClusterRoleBindings, or any cluster-scoped resources — the sandbox won't allow them and the POC doesn't need them.

## Code & Chart Quality

- Structure the Helm chart conventionally: `Chart.yaml`, `values.yaml`, `templates/`, with a `NOTES.txt` explaining post-install steps.
- Every configurable item (image tags, resource limits, Gitea admin user, repo names, hostnames) belongs in `values.yaml` with sane sandbox-sized defaults.
- Add comments in templates explaining anything non-obvious (especially Gitea API hook Jobs and webhook wiring).
- Validate with `helm lint` and `helm template` before declaring any feature complete.
- Keep a running `README.md` in the repo covering: prerequisites, install command, how to test the dev→prod flow, and teardown.
- Keep it simple. This is a weekend POC — prefer boring, well-documented approaches over clever ones. No operators, no ArgoCD, no Tekton pipelines unless explicitly requested.

## Scope Discipline

- Build ONLY the POC scope: one project, one Gitea, one starter repo, one Flask app with dev + prod deployments, BuildConfigs with webhooks.
- Do not build multi-team support, RBAC schemes, monitoring stacks, or CI/CD pipelines. Note ideas for the full version in a `FUTURE.md` instead of implementing them.
- If a task is ambiguous or a decision has trade-offs (e.g., webhook auth approach), present options briefly and ask rather than guessing.
