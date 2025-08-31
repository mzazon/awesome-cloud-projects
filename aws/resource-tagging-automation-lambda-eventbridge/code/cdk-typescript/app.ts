#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ResourceTaggingAutomationStack } from './lib/resource-tagging-automation-stack';

/**
 * AWS CDK Application for Resource Tagging Automation
 * 
 * This application deploys an automated resource tagging solution using:
 * - Lambda function for processing tagging logic
 * - EventBridge rule for capturing resource creation events
 * - IAM role with least privilege permissions
 * - Resource Group for organizing tagged resources
 * 
 * The solution automatically applies standardized organizational tags
 * to newly created AWS resources based on CloudTrail events.
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environment = app.node.tryGetContext('environment') || 'production';
const costCenter = app.node.tryGetContext('costCenter') || 'engineering';
const managedBy = app.node.tryGetContext('managedBy') || 'automation';

// Deploy the Resource Tagging Automation Stack
new ResourceTaggingAutomationStack(app, 'ResourceTaggingAutomationStack', {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features are not used, making the stack
   * deployment more flexible across different AWS environments. */
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Pass configuration parameters to the stack
  description: 'Automated resource tagging system using Lambda and EventBridge',
  
  // Stack-level tags that will be applied to all resources
  tags: {
    Project: 'ResourceTaggingAutomation',
    Environment: environment,
    CostCenter: costCenter,
    ManagedBy: managedBy,
    DeployedWith: 'CDK',
  },
  
  // Additional stack properties
  stackName: 'resource-tagging-automation',
  terminationProtection: false, // Set to true for production deployments
});

// Add global tags to the entire CDK application
cdk.Tags.of(app).add('Project', 'ResourceTaggingAutomation');
cdk.Tags.of(app).add('DeployedWith', 'CDK');
cdk.Tags.of(app).add('Repository', 'aws-recipes');