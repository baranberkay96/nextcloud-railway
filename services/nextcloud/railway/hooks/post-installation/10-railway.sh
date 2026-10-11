#!/bin/sh
# Runs once as www-data, right after the automatic `occ maintenance:install`.
occ() { php /var/www/html/occ "$@"; }
log() { echo "[railway] $*"; }

# Remember the primary storage this instance was installed with.
printf '%s\n' "${NC_RAILWAY_STORAGE_MODE:-volume}" > /var/www/html/config/.railway-primary-storage

occ background:cron

# Calendar, Contacts etc. come from the Nextcloud app store (not bundled).
for app in ${NEXTCLOUD_INSTALL_APPS:-}; do
    if occ app:install "${app}" >/dev/null 2>&1 || occ app:enable "${app}" >/dev/null 2>&1; then
        log "app '${app}' installed"
    else
        log "could not install app '${app}' (app store unreachable?); install it later under Apps"
    fi
done

exit 0
