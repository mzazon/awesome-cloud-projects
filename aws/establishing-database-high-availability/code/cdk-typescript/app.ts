#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiAzDatabaseStack } from './lib/multi-az-database-stack';
import { Tags } from 'aws-cdk-lib';

const app = new cdk.App();

// Create the Multi-AZ database stack
const multiAzStack = new MultiAzDatabaseStack(app, 'MultiAzDatabaseStack', {
  env: {
    // Use the account and region from the environment
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Multi-AZ RDS Aurora PostgreSQL cluster with high availability configuration',
});

// Apply common tags to all resources in the stack
Tags.of(multiAzStack).add('Project', 'MultiAzDatabase');
Tags.of(multiAzStack).add('Environment', 'Development');
Tags.of(multiAzStack).add('Owner', 'DevOps');
Tags.of(multiAzStack).add('Recipe', 'multi-az-database-deployments-high-availability');