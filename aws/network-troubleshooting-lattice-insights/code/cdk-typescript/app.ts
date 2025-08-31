#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { NetworkTroubleshootingStack } from './lib/network-troubleshooting-stack';

/**
 * AWS CDK TypeScript Application for Network Troubleshooting with VPC Lattice and Network Insights
 * 
 * This application deploys a comprehensive network troubleshooting platform that combines:
 * - VPC Lattice service mesh for application-level networking
 * - VPC Reachability Analyzer for static configuration analysis  
 * - CloudWatch monitoring for real-time performance insights
 * - Systems Manager automation for diagnostic workflows
 * - Lambda functions for automated response
 * - SNS notifications for proactive alerting
 * 
 * The solution provides network engineers with automated tools to rapidly
 * identify and resolve service communication issues across multi-VPC environments.
 */

const app = new cdk.App();

// Get context values or use defaults
const accountId = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Generate a random suffix for unique resource names
const randomSuffix = Math.random().toString(36).substring(2, 8);

// Create the main stack
const stack = new NetworkTroubleshootingStack(app, 'NetworkTroubleshootingStack', {
  env: {
    account: accountId,
    region: region,
  },
  description: 'Network Troubleshooting with VPC Lattice and Network Insights - CDK Stack',
  tags: {
    Project: 'NetworkTroubleshooting',
    Environment: 'Demo',
    Purpose: 'VPCLatticeNetworkAnalysis',
    Recipe: 'network-troubleshooting-lattice-insights',
    CreatedBy: 'CDK',
  },
  randomSuffix: randomSuffix,
});

// Add additional tags for cost allocation and governance
cdk.Tags.of(stack).add('CostCenter', 'NetworkOps');
cdk.Tags.of(stack).add('Owner', 'NetworkEngineeringTeam');
cdk.Tags.of(stack).add('AutoDelete', 'true');
cdk.Tags.of(stack).add('Recipe', 'network-troubleshooting-lattice-insights');

// Output important deployment information
console.log(`Deploying Network Troubleshooting Stack to account ${accountId} in region ${region}`);
console.log(`Random suffix for unique resource names: ${randomSuffix}`);
console.log('Resources will be created with appropriate tags for cost allocation and governance');