#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { VisualServerlessApplicationStack } from './lib/visual-serverless-application-stack';

/**
 * CDK Application for Visual Serverless Applications
 * 
 * This application demonstrates building serverless applications using AWS CDK
 * that can be visually designed with AWS Application Composer and deployed
 * via CodeCatalyst CI/CD pipelines.
 * 
 * Architecture includes:
 * - API Gateway REST API for HTTP endpoints
 * - Lambda functions for business logic
 * - DynamoDB table for data persistence
 * - CloudWatch monitoring and X-Ray tracing
 * - Dead letter queues for error handling
 */

const app = new cdk.App();

// Get deployment context from environment or CDK context
const stage = app.node.tryGetContext('stage') || process.env.STAGE || 'dev';
const region = app.node.tryGetContext('region') || process.env.AWS_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.AWS_ACCOUNT_ID;

// Stack configuration
const stackName = `visual-serverless-app-${stage}`;
const stackDescription = `Visual Serverless Application Stack for ${stage} environment`;

// Create the main stack
const visualServerlessStack = new VisualServerlessApplicationStack(app, stackName, {
  stackName,
  description: stackDescription,
  env: {
    account,
    region,
  },
  tags: {
    Environment: stage,
    Application: 'Visual Serverless App',
    CreatedBy: 'CDK',
    Recipe: 'building-visual-serverless-applications-with-aws-infrastructure-composer-and-codecatalyst',
  },
  // Stack-specific properties
  stage,
  terminationProtection: stage === 'prod',
});

// Add stack-level tags
cdk.Tags.of(visualServerlessStack).add('Project', 'AWS Recipe Implementation');
cdk.Tags.of(visualServerlessStack).add('DeploymentMethod', 'CDK');
cdk.Tags.of(visualServerlessStack).add('ManagedBy', 'CDK');

// Output deployment information
new cdk.CfnOutput(visualServerlessStack, 'StackName', {
  value: visualServerlessStack.stackName,
  description: 'Name of the deployed stack',
});

new cdk.CfnOutput(visualServerlessStack, 'DeploymentStage', {
  value: stage,
  description: 'Deployment stage (dev/staging/prod)',
});

new cdk.CfnOutput(visualServerlessStack, 'DeploymentRegion', {
  value: region,
  description: 'AWS region for deployment',
});