#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ServerlessGraphQLApiStack } from './serverless-graphql-api-stack';

/**
 * CDK Application for Serverless GraphQL APIs with AWS AppSync and EventBridge Scheduler
 * 
 * This application deploys a complete task management system including:
 * - AWS AppSync GraphQL API with real-time subscriptions
 * - DynamoDB table for task storage
 * - Lambda function for task processing
 * - EventBridge Scheduler for automated reminders
 * - IAM roles with least privilege access
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const stackName = app.node.tryGetContext('stackName') || 'ServerlessGraphQLApi';
const environment = app.node.tryGetContext('environment') || 'dev';

// Define stack with comprehensive tags
new ServerlessGraphQLApiStack(app, stackName, {
  description: 'Serverless GraphQL API with AppSync and EventBridge Scheduler for task management',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ServerlessGraphQLAPI',
    Environment: environment,
    ManagedBy: 'CDK',
    Recipe: 'implementing-serverless-graphql-apis-with-aws-appsync-and-eventbridge-scheduler'
  }
});

// Synthesize the CloudFormation template
app.synth();