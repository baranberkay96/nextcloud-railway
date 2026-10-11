#!/bin/bash
# Start script for Nextcloud on Railway (runs as root, then hands over to the
# official /entrypoint.sh, which copies/installs/upgrades Nextcloud and starts
# Apache).
#
#  1. Guarantees exactly one Apache MPM.
#  2. Waits for Postgres and Redis, so a slow database never leaves a
#     half-finished automatic installation behind.
#  3. Selects the primary storage (volume or Railway Bucket) and locks the
#     choice after installation.
#  4. Starts the Nextcloud background-job cron (busybox crond, supervised) in
#     this container, because the cron job needs the same volume.
set -Eeuo pipefail

HTML=/var/www/html
STORAGE_MARKER="${HTML}/config/.railway-primary-storage"

log() { echo "[railway] $*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# 1. Single MPM guard (also enforced at build time).
mpm_count="$(find /etc/apache2/mods-enabled -maxdepth 1 -name 'mpm_*.load' | wc -l)"
if [ "${mpm_count}" != "1" ] || [ ! -e /etc/apache2/mods-enabled/mpm_prefork.load ]; then
    log "found ${mpm_count} enabled MPM modules; enabling mpm_prefork only"
    rm -f /etc/apache2/mods-enabled/mpm_*.load /etc/apache2/mods-enabled/mpm_*.conf
    a2enmod -q mpm_prefork
fi

# 2. Wait for the database and Redis (up to WAIT_TIMEOUT seconds each).
wait_for() {
    local name="$1" check="$2" waited=0 limit="${WAIT_TIMEOUT:-900}"
    until php -r "${check}" 2>/tmp/wait-error; do
        if [ "${waited}" -ge "${limit}" ]; then
            die "${name} not reachable after ${limit}s: $(cat /tmp/wait-error)"
        fi
        log "waiting for ${name} ($(tr -d '\n' </tmp/wait-error | cut -c1-160))"
        sleep 5
        waited=$((waited + 5))
    done
    log "${name} is reachable"
}

if [ -n "${POSTGRES_HOST:-}" ]; then
    wait_for "Postgres" '
        $dsn = sprintf("pgsql:host=%s;port=%s;dbname=%s;connect_timeout=5",
            getenv("POSTGRES_HOST"), getenv("POSTGRES_PORT") ?: "5432", getenv("POSTGRES_DB"));
        try { new PDO($dsn, getenv("POSTGRES_USER"), getenv("POSTGRES_PASSWORD")); }
        catch (Throwable $e) { fwrite(STDERR, $e->getMessage()); exit(1); }'
fi
if [ -n "${REDIS_HOST:-}" ]; then
    wait_for "Redis" '
        try {
            $r = new Redis();
            $r->connect(getenv("REDIS_HOST"), (int) (getenv("REDIS_HOST_PORT") ?: 6379), 5);
            if ((string) getenv("REDIS_HOST_PASSWORD") !== "") { $r->auth(getenv("REDIS_HOST_PASSWORD")); }
            $r->ping();
        } catch (Throwable $e) { fwrite(STDERR, $e->getMessage()); exit(1); }'
fi

# 3. Primary storage. The choice made at installation is stored on the volume and
#    wins over later changes of NEXTCLOUD_PRIMARY_STORAGE (switching would hide
#    every existing file).
requested="${NEXTCLOUD_PRIMARY_STORAGE:-volume}"
case "${requested}" in
    volume|bucket) ;;
    *) die "NEXTCLOUD_PRIMARY_STORAGE must be 'volume' or 'bucket' (got '${requested}')" ;;
esac
mode="${requested}"
if [ -f "${STORAGE_MARKER}" ]; then
    mode="$(tr -d '[:space:]' <"${STORAGE_MARKER}")"
    if [ "${mode}" != "${requested}" ]; then
        log "WARNING: this instance was installed with primary storage '${mode}'; ignoring NEXTCLOUD_PRIMARY_STORAGE='${requested}'"
    fi
fi

if [ "${mode}" = "bucket" ]; then
    for name in BUCKET_NAME BUCKET_ENDPOINT BUCKET_ACCESS_KEY_ID BUCKET_SECRET_ACCESS_KEY; do
        [ -n "${!name:-}" ] || die "primary storage 'bucket' needs ${name}"
    done
    endpoint="${BUCKET_ENDPOINT%/}"
    ssl=true
    case "${endpoint}" in http://*) ssl=false ;; esac
    hostport="${endpoint#*://}"
    hostport="${hostport%%/*}"
    host="${hostport%%:*}"
    if [ "${hostport}" != "${host}" ]; then
        port="${hostport##*:}"
    elif [ "${ssl}" = true ]; then
        port=443
    else
        port=80
    fi
    # Read by Nextcloud's own config/s3.config.php on every request and cron run.
    export OBJECTSTORE_S3_BUCKET="${BUCKET_NAME}"
    export OBJECTSTORE_S3_HOST="${host}"
    export OBJECTSTORE_S3_PORT="${port}"
    export OBJECTSTORE_S3_SSL="${ssl}"
    export OBJECTSTORE_S3_REGION="${BUCKET_REGION:-auto}"
    export OBJECTSTORE_S3_KEY="${BUCKET_ACCESS_KEY_ID}"
    export OBJECTSTORE_S3_SECRET="${BUCKET_SECRET_ACCESS_KEY}"
    export OBJECTSTORE_S3_USEPATH_STYLE="${BUCKET_FORCE_PATH_STYLE:-false}"
    export OBJECTSTORE_S3_AUTOCREATE=false
    log "primary storage: Railway Bucket ${BUCKET_NAME} at ${host}:${port}"
else
    log "primary storage: volume (${HTML}/data)"
fi
export NC_RAILWAY_STORAGE_MODE="${mode}"

# 4. Background jobs: Nextcloud's recommended "system cron" (cron.php every
#    5 minutes as www-data, crontab shipped in the image), restarted if it exits.
if [ "${NEXTCLOUD_CRON:-true}" = "true" ]; then
    (
        while true; do
            busybox crond -f -L /dev/stdout || true
            log "crond exited; restarting in 10 s"
            sleep 10
        done
    ) &
    log "background jobs: cron every 5 minutes (in this container)"
else
    log "NEXTCLOUD_CRON=false: not starting cron (configure AJAX/Webcron in Nextcloud)"
fi

exec /entrypoint.sh "$@"
