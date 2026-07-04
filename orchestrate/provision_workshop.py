#!/usr/bin/env python3
"""Batch-provision (or tear down) one workshop-deploy stack per team.

Usage:
    export OC_TOKEN=<token used for Gitea webhook auth>
    python provision_workshop.py teams.local.yaml [--dry-run] [--teardown]

Assumes the caller is already `oc login`'d to the target cluster with rights to
create/delete projects and install Helm releases into them. Reuses the existing
charts/workshop chart unmodified — one Helm release per team, one namespace per team.
"""
import argparse
import csv
import os
import secrets
import string
import subprocess
import sys
import time
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
CHART_PATH = REPO_ROOT / "charts" / "workshop"
HANDOUT_TEMPLATE_PATH = Path(__file__).resolve().parent / "templates" / "handout.md.tmpl"

GITEA_ADMIN_USER = "workshop-admin"
JOB_POLL_ATTEMPTS = 60
JOB_POLL_INTERVAL_SECONDS = 5


class TeamResult:
    def __init__(self, team_id, display_name, namespace, release):
        self.team_id = team_id
        self.display_name = display_name
        self.namespace = namespace
        self.release = release
        self.succeeded = False
        self.error = None
        self.gitea_url = None
        self.dev_url = None
        self.prod_url = None
        self.admin_password = None


def run(cmd, dry_run, mask_values=None, check=True):
    """Run a command, or print a masked version of it if dry_run is set."""
    if dry_run:
        display = list(cmd)
        if mask_values:
            for i, arg in enumerate(display):
                for secret_value in mask_values:
                    if secret_value and secret_value in arg:
                        display[i] = arg.replace(secret_value, "<redacted>")
        print("  [dry-run] " + " ".join(display))
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({' '.join(cmd[:3])}...): {result.stderr.strip()}"
        )
    return result


def namespace_exists(namespace):
    result = subprocess.run(
        ["oc", "get", "project", namespace], capture_output=True, text=True
    )
    return result.returncode == 0


def generate_secret(length=20):
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))


def wait_for_setup_job(namespace, release, dry_run):
    if dry_run:
        print(f"  [dry-run] would wait for job/{release}-gitea-setup in {namespace}")
        return True

    for _ in range(JOB_POLL_ATTEMPTS):
        result = subprocess.run(
            [
                "oc", "get", "job", f"{release}-gitea-setup",
                "-n", namespace, "-o", "jsonpath={.status.succeeded}",
            ],
            capture_output=True, text=True,
        )
        if result.stdout.strip() == "1":
            return True
        failed = subprocess.run(
            [
                "oc", "get", "job", f"{release}-gitea-setup",
                "-n", namespace, "-o", "jsonpath={.status.failed}",
            ],
            capture_output=True, text=True,
        )
        if failed.stdout.strip():
            return False
        time.sleep(JOB_POLL_INTERVAL_SECONDS)
    return False


def get_route_url(namespace, route_name, dry_run):
    if dry_run:
        return f"https://{route_name}.example.com"
    result = subprocess.run(
        ["oc", "get", "route", route_name, "-n", namespace, "-o", "jsonpath={.spec.host}"],
        capture_output=True, text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return f"https://{result.stdout.strip()}"


def provision_team(team, cluster, dry_run):
    team_id = str(team["id"])
    display_name = team.get("displayName", f"Team {team_id}")
    namespace = f"{cluster['namespacePrefix']}-team-{team_id}"
    release = f"team-{team_id}"

    print(f"\n=== {display_name} ({namespace}) ===")
    outcome = TeamResult(team_id, display_name, namespace, release)

    try:
        if namespace_exists(namespace):
            print(f"  Namespace {namespace} already exists, skipping creation.")
        else:
            run(["oc", "new-project", namespace], dry_run)

        admin_password = generate_secret()
        webhook_secret = generate_secret()
        oc_token = os.environ.get("OC_TOKEN", "")
        if not dry_run and not oc_token:
            raise RuntimeError("OC_TOKEN environment variable is not set")

        helm_cmd = [
            "helm", "install", release, str(CHART_PATH),
            "-n", namespace,
            "-f", cluster["valuesFile"],
            "--set", f"openshift.apiServer={cluster['apiServer']}",
            "--set", f"openshift.token={oc_token}",
            "--set", f"gitea.admin.password={admin_password}",
            "--set", f"build.webhookSecret={webhook_secret}",
        ]
        run(helm_cmd, dry_run, mask_values=[oc_token, admin_password, webhook_secret])

        if not wait_for_setup_job(namespace, release, dry_run):
            raise RuntimeError("gitea-setup Job did not complete successfully")

        outcome.gitea_url = get_route_url(namespace, f"{release}-gitea", dry_run)
        outcome.dev_url = get_route_url(namespace, f"{release}-dev", dry_run)
        outcome.prod_url = get_route_url(namespace, f"{release}-prod", dry_run)
        outcome.admin_password = admin_password
        outcome.succeeded = True
        print(f"  Success: gitea={outcome.gitea_url} dev={outcome.dev_url} prod={outcome.prod_url}")
    except Exception as exc:
        outcome.error = str(exc)
        print(f"  FAILED: {outcome.error}")

    return outcome


def teardown_team(team, cluster, dry_run):
    team_id = str(team["id"])
    display_name = team.get("displayName", f"Team {team_id}")
    namespace = f"{cluster['namespacePrefix']}-team-{team_id}"
    release = f"team-{team_id}"

    print(f"\n=== Tearing down {display_name} ({namespace}) ===")
    run(["helm", "uninstall", release, "-n", namespace], dry_run, check=False)
    run(["oc", "delete", "project", namespace], dry_run, check=False)


def render_handout(outcome, clone_url):
    template = string.Template(HANDOUT_TEMPLATE_PATH.read_text())
    return template.substitute(
        display_name=outcome.display_name,
        gitea_url=outcome.gitea_url,
        dev_url=outcome.dev_url,
        prod_url=outcome.prod_url,
        clone_url=clone_url,
        admin_user=GITEA_ADMIN_USER,
        admin_password=outcome.admin_password,
    )


def write_outputs(config_path, results):
    output_dir = Path(__file__).resolve().parent / "output" / config_path.stem
    handouts_dir = output_dir / "handouts"
    handouts_dir.mkdir(parents=True, exist_ok=True)

    roster_rows = []
    for outcome in results:
        if not outcome.succeeded:
            roster_rows.append([
                outcome.team_id, outcome.display_name, outcome.namespace,
                "FAILED", "", "", "", outcome.error or "",
            ])
            continue

        clone_url = f"{outcome.gitea_url}/{GITEA_ADMIN_USER}/starter-flask-app.git"
        handout_text = render_handout(outcome, clone_url)
        handout_path = handouts_dir / f"team-{outcome.team_id}-handout.md"
        handout_path.write_text(handout_text)

        roster_rows.append([
            outcome.team_id, outcome.display_name, outcome.namespace,
            "OK", outcome.gitea_url, outcome.dev_url, outcome.prod_url,
            outcome.admin_password,
        ])

    header = ["team_id", "display_name", "namespace", "status", "gitea_url", "dev_url", "prod_url", "admin_password_or_error"]

    csv_path = output_dir / "roster.csv"
    with csv_path.open("w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        writer.writerows(roster_rows)

    md_path = output_dir / "roster.md"
    with md_path.open("w") as f:
        f.write("# Workshop Roster\n\n")
        f.write("| " + " | ".join(header) + " |\n")
        f.write("|" + "---|" * len(header) + "\n")
        for row in roster_rows:
            f.write("| " + " | ".join(str(c) for c in row) + " |\n")

    print(f"\nWrote roster to {md_path} and {csv_path}")
    print(f"Wrote {sum(1 for r in results if r.succeeded)} handout(s) to {handouts_dir}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("config", type=Path, help="Path to a teams YAML file (see teams.example.yaml)")
    parser.add_argument("--dry-run", action="store_true", help="Print planned oc/helm commands without executing")
    parser.add_argument("--teardown", action="store_true", help="Uninstall and delete namespaces for every team instead of provisioning")
    args = parser.parse_args()

    config = yaml.safe_load(args.config.read_text())
    cluster = config["cluster"]
    teams = config["teams"]

    if args.teardown:
        for team in teams:
            teardown_team(team, cluster, args.dry_run)
        return

    results = [provision_team(team, cluster, args.dry_run) for team in teams]

    succeeded = sum(1 for r in results if r.succeeded)
    print(f"\n=== Summary: {succeeded}/{len(results)} teams provisioned successfully ===")
    for r in results:
        if not r.succeeded:
            print(f"  FAILED: {r.display_name} ({r.namespace}): {r.error}")

    if not args.dry_run:
        write_outputs(args.config, results)

    if succeeded != len(results):
        sys.exit(1)


if __name__ == "__main__":
    main()
