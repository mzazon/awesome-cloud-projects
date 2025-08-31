#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SimpleTextProcessingStack } from './lib/simple-text-processing-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

/**
 * Main CDK Application for Simple Text Processing with CloudShell and S3
 * 
 * This application creates the infrastructure needed for text processing workflows
 * using AWS CloudShell and S3 storage. The stack includes:
 * - S3 bucket for storing input and output files
 * - Appropriate IAM permissions for CloudShell access
 * - Security best practices with encryption and access controls
 */

const app = new cdk.App();

// Get environment configuration from context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
const textProcessingStack = new SimpleTextProcessingStack(app, 'SimpleTextProcessingStack', {
  env,
  description: 'Infrastructure for simple text processing using CloudShell and S3',
  
  // Add tags for resource management and cost tracking
  tags: {
    Project: 'SimpleTextProcessing',
    Environment: 'Demo',
    Purpose: 'TextAnalysis',
    CreatedBy: 'CDK'
  }
});

// Apply CDK Nag for security best practices validation
// This ensures the infrastructure follows AWS security best practices
AwsSolutionsChecks.check(app, {
  verbose: true,
  reportFormats: ['cli']
});

// Add global aspects for consistent resource configuration
cdk.Aspects.of(app).add({
  visit(node: cdk.IConstruct) {
    // Ensure all resources have consistent tagging
    if (cdk.CfnResource.isCfnResource(node)) {
      const cfnResource = node as cdk.CfnResource;
      cdk.Tags.of(cfnResource).add('ManagedBy', 'CDK');
      cdk.Tags.of(cfnResource).add('Recipe', 'simple-text-processing-cloudshell-s3');
    }
  }
});