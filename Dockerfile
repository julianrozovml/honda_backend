FROM drupal:11-php8.3-apache

WORKDIR /opt/drupal

RUN apt-get update && apt-get install -y \
    git curl unzip rsync \
    openssh-server \
    mariadb-client \
    default-mysql-client \
    jq \
    libxml2-dev libpng-dev libjpeg62-turbo-dev \
    libfreetype6-dev libwebp-dev libzip-dev \
    libsodium-dev \
  && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
  && docker-php-ext-install -j"$(nproc)" \
      gd opcache pdo_mysql sodium zip soap \
  && a2enmod rewrite headers \
  && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

RUN mkdir -p /var/run/sshd /root/.ssh \
  && chmod 700 /root/.ssh \
  && echo "Port 2222" >> /etc/ssh/sshd_config \
  && echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config \
  && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
  && echo "PasswordAuthentication no" >> /etc/ssh/sshd_config \
  && echo "AuthorizedKeysFile /root/.ssh/authorized_keys" >> /etc/ssh/sshd_config

COPY . /opt/drupal/

RUN composer install \
    --working-dir=/opt/drupal \
    --no-interaction \
    --no-dev \
    --optimize-autoloader \
    --prefer-dist \
    --no-progress \
 && ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 80 2222

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
