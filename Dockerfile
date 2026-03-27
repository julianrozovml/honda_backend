FROM drupal:11-php8.3-apache

WORKDIR /opt/drupal

# ── Sistema + extensiones PHP + utilidades ───────────────────
RUN apt-get update && apt-get install -y \
  git \
  curl \
  unzip \
  rsync \
  jq \
  openssh-server \
  mariadb-client \
  default-mysql-client \
  libxml2-dev \
  libpng-dev \
  libjpeg62-turbo-dev \
  libfreetype6-dev \
  libwebp-dev \
  libzip-dev \
  libsodium-dev \
  && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
  && docker-php-ext-install -j"$(nproc)" \
  gd \
  opcache \
  pdo_mysql \
  sodium \
  zip \
  soap \
  && a2enmod rewrite headers \
  && rm -rf /var/lib/apt/lists/*

# ── Composer ──────────────────────────────────────────────────
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# ── SSH ───────────────────────────────────────────────────────
RUN mkdir -p /var/run/sshd /root/.ssh \
  && chmod 700 /root/.ssh \
  && echo "Port 2222" >> /etc/ssh/sshd_config \
  && echo "PermitRootLogin prohibit-password" >> /etc/ssh/sshd_config \
  && echo "PubkeyAuthentication yes" >> /etc/ssh/sshd_config \
  && echo "PasswordAuthentication no" >> /etc/ssh/sshd_config \
  && echo "AuthorizedKeysFile /root/.ssh/authorized_keys" >> /etc/ssh/sshd_config


# ── Cliente MySQL sin SSL (red interna Docker) ────────────────
# Drush usa el cliente mariadb para sqlc, sql-dump, etc.
# Sin esta config exige SSL que MariaDB en Docker no tiene por defecto.
RUN printf '[client]\nssl-mode=DISABLED\nprotocol=TCP\n' > /root/.my.cnf \
  && chmod 600 /root/.my.cnf \
  && printf '[client]\nssl-mode=DISABLED\nprotocol=TCP\n' > /etc/mysql/conf.d/no-ssl.cnf

# ── Copiar proyecto ───────────────────────────────────────────
COPY . /opt/drupal/


# ── Dependencias Composer ─────────────────────────────────────
# Intenta composer install.
# Si falla (lock desactualizado o incompatible) → limpia lock + vendor
# y vuelve a intentar composer install para generar lock fresco.
RUN cd /opt/drupal \
  && composer install \
      --no-interaction \
      --no-dev \
      --optimize-autoloader \
      --prefer-dist \
      --no-progress \
  || ( \
      echo "⚠️  composer install falló — limpiando lock y vendor..." \
      && rm -f composer.lock \
      && rm -rf vendor \
      && composer install \
          --no-interaction \
          --no-dev \
          --optimize-autoloader \
          --prefer-dist \
          --no-progress \
  ) \
  && ln -sf /opt/drupal/vendor/bin/drush /usr/local/bin/drush \
  && chown -R www-data:www-data /opt/drupal


EXPOSE 80 2222

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]