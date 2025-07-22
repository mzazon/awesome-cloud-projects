#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { InfrastructureAutomationStack } from './lib/infrastructure-automation-stack';

/**
 * CDK Application for Infrastructure Management Automation with CloudShell PowerShell
 * 
 * This application deploys serverless automation workflows using Systems Manager Automation,
 * Lambda functions, and CloudWatch monitoring. The solution enables PowerShell scripts
 * developed in AWS CloudShell to be executed automatically on schedules or in response
 * to events, providing centralized infrastructure management without local tooling requirements.
 */
const app = new cdk.App();

// Create the main infrastructure automation stack
new InfrastructureAutomationStack(app, 'InfrastructureAutomationStack', {
  description: 'Infrastructure automation with CloudShell PowerShell, Systems Manager, and Lambda',
  
  // Enable stack termination protection for production workloads
  terminationProtection: false,
  
  // Tags applied to all resources in the stack
  tags: {
    Project: 'InfrastructureAutomation',
    Environment: 'Production',
    Purpose: 'CloudShell PowerShell Automation',
    CreatedBy: 'CDK'
  },
  
  // CDK environment - will be inferred from CLI context or defaults
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Add global tags to the application
cdk.Tags.of(app).add('Application', 'InfrastructureAutomation');
cdk.Tags.of(app).add('ManagedBy', 'CDK');