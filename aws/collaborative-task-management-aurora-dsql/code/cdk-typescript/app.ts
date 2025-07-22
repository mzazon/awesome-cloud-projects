#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RealTimeTaskManagementStack } from './lib/real-time-task-management-stack';

const app = new cdk.App();

// Primary region stack (us-east-1)
new RealTimeTaskManagementStack(app, 'RealTimeTaskManagementStack-Primary', {
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: 'us-east-1' 
  },
  region: 'us-east-1',
  isSecondaryRegion: false,
  description: 'Real-time collaborative task management system with Aurora DSQL and EventBridge (Primary Region)'
});

// Secondary region stack (us-west-2)
new RealTimeTaskManagementStack(app, 'RealTimeTaskManagementStack-Secondary', {
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: 'us-west-2' 
  },
  region: 'us-west-2',
  isSecondaryRegion: true,
  description: 'Real-time collaborative task management system with Aurora DSQL and EventBridge (Secondary Region)'
});