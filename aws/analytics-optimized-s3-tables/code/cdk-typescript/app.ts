#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag';
import { AnalyticsOptimizedS3TablesStack } from './lib/analytics-optimized-s3-tables-stack';

/**
 * CDK Application for Analytics-Optimized Data Storage with S3 Tables
 * 
 * This application deploys a complete analytics solution using Amazon S3 Tables
 * with Apache Iceberg format, integrated with AWS analytics services including
 * Amazon Athena, AWS Glue, and Amazon QuickSight.
 * 
 * Features:
 * - S3 Table Bucket with automatic maintenance operations
 * - Table Namespace for logical organization
 * - Apache Iceberg table with optimized schema
 * - AWS Glue Data Catalog integration
 * - Amazon Athena workgroup for interactive querying
 * - Sample dataset and ETL pipeline
 * - Security best practices with CDK Nag validation
 */

const app = new cdk.App();

// Environment configuration
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Stack configuration
const stackProps: cdk.StackProps = {
  env,
  description: 'Analytics-Optimized Data Storage with S3 Tables - CDK Implementation',
  tags: {
    Project: 'AnalyticsOptimizedS3Tables',
    Environment: process.env.NODE_ENV || 'development',
    CostCenter: 'Analytics',
    Owner: 'DataEngineering',
    Recipe: 'analytics-optimized-data-storage-s3-tables',
  },
};

// Create the main stack
const analyticsStack = new AnalyticsOptimizedS3TablesStack(
  app, 
  'AnalyticsOptimizedS3TablesStack', 
  stackProps
);

// Apply AWS security best practices with CDK Nag
// This ensures the infrastructure follows AWS Well-Architected Framework
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Add additional stack tags for cost tracking and governance
cdk.Tags.of(analyticsStack).add('StackType', 'Analytics');
cdk.Tags.of(analyticsStack).add('DataClassification', 'Internal');
cdk.Tags.of(analyticsStack).add('BackupRequired', 'Yes');
cdk.Tags.of(analyticsStack).add('MonitoringLevel', 'Enhanced');