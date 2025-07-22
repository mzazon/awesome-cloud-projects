#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CostAwareResourceLifecycleStack } from './lib/cost-aware-resource-lifecycle-stack';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

/**
 * CDK application for deploying cost-aware resource lifecycle management
 * with EventBridge Scheduler and MemoryDB for Redis
 */
const app = new cdk.App();

// Get deployment configuration from context or environment
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

const stackName = app.node.tryGetContext('stackName') || 'CostAwareResourceLifecycleStack';
const clusterName = app.node.tryGetContext('clusterName') || 'cost-aware-memorydb';
const costThreshold = app.node.tryGetContext('costThreshold') || 100;

// Create the main stack
const costAwareStack = new CostAwareResourceLifecycleStack(app, stackName, {
  env,
  description: 'Cost-aware resource lifecycle management with EventBridge Scheduler and MemoryDB',
  clusterName,
  costThreshold,
  tags: {
    Project: 'CostAwareResourceLifecycle',
    Environment: app.node.tryGetContext('environment') || 'development',
    CostCenter: app.node.tryGetContext('costCenter') || 'devops',
  },
});

// Apply CDK Nag for security best practices
if (app.node.tryGetContext('enableCdkNag') !== 'false') {
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
  
  // Add justified suppressions for cost optimization use case
  NagSuppressions.addStackSuppressions(costAwareStack, [
    {
      id: 'AwsSolutions-IAM4',
      reason: 'AWS managed policies are acceptable for service roles in this cost optimization solution',
    },
    {
      id: 'AwsSolutions-IAM5',
      reason: 'Wildcard permissions required for cost analysis and MemoryDB operations across regions',
    },
    {
      id: 'AwsSolutions-L1',
      reason: 'Python 3.9 is stable and supported for Lambda functions in this solution',
    },
  ]);
}

app.synth();