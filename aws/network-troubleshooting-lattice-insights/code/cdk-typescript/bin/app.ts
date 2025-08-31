#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { NetworkTroubleshootingStack } from '../lib/network-troubleshooting-stack';

const app = new cdk.App();

// Get context values or use defaults
const accountId = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Generate a random suffix for unique resource names
const randomSuffix = Math.random().toString(36).substring(2, 8);

new NetworkTroubleshootingStack(app, 'NetworkTroubleshootingStack', {
  env: {
    account: accountId,
    region: region,
  },
  description: 'Network Troubleshooting with VPC Lattice and Network Insights - CDK Stack',
  tags: {
    Project: 'NetworkTroubleshooting',
    Environment: 'Demo',
    Purpose: 'VPCLatticeNetworkAnalysis',
  },
  randomSuffix: randomSuffix,
});