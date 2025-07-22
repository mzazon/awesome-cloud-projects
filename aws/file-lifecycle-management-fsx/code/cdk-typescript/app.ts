#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AutomatedFileLifecycleManagementStack } from './lib/automated-file-lifecycle-management-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

new AutomatedFileLifecycleManagementStack(app, 'AutomatedFileLifecycleManagementStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Automated File Lifecycle Management with Amazon FSx and Lambda',
  
  // Stack configuration
  fsxConfiguration: {
    storageCapacity: app.node.tryGetContext('fsxStorageCapacity') || 64,
    throughputCapacity: app.node.tryGetContext('fsxThroughputCapacity') || 64,
    cacheSize: app.node.tryGetContext('fsxCacheSize') || 128,
  },
  
  monitoring: {
    cacheHitRatioThreshold: app.node.tryGetContext('cacheHitRatioThreshold') || 70,
    storageUtilizationThreshold: app.node.tryGetContext('storageUtilizationThreshold') || 85,
    networkUtilizationThreshold: app.node.tryGetContext('networkUtilizationThreshold') || 90,
  },
  
  automation: {
    lifecyclePolicySchedule: app.node.tryGetContext('lifecyclePolicySchedule') || 'rate(1 hour)',
    costReportingSchedule: app.node.tryGetContext('costReportingSchedule') || 'rate(24 hours)',
  },
  
  // Notification configuration
  notificationEmail: app.node.tryGetContext('notificationEmail'),
  
  // Tagging
  tags: {
    Project: 'FSx-Lifecycle-Management',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: app.node.tryGetContext('owner') || 'devops',
    CostCenter: app.node.tryGetContext('costCenter') || 'infrastructure',
  },
});