# Nextcloud for Railway: official Apache image + single MPM, in-container cron,
# Railway-aware start script and occ hooks.
#
# The Nextcloud version is this FROM line. Upgrade one major version at a time
# (34 -> 35 -> 36); the official entrypoint runs `occ upgrade` on start.
FROM nextcloud:34.0.4-apache

# 1) Exactly one Apache MPM. Stock PHP/Apache images have failed on Railway with
#    "AH00534: More than one MPM loaded"; mod_php needs prefork. Checked again at
#    container start by railway-entrypoint.sh.
RUN set -eux; \
    rm -f /etc/apache2/mods-enabled/mpm_*.load /etc/apache2/mods-enabled/mpm_*.conf; \
    a2enmod mpm_prefork; \
    test "$(ls /etc/apache2/mods-enabled/ | grep -c '^mpm_.*\.load$')" = "1"

# 2) Apache sizing (each prefork worker is one PHP process, ~60-120 MB with
#    Nextcloud). Override with service variables.
ENV APACHE_MAX_REQUEST_WORKERS=16 \
    APACHE_MAX_CONNECTIONS_PER_CHILD=500

COPY config/mpm_prefork.conf /etc/apache2/mods-available/mpm_prefork.conf
COPY config/railway.conf     /etc/apache2/conf-available/railway.conf

# 3) Start script and occ hooks (the official entrypoint runs hooks as www-data).
COPY --chmod=755 railway/railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
COPY --chmod=755 railway/hooks/post-installation/ /docker-entrypoint-hooks.d/post-installation/
COPY --chmod=755 railway/hooks/before-starting/   /docker-entrypoint-hooks.d/before-starting/
COPY --chmod=755 railway/hooks/post-upgrade/      /docker-entrypoint-hooks.d/post-upgrade/

RUN set -eux; \
    a2enconf railway; \
    apache2ctl -t; \
    bash -n /usr/local/bin/railway-entrypoint.sh; \
    for f in /docker-entrypoint-hooks.d/*/*.sh; do sh -n "$f"; done

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
CMD ["apache2-foreground"]
