#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ProgressiveWebAppStack } from './lib/progressive-web-app-stack';

/**
 * CDK Application for Progressive Web Applications with AWS Amplify
 * 
 * This application demonstrates how to build a comprehensive Progressive Web App (PWA)
 * using AWS Amplify, Cognito, AppSync, and S3 with full offline capabilities and 
 * real-time data synchronization.
 * 
 * Architecture Components:
 * - Amazon Cognito for user authentication and authorization
 * - AWS AppSync for GraphQL API with real-time subscriptions
 * - Amazon DynamoDB for data storage
 * - Amazon S3 for file storage and static web hosting
 * - AWS Amplify for hosting and CI/CD pipeline
 * - CloudFront for global content delivery
 * 
 * Features:
 * - Offline-first data management with DataStore
 * - Real-time synchronization across devices
 * - Progressive Web App capabilities
 * - Secure authentication and authorization
 * - Scalable serverless architecture
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config = {
  appName: app.node.tryGetContext('appName') || process.env.APP_NAME || 'progressive-web-app',
  environment: app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev',
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  account: process.env.CDK_DEFAULT_ACCOUNT,
  
  // Feature flags
  enableAnalytics: app.node.tryGetContext('enableAnalytics') || true,
  enableCustomDomain: app.node.tryGetContext('enableCustomDomain') || false,
  customDomainName: app.node.tryGetContext('customDomainName'),
  
  // Security settings
  enableMFA: app.node.tryGetContext('enableMFA') || false,
  passwordPolicy: {
    minLength: 8,
    requireUppercase: true,
    requireLowercase: true,
    requireNumbers: true,
    requireSymbols: true
  }
};

// Create the main stack
const progressiveWebAppStack = new ProgressiveWebAppStack(app, `${config.appName}-${config.environment}`, {
  env: {
    account: config.account,
    region: config.region,
  },
  description: `Progressive Web Application Stack for ${config.appName} (${config.environment})`,
  
  // Pass configuration to the stack
  config,
  
  // Stack-level tags for resource management
  tags: {
    Application: config.appName,
    Environment: config.environment,
    Stack: 'ProgressiveWebApp',
    CreatedBy: 'CDK',
    Purpose: 'PWA-Demo'
  }
});

// Add stack-level outputs for easy access
new cdk.CfnOutput(progressiveWebAppStack, 'StackName', {
  value: progressiveWebAppStack.stackName,
  description: 'Name of the CloudFormation stack'
});

new cdk.CfnOutput(progressiveWebAppStack, 'Region', {
  value: progressiveWebAppStack.region,
  description: 'AWS Region where the stack is deployed'
});

new cdk.CfnOutput(progressiveWebAppStack, 'Account', {
  value: progressiveWebAppStack.account,
  description: 'AWS Account ID where the stack is deployed'
});

// Synthesize the CloudFormation template
app.synth();