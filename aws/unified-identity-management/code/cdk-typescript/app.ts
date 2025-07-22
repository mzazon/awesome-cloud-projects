#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { HybridIdentityStack } from './lib/hybrid-identity-stack';

/**
 * CDK Application for Hybrid Identity Management with AWS Directory Service
 * 
 * This application creates a complete hybrid identity management solution using:
 * - AWS Managed Microsoft AD (Directory Service)
 * - Amazon WorkSpaces for virtual desktop infrastructure
 * - Amazon RDS SQL Server with Windows Authentication
 * - Supporting networking and security infrastructure
 */
const app = new cdk.App();

// Get environment configuration from context or use defaults
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

// Create the main stack
new HybridIdentityStack(app, 'HybridIdentityManagementStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'Hybrid Identity Management solution with AWS Directory Service, WorkSpaces, and RDS',
  
  // Stack-specific configuration
  terminationProtection: false, // Set to true for production environments
  
  // Tags applied to all resources in this stack
  tags: {
    Project: 'HybridIdentityManagement',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: 'CloudTeam',
    CostCenter: app.node.tryGetContext('costCenter') || 'IT',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('Recipe', 'hybrid-identity-management-aws-directory-service');