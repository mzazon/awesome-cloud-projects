#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { GuardDutyThreatDetectionStack } from './lib/guardduty-threat-detection-stack';

/**
 * CDK Application for GuardDuty Threat Detection
 * 
 * This application deploys a comprehensive threat detection system using Amazon GuardDuty
 * with automated alerting through SNS and monitoring via CloudWatch dashboards.
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Get notification email from context
const notificationEmail = app.node.tryGetContext('notificationEmail') || 
                         process.env.NOTIFICATION_EMAIL;

if (!notificationEmail) {
  throw new Error('Notification email is required. Set NOTIFICATION_EMAIL environment variable or use --context notificationEmail=your-email@example.com');
}

// Create the GuardDuty threat detection stack
new GuardDutyThreatDetectionStack(app, 'GuardDutyThreatDetectionStack', {
  env,
  description: 'Comprehensive threat detection system using Amazon GuardDuty with automated alerting and monitoring',
  notificationEmail,
  // Optional: Configure finding export to S3
  enableS3Export: app.node.tryGetContext('enableS3Export') !== 'false',
  // Optional: Configure finding publishing frequency
  findingPublishingFrequency: app.node.tryGetContext('findingPublishingFrequency') || 'FIFTEEN_MINUTES',
  tags: {
    Application: 'GuardDutyThreatDetection',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'SecurityTeam',
    CostCenter: app.node.tryGetContext('costCenter') || 'security',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'ThreatDetection');
cdk.Tags.of(app).add('ManagedBy', 'CDK');