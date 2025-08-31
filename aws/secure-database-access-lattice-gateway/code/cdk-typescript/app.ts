#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SecureDatabaseAccessStack } from './lib/secure-database-access-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const dbOwnerAccountId = app.node.tryGetContext('dbOwnerAccountId') || process.env.CDK_DEFAULT_ACCOUNT;
const consumerAccountId = app.node.tryGetContext('consumerAccountId') || '123456789012';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const vpcId = app.node.tryGetContext('vpcId');
const subnetIds = app.node.tryGetContext('subnetIds')?.split(',') || [];

if (!vpcId || subnetIds.length < 2) {
  throw new Error('VPC ID and at least 2 subnet IDs must be provided via CDK context or environment variables');
}

// Create the main stack
new SecureDatabaseAccessStack(app, 'SecureDatabaseAccessStack', {
  env: {
    account: dbOwnerAccountId,
    region: region,
  },
  description: 'Secure database access with VPC Lattice Resource Gateway',
  
  // Stack-specific properties
  vpcId: vpcId,
  subnetIds: subnetIds,
  consumerAccountId: consumerAccountId,
  
  // Resource naming
  resourcePrefix: app.node.tryGetContext('resourcePrefix') || 'lattice-db',
  
  // Database configuration
  dbInstanceClass: app.node.tryGetContext('dbInstanceClass') || 'db.t3.micro',
  dbEngine: app.node.tryGetContext('dbEngine') || 'mysql',
  dbAllocatedStorage: parseInt(app.node.tryGetContext('dbAllocatedStorage') || '20'),
  
  // Security configuration
  enableEncryption: app.node.tryGetContext('enableEncryption') !== 'false',
  backupRetentionPeriod: parseInt(app.node.tryGetContext('backupRetentionPeriod') || '7'),
  
  // Tagging
  tags: {
    Project: 'VPCLatticeDemo',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'cdk-deployment'
  }
});