#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { BudgetMonitoringStack } from './lib/budget-monitoring-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * Budget Monitoring CDK Application
 * 
 * This application creates a comprehensive budget monitoring solution using:
 * - AWS Budgets for cost tracking and forecasting
 * - Amazon SNS for reliable notification delivery
 * - Multi-threshold alerting (80% and 100% actual, 80% forecasted)
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const budgetAmount = app.node.tryGetContext('budgetAmount') || 100;
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;

if (!notificationEmail) {
  throw new Error('Notification email must be provided via context or NOTIFICATION_EMAIL environment variable');
}

// Create the budget monitoring stack
const budgetStack = new BudgetMonitoringStack(app, 'BudgetMonitoringStack', {
  budgetAmount: Number(budgetAmount),
  notificationEmail: notificationEmail,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Apply CDK Nag for security best practices
AwsSolutionsChecks.check(budgetStack);

// Add common tags to all resources
cdk.Tags.of(budgetStack).add('Project', 'BudgetMonitoring');
cdk.Tags.of(budgetStack).add('Environment', app.node.tryGetContext('environment') || 'development');
cdk.Tags.of(budgetStack).add('CostCenter', app.node.tryGetContext('costCenter') || 'shared');