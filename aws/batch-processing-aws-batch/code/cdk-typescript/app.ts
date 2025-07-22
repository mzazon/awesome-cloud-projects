#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { BatchProcessingStack } from './lib/batch-processing-stack';

const app = new cdk.App();

// Get environment configuration
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';

// Create the batch processing stack
new BatchProcessingStack(app, 'BatchProcessingStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'AWS Batch processing workloads infrastructure stack',
  tags: {
    Project: 'BatchProcessingWorkloads',
    Environment: 'demo',
    ManagedBy: 'CDK',
  },
});

app.synth();