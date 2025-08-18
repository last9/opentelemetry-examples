<p align="center"><a href="https://laravel.com" target="_blank"><img src="https://raw.githubusercontent.com/laravel/art/master/logo-lockup/5%20SVG/2%20CMYK/1%20Full%20Color/laravel-logolockup-cmyk-red.svg" width="400"></a></p>

<p align="center">
<a href="https://travis-ci.org/laravel/framework"><img src="https://travis-ci.org/laravel/framework.svg" alt="Build Status"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://poser.pugx.org/laravel/framework/d/total.svg" alt="Total Downloads"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://poser.pugx.org/laravel/framework/v/stable.svg" alt="Latest Stable Version"></a>
<a href="https://packagist.org/packages/laravel/framework"><img src="https://poser.pugx.org/laravel/framework/license.svg" alt="License"></a>
</p>

## About Laravel

Laravel is a web application framework with expressive, elegant syntax. We believe development must be an enjoyable and creative experience to be truly fulfilling. Laravel takes the pain out of development by easing common tasks used in many web projects, such as:

- [Simple, fast routing engine](https://laravel.com/docs/routing).
- [Powerful dependency injection container](https://laravel.com/docs/container).
- Multiple back-ends for [session](https://laravel.com/docs/session) and [cache](https://laravel.com/docs/cache) storage.
- Expressive, intuitive [database ORM](https://laravel.com/docs/eloquent).
- Database agnostic [schema migrations](https://laravel.com/docs/migrations).
- [Robust background job processing](https://laravel.com/docs/queues).
- [Real-time event broadcasting](https://laravel.com/docs/broadcasting).

Laravel is accessible, powerful, and provides tools required for large, robust applications.

## Learning Laravel

Laravel has the most extensive and thorough [documentation](https://laravel.com/docs) and video tutorial library of all modern web application frameworks, making it a breeze to get started with the framework.

If you don't feel like reading, [Laracasts](https://laracasts.com) can help. Laracasts contains over 1500 video tutorials on a range of topics including Laravel, modern PHP, unit testing, and JavaScript. Boost your skills by digging into our comprehensive video library.

## Laravel Sponsors

We would like to extend our thanks to the following sponsors for funding Laravel development. If you are interested in becoming a sponsor, please visit the Laravel [Patreon page](https://patreon.com/taylorotwell).

### Premium Partners

- **[Vehikl](https://vehikl.com/)**
- **[Tighten Co.](https://tighten.co)**
- **[Kirschbaum Development Group](https://kirschbaumdevelopment.com)**
- **[64 Robots](https://64robots.com)**
- **[Cubet Techno Labs](https://cubettech.com)**
- **[Cyber-Duck](https://cyber-duck.co.uk)**
- **[Many](https://www.many.co.uk)**
- **[Webdock, Fast VPS Hosting](https://www.webdock.io/en)**
- **[DevSquad](https://devsquad.com)**
- **[OP.GG](https://op.gg)**

## Contributing

Thank you for considering contributing to the Laravel framework! The contribution guide can be found in the [Laravel documentation](https://laravel.com/docs/contributions).

## Code of Conduct

In order to ensure that the Laravel community is welcoming to all, please review and abide by the [Code of Conduct](https://laravel.com/docs/contributions#code-of-conduct).

## Security Vulnerabilities

If you discover a security vulnerability within Laravel, please send an e-mail to Taylor Otwell via [taylor@laravel.com](mailto:taylor@laravel.com). All security vulnerabilities will be promptly addressed.

## Laravel OpenTelemetry Instrumentation

### Overview

This Laravel application provides comprehensive OpenTelemetry instrumentation for Redis operations, queue processing, HTTP requests, and database queries with automatic trace context propagation.

### Features

✅ **Automatic Redis Instrumentation**: All Redis operations traced transparently  
✅ **Laravel Queue Tracking**: Complete job lifecycle tracing via Redis  
✅ **Connected Traces**: Producer-consumer span linking with context propagation  
✅ **Route-Based URL Folding**: Intelligent URL grouping using Laravel routes  
✅ **Database Query Tracing**: Automatic SQL query instrumentation  
✅ **HTTP Client Tracing**: cURL and Guzzle request instrumentation  

### Redis Auto-Instrumentation

**Zero Code Changes Required** - All Redis operations are automatically traced:

```php
// Standard Laravel Redis calls - automatically instrumented
Redis::set('user:123', 'data');
Redis::get('user:123');
Redis::hset('session:abc', 'user_id', '123');
Redis::lpush('queue:tasks', 'task1');

// Works in controllers, jobs, services - everywhere
class UserController extends Controller {
    public function store() {
        Redis::set("user:{$user->id}", $user->toJson()); // Automatically traced
    }
}
```

### Queue Job Tracking

Queue jobs are automatically instrumented with connected traces:

```php
// Job dispatch - automatically creates producer span
dispatch(new ProcessUserData($user));

// Job execution - automatically creates consumer span linked to producer
class ProcessUserData extends Job {
    public function handle() {
        Redis::set('processing', 'user_data'); // Automatically traced
        // All Redis ops connected to job execution span
    }
}
```

### Available Test Endpoints

- `/transparent/redis/test` - Test automatic Redis tracing
- `/transparent/redis/job-simulation` - Test job processing with Redis
- `/redis/test` - Test manual Redis functions
- `/redis/queue/dispatch/{count}` - Test queue dispatch
- `/api/health` - Basic health check

### Route Folding Examples

```php
// Laravel route definitions automatically fold URLs
Route::get('/users/{user}', 'UserController@show');
Route::get('/users/{user}/posts/{post}', 'PostController@show');

// URL folding results in traces
GET /api/users/123                    → GET /api/users/{user}
GET /api/users/123/posts/456          → GET /api/users/{user}/posts/{post}
```

### Manual Instrumentation Functions

Optional helper functions for advanced use cases:

```php
// Redis operations
traced_redis_get('key');
traced_redis_set('key', 'value', 300);
traced_queue_push(new MyJob($data));

// HTTP requests
traced_http_request('GET', 'https://api.example.com/users');
traced_curl_exec($ch);
traced_guzzle_request($client, 'POST', $url, $options);
```

## Adding to Your Existing Laravel App

To add all instrumentations to your existing Laravel application:

### Files to Copy

1. **OpenTelemetry bootstrap:**
   ```bash
   cp bootstrap/otel.php your-app/bootstrap/
   ```

2. **Instrumentation classes:**
   ```bash
   cp app/Http/Middleware/OpenTelemetryMiddleware.php your-app/app/Http/Middleware/
   cp app/Http/Middleware/RedisInstrumentationWrapper.php your-app/app/Http/Middleware/
   cp app/Providers/RedisInstrumentationServiceProvider.php your-app/app/Providers/
   cp app/Jobs/BaseTracedJob.php your-app/app/Jobs/
   ```

3. **Configuration:**
   ```bash
   cp config/otel.php your-app/config/
   ```

### Code Changes Required

1. **Update `public/index.php`** - Add at the top:
   ```php
   require_once __DIR__.'/../bootstrap/otel.php';
   ```

2. **Update `config/app.php`** - Add to providers array:
   ```php
   App\Providers\RedisInstrumentationServiceProvider::class,
   ```

3. **Update `app/Http/Kernel.php`** - Add to middleware:
   ```php
   \App\Http\Middleware\OpenTelemetryMiddleware::class,
   ```

4. **Update `composer.json`** - Add dependencies:
   ```json
   "require": {
       "open-telemetry/exporter-otlp": "0.0.17",
       "nyholm/psr7": "^1.8",
       "php-http/guzzle6-adapter": "^2.0"
   }
   ```

5. **Environment variables:**
   ```bash
   OTEL_SERVICE_NAME=your-app-name
   OTEL_EXPORTER_OTLP_TRACES_ENDPOINT=your-endpoint
   OTEL_EXPORTER_OTLP_HEADERS=authorization=Bearer your-token
   ```

6. **Run composer install:**
   ```bash
   composer install
   ```

### What You Get

- **Automatic Redis tracing** for all `Redis::` calls
- **Queue job lifecycle tracking** with connected traces
- **Database query instrumentation** via Eloquent and raw queries
- **HTTP request tracing** for external API calls
- **Route-based URL folding** for better trace grouping
- **Zero performance impact** when tracing is disabled

No changes to your existing business logic required!

## License

The Laravel framework is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
