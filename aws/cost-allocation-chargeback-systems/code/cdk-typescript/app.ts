#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CostAllocationChargebackStack } from './lib/cost-allocation-chargeback-stack';

/**
 * CDK Application for Cost Allocation and Chargeback Systems
 * 
 * This application creates a comprehensive cost allocation and chargeback system
 * using AWS native billing and cost management tools including:
 * - Cost allocation tags and categories
 * - S3 bucket for Cost and Usage Reports (CUR)
 * - SNS topic for cost alerts and notifications
 * - Lambda function for automated cost processing
 * - AWS Budgets for department-specific spending limits
 * - EventBridge schedule for monthly cost processing
 * - Cost Anomaly Detection for unusual spending patterns
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const stackName = app.node.tryGetContext('stackName') || 'CostAllocationChargebackStack';
const environment = app.node.tryGetContext('environment') || 'dev';

new CostAllocationChargebackStack(app, stackName, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'Cost Allocation and Chargeback Systems with AWS Billing and Cost Management',
  tags: {
    Project: 'CostAllocationChargeback',
    Environment: environment,
    CostCenter: 'Finance',
    Owner: 'FinanceTeam'
  }
});

app.synth();