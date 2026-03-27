FROM drupal:11-php8.3-apache

WORKDIR /opt/drupal

# ── Sistema + SSH + cliente MySQL ─────────────────────────────
RUN apt-get update && apt-get install -y \
    wget unzip git curl \
    openssh-server \
    mariadb-client \
    rsync \
    libxml2-dev libpng-dev libjpeg62-turbo-dev \
    libfreetype6-dev libwebp-dev libzip-dev \
    libpq-dev libsodium-dev \
  && docker-php-ext-configure gd \
      --with-freetype --with-jpeg --with-webp \
  && docker-php-ext-install -j"$(nproc)" \
      soap gd opcache pdo_mysql sodium zip \
  && rm -rf /var/lib/apt/lists/*

# ── Composer 2 ────────────────────────────────────────────────
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# ── SSH: solo por llave pública, sin contraseña ───────────────
RUN mkdir -p /var/run/sshd /root/.ssh \
  && chmod 700 /root/.ssh \
  && echo "Port 2222"                              >> /etc/ssh/sshd_config \
  && echo "PermitRootLogin prohibit-password"      >> /etc/ssh/sshd_config \
  && echo "PubkeyAuthentication yes"               >> /etc/ssh/sshd_config \
  && echo "PasswordAuthentication no"              >> /etc/ssh/sshd_config \
  && echo "AuthorizedKeysFile /root/.ssh/authorized_keys" >> /etc/ssh/sshd_config

# ── Apache mod_rewrite ────────────────────────────────────────
RUN a2enmod rewrite

# 80   → Drupal / Apache
# 2222 → SSH al contenedor
EXPOSE 80 2222

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD ["apache2-foreground"]
