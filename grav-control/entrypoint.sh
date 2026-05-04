#!/bin/bash
set -e

# Ensure Docker socket is accessible by www-data
if [ -e /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock
fi

# Ensure Grav permissions are correct
chown -R www-data:www-data /var/www/html

# Run Apache
source /etc/apache2/envvars
exec apache2 -D FOREGROUND
