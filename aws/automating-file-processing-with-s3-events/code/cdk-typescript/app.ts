#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { S3EventProcessingStack } from './lib/s3-event-processing-stack';

const app = new cdk.App();

// Get environment configuration from context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Optional configuration parameters with defaults
const config = {
  environment: app.node.tryGetContext('environment') || 'dev',
  notificationEmail: app.node.tryGetContext('notificationEmail') || undefined,
  bucketName: app.node.tryGetContext('bucketName') || undefined,
  enableEncryption: app.node.tryGetContext('enableEncryption') !== 'false',
  logRetentionDays: parseInt(app.node.tryGetContext('logRetentionDays') || '30'),
};

// Create the main stack
new S3EventProcessingStack(app, 'S3EventProcessingStack', {
  env,
  description: 'S3 Event Notifications and Automated Processing Infrastructure',
  
  // Stack-specific configuration
  environment: config.environment,
  notificationEmail: config.notificationEmail,
  bucketName: config.bucketName,
  enableEncryption: config.enableEncryption,
  logRetentionDays: config.logRetentionDays,
  
  // CDK resource tagging
  tags: {
    Project: 'S3EventProcessing',
    Environment: config.environment,
    Stack: 'S3EventProcessingStack',
    CreatedBy: 'CDK',
  },
});