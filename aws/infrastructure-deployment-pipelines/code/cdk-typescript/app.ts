#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { PipelineStack } from './lib/pipeline-stack';

const app = new cdk.App();

// Create the pipeline stack
new PipelineStack(app, 'InfrastructureDeploymentPipeline', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Infrastructure deployment pipeline using CDK and CodePipeline',
});

app.synth();