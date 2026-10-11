# Nextcloud 34 Files and Collaboration — composer spec

| Field | Value |
|---|---|
| Listing name | **Nextcloud 34 Files and Collaboration** (version label `34` = Nextcloud server major; Nextcloud writes versions without "v"; image tag `34.0.4-apache`) |
| Description | Your own cloud for files, calendars and contacts, with Redis and cron. (70 chars) |
| Category | Storage |
| Tags | nextcloud, file-sharing, cloud-storage, calendar, contacts, dropbox-alternative |
| Base market template | `self-host-nextcloud` (32 projects): `nextcloud:apache` + Postgres + Redis, MPM workaround in the start command, volume on `/var/www/html`, `OVERWRITEPROTOCOL`/`OVERWRITECLIURL`, trusted domain from `RAILWAY_PUBLIC_DOMAIN`. Kept: that service set and the official image's own environment variables. Fixed: admin credentials left empty (web installer exposed to the internet), no cron (background jobs fall back to AJAX), no healthcheck, unpinned image, MPM fix in a fragile start command, trusted domains only set at install. Also reviewed `nextcloud` (112 projects; Bucket as primary storage with a hard-coded `storage.railway.app` host, no Redis, no cron, `NEXTCLOUD_UPDATE=1`) and `LddOJ1` (405 projects; SQLite, placeholder S3 values). |
| Upstream checked | `nextcloud/docker` (AGPL-3.0) `34/apache/Dockerfile`, `entrypoint.sh`, `cron.sh`, `upgrade.exclude`, `config/*.config.php` (redis, s3, reverse-proxy, smtp, apcu, pretty URLs), `README.md`, `versions.json`; Nextcloud server releases (`v35.0.1` latest, `34.0.4` = Docker `stable`/`production` alias). Pinned 2026-10-11. |

## Architecture

```
 browsers, desktop/mobile sync clients, CalDAV/CardDAV ──HTTPS──► Nextcloud (Apache + PHP 8.5 :80, volume /var/www/html)
                                                                      │   └─ busybox crond → cron.php every 5 min (same container)
                                          ┌───────────────────────────┼──────────────────────────────┐
                                          ▼                           ▼                              ▼
                                     Postgres 18             Redis (locking, cache,      Railway Bucket (optional primary
                                                             PHP sessions)               storage, NEXTCLOUD_PRIMARY_STORAGE=bucket)
```

### Cron decision

Nextcloud's background jobs (file scans, trash/version expiry, previews, notifications, calendar reminders) need `cron.php` every 5 minutes with the same code, `config.php` and data as the web server. On Railway a volume belongs to one service, so a separate cron service cannot see `/var/www/html`. Options considered:

| Option | Verdict |
|---|---|
| Separate cron service (`cronSchedule`) | Not possible: no access to the app volume (`config.php`, data). |
| Webcron (an external job calling `/cron.php` over HTTP) | Works, but jobs run inside a web request (PHP/Apache time limits, public endpoint), Nextcloud ranks it below system cron. |
| AJAX (default without cron) | Jobs only run while someone has the web UI open. Unreliable. |
| **System cron inside the app container** (chosen) | Nextcloud's recommended mode, using the crontab and `busybox` the official image already ships (`/var/spool/cron/crontabs/www-data`, same as upstream's `cron.sh`). `railway-entrypoint.sh` starts `busybox crond -f` in a restart loop before handing over to the official entrypoint; jobs run as `www-data` with the same environment (Redis, S3, overwrite settings). Background-job mode is set to `cron` after install and on every start. |

### Primary storage

- **Default `volume`**: files live in `/var/www/html/data` on the service volume. The Hobby plan caps a volume at **5 GB** (the Nextcloud code and apps take ~0.9 GB of it), so plan on ~4 GB of files; Pro volumes are larger.
- **`bucket`**: set `NEXTCLOUD_PRIMARY_STORAGE=bucket` **before the first deploy**. The start script converts the Bucket credentials into Nextcloud's `OBJECTSTORE_S3_*` variables (host and port parsed from `ENDPOINT`, virtual-hosted addressing, no auto-create), which the image's `s3.config.php` reads on every request and cron run. Files, previews and app data then live in the Bucket ($0.015/GB-month, no size cap); the volume keeps only code, config and logs.
- The mode is written to `config/.railway-primary-storage` after installation and **wins over later variable changes** (switching would hide every existing file); a warning is logged if the variable differs.

## Services

| Service | Source | Start / pre-deploy | Public | Healthcheck | Volume | Restart | Replicas |
|---|---|---|---|---|---|---|---|
| `Nextcloud` | repo `/services/nextcloud` (FROM `nextcloud:34.0.4-apache`) | `railway-entrypoint.sh` → official `/entrypoint.sh apache2-foreground` (copy, auto-install or `occ upgrade`, hooks) | domain → 80 | `/status.php`, 900 s | `/var/www/html` | ALWAYS | 1 (volume) |
| `Postgres` | `ghcr.io/railwayapp-templates/postgres-ssl:18` (from `_railway-base/postgres.json`) | image | — | — | `/var/lib/postgresql/data` | ON_FAILURE ×10 | 1 |
| `Redis` | `redis:8.2` (from `_railway-base/redis.json`) | base start command | — | — | `/data` | ON_FAILURE ×10 | 1 |
| `Bucket` | Railway Bucket | — | — | — | — | — | — |

No pre-deploy step: the install/upgrade logic lives in the official entrypoint and needs the volume, which is not mounted during Railway's pre-deploy phase. The start script waits up to 15 minutes for Postgres and Redis before the official entrypoint runs, so a slow database cannot interrupt the automatic installation halfway (a half-finished install would otherwise leave the public web installer open).

## Variables

**`Nextcloud`**

| Variable | Default | Notes |
|---|---|---|
| `PORT` | `80` | |
| `NEXTCLOUD_ADMIN_USER` / `NEXTCLOUD_ADMIN_PASSWORD` | `admin` / `${{secret(24)}}` | Automatic installation on first start. |
| `NEXTCLOUD_TRUSTED_DOMAINS` | `${{RAILWAY_PUBLIC_DOMAIN}}` | Space-separated. The `before-starting` hook rewrites `trusted_domains` = `localhost`, `healthcheck.railway.app` (Railway's healthcheck Host, otherwise HTTP 400) and this list on every start. |
| `POSTGRES_HOST/DB/USER/PASSWORD` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}`, `PGDATABASE`, `PGUSER`, `PGPASSWORD` | Install-time only (Nextcloud then uses its own `oc_admin` DB user). |
| `REDIS_HOST`, `REDIS_HOST_PORT`, `REDIS_HOST_PASSWORD` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}`, `6379`, `${{Redis.REDIS_PASSWORD}}` | Enables `memcache.distributed`, `memcache.locking` (transactional file locking) and Redis PHP sessions (image logic). APCu stays the local cache. |
| `OVERWRITEPROTOCOL`, `OVERWRITECLIURL` | `https`, `https://${{RAILWAY_PUBLIC_DOMAIN}}` | No `OVERWRITEHOST`, so custom domains work without rewriting. |
| `TRUSTED_PROXIES`, `FORWARDED_FOR_HEADERS` | `100.64.0.0/10 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 fd00::/8`, `HTTP_X_FORWARDED_FOR` | Real client IPs for brute-force protection; Apache `remoteip` also trusts 100.64/10 and fd00::/8. |
| `NEXTCLOUD_INIT_HTACCESS` | `true` | Pretty URLs. |
| `NEXTCLOUD_PRIMARY_STORAGE` | `volume` | `volume` or `bucket` (see above). |
| `BUCKET_NAME/ENDPOINT/REGION/ACCESS_KEY_ID/SECRET_ACCESS_KEY` | `${{Bucket.*}}` | Used only in `bucket` mode. |
| `BUCKET_FORCE_PATH_STYLE` | `false` | |
| `NEXTCLOUD_INSTALL_APPS` | `calendar contacts` | Installed from the app store after the first install (the listing promises calendars and contacts; they are not bundled with the server). |
| `NEXTCLOUD_DEFAULT_PHONE_REGION` | empty | Optional, clears an admin warning. |
| `NEXTCLOUD_MAINTENANCE_WINDOW_START` | `1` | UTC hour; clears an admin warning. |
| `NEXTCLOUD_CRON` | `true` | `false` = no in-container cron. |
| `PHP_MEMORY_LIMIT`, `PHP_UPLOAD_LIMIT` | `512M`, `512M` | Image defaults made visible. |
| `APACHE_MAX_REQUEST_WORKERS` | `16` | Prefork workers (template-specific). |
| `RAILWAY_DEPLOYMENT_DRAINING_SECONDS` | `30` | |

**Optional email (SMTP only, Railway Pro plan):** `SMTP_HOST`, `SMTP_SECURE` (`ssl`/`tls`), `SMTP_PORT`, `SMTP_NAME`, `SMTP_PASSWORD`, `MAIL_FROM_ADDRESS`, `MAIL_DOMAIN` (read by the image's `smtp.config.php`), or configure in Administration → Basic settings.

**Postgres / Redis**: Railway base definitions unchanged.

## Hooks shipped in the image

- `post-installation/10-railway.sh`: records the storage mode, sets background jobs to cron, installs `NEXTCLOUD_INSTALL_APPS` (logs and continues if the app store is unreachable).
- `before-starting/10-railway.sh` (every start, skipped until installed): trusted domains, cron mode, maintenance window, phone region.
- `post-upgrade/10-railway.sh`: `occ db:add-missing-indices`, `db:add-missing-columns`, `db:add-missing-primary-keys`.

## First start and accounts

1. Postgres and Redis start; the start script waits for both, then the official entrypoint copies Nextcloud to the volume and runs `occ maintenance:install` with the generated admin password (≈1–2 min), installs Calendar and Contacts, then starts Apache.
2. Log in at the public domain with `admin` and the `NEXTCLOUD_ADMIN_PASSWORD` value from the service variables. Change the password, then create users (Administration → Accounts).
3. Desktop/mobile clients and CalDAV/CardDAV use the same URL (`/remote.php/dav`).

## Composer steps (Railway dashboard)

1. Add `Postgres` (`_railway-base/postgres.json`), `Redis` (`_railway-base/redis.json`) and a Bucket named `Bucket`.
2. `Nextcloud`: GitHub repo `baranberkay96/nextcloud-railway`, root `/services/nextcloud`; volume `/var/www/html`; domain → 80; healthcheck `/status.php` (900 s); restart ALWAYS; variables as above.

## Improvements over market templates

| Area | Market templates | This template |
|---|---|---|
| Admin account | `self-host-nextcloud`/`nextcloud`: admin user/password empty → public web installer on a fresh domain | Automatic install with generated admin password |
| Background jobs | No cron in any of them (AJAX fallback) | System cron inside the container (busybox crond, supervised), mode set to cron |
| Image | `nextcloud`, `nextcloud:apache` floating tags | `nextcloud:34.0.4-apache` pinned (Docker `stable`/`production` channel) |
| Apache MPM | Fix inside a long start command / none | Fixed at build time, asserted by `apache2ctl -t`, re-checked at start |
| Database | `LddOJ1`: SQLite | Postgres 18 on the private network, wait-for-DB before install |
| Caching/locking | `nextcloud`/`LddOJ1`: no Redis | Redis for locking, distributed cache and sessions; APCu local cache |
| Storage | Volume only, or Bucket only with a hard-coded legacy host | Volume by default, Bucket as a deploy-time option, endpoint parsed from Railway variables, choice locked after install |
| Domains | Trusted domain set once at install; Railway healthcheck host not trusted | Rewritten from a variable on every start, includes `healthcheck.railway.app` |
| Proxy | No trusted proxies (brute-force throttling hits every user behind the proxy IP) | Railway proxy ranges trusted in Nextcloud and Apache |
| Healthcheck | none | `/status.php`, 900 s |
| Upgrades | `NEXTCLOUD_UPDATE=1` only | Official upgrade path + missing-index/column repair hook |

## Resource profile and cost (Railway: RAM $10/GB-mo, vCPU $20/mo, volume $0.15/GB-mo, bucket $0.015/GB-mo)

| Service | Idle RAM | Typical RAM | Idle CPU | Typical CPU |
|---|---|---|---|---|
| Nextcloud (Apache prefork + cron) | 0.2 GB | 0.5–1.5 GB | 0.01 (cron spikes every 5 min) | 0.1–0.5 |
| Postgres | 0.07 GB | 0.15–0.4 GB | 0.01 | 0.03–0.15 |
| Redis | 0.01 GB | 0.02–0.06 GB | 0 | 0.01 |
| **Total** | **~0.3 GB** | **~0.7–2 GB** | **~0.02 vCPU** | **~0.15–0.65 vCPU** |

Measured locally after install and a test upload: Nextcloud 197 MiB, Postgres 63 MiB, Redis 5 MiB.

Estimated monthly cost: **idle ≈ $4** (0.3 GB × $10 + 0.02 vCPU × $20 + ~1.1 GB volumes); **typical household/small team (5–20 users with sync clients) ≈ $10–30** plus storage ($0.15/GB on the volume or $0.015/GB in the Bucket). Minimum plan: **Hobby** (5 GB volume → choose `bucket` for more files); Pro for larger volumes or outbound SMTP.

## Scaling

Nextcloud keeps code and config on its volume, so the service runs as one replica; scale vertically and raise `APACHE_MAX_REQUEST_WORKERS` with RAM (≈100 MB per worker). Postgres and Redis already offload locking, cache and sessions.

## Pinning and upgrades

Pinned 2026-10-11: `nextcloud:34.0.4-apache` (`services/nextcloud/Dockerfile`), Postgres `postgres-ssl:18`, `redis:8.2`. Upgrade by changing the `FROM` tag one major version at a time (34 → 35 → 36); on start the official entrypoint syncs the new code and runs `occ upgrade`, then the post-upgrade hook adds missing indices. Rename the listing when the major changes.

## Verification checklist

- [ ] Nextcloud logs: `Postgres is reachable`, `Redis is reachable`, `Nextcloud was successfully installed`, `app 'calendar' installed`, `app 'contacts' installed`, `trusted domains: …`, then Apache `resuming normal operations`.
- [ ] Railway healthcheck on `/status.php` passes (`"installed":true`).
- [ ] Log in as `admin`; Administration → Overview shows no cron, memcache, locking or reverse-proxy warnings; Basic settings shows "Cron" selected and a recent last run.
- [ ] Upload a file in the web UI and via WebDAV; create a calendar event and a contact.
- [ ] Redeploy: files, users and settings persist; logs show the storage mode unchanged.
- [ ] Optional `bucket` mode (fresh project): uploaded files appear as `urn:oid:*` objects in the Bucket; `data/` on the volume holds only logs.
- [ ] Add a custom domain: append it to `NEXTCLOUD_TRUSTED_DOMAINS`, update `OVERWRITECLIURL`, redeploy, log in through it.

## Local test (2026-10-11)

Built `services/nextcloud` and ran it with Postgres 18 and Redis 8.2, starting Nextcloud ~25 s before the database: the start script waited, then the automatic install, Calendar/Contacts install, cron (`lastcron` set, mode `cron`), Redis locking/cache and trusted domains all worked; `/status.php` with `Host: healthcheck.railway.app` returned 200; a 3 MB WebDAV upload round-tripped. Restarting with `NEXTCLOUD_PRIMARY_STORAGE=bucket` kept the volume mode and logged the warning. A second fresh install in `bucket` mode against a local S3 server stored all files as objects (66 objects), with only `nextcloud.log` in `data/`; crond's environment contained the `OBJECTSTORE_S3_*` settings.

## Open questions

- Not deployed on Railway. Bucket mode was tested against a local S3 server with path-style; on Railway it uses virtual-hosted addressing (`use_path_style=false`, aws-sdk-php default), region `auto`.
- Nextcloud `35.0.1` is the newest release; the Docker `stable`/`production` channel still points to 34. Move to 35 (and rename the listing) once that channel does.
- Railway's edge proxy source address range is not documented; the trusted-proxy list covers all private/CGNAT ranges. Verify in Administration → Logging that client IPs (not proxy IPs) are recorded.
- Talk (video calls) is not included: it needs a TURN/STUN server with UDP, which Railway does not offer.
