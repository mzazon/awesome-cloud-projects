#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DisasterRecoveryS3Stack } from './lib/disaster-recovery-s3-stack';

/**
 * CDK Application for S3 Cross-Region Replication Disaster Recovery
 * 
 * This application deploys a comprehensive disaster recovery solution using
 * S3 Cross-Region Replication (CRR) with monitoring and alerting capabilities.
 * 
 * The solution includes:
 * - Source S3 bucket with versioning enabled
 * - Destination S3 bucket in a different region
 * - IAM role for secure cross-region replication
 * - CloudWatch monitoring and alarms
 * - CloudTrail logging for audit compliance
 * - SNS notifications for replication alerts
 */

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const primaryRegion = app.node.tryGetContext('primaryRegion') || process.env.PRIMARY_REGION || 'us-east-1';
const drRegion = app.node.tryGetContext('drRegion') || process.env.DR_REGION || 'us-west-2';
const bucketPrefix = app.node.tryGetContext('bucketPrefix') || process.env.BUCKET_PREFIX || 'dr-replication';
const enableCloudTrail = app.node.tryGetContext('enableCloudTrail') !== 'false';
const enableMonitoring = app.node.tryGetContext('enableMonitoring') !== 'false';

// Validate that primary and DR regions are different
if (primaryRegion === drRegion) {
  throw new Error('Primary region and DR region must be different for cross-region replication');
}

// Deploy primary stack in the source region
const primaryStack = new DisasterRecoveryS3Stack(app, 'DisasterRecoveryS3PrimaryStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: primaryRegion,
  },
  stackName: `disaster-recovery-s3-primary-${primaryRegion}`,
  description: 'Primary stack for S3 Cross-Region Replication disaster recovery solution',
  
  // Stack-specific configuration
  isPrimaryStack: true,
  primaryRegion: primaryRegion,
  drRegion: drRegion,
  bucketPrefix: bucketPrefix,
  enableCloudTrail: enableCloudTrail,
  enableMonitoring: enableMonitoring,
  
  // Add tags for resource management and cost allocation
  tags: {
    Project: 'DisasterRecovery',
    Component: 'S3CrossRegionReplication',
    Environment: 'Production',
    CostCenter: 'Infrastructure',
    Region: 'Primary'
  }
});

// Deploy destination stack in the DR region
const drStack = new DisasterRecoveryS3Stack(app, 'DisasterRecoveryS3DrStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: drRegion,
  },
  stackName: `disaster-recovery-s3-dr-${drRegion}`,
  description: 'Destination stack for S3 Cross-Region Replication disaster recovery solution',
  
  // Stack-specific configuration
  isPrimaryStack: false,
  primaryRegion: primaryRegion,
  drRegion: drRegion,
  bucketPrefix: bucketPrefix,
  enableCloudTrail: enableCloudTrail,
  enableMonitoring: enableMonitoring,
  
  // Cross-stack dependencies
  sourceBucketArn: primaryStack.sourceBucketArn,
  replicationRoleArn: primaryStack.replicationRoleArn,
  
  // Add tags for resource management and cost allocation
  tags: {
    Project: 'DisasterRecovery',
    Component: 'S3CrossRegionReplication',
    Environment: 'Production',
    CostCenter: 'Infrastructure',
    Region: 'DisasterRecovery'
  }
});

// Add dependency to ensure primary stack deploys first
drStack.addDependency(primaryStack);

// Add metadata for better CloudFormation template documentation
primaryStack.templateOptions.description = 
  'AWS CDK stack for S3 Cross-Region Replication disaster recovery - Primary region resources';
drStack.templateOptions.description = 
  'AWS CDK stack for S3 Cross-Region Replication disaster recovery - DR region resources';

// Output deployment information
console.log(`Primary Region: ${primaryRegion}`);
console.log(`DR Region: ${drRegion}`);
console.log(`Bucket Prefix: ${bucketPrefix}`);
console.log(`CloudTrail Enabled: ${enableCloudTrail}`);
console.log(`Monitoring Enabled: ${enableMonitoring}`);