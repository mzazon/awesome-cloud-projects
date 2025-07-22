#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ScheduledEmailReportsStack } from './lib/scheduled-email-reports-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  verifiedEmail: app.node.tryGetContext('verifiedEmail') || process.env.SES_VERIFIED_EMAIL || 'your-verified-email@example.com',
  githubRepo: app.node.tryGetContext('githubRepo') || process.env.GITHUB_REPO_URL || 'https://github.com/YOUR-USERNAME/email-reports-app',
  scheduleExpression: app.node.tryGetContext('scheduleExpression') || 'cron(0 9 * * ? *)', // Daily at 9 AM UTC
};

new ScheduledEmailReportsStack(app, 'ScheduledEmailReportsStack', {
  ...config,
  description: 'Stack for scheduled email reports using App Runner, SES, and EventBridge Scheduler',
  tags: {
    Project: 'EmailReports',
    Environment: 'Production',
    CreatedBy: 'CDK'
  }
});