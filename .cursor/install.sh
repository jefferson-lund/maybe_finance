#!/usr/bin/env bash
# Idempotent repository setup for the Maybe Rails app.
# Prepares dependencies and the development database. Safe to run repeatedly.
set -euo pipefail

cd "$(dirname "$0")/.."

# Detect the installed PostgreSQL major version.
PG_VER="$(ls /usr/lib/postgresql 2>/dev/null | head -1 || true)"

echo "== Ensuring PostgreSQL cluster exists =="
if [ -n "${PG_VER}" ] && [ ! -d "/etc/postgresql/${PG_VER}/main" ]; then
  sudo pg_createcluster "${PG_VER}" main
fi

echo "== Starting PostgreSQL & Redis =="
sudo service postgresql start 2>/dev/null || sudo pg_ctlcluster "${PG_VER}" main start 2>/dev/null || true
sudo service redis-server start 2>/dev/null || sudo redis-server --daemonize yes 2>/dev/null || true

echo "== Waiting for PostgreSQL =="
for _ in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then break; fi
  sleep 1
done

echo "== Ensuring 'postgres' role password =="
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'postgres';" >/dev/null 2>&1 || true

echo "== Writing .env.local (development defaults) =="
cat > .env.local <<'ENVEOF'
SELF_HOSTED=false
DB_HOST=127.0.0.1
DB_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
REDIS_URL=redis://localhost:6379/1
ENVEOF

echo "== Installing Ruby gems =="
bundle install

echo "== Installing JS dependencies =="
npm install

echo "== Preparing database (create + migrate + seed) =="
bin/rails db:prepare

echo "== Install complete =="
