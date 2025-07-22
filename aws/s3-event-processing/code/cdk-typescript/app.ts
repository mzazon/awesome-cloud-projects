#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EventDrivenDataProcessingStack } from './lib/event-driven-data-processing-stack';

const app = new cdk.App();

// Get configuration from context or environment
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Generate unique suffix for resource names
  resourceSuffix: process.env.RESOURCE_SUFFIX || Math.random().toString(36).substring(2, 8),
  // Optional: Email for SNS notifications
  notificationEmail: process.env.NOTIFICATION_EMAIL || 'your-email@example.com',
  // Optional: Enable detailed monitoring
  enableDetailedMonitoring: process.env.ENABLE_DETAILED_MONITORING === 'true',
};

new EventDrivenDataProcessingStack(app, 'EventDrivenDataProcessingStack', {
  env: config.env,
  resourceSuffix: config.resourceSuffix,
  notificationEmail: config.notificationEmail,
  enableDetailedMonitoring: config.enableDetailedMonitoring,
  description: 'Event-driven data processing pipeline with S3 event notifications',
  tags: {
    Project: 'EventDrivenDataProcessing',
    Environment: process.env.ENVIRONMENT || 'dev',
    Owner: process.env.OWNER || 'data-team',
  },
});