#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DynamicConfigManagementStack } from './lib/dynamic-config-management-stack';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';

const app = new cdk.App();

// Create the dynamic configuration management stack
new DynamicConfigManagementStack(app, 'DynamicConfigManagementStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Dynamic Configuration with Parameter Store',
});

// Apply CDK Nag security checks
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Suppress specific CDK Nag rules that may not be applicable
NagSuppressions.addStackSuppressions(app.node.findChild('DynamicConfigManagementStack') as cdk.Stack, [
  {
    id: 'AwsSolutions-IAM4',
    reason: 'AWS managed policies are used for standard Lambda execution roles to follow AWS best practices',
  },
  {
    id: 'AwsSolutions-IAM5',
    reason: 'Wildcard permissions are required for CloudWatch metric publishing and parameter access within defined paths',
  },
]);