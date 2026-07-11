# Hackathon Workshop Environment: Setup, Usage, & Teardown Guide

This guide is split into instructions for the **Workshop Organizer** (infrastructure setup and teardown) and the **Hackathon Participants** (developing and deploying code).

## Which setup do I need?

There are two ways to stand this up, depending on what you're running:

* **A single deployment** — one git server + dev + prod stack, e.g. for testing the chart
  or a one-person session. Follow **Part 1: Organizer Setup Guide (Single Deployment)**
  below.
* **A real multi-team workshop** (up to ~20 teams) — one fully isolated stack per
  team, provisioned in one batch, with a handout generated per team and a master
  roster of every team's URLs and credentials. Skip ahead to
  **Part 1B: Organizer Setup Guide (Batch / Multi-Team Workshops)**.

---

## Part 1: Organizer Setup Guide (Single Deployment)

**Audience: the person deploying the environment.** Participants don't need anything
in this section — they get their own instructions via the generated handout (see
Part 2 below).

### 1. Prerequisites
Before deploying, make sure you have:
* The OpenShift CLI (`oc`) and Helm CLI (`helm`) installed.
* Access to a Red Hat OpenShift namespace (such as the Developer Sandbox).

### 2. Login to OpenShift
Log in to the cluster using your token and server URL (retrieve this from the OpenShift Web Console):
```bash
oc login --token=<YOUR_TOKEN> --server=<YOUR_SERVER_URL>
```

### 3. Deploy the Environment
Deploy the git server, starter repository, BuildConfigs, and routing templates using Helm.
`openshift.apiServer`/`openshift.token` are required — without them, the git server's
`post-receive` hook (and the initial-build trigger) get an HTTP 403 from the API server
(an empty token is treated as anonymous) and the dev/prod sites never get a build:
```bash
helm install workshop-poc charts/workshop \
  --set openshift.apiServer=$(oc whoami --show-server) \
  --set openshift.token=$(oc whoami -t)
```

### 4. Retrieve URLs & Generate the Attendee Handout
Wait about 1–2 minutes for the git server image to build and the repo to seed, then run
the handout generator — it queries the routes for you and writes a ready-to-share
`HANDOUT.md` (git clone URL + Dev/Prod site URLs):
```bash
./generate-handout.sh
```
The git server is a plain repository (no web UI). Cloning is anonymous; pushing prompts for
the shared `gitServer.admin` credential (default `workshop-admin` / `WorkshopAdminPassword123!`,
included in the handout). Participants clone and push
over the git clone URL in the handout.

Share the generated `HANDOUT.md` with the participant.

The Dev/Prod routes will be reachable as soon as the git server is up, but the starter
app itself won't render for another ~1-2 minutes while the initial build finishes — if
you check immediately and see an error page, that's expected; run `oc get builds` to
confirm one is in progress.

<details>
<summary>Just need the URLs yourself, without generating a handout?</summary>

```bash
# Retrieve Git clone URL
echo "Git clone URL: $(oc get route workshop-poc-gitserver -o jsonpath='https://{.spec.host}')/git/starter-flask-app.git"

# Retrieve Dev Environment App URL
echo "Dev Web Site URL: $(oc get route workshop-poc-dev -o jsonpath='https://{.spec.host}')"

# Retrieve Prod Environment App URL
echo "Prod Web Site URL: $(oc get route workshop-poc-prod -o jsonpath='https://{.spec.host}')"
```
</details>

---

## Part 1B: Organizer Setup Guide (Batch / Multi-Team Workshops)

**Audience: the person deploying the environments.** Same as Part 1 — nothing here is
meant for participants; they get their own per-team handout automatically.

Use this instead of Part 1 when you're running a real workshop with multiple teams
(up to ~20). It uses `orchestrate/provision_workshop.py` to create one isolated
namespace and one full stack per team, then generates a per-team handout plus a master
roster of every team's URLs and credentials — no need to repeat Part 1 by hand for
each team.

**This targets a real enterprise OpenShift cluster, not the Developer Sandbox** — a
sandbox account only gets one namespace and its quotas aren't sized for 20 concurrent
stacks. See [ENTERPRISE_DEPLOY.md](ENTERPRISE_DEPLOY.md) for cluster prerequisites
(registry secrets, storage class, etc.) before running this at scale.

1. **Create a virtual environment and install the script's dependency:**
   ```bash
   python3 -m venv orchestrate/.venv
   source orchestrate/.venv/bin/activate
   pip install -r orchestrate/requirements.txt
   ```
   `orchestrate/.venv/` is gitignored. Re-run the `source` line (only) to reactivate
   it in a new shell — no need to recreate it or reinstall dependencies each time.
2. **Copy the example roster and fill in your event's details** (this file is
   gitignored — never commit real cluster/participant details):
   ```bash
   cp orchestrate/teams.example.yaml orchestrate/teams.local.yaml
   ```
   Edit `cluster.apiServer`, `cluster.valuesFile`, `cluster.namespacePrefix`, and the
   `teams` list (one `id` + `displayName` per team). Optionally set `members: <N>` per
   team (default 1): for a team of 2+, the deploy pre-creates branches `member1`..`memberN`
   off `dev`, one per developer, and each team's handout is tailored with the matching
   member-branch workflow (see Part 2).
3. **Log in to the target cluster and set the webhook auth token** (same token model
   as the single-deployment flow — see Prerequisites above):
   ```bash
   oc login --token=<YOUR_TOKEN> --server=<YOUR_ENTERPRISE_SERVER>
   export OC_TOKEN=<YOUR_TOKEN>
   ```
4. **Dry-run first** to sanity-check the commands it would run, with no cluster changes:
   ```bash
   python orchestrate/provision_workshop.py orchestrate/teams.local.yaml --dry-run
   ```
5. **Smoke-test with 2–3 teams** before committing to the full roster — trim the
   `teams` list temporarily, or keep a separate small test file. Confirm each team's
   namespace, routes, and handout look right.
6. **Run for real** once satisfied:
   ```bash
   python orchestrate/provision_workshop.py orchestrate/teams.local.yaml
   ```
   Per-team handouts land in `orchestrate/output/teams.local/handouts/`, and the
   master roster (all teams' URLs + credentials) in
   `orchestrate/output/teams.local/roster.md` / `roster.csv`. These are gitignored —
   treat them as sensitive files for the duration of the event.
7. **Tear everything down** after the workshop:
   ```bash
   python orchestrate/provision_workshop.py orchestrate/teams.local.yaml --teardown
   ```

**Before running the full batch:** multiply `values-enterprise.yaml`'s per-team
resource requests by your team count and check against the target cluster's actual
available capacity — this is real infrastructure, not free sandbox quota.

---

## Part 2: Participant Development Guide

**Audience: hackathon participants — not the organizer.** This isn't something you
walk participants through by hand: it's the content they already receive
automatically in their generated handout (`HANDOUT.md` from Part 1, or their team's
`team-<id>-handout.md` from Part 1B). It's documented here so you know what
participants are being told without having to go dig it out of a template file.

In short, a participant:

1. **Clones their starter repo** from the git server using the clone URL in their
   handout (clone is anonymous) — pre-populated with `app.py` (a simple Flask app) and `requirements.txt`.
2. **Pushes changes to the `dev` branch** → OpenShift automatically builds and
   deploys the update to their **Dev Web Site**.
3. **Merges `dev` into `main` and pushes** → OpenShift automatically builds and
   deploys the update to their **Prod Web Site**.

**Teams with multiple developers (batch `members: N ≥ 2`):** each team shares one Dev
site, so developers don't all push `dev` directly. The deploy pre-creates a branch per
developer — `member1`..`memberN`, off `dev`. Each developer works on their own member
branch (pushing there triggers no build — it's private scratch space), then merges into
`dev` and pushes `dev` to update the shared team Dev site. They `git pull origin dev`
before merging so the site reflects everyone's work, and one person promotes `dev`→`main`
for Prod. This member-branch section is injected into each team's handout automatically
based on its `members` count; solo teams (`members: 1`) just use `dev` directly as above.

They never touch OpenShift directly. The exact commands and wording sent to
participants live in the handout templates, not here — edit those if you want to
change what participants are told:
* [`generate-handout.sh`](generate-handout.sh) (single deployment, Part 1)
* [`orchestrate/templates/handout.md.tmpl`](orchestrate/templates/handout.md.tmpl) (batch, Part 1B)

---

## Part 3: Organizer Cleanup Guide

**Ran a multi-team batch (Part 1B)?** Don't use the steps below — tear down every
team's namespace and release with the batch script's teardown mode instead (Part 1B,
step 7):
```bash
python orchestrate/provision_workshop.py orchestrate/teams.local.yaml --teardown
```

The rest of this section is for a single deployment (Part 1). Once the hackathon is finished, you can cleanly delete the entire setup (including dynamically created builds and leftover pods) and prepare for a fresh install by running the automated cleanup script:

```bash
./reset.sh
```

Alternatively, you can clean up resources manually:

```bash
# Uninstall the Helm release
helm uninstall workshop-poc

# Clean up leftover build resources
oc delete builds -l app.kubernetes.io/name=workshop
oc delete pods -l openshift.io/build.name
```
