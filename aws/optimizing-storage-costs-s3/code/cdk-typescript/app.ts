#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { StorageOptimizationStack } from './lib/storage-optimization-stack';

const app = new cdk.App();

// Get configuration from context or use defaults
const config = {
  bucketName: app.node.tryGetContext('bucketName') || 'storage-optimization-demo',
  enableIntelligentTiering: app.node.tryGetContext('enableIntelligentTiering') ?? true,
  enableStorageAnalytics: app.node.tryGetContext('enableStorageAnalytics') ?? true,
  budgetLimit: app.node.tryGetContext('budgetLimit') || 50,
  alertEmail: app.node.tryGetContext('alertEmail') || 'admin@example.com',
  environment: app.node.tryGetContext('environment') || 'demo'
};

new StorageOptimizationStack(app, 'StorageOptimizationStack', {
  ...config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS S3 Storage Cost Optimization with Intelligent Tiering and Lifecycle Policies'
});