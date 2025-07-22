#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ServerlessWebAppStack } from './lib/serverless-web-app-stack';

const app = new cdk.App();

// Get environment configuration
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';

// Create the main stack
new ServerlessWebAppStack(app, 'ServerlessWebAppStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Serverless Web Application with Amplify, Lambda, API Gateway, and Cognito',
  tags: {
    Project: 'ServerlessWebApp',
    Environment: process.env.ENVIRONMENT || 'development',
    Owner: 'CDK',
    CostCenter: 'Engineering',
  },
});

// Synthesize the CloudFormation template
app.synth();