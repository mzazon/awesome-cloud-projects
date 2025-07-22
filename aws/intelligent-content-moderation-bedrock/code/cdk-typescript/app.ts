#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ContentModerationStack } from './lib/content-moderation-stack';

const app = new cdk.App();

// Create the content moderation stack with configuration
new ContentModerationStack(app, 'ContentModerationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  
  // Stack configuration
  description: 'Intelligent Content Moderation with Amazon Bedrock and EventBridge',
  
  // Optional: Configure notification email (can be overridden via context)
  notificationEmail: app.node.tryGetContext('notificationEmail') || 'admin@example.com',
  
  // Optional: Configure resource prefix (can be overridden via context)
  resourcePrefix: app.node.tryGetContext('resourcePrefix') || 'content-moderation',
  
  // Tags applied to all resources
  tags: {
    Project: 'ContentModeration',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'ContentModerationTeam',
    CostCenter: 'AI-ML',
    Application: 'IntelligentContentModeration',
  },
});

// Output stack information
console.log('Content Moderation Stack deployed successfully!');
console.log(`Account: ${process.env.CDK_DEFAULT_ACCOUNT}`);
console.log(`Region: ${process.env.CDK_DEFAULT_REGION || 'us-east-1'}`);