FROM php:8.2-apache

ADD --chmod=0755 https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# Install dependencies
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    default-mysql-client \
    && docker-php-ext-install zip mysqli\
    && docker-php-ext-enable mysqli

RUN install-php-extensions opentelemetry-php/ext-opentelemetry@main

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Set working directory
WORKDIR /var/www/html

# Copy composer files first
COPY composer.json ./

# Debug: List contents after copying composer.json
RUN ls -la && \
    # Run composer install with verbose output
    composer install --verbose && \
    # Debug: List contents after composer install
    ls -la && \
    # Debug: List vendor directory if it exists
    ls -la vendor/ || echo "Vendor directory not created"

# Copy the rest of the application
COPY . .

# Run composer install again after copying all files
RUN composer install --verbose

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Enable Apache rewrite module
RUN a2enmod rewrite

# Debug: Final directory listing
RUN ls -la && ls -la vendor/ || echo "Vendor directory still not created"
