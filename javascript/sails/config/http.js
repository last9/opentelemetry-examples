/**
 * HTTP Server Settings
 */

module.exports.http = {
    middleware: {
      order: [
        'cookieParser',
        'session',
        'bodyParser',
        'compress',
        'router',
        'www',
        'favicon',
      ]
    }
  };