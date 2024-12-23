FROM php:7.3-apache

RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    && docker-php-ext-install zip

RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /var/www/html

COPY . .

# Install Composer dependencies
RUN composer require guzzlehttp/guzzle

RUN chown -R www-data:www-data /var/www/html

RUN a2enmod rewrite