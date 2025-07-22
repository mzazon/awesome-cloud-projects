#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AutomatedWorkspacesStack } from './lib/automated-workspaces-stack';

const app = new cdk.App();

// Get configuration from context or environment
const accountId = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

if (!accountId || !region) {
  throw new Error('Account ID and region must be specified via context or environment variables');
}

const env = { account: accountId, region: region };

// Create the main stack
new AutomatedWorkspacesStack(app, 'AutomatedWorkspacesStack', {
  env,
  description: 'Automated WorkSpaces Personal provisioning with Lambda and Systems Manager (uksb-1tupboc57)',
  
  // Stack configuration
  stackName: app.node.tryGetContext('stackName') || 'automated-workspaces-dev',
  
  // WorkSpaces configuration
  directoryId: app.node.tryGetContext('directoryId'),
  bundleId: app.node.tryGetContext('bundleId') || 'wsb-bh8rsxt14', // Windows 10 Standard bundle
  
  // Lambda configuration
  targetUsers: app.node.tryGetContext('targetUsers') || ['developer1', 'developer2', 'developer3'],
  
  // Automation configuration  
  automationSchedule: app.node.tryGetContext('automationSchedule') || 'rate(24 hours)',
  
  // Security configuration
  enableVpcEndpoints: app.node.tryGetContext('enableVpcEndpoints') || false,
  
  // Tags
  tags: {
    Project: 'DevEnvironmentAutomation',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'DevOps Team',
    CostCenter: app.node.tryGetContext('costCenter') || 'Engineering'
  }
});

// Apply common tags to all resources
cdk.Tags.of(app).add('Application', 'AutomatedWorkSpaces');
cdk.Tags.of(app).add('ManagedBy', 'CDK');