#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EdgeAiInferenceStack } from './edge-ai-inference-stack';

/**
 * Main CDK application for Edge AI Inference with SageMaker and IoT Greengrass
 * 
 * This application creates infrastructure for real-time edge AI inference including:
 * - IoT Greengrass Core device configuration
 * - S3 bucket for model storage
 * - EventBridge for centralized monitoring
 * - IAM roles for secure edge device operation
 * - IoT Core policies and certificates
 * - CloudWatch logs for monitoring
 */

const app = new cdk.App();

// Get configuration from context or environment variables
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'edge-ai-inference';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';

// Construct stack name with project and environment
const stackName = `${projectName}-${environment}`;

// Deploy the Edge AI Inference stack
const edgeAiStack = new EdgeAiInferenceStack(app, stackName, {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: process.env.CDK_DEFAULT_REGION 
  },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  // env: { account: '123456789012', region: 'us-east-1' },

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */

  description: 'Infrastructure for real-time edge AI inference with SageMaker and IoT Greengrass',
  
  // Stack configuration
  projectName: projectName,
  environment: environment,
});

// Add common tags to all resources
cdk.Tags.of(edgeAiStack).add('Project', projectName);
cdk.Tags.of(edgeAiStack).add('Environment', environment);
cdk.Tags.of(edgeAiStack).add('ManagedBy', 'CDK');
cdk.Tags.of(edgeAiStack).add('Purpose', 'EdgeAI-Inference');

// Output the stack name for reference
console.log(`Deploying Edge AI Inference Stack: ${stackName}`);