#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiRegionBackupStack } from './lib/multi-region-backup-stack';

const app = new cdk.App();

// Get configuration from context or use defaults
const primaryRegion = app.node.tryGetContext('primaryRegion') || 'us-east-1';
const secondaryRegion = app.node.tryGetContext('secondaryRegion') || 'us-west-2';
const tertiaryRegion = app.node.tryGetContext('tertiaryRegion') || 'eu-west-1';
const organizationName = app.node.tryGetContext('organizationName') || 'YourOrg';
const notificationEmail = app.node.tryGetContext('notificationEmail') || 'admin@example.com';

// Deploy stacks in each region for comprehensive backup coverage
new MultiRegionBackupStack(app, 'MultiRegionBackupStackPrimary', {
  env: { region: primaryRegion },
  isPrimaryRegion: true,
  primaryRegion,
  secondaryRegion,
  tertiaryRegion,
  organizationName,
  notificationEmail,
  description: `Multi-region backup solution - Primary region (${primaryRegion})`
});

new MultiRegionBackupStack(app, 'MultiRegionBackupStackSecondary', {
  env: { region: secondaryRegion },
  isPrimaryRegion: false,
  primaryRegion,
  secondaryRegion,
  tertiaryRegion,
  organizationName,
  notificationEmail,
  description: `Multi-region backup solution - Secondary region (${secondaryRegion})`
});

new MultiRegionBackupStack(app, 'MultiRegionBackupStackTertiary', {
  env: { region: tertiaryRegion },
  isPrimaryRegion: false,
  primaryRegion,
  secondaryRegion,
  tertiaryRegion,
  organizationName,
  notificationEmail,
  description: `Multi-region backup solution - Tertiary region (${tertiaryRegion})`
});

// Add tags to all resources in the application
cdk.Tags.of(app).add('Project', 'MultiRegionBackup');
cdk.Tags.of(app).add('Environment', 'Production');
cdk.Tags.of(app).add('CostCenter', 'Infrastructure');
cdk.Tags.of(app).add('ManagedBy', 'CDK');