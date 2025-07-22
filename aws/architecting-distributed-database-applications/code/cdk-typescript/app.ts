#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiRegionDistributedApplicationsStack } from './lib/multi-region-distributed-applications-stack';

const app = new cdk.App();

// Configuration parameters
const projectName = 'MultiRegionDistributedApp';
const primaryRegion = 'us-east-1';
const secondaryRegion = 'us-west-2';
const witnessRegion = 'eu-west-1';

// Create primary region stack
const primaryStack = new MultiRegionDistributedApplicationsStack(app, `${projectName}-Primary`, {
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: primaryRegion 
  },
  stackName: `${projectName}-Primary-Stack`,
  primaryRegion: primaryRegion,
  secondaryRegion: secondaryRegion,
  witnessRegion: witnessRegion,
  isPrimaryRegion: true,
  tags: {
    Environment: 'Production',
    Application: 'DistributedApp',
    Region: 'Primary'
  }
});

// Create secondary region stack
const secondaryStack = new MultiRegionDistributedApplicationsStack(app, `${projectName}-Secondary`, {
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: secondaryRegion 
  },
  stackName: `${projectName}-Secondary-Stack`,
  primaryRegion: primaryRegion,
  secondaryRegion: secondaryRegion,
  witnessRegion: witnessRegion,
  isPrimaryRegion: false,
  tags: {
    Environment: 'Production',
    Application: 'DistributedApp',
    Region: 'Secondary'
  }
});

// Add dependencies between stacks
secondaryStack.addDependency(primaryStack);

app.synth();