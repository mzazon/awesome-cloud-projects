#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DistributedScientificComputingStack } from './lib/distributed-scientific-computing-stack';

const app = new cdk.App();

// Get context values for customization
const envName = app.node.tryGetContext('envName') || 'dev';
const nodeCount = parseInt(app.node.tryGetContext('nodeCount')) || 2;
const instanceTypes = app.node.tryGetContext('instanceTypes') || ['c5.large', 'c5.xlarge'];
const maxvCpus = parseInt(app.node.tryGetContext('maxvCpus')) || 256;

new DistributedScientificComputingStack(app, `DistributedScientificComputing-${envName}`, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS Batch Multi-Node Parallel Jobs for Distributed Scientific Computing',
  tags: {
    Environment: envName,
    Project: 'scientific-computing',
    Purpose: 'distributed-hpc',
  },
  // Stack-specific configuration
  nodeCount,
  instanceTypes,
  maxvCpus,
});