#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DedicatedHostsLicenseComplianceStack } from './lib/dedicated-hosts-license-compliance-stack';

const app = new cdk.App();

// Get context values or use defaults
const stackName = app.node.tryGetContext('stackName') || 'DedicatedHostsLicenseComplianceStack';
const notificationEmail = app.node.tryGetContext('notificationEmail');
const windowsInstanceFamily = app.node.tryGetContext('windowsInstanceFamily') || 'm5';
const oracleInstanceFamily = app.node.tryGetContext('oracleInstanceFamily') || 'r5';
const windowsLicenseCount = app.node.tryGetContext('windowsLicenseCount') || 10;
const oracleLicenseCount = app.node.tryGetContext('oracleLicenseCount') || 16;

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

new DedicatedHostsLicenseComplianceStack(app, stackName, {
  env,
  description: 'AWS CDK Stack for Dedicated Hosts License Compliance with BYOL support',
  notificationEmail,
  windowsInstanceFamily,
  oracleInstanceFamily,
  windowsLicenseCount,
  oracleLicenseCount,
  tags: {
    Project: 'LicenseCompliance',
    Purpose: 'BYOL-Production',
    Environment: 'Production',
    ManagedBy: 'CDK',
  },
});