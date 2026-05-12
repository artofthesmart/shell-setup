#!/bin/bash
set -e

# Ensure Grav permissions are correct
chown -R www-data:www-data /var/www/html

# Run Apache
source /etc/apache2/envvars
exec apache2 -D FOREGROUND
