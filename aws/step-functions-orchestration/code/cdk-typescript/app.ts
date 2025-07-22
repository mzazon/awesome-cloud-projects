#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MicroservicesStepFunctionsStack } from './lib/microservices-step-functions-stack';

const app = new cdk.App();

// Get environment configuration
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
new MicroservicesStepFunctionsStack(app, 'MicroservicesStepFunctionsStack', {
  env,
  description: 'Step Functions Microservices Orchestration - CDK TypeScript Implementation',
  tags: {
    Project: 'MicroservicesOrchestration',
    Environment: app.node.tryGetContext('environment') || 'dev',
    Recipe: 'microservices-step-functions',
    IaC: 'CDK-TypeScript'
  }
});