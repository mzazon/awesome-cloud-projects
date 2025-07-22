#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  CrossOrgDataSharingStack,
  BlockchainNetworkStack,
  EventProcessingStack,
  MonitoringAndComplianceStack 
} from './lib/cross-org-data-sharing-stack';

/**
 * CDK Application for Cross-Organization Data Sharing with Amazon Managed Blockchain
 * 
 * This application deploys a complete cross-organization data sharing platform using:
 * - Amazon Managed Blockchain with Hyperledger Fabric
 * - AWS Lambda for data validation and event processing
 * - Amazon EventBridge for cross-organization notifications
 * - Amazon S3 for shared data storage
 * - Amazon DynamoDB for audit trail
 * - Amazon CloudWatch for monitoring and compliance
 */

const app = new cdk.App();

// Get deployment configuration from context or environment
const account = process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account');
const region = process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1';

if (!account) {
  throw new Error('Account must be specified via CDK_DEFAULT_ACCOUNT environment variable or cdk.json context');
}

// Environment configuration
const env = {
  account,
  region,
};

// Configuration parameters
const config = {
  networkName: app.node.tryGetContext('networkName') || 'cross-org-network',
  orgAName: app.node.tryGetContext('orgAName') || 'financial-institution',
  orgBName: app.node.tryGetContext('orgBName') || 'healthcare-provider',
  environment: app.node.tryGetContext('environment') || 'dev',
  enableMonitoring: app.node.tryGetContext('enableMonitoring') !== 'false',
  retentionDays: parseInt(app.node.tryGetContext('retentionDays') || '30'),
};

// Generate unique suffix for resource names
const uniqueSuffix = Math.random().toString(36).substring(2, 8);

// Deploy blockchain network stack first
const networkStack = new BlockchainNetworkStack(app, 'CrossOrgBlockchainNetwork', {
  env,
  description: 'Amazon Managed Blockchain network for cross-organization data sharing',
  config: {
    ...config,
    uniqueSuffix,
  },
  tags: {
    Project: 'CrossOrgDataSharing',
    Environment: config.environment,
    CostCenter: 'Blockchain',
    Owner: 'DataGovernance',
  },
});

// Deploy main data sharing infrastructure
const mainStack = new CrossOrgDataSharingStack(app, 'CrossOrgDataSharing', {
  env,
  description: 'Core infrastructure for cross-organization data sharing',
  config: {
    ...config,
    uniqueSuffix,
    networkId: networkStack.networkId,
    orgAMemberId: networkStack.orgAMemberId,
    orgBMemberId: networkStack.orgBMemberId,
  },
  tags: {
    Project: 'CrossOrgDataSharing',
    Environment: config.environment,
    CostCenter: 'DataSharing',
    Owner: 'DataGovernance',
  },
});

// Deploy event processing stack
const eventStack = new EventProcessingStack(app, 'CrossOrgEventProcessing', {
  env,
  description: 'Event processing and notification infrastructure',
  config: {
    ...config,
    uniqueSuffix,
    auditTable: mainStack.auditTable,
    dataBucket: mainStack.dataBucket,
  },
  tags: {
    Project: 'CrossOrgDataSharing',
    Environment: config.environment,
    CostCenter: 'EventProcessing',
    Owner: 'DataGovernance',
  },
});

// Deploy monitoring and compliance stack
const monitoringStack = new MonitoringAndComplianceStack(app, 'CrossOrgMonitoring', {
  env,
  description: 'Monitoring, compliance, and audit infrastructure',
  config: {
    ...config,
    uniqueSuffix,
    lambdaFunction: eventStack.dataValidationFunction,
    eventBridgeRule: eventStack.eventRule,
    auditTable: mainStack.auditTable,
    notificationTopic: eventStack.notificationTopic,
  },
  tags: {
    Project: 'CrossOrgDataSharing',
    Environment: config.environment,
    CostCenter: 'Monitoring',
    Owner: 'DataGovernance',
  },
});

// Stack dependencies
mainStack.addDependency(networkStack);
eventStack.addDependency(mainStack);
monitoringStack.addDependency(eventStack);

// Add stack-level outputs
new cdk.CfnOutput(app.node.root as cdk.Stack, 'DeploymentSummary', {
  value: JSON.stringify({
    networkId: networkStack.networkId,
    region: region,
    environment: config.environment,
    timestamp: new Date().toISOString(),
  }),
  description: 'Cross-organization data sharing deployment summary',
});

// Tag all resources in the application
cdk.Tags.of(app).add('Application', 'CrossOrgDataSharing');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('RecipeId', '91b5f3e8');
cdk.Tags.of(app).add('DeployedBy', 'CDK');
cdk.Tags.of(app).add('DeployedAt', new Date().toISOString());

// Synthesize the application
app.synth();