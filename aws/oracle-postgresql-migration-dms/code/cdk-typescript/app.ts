#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { DatabaseMigrationStack } from './lib/database-migration-stack';

const app = new cdk.App();

// Get deployment parameters from context or environment variables
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'oracle-to-postgresql';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const oracleServerName = app.node.tryGetContext('oracleServerName') || process.env.ORACLE_SERVER_NAME || 'your-oracle-server.example.com';
const oracleUsername = app.node.tryGetContext('oracleUsername') || process.env.ORACLE_USERNAME || 'oracle_user';
const oracleDatabaseName = app.node.tryGetContext('oracleDatabaseName') || process.env.ORACLE_DATABASE_NAME || 'ORCL';

// Account and region from CDK environment
const account = process.env.CDK_DEFAULT_ACCOUNT;
const region = process.env.CDK_DEFAULT_REGION;

if (!account || !region) {
  throw new Error('Please set CDK_DEFAULT_ACCOUNT and CDK_DEFAULT_REGION environment variables');
}

new DatabaseMigrationStack(app, `DatabaseMigrationStack-${environment}`, {
  env: {
    account: account,
    region: region,
  },
  description: 'Oracle to PostgreSQL database migration infrastructure using AWS DMS and Aurora PostgreSQL',
  tags: {
    Project: projectName,
    Environment: environment,
    Component: 'DatabaseMigration',
    Purpose: 'OracleToPostgreSQLMigration'
  },
  // Stack-specific properties
  projectName: projectName,
  environment: environment,
  oracleServerName: oracleServerName,
  oracleUsername: oracleUsername,
  oracleDatabaseName: oracleDatabaseName,
});

app.synth();