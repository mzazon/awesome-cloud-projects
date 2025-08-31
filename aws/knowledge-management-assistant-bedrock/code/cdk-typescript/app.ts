#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { KnowledgeManagementAssistantStack } from './lib/knowledge-management-assistant-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  // Bedrock models are available in specific regions
  // Claude 3.5 Sonnet and Titan embeddings are available in us-east-1, us-west-2, and other regions
  stackName: app.node.tryGetContext('stackName') || 'KnowledgeManagementAssistant',
  bucketName: app.node.tryGetContext('bucketName'),
  enableCdkNag: app.node.tryGetContext('enableCdkNag') !== 'false', // Enable by default
};

const stack = new KnowledgeManagementAssistantStack(app, config.stackName, {
  env: config.env,
  description: 'Knowledge Management Assistant with Amazon Bedrock Agents and Knowledge Bases',
  bucketName: config.bucketName,
  enableCdkNag: config.enableCdkNag,
  tags: {
    Project: 'KnowledgeManagementAssistant',
    Environment: app.node.tryGetContext('environment') || 'development',
    CostCenter: app.node.tryGetContext('costCenter') || 'engineering',
  },
});

// Add CDK Nag for security best practices
if (config.enableCdkNag) {
  cdk.Aspects.of(app).add(new (require('cdk-nag').AwsSolutionsChecks)({ verbose: true }));
}

app.synth();