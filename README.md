# Deploy and Host Nextcloud with Railway

Nextcloud is an open-source cloud for files, calendars, contacts and collaboration that you run yourself. This community template deploys Nextcloud 34 on Railway with PostgreSQL, Redis for file locking and caching, background jobs on cron, and a choice between volume storage and a Railway Bucket for your files.

## About Hosting Nextcloud

Nextcloud is a PHP application served by Apache. It needs a database, Redis for transactional file locking and caching, a place to store files, and a cron job that runs background tasks every five minutes. On Railway a volume belongs to one service, so this template runs cron inside the Nextcloud container instead of a separate service. Nextcloud installs itself on first start with a generated admin password, installs the Calendar and Contacts apps, and trusts Railway's proxy so links use HTTPS and client IP addresses are correct. Files go to the service volume by default or, if you choose it before deploying, to a Railway Bucket.

## Common Use Cases

- Private Dropbox or Google Drive replacement for a family, club or small company.
- Calendar and contact sync for phones and desktops via CalDAV and CardDAV.
- Sharing files with clients through password-protected links.
- Team file server with desktop sync clients and mobile apps.

## Dependencies for Nextcloud Hosting

- Nextcloud server (official `nextcloud` Apache image)
- PostgreSQL 18
- Redis
- Storage: Railway volume (default) or Railway Bucket (S3)
- Optional: SMTP server for email notifications (Railway Pro plan)

### Deployment Dependencies

- Nextcloud admin manual: https://docs.nextcloud.com/server/latest/admin_manual/
- Official Docker image and its environment variables: https://github.com/nextcloud/docker
- Background jobs (cron): https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/background_jobs_configuration.html
- S3 primary storage: https://docs.nextcloud.com/server/latest/admin_manual/configuration_files/primary_storage.html
- Railway Buckets: https://docs.railway.com/storage-buckets

### Implementation Details

| Service | Image | Role | Public |
|---|---|---|---|
| `Nextcloud` | `nextcloud:34.0.4-apache` + start script and hooks | Web UI, WebDAV/CalDAV/CardDAV, cron | HTTPS domain |
| `Postgres` | `ghcr.io/railwayapp-templates/postgres-ssl:18` | Database | — |
| `Redis` | `redis:8.2` | File locking, cache, sessions | — |
| `Bucket` | Railway Bucket | Optional primary storage | — |

**First login.** After the first deploy (about two minutes), open the domain and sign in as `admin` with the password in the `NEXTCLOUD_ADMIN_PASSWORD` variable. Change it, then create accounts for your users.

**Storage choice.** `NEXTCLOUD_PRIMARY_STORAGE=volume` (default) keeps files on the service volume, which is limited to 5 GB on the Hobby plan, including about 1 GB for Nextcloud itself. Set it to `bucket` before the first deploy to store files in the Railway Bucket without a size cap. The choice is locked after installation.

**Custom domain.** Add the domain to `NEXTCLOUD_TRUSTED_DOMAINS` (space-separated), set `OVERWRITECLIURL` to `https://{your-domain}` and redeploy.

**Email.** Nextcloud sends email over SMTP, which Railway allows on the Pro plan. Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_NAME`, `SMTP_PASSWORD`, `MAIL_FROM_ADDRESS` and `MAIL_DOMAIN`, or configure it under Administration → Basic settings.

**Scaling.** Nextcloud runs as one service with its volume. Give it more memory and raise `APACHE_MAX_REQUEST_WORKERS` (about 100 MB per worker) for more simultaneous users.

**Pinning and upgrades.** The version is the `FROM` line in `services/nextcloud/Dockerfile`. Upgrade one major version at a time (34 to 35, then 35 to 36); the container runs the upgrade on start.

### Why Deploy Nextcloud on Railway?

Railway runs Nextcloud, PostgreSQL and Redis together on a private network with automatic HTTPS, persistent storage and background jobs already configured. You keep your files and calendars on infrastructure you control and pay for the resources you use, with an optional Bucket for low-cost storage that grows with you.
