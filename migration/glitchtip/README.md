# GlitchTip migration candidate — 2026-09-08

Status: prepared, not deployed. This directory is a reviewable candidate for
admission to the deployment owner. It does not replace the Sentry root Compose.
The Founder proposal is basic telemetry on the Linux VM. The choices below are
agent proposals; live deployment and retirement remain Founder buttons.

## Verified starting point

- Sentry HEAD before this cut: `73208ed5719288010d6299b56a182b387765100c`, master.
- Rendered configuration: 72 services, retention 90 days, nightly dependencies.
- Current Sentry containers: 72 total, 44 unhealthy, 19 exited.
- `colima ssh -- true`: `/bin/bash: Input/output error`; public health: HTTP 502.
  This proves a guest execution failure, not a filesystem repair diagnosis.
- Colima default: 8 CPU, 64 GiB assigned RAM, 100 GiB virtual disk.
  RAM assignment is not a measurement of physically resident host memory.
- Default also hosts `vc-workspace`, `div0-space` and other containers.
  Deleting default would destroy their storage too; inventory mounts and owners
  before any retirement decision. Stopped smoke profiles are separate scopes.
- Public DNS resolves to `213.160.77.173`. Reachable SSH alias is `libraxis-vm`
  (the proposed `vm-libraxis` alias does not resolve here). Host reports `ops`.
- VM `/etc/caddy/Caddyfile` already proxies this hostname to Dragon over tailnet.
  Expect a backend change, not DNS migration. Recheck the active Caddy config at
  cutover; the file alone does not prove the loaded routing generation.
- VM: about 13.6 GiB RAM available; root filesystem 78% used, 25 GiB available.
  Only portal containers appeared in the Docker inventory. The proposed existing
  Grafana/Loki/Kuma Compose owner has not been located. The discovered local
  `vetcoders-io/portal/deploy/vm` is a portal stack, not that telemetry stack.
- An earlier AICX session (2026-08-26, `9243fa64-6bc0-4df0-a464-9cf073a1151a`)
  reported successful recovery and ingest, but no backups. That is history, not
  current acceptance. Last successful ingest and a full week of outage remain
  unverified because the database cannot currently be queried reliably.

## Candidate configuration

Four services, separate web/worker, private database/cache and loopback HTTP for
host Caddy. Select immutable image digests for GlitchTip 6.2.5, PostgreSQL 18 and
Valkey 9 before deployment. No default passwords or floating production images.
PostgreSQL 18 uses the parent data mount shown in the upstream sample.

Create a mode-0600 environment file outside Git, for example
`/etc/glitchtip/runtime.env`, containing these keys (do not print its values):

- `GLITCHTIP_IMAGE`, `GLITCHTIP_POSTGRES_IMAGE`, `GLITCHTIP_VALKEY_IMAGE`: reviewed
  image references with `@sha256:...`, including the VM architecture.
- `GLITCHTIP_DB_PASSWORD`: random hexadecimal password (URL-safe).
- `GLITCHTIP_SECRET_KEY`: independent random hexadecimal secret.
- `GLITCHTIP_EMAIL_URL`: SMTP URL with URL-encoded credentials.
- `GLITCHTIP_FROM_EMAIL`: verified sender address.

Caddy integration assumes a free host loopback port 18000. Database and cache
have no host ports; Docker logs rotate. Persistent data includes database,
uploads and the task queue. This is not a measured RAM/disk sizing claim.
The VM disk budget must include growth, backups and image layers.

## Admission and cutover sequence

1. Locate the canonical VM deploy owner and its recovery/backup contract. Admit
   these services there, or explicitly adopt this standalone Compose project.
   Do not merge this file blindly into the unrelated portal Compose. Confirm
   port 18000 is free, image digests, SMTP, capacity and an off-host backup target.
2. After deployment approval, copy the admitted Compose to the VM and define:

   ```sh
   dc() { docker compose --env-file /etc/glitchtip/runtime.env -f /etc/glitchtip/compose.yml "$@"; }
   dc config --quiet
   dc pull
   dc up -d --wait glitchtip-postgres glitchtip-valkey
   dc run --rm glitchtip-web ./manage.py migrate
   dc run --rm glitchtip-web ./manage.py createsuperuser
   dc up -d glitchtip-web glitchtip-worker
   ```

   Migrate before starting both long-running services. Create the first account
   privately before exposing registration. Reach the private backend with an
   SSH tunnel; configure an organization and projects before public cutover.
3. Create projects for lbrx-services, vista-brain and Vista desktop. Inventory
   existing portal BE/FE emitters too: the old runbook lists six projects, not
   just three. Record explicit keep/retire decisions and new DSNs in private
   configuration. DSN migration changes both public key AND project ID; retaining
   the hostname does not preserve old DSNs or already shipped clients.
4. Test the private service, worker processing and backup/restore on disposable
   storage. Create an off-host database plus uploads backup and prove restore.
   Confirm the real SDK versions, error stacktraces, transaction support,
   releases/sourcemaps and any native crash requirements with actual emitters.
   Do not infer full Sentry compatibility from accepting an envelope.
5. Capture the current loaded Caddy route and back up the complete config.
   Replace only the Sentry site block with the candidate Caddyfile, validate the
   complete config, then reload after cutover approval. Keep the public hostname.
   Do not add duplicate site definitions or touch portal routes.
6. Apply complete DSNs to the actual Dragon observability config and Vista
   configuration, preserving rollback copies privately. Rebuild/release clients
   with embedded DSNs through their owner workflow; a server restart does not
   update installed desktop apps or browser bundles. Restart only the admitted
   API services through their supervisor. Disable unsupported telemetry only
   after mapping the SDK initialization and product requirements.

## Acceptance: a 60-second ingest probe, followed by real completion gates

For EACH retained project, use its real SDK/runtime to emit a unique synthetic
error containing no user data. Record timestamp, release/environment and returned
SDK event ID. Flush the SDK, then within 60 seconds find that exact event in the
GlitchTip UI or authenticated API, in the intended project, with stacktrace and
release intact. Sender acceptance or HTTP 200 alone is FAIL to prove ingest.
Check outside the tailnet for desktop/browser emitters. Verify one transaction
if basic performance is part of the adopted scope.

Separately verify alert email receipt, uptime alert/recovery, sourcemap or native
symbol handling where required, restart durability, cleanup/retention scheduling,
resource consumption under real traffic, and off-host restore. Email and retention
cannot honestly be certified by a generic 60-second health check. Keep event IDs,
recipient receipt and restore evidence in a private handoff. The existing
`scripts/vc-smoke.sh` is Sentry-specific and is not a GlitchTip acceptance gate.

## Rollback and retirement

Before cutover, the old route and DSNs are preserved. If acceptance fails, restore
those configurations where appropriate, but report that the old Sentry backend
is already broken: route rollback does not restore telemetry availability.
Keep GlitchTip data for diagnosis; do not run `down -v`. Restoring an earlier
GlitchTip image after schema changes requires its matching database backup.

Only after acceptance and an explicit data-loss/retirement decision: enumerate
all default-profile containers, mounts and volumes, preserve or migrate non-Sentry
workloads, identify both Colima autostart and the Sentry watchdog, and retire only
approved resources. No `colima delete` is supplied as an automatic final step.
Fsck requires an offline copy and the correct Linux filesystem tooling; no repair
was attempted. Disk savings must be measured as unique allocated blocks: `disk`
and `diffdisk` may alias the same file and must not be summed blindly. The earlier
82/88 GB estimates and 0.5 GB/day log growth are not certified by this snapshot.

## Upstream sources checked

- [Installation and configuration](https://glitchtip.com/documentation/install/):
  PostgreSQL plus optional Valkey, configurable retention and resource guidance.
- [Current Compose sample](https://glitchtip.com/assets/compose.sample.yml).
- [GlitchTip 6 changes](https://glitchtip.com/blog/2026-02-03-glitchtip-6-released/):
  django-vtasks replaces Celery; SERVER_ROLE selects web/worker; port 8000.
- [Versioned startup contract](https://gitlab.com/glitchtip/glitchtip-backend/-/blob/v6.2.5/bin/start.sh).

Local Compose rendering and Caddy syntax checks establish candidate syntax only.
Deployment, actual image startup, SDK ingest and backup restoration remain open.
