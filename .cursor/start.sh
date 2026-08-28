#!/usr/bin/env bash
# Per-boot runtime initialization for the Maybe Cloud Agent environment.
# Starts the PostgreSQL and Redis daemons and reconciles the database schema.
# Must be idempotent: safe to run on every boot and when services are already up.
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "== Starting PostgreSQL =="
sudo pg_ctlcluster 16 main start 2>/dev/null || true
for i in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
    echo "PostgreSQL is ready"
    break
  fi
  sleep 1
done

echo "== Starting Redis =="
if ! redis-cli ping >/dev/null 2>&1; then
  sudo service redis-server start 2>/dev/null || redis-server --daemonize yes
fi
redis-cli ping >/dev/null 2>&1 && echo "Redis is ready"

# Reconcile the database schema for the checked-out branch. db:prepare creates
# the databases if needed and applies any pending migrations. It is idempotent.
if command -v bundle >/dev/null 2>&1 && [ -f Gemfile.lock ]; then
  echo "== Preparing database =="
  bin/rails db:prepare
fi
