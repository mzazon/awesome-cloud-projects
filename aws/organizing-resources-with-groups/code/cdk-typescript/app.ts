#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ResourceGroupsAutomationStack } from './lib/resource-groups-automation-stack';

/**
 * CDK Application for AWS Resource Groups Automated Resource Management
 * 
 * This application deploys infrastructure for automated resource management including:
 * - Resource Groups for logical organization
 * - Systems Manager automation documents
 * - CloudWatch monitoring and dashboards
 * - SNS notifications for alerts
 * - AWS Budgets for cost tracking
 * - EventBridge rules for automated tagging
 */

const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
    region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1'
  },
  
  // Application configuration
  resourceGroupName: app.node.tryGetContext('resourceGroupName') || 'production-web-app',
  notificationEmail: app.node.tryGetContext('notificationEmail') || '',
  budgetAmount: Number(app.node.tryGetContext('budgetAmount')) || 100,
  
  // Tagging configuration
  defaultTags: {
    Project: 'ResourceGroupsAutomation',
    Environment: 'production',
    Application: 'web-app',
    Purpose: 'resource-management'
  }
};

// Validate required configuration
if (!config.notificationEmail) {
  console.warn('Warning: No notification email provided. Set notificationEmail in cdk.json context or use --context notificationEmail=your@email.com');
}

// Deploy the main stack
new ResourceGroupsAutomationStack(app, 'ResourceGroupsAutomationStack', {
  env: config.env,
  description: 'AWS Resource Groups Automated Resource Management - Production-ready infrastructure for resource organization, monitoring, and automation',
  
  // Stack configuration
  resourceGroupName: config.resourceGroupName,
  notificationEmail: config.notificationEmail,
  budgetAmount: config.budgetAmount,
  
  // Apply default tags to all resources
  tags: config.defaultTags,
  
  // Enable termination protection for production environments
  terminationProtection: process.env.NODE_ENV === 'production',
  
  // Stack naming
  stackName: `ResourceGroupsAutomation-${config.env.region}`,
});

// Add application-level tags
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('Recipe', 'resource-groups-automated-resource-management');