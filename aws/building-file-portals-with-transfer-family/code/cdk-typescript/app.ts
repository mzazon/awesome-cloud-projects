#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SecureFilePortalStack } from './lib/secure-file-portal-stack';

/**
 * CDK Application for Secure Self-Service File Portals with AWS Transfer Family Web Apps
 * 
 * This application creates a complete secure file sharing solution using:
 * - AWS Transfer Family Web Apps for the web portal
 * - S3 for file storage with encryption and versioning
 * - IAM Identity Center for authentication
 * - S3 Access Grants for fine-grained permissions
 * - IAM roles with least privilege access
 */

const app = new cdk.App();

// Get deployment context from CDK context or environment variables
const stackName = app.node.tryGetContext('stackName') || 'SecureFilePortalStack';
const environment = app.node.tryGetContext('environment') || 'dev';

new SecureFilePortalStack(app, stackName, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Secure Self-Service File Portal with AWS Transfer Family Web Apps, S3 Access Grants, and IAM Identity Center integration',
  tags: {
    Project: 'SecureFilePortal',
    Environment: environment,
    ManagedBy: 'CDK',
    Purpose: 'FileSharing'
  }
});