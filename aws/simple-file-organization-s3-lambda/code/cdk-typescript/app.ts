#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { FileOrganizerStack } from './lib/file-organizer-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

const app = new cdk.App();

// Create the main stack with props that can be customized
new FileOrganizerStack(app, 'FileOrganizerStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Simple File Organization with S3 and Lambda - Automatically organizes uploaded files by type',
  
  // Stack configuration options
  bucketName: app.node.tryGetContext('bucketName'),
  enableVersioning: app.node.tryGetContext('enableVersioning') ?? true,
  enableEncryption: app.node.tryGetContext('enableEncryption') ?? true,
  lambdaTimeout: app.node.tryGetContext('lambdaTimeout') ?? 60,
  lambdaMemorySize: app.node.tryGetContext('lambdaMemorySize') ?? 256,
});

// Apply CDK Nag security checks to ensure best practices
// Only apply in CI/CD or when explicitly enabled
if (process.env.ENABLE_CDK_NAG === 'true' || app.node.tryGetContext('enableCdkNag')) {
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}