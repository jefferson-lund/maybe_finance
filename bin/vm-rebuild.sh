#!/usr/bin/env bash
# Rebuild and restart the self-hosted Maybe app on this VM from /opt/maybe.
#
# Typical use from the VM:
#   /opt/maybe/rebuild.sh --from-git
#   /opt/maybe/rebuild.sh --from-git --ref f2d6c20c
#
# Typical use from your Mac (current checkout as a tarball):
#   git archive --format=tar HEAD | gzip -9 | ssh root@pve-node1.tail989d76.ts.net \
#     'ssh root@192.168.4.31 /opt/maybe/rebuild.sh --from-stdin'
#
# Rebuild whatever is already in /opt/maybe/src:
#   /opt/maybe/rebuild.sh
set -euo pipefail

APP_DIR="/opt/maybe"
SRC_DIR="${APP_DIR}/src"
COMPOSE_DIR="${APP_DIR}"
DEFAULT_GIT_URL="https://github.com/jefferson-lund/maybe_finance.git"
DEFAULT_REF="self-host-plaid-https"
DEFAULT_IMAGE="maybe-fork:household-budget"
HEALTH_HOST="maybe.aj-data.com"

from_git=false
from_stdin=false
skip_backup=false
skip_migrate=false
skip_verify=false
git_url="${DEFAULT_GIT_URL}"
git_ref="${DEFAULT_REF}"
image=""

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \?//'
  echo
  echo "Options:"
  echo "  --from-git          Clone --ref from --url into ${SRC_DIR}, then rebuild"
  echo "  --from-stdin        Read a gzipped git-archive tarball from stdin"
  echo "  --url URL           Git remote (default: ${DEFAULT_GIT_URL})"
  echo "  --ref REF           Branch, tag, or commit (default: ${DEFAULT_REF})"
  echo "  --image NAME        Docker image tag (default: MAYBE_IMAGE or ${DEFAULT_IMAGE})"
  echo "  --skip-backup       Do not dump Postgres before rebuilding"
  echo "  --skip-migrate      Do not run bin/rails db:migrate"
  echo "  --skip-verify       Do not restore the dump into a disposable database"
  echo "  -h, --help          Show this help"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --from-git) from_git=true ;;
    --from-stdin) from_stdin=true ;;
    --url) git_url="${2:?}"; shift ;;
    --ref) git_ref="${2:?}"; shift ;;
    --image) image="${2:?}"; shift ;;
    --skip-backup) skip_backup=true ;;
    --skip-migrate) skip_migrate=true ;;
    --skip-verify) skip_verify=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "${from_git}" = true ] && [ "${from_stdin}" = true ]; then
  echo "Choose only one of --from-git or --from-stdin" >&2
  exit 2
fi

cd "${COMPOSE_DIR}"

compose() {
  docker compose "$@"
}

compose_no_stdin() {
  docker compose "$@" </dev/null
}

load_image() {
  if [ -n "${image}" ]; then
    return
  fi
  if [ -f "${APP_DIR}/.env" ]; then
    image="$(awk -F= '$1=="MAYBE_IMAGE" {print substr($0, index($0, "=")+1); exit}' "${APP_DIR}/.env" | tr -d '"' | tr -d "'")"
  fi
  if [ -z "${image}" ]; then
    image="${DEFAULT_IMAGE}"
  fi
}

ensure_src() {
  if [ ! -f "${SRC_DIR}/Dockerfile" ]; then
    echo "No Dockerfile at ${SRC_DIR}/Dockerfile" >&2
    exit 1
  fi
}

replace_src_from_dir() {
  local incoming="$1"
  if [ ! -f "${incoming}/Dockerfile" ]; then
    echo "Incoming source is missing Dockerfile" >&2
    exit 1
  fi
  rm -rf "${SRC_DIR}"
  mv "${incoming}" "${SRC_DIR}"
  chmod -R a+rX "${SRC_DIR}"
}

refresh_from_git() {
  local tmp
  tmp="$(mktemp -d "${APP_DIR}/src.incoming.XXXXXX")"
  echo "=== fetching ${git_url} (${git_ref}) ==="
  git -C "${tmp}" init --quiet
  git -C "${tmp}" remote add origin "${git_url}"
  git -C "${tmp}" fetch --depth 1 origin "${git_ref}"
  git -C "${tmp}" checkout --quiet FETCH_HEAD
  rm -rf "${tmp}/.git"
  replace_src_from_dir "${tmp}"
}

refresh_from_stdin() {
  if [ -t 0 ]; then
    echo "--from-stdin needs a gzipped tar on stdin" >&2
    exit 2
  fi
  local tmp
  tmp="$(mktemp -d "${APP_DIR}/src.incoming.XXXXXX")"
  echo "=== extracting source tarball ==="
  gzip -dc | tar -x -C "${tmp}"
  replace_src_from_dir "${tmp}"
}

backup_database() {
  local ts dump toc verify_db
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  mkdir -p "${APP_DIR}/backups"
  chmod 700 "${APP_DIR}/backups"
  dump="${APP_DIR}/backups/maybe-${ts}.dump"

  echo "=== stopping web and worker ==="
  compose_no_stdin stop web worker

  echo "=== dumping database to ${dump} ==="
  (
    umask 077
    compose_no_stdin exec -T db sh -c 'pg_dump --format=custom --username="$POSTGRES_USER" --dbname="$POSTGRES_DB"' > "${dump}"
  )
  chmod 600 "${dump}"
  test -s "${dump}"
  ls -lh "${dump}"

  if [ "${skip_verify}" = true ]; then
    echo "=== skipping restore verification ==="
    return
  fi

  toc="$(mktemp)"
  verify_db="verify_rebuild_${ts}"
  compose exec -T db pg_restore --list < "${dump}" > "${toc}"
  if ! grep -Eq 'TABLE DATA public (users|accounts) ' "${toc}"; then
    echo "Dump is missing users or accounts table data: ${dump}" >&2
    rm -f "${toc}"
    exit 1
  fi
  rm -f "${toc}"

  echo "=== verifying dump by restoring into ${verify_db} ==="
  compose_no_stdin exec -T db sh -c 'dropdb --if-exists --username="$POSTGRES_USER" "'"${verify_db}"'"'
  compose_no_stdin exec -T db sh -c 'createdb --username="$POSTGRES_USER" "'"${verify_db}"'"'
  compose exec -T db sh -c 'pg_restore --exit-on-error --single-transaction --no-owner --no-privileges --username="$POSTGRES_USER" --dbname="'"${verify_db}"'"' < "${dump}"
  compose_no_stdin exec -T db sh -c 'psql --username="$POSTGRES_USER" --dbname="'"${verify_db}"'" --set=ON_ERROR_STOP=1 --command="SELECT count(*) FROM users; SELECT count(*) FROM accounts; SELECT count(*) FROM entries;"'
  compose_no_stdin exec -T db sh -c 'dropdb --username="$POSTGRES_USER" "'"${verify_db}"'"'
  echo "=== backup verified ==="
}

build_image() {
  local sha=""
  if [ -n "${git_ref}" ]; then
    sha="${git_ref}"
  fi
  echo "=== stopping web and worker for the build ==="
  compose_no_stdin stop web worker || true
  echo "=== building ${image} ==="
  chmod -R a+rX "${SRC_DIR}"
  docker build --build-arg "BUILD_COMMIT_SHA=${sha}" -t "${image}" "${SRC_DIR}"
}

ensure_image_env() {
  if grep -q '^MAYBE_IMAGE=' "${APP_DIR}/.env"; then
    sed -i "s|^MAYBE_IMAGE=.*|MAYBE_IMAGE=${image}|" "${APP_DIR}/.env"
  else
    printf '\nMAYBE_IMAGE=%s\n' "${image}" >> "${APP_DIR}/.env"
  fi
}

migrate() {
  echo "=== migrating ==="
  compose_no_stdin run --rm --no-deps web ./bin/rails db:migrate
}

start_app() {
  echo "=== starting web and worker ==="
  compose_no_stdin up -d web worker
}

healthcheck() {
  local i code
  echo "=== health check ==="
  for i in $(seq 1 30); do
    code="$(curl -s -o /dev/null -w '%{http_code}' -H "Host: ${HEALTH_HOST}" http://localhost:3000/up || true)"
    echo "attempt ${i}: /up -> ${code}"
    if [ "${code}" = "200" ]; then
      compose_no_stdin ps
      return 0
    fi
    sleep 3
  done
  echo "App did not become healthy" >&2
  compose_no_stdin logs web --tail 80 || true
  exit 1
}

load_image
if [ "${from_git}" = true ]; then
  refresh_from_git
elif [ "${from_stdin}" = true ]; then
  refresh_from_stdin
fi
ensure_src

if [ "${skip_backup}" = true ]; then
  echo "=== skipping backup ==="
  compose_no_stdin stop web worker || true
else
  backup_database
fi

build_image
ensure_image_env

if [ "${skip_migrate}" = true ]; then
  echo "=== skipping migrate ==="
else
  migrate
fi

start_app
healthcheck
echo "=== rebuild complete (${image}) ==="
