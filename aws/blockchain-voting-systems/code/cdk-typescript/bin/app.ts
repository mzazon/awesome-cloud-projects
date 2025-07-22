#!/usr/bin/env node
/**
 * AWS CDK Application for Blockchain-Based Voting System
 * 
 * This application creates a secure, transparent voting system using Amazon Managed Blockchain
 * with Ethereum smart contracts. The system ensures vote immutability through blockchain technology,
 * maintains voter anonymity through cryptographic techniques, and provides real-time vote tallying 
 * with publicly verifiable results.
 * 
 * Key Components:
 * - Amazon Managed Blockchain (Ethereum)
 * - Lambda functions for voter authentication and monitoring
 * - DynamoDB tables for voter registry and election data
 * - S3 buckets for voting data and DApp hosting
 * - EventBridge for real-time event processing
 * - CloudWatch for monitoring and alerting
 * - SNS for notifications
 * - KMS for encryption
 * - IAM roles with least privilege access
 * 
 * Author: AWS Recipe
 * Version: 1.0.0
 * License: MIT
 */

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { BlockchainVotingSystemStack } from '../lib/blockchain-voting-system-stack';
import { VotingSystemMonitoringStack } from '../lib/voting-system-monitoring-stack';
import { VotingSystemSecurityStack } from '../lib/voting-system-security-stack';

/**
 * Main CDK Application Entry Point
 * 
 * This application deploys a complete blockchain-based voting system with:
 * - Core infrastructure (blockchain, databases, storage)
 * - Monitoring and observability
 * - Security and compliance features
 */
const app = new cdk.App();

// Get deployment configuration from CDK context or environment variables
const config = {
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
    region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
  },
  
  // Application configuration
  appName: app.node.tryGetContext('appName') || 'blockchain-voting-system',
  environment: app.node.tryGetContext('environment') || 'dev',
  
  // Blockchain configuration
  blockchain: {
    network: app.node.tryGetContext('blockchainNetwork') || 'GOERLI', // GOERLI for testing, MAINNET for production
    instanceType: app.node.tryGetContext('blockchainInstanceType') || 'bc.t3.medium',
    nodeCount: parseInt(app.node.tryGetContext('blockchainNodeCount') || '1'),
  },
  
  // Security configuration
  security: {
    enableEncryption: app.node.tryGetContext('enableEncryption') !== 'false',
    enableMultiFactorAuth: app.node.tryGetContext('enableMFA') !== 'false',
    kmsKeyRotation: app.node.tryGetContext('enableKmsRotation') !== 'false',
  },
  
  // Monitoring configuration
  monitoring: {
    enableDetailedLogging: app.node.tryGetContext('enableDetailedLogging') !== 'false',
    enableAlarming: app.node.tryGetContext('enableAlarming') !== 'false',
    logRetentionDays: parseInt(app.node.tryGetContext('logRetentionDays') || '30'),
  },
  
  // Application features
  features: {
    enableDApp: app.node.tryGetContext('enableDApp') !== 'false',
    enableMobileSupport: app.node.tryGetContext('enableMobileSupport') === 'true',
    enableAuditReporting: app.node.tryGetContext('enableAuditReporting') !== 'false',
    enableRealTimeResults: app.node.tryGetContext('enableRealTimeResults') !== 'false',
  },
  
  // Notification configuration
  notifications: {
    adminEmail: app.node.tryGetContext('adminEmail') || '',
    auditorsEmail: app.node.tryGetContext('auditorsEmail') || '',
    enableSlackNotifications: app.node.tryGetContext('enableSlackNotifications') === 'true',
  },
};

// Validate required configuration
if (!config.env.account) {
  throw new Error('Account ID is required. Set CDK_DEFAULT_ACCOUNT or AWS_ACCOUNT_ID environment variable.');
}

if (!config.env.region) {
  throw new Error('AWS region is required. Set CDK_DEFAULT_REGION or AWS_REGION environment variable.');
}

// Add tags to all resources
const commonTags = {
  Project: 'BlockchainVotingSystem',
  Environment: config.environment,
  Owner: 'AWS-Recipe',
  CostCenter: 'Blockchain-Demo',
  Version: '1.0.0',
  CreatedBy: 'AWS-CDK',
};

// Create resource naming helper
const createResourceName = (resourceType: string): string => {
  return `${config.appName}-${resourceType}-${config.environment}`;
};

/**
 * Security Stack - KMS keys, IAM roles, and security policies
 * 
 * This stack creates the foundational security infrastructure including:
 * - KMS keys for encryption
 * - IAM roles with least privilege access
 * - Security policies and groups
 */
const securityStack = new VotingSystemSecurityStack(app, createResourceName('Security'), {
  env: config.env,
  description: 'Security infrastructure for blockchain voting system including KMS keys and IAM roles',
  stackName: createResourceName('Security'),
  tags: commonTags,
  config: {
    appName: config.appName,
    environment: config.environment,
    enableEncryption: config.security.enableEncryption,
    enableKeyRotation: config.security.kmsKeyRotation,
    adminEmail: config.notifications.adminEmail,
  },
});

/**
 * Core Voting System Stack - Main infrastructure
 * 
 * This stack deploys the core voting system infrastructure including:
 * - Amazon Managed Blockchain (Ethereum)
 * - DynamoDB tables for voter registry and elections
 * - Lambda functions for authentication and monitoring
 * - S3 buckets for data storage and DApp hosting
 * - EventBridge for event processing
 * - API Gateway for REST API
 */
const votingSystemStack = new BlockchainVotingSystemStack(app, createResourceName('Core'), {
  env: config.env,
  description: 'Core blockchain voting system infrastructure with Ethereum, Lambda, and DynamoDB',
  stackName: createResourceName('Core'),
  tags: commonTags,
  config: {
    appName: config.appName,
    environment: config.environment,
    blockchain: config.blockchain,
    security: config.security,
    features: config.features,
    adminEmail: config.notifications.adminEmail,
    logRetentionDays: config.monitoring.logRetentionDays,
  },
  securityResources: {
    kmsKey: securityStack.kmsKey,
    lambdaExecutionRole: securityStack.lambdaExecutionRole,
    blockchainAccessRole: securityStack.blockchainAccessRole,
    apiGatewayRole: securityStack.apiGatewayRole,
  },
});

/**
 * Monitoring Stack - CloudWatch dashboards, alarms, and observability
 * 
 * This stack creates comprehensive monitoring and observability including:
 * - CloudWatch dashboards for system metrics
 * - Alarms for critical system events
 * - SNS topics for notifications
 * - Log groups with appropriate retention
 * - X-Ray tracing for distributed tracing
 */
const monitoringStack = new VotingSystemMonitoringStack(app, createResourceName('Monitoring'), {
  env: config.env,
  description: 'Monitoring and observability infrastructure for blockchain voting system',
  stackName: createResourceName('Monitoring'),
  tags: commonTags,
  config: {
    appName: config.appName,
    environment: config.environment,
    enableDetailedLogging: config.monitoring.enableDetailedLogging,
    enableAlarming: config.monitoring.enableAlarming,
    logRetentionDays: config.monitoring.logRetentionDays,
    adminEmail: config.notifications.adminEmail,
    auditorsEmail: config.notifications.auditorsEmail,
    enableSlackNotifications: config.notifications.enableSlackNotifications,
  },
  systemResources: {
    voterAuthFunction: votingSystemStack.voterAuthFunction,
    voteMonitorFunction: votingSystemStack.voteMonitorFunction,
    voterRegistryTable: votingSystemStack.voterRegistryTable,
    electionsTable: votingSystemStack.electionsTable,
    votingDataBucket: votingSystemStack.votingDataBucket,
    eventBridge: votingSystemStack.eventBridge,
    apiGateway: votingSystemStack.apiGateway,
  },
});

// Add stack dependencies
votingSystemStack.addDependency(securityStack);
monitoringStack.addDependency(votingSystemStack);

// Add metadata to stacks
votingSystemStack.addMetadata('Purpose', 'Core blockchain voting system infrastructure');
securityStack.addMetadata('Purpose', 'Security and access control for voting system');
monitoringStack.addMetadata('Purpose', 'Monitoring and observability for voting system');

// Output deployment information
new cdk.CfnOutput(votingSystemStack, 'DeploymentInfo', {
  value: JSON.stringify({
    environment: config.environment,
    region: config.env.region,
    appName: config.appName,
    version: '1.0.0',
    deployedAt: new Date().toISOString(),
  }),
  description: 'Deployment configuration and metadata',
});

// Output important endpoints and resources
new cdk.CfnOutput(votingSystemStack, 'VotingSystemEndpoints', {
  value: JSON.stringify({
    apiGateway: votingSystemStack.apiGateway.restApiId,
    dappUrl: votingSystemStack.dappUrl,
    monitoringDashboard: monitoringStack.dashboardUrl,
  }),
  description: 'Important system endpoints and URLs',
});

// Security and compliance outputs
new cdk.CfnOutput(securityStack, 'SecurityConfiguration', {
  value: JSON.stringify({
    kmsKeyId: securityStack.kmsKey.keyId,
    encryptionEnabled: config.security.enableEncryption,
    mfaEnabled: config.security.enableMultiFactorAuth,
    keyRotationEnabled: config.security.kmsKeyRotation,
  }),
  description: 'Security configuration and encryption settings',
});

// Add synthesis validation
app.synth();

console.log('✅ CDK Application synthesized successfully');
console.log(`📋 Configuration:`);
console.log(`   - Environment: ${config.environment}`);
console.log(`   - Region: ${config.env.region}`);
console.log(`   - App Name: ${config.appName}`);
console.log(`   - Blockchain Network: ${config.blockchain.network}`);
console.log(`   - Security Features: ${config.security.enableEncryption ? 'Enabled' : 'Disabled'}`);
console.log(`   - Monitoring: ${config.monitoring.enableAlarming ? 'Enabled' : 'Disabled'}`);