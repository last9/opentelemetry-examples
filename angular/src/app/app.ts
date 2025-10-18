import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { monitoringTests } from './test-scenarios';

type TestScenario = 
  | 'javascript-errors'
  | 'network-errors'
  | 'performance-issues'
  | 'user-interaction-issues'
  | 'angular-specific-issues'
  | 'business-logic-errors'
  | 'success-scenarios';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {
  protected readonly title = 'last9-angular-sample';

  /**
   * Run all monitoring test scenarios
   */
  runAllTests(): void {
    monitoringTests.runAllTests();
  }

  /**
   * Run JavaScript error test scenarios
   */
  runJavaScriptErrors(): void {
    this.runTest('javascript-errors');
  }

  /**
   * Run network error test scenarios
   */
  runNetworkErrors(): void {
    this.runTest('network-errors');
  }

  /**
   * Run performance issue test scenarios
   */
  runPerformanceIssues(): void {
    this.runTest('performance-issues');
  }

  /**
   * Run user interaction issue test scenarios
   */
  runUserInteractionIssues(): void {
    this.runTest('user-interaction-issues');
  }

  /**
   * Run Angular-specific issue test scenarios
   */
  runAngularSpecificIssues(): void {
    this.runTest('angular-specific-issues');
  }

  /**
   * Run business logic error test scenarios
   */
  runBusinessLogicErrors(): void {
    this.runTest('business-logic-errors');
  }

  /**
   * Run success scenario tests
   */
  runSuccessScenarios(): void {
    this.runTest('success-scenarios');
  }

  /**
   * Run a specific test scenario
   * @param scenario - The test scenario to run
   */
  private runTest(scenario: TestScenario): void {
    monitoringTests.runTest(scenario);
  }
}
