#!/usr/bin/env bash
# Repository bootstrap for the Maybe Cloud Agent environment.
# Runs after the repository is checked out. Installs Ruby/JS dependencies and
# prepares the database. Must be idempotent and terminate (no long-lived
# processes are started here).
set -euo pipefail

export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Ensure the pinned Ruby (from .ruby-version) is installed and active.
if command -v mise >/dev/null 2>&1; then
  mise install
fi

# Local development env file (gitignored). Points the app at the local
# PostgreSQL and Redis started by start.sh. Uses a throwaway dev DB password;
# local connections are configured for trust auth.
if [ ! -f .env.local ]; then
  echo "== Writing .env.local =="
  cat > .env.local <<'EOF'
SELF_HOSTED=false
DB_HOST=127.0.0.1
DB_PORT=5432
POSTGRES_USER=postgres
POSTGRES_PASSWORD=postgres
REDIS_URL=redis://localhost:6379/0
EOF
fi

# Bring up services so the database can be prepared.
./.cursor/start.sh

echo "== Installing Ruby dependencies =="
gem install bundler --conservative
bundle check || bundle install

echo "== Installing JavaScript dependencies =="
npm install

echo "== Preparing database =="
bin/rails db:prepare

echo "== Clearing logs and tempfiles =="
bin/rails log:clear tmp:clear || true

echo "== Install complete =="
