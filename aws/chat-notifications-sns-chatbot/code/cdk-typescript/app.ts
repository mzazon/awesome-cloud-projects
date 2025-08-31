#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { ChatNotificationsStack } from './lib/chat-notifications-stack';

/**
 * Main CDK application for Chat Notifications with SNS and Chatbot
 * 
 * This application deploys infrastructure for sending real-time notifications
 * from AWS services to Slack or Microsoft Teams channels using Amazon SNS
 * and AWS Chatbot integration.
 * 
 * Architecture includes:
 * - SNS Topic with KMS encryption for secure message delivery
 * - CloudWatch Alarm for testing notification workflows
 * - IAM roles and policies for AWS Chatbot integration
 * - Comprehensive security controls and monitoring
 */
const app = new cdk.App();

// Environment configuration with validation
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';
const environment = process.env.ENVIRONMENT || 'development';

// Validate required environment variables
if (!account) {
  throw new Error(
    'AWS account ID must be provided via CDK_DEFAULT_ACCOUNT or AWS_ACCOUNT_ID environment variable. ' +
    'Run: export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)'
  );
}

// Configuration options from context or environment
const config = {
  enableCdkNag: process.env.ENABLE_CDK_NAG !== 'false', // Enabled by default
  stackName: process.env.STACK_NAME || 'ChatNotificationsStack',
  owner: process.env.OWNER || 'DevOpsTeam',
  costCenter: process.env.COST_CENTER || 'Engineering',
  project: process.env.PROJECT || 'ChatNotifications'
};

console.log(`🚀 Deploying Chat Notifications Stack to ${region} (${environment})`);
console.log(`📊 CDK Nag security checks: ${config.enableCdkNag ? 'enabled' : 'disabled'}`);

// Create the main stack with comprehensive configuration
const chatNotificationsStack = new ChatNotificationsStack(app, config.stackName, {
  env: {
    account: account,
    region: region,
  },
  description: `Chat Notifications with SNS and Chatbot - Real-time alerts to Slack/Teams channels (${environment})`,
  
  // Resource tagging for governance and cost allocation
  tags: {
    Project: config.project,
    Environment: environment,
    Owner: config.owner,
    CostCenter: config.costCenter,
    Application: 'ChatNotificationSystem',
    ManagedBy: 'AWS-CDK',
    Version: '1.0.0'
  }
});

// Apply CDK Nag security checks for AWS Well-Architected compliance
if (config.enableCdkNag) {
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ 
    verbose: true,
    logIgnores: true 
  }));
  console.log('🔒 CDK Nag security checks applied to all resources');
}

// Add comprehensive stack-level tags for better resource management
const stackTags = [
  ['StackName', config.stackName],
  ['CreatedBy', 'AWS-CDK'],
  ['Repository', 'chat-notifications-sns-chatbot'],
  ['DeploymentDate', new Date().toISOString().split('T')[0]],
  ['CDKVersion', cdk.VERSION]
];

stackTags.forEach(([key, value]) => {
  cdk.Tags.of(chatNotificationsStack).add(key, value);
});

// Synthesis with validation
try {
  app.synth();
  console.log('✅ CDK synthesis completed successfully');
} catch (error) {
  console.error('❌ CDK synthesis failed:', error);
  process.exit(1);
}