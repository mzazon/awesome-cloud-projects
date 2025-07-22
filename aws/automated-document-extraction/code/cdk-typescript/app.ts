#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { TextractDocumentProcessingStack } from './lib/textract-document-processing-stack';

const app = new cdk.App();

// Get environment configuration
const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Create the Textract document processing stack
new TextractDocumentProcessingStack(app, 'TextractDocumentProcessingStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Intelligent Document Processing with Amazon Textract - Stack for automated document analysis and text extraction',
  tags: {
    Project: 'TextractDocumentProcessing',
    Environment: 'Demo',
    CostCenter: 'ML-Analytics',
    Recipe: 'intelligent-document-processing-amazon-textract'
  }
});

app.synth();