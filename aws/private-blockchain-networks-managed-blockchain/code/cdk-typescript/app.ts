#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ManagedBlockchainStack } from './lib/managed-blockchain-stack';

const app = new cdk.App();

// Get configuration from context or use defaults
const config = {
  networkName: app.node.tryGetContext('networkName') || 'SupplyChainNetwork',
  memberName: app.node.tryGetContext('memberName') || 'OrganizationA',
  adminUsername: app.node.tryGetContext('adminUsername') || 'admin',
  adminPassword: app.node.tryGetContext('adminPassword') || 'TempPassword123!',
  nodeInstanceType: app.node.tryGetContext('nodeInstanceType') || 'bc.t3.small',
  ec2InstanceType: app.node.tryGetContext('ec2InstanceType') || 't3.medium',
  environment: app.node.tryGetContext('environment') || 'development'
};

new ManagedBlockchainStack(app, 'ManagedBlockchainStack', {
  config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS CDK stack for Amazon Managed Blockchain private network with Hyperledger Fabric',
  tags: {
    Project: 'SupplyChain',
    Environment: config.environment,
    Recipe: 'private-blockchain-networks-amazon-managed-blockchain'
  }
});