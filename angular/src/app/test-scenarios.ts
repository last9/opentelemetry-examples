import opentelemetry from '@opentelemetry/api';
import { environment } from '../environments/environment';

type TestScenario = 
  | 'javascript-errors'
  | 'network-errors'
  | 'performance-issues'
  | 'user-interaction-issues'
  | 'angular-specific-issues'
  | 'business-logic-errors'
  | 'success-scenarios';

interface FormData {
  email: string;
  password: string;
  age: string;
}

/**
 * Test Scenarios for Last9 Monitoring Validation
 * 
 * This file contains various test scenarios to validate your monitoring setup.
 * Each scenario produces specific traces that you can monitor in Last9.
 */
export class MonitoringTestScenarios {
  private readonly tracer = opentelemetry.trace.getTracer('monitoring-test-tracer');
  private readonly httpbinUrl: string = 'https://httpbin.org';
  private readonly githubUrl: string = 'https://api.github.com';

  /**
   * SCENARIO 1: JavaScript Errors
   * Tests: Error tracking, stack traces, error categorization
   */
  testJavaScriptErrors(): void {
    console.log('🧪 Testing JavaScript Errors...');
    
    // Test 1: Reference Error
    setTimeout(() => {
      try {
        // @ts-ignore - Intentionally causing error
        const undefinedVar = someUndefinedVariable;
      } catch (error) {
        const err = error as any;
        this.tracer.startActiveSpan('javascript-reference-error', (span) => {
          span.setAttribute('error.type', 'ReferenceError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('error.stack', err.stack);
          span.setAttribute('test.scenario', 'javascript-errors');
          span.setAttribute('http.status_code', 400);
          span.setAttribute('test.status_message', 'ReferenceError: Variable not defined');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Reference Error Test:', err);
          span.end();
        });
      }
    }, 1000);

    // Test 2: TypeError
    setTimeout(() => {
      try {
        // @ts-ignore - Intentionally causing error
        const nullObj: any = null;
        if (nullObj) {
          nullObj.someMethod();
        } else {
          throw new TypeError('Cannot read properties of null (reading someMethod)');
        }
      } catch (error) {
        const err = error as any;
        this.tracer.startActiveSpan('javascript-type-error', (span) => {
          span.setAttribute('error.type', 'TypeError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('test.scenario', 'javascript-errors');
          span.setAttribute('http.status_code', 400);
          span.setAttribute('test.status_message', 'TypeError: Cannot read properties of null');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Type Error Test:', err);
          span.end();
        });
      }
    }, 2000);

    // Test 3: Syntax Error (simulated)
    setTimeout(() => {
      this.tracer.startActiveSpan('javascript-syntax-error', (span) => {
        span.setAttribute('error.type', 'SyntaxError');
        span.setAttribute('error.message', 'Unexpected token }');
        span.setAttribute('test.scenario', 'javascript-errors');
        span.setAttribute('http.status_code', 400);
        span.setAttribute('test.status_message', 'SyntaxError: Unexpected token }');
        span.setAttribute('environment', environment.environment);
        console.error('❌ Syntax Error Test: Unexpected token }');
        span.end();
      });
    }, 3000);
  }

  /**
   * SCENARIO 2: Network Request Errors
   * Tests: API failures, timeouts, CORS errors, HTTP status codes
   */
  testNetworkErrors(): void {
    console.log('🌐 Testing Network Request Errors...');

    // Test 1: 404 Error
    setTimeout(() => {
      this.tracer.startActiveSpan('network-404-error', (span) => {
        fetch(`${this.httpbinUrl}/status/404`)
          .then(response => {
            span.setAttribute('http.status_code', response.status);
            span.setAttribute('http.status_text', response.statusText);
            span.setAttribute('http.url', `${this.httpbinUrl}/status/404`);
            span.setAttribute('test.scenario', 'network-errors');
            span.setAttribute('test.status_message', 'HTTP 404: Not Found');
            span.setAttribute('environment', environment.environment);
            console.log('❌ 404 Error Test:', response.status);
            span.end();
          })
          .catch(error => {
            const err = error as any;
            span.setAttribute('error', true);
            span.setAttribute('error.message', err.message);
            span.setAttribute('http.status_code', 500);
            span.setAttribute('test.status_message', 'Network request failed');
            span.setAttribute('environment', environment.environment);
            span.end();
          });
      });
    }, 1000);

    // Test 2: 500 Error
    setTimeout(() => {
      this.tracer.startActiveSpan('network-500-error', (span) => {
        fetch(`${this.httpbinUrl}/status/500`)
          .then(response => {
            span.setAttribute('http.status_code', response.status);
            span.setAttribute('http.status_text', response.statusText);
            span.setAttribute('http.url', `${this.httpbinUrl}/status/500`);
            span.setAttribute('test.scenario', 'network-errors');
            span.setAttribute('test.status_message', 'HTTP 500: Internal Server Error');
            span.setAttribute('environment', environment.environment);
            console.log('❌ 500 Error Test:', response.status);
            span.end();
          });
      });
    }, 2000);

    // Test 3: Network Timeout
    setTimeout(() => {
      this.tracer.startActiveSpan('network-timeout', (span) => {
        const controller = new AbortController();
        setTimeout(() => controller.abort(), 1000);

        fetch(`${this.httpbinUrl}/delay/10`, { signal: controller.signal })
          .then(response => response.json())
          .catch(error => {
            const err = error as any;
            span.setAttribute('error', true);
            span.setAttribute('error.type', 'AbortError');
            span.setAttribute('error.message', 'Request timeout');
            span.setAttribute('test.scenario', 'network-errors');
            span.setAttribute('http.status_code', 408);
            span.setAttribute('test.status_message', 'Request Timeout');
            span.setAttribute('environment', environment.environment);
            console.log('❌ Network Timeout Test:', err.message);
            span.end();
          });
      });
    }, 3000);

    // Test 4: CORS Error
    setTimeout(() => {
      this.tracer.startActiveSpan('network-cors-error', (span) => {
        fetch(`${this.githubUrl}/users/nonexistentuser123456789`)
          .then(response => {
            if (!response.ok) {
              span.setAttribute('http.status_code', response.status);
              span.setAttribute('http.status_text', response.statusText);
              span.setAttribute('test.scenario', 'network-errors');
              span.setAttribute('test.status_message', `HTTP ${response.status}: ${response.statusText}`);
              span.setAttribute('environment', environment.environment);
              console.log('❌ CORS/API Error Test:', response.status);
            }
            span.end();
          })
          .catch(error => {
            const err = error as any;
            span.setAttribute('error', true);
            span.setAttribute('error.message', err.message);
            span.setAttribute('http.status_code', 500);
            span.setAttribute('test.status_message', 'Network request failed');
            span.setAttribute('environment', environment.environment);
            span.end();
          });
      });
    }, 4000);
  }

  /**
   * SCENARIO 3: Performance Issues
   * Tests: Slow operations, memory leaks, long-running tasks
   */
  testPerformanceIssues(): void {
    console.log('⚡ Testing Performance Issues...');

    // Test 1: Slow Operation
    setTimeout(() => {
      this.tracer.startActiveSpan('slow-operation', (span) => {
        const start = performance.now();
        
        // Simulate slow operation
        let result = 0;
        for (let i = 0; i < 10000000; i++) {
          result += Math.random();
        }
        
        const duration = performance.now() - start;
        span.setAttribute('operation.duration_ms', duration);
        span.setAttribute('operation.type', 'cpu-intensive');
        span.setAttribute('test.scenario', 'performance-issues');
        span.setAttribute('http.status_code', 200);
        span.setAttribute('test.status_message', 'Slow operation completed');
        span.setAttribute('environment', environment.environment);
        console.log('🐌 Slow Operation Test:', duration.toFixed(2), 'ms');
        span.end();
      });
    }, 1000);

    // Test 2: Memory Leak Simulation
    setTimeout(() => {
      this.tracer.startActiveSpan('memory-leak-simulation', (span) => {
        let memoryBefore = 0;
        let memoryAfter = 0;
        if ((performance as any).memory) {
          memoryBefore = (performance as any).memory.usedJSHeapSize || 0;
        }
        
        // Simulate memory leak
        const leakyArray: any[] = [];
        for (let i = 0; i < 100000; i++) {
          leakyArray.push(new Array(1000).fill('leak'));
        }
        
        if ((performance as any).memory) {
          memoryAfter = (performance as any).memory.usedJSHeapSize || 0;
        }
        const memoryIncrease = memoryAfter - memoryBefore;
        
        span.setAttribute('memory.increase_bytes', memoryIncrease);
        span.setAttribute('memory.leak_simulation', true);
        span.setAttribute('test.scenario', 'performance-issues');
        span.setAttribute('http.status_code', 200);
        span.setAttribute('test.status_message', 'Memory leak simulation completed');
        span.setAttribute('environment', environment.environment);
        console.log('💾 Memory Leak Test:', (memoryIncrease / 1024 / 1024).toFixed(2), 'MB increase');
        span.end();
      });
    }, 2000);

    // Test 3: Long-running Task
    setTimeout(() => {
      this.tracer.startActiveSpan('long-running-task', (span) => {
        const start = Date.now();
        
        // Simulate long task
        setTimeout(() => {
          const duration = Date.now() - start;
          span.setAttribute('task.duration_ms', duration);
          span.setAttribute('task.type', 'long-running');
          span.setAttribute('test.scenario', 'performance-issues');
          span.setAttribute('http.status_code', 200);
          span.setAttribute('test.status_message', 'Long running task completed');
          span.setAttribute('environment', environment.environment);
          console.log('⏱️ Long Running Task Test:', duration, 'ms');
          span.end();
        }, 3000);
      });
    }, 3000);
  }

  /**
   * SCENARIO 4: User Interaction Issues
   * Tests: Slow UI responses, unresponsive buttons, form validation errors
   */
  testUserInteractionIssues(): void {
    console.log('👆 Testing User Interaction Issues...');

    // Test 1: Slow Button Response
    setTimeout(() => {
      this.tracer.startActiveSpan('slow-button-response', (span) => {
        const start = performance.now();
        
        // Simulate slow button processing
        setTimeout(() => {
          const duration = performance.now() - start;
          span.setAttribute('interaction.duration_ms', duration);
          span.setAttribute('interaction.type', 'button-click');
          span.setAttribute('test.scenario', 'user-interaction-issues');
          span.setAttribute('http.status_code', 200);
          span.setAttribute('test.status_message', 'Slow button response completed');
          span.setAttribute('environment', environment.environment);
          console.log('🐌 Slow Button Test:', duration.toFixed(2), 'ms');
          span.end();
        }, 800); // Simulate 800ms delay
      });
    }, 1000);

    // Test 2: Form Validation Error
    setTimeout(() => {
      this.tracer.startActiveSpan('form-validation-error', (span) => {
        // Simulate form validation error
        const formData: FormData = {
          email: 'invalid-email',
          password: '123', // Too short
          age: 'abc' // Invalid number
        };

        const errors: string[] = [];
        
        if (!formData.email.includes('@')) {
          errors.push('Invalid email format');
        }
        if (formData.password.length < 8) {
          errors.push('Password too short');
        }
        if (isNaN(Number(formData.age))) {
          errors.push('Age must be a number');
        }

        span.setAttribute('form.errors_count', errors.length);
        span.setAttribute('form.errors', JSON.stringify(errors));
        span.setAttribute('test.scenario', 'user-interaction-issues');
        span.setAttribute('http.status_code', 422);
        span.setAttribute('test.status_message', 'Form validation failed');
        span.setAttribute('environment', environment.environment);
        console.log('❌ Form Validation Test:', errors);
        span.end();
      });
    }, 2000);

    // Test 3: Unresponsive UI
    setTimeout(() => {
      this.tracer.startActiveSpan('unresponsive-ui', (span) => {
        const start = performance.now();
        
        // Simulate UI freeze
        const heavyOperation = () => {
          let result = 0;
          for (let i = 0; i < 5000000; i++) {
            result += Math.sqrt(i);
          }
          return result;
        };

        // This will block the UI thread
        const result = heavyOperation();
        const duration = performance.now() - start;
        
        span.setAttribute('ui.freeze_duration_ms', duration);
        span.setAttribute('ui.operation_result', result);
        span.setAttribute('test.scenario', 'user-interaction-issues');
        span.setAttribute('http.status_code', 200);
        span.setAttribute('test.status_message', 'UI freeze simulation completed');
        span.setAttribute('environment', environment.environment);
        console.log('🔒 UI Freeze Test:', duration.toFixed(2), 'ms');
        span.end();
      });
    }, 3000);
  }

  /**
   * SCENARIO 5: Angular-Specific Issues
   * Tests: Change detection problems, component errors, service failures
   */
  testAngularSpecificIssues(): void {
    console.log('🅰️ Testing Angular-Specific Issues...');

    // Test 1: Change Detection Cycle Issues
    setTimeout(() => {
      this.tracer.startActiveSpan('change-detection-issue', (span) => {
        const start = performance.now();
        
        // Simulate expensive change detection
        let expensiveValue = 0;
        for (let i = 0; i < 100000; i++) {
          expensiveValue += Math.random() * Math.PI;
        }
        
        const duration = performance.now() - start;
        span.setAttribute('angular.change_detection_duration_ms', duration);
        span.setAttribute('angular.expensive_calculation', true);
        span.setAttribute('test.scenario', 'angular-specific-issues');
        span.setAttribute('http.status_code', 200);
        span.setAttribute('test.status_message', 'Change detection cycle completed');
        span.setAttribute('environment', environment.environment);
        console.log('🔄 Change Detection Test:', duration.toFixed(2), 'ms');
        span.end();
      });
    }, 1000);

    // Test 2: Component Initialization Error
    setTimeout(() => {
      this.tracer.startActiveSpan('component-init-error', (span) => {
        try {
          // Simulate component initialization error
          throw new Error('Component failed to initialize: Missing required dependency');
        } catch (error) {
          const err = error as any;
          span.setAttribute('error.type', 'ComponentInitializationError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('angular.component_name', 'TestComponent');
          span.setAttribute('test.scenario', 'angular-specific-issues');
          span.setAttribute('http.status_code', 500);
          span.setAttribute('test.status_message', 'Component initialization failed');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Component Init Error Test:', err.message);
          span.end();
        }
      });
    }, 2000);

    // Test 3: Service Injection Error
    setTimeout(() => {
      this.tracer.startActiveSpan('service-injection-error', (span) => {
        try {
          // Simulate service injection error
          throw new Error('Service injection failed: Circular dependency detected');
        } catch (error) {
          const err = error as any;
          span.setAttribute('error.type', 'ServiceInjectionError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('angular.service_name', 'TestService');
          span.setAttribute('test.scenario', 'angular-specific-issues');
          span.setAttribute('http.status_code', 500);
          span.setAttribute('test.status_message', 'Service injection failed');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Service Injection Error Test:', err.message);
          span.end();
        }
      });
    }, 3000);

    // Test 4: Router Navigation Error
    setTimeout(() => {
      this.tracer.startActiveSpan('router-navigation-error', (span) => {
        try {
          // Simulate router navigation error
          throw new Error('Route not found: /invalid-route');
        } catch (error) {
          const err = error as any;
          span.setAttribute('error.type', 'RouterNavigationError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('angular.route_path', '/invalid-route');
          span.setAttribute('test.scenario', 'angular-specific-issues');
          span.setAttribute('http.status_code', 404);
          span.setAttribute('test.status_message', 'Route not found');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Router Navigation Error Test:', err.message);
          span.end();
        }
      });
    }, 4000);
  }

  /**
   * SCENARIO 6: Business Logic Errors
   * Tests: Data processing errors, calculation mistakes, business rule violations
   */
  testBusinessLogicErrors(): void {
    console.log('💼 Testing Business Logic Errors...');

    // Test 1: Data Processing Error
    setTimeout(() => {
      this.tracer.startActiveSpan('data-processing-error', (span) => {
        try {
          // Simulate data processing error
          const invalidData = { amount: 'not-a-number', currency: 'USD' };
          const amount = parseFloat(invalidData.amount);
          
          if (isNaN(amount)) {
            throw new Error('Invalid amount format');
          }
        } catch (error) {
          const err = error as any;
          span.setAttribute('error.type', 'DataProcessingError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('business.data_type', 'payment_amount');
          span.setAttribute('test.scenario', 'business-logic-errors');
          span.setAttribute('http.status_code', 400);
          span.setAttribute('test.status_message', 'Data processing failed');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Data Processing Error Test:', err.message);
          span.end();
        }
      });
    }, 1000);

    // Test 2: Calculation Error
    setTimeout(() => {
      this.tracer.startActiveSpan('calculation-error', (span) => {
        try {
          // Simulate calculation error
          const values = [10, 20, 30, 'invalid', 50];
          // Filter only numbers for summing
          const sum = values.filter(v => typeof v === 'number').reduce((acc, val) => acc + (val as number), 0);
          if (sum !== 110) {
            throw new Error('Calculation failed: Invalid number in array');
          }
        } catch (error) {
          const err = error as any;
          span.setAttribute('error.type', 'CalculationError');
          span.setAttribute('error.message', err.message);
          span.setAttribute('business.calculation_type', 'sum');
          span.setAttribute('test.scenario', 'business-logic-errors');
          span.setAttribute('http.status_code', 400);
          span.setAttribute('test.status_message', 'Calculation failed');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Calculation Error Test:', err.message);
          span.end();
        }
      });
    }, 2000);

    // Test 3: Business Rule Violation
    setTimeout(() => {
      this.tracer.startActiveSpan('business-rule-violation', (span) => {
        try {
          // Simulate business rule violation
          const userAge = 15;
          const requiredAge = 18;
          
          if (userAge < requiredAge) {
            throw new Error(`User age ${userAge} is below required age ${requiredAge}`);
          }
        } catch (error) {
          const err = error as any;
          span.setAttribute('error.type', 'BusinessRuleViolation');
          span.setAttribute('error.message', err.message);
          span.setAttribute('business.rule', 'minimum_age_requirement');
          span.setAttribute('test.scenario', 'business-logic-errors');
          span.setAttribute('http.status_code', 422);
          span.setAttribute('test.status_message', 'Business rule violation');
          span.setAttribute('environment', environment.environment);
          console.error('❌ Business Rule Violation Test:', err.message);
          span.end();
        }
      });
    }, 3000);
  }

  /**
   * SCENARIO 7: Success Scenarios
   * Tests: Normal operations, successful API calls, good performance
   */
  testSuccessScenarios(): void {
    console.log('✅ Testing Success Scenarios...');

    // Test 1: Successful API Call
    setTimeout(() => {
      this.tracer.startActiveSpan('successful-api-call', (span) => {
        fetch(`${this.httpbinUrl}/status/200`)
          .then(response => {
            span.setAttribute('http.status_code', response.status);
            span.setAttribute('http.status_text', response.statusText);
            span.setAttribute('http.url', `${this.httpbinUrl}/status/200`);
            span.setAttribute('test.scenario', 'success-scenarios');
            span.setAttribute('test.status_message', 'API call successful');
            span.setAttribute('environment', environment.environment);
            console.log('✅ Successful API Test:', response.status);
            span.end();
          });
      });
    }, 1000);

    // Test 2: Fast Operation
    setTimeout(() => {
      this.tracer.startActiveSpan('fast-operation', (span) => {
        const start = performance.now();
        
        // Simulate fast operation
        const result = Math.random() * 100;
        
        const duration = performance.now() - start;
        span.setAttribute('operation.duration_ms', duration);
        span.setAttribute('operation.result', result);
        span.setAttribute('test.scenario', 'success-scenarios');
        span.setAttribute('http.status_code', 200);
        span.setAttribute('test.status_message', 'Fast operation completed');
        span.setAttribute('environment', environment.environment);
        console.log('⚡ Fast Operation Test:', duration.toFixed(2), 'ms');
        span.end();
      });
    }, 2000);

    // Test 3: Successful User Interaction
    setTimeout(() => {
      this.tracer.startActiveSpan('successful-user-interaction', (span) => {
        const start = performance.now();
        
        // Simulate successful user interaction
        setTimeout(() => {
          const duration = performance.now() - start;
          span.setAttribute('interaction.duration_ms', duration);
          span.setAttribute('interaction.type', 'button-click');
          span.setAttribute('interaction.success', true);
          span.setAttribute('test.scenario', 'success-scenarios');
          span.setAttribute('http.status_code', 200);
          span.setAttribute('test.status_message', 'User interaction successful');
          span.setAttribute('environment', environment.environment);
          console.log('👆 Successful Interaction Test:', duration.toFixed(2), 'ms');
          span.end();
        }, 50); // Fast response
      });
    }, 3000);
  }

  /**
   * Run all test scenarios
   */
  runAllTests(): void {
    console.log('🚀 Starting All Monitoring Test Scenarios...');
    console.log('📊 Check your Last9 dashboard for traces!');
    
    // Run tests with delays to avoid overwhelming
    setTimeout(() => this.testJavaScriptErrors(), 1000);
    setTimeout(() => this.testNetworkErrors(), 5000);
    setTimeout(() => this.testPerformanceIssues(), 9000);
    setTimeout(() => this.testUserInteractionIssues(), 13000);
    setTimeout(() => this.testAngularSpecificIssues(), 17000);
    setTimeout(() => this.testBusinessLogicErrors(), 21000);
    setTimeout(() => this.testSuccessScenarios(), 25000);
  }

  /**
   * Run specific test scenario
   */
  runTest(testName: string): void {
    switch (testName) {
      case 'javascript-errors':
        this.testJavaScriptErrors();
        break;
      case 'network-errors':
        this.testNetworkErrors();
        break;
      case 'performance-issues':
        this.testPerformanceIssues();
        break;
      case 'user-interaction-issues':
        this.testUserInteractionIssues();
        break;
      case 'angular-specific-issues':
        this.testAngularSpecificIssues();
        break;
      case 'business-logic-errors':
        this.testBusinessLogicErrors();
        break;
      case 'success-scenarios':
        this.testSuccessScenarios();
        break;
      default:
        console.log('Available tests: javascript-errors, network-errors, performance-issues, user-interaction-issues, angular-specific-issues, business-logic-errors, success-scenarios');
    }
  }
}

// Export for use in other files
export const monitoringTests = new MonitoringTestScenarios(); 