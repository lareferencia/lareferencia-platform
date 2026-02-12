FROM php:8.3-apache-bullseye

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        default-mysql-client \
        git \
        libfreetype6-dev \
        libicu-dev \
        libjpeg62-turbo-dev \
        libldap2-dev \
        libonig-dev \
        libpng-dev \
        libxml2-dev \
        libxslt1-dev \
        libzip-dev \
        unzip \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    && docker-php-ext-configure ldap --with-libdir="lib/$(dpkg-architecture -qDEB_HOST_MULTIARCH)/" \
    && docker-php-ext-install -j"$(nproc)" \
        gd \
        intl \
        ldap \
        mbstring \
        mysqli \
        opcache \
        pdo_mysql \
        soap \
        xsl \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

COPY Docker/vufind/apache-vufind.conf /etc/apache2/conf-available/vufind.conf
COPY Docker/vufind/entrypoint.sh /usr/local/bin/vufind-entrypoint.sh

RUN chmod +x /usr/local/bin/vufind-entrypoint.sh \
    && a2enmod rewrite headers \
    && a2enconf vufind \
    && sed -ri 's!/var/www/html!/usr/local/vufind/public!g' /etc/apache2/sites-available/000-default.conf

WORKDIR /usr/local/vufind

ENTRYPOINT ["/usr/local/bin/vufind-entrypoint.sh"]
CMD ["apache2-foreground"]
