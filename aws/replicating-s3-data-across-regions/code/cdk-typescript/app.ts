#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { S3CrossRegionReplicationStack } from './lib/s3-cross-region-replication-stack';

/**
 * AWS CDK Application for S3 Cross-Region Replication with Encryption and Access Controls
 * 
 * This application demonstrates implementing secure cross-region replication for S3 buckets
 * with KMS encryption, IAM access controls, and CloudWatch monitoring.
 * 
 * Architecture includes:
 * - Source S3 bucket with KMS encryption in primary region
 * - Destination S3 bucket with KMS encryption in secondary region
 * - IAM replication role with least privilege permissions
 * - Cross-region replication configuration
 * - CloudWatch alarms for monitoring replication health
 * - Bucket policies enforcing encryption and secure transport
 */

const app = new cdk.App();

// Get configuration from context or environment variables
const primaryRegion = app.node.tryGetContext('primaryRegion') || process.env.CDK_PRIMARY_REGION || 'us-east-1';
const secondaryRegion = app.node.tryGetContext('secondaryRegion') || process.env.CDK_SECONDARY_REGION || 'us-west-2';
const projectName = app.node.tryGetContext('projectName') || process.env.CDK_PROJECT_NAME || 'S3CrossRegionReplication';

// Create the primary stack in the primary region
const primaryStack = new S3CrossRegionReplicationStack(app, `${projectName}-Primary-Stack`, {
  env: {
    region: primaryRegion,
    account: process.env.CDK_DEFAULT_ACCOUNT,
  },
  description: 'S3 Cross-Region Replication - Primary region resources',
  isPrimaryRegion: true,
  primaryRegion,
  secondaryRegion,
  projectName,
});

// Create the secondary stack in the secondary region
const secondaryStack = new S3CrossRegionReplicationStack(app, `${projectName}-Secondary-Stack`, {
  env: {
    region: secondaryRegion,
    account: process.env.CDK_DEFAULT_ACCOUNT,
  },
  description: 'S3 Cross-Region Replication - Secondary region resources',
  isPrimaryRegion: false,
  primaryRegion,
  secondaryRegion,
  projectName,
  sourceBucketArn: primaryStack.sourceBucketArn,
  sourceKmsKeyArn: primaryStack.sourceKmsKeyArn,
});

// Add cross-stack dependencies
secondaryStack.addDependency(primaryStack);

// Add tags to all resources
cdk.Tags.of(app).add('Project', projectName);
cdk.Tags.of(app).add('Purpose', 'CrossRegionReplication');
cdk.Tags.of(app).add('Environment', app.node.tryGetContext('environment') || 'development');
cdk.Tags.of(app).add('ManagedBy', 'CDK');

/**
 * Sample deployment commands:
 * 
 * Deploy to both regions:
 * npx cdk deploy --all
 * 
 * Deploy with custom configuration:
 * npx cdk deploy --all --context primaryRegion=us-east-1 --context secondaryRegion=eu-west-1 --context projectName=MyProject
 * 
 * Deploy only primary region:
 * npx cdk deploy S3CrossRegionReplication-Primary-Stack
 * 
 * Deploy only secondary region (after primary):
 * npx cdk deploy S3CrossRegionReplication-Secondary-Stack
 */