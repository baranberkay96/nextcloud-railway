#!/bin/sh
# Runs as www-data after `occ upgrade` (new image version). Adds the database
# indices/columns new releases expect, which the admin overview otherwise flags.
occ() { php /var/www/html/occ "$@"; }

occ db:add-missing-indices || true
occ db:add-missing-columns || true
occ db:add-missing-primary-keys || true

exit 0
