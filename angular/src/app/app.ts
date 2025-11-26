import { Component, inject } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { CommonModule } from '@angular/common';
import { traceUserAction, startCustomSpan } from '../telemetry';
import { SpanStatusCode } from '@opentelemetry/api';

@Component({
  selector: 'app-root',
  imports: [CommonModule],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {
  private http = inject(HttpClient);

  count = 0;
  apiData: any = null;
  loading = false;

  // Handler for counter with custom span tracking
  handleCounterChange(action: string, newCount: number): void {
    const span = startCustomSpan('user.counter_interaction', {
      'user.action': action,
      'counter.previous_value': this.count,
      'counter.new_value': newCount,
    });

    try {
      this.count = newCount;
      span.setStatus({ code: SpanStatusCode.OK });
    } catch (error) {
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error instanceof Error ? error.message : String(error)
      });
    } finally {
      span.end();
    }
  }

  // Sample API calls that will be automatically traced
  async fetchUserData(): Promise<void> {
    // Wrap the entire operation in a custom span to track user action
    await traceUserAction(
      'user.fetch_external_user_data',
      {
        'user.action': 'fetch_user',
        'api.endpoint': 'jsonplaceholder.typicode.com/users/1',
        'api.type': 'external',
      },
      async () => {
        this.loading = true;
        try {
          // This will be automatically traced by OpenTelemetry
          const data = await fetch('https://jsonplaceholder.typicode.com/users/1');
          this.apiData = await data.json();
        } catch (error) {
          console.error('Error fetching user data:', error);
          throw error; // Re-throw to mark span as failed
        } finally {
          this.loading = false;
        }
      }
    );
  }

  async fetchPosts(): Promise<void> {
    this.loading = true;
    try {
      // This will also be automatically traced
      const data = await fetch('https://jsonplaceholder.typicode.com/posts?_limit=5');
      this.apiData = await data.json();
    } catch (error) {
      console.error('Error fetching posts:', error);
    } finally {
      this.loading = false;
    }
  }

  async fetchBackendUsers(): Promise<void> {
    this.loading = true;
    try {
      // Call our Node.js backend - this will test context propagation
      const data = await fetch('http://localhost:3001/api/users');
      this.apiData = await data.json();
    } catch (error) {
      console.error('Error fetching backend users:', error);
    } finally {
      this.loading = false;
    }
  }

  async fetchBackendPosts(): Promise<void> {
    this.loading = true;
    try {
      // Call our Node.js backend for posts
      const data = await fetch('http://localhost:3001/api/posts');
      this.apiData = await data.json();
    } catch (error) {
      console.error('Error fetching backend posts:', error);
    } finally {
      this.loading = false;
    }
  }

  async testBackendProcess(): Promise<void> {
    this.loading = true;
    try {
      // Test a slow endpoint to see timing
      const data = await fetch('http://localhost:3001/api/process');
      this.apiData = await data.json();
    } catch (error) {
      console.error('Error testing backend process:', error);
    } finally {
      this.loading = false;
    }
  }
}
