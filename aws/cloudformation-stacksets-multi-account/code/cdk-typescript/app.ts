#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { StackSetsMultiAccountStack } from './lib/stacksets-multi-account-stack';
import { GovernanceTemplateStack } from './lib/governance-template-stack';
import { ExecutionRoleStack } from './lib/execution-role-stack';
import { MonitoringStack } from './lib/monitoring-stack';

/**
 * CDK Application for CloudFormation StackSets Multi-Account Multi-Region Management
 * 
 * This application creates a comprehensive StackSets solution for organization-wide
 * governance, including:
 * - StackSet administrator roles and permissions
 * - Execution role templates for target accounts
 * - Governance policy templates
 * - Monitoring and alerting infrastructure
 * - Automated drift detection
 */

const app = new cdk.App();

// Get configuration from context or environment
const config = {
  managementAccountId: app.node.tryGetContext('managementAccountId') || process.env.MANAGEMENT_ACCOUNT_ID,
  organizationId: app.node.tryGetContext('organizationId') || process.env.ORGANIZATION_ID,
  targetRegions: app.node.tryGetContext('targetRegions') || process.env.TARGET_REGIONS?.split(',') || ['us-east-1', 'us-west-2', 'eu-west-1'],
  targetAccounts: app.node.tryGetContext('targetAccounts') || process.env.TARGET_ACCOUNTS?.split(',') || [],
  complianceLevel: app.node.tryGetContext('complianceLevel') || process.env.COMPLIANCE_LEVEL || 'standard',
  environment: app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'all',
  stackSetName: app.node.tryGetContext('stackSetName') || process.env.STACKSET_NAME || 'org-governance-stackset',
  templateBucket: app.node.tryGetContext('templateBucket') || process.env.TEMPLATE_BUCKET
};

// Validate required configuration
if (!config.managementAccountId) {
  throw new Error('Management account ID is required. Set MANAGEMENT_ACCOUNT_ID environment variable or managementAccountId context.');
}

if (!config.organizationId) {
  console.warn('Organization ID not provided. Some features may be limited.');
}

if (!config.templateBucket) {
  console.warn('Template bucket not provided. Templates will be included inline.');
}

// Primary region for management resources
const primaryRegion = process.env.CDK_DEFAULT_REGION || 'us-east-1';
const env = {
  account: config.managementAccountId,
  region: primaryRegion
};

// Create execution role stack (deployed to management account first)
const executionRoleStack = new ExecutionRoleStack(app, 'ExecutionRoleStack', {
  env,
  description: 'StackSet execution role template for target accounts',
  managementAccountId: config.managementAccountId,
  stackSetName: `${config.stackSetName}-execution-roles`,
  templateBucket: config.templateBucket,
  targetAccounts: config.targetAccounts
});

// Create governance template stack
const governanceTemplateStack = new GovernanceTemplateStack(app, 'GovernanceTemplateStack', {
  env,
  description: 'Organization-wide governance and security policies template',
  organizationId: config.organizationId,
  complianceLevel: config.complianceLevel,
  environment: config.environment,
  templateBucket: config.templateBucket
});

// Create main StackSets management stack
const stackSetsStack = new StackSetsMultiAccountStack(app, 'StackSetsMultiAccountStack', {
  env,
  description: 'CloudFormation StackSets for multi-account multi-region management',
  managementAccountId: config.managementAccountId,
  organizationId: config.organizationId,
  stackSetName: config.stackSetName,
  targetRegions: config.targetRegions,
  targetAccounts: config.targetAccounts,
  complianceLevel: config.complianceLevel,
  environment: config.environment,
  templateBucket: config.templateBucket
});

// Create monitoring and alerting stack
const monitoringStack = new MonitoringStack(app, 'MonitoringStack', {
  env,
  description: 'Monitoring and alerting for StackSets operations',
  stackSetName: config.stackSetName,
  managementAccountId: config.managementAccountId
});

// Add dependencies
stackSetsStack.addDependency(executionRoleStack);
stackSetsStack.addDependency(governanceTemplateStack);
monitoringStack.addDependency(stackSetsStack);

// Add tags to all stacks
const tags = {
  Project: 'StackSets-Multi-Account-Management',
  Environment: config.environment,
  ManagedBy: 'CDK',
  Purpose: 'OrganizationGovernance'
};

Object.entries(tags).forEach(([key, value]) => {
  cdk.Tags.of(app).add(key, value);
});

// Add stack-specific tags
cdk.Tags.of(executionRoleStack).add('Component', 'ExecutionRoles');
cdk.Tags.of(governanceTemplateStack).add('Component', 'GovernanceTemplate');
cdk.Tags.of(stackSetsStack).add('Component', 'StackSetsManagement');
cdk.Tags.of(monitoringStack).add('Component', 'Monitoring');

// Output configuration for debugging
console.log('CDK App Configuration:');
console.log('- Management Account ID:', config.managementAccountId);
console.log('- Organization ID:', config.organizationId || 'Not provided');
console.log('- Target Regions:', config.targetRegions.join(', '));
console.log('- Target Accounts:', config.targetAccounts.join(', ') || 'Will be discovered');
console.log('- Compliance Level:', config.complianceLevel);
console.log('- Environment:', config.environment);
console.log('- StackSet Name:', config.stackSetName);
console.log('- Template Bucket:', config.templateBucket || 'Inline templates');
console.log('- Primary Region:', primaryRegion);