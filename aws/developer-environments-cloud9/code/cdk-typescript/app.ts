#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DeveloperEnvironmentsStack } from './lib/developer-environments-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const accountId = app.node.tryGetContext('accountId') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Stack configuration
const stackProps: cdk.StackProps = {
  env: {
    account: accountId,
    region: region,
  },
  description: 'Developer Environments with Cloud9 - CDK TypeScript Implementation',
  tags: {
    Project: 'developer-environments-cloud9',
    Environment: 'development',
    ManagedBy: 'CDK',
    Recipe: 'developer-environments-aws-cloud9'
  }
};

// Create the main stack
new DeveloperEnvironmentsStack(app, 'DeveloperEnvironmentsStack', stackProps);

// Tag all resources in the app
cdk.Tags.of(app).add('Project', 'developer-environments-cloud9');
cdk.Tags.of(app).add('CreatedBy', 'CDK');