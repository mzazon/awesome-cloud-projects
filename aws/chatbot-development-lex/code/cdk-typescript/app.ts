#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ChatbotDevelopmentStack } from './lib/chatbot-development-stack';

/**
 * CDK Application for implementing Amazon Lex chatbot development
 * This application deploys a complete customer service chatbot with:
 * - Amazon Lex V2 bot with multiple intents
 * - AWS Lambda fulfillment function with business logic
 * - DynamoDB table for order tracking
 * - S3 bucket for product catalog
 * - Proper IAM roles and permissions
 */
const app = new cdk.App();

// Get environment configuration from CDK context or environment variables
const environment = {
  account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
  region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1',
};

// Create the main chatbot stack
new ChatbotDevelopmentStack(app, 'ChatbotDevelopmentStack', {
  env: environment,
  description: 'Customer service chatbot implementation with Amazon Lex, Lambda, and DynamoDB',
  tags: {
    Project: 'ChatbotDevelopment',
    Purpose: 'CustomerService',
    Environment: app.node.tryGetContext('environment') || 'development',
  },
});

// Add stack-level tags for better resource management
cdk.Tags.of(app).add('Source', 'AWS-Recipe-CDK');
cdk.Tags.of(app).add('Recipe', 'chatbot-development-amazon-lex');