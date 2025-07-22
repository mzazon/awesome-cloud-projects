#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DatabasePerformanceMonitoringStack } from './lib/database-performance-monitoring-stack';

const app = new cdk.App();

// Get context values or use defaults
const stackName = app.node.tryGetContext('stackName') || 'DatabasePerformanceMonitoringStack';
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the main stack
new DatabasePerformanceMonitoringStack(app, stackName, {
  env,
  description: 'Database Performance Monitoring with RDS Performance Insights',
  
  // Stack configuration
  stackProps: {
    // Database configuration
    dbInstanceClass: app.node.tryGetContext('dbInstanceClass') || 'db.t3.small',
    dbEngine: app.node.tryGetContext('dbEngine') || 'mysql',
    dbEngineVersion: app.node.tryGetContext('dbEngineVersion') || '8.0.35',
    allocatedStorage: Number(app.node.tryGetContext('allocatedStorage')) || 20,
    
    // Performance Insights configuration
    performanceInsightsRetentionPeriod: Number(app.node.tryGetContext('performanceInsightsRetentionPeriod')) || 7,
    monitoringInterval: Number(app.node.tryGetContext('monitoringInterval')) || 60,
    
    // Lambda configuration
    lambdaMemorySize: Number(app.node.tryGetContext('lambdaMemorySize')) || 512,
    lambdaTimeout: Number(app.node.tryGetContext('lambdaTimeout')) || 300,
    
    // Monitoring configuration
    analysisSchedule: app.node.tryGetContext('analysisSchedule') || 'rate(15 minutes)',
    
    // Notification configuration
    notificationEmail: app.node.tryGetContext('notificationEmail') || undefined,
    
    // CloudWatch configuration
    createDashboard: app.node.tryGetContext('createDashboard') !== 'false',
    enableAnomalyDetection: app.node.tryGetContext('enableAnomalyDetection') !== 'false',
    
    // Security configuration
    enableCloudWatchLogs: app.node.tryGetContext('enableCloudWatchLogs') !== 'false',
    enableEncryption: app.node.tryGetContext('enableEncryption') !== 'false',
    
    // Tagging
    tags: {
      Project: 'DatabasePerformanceMonitoring',
      Environment: app.node.tryGetContext('environment') || 'development',
      Owner: app.node.tryGetContext('owner') || 'DatabaseTeam',
      CostCenter: app.node.tryGetContext('costCenter') || 'IT',
    },
  },
});

// Add tags to all resources in the app
cdk.Tags.of(app).add('Project', 'DatabasePerformanceMonitoring');
cdk.Tags.of(app).add('ManagedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'recipes/database-performance-monitoring-rds-performance-insights');

app.synth();