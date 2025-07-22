#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { LambdaCostOptimizerStack } from './lib/lambda-cost-optimizer-stack';

/**
 * AWS CDK Application for Lambda Cost Optimization with Compute Optimizer
 * 
 * This application deploys infrastructure to demonstrate Lambda cost optimization
 * using AWS Compute Optimizer recommendations. It includes sample Lambda functions,
 * monitoring capabilities, and automation for applying optimization recommendations.
 */

const app = new cdk.App();

// Get deployment configuration from context or environment variables
const account = process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account');
const region = process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1';

// Optional: Get environment type for resource naming
const environment = app.node.tryGetContext('environment') || 'dev';

// Stack configuration
const stackName = `lambda-cost-optimizer-${environment}`;

new LambdaCostOptimizerStack(app, stackName, {
  env: {
    account: account,
    region: region,
  },
  
  // Stack description
  description: 'Infrastructure for AWS Lambda Cost Optimization with Compute Optimizer (Recipe: lambda-cost-compute-optimizer)',
  
  // Add tags for cost tracking and resource management
  tags: {
    Project: 'lambda-cost-optimizer',
    Environment: environment,
    Recipe: 'lambda-cost-compute-optimizer',
    CostCenter: 'engineering',
    Purpose: 'cost-optimization-demo'
  }
});

// Add global tags to all resources in the app
cdk.Tags.of(app).add('Project', 'lambda-cost-optimizer');
cdk.Tags.of(app).add('ManagedBy', 'CDK');
cdk.Tags.of(app).add('Recipe', 'lambda-cost-compute-optimizer');