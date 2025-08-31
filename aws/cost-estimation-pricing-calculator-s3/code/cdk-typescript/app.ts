#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CostEstimationStack } from './lib/cost-estimation-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

const app = new cdk.App();

// Get environment configuration from CDK context or environment variables
const accountId = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Create the main stack
const costEstimationStack = new CostEstimationStack(app, 'CostEstimationStack', {
  env: {
    account: accountId,
    region: region,
  },
  description: 'Cost Estimation Planning with Pricing Calculator and S3 - CDK deployment for centralizing cost estimates',
  
  // Stack-level tags for cost allocation and resource management
  tags: {
    Project: 'CostEstimation',
    Environment: app.node.tryGetContext('environment') || 'dev',
    Owner: 'FinanceTeam',
    CostCenter: 'IT-Infrastructure',
    Recipe: 'cost-estimation-pricing-calculator-s3'
  }
});

// Apply CDK Nag security checks to ensure AWS best practices
// Only apply in production or when explicitly enabled
const enableCdkNag = app.node.tryGetContext('enable-cdk-nag') || process.env.ENABLE_CDK_NAG === 'true';
if (enableCdkNag) {
  // Apply AWS Solutions security checks
  cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
}

// Add stack-level metadata for tracking and documentation
costEstimationStack.templateOptions.description = 'Infrastructure for centralizing AWS cost estimates with automated storage, lifecycle management, and budget monitoring';
costEstimationStack.templateOptions.metadata = {
  'AWS::CloudFormation::Interface': {
    ParameterGroups: [
      {
        Label: { default: 'Cost Estimation Configuration' },
        Parameters: ['ProjectName', 'Environment']
      },
      {
        Label: { default: 'Budget Configuration' },
        Parameters: ['BudgetLimit', 'AlertThreshold']
      }
    ]
  }
};