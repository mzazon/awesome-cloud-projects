#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiRegionBackupStack } from './lib/multi-region-backup-stack';

/**
 * AWS CDK App for Automating Multi-Region Backup Strategies using AWS Backup
 * 
 * This application deploys a comprehensive multi-region backup solution that:
 * - Creates backup vaults across multiple regions
 * - Implements automated backup plans with cross-region copy
 * - Sets up EventBridge monitoring for backup job state changes
 * - Deploys Lambda functions for backup validation
 * - Configures SNS notifications for alerts
 * 
 * The solution follows AWS Well-Architected Framework principles for
 * reliability, security, and cost optimization.
 */

const app = new cdk.App();

// Configuration for the multi-region backup solution
const config = {
  organizationName: process.env.ORGANIZATION_NAME || 'MyOrg',
  primaryRegion: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  secondaryRegion: process.env.SECONDARY_REGION || 'us-west-2',
  tertiaryRegion: process.env.TERTIARY_REGION || 'eu-west-1',
  notificationEmail: process.env.NOTIFICATION_EMAIL || 'admin@example.com',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  }
};

// Deploy the primary stack in the main region
const primaryStack = new MultiRegionBackupStack(app, 'MultiRegionBackupPrimaryStack', {
  ...config,
  stackName: 'multi-region-backup-primary',
  description: 'Primary stack for multi-region backup strategies using AWS Backup',
});

// Deploy secondary stacks in other regions for cross-region backup vaults
const secondaryStack = new MultiRegionBackupStack(app, 'MultiRegionBackupSecondaryStack', {
  ...config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: config.secondaryRegion
  },
  stackName: 'multi-region-backup-secondary',
  description: 'Secondary stack for multi-region backup strategies (disaster recovery region)',
});

const tertiaryStack = new MultiRegionBackupStack(app, 'MultiRegionBackupTertiaryStack', {
  ...config,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: config.tertiaryRegion
  },
  stackName: 'multi-region-backup-tertiary',
  description: 'Tertiary stack for multi-region backup strategies (long-term archival region)',
});

// Add tags to all stacks for cost allocation and governance
const commonTags = {
  'Project': 'MultiRegionBackup',
  'Environment': 'Production',
  'Owner': 'BackupTeam',
  'CostCenter': 'Infrastructure',
  'Compliance': 'Required'
};

Object.entries(commonTags).forEach(([key, value]) => {
  cdk.Tags.of(primaryStack).add(key, value);
  cdk.Tags.of(secondaryStack).add(key, value);
  cdk.Tags.of(tertiaryStack).add(key, value);
});

// Synthesize the CloudFormation templates
app.synth();