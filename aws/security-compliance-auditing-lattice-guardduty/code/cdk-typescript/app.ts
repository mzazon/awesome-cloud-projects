#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SecurityComplianceAuditingStack } from './lib/security-compliance-auditing-stack';

/**
 * Main CDK application for Security Compliance Auditing with VPC Lattice and GuardDuty
 * 
 * This application deploys a comprehensive security compliance auditing system that
 * continuously monitors VPC Lattice access logs, integrates with GuardDuty threat
 * intelligence, and generates real-time compliance reports.
 * 
 * Key Features:
 * - Automated GuardDuty threat detection
 * - VPC Lattice access log monitoring  
 * - Real-time security analytics via Lambda
 * - CloudWatch dashboards and alerting
 * - Compliance report generation in S3
 * - SNS notifications for security incidents
 */

const app = new cdk.App();

// Get configuration from context or environment variables
const account = process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account');
const region = process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1';

// Get optional configuration parameters
const emailForAlerts = app.node.tryGetContext('emailForAlerts') || 'security-admin@yourcompany.com';
const enableVpcLatticeDemo = app.node.tryGetContext('enableVpcLatticeDemo') !== 'false';

new SecurityComplianceAuditingStack(app, 'SecurityComplianceAuditingStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Security Compliance Auditing with VPC Lattice and GuardDuty - Recipe a9b3c2d1',
  
  // Stack configuration
  emailForAlerts: emailForAlerts,
  enableVpcLatticeDemo: enableVpcLatticeDemo,
  
  // Add tags for resource management
  tags: {
    'Project': 'SecurityComplianceAuditing',
    'Recipe': 'a9b3c2d1',
    'Purpose': 'SecurityMonitoring',
    'Environment': app.node.tryGetContext('environment') || 'demo',
  },
});

// Add stack-level metadata
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
app.node.setContext('@aws-cdk/aws-s3:createDefaultLoggingPolicy', true);