FROM php:7.2-fpm-alpine

################################################################################
# Environment Variables
################################################################################
ENV APP_DIR /app
ENV LOG_TMP_DIR /log
ENV CACHE_TMP_DIR /tmp
ENV NGINX_LOG /log/nginx
ENV REST_LOG_DIR /log/api/
ENV COMPOSER_PROCESS_TIMEOUT 900

################################################################################
# Required Dependencies
################################################################################

# Install application dependencies
RUN docker-php-ext-install pdo pdo_mysql mysqli pcntl sockets mbstring opcache

# Install PHP Extensions (igbinary & memcached)
RUN apk add --no-cache --update libmemcached-libs zlib git bash
RUN set -xe && \
    cd /tmp/ && \
    apk add --no-cache --update --virtual .phpize-deps $PHPIZE_DEPS && \
    apk add --no-cache --update --virtual .memcached-deps zlib-dev libmemcached-dev cyrus-sasl-dev && \
    # Install igbinary (memcached's deps)
    pecl install igbinary && \
    # Install memcached
    ( \
        pecl install --nobuild memcached && \
        cd "$(pecl config-get temp_dir)/memcached" && \
        phpize && \
        ./configure --enable-memcached-igbinary && \
        make -j$(nproc) && \
        make install && \
        cd /tmp/ \
    ) && \
    # Enable PHP extensions
    docker-php-ext-enable igbinary memcached && \
    rm -rf /tmp/* && \
    apk del .memcached-deps .phpize-deps

# Install Zip
RUN apk add zlib-dev libzip-dev && \
    docker-php-ext-configure zip --with-libzip && \
    docker-php-ext-install zip

# Install ImageMagick
RUN apk add --update freetype-dev libpng-dev libjpeg-turbo-dev libxml2-dev autoconf g++ imagemagick-dev libtool make && \
    docker-php-ext-install gd && \
    docker-php-ext-configure gd \
    --with-gd \
    --with-freetype-dir=/usr/include/ \
    --with-png-dir=/usr/include/ \
    --with-jpeg-dir=/usr/include/ && \
    pecl install imagick && \
    docker-php-ext-enable imagick && \
    apk del autoconf g++ libtool make && \
    rm -rf /tmp/* /var/cache/apk/*

# Install rdkafka
RUN set -xe && \
    cd /tmp/ && \
    git clone https://github.com/edenhill/librdkafka && \
    cd librdkafka && \
    ./configure && \
    make && \
    make install && \
    pecl install rdkafka && docker-php-ext-enable rdkafka && \
    cd ../ && rm -rf librdkaf

# Install Composer
COPY --from=composer:1 /usr/bin/composer /usr/local/bin/composer
RUN composer --version

################################################################################
# Create Folders
################################################################################

RUN mkdir -p $REST_LOG_DIR \
    $NGINX_LOG \
    $LOG_TMP_DIR \
    $CACHE_TMP_DIR \
    /log \
    /tmp \
    /log/nginx \
    /var/alsocan/certs && \
    \
    chmod -R 777 /log \
    /tmp \
    /log/nginx && \
    \
    touch $NGINX_LOG/op-access.log && \
    touch $NGINX_LOG/op-access.log

RUN pecl install -f xdebug && docker-php-ext-enable xdebug

################################################################################
# COPY CODE
################################################################################
WORKDIR ${APP_DIR}
RUN chown www-data:www-data -R ${APP_DIR}

COPY --chown=www-data:www-data . ${APP_DIR}

################################################################################
# Install PHP Dependencies
################################################################################
RUN composer install

EXPOSE 8000

CMD [ "php", "artisan", "serve", "--host", "0.0.0.0", "--port", "8000" ]