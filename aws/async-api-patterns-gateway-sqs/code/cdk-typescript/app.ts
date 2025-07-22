#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AsynchronousApiStack } from './lib/asynchronous-api-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || 'dev';
const projectName = app.node.tryGetContext('projectName') || 'async-api';

new AsynchronousApiStack(app, `${projectName}-${environment}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environment,
  projectName,
  description: 'Asynchronous API Patterns with API Gateway and SQS',
});

app.synth();