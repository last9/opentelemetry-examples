import React from 'react';
import ReactDOM from 'react-dom/client';
import { setupTelemetry } from './telemetry';
import App from './App';

// Initialize OTel (traces + logs) before React renders anything
setupTelemetry();

const root = ReactDOM.createRoot(document.getElementById('root') as HTMLElement);
root.render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
