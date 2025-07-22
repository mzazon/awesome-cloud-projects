#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AutomatedBackupStack } from './lib/automated-backup-stack';
import { AwsSolutionsChecks } from 'cdk-nag';

const app = new cdk.App();

// Get configuration from context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-west-2',
};

const drRegion = app.node.tryGetContext('drRegion') || process.env.DR_REGION || 'us-east-1';
const backupRetentionDays = Number(app.node.tryGetContext('backupRetentionDays')) || 30;
const weeklyRetentionDays = Number(app.node.tryGetContext('weeklyRetentionDays')) || 90;
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const environment = app.node.tryGetContext('environment') || 'development';
const enableCdkNag = app.node.tryGetContext('enableCdkNag') !== 'false';

// Create primary backup stack
const backupStack = new AutomatedBackupStack(app, 'AutomatedBackupStack', {
  env,
  description: 'Automated backup solution using AWS Backup with cross-region replication and monitoring',
  drRegion,
  backupRetentionDays,
  weeklyRetentionDays,
  notificationEmail,
  environment,
});

// Add tags for resource management
cdk.Tags.of(backupStack).add('Project', 'AutomatedBackup');
cdk.Tags.of(backupStack).add('Environment', environment);
cdk.Tags.of(backupStack).add('Owner', 'Infrastructure');
cdk.Tags.of(backupStack).add('CostCenter', 'IT-Operations');
cdk.Tags.of(backupStack).add('ManagedBy', 'CDK');

// Apply CDK Nag security checks if enabled
if (enableCdkNag) {
  AwsSolutionsChecks.check(app);
}

app.synth();