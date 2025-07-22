#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { TaskCatInfrastructureStack } from './lib/taskcat-infrastructure-stack';

const app = new cdk.App();

// Get environment configuration
const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION;

// Create the main TaskCat infrastructure stack
new TaskCatInfrastructureStack(app, 'TaskCatInfrastructureStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Infrastructure testing framework using TaskCat and CloudFormation',
  tags: {
    Project: 'TaskCat-Demo',
    Environment: 'Development',
    Purpose: 'Infrastructure-Testing',
  },
});

app.synth();