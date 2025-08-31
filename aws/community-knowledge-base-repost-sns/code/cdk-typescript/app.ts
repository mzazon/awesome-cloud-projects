#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { CommunityKnowledgeBaseStack } from './community-knowledge-base-stack';

/**
 * CDK Application for Community Knowledge Base with re:Post Private and SNS
 * 
 * This application creates the infrastructure for an enterprise knowledge base
 * solution using AWS re:Post Private and Amazon SNS for notifications.
 * 
 * Architecture:
 * - Amazon SNS Topic for knowledge base notifications
 * - Email subscriptions for team members
 * - IAM roles and policies for secure access
 * - CloudWatch Logs for monitoring
 * 
 * Note: AWS re:Post Private is provisioned through the AWS console and requires
 * Enterprise Support plan. This CDK app creates the supporting infrastructure.
 */

const app = new cdk.App();

// Get configuration from context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

// Create the main stack
new CommunityKnowledgeBaseStack(app, 'CommunityKnowledgeBaseStack', {
  env,
  description: 'Infrastructure for Community Knowledge Base with re:Post Private and SNS notifications',
  
  // Stack configuration
  stackName: app.node.tryGetContext('stackName') || 'community-knowledge-base',
  
  // Notification configuration
  notificationEmails: app.node.tryGetContext('notificationEmails') || [
    // Default email addresses - should be overridden via context
    'developer1@company.com',
    'developer2@company.com',
    'teamlead@company.com'
  ],
  
  // Enable detailed monitoring
  enableDetailedMonitoring: app.node.tryGetContext('enableDetailedMonitoring') ?? true,
  
  // Tags for all resources
  tags: {
    Project: 'CommunityKnowledgeBase',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: app.node.tryGetContext('owner') || 'DevOps',
    CostCenter: app.node.tryGetContext('costCenter') || 'Engineering',
    Purpose: 'Knowledge Management and Team Collaboration',
  },
});

// Add global tags to all resources
cdk.Tags.of(app).add('ManagedBy', 'AWS-CDK');
cdk.Tags.of(app).add('Repository', 'community-knowledge-base-repost-sns');
cdk.Tags.of(app).add('Recipe', 'a7b8c9d0');