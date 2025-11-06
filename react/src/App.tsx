import React, { useState } from 'react';
import { traceUserAction, startCustomSpan } from './telemetry';
import { SpanStatusCode } from '@opentelemetry/api';

function App() {
  const [count, setCount] = useState(0);
  const [apiData, setApiData] = useState<any>(null);
  const [loading, setLoading] = useState(false);

  // Handler for counter with custom span tracking
  const handleCounterChange = (action: string, newCount: number) => {
    const span = startCustomSpan('user.counter_interaction', {
      'user.action': action,
      'counter.previous_value': count,
      'counter.new_value': newCount,
    });

    try {
      setCount(newCount);
      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error instanceof Error ? error.message : String(error)
      });
    } finally {
      span.end();
    }
  };

  // Sample API calls that will be automatically traced
  const fetchUserData = async () => {
    // Wrap the entire operation in a custom span to track user action
    await traceUserAction(
      'user.fetch_external_user_data',
      {
        'user.action': 'fetch_user',
        'api.endpoint': 'jsonplaceholder.typicode.com/users/1',
        'api.type': 'external',
      },
      async () => {
        setLoading(true);
        try {
          // This will be automatically traced by OpenTelemetry
          const response = await fetch('https://jsonplaceholder.typicode.com/users/1');
          const data = await response.json();
          setApiData(data);
        } catch (error) {
          console.error('Error fetching user data:', error);
          throw error; // Re-throw to mark span as failed
        } finally {
          setLoading(false);
        }
      }
    );
  };

  const fetchPosts = async () => {
    setLoading(true);
    try {
      // This will also be automatically traced
      const response = await fetch('https://jsonplaceholder.typicode.com/posts?_limit=5');
      const data = await response.json();
      setApiData(data);
    } catch (error) {
      console.error('Error fetching posts:', error);
    } finally {
      setLoading(false);
    }
  };

  const fetchBackendUsers = async () => {
    setLoading(true);
    try {
      // Call our Node.js backend - this will test context propagation
      const response = await fetch('http://localhost:3001/api/users');
      const data = await response.json();
      setApiData(data);
    } catch (error) {
      console.error('Error fetching backend users:', error);
    } finally {
      setLoading(false);
    }
  };

  const fetchBackendPosts = async () => {
    setLoading(true);
    try {
      // Call our Node.js backend for posts
      const response = await fetch('http://localhost:3001/api/posts');
      const data = await response.json();
      setApiData(data);
    } catch (error) {
      console.error('Error fetching backend posts:', error);
    } finally {
      setLoading(false);
    }
  };

  const testBackendProcess = async () => {
    setLoading(true);
    try {
      // Test a slow endpoint to see timing
      const response = await fetch('http://localhost:3001/api/process');
      const data = await response.json();
      setApiData(data);
    } catch (error) {
      console.error('Error testing backend process:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="app">
      <div className="container">
        <h1 className="title">
          Hello World! 👋
        </h1>
        <p className="subtitle">
          Welcome to your React Demo App with API Tracing
        </p>
        
        <div className="card">
          <h2 className="card-title">
            Simple Counter Demo
          </h2>
          <div className="counter">
            {count}
          </div>
          <div className="button-group">
            <button
              onClick={() => handleCounterChange('decrease', count - 1)}
              className="button button-decrease"
            >
              - Decrease
            </button>
            <button
              onClick={() => handleCounterChange('reset', 0)}
              className="button button-reset"
            >
              Reset
            </button>
            <button
              onClick={() => handleCounterChange('increase', count + 1)}
              className="button button-increase"
            >
              + Increase
            </button>
          </div>
        </div>

        <div className="card">
          <h2 className="card-title">
            External API Calls (Auto-Traced)
          </h2>
          <p className="subtitle">
            Third-party API calls for testing external service tracing
          </p>
          <div className="button-group">
            <button
              onClick={fetchUserData}
              className="button button-increase"
              disabled={loading}
            >
              {loading ? 'Loading...' : 'External Users'}
            </button>
            <button
              onClick={fetchPosts}
              className="button button-increase"
              disabled={loading}
            >
              {loading ? 'Loading...' : 'External Posts'}
            </button>
          </div>
        </div>

        <div className="card">
          <h2 className="card-title">
            Backend API Calls (Context Propagation Test)
          </h2>
          <p className="subtitle">
            Calls to our Node.js backend to test end-to-end tracing
          </p>
          <div className="button-group">
            <button
              onClick={fetchBackendUsers}
              className="button button-increase"
              disabled={loading}
            >
              {loading ? 'Loading...' : 'Backend Users'}
            </button>
            <button
              onClick={fetchBackendPosts}
              className="button button-increase"
              disabled={loading}
            >
              {loading ? 'Loading...' : 'Backend Posts'}
            </button>
            <button
              onClick={testBackendProcess}
              className="button button-increase"
              disabled={loading}
            >
              {loading ? 'Processing...' : 'Slow Process'}
            </button>
          </div>
          
          {apiData && (
            <div className="api-response">
              <h3>API Response:</h3>
              <pre>{JSON.stringify(apiData, null, 2)}</pre>
            </div>
          )}
        </div>
        
        <p className="footer">
          Ready for OpenTelemetry instrumentation! 🚀<br/>
          Check your Last9 dashboard for HTTP request traces
        </p>
      </div>
    </div>
  );
}

export default App;
