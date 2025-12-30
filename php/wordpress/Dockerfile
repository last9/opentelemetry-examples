FROM wordpress:6.8.3-php8.2-apache

# Install build dependencies for OpenTelemetry extension
RUN apt-get update && apt-get install -y \
    git \
    unzip \
    libzip-dev \
    && docker-php-ext-install zip \
    && rm -rf /var/lib/apt/lists/*

# Install OpenTelemetry PHP extension using PECL
RUN pecl install opentelemetry \
    && docker-php-ext-enable opentelemetry

# Install protobuf extension for better OTLP performance (optional but recommended)
RUN pecl install protobuf \
    && docker-php-ext-enable protobuf

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Create vendor directory for OTel packages
WORKDIR /var/www

# Copy composer configuration and install OTel dependencies
COPY composer.json ./
RUN composer install --no-dev --optimize-autoloader

# Copy the OTel bootstrap file and set permissions
COPY otel-bootstrap.php ./otel-bootstrap.php
RUN chmod 644 /var/www/otel-bootstrap.php && \
    chmod 644 /var/www/composer.json && \
    chown -R www-data:www-data /var/www/vendor

# Configure PHP to auto-prepend the OTel bootstrap file
RUN echo "auto_prepend_file=/var/www/otel-bootstrap.php" >> /usr/local/etc/php/conf.d/otel.ini

# Set working directory back to WordPress root
WORKDIR /var/www/html

# Enable Apache rewrite module (required by WordPress)
RUN a2enmod rewrite
