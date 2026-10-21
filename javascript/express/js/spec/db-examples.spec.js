// Runs src/db-examples.js against unreachable databases: every route that
// acquires a connection must answer 500 instead of crashing the process.
const { spawn } = require('node:child_process');
const { once } = require('node:events');
const path = require('node:path');

const PORT = 31412;
const BASE_URL = `http://127.0.0.1:${PORT}`;
const UNREACHABLE = '127.0.0.1';

describe('db-examples with databases unavailable', () => {
  let server;
  let output;

  // A fresh server per spec, so one crash cannot hide the next case.
  beforeEach(async () => {
    output = '';
    server = spawn(process.execPath, [path.join(__dirname, '..', 'src', 'db-examples.js')], {
      env: {
        ...process.env,
        PORT: String(PORT),
        PG_HOST: UNREACHABLE,
        PG_PORT: '1',
        MYSQL_HOST: UNREACHABLE,
        MYSQL_PORT: '1',
        MONGO_URI: `mongodb://${UNREACHABLE}:1/?serverSelectionTimeoutMS=500`,
        REDIS_HOST: UNREACHABLE,
        REDIS_PORT: '1',
        OTEL_EXPORTER_OTLP_ENDPOINT: `http://${UNREACHABLE}:1`,
      },
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    server.stdout.on('data', (chunk) => { output += chunk; });
    server.stderr.on('data', (chunk) => { output += chunk; });

    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error(`startup timeout:\n${output}`)), 10000);
      server.stdout.on('data', () => {
        if (output.includes(`Server running on http://localhost:${PORT}`)) {
          clearTimeout(timer);
          resolve();
        }
      });
      server.once('exit', (code) => {
        clearTimeout(timer);
        reject(new Error(`server exited ${code} during startup:\n${output}`));
      });
    });
  }, 15000);

  afterEach(async () => {
    // Give an escaped rejection time to terminate the process before checking.
    await new Promise((resolve) => setTimeout(resolve, 300));
    expect(server.exitCode).withContext(`server must stay up:\n${output}`).toBeNull();
    if (server.exitCode === null) {
      server.kill('SIGKILL');
      await once(server, 'exit');
    }
  });

  function post(route, body) {
    return fetch(`${BASE_URL}${route}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(5000),
    });
  }

  it('GET /api/pg/users returns 500', async () => {
    const res = await fetch(`${BASE_URL}/api/pg/users`, { signal: AbortSignal.timeout(5000) });
    expect(res.status).toBe(500);
  });

  it('POST /api/pg/users returns 500 when the connection cannot be acquired', async () => {
    const res = await post('/api/pg/users', { name: 'Synthetic', email: 'synthetic@example.invalid' });
    expect(res.status).toBe(500);
    expect((await res.json()).error).toBeTruthy();
  });

  it('POST /api/mysql/products/bulk returns 500 when the connection cannot be acquired', async () => {
    const res = await post('/api/mysql/products/bulk', { products: [{ name: 'Widget', price: 1, stock: 1 }] });
    expect(res.status).toBe(500);
    expect((await res.json()).error).toBeTruthy();
  });

  it('POST /api/mysql/products/bulk returns 500 when products is missing', async () => {
    const res = await post('/api/mysql/products/bulk', {});
    expect(res.status).toBe(500);
  });

  it('POST /api/orders/process returns 500 when the connection cannot be acquired', async () => {
    const res = await post('/api/orders/process', { userId: 1, items: [{ productId: 1, quantity: 1, price: 1 }] });
    expect(res.status).toBe(500);
    expect((await res.json()).error).toBeTruthy();
  });

  it('POST /api/orders/process returns 500 when items is missing', async () => {
    const res = await post('/api/orders/process', { userId: 1 });
    expect(res.status).toBe(500);
  });
});
