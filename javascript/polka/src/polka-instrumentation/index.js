const { InstrumentationBase } = require('@opentelemetry/instrumentation');
const { context, trace } = require('@opentelemetry/api');

class PolkaInstrumentation extends InstrumentationBase {
  constructor(config = {}) {
    super('@opentelemetry/instrumentation-polka', '0.1.0', config);
    this._patchedApps = new WeakSet();
  }

  init() {
    // No module patching needed; Polka is app instance based
    return [];
  }

  /**
   * Patch a Polka app instance to auto-instrument requests.
   * @param {object} app - Polka app instance
   * @param {object} [options] - { serviceName?: string }
   */
  patchApp(app, options = {}) {
    if (this._patchedApps.has(app)) return;
    this._patchedApps.add(app);
    const tracer = this.tracer;
    const originalHandler = app.handler;
    app.handler = (req, res, info) => {
      // Find the matched route pattern
      let routePattern = '';
      const match = app.find(req.method, info?.pathname || req.url);
      if (match && match.handlers && Array.isArray(match.handlers)) {
        // Try to get the pattern from the matched route
        if (Array.isArray(app.routes[req.method])) {
          // Find the route array that matches the handler
          const arr = app.routes[req.method].find(r => {
            // r is an array of route segments, each with .old
            // match.handlers is the handler array for the matched route
            return r[0] && match.handlers === app.handlers[req.method][r[0].old];
          });
          if (arr && arr.length > 0) {
            // Join the .old values for the full pattern
            routePattern = arr.map(x => x.old).join('');
          }
        }
      }
      // Fallback to root or actual path if no pattern found
      if (!routePattern) {
        // If root route
        if ((info?.pathname || req.url) === '/') {
          routePattern = '/';
        } else {
          routePattern = info?.pathname || req.url;
        }
      }
      const spanName = `${req.method} ${routePattern}`;
      const span = tracer.startSpan(spanName, {
        attributes: {
          'http.route': routePattern,
          'http.method': req.method,
          'http.target': req.url,
        },
      });
      const parentContext = context.active();
      const spanContext = trace.setSpan(parentContext, span);
      let finished = false;
      res.once('finish', () => {
        if (!finished) {
          finished = true;
          span.end();
        }
      });
      return context.with(spanContext, () => originalHandler.call(app, req, res, info));
    };
  }
}

module.exports = {
  PolkaInstrumentation,
}; 