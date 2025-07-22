#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CloudFrontInvalidationStack } from './lib/cloudfront-invalidation-stack';
import { Construct } from 'constructs';

/**
 * AWS CDK TypeScript Application for CloudFront Cache Invalidation Strategies
 * 
 * This application implements an intelligent CloudFront cache invalidation system
 * that automatically detects content changes, applies selective invalidation patterns,
 * optimizes costs through batch processing, and provides comprehensive monitoring.
 * 
 * Architecture Components:
 * - S3 Bucket for origin content
 * - CloudFront Distribution with Origin Access Control (OAC)
 * - Lambda Function for intelligent invalidation logic
 * - EventBridge Custom Bus for event-driven automation
 * - SQS Queue for batch processing
 * - DynamoDB Table for invalidation audit logging
 * - CloudWatch Dashboard for monitoring and optimization
 * 
 * The solution uses EventBridge for event-driven automation, Lambda functions
 * for intelligent invalidation logic, and CloudWatch for performance tracking
 * to achieve cache hit rates above 85% while minimizing invalidation costs.
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config = {
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
    region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1',
  },
  
  // Stack naming configuration
  stackName: app.node.tryGetContext('stackName') || 'CloudFrontInvalidationStack',
  
  // Resource naming configuration
  projectName: app.node.tryGetContext('projectName') || 'cf-invalidation',
  
  // Feature flags
  enableMonitoring: app.node.tryGetContext('enableMonitoring') !== 'false',
  enableBatchProcessing: app.node.tryGetContext('enableBatchProcessing') !== 'false',
  enableCostOptimization: app.node.tryGetContext('enableCostOptimization') !== 'false',
  
  // Performance configuration
  lambdaTimeout: parseInt(app.node.tryGetContext('lambdaTimeout') || '300'),
  lambdaMemory: parseInt(app.node.tryGetContext('lambdaMemory') || '256'),
  batchSize: parseInt(app.node.tryGetContext('batchSize') || '10'),
  batchWindow: parseInt(app.node.tryGetContext('batchWindow') || '30'),
  
  // CloudFront configuration
  priceClass: app.node.tryGetContext('priceClass') || 'PriceClass_100',
  enableCompression: app.node.tryGetContext('enableCompression') !== 'false',
  enableIPv6: app.node.tryGetContext('enableIPv6') !== 'false',
  
  // Security configuration
  enableOriginAccessControl: app.node.tryGetContext('enableOriginAccessControl') !== 'false',
  enforceHTTPS: app.node.tryGetContext('enforceHTTPS') !== 'false',
  
  // Monitoring configuration
  retentionPeriod: parseInt(app.node.tryGetContext('retentionPeriod') || '30'),
  dashboardName: app.node.tryGetContext('dashboardName') || 'CloudFront-Invalidation-Dashboard',
  
  // Tags to apply to all resources
  tags: {
    Application: 'CloudFront-Cache-Invalidation',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: app.node.tryGetContext('owner') || 'platform-team',
    Project: 'intelligent-cache-invalidation',
    CostCenter: app.node.tryGetContext('costCenter') || 'engineering',
    ManagedBy: 'AWS-CDK',
    Version: '1.0.0',
    ...JSON.parse(app.node.tryGetContext('additionalTags') || '{}'),
  },
};

// Validate configuration
if (!config.env.account) {
  throw new Error('Account ID must be specified via CDK_DEFAULT_ACCOUNT environment variable or CDK context');
}

if (!config.env.region) {
  throw new Error('Region must be specified via CDK_DEFAULT_REGION environment variable or CDK context');
}

// Create the main stack
const stack = new CloudFrontInvalidationStack(app, config.stackName, {
  env: config.env,
  description: 'Intelligent CloudFront cache invalidation system with automated content change detection, selective invalidation patterns, cost optimization through batch processing, and comprehensive monitoring capabilities.',
  
  // Pass configuration to stack
  projectName: config.projectName,
  enableMonitoring: config.enableMonitoring,
  enableBatchProcessing: config.enableBatchProcessing,
  enableCostOptimization: config.enableCostOptimization,
  
  // Performance configuration
  lambdaTimeout: config.lambdaTimeout,
  lambdaMemory: config.lambdaMemory,
  batchSize: config.batchSize,
  batchWindow: config.batchWindow,
  
  // CloudFront configuration
  priceClass: config.priceClass,
  enableCompression: config.enableCompression,
  enableIPv6: config.enableIPv6,
  
  // Security configuration
  enableOriginAccessControl: config.enableOriginAccessControl,
  enforceHTTPS: config.enforceHTTPS,
  
  // Monitoring configuration
  retentionPeriod: config.retentionPeriod,
  dashboardName: config.dashboardName,
  
  // Apply tags to all resources in the stack
  tags: config.tags,
});

// Add stack-level tags
Object.entries(config.tags).forEach(([key, value]) => {
  cdk.Tags.of(stack).add(key, value);
});

// Output deployment information
new cdk.CfnOutput(stack, 'StackName', {
  value: stack.stackName,
  description: 'Name of the CloudFormation stack',
});

new cdk.CfnOutput(stack, 'Region', {
  value: stack.region,
  description: 'AWS region where the stack is deployed',
});

new cdk.CfnOutput(stack, 'Account', {
  value: stack.account,
  description: 'AWS account ID where the stack is deployed',
});

// Add termination protection for production environments
if (config.tags.Environment === 'production') {
  stack.terminationProtection = true;
}

// Synthesize the CloudFormation template
app.synth();

// Export configuration for use in other modules
export { config };