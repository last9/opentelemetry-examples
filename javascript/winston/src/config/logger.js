const winston = require("winston");
const { OTLPLogExporter } = require("@opentelemetry/exporter-logs-otlp-http");
const {
  OpenTelemetryTransportV3,
} = require("@opentelemetry/winston-transport");
const { resourceFromAttributes } = require("@opentelemetry/resources");
const logsAPI = require("@opentelemetry/api-logs");
const {
  LoggerProvider,
  SimpleLogRecordProcessor,
} = require("@opentelemetry/sdk-logs");

// const { diag, DiagConsoleLogger, DiagLogLevel } = require("@opentelemetry/api");
// For troubleshooting, set the log level to DiagLogLevel.DEBUG
// diag.setLogger(new DiagConsoleLogger(), DiagLogLevel.DEBUG);

// Initialize logger provider
const loggerProvider = new LoggerProvider({
  resource: resourceFromAttributes({
    ["service.name"]: process.env.OTEL_SERVICE_NAME,
    ["deployment.environment"]: process.env.NODE_ENV,
  }),
});

// In the current version of the OpenTelemetry SDK, even though the deprecation warning is shown,
// the SimpleLogRecordProcessor is still the recommended way to process logs.
loggerProvider.addLogRecordProcessor(
  new SimpleLogRecordProcessor(new OTLPLogExporter()),
);

// Setup Global Logger Provider
logsAPI.logs.setGlobalLoggerProvider(loggerProvider);

// Define log format
const logFormat = winston.format.combine(
  winston.format.timestamp({ format: "YYYY-MM-DD HH:mm:ss" }),
  winston.format.errors({ stack: true }),
  winston.format.splat(),
  winston.format.json(),
);

// Create the winston logger
const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || "info",
  format: logFormat,
  defaultMeta: { service: "express-api-server" },
  transports: [
    // Write all logs to console
    new winston.transports.Console({
      format: winston.format.combine(
        winston.format.colorize(),
        winston.format.simple(),
      ),
    }),
    // Enable OpenTelemetry logging to Last9
    new OpenTelemetryTransportV3({
      loggerProvider: loggerProvider,
    }),
  ],
});

// Create a stream object with a 'write' function that will be used by Morgan
logger.stream = {
  write: function (message) {
    logger.info(message.trim());
  },
};

module.exports = logger;
