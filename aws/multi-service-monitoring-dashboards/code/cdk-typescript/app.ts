#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AdvancedMonitoringStack } from './lib/advanced-monitoring-stack';

const app = new cdk.App();

// Get configuration from context or environment
const config = {
  stackName: app.node.tryGetContext('stackName') || 'AdvancedMonitoringStack',
  environment: app.node.tryGetContext('environment') || 'production',
  projectName: app.node.tryGetContext('projectName') || 'advanced-monitoring',
  alertEmail: app.node.tryGetContext('alertEmail') || 'your-email@example.com',
  enableCostMonitoring: app.node.tryGetContext('enableCostMonitoring') || true,
  anomalyDetectionSensitivity: app.node.tryGetContext('anomalyDetectionSensitivity') || 2,
};

// Create the main monitoring stack
new AdvancedMonitoringStack(app, config.stackName, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Advanced Multi-Service Monitoring Dashboards with Custom Metrics and Anomaly Detection',
  config,
  tags: {
    Project: config.projectName,
    Environment: config.environment,
    Purpose: 'Monitoring',
    Recipe: 'advanced-multi-service-monitoring-dashboards-custom-metrics',
  },
});

app.synth();