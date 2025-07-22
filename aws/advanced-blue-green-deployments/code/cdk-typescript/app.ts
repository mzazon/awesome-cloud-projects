#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AdvancedBlueGreenDeploymentStack } from './lib/advanced-blue-green-deployment-stack';

const app = new cdk.App();

// Get context variables with defaults
const projectName = app.node.tryGetContext('projectName') || 'advanced-deployment';
const environment = app.node.tryGetContext('environment') || 'dev';

new AdvancedBlueGreenDeploymentStack(app, 'AdvancedBlueGreenDeploymentStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  projectName,
  environment,
  description: 'Advanced Blue-Green Deployments with ECS, Lambda, and CodeDeploy',
  tags: {
    Project: projectName,
    Environment: environment,
    Recipe: 'advanced-blue-green-deployments-ecs-lambda-codedeploy',
    ManagedBy: 'CDK',
  },
});

app.synth();