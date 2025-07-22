#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { HighPerformanceFileSystemsStack } from './lib/high-performance-file-systems-stack';

const app = new cdk.App();

// Get environment variables with defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
const stack = new HighPerformanceFileSystemsStack(app, 'HighPerformanceFileSystemsStack', {
  env: env,
  description: 'High-Performance File Systems with Amazon FSx - Lustre, Windows, and ONTAP file systems with best practices for HPC workloads',
  
  // Stack-level tags
  tags: {
    Project: 'FSx-Demo',
    Environment: 'Development',
    Purpose: 'High-Performance-Computing',
    CreatedBy: 'CDK',
    Recipe: 'high-performance-file-systems-amazon-fsx',
  },
});

// Apply CDK Nag to ensure security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));