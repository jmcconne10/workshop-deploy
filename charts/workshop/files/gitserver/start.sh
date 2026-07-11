#!/bin/bash
# Git server entrypoint. All configuration comes from environment variables set by
# the Deployment (REPO_NAME, OC_API_SERVER, BUILD_NAMESPACE, DEV_BC, PROD_BC,
# WEBHOOK_SECRET, MEMBER_COUNT, OC_TOKEN, GITSERVER_SERVICE) so this file needs no
# Helm templating.
set -e

GIT_ROOT=/var/git
export GIT_PROJECT_ROOT="${GIT_ROOT}"
REPO="${REPO_NAME}.git"

DEV_WEBHOOK_URL="${OC_API_SERVER}/apis/build.openshift.io/v1/namespaces/${BUILD_NAMESPACE}/buildconfigs/${DEV_BC}/webhooks/${WEBHOOK_SECRET}/generic"
PROD_WEBHOOK_URL="${OC_API_SERVER}/apis/build.openshift.io/v1/namespaces/${BUILD_NAMESPACE}/buildconfigs/${PROD_BC}/webhooks/${WEBHOOK_SECRET}/generic"
SELF_REFS_URL="http://${GITSERVER_SERVICE}:8080/git/${REPO}/info/refs?service=git-upload-pack"

fire_webhook() {  # $1 = url, $2 = label
  code=$(curl -s -o /dev/null -w '%{http_code}' -k -X POST \
    -H "Authorization: Bearer ${OC_TOKEN}" -H "Content-Type: application/json" -d '{}' \
    "$1" 2>/dev/null || echo 000)
  echo "[gitserver] triggered initial $2 build (HTTP ${code})"
}

# --- Start httpd first, so a build can clone the moment it is triggered ---
echo "[gitserver] configuring httpd git-http-backend on 8080"
cat > /etc/httpd/conf.d/git.conf <<'CONF'
Listen 8080
SetEnv GIT_PROJECT_ROOT /var/git
SetEnv GIT_HTTP_EXPORT_ALL
ScriptAlias /git/ /usr/libexec/git-core/git-http-backend/

# Require authentication for PUSH only. Flag CLONE/FETCH requests (git-upload-pack)
# as anonymous-OK: the GET .../info/refs?service=git-upload-pack handshake and the
# POST .../git-upload-pack. Everything else (i.e. git-receive-pack = push) falls
# through to valid-user. This keeps anonymous clone working for the S2I BuildConfigs.
SetEnvIfExpr "%{QUERY_STRING} =~ /service=git-upload-pack/ || %{REQUEST_URI} =~ m#/git-upload-pack$#" GIT_ANON

<Directory "/usr/libexec/git-core">
  Options +ExecCGI
  AuthType Basic
  AuthName "Git push (workshop credentials)"
  AuthUserFile /etc/git-secret/htpasswd
  <RequireAny>
    # anonymous for clone/fetch...
    Require env GIT_ANON
    # ...and a valid user for pushes (git prompts for the credential on the 401)
    Require valid-user
  </RequireAny>
</Directory>
CONF
sed -i 's/^Listen 80$/#Listen 80/' /etc/httpd/conf/httpd.conf || true
trap 'kill $(jobs -p) 2>/dev/null' TERM INT
httpd -DFOREGROUND &

cd "${GIT_ROOT}"
if [ ! -d "${REPO}" ]; then
  echo "[gitserver] initializing bare repo ${REPO}"
  git init --bare "${REPO}"
  git -C "${REPO}" symbolic-ref HEAD refs/heads/main
  git -C "${REPO}" config http.receivepack true
  git -C "${REPO}" config http.uploadpack true

  # Seed content BEFORE installing the post-receive hook, so these seed pushes do
  # not fire the webhook (the server / Service endpoint may not be ready yet, which
  # would make a triggered build fail to clone).
  echo "[gitserver] seeding starter app + branches"
  SEED=$(mktemp -d)
  git clone "${GIT_ROOT}/${REPO}" "${SEED}"
  cd "${SEED}"
  git config user.email "workshop@example.com"
  git config user.name "workshop"
  git checkout -b main 2>/dev/null || true
  cp /starter/app.py app.py
  cp /starter/requirements.txt requirements.txt
  git add .
  git commit -m "seed starter flask app"
  git push origin main
  git checkout -b dev
  git push origin dev
  if [ "${MEMBER_COUNT:-1}" -ge 2 ]; then
    i=1
    while [ "${i}" -le "${MEMBER_COUNT}" ]; do
      echo "[gitserver] creating member${i} branch"
      git branch "member${i}" dev
      git push origin "member${i}"
      i=$((i + 1))
    done
  fi
  cd "${GIT_ROOT}"

  echo "[gitserver] installing post-receive hook (token + webhook URLs baked in)"
  cat > "${REPO}/hooks/post-receive" <<HOOK
#!/bin/bash
# Fires the matching OpenShift BuildConfig generic webhook on push. This replaces
# Gitea's webhook: push to dev -> dev build, push to main -> prod build, member
# branches -> no build.
TOKEN='${OC_TOKEN}'
DEV_URL='${DEV_WEBHOOK_URL}'
PROD_URL='${PROD_WEBHOOK_URL}'
while read oldrev newrev refname; do
  branch="\${refname#refs/heads/}"
  case "\${branch}" in
    dev)         url="\${DEV_URL}" ;;
    main|master) url="\${PROD_URL}" ;;
    *) echo "post-receive: no build trigger for branch \${branch}"; continue ;;
  esac
  echo "post-receive: push to \${branch} -> firing OpenShift build"
  code=\$(curl -s -o /tmp/wh.out -w '%{http_code}' -k -X POST \
    -H "Authorization: Bearer \${TOKEN}" -H "Content-Type: application/json" -d '{}' \
    "\${url}" || echo 000)
  echo "post-receive: webhook returned HTTP \${code}"
done
HOOK
  chmod +x "${REPO}/hooks/post-receive"

  # Trigger the initial dev+prod builds only once the repo is reachable over the
  # Service (i.e. this pod is Ready and has a Service endpoint), so the builds
  # don't race ahead of the server and fail to clone.
  echo "[gitserver] waiting for the repo to be reachable via the Service..."
  code=000
  for _ in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' "${SELF_REFS_URL}" 2>/dev/null || echo 000)
    [ "${code}" = "200" ] && break
    sleep 2
  done
  echo "[gitserver] Service reachability check returned HTTP ${code}; triggering initial builds"
  fire_webhook "${PROD_WEBHOOK_URL}" "prod"
  fire_webhook "${DEV_WEBHOOK_URL}" "dev"
fi

echo "[gitserver] ready; serving httpd"
wait
