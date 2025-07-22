#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EventDrivenArchitectureStack } from './lib/event-driven-architecture-stack';

const app = new cdk.App();

// Get deployment configuration from context or environment
const environment = app.node.tryGetContext('environment') || 'dev';
const accountId = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Generate unique suffix for resource naming
const uniqueSuffix = app.node.tryGetContext('uniqueSuffix') || 
  Math.random().toString(36).substring(2, 8);

new EventDrivenArchitectureStack(app, `EventDrivenArchitecture-${environment}`, {
  env: {
    account: accountId,
    region: region,
  },
  uniqueSuffix: uniqueSuffix,
  environment: environment,
  description: 'Event-driven architecture implementation using Amazon EventBridge',
  tags: {
    Purpose: 'EcommerceDemoIntegration',
    Environment: environment,
    Recipe: 'event-driven-architectures-with-eventbridge',
    ManagedBy: 'CDK'
  }
});