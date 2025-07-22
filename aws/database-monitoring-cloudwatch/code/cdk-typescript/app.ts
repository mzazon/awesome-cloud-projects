#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DatabaseMonitoringStack } from './lib/database-monitoring-stack';

/**
 * CDK Application for Database Monitoring with CloudWatch
 * 
 * This application creates a comprehensive database monitoring solution including:
 * - RDS MySQL instance with enhanced monitoring
 * - CloudWatch dashboard for real-time visualization
 * - CloudWatch alarms for proactive alerting
 * - SNS topic for email notifications
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'development';
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;

// Validate required parameters
if (!alertEmail) {
  throw new Error('Alert email is required. Set ALERT_EMAIL environment variable or use --context alertEmail=your-email@example.com');
}

// Create the database monitoring stack
new DatabaseMonitoringStack(app, 'DatabaseMonitoringStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Stack configuration
  description: 'Comprehensive database monitoring solution with CloudWatch dashboards and alarms',
  // Custom props for the stack
  alertEmail,
  environment,
  // Optional overrides from context
  databaseInstanceClass: app.node.tryGetContext('databaseInstanceClass') || 'db.t3.micro',
  databaseAllocatedStorage: Number(app.node.tryGetContext('databaseAllocatedStorage')) || 20,
  databaseName: app.node.tryGetContext('databaseName') || 'monitoringdemo',
  databaseUsername: app.node.tryGetContext('databaseUsername') || 'admin',
  monitoringInterval: Number(app.node.tryGetContext('monitoringInterval')) || 60,
  performanceInsightsRetentionPeriod: Number(app.node.tryGetContext('performanceInsightsRetentionPeriod')) || 7,
  cpuAlarmThreshold: Number(app.node.tryGetContext('cpuAlarmThreshold')) || 80,
  connectionsAlarmThreshold: Number(app.node.tryGetContext('connectionsAlarmThreshold')) || 50,
  freeStorageSpaceThreshold: Number(app.node.tryGetContext('freeStorageSpaceThreshold')) || 2147483648, // 2GB in bytes
});

// Add tags to all resources in the application
cdk.Tags.of(app).add('Project', 'DatabaseMonitoring');
cdk.Tags.of(app).add('Environment', environment);
cdk.Tags.of(app).add('ManagedBy', 'CDK');
cdk.Tags.of(app).add('Purpose', 'DatabaseMonitoringDemo');