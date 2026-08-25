# Self-hosted Plaid over HTTPS

Feature: make self-hosted Maybe work with Plaid Link behind TLS termination (Cloudflare Tunnel), without requiring operators to reverse-engineer env vars.

## Increment 1 — PLAN (2026-08-25)

Plaid retired the `development` API environment. Self-hosted compose previously had no first-class Plaid/HTTPS knobs, so operators commonly set `PLAID_ENV=development` and hit opaque Link failures. This increment adds a boot-safe `PlaidEnvironment` helper (loaded from `lib/maybe_boot`, not autoloaded from `app/models`) that rejects `development`, defaults blank to `sandbox`, fails fast on half-configured credential pairs, passes `PLAID_*` through compose/`/.env.example`, and documents request-derived redirect URIs vs Sandbox localhost.

## Increment 1 — ADVERSARIAL REVIEW

Reviewer: [Plaid env review](23d45936-75c1-4654-b353-9ee3c3485d0d)

Resolved:
- Boot `NameError`: moved normalizer to `lib/maybe_boot/` (ignored by Zeitwerk) and `require` it from the initializer. Confirmed by Docker boot failure before the fix.
- Silent `development`→`sandbox` alias: rejected. `PLAID_ENV=development` now raises with a migration message so production keys cannot be pointed at sandbox by accident.
- Half-configured credentials: fail boot if only one of a US or EU pair is set.
- EU compose passthrough: added `PLAID_EU_*`.
- Docs claimed HTTPS was always required: split Sandbox localhost vs public-host rules. Documented that `redirect_uri` comes from the request Host, not `APP_DOMAIN`.

Deferred (logged, not dropped): generating canonical Plaid URLs from `APP_DOMAIN` / host authorization. That is a larger controller change and a separate increment.

## Increment 1 — FIX

See files under `lib/maybe_boot/`, `config/initializers/plaid.rb`, `test/models/plaid_environment_test.rb`.

Second review ([re-review](f539b065-6a9c-4647-a760-70c4820d4df1)): moved Plaid env assignment in `test/test_helper.rb` before boot; quoted Compose SSL interpolations; always validate `PLAID_ENV` even with Plaid off; added EU/secret-only tests and `.env.example` keys.

## Increment 2 — PLAN (2026-08-25)

Self-hosted Action Cable currently leaves `allowed_request_origins` commented out, so WebSocket upgrades fail when the browser Origin is the public hostname (or a LAN URL). This increment adds a boot-safe host parser that turns `APP_DOMAIN` into http/https origin allowlist entries, applies it in `production.rb`, and documents that `APP_DOMAIN` must match the hostname you browse. No Plaid URL rewriting in this pass.

## Increment 2 — ADVERSARIAL REVIEW

Reviewer: [Action Cable host review](b5d1e0a3-78a4-4382-8080-84f7bcd7325c)

Resolved: parse via `URI` so invalid ports and userinfo are rejected; keep non-default ports on origins; reject IPv6 rather than silently truncating; document that `APP_DOMAIN` must match the browsed hostname for `/cable`.

Deferred: Rails `config.hosts` / DNS rebinding (pre-existing); emitting only `https` origins when `force_ssl` is on (http origin still needed when proto headers disagree).

## Scope this loop will not touch

- Cloudflare token rotation (operator dashboard)
- Linking real banks in Plaid Link (operator click-through)
- Opening a GitHub PR
- Auto-running database migrations
