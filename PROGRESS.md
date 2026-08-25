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

## Increment 3 — PLAN (2026-08-25)

Plaid Link and webhook URLs still inherit the incoming `Host`, so a raw LAN request or spoofed proxy host can generate a redirect URI that does not match Plaid’s allowlist. This increment will make `PlaidItemsController` use validated `APP_DOMAIN` URL options when configured, force HTTPS for non-local hosts, preserve request-derived localhost behavior for Sandbox, and fail production boot on a malformed `APP_DOMAIN`. Controller and parser tests will cover canonical URLs, hostile Host headers, localhost fallback, and malformed configuration.

## Increment 3 — ADVERSARIAL REVIEW

Reviewers: [canonical URL review](af44332d-5235-4224-8ebf-884cc6ad9e08), [port-isolation re-review](8637f4d9-65ca-4266-a59a-393a83eecc74)

Resolved:
- Changed the Compose and env-template default to `localhost:3000`, so Sandbox’s allowlisted redirect keeps its port.
- Production Plaid now requires a valid `APP_DOMAIN`; blank configuration no longer falls back to a request-controlled Host.
- Added production-path coverage for US/EU webhooks and update-mode Link.
- Pinned localhost Sandbox to HTTP and public hosts to HTTPS.
- Split canonical host and port into explicit Rails URL options, including `port: nil`, so a spoofed request port cannot contaminate Plaid URLs.
- Updated hosting docs to describe `APP_DOMAIN` as the canonical Plaid URL source.

Verification: 28 tests, 70 assertions, zero failures; scoped RuboCop passes.

## Increment 4 — PLAN (2026-08-25)

Canonical Plaid URLs remove Host-header influence from Link, but production still accepts arbitrary HTTP Host headers because Rails host authorization is commented out. This increment will derive a port-free hostname from validated `APP_DOMAIN` and enable `config.hosts` for that hostname plus loopback health access. Tests will cover public hosts, ports, and malformed values; documentation will call out that direct LAN-IP access is intentionally rejected once a public domain is configured.

## Increment 4 — ADVERSARIAL REVIEW

Reviewer: [host authorization review](ae87f2eb-3263-4b9d-890d-e9018a622698)

Resolved:
- Removed global loopback hosts from the allowlist because a Host-rewriting proxy could otherwise bypass the protection.
- Restricted the loopback exception to `/up` and added a Compose healthcheck for that endpoint.
- Required valid `APP_DOMAIN` for every self-hosted production boot while preserving managed-mode host policy; production Plaid still requires a domain in either mode.
- Tightened `APP_DOMAIN` to a bare hostname/optional port and normalized mailer URL options.
- Added request-level `ActionDispatch::HostAuthorization` coverage for ports, sibling/hostile/forwarded hosts, and the path-limited health exception.
- Extracted and tested the production configuration policy for both self-hosted and managed modes.

Verification: 29 tests, 65 assertions, zero failures; scoped RuboCop and Compose validation pass. Docker production boot checks confirm blank self-host configuration fails, blank managed configuration without Plaid boots, and valid self-host configuration sets the exact host and mailer URL options.

## Increment 5 — PLAN (2026-08-25)

Action Cable currently allowlists both HTTP and HTTPS for every `APP_DOMAIN`, even though Plaid/public deployments are canonical HTTPS and localhost Sandbox is canonical HTTP. This increment will derive one exact WebSocket origin from the same canonical URL policy used by Plaid: HTTPS for public hosts, HTTP for loopback, with the configured port preserved. Tests will prove plaintext public origins and HTTPS localhost origins are rejected by the actual Host/Origin verification path.

## Increment 5 — ADVERSARIAL REVIEW

Reviewer: [Action Cable origin review](9cf9d870-146e-4fd1-b2ed-6e629b950298)

Resolved:
- Disabled Action Cable’s same-origin fallback for self-hosted production so the opposite scheme cannot bypass the canonical allowlist.
- Extracted `configure_action_cable!` and tested self-hosted wiring plus managed-mode non-interference.
- Added connection-level checks against Action Cable’s actual `allow_request_origin?` path for public HTTPS, localhost HTTP, wrong/missing origins, opposite schemes, non-default ports, and Cloudflare-style HTTPS forwarding over internal HTTP.
- Normalized explicit default ports (`:443` public, `:80` loopback), rejected port zero, and documented that public Cloudflare domains must not inherit Docker’s internal `:3000`.
- Replaced process-global Action Cable config mutation in tests with an isolated server instance.

Verification: 28 tests, 55 assertions, zero failures; scoped RuboCop passes.

## Increment 6 — PLAN (2026-08-25)

Self-hosted users currently get a persistent Postgres volume but no documented backup workflow, making account and linked-bank continuity dependent on an undeleted Docker volume. This increment will add a timestamped, compressed `pg_dump` procedure and a guarded restore procedure to the Docker hosting guide, including pre-restore backup and service-stop steps. It will not automate destructive restore operations or introduce a new dependency.

## Increment 6 — ADVERSARIAL REVIEW

Reviewer: [backup safety review](2f050e38-08f7-4068-887e-f5e0e7daec49)

Resolved:
- Replaced shell-dependent snippets with one explicit Bash heredoc using strict mode and private permissions.
- Stopped web/worker once so the Postgres dump and local storage copy share a timestamp; cleanup always attempts restart.
- Verified the custom dump contains Maybe `users`/`accounts` table data without a SIGPIPE-prone live pipeline.
- Preserved verified database output when local storage copy fails and removed only partial storage.
- Recorded PostgreSQL version and Compose image metadata without writing secrets into the backup.
- Mounted `app-storage` into the worker and documented migration of any legacy worker-overlay files.
- Corrected secret guidance: existing installs must preserve their current key rather than rotate it underneath ciphertext.

Changed from the initial plan after review: a generic destructive restore command cannot be made safe across arbitrary schema/image/PostgreSQL versions in a copy-paste guide. It was intentionally removed in favor of rehearsing a matching database-and-storage restore on a disposable VM first. This is a documented scope decision, not a silently dropped review issue.

Residual operational limitations accepted: some Compose versions may not copy from a stopped container; in that case the verified DB dump is retained and the command exits non-zero. Local storage is copied but not checksummed, and restoration remains an operator-tested runbook.

Verification: Compose configuration validates; the documented TOC regex was checked against a real Maybe custom-format test dump.

## Increment 7 — PLAN (2026-08-25)

All scoped implementation tasks are committed. This final increment is release-readiness verification across the complete branch: full Rails tests, repository-wide RuboCop, ERB lint, Brakeman, and Compose validation. Any failure caused by this branch will be fixed and adversarially reviewed before a final verification commit; unrelated baseline failures will be recorded with evidence rather than hidden.

## Increment 7 — ADVERSARIAL REVIEW

Reviewer: [final branch audit](53fbd6ef-fe38-4d49-a8d5-30f9659be998)

Resolved four release blockers:
- Preserved image-only upgrade compatibility by leaving Host/Action Cable policy unchanged when legacy installs omit `APP_DOMAIN`; new Compose also defaults it to blank.
- Separated LAN/public Cable scheme policy: public hosts remain HTTPS even when container-facing SSL flags are false, while loopback/RFC1918/`.local`/dotless LAN names may use HTTP.
- Rejected `PLAID_ENV=production` with loopback `APP_DOMAIN`.
- Upgraded backup verification from TOC inspection to a complete disposable-database restore plus expected-table queries.

Verification:
- Full Rails suite: 952 tests, 5,818 assertions, zero failures/errors, 9 skips.
- Repository RuboCop: pass.
- ERB lint: 332 files, pass.
- Compose validation: pass.
- Brakeman scan completed with zero scanner errors and one pre-existing warning: Rails 7.2.2.1 reached end of support on 2026-08-09.
- Docker production boot checks cover legacy blank domain, LAN HTTP, public HTTPS with SSL env flags off, and Plaid production rejecting localhost.
- Disposable restore flags were executed successfully against a real Maybe test dump.

Deferred with rationale: upgrading Rails and Brakeman is a repository-wide dependency increment unrelated to this self-host/Plaid branch. `bin/brakeman` currently fails its version gate because the lockfile has Brakeman 7.1.0 instead of 8.0.6; `bundle exec brakeman --no-exit-on-warn` was used to complete the actual scan. This baseline security-maintenance work should be handled separately rather than hidden inside the feature branch.

## Scope this loop will not touch

- Cloudflare token rotation (operator dashboard)
- Linking real banks in Plaid Link (operator click-through)
- Opening a GitHub PR
- Auto-running database migrations
