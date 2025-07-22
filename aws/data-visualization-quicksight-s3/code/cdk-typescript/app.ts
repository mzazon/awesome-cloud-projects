#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DataVisualizationPipelineStack } from './lib/data-visualization-pipeline-stack';

const app = new cdk.App();

// Get configuration from context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

const projectName = app.node.tryGetContext('projectName') || 'data-viz-pipeline';
const environment = app.node.tryGetContext('environment') || 'dev';

new DataVisualizationPipelineStack(app, `DataVisualizationPipelineStack-${environment}`, {
  env,
  projectName,
  environment,
  description: 'Data Visualization Pipeline with QuickSight, S3, Glue, and Athena',
  tags: {
    Project: projectName,
    Environment: environment,
    Purpose: 'DataVisualization',
    ManagedBy: 'CDK',
  },
});