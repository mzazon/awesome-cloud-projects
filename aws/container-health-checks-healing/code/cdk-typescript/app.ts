#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ContainerHealthCheckStack } from './lib/container-health-check-stack';

const app = new cdk.App();

// Get configuration from context or environment
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
  region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1'
};

// Create the main stack
new ContainerHealthCheckStack(app, 'ContainerHealthCheckStack', {
  env,
  description: 'Container health checks and self-healing applications infrastructure',
  tags: {
    Project: 'ContainerHealthCheck',
    Environment: app.node.tryGetContext('environment') || 'dev',
    Recipe: 'container-health-checks-self-healing-applications'
  }
});