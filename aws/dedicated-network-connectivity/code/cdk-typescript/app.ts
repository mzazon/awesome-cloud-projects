#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { HybridConnectivityStack } from './lib/hybrid-connectivity-stack';

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  onPremisesCidr: app.node.tryGetContext('onPremisesCidr') || '10.0.0.0/8',
  onPremisesAsn: parseInt(app.node.tryGetContext('onPremisesAsn') || '65000'),
  awsAsn: parseInt(app.node.tryGetContext('awsAsn') || '64512'),
  privateVifVlan: parseInt(app.node.tryGetContext('privateVifVlan') || '100'),
  transitVifVlan: parseInt(app.node.tryGetContext('transitVifVlan') || '200'),
  projectId: app.node.tryGetContext('projectId') || 'hybrid-dx',
  enableDnsResolution: app.node.tryGetContext('enableDnsResolution') !== 'false',
  enableMonitoring: app.node.tryGetContext('enableMonitoring') !== 'false',
  enableFlowLogs: app.node.tryGetContext('enableFlowLogs') !== 'false',
};

new HybridConnectivityStack(app, 'HybridConnectivityStack', {
  ...config,
  description: 'Hybrid Cloud Connectivity with AWS Direct Connect - Production Ready Infrastructure',
  tags: {
    Project: 'HybridConnectivity',
    Environment: 'Production',
    CreatedBy: 'CDK',
    Recipe: 'hybrid-cloud-connectivity-aws-direct-connect',
  },
});