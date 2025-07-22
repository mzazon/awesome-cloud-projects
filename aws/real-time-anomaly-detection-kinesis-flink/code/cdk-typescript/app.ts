#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AnomalyDetectionStack } from './lib/anomaly-detection-stack';

const app = new cdk.App();

// Get environment configuration
const account = process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account');
const region = process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1';

// Create the main stack
new AnomalyDetectionStack(app, 'AnomalyDetectionStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Real-time Anomaly Detection with Kinesis Data Analytics and Managed Service for Apache Flink',
  
  // Stack configuration
  stackName: app.node.tryGetContext('stackName') || 'anomaly-detection-stack',
  
  // Application configuration
  streamShardCount: app.node.tryGetContext('streamShardCount') || 2,
  flinkParallelism: app.node.tryGetContext('flinkParallelism') || 2,
  notificationEmail: app.node.tryGetContext('notificationEmail'),
  
  tags: {
    Project: 'AnomalyDetection',
    Environment: app.node.tryGetContext('environment') || 'dev',
    Recipe: 'real-time-anomaly-detection-kinesis-data-analytics',
  },
});

app.synth();