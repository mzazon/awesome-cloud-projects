#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ComprehendNlpPipelineStack } from './lib/comprehend-nlp-pipeline-stack';

/**
 * CDK Application entry point for Amazon Comprehend NLP Pipeline
 * 
 * This application deploys a complete natural language processing pipeline
 * using Amazon Comprehend for text analysis, including:
 * - S3 buckets for input and output data
 * - Lambda function for real-time text processing
 * - IAM roles with least privilege access
 * - Batch processing capabilities for large document sets
 */
const app = new cdk.App();

// Deploy the Comprehend NLP Pipeline stack
new ComprehendNlpPipelineStack(app, 'ComprehendNlpPipelineStack', {
  description: 'Natural Language Processing Pipeline with Amazon Comprehend',
  
  // Enable termination protection for production deployments
  terminationProtection: false,
  
  // Apply consistent tags across all resources
  tags: {
    Project: 'ComprehendNlpPipeline',
    Environment: 'Development',
    Owner: 'DataEngineering',
    CostCenter: 'Analytics'
  },

  env: {
    // Inherit environment from CDK CLI or use defaults
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the CloudFormation template
app.synth();