#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { UptimeMonitoringStack } from './lib/uptime-monitoring-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const websiteUrl = app.node.tryGetContext('websiteUrl') || process.env.WEBSITE_URL || 'https://example.com';
const adminEmail = app.node.tryGetContext('adminEmail') || process.env.ADMIN_EMAIL || 'admin@example.com';
const stackName = app.node.tryGetContext('stackName') || 'UptimeMonitoringStack';
const environment = app.node.tryGetContext('environment') || 'Production';

// Validate required parameters
if (!websiteUrl || !adminEmail) {
  throw new Error('websiteUrl and adminEmail are required. Set via context or environment variables.');
}

// Validate email format
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
if (!emailRegex.test(adminEmail)) {
  throw new Error('Invalid email format provided for adminEmail.');
}

// Validate URL format
try {
  new URL(websiteUrl);
} catch (error) {
  throw new Error('Invalid URL format provided for websiteUrl.');
}

new UptimeMonitoringStack(app, stackName, {
  websiteUrl,
  adminEmail,
  environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: `Simple Website Uptime Monitoring for ${websiteUrl}`,
  tags: {
    Purpose: 'UptimeMonitoring',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});