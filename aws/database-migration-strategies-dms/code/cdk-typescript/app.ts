#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DatabaseMigrationStack } from './lib/database-migration-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

const app = new cdk.App();

// Environment configuration
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the main stack
const databaseMigrationStack = new DatabaseMigrationStack(app, 'DatabaseMigrationStack', {
  env,
  description: 'AWS DMS Database Migration Infrastructure with replication instances, endpoints, and monitoring',
  
  // Stack tags for resource management
  tags: {
    Project: 'DatabaseMigration',
    Environment: 'Migration',
    ManagedBy: 'CDK',
    CostCenter: 'DataEngineering',
  },
});

// Apply CDK Nag security checks to ensure best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Add metadata to the app
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', false);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);