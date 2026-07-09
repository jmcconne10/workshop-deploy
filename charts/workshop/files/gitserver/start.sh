#!/bin/bash
# Git server entrypoint. All configuration comes from environment variables set by
# the Deployment (REPO_NAME, OC_API_SERVER, BUILD_NAMESPACE, DEV_BC, PROD_BC,
# WEBHOOK_SECRET, MEMBER_COUNT, OC_TOKEN) so this file needs no Helm templating.
set -e

GIT_ROOT=/var/git
export GIT_PROJECT_ROOT="${GIT_ROOT}"
REPO="${REPO_NAME}.git"

DEV_WEBHOOK_URL="${OC_API_SERVER}/apis/build.openshift.io/v1/namespaces/${BUILD_NAMESPACE}/buildconfigs/${DEV_BC}/webhooks/${WEBHOOK_SECRET}/generic"
PROD_WEBHOOK_URL="${OC_API_SERVER}/apis/build.openshift.io/v1/namespaces/${BUILD_NAMESPACE}/buildconfigs/${PROD_BC}/webhooks/${WEBHOOK_SECRET}/generic"

cd "${GIT_ROOT}"

if [ ! -d "${REPO}" ]; then
  echo "[gitserver] initializing bare repo ${REPO}"
  git init --bare "${REPO}"
  git -C "${REPO}" symbolic-ref HEAD refs/heads/main
  git -C "${REPO}" config http.receivepack true
  git -C "${REPO}" config http.uploadpack true

  echo "[gitserver] installing post-receive hook (token + webhook URLs baked in)"
  cat > "${REPO}/hooks/post-receive" <<HOOK
#!/bin/bash
# Fires the matching OpenShift BuildConfig generic webhook on push. This replaces
# Gitea's webhook: push to dev -> dev build, push to main -> prod build, member
# branches -> no build (mirrors the branch_filter behavior of the old setup).
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
fi

echo "[gitserver] configuring httpd git-http-backend on 8080"
cat > /etc/httpd/conf.d/git.conf <<'CONF'
Listen 8080
SetEnv GIT_PROJECT_ROOT /var/git
SetEnv GIT_HTTP_EXPORT_ALL
ScriptAlias /git/ /usr/libexec/git-core/git-http-backend/
<Directory "/usr/libexec/git-core">
  Require all granted
  Options +ExecCGI
</Directory>
CONF
sed -i 's/^Listen 80$/#Listen 80/' /etc/httpd/conf/httpd.conf || true

echo "[gitserver] starting httpd"
exec httpd -DFOREGROUND
