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

# Install Docker CLI
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
    chmod a+r /etc/apt/keyrings/docker.gpg && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

RUN a2enmod rewrite

# Install Grav
RUN rm -rf /var/www/html/* && \
    curl -o grav.zip -L https://getgrav.org/download/core/grav-admin/latest && \
    unzip grav.zip -d /tmp && \
    mv /tmp/grav-admin/* /var/www/html/ && \
    mv /tmp/grav-admin/.htaccess /var/www/html/ && \
    rm -rf /tmp/grav-admin grav.zip

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

COPY docker-manager.php /var/www/html/docker-manager.php
RUN chown -R www-data:www-data /var/www/html

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
