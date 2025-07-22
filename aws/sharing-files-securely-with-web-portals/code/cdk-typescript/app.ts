#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SecureFileSharingStack } from './lib/secure-file-sharing-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * AWS CDK application for secure file sharing with Transfer Family Web Apps
 * 
 * This application creates a complete secure file sharing solution using:
 * - AWS Transfer Family Web Apps for browser-based file access
 * - S3 for secure object storage with encryption and lifecycle policies  
 * - IAM Identity Center for centralized authentication
 * - CloudTrail for comprehensive audit logging
 * - Fine-grained access controls and monitoring
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const envConfig = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1'
};

// Create the main stack for secure file sharing
const secureFileSharingStack = new SecureFileSharingStack(app, 'SecureFileSharingStack', {
  env: envConfig,
  description: 'Secure file sharing portal using AWS Transfer Family Web Apps with S3, Identity Center, and CloudTrail audit logging',
  
  // Add stack-level tags for resource management and cost allocation
  tags: {
    Project: 'SecureFileSharing',
    Environment: process.env.ENVIRONMENT || 'Development',
    Owner: process.env.OWNER || 'DevOps',
    CostCenter: process.env.COST_CENTER || 'IT',
    Application: 'TransferFamilyWebApp'
  }
});

// Apply AWS security best practices using CDK Nag
// This ensures the infrastructure follows AWS Well-Architected security principles
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ 
  verbose: true,
  reports: true,
  logIgnores: false
}));

// Add application-level tags
cdk.Tags.of(app).add('CreatedBy', 'AWS-CDK');
cdk.Tags.of(app).add('Repository', 'aws-samples/recipes');
cdk.Tags.of(app).add('RecipeVersion', '1.0');
cdk.Tags.of(app).add('LastUpdated', '2025-01-17');