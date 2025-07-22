#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiAgentWorkflowStack } from './lib/multi-agent-workflow-stack';

const app = new cdk.App();

// Generate unique suffix for resource names
const uniqueSuffix = Math.random().toString(36).substring(2, 8);

new MultiAgentWorkflowStack(app, 'MultiAgentWorkflowStack', {
  uniqueSuffix: uniqueSuffix,
  description: 'Multi-Agent AI Workflows with Amazon Bedrock AgentCore',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'MultiAgentWorkflow',
    Environment: 'Development',
    CreatedBy: 'CDK',
  },
});