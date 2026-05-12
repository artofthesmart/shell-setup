FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y \
    apache2 \
    curl \
    unzip \
    git \
    php \
    libapache2-mod-php \
    php-cli \
    php-gd \
    php-curl \
    php-mbstring \
    php-xml \
    php-zip \
    php-apcu \
    php-intl \
    ca-certificates \
    gnupg \
    && rm -rf /var/lib/apt/lists/*



RUN a2enmod rewrite

# Install Grav
RUN rm -rf /var/www/html/* && \
    curl -o grav.zip -L https://getgrav.org/download/core/grav-admin/latest && \
    unzip grav.zip -d /tmp && \
    mv /tmp/grav-admin/* /var/www/html/ && \
    mv /tmp/grav-admin/.htaccess /var/www/html/ && \
    rm -rf /tmp/grav-admin grav.zip

RUN sed -i 's/80/8080/g' /etc/apache2/ports.conf && \
    sed -i 's/:80/:8080/g' /etc/apache2/sites-available/000-default.conf

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

RUN chown -R www-data:www-data /var/www/html

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
