#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { BackupStrategyStack } from './lib/backup-strategy-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const stackName = app.node.tryGetContext('stackName') || 'BackupStrategyStack';
const environment = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the main backup strategy stack
new BackupStrategyStack(app, stackName, {
  env: environment,
  description: 'Comprehensive backup strategy with S3, Glacier, Lambda, and EventBridge',
  tags: {
    Project: 'BackupStrategy',
    Environment: app.node.tryGetContext('environment') || 'dev',
    Owner: 'CDK',
  },
});

app.synth();