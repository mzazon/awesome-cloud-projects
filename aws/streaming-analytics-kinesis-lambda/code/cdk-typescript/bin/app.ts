#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ServerlessRealtimeAnalyticsStack } from '../lib/serverless-realtime-analytics-stack';

const app = new cdk.App();

// Get context values or use defaults
const stackName = app.node.tryGetContext('stackName') || 'ServerlessRealtimeAnalyticsStack';
const environment = app.node.tryGetContext('environment') || 'dev';

// Get custom configuration from context
const kinesisShardCount = app.node.tryGetContext('kinesisShardCount');
const kinesisRetentionPeriod = app.node.tryGetContext('kinesisRetentionPeriod');
const lambdaMemorySize = app.node.tryGetContext('lambdaMemorySize');
const lambdaTimeout = app.node.tryGetContext('lambdaTimeout');
const lambdaBatchSize = app.node.tryGetContext('lambdaBatchSize');
const lambdaMaxBatchingWindow = app.node.tryGetContext('lambdaMaxBatchingWindow');

new ServerlessRealtimeAnalyticsStack(app, stackName, {
  /* If you don't specify 'env', this stack will be environment-agnostic.
   * Account/Region-dependent features and context lookups will not work,
   * but a single synthesized template can be deployed anywhere. */

  /* Uncomment the next line to specialize this stack for the AWS Account
   * and Region that are implied by the current CLI configuration. */
  env: { 
    account: process.env.CDK_DEFAULT_ACCOUNT, 
    region: process.env.CDK_DEFAULT_REGION 
  },

  /* Uncomment the next line if you know exactly what Account and Region you
   * want to deploy the stack to. */
  // env: { account: '123456789012', region: 'us-east-1' },

  /* For more information, see https://docs.aws.amazon.com/cdk/latest/guide/environments.html */
  
  description: `Serverless Real-Time Analytics Pipeline with Kinesis and Lambda - ${environment}`,
  
  tags: {
    Environment: environment,
    Project: 'ServerlessRealtimeAnalytics',
    Recipe: 'serverless-realtime-analytics-kinesis-lambda',
    ManagedBy: 'CDK',
    CostCenter: 'Analytics',
    Owner: 'DataEngineering'
  },

  // Pass custom configuration if provided
  ...(kinesisShardCount && { kinesisShardCount: Number(kinesisShardCount) }),
  ...(kinesisRetentionPeriod && { kinesisRetentionPeriod: cdk.Duration.hours(Number(kinesisRetentionPeriod)) }),
  ...(lambdaMemorySize && { lambdaMemorySize: Number(lambdaMemorySize) }),
  ...(lambdaTimeout && { lambdaTimeout: cdk.Duration.minutes(Number(lambdaTimeout)) }),
  ...(lambdaBatchSize && { lambdaBatchSize: Number(lambdaBatchSize) }),
  ...(lambdaMaxBatchingWindow && { lambdaMaxBatchingWindow: cdk.Duration.seconds(Number(lambdaMaxBatchingWindow)) })
});