#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EC2FleetStack } from './lib/ec2-fleet-stack';

const app = new cdk.App();

// Get configuration from context or environment
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  fleetName: app.node.tryGetContext('fleetName') || 'ec2-fleet-demo',
  targetCapacity: {
    total: parseInt(app.node.tryGetContext('totalCapacity') || '6'),
    onDemand: parseInt(app.node.tryGetContext('onDemandCapacity') || '2'),
    spot: parseInt(app.node.tryGetContext('spotCapacity') || '4'),
  },
  instanceTypes: app.node.tryGetContext('instanceTypes') || ['t3.micro', 't3.small', 't3.nano'],
  keyPairName: app.node.tryGetContext('keyPairName'),
  enableMonitoring: app.node.tryGetContext('enableMonitoring') !== 'false',
};

new EC2FleetStack(app, 'EC2FleetStack', {
  ...config,
  description: 'CDK Stack for EC2 Fleet Management with Spot Instances',
  tags: {
    Project: 'EC2-Fleet-Demo',
    Environment: app.node.tryGetContext('environment') || 'dev',
    CreatedBy: 'CDK',
  },
});