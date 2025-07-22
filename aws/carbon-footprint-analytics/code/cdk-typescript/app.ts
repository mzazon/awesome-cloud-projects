#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsSolutionsChecks, NagSuppressions } from 'cdk-nag';
import { SustainabilityDashboardStack } from './lib/sustainability-dashboard-stack';

/**
 * AWS CDK Application for Intelligent Sustainability Dashboards
 * 
 * This application creates an integrated sustainability intelligence platform using:
 * - AWS Customer Carbon Footprint Tool for emissions tracking
 * - Amazon QuickSight for advanced visualization
 * - AWS Cost Explorer API for cost correlation
 * - AWS Lambda for automated data processing
 * 
 * The solution enables real-time carbon footprint monitoring with intelligent
 * cost optimization recommendations, providing actionable insights for both
 * environmental responsibility and financial efficiency.
 */

const app = new cdk.App();

// Create the main sustainability dashboard stack
const sustainabilityStack = new SustainabilityDashboardStack(app, 'SustainabilityDashboardStack', {
  description: 'Intelligent Sustainability Dashboards with AWS Customer Carbon Footprint Tool and QuickSight',
  env: {
    // Use environment variables or specify region/account explicitly
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SustainabilityAnalytics',
    Environment: 'Production',
    CostCenter: 'Sustainability',
    Owner: 'EnvironmentalTeam',
    Purpose: 'CarbonFootprintAnalytics'
  }
});

// Apply AWS Well-Architected security best practices using CDK Nag
const nagAspect = new AwsSolutionsChecks({ 
  verbose: true,
  logIgnores: true 
});

cdk.Aspects.of(app).add(nagAspect);

// Apply global suppressions for known false positives or accepted risks
// Note: In production, carefully review and document all suppressions
NagSuppressions.addStackSuppressions(sustainabilityStack, [
  {
    id: 'AwsSolutions-IAM4',
    reason: 'AWS managed policies are used for standard Lambda execution role permissions',
    appliesTo: ['Policy::arn:<AWS::Partition>:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole']
  },
  {
    id: 'AwsSolutions-IAM5',
    reason: 'Wildcard permissions required for Cost Explorer API access and S3 bucket operations with dynamic prefixes',
    appliesTo: [
      'Action::ce:*',
      'Resource::arn:<AWS::Partition>:s3:::*/*',
      'Resource::*'
    ]
  }
]);

// Add additional metadata to the CDK application
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', false);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);

/**
 * Deploy Instructions:
 * 
 * 1. Install dependencies: npm install
 * 2. Bootstrap CDK (first time): cdk bootstrap
 * 3. Synthesize CloudFormation: cdk synth
 * 4. Deploy the stack: cdk deploy
 * 
 * Post-deployment setup:
 * 
 * 1. Set up QuickSight account (Standard edition recommended)
 * 2. Grant QuickSight permissions to access S3 data lake
 * 3. Create QuickSight data source using the S3 manifest file
 * 4. Build sustainability dashboard with carbon footprint visualizations
 * 5. Configure automated refresh schedules to align with carbon footprint data availability
 * 
 * Cost Considerations:
 * 
 * - QuickSight Standard: ~$18/month per user
 * - Lambda executions: Minimal cost for monthly processing
 * - S3 storage: Low cost for sustainability analytics data
 * - CloudWatch logs and metrics: Standard monitoring costs
 * - EventBridge rules: Minimal cost for monthly triggers
 * 
 * Security Best Practices:
 * 
 * - IAM roles follow least privilege principles
 * - S3 bucket encryption enabled by default
 * - Lambda functions use VPC endpoints where applicable
 * - CloudWatch logs encrypted and retention configured
 * - All resources tagged for cost allocation and governance
 */