FROM getgrav/grav:latest

# Grav 2.0 RC releases are only available on GitHub, not via getgrav.org/download.
# This Dockerfile overrides the entrypoint so GRAV_VERSION values like "2.0.0-rc.7"
# are fetched directly from GitHub release assets.
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Enable mod_rewrite and apply AllowOverride All for the web root.
# The base image's VirtualHost has no <Directory> block, so Apache ignores .htaccess
# entirely — Grav's PHP backend is never invoked and all API calls silently fail.
COPY grav-apache.conf /etc/apache2/conf-available/grav.conf
RUN a2enmod rewrite && a2enconf grav
