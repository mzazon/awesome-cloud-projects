#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AdvancedRequestRoutingStack } from './lib/advanced-request-routing-stack';

const app = new cdk.App();

// Get context values with defaults
const stackPrefix = app.node.tryGetContext('stackPrefix') || 'AdvancedRouting';
const environment = app.node.tryGetContext('environment') || 'dev';
const vpcCidr = app.node.tryGetContext('vpcCidr') || '10.0.0.0/16';
const targetVpcCidr = app.node.tryGetContext('targetVpcCidr') || '10.1.0.0/16';

new AdvancedRequestRoutingStack(app, `${stackPrefix}-${environment}`, {
  stackName: `${stackPrefix}-${environment}`,
  description: 'Advanced Request Routing with VPC Lattice and ALB - Demonstrates sophisticated layer 7 routing across VPCs',
  vpcCidr,
  targetVpcCidr,
  environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'AdvancedRequestRouting',
    Environment: environment,
    ManagedBy: 'CDK',
    Recipe: 'advanced-request-routing-lattice-alb'
  }
});