// Initialize OpenTelemetry BEFORE bootstrapping Angular
import { setupTelemetry } from './telemetry';
import { environment } from './environment';
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { App } from './app/app';

// Configure OpenTelemetry from environment
// This makes the configuration available to the telemetry setup
(window as any).__OTEL_CONFIG__ = environment.otel;

// Initialize telemetry before Angular bootstraps
setupTelemetry();

// Bootstrap Angular application
bootstrapApplication(App, appConfig)
  .catch((err) => console.error(err));
