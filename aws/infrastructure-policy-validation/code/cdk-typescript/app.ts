#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { InfrastructurePolicyValidationStack } from './lib/infrastructure-policy-validation-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

const app = new cdk.App();

// Get configuration from context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
const stack = new InfrastructurePolicyValidationStack(app, 'InfrastructurePolicyValidationStack', {
  env,
  description: 'Infrastructure Policy Validation with CloudFormation Guard - automated compliance validation pipeline',
  tags: {
    Project: 'InfrastructurePolicyValidation',
    Environment: app.node.tryGetContext('environment') || 'development',
    Team: 'DevOps',
    CostCenter: 'CC-1001',
  },
});

// Apply CDK Nag for security best practices validation
// Only apply in CI/CD or when explicitly enabled
if (process.env.ENABLE_CDK_NAG === 'true' || app.node.tryGetContext('enableCdkNag')) {
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}

app.synth();