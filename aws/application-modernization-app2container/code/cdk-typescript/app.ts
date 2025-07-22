#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { App2ContainerStack } from './lib/app2container-stack';

const app = new cdk.App();

// Get environment configuration from CDK context or environment variables
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Get optional configuration
const appName = app.node.tryGetContext('appName') || 'modernized-app';
const environment = app.node.tryGetContext('environment') || 'dev';

// Create the main stack
new App2ContainerStack(app, 'App2ContainerStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'AWS App2Container modernization infrastructure stack',
  
  // Pass configuration to the stack
  appName: appName,
  environment: environment,
  
  // Stack tags for resource management
  tags: {
    Project: 'App2Container-Modernization',
    Environment: environment,
    ManagedBy: 'CDK',
    Purpose: 'Application-Modernization',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('CreatedBy', 'AWS-CDK');
cdk.Tags.of(app).add('Repository', 'recipes');