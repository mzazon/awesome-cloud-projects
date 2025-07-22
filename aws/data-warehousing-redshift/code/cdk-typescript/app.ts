#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RedshiftDataWarehouseStack } from './lib/redshift-data-warehouse-stack';

const app = new cdk.App();

// Environment configuration from context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
  region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1',
};

// Create the Redshift data warehouse stack
new RedshiftDataWarehouseStack(app, 'RedshiftDataWarehouseStack', {
  env,
  description: 'Amazon Redshift Serverless data warehousing solution with S3 integration',
  
  // CDK tags for resource management
  tags: {
    Project: 'DataWarehouse',
    Environment: 'development',
    Owner: 'data-team',
    CostCenter: 'analytics',
  },
});

// Add stack termination protection for production environments
const environment = app.node.tryGetContext('environment') || 'development';
if (environment === 'production') {
  cdk.Aspects.of(app).add({
    visit(node) {
      if (node instanceof cdk.Stack) {
        node.terminationProtection = true;
      }
    },
  });
}