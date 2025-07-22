# Azure Load Testing Configuration Template
# This configuration defines the load test parameters and failure criteria

version: v0.1
testId: performance-regression-test
displayName: Performance Regression Detection Test
description: Automated load test for CI/CD pipeline performance validation
testPlan: loadtest.jmx

# Test execution configuration
engineInstances: 1
subnetId: null

# Test properties that will be passed to JMeter
properties:
  webapp_url: ${app_url}
  virtual_users: ${virtual_users}
  ramp_up_time: ${ramp_up_time_seconds}
  test_duration: ${test_duration_seconds}

# Environment variables for the test
env:
  - name: WEBAPP_URL
    value: ${app_url}

# Failure criteria that will trigger test failure
failureCriteria:
  # Response time threshold - test fails if average response time exceeds this value
  - aggregate: avg
    clientMetric: response_time_ms
    condition: '>'
    value: ${response_time_threshold}
    
  # Error rate threshold - test fails if error percentage exceeds this value
  - aggregate: percentage
    clientMetric: error
    condition: '>'
    value: ${error_rate_threshold}
    
  # 95th percentile response time - additional performance check
  - aggregate: percentile
    clientMetric: response_time_ms
    condition: '>'
    value: ${response_time_threshold * 1.5}
    percentile: 95

# Auto-stop configuration
autoStop:
  autoStopDisabled: false
  errorRate: ${error_rate_threshold + 5}
  errorRateTimeWindowInSeconds: 60

# Load test monitoring configuration
monitoring:
  # Enable Application Insights integration
  appInsights:
    enabled: true
    
  # Enable resource monitoring
  resourceMonitoring:
    enabled: true