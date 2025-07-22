#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DrmProtectedVideoStreamingStack } from './lib/drm-protected-video-streaming-stack';

const app = new cdk.App();

// Get context values or use defaults
const stackName = app.node.tryGetContext('stackName') || 'DrmProtectedVideoStreaming';
const environment = app.node.tryGetContext('environment') || 'dev';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Create the main stack
new DrmProtectedVideoStreamingStack(app, `${stackName}-${environment}`, {
  env: {
    account: account,
    region: region,
  },
  description: 'DRM-protected video streaming infrastructure with MediaPackage and multi-DRM support',
  tags: {
    Project: 'DRM-Protected-Streaming',
    Environment: environment,
    Service: 'Video-Content-Protection',
    Generator: 'CDK-TypeScript',
    Version: '1.0'
  }
});

// Add stack-level tags
cdk.Tags.of(app).add('Project', 'DRM-Protected-Streaming');
cdk.Tags.of(app).add('ManagedBy', 'CDK');