#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AnalyticsDataStorageStack } from './lib/analytics-data-storage-stack';

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  tableBucketName: app.node.tryGetContext('tableBucketName') || undefined,
  namespaceName: app.node.tryGetContext('namespaceName') || 'analytics_data',
  sampleTableName: app.node.tryGetContext('sampleTableName') || 'customer_events',
  enableSampleData: app.node.tryGetContext('enableSampleData') !== 'false',
};

new AnalyticsDataStorageStack(app, 'AnalyticsDataStorageStack', {
  env: config.env,
  description: 'Analytics-Ready Data Storage with S3 Tables and Apache Iceberg',
  tableBucketName: config.tableBucketName,
  namespaceName: config.namespaceName,
  sampleTableName: config.sampleTableName,
  enableSampleData: config.enableSampleData,
  tags: {
    Project: 'AnalyticsDataStorage',
    Environment: 'Development',
    Recipe: 'analytics-ready-data-storage-s3-tables',
  },
});