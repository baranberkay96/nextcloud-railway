# NOTICE — Nextcloud template

This is a community template. It is not affiliated with or endorsed by Nextcloud GmbH. "Nextcloud" is a trademark of Nextcloud GmbH.

## Upstream sources checked (2026-10-11)

| Source | Version / path | License | Use |
|---|---|---|---|
| nextcloud/docker | `34/apache/Dockerfile`, `entrypoint.sh`, `cron.sh`, `upgrade.exclude`, `config/*.config.php`, `README.md`, `versions.json` | AGPL-3.0 | Image behaviour, environment variables, hook folders, cron crontab, S3/Redis/proxy config logic (read; the template's scripts call the image's entrypoint, nothing copied) |
| nextcloud/server | releases `v34.0.4`, `v35.0.1` | AGPL-3.0 | Version choice |
| Nextcloud admin manual | background jobs, primary storage, reverse proxy | CC BY 3.0 | Cron/storage/proxy design |
| Railway docs | Healthchecks (`healthcheck.railway.app`), Storage Buckets | — | Trusted domain for healthchecks, Bucket variables |

## Market templates reviewed

| Code | License | Use |
|---|---|---|
| `self-host-nextcloud` (base) | n/a (image-based) | Service set and variable ideas; nothing copied |
| `nextcloud` | n/a (image-based) | Reviewed only |
| `LddOJ1` | n/a (image-based) | Reviewed only |

## Own prior work reused

The single-MPM build step, runtime MPM guard and `mpm_prefork.conf` structure follow this project's round-1 WordPress template (`templates/27-wordpress`), written for these templates.

## Railway base services

`Postgres` and `Redis` copied from `templates/_railway-base/postgres.json` and `redis.json` (unchanged).

## Runtime images

- `nextcloud:34.0.4-apache` — Nextcloud (AGPL-3.0) on the official Docker image.
- `ghcr.io/railwayapp-templates/postgres-ssl:18` (PostgreSQL License), `redis:8.2`.

All files in `template/` (Dockerfile, start script, hooks, Apache snippets, documentation) were written for this template.
