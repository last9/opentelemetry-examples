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

## Laravel Route-Based URL Folding for OpenTelemetry

### Overview

The Laravel route-based URL folding system provides intelligent URL grouping for OpenTelemetry traces by using your actual Laravel route definitions instead of pattern matching. This creates meaningful trace groupings that align with your application's architecture.

### How It Works

The system attempts to match incoming URLs against Laravel route definitions:

```php
// Route definition: Route::get('/users/{user}', 'UserController@show');
// URL: https://example.com/api/users/123
// Result: GET /api/users/{user}
```

### Benefits

✅ **Uses Actual Route Definitions**: Groups by real Laravel routes  
✅ **Semantic Parameter Names**: Preserves route parameter names like `{user}`, `{post}`  
✅ **Consistent Grouping**: Same URLs always group together  
✅ **Zero Configuration**: Always enabled by default  
✅ **Automatic Fallback**: Works even when Laravel routing unavailable  

### Route Folding Examples

```php
// Laravel route definitions
Route::get('/users/{user}', 'UserController@show');
Route::get('/users/{user}/posts/{post}', 'PostController@show');
Route::get('/orders/{uuid}', 'OrderController@show');
Route::get('/analytics/{date}', 'AnalyticsController@show');

// URL folding results
GET /api/users/123                    → GET /api/users/{user}
GET /api/users/123/posts/456          → GET /api/users/{user}/posts/{post}
GET /api/orders/{uuid}                → GET /api/orders/{uuid}
GET /api/analytics/2024-12-25         → GET /api/analytics/{date}
```

### Usage

```php
// URL folding happens automatically in middleware
// No manual configuration needed

// Custom HTTP requests with folding
$response = traced_http_request('GET', 'https://api.example.com/users/123');

// Laravel route generation with tracing
$url = traced_laravel_route('users.show', ['user' => 123]);
```

## License

The Laravel framework is open-sourced software licensed under the [MIT license](https://opensource.org/licenses/MIT).
