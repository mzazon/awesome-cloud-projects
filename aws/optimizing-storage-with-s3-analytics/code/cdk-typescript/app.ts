#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { S3InventoryStorageAnalyticsStack } from './lib/s3-inventory-storage-analytics-stack';

const app = new cdk.App();

// Get deployment configuration from context or environment
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the main stack
new S3InventoryStorageAnalyticsStack(app, 'S3InventoryStorageAnalyticsStack', {
  env,
  description: 'S3 Inventory and Storage Analytics Reporting Solution',
  
  // Stack configuration
  stackName: 'S3-Storage-Analytics',
  
  // Tags for all resources
  tags: {
    'Project': 'S3-Storage-Analytics',
    'Environment': app.node.tryGetContext('environment') || 'development',
    'Owner': 'AWS-CDK',
    'Purpose': 'StorageOptimization',
  },
});