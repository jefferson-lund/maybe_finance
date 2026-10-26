#!/usr/bin/env bash
# Per-boot service reconciliation for the Maybe Rails app.
# Starts PostgreSQL and Redis and waits until the database is ready.
set -euo pipefail

PG_VER="$(ls /usr/lib/postgresql 2>/dev/null | head -1 || true)"

sudo service postgresql start 2>/dev/null || sudo pg_ctlcluster "${PG_VER}" main start 2>/dev/null || true
sudo service redis-server start 2>/dev/null || sudo redis-server --daemonize yes 2>/dev/null || true

for _ in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then break; fi
  sleep 1
done

echo "PostgreSQL and Redis are up."
