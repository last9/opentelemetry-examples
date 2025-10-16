import { Component } from '@angular/core';
import { RouterOutlet } from '@angular/router';
import { monitoringTests } from './test-scenarios';

@Component({
  selector: 'app-root',
  imports: [RouterOutlet],
  templateUrl: './app.html',
  styleUrl: './app.css'
})
export class App {
  protected title = 'last9-angular-sample';

  // Test scenario methods
  runAllTests() {
    monitoringTests.runAllTests();
  }

  runJavaScriptErrors() {
    monitoringTests.runTest('javascript-errors');
  }

  runNetworkErrors() {
    monitoringTests.runTest('network-errors');
  }

  runPerformanceIssues() {
    monitoringTests.runTest('performance-issues');
  }

  runUserInteractionIssues() {
    monitoringTests.runTest('user-interaction-issues');
  }

  runAngularSpecificIssues() {
    monitoringTests.runTest('angular-specific-issues');
  }

  runBusinessLogicErrors() {
    monitoringTests.runTest('business-logic-errors');
  }

  runSuccessScenarios() {
    monitoringTests.runTest('success-scenarios');
  }
}
