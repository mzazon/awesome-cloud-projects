#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { CloudDevelopmentWorkflowStack } from './lib/cloud-development-workflow-stack';

/**
 * CDK Application for Cloud-Based Development Workflows
 * 
 * This application demonstrates cloud-based development workflows using
 * AWS CloudShell and CodeCommit for secure, browser-based development
 * environments with integrated source control.
 */

const app = new cdk.App();

// Get context values for configuration
const environmentName = app.node.tryGetContext('environment') || 'dev';
const repositoryName = app.node.tryGetContext('repositoryName') || 'cloud-development-workflow';

// Create the main stack
new CloudDevelopmentWorkflowStack(app, 'CloudDevelopmentWorkflowStack', {
  environmentName,
  repositoryName,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Infrastructure for cloud-based development workflows with AWS CloudShell and CodeCommit',
  tags: {
    Project: 'CloudDevelopmentWorkflow',
    Environment: environmentName,
    ManagedBy: 'CDK',
    Purpose: 'DevelopmentWorkflow'
  }
});

// Add global tags to all resources
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'cloud-development-workflows');