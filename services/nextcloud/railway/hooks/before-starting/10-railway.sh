#!/bin/sh
# Runs as www-data on every start, after install/upgrade and before Apache.
# Re-applies settings that follow Railway variables. Never fails the start.
occ() { php /var/www/html/occ "$@"; }
log() { echo "[railway] $*"; }

if ! occ status --output=json 2>/dev/null | grep -q '"installed":true'; then
    log "Nextcloud is not installed yet; skipping start-up settings"
    exit 0
fi

marker=/var/www/html/config/.railway-primary-storage
[ -f "${marker}" ] || printf '%s\n' "${NC_RAILWAY_STORAGE_MODE:-volume}" > "${marker}"

# Trusted domains = localhost + Railway's healthcheck host + NEXTCLOUD_TRUSTED_DOMAINS
# (space-separated), rewritten on every start so adding a custom domain only needs
# a variable change. Railway probes /status.php with Host healthcheck.railway.app,
# which Nextcloud would otherwise answer with 400.
set -f
occ config:system:delete trusted_domains >/dev/null 2>&1 || true
index=0
for domain in localhost healthcheck.railway.app ${NEXTCLOUD_TRUSTED_DOMAINS:-}; do
    if occ config:system:set trusted_domains "${index}" --value="${domain}" >/dev/null; then
        index=$((index + 1))
    fi
done
set +f
log "trusted domains: localhost healthcheck.railway.app ${NEXTCLOUD_TRUSTED_DOMAINS:-}"

occ background:cron >/dev/null || log "could not set background jobs to cron"
occ config:system:set maintenance_window_start --type=integer \
    --value="${NEXTCLOUD_MAINTENANCE_WINDOW_START:-1}" >/dev/null || true
if [ -n "${NEXTCLOUD_DEFAULT_PHONE_REGION:-}" ]; then
    occ config:system:set default_phone_region --value="${NEXTCLOUD_DEFAULT_PHONE_REGION}" >/dev/null || true
fi

exit 0
