#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { BatchProcessingStack } from './lib/batch-processing-stack';

/**
 * AWS CDK Application for Batch Processing Workloads with AWS Batch
 * 
 * This application creates a complete AWS Batch infrastructure including:
 * - ECR Repository for container images
 * - IAM Roles and Policies for AWS Batch
 * - Managed Compute Environment with EC2 instances
 * - Job Queue for batch job scheduling
 * - Job Definition for containerized workloads
 * - CloudWatch Log Group for job logging
 * - CloudWatch Alarms for monitoring
 * - Security Group for compute resources
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const stackName = app.node.tryGetContext('stackName') || 'BatchProcessingStack';
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the main stack
new BatchProcessingStack(app, stackName, {
  env,
  description: 'AWS Batch processing infrastructure for containerized workloads',
  
  // Stack configuration
  stackName,
  
  // Tagging for cost allocation and resource management
  tags: {
    Project: 'BatchProcessing',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: app.node.tryGetContext('owner') || 'dev-team',
    CostCenter: app.node.tryGetContext('costCenter') || 'engineering',
  },
});