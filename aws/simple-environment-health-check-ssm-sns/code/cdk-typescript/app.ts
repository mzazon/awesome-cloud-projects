#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EnvironmentHealthCheckStack } from './lib/environment-health-check-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

const app = new cdk.App();

// Create the main stack
const environmentHealthCheckStack = new EnvironmentHealthCheckStack(app, 'EnvironmentHealthCheckStack', {
  description: 'Environment Health Check with Systems Manager and SNS notifications',
  tags: {
    Project: 'EnvironmentHealthCheck',
    Environment: 'Production',
    Purpose: 'HealthMonitoring'
  },
  // Uncomment to specify environment
  // env: {
  //   account: process.env.CDK_DEFAULT_ACCOUNT,
  //   region: process.env.CDK_DEFAULT_REGION,
  // },
});

// Apply CDK Nag security checks
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));