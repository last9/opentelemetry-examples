# Lumen Test App

A basic test application built with PHP 8.3+ and Lumen 10.0 framework.

## Requirements

- PHP 8.1, 8.2, or 8.3
- Composer
- Web server (Apache/Nginx) or PHP built-in server

## Installation

1. Clone or download this project
2. Install dependencies:
   ```bash
   composer install
   ```
3. Copy environment file:
   ```bash
   cp .env.example .env
   ```
4. Generate application key:
   ```bash
   php artisan key:generate
   ```

## Running the Application

### Using PHP Built-in Server
```bash
php -S localhost:8000 -t public
```

### Using Artisan Serve
```bash
php artisan serve
```

The application will be available at `http://localhost:8000`

## Available Endpoints

### Basic Routes

#### GET `/`
- **Description**: Welcome page with app information
- **Response**: JSON with app version, PHP version, and timestamp

#### GET `/test`
- **Description**: Basic test endpoint
- **Response**: JSON with status, message, and random data

#### GET `/health`
- **Description**: Health check endpoint
- **Response**: JSON with service status and uptime

#### POST `/echo`
- **Description**: Echo endpoint that returns received data
- **Request**: Any JSON data
- **Response**: JSON with received data, headers, and request info

#### GET `/users`
- **Description**: Get list of users
- **Response**: JSON array of users with pagination info

#### GET `/users/{id}`
- **Description**: Get specific user by ID
- **Parameters**: `id` (integer)
- **Response**: JSON user object or 404 error

### API Routes (Controller-based)

#### GET `/api/info`
- **Description**: Get detailed application information
- **Response**: JSON with app config, PHP version, memory usage, etc.

#### POST `/api/validate`
- **Description**: Test validation functionality
- **Request Body**:
  ```json
  {
    "name": "John Doe",
    "email": "john@example.com",
    "age": 25,
    "interests": ["php", "lumen", "api"]
  }
  ```
- **Response**: JSON with validation result

#### GET `/api/error`
- **Description**: Test error handling
- **Query Parameters**:
  - `type`: Error type (`not_found`, `unauthorized`, `forbidden`, `server_error`, `exception`)
- **Response**: JSON error response with appropriate HTTP status

#### POST `/api/upload`
- **Description**: Test file upload simulation
- **Request**: Multipart form data with file
- **Response**: JSON with file information

#### GET `/api/paginated`
- **Description**: Test pagination functionality
- **Query Parameters**:
  - `page`: Page number (default: 1)
  - `per_page`: Items per page (default: 10)
- **Response**: JSON with paginated data and pagination metadata

#### GET `/api/cache`
- **Description**: Test caching simulation
- **Query Parameters**:
  - `action`: Cache action (`set`, `get`, `delete`)
  - `key`: Cache key
  - `value`: Value to cache (for set action)
- **Response**: JSON with cache operation result

## Testing the Endpoints

### Using curl

```bash
# Test basic endpoint
curl http://localhost:8000/

# Test health check
curl http://localhost:8000/health

# Test echo endpoint
curl -X POST http://localhost:8000/echo \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello World"}'

# Test validation
curl -X POST http://localhost:8000/api/validate \
  -H "Content-Type: application/json" \
  -d '{"name": "John", "email": "john@example.com", "age": 25}'

# Test pagination
curl "http://localhost:8000/api/paginated?page=1&per_page=5"

# Test error handling
curl "http://localhost:8000/api/error?type=not_found"
```

### Using Postman or similar tools

Import these sample requests:

1. **GET** `http://localhost:8000/`
2. **GET** `http://localhost:8000/health`
3. **POST** `http://localhost:8000/echo`
   - Body: `{"test": "data"}`
4. **GET** `http://localhost:8000/users`
5. **GET** `http://localhost:8000/users/1`
6. **GET** `http://localhost:8000/api/info`
7. **POST** `http://localhost:8000/api/validate`
   - Body: `{"name": "Test", "email": "test@example.com", "age": 30}`
8. **GET** `http://localhost:8000/api/paginated?page=1&per_page=10`

## Features Demonstrated

- ✅ Basic routing and responses
- ✅ JSON API responses
- ✅ Request validation
- ✅ Error handling
- ✅ File upload handling
- ✅ Pagination
- ✅ Caching simulation
- ✅ Controller usage
- ✅ Route grouping
- ✅ Parameter binding
- ✅ HTTP status codes
- ✅ Request/Response handling

## Project Structure

```
php-lumen-app/
├── app/
│   ├── Http/
│   │   └── Controllers/
│   │       └── TestController.php    # Main test controller
│   └── ...
├── routes/
│   └── web.php                       # All routes defined here
├── public/
│   └── index.php                     # Entry point
├── .env                              # Environment configuration
├── composer.json                     # Dependencies
└── README_TEST_APP.md               # This file
```

## Next Steps

To extend this test app, you could:

1. Add database integration
2. Implement authentication
3. Add more complex validation rules
4. Create middleware
5. Add logging functionality
6. Implement real caching
7. Add unit tests
8. Create API documentation

## Troubleshooting

- **500 Error**: Check if `.env` file exists and has proper configuration
- **404 Error**: Ensure the web server is pointing to the `public` directory
- **Permission Issues**: Make sure `storage` directory is writable
- **Composer Issues**: Run `composer install` to install dependencies

## Support

This is a basic test application. For more information about Lumen, visit the [official documentation](https://lumen.laravel.com/docs).

