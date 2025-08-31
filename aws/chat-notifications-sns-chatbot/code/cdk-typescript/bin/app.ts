#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { ChatNotificationsStack } from '../lib/chat-notifications-stack';

/**
 * Main CDK application for Chat Notifications with SNS and Chatbot
 * 
 * This application deploys infrastructure for sending real-time notifications
 * from AWS services to Slack or Microsoft Teams channels using Amazon SNS
 * and AWS Chatbot integration.
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';

// Validate required environment
if (!account) {
  throw new Error('AWS account ID must be provided via CDK_DEFAULT_ACCOUNT or AWS_ACCOUNT_ID environment variable');
}

// Create the main stack
const chatNotificationsStack = new ChatNotificationsStack(app, 'ChatNotificationsStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Chat Notifications with SNS and Chatbot - Real-time alerts to Slack/Teams channels',
  tags: {
    Project: 'ChatNotifications',
    Environment: process.env.ENVIRONMENT || 'development',
    Owner: process.env.OWNER || 'DevOpsTeam',
    CostCenter: process.env.COST_CENTER || 'Engineering',
    Application: 'ChatNotificationSystem'
  }
});

// Apply CDK Nag security checks
// This ensures the infrastructure follows AWS security best practices
const nagEnabled = process.env.ENABLE_CDK_NAG !== 'false'; // Enabled by default
if (nagEnabled) {
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}

// Add stack-level tags for governance
cdk.Tags.of(chatNotificationsStack).add('StackName', 'ChatNotificationsStack');
cdk.Tags.of(chatNotificationsStack).add('CreatedBy', 'AWS-CDK');
cdk.Tags.of(chatNotificationsStack).add('Repository', 'chat-notifications-sns-chatbot');

app.synth();