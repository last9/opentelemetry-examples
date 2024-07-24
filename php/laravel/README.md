# Instrumenting Laravel application with OpenTelemetry

This example demonstrates how to instrument a Laravel application with OpenTelemetry. Make sure you have installed:

-   PHP 8.0 or higher
-   Composer (Install from [here](https://getcomposer.org/download/))

## Setting up this example

1. After cloning this repository, navigate to the `php/laravel` directory:

    ```bash
    cd php/laravel
    ```

2. Install the dependencies:

    ```bash
    composer install
    ```

3. Next, we need to set the environment variables. The following environment variables are required to send traces:

    - `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT`: Specify the endpoint where the traces will be pushed, such as `https://otlp.last9.io/v1/traces`.

    - `OTEL_EXPORTER_OTLP_AUTH_HEADER`: Specify the basic auth header for the endpoint. For example, `Basic <BASIC_AUTH_TOKEN>`.

You can get the `BASE_AUTH_TOKEN` from the Last9 dashboard.

4. Start the Laravel application by running the following command:

    ```bash
    php artisan serve
    ```

5. Once the server is running, you can access the application at `http://localhost:8000`. The API endpoints are:

    - GET `/users` - Get all users
    - POST `/users` - Create a new user
    - GET `/users/:id` - Get a user by ID
    - PUT `/users/:id` - Update a user
    - DELETE `/users/:id` - Delete a user

6. Sign in to the [Last9 Dashboard](https://app.last9.io) and visit the APM dashboard to see the traces in action.
