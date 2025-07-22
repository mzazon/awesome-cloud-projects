#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ConversationalAIStack } from './lib/conversational-ai-stack';

/**
 * Main CDK Application for Conversational AI with Amazon Bedrock and Claude
 * 
 * This application deploys a complete conversational AI solution including:
 * - DynamoDB table for conversation storage
 * - Lambda function for AI processing with Bedrock Claude
 * - API Gateway for REST API endpoints
 * - IAM roles and policies with least privilege access
 * - CloudWatch logging and X-Ray tracing
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const account = process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account');
const region = process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1';

// Validate that we're deploying to a supported Bedrock region
const bedrockSupportedRegions = [
  'us-east-1',
  'us-west-2', 
  'ap-southeast-1',
  'ap-northeast-1',
  'eu-central-1',
  'eu-west-1',
  'eu-west-3'
];

if (!bedrockSupportedRegions.includes(region)) {
  console.warn(`⚠️  Warning: Region ${region} may not support all Bedrock models. Supported regions: ${bedrockSupportedRegions.join(', ')}`);
}

// Create the main conversational AI stack
new ConversationalAIStack(app, 'ConversationalAIStack', {
  // Environment configuration
  env: {
    account: account,
    region: region,
  },
  
  // Stack configuration
  description: 'Conversational AI application using Amazon Bedrock Claude models, Lambda, API Gateway, and DynamoDB',
  
  // Add tags for resource management and cost tracking
  tags: {
    Project: 'ConversationalAI',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'CDK',
    CostCenter: 'AI-Innovation',
    AutoShutdown: 'true'
  },
  
  // Enable termination protection for production environments
  terminationProtection: app.node.tryGetContext('environment') === 'production',
});

// Add global aspects for security and compliance
cdk.Aspects.of(app).add(new cdk.aws_iam.AddPermissionBoundaryAspect({
  permissionBoundaryPolicyName: app.node.tryGetContext('permissionBoundary')
}));

// Synthesize the CloudFormation template
app.synth();