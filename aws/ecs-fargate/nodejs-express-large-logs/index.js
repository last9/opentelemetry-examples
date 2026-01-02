const express = require('express');

const app = express();
const PORT = process.env.PORT || 3000;

// Helper function to generate a large nested context object (>30KB)
function generateLargeContext() {
  const largeContext = {
    requestId: `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    timestamp: new Date().toISOString(),
    user: {
      id: Math.floor(Math.random() * 100000),
      name: `user_${Math.random().toString(36).substr(2, 9)}`,
      email: `user${Math.random().toString(36).substr(2, 9)}@example.com`,
      roles: ['admin', 'user', 'developer', 'tester'],
      metadata: {
        loginCount: Math.floor(Math.random() * 1000),
        lastLogin: new Date().toISOString(),
        preferences: {}
      }
    },
    session: {
      id: `session-${Math.random().toString(36).substr(2, 20)}`,
      createdAt: new Date().toISOString(),
      expiresAt: new Date(Date.now() + 3600000).toISOString()
    },
    // Generate a large array of data to exceed 30KB
    dataRecords: [],
    nestedStructure: {
      level1: {
        level2: {
          level3: {
            level4: {
              level5: {
                data: []
              }
            }
          }
        }
      }
    }
  };

  // Add large amount of data to exceed 30KB
  // Each record is approximately 200-300 bytes, so we need ~150-200 records to exceed 30KB
  for (let i = 0; i < 200; i++) {
    largeContext.dataRecords.push({
      id: i,
      uuid: `${Math.random().toString(36).substr(2, 9)}-${Math.random().toString(36).substr(2, 9)}-${Math.random().toString(36).substr(2, 9)}`,
      timestamp: new Date(Date.now() - Math.random() * 86400000).toISOString(),
      status: ['success', 'pending', 'failed', 'processing'][Math.floor(Math.random() * 4)],
      message: `This is a sample message for record ${i} with some additional text to increase size. Lorem ipsum dolor sit amet, consectetur adipiscing elit.`,
      payload: {
        key1: Math.random().toString(36).substr(2, 20),
        key2: Math.random().toString(36).substr(2, 20),
        key3: Math.random().toString(36).substr(2, 20),
        nestedData: {
          field1: `value-${Math.random().toString(36).substr(2, 15)}`,
          field2: `value-${Math.random().toString(36).substr(2, 15)}`,
          field3: `value-${Math.random().toString(36).substr(2, 15)}`
        }
      },
      metadata: {
        source: 'api',
        version: '1.0.0',
        tags: ['tag1', 'tag2', 'tag3', 'tag4']
      }
    });
  }

  // Add more nested data
  for (let i = 0; i < 50; i++) {
    largeContext.nestedStructure.level1.level2.level3.level4.level5.data.push({
      index: i,
      value: Math.random().toString(36).substr(2, 50),
      description: `Nested data entry ${i} with additional information to increase the overall size of the context object.`
    });
  }

  return largeContext;
}

// Helper function to generate a small context object
function generateSmallContext() {
  return {
    requestId: `req-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`,
    timestamp: new Date().toISOString(),
    user: {
      id: Math.floor(Math.random() * 100000),
      name: `user_${Math.random().toString(36).substr(2, 9)}`
    }
  };
}

// Helper function to log JSON with context (30% small, 70% large)
function logWithContext(level, message, additionalFields = {}) {
  const isSmallLog = Math.random() < 0.3; // 30% chance of small log
  const context = isSmallLog ? generateSmallContext() : generateLargeContext();

  const logEntry = {
    level,
    message,
    timestamp: new Date().toISOString(),
    context,
    ...additionalFields
  };

  console.log(JSON.stringify(logEntry));

  // Also log the size for monitoring
  const logSize = JSON.stringify(logEntry).length;
  if (!isSmallLog && logSize > 30000) {
    console.log(JSON.stringify({
      level: 'info',
      message: `Generated large log: ${logSize} bytes`,
      timestamp: new Date().toISOString()
    }));
  }
}

// Middleware
app.use(express.json());

// Routes
app.get('/', (req, res) => {
  logWithContext('info', 'Received request to root endpoint', {
    path: req.path,
    method: req.method,
    ip: req.ip
  });

  res.json({
    status: 'ok',
    message: 'ECS Fargate Large Logs Example',
    timestamp: new Date().toISOString()
  });
});

app.get('/health', (req, res) => {
  logWithContext('info', 'Health check', {
    path: req.path,
    healthy: true
  });

  res.json({ status: 'healthy' });
});

app.post('/api/data', (req, res) => {
  logWithContext('info', 'Processing data request', {
    path: req.path,
    method: req.method,
    bodySize: JSON.stringify(req.body).length
  });

  res.json({
    status: 'processed',
    timestamp: new Date().toISOString()
  });
});

app.get('/api/generate-logs/:count', (req, res) => {
  const count = parseInt(req.params.count) || 10;

  logWithContext('info', `Generating ${count} log entries`, {
    path: req.path,
    count
  });

  for (let i = 0; i < count; i++) {
    logWithContext('info', `Generated log entry ${i + 1}/${count}`, {
      iteration: i + 1,
      total: count
    });
  }

  res.json({
    status: 'completed',
    logsGenerated: count,
    timestamp: new Date().toISOString()
  });
});

// Error handling
app.use((err, req, res, next) => {
  logWithContext('error', 'Unhandled error', {
    error: err.message,
    stack: err.stack,
    path: req.path
  });

  res.status(500).json({
    status: 'error',
    message: err.message
  });
});

// Generate logs periodically (every 5 seconds)
setInterval(() => {
  logWithContext('info', 'Periodic log generation', {
    type: 'automated',
    interval: '5s'
  });
}, 5000);

app.listen(PORT, () => {
  console.log(JSON.stringify({
    level: 'info',
    message: `Server started on port ${PORT}`,
    timestamp: new Date().toISOString(),
    port: PORT
  }));
});
