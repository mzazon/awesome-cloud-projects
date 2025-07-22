#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiAccountResourceDiscoveryStack } from './lib/multi-account-resource-discovery-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * AWS CDK Application for automated multi-account resource discovery
 * 
 * This application creates infrastructure for:
 * - AWS Resource Explorer for cross-account resource search
 * - AWS Config aggregator for compliance monitoring
 * - EventBridge rules for event-driven automation
 * - Lambda function for intelligent processing
 * 
 * The solution enables enterprise-wide governance and compliance
 * monitoring across multiple AWS accounts with automated responses
 * to configuration changes and compliance violations.
 */

const app = new cdk.App();

// Get environment variables or use default values
const projectName = process.env.PROJECT_NAME || 'multi-account-discovery';
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
const stack = new MultiAccountResourceDiscoveryStack(app, 'MultiAccountResourceDiscoveryStack', {
  env,
  stackName: `${projectName}-stack`,
  description: 'Automated multi-account resource discovery with Resource Explorer, Config, EventBridge, and Lambda',
  
  // Stack-level tags for resource organization and cost tracking
  tags: {
    'Application': 'Multi-Account-Resource-Discovery',
    'Environment': process.env.ENVIRONMENT || 'development',
    'Owner': 'CloudGovernanceTeam',
    'CostCenter': 'IT-Governance',
    'Backup': 'Required',
    'Compliance': 'Required'
  },
  
  // Enable termination protection for production deployments
  terminationProtection: process.env.ENVIRONMENT === 'production',
  
  // Custom properties for the stack
  projectName,
});

// Apply AWS Solutions Framework security checks using CDK Nag
// This ensures the infrastructure follows AWS security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({
  verbose: true,
  logIgnores: true,
  reportInJson: true,
}));

// Add stack-level metadata
stack.addMetadata('Purpose', 'Multi-account resource discovery and compliance automation');
stack.addMetadata('Architecture', 'Event-driven serverless architecture with centralized governance');
stack.addMetadata('Services', 'Resource Explorer, Config, EventBridge, Lambda, IAM, S3');

// Synthesize the CDK application
app.synth();