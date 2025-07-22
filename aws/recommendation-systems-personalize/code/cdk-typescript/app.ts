#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { RecommendationSystemStack } from './lib/recommendation-system-stack';

const app = new cdk.App();

// Get configuration from CDK context or environment variables
const config = {
  region: app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1',
  account: app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT,
  solutionName: app.node.tryGetContext('solutionName') || 'user-personalization',
  campaignName: app.node.tryGetContext('campaignName') || 'real-time-recommendations',
  minProvisionedTPS: Number(app.node.tryGetContext('minProvisionedTPS')) || 1,
  enableDetailedMonitoring: app.node.tryGetContext('enableDetailedMonitoring') !== 'false',
  enableXRayTracing: app.node.tryGetContext('enableXRayTracing') !== 'false',
  lambdaMemorySize: Number(app.node.tryGetContext('lambdaMemorySize')) || 256,
  lambdaTimeout: Number(app.node.tryGetContext('lambdaTimeout')) || 30,
  apiStageName: app.node.tryGetContext('apiStageName') || 'prod',
  corsOrigins: app.node.tryGetContext('corsOrigins') || '*',
  enableApiCaching: app.node.tryGetContext('enableApiCaching') !== 'false',
  enableThrottling: app.node.tryGetContext('enableThrottling') !== 'false',
  burstLimit: Number(app.node.tryGetContext('burstLimit')) || 2000,
  rateLimit: Number(app.node.tryGetContext('rateLimit')) || 1000,
};

// Create the recommendation system stack
new RecommendationSystemStack(app, 'RecommendationSystemStack', {
  env: {
    account: config.account,
    region: config.region,
  },
  description: 'Real-time recommendation system using Amazon Personalize and API Gateway',
  config,
});

// Add tags to all resources
cdk.Tags.of(app).add('Project', 'RecommendationSystem');
cdk.Tags.of(app).add('Environment', app.node.tryGetContext('environment') || 'development');
cdk.Tags.of(app).add('Owner', app.node.tryGetContext('owner') || 'aws-recipes');
cdk.Tags.of(app).add('CostCenter', app.node.tryGetContext('costCenter') || 'ml-engineering');
cdk.Tags.of(app).add('Recipe', 'real-time-recommendation-systems-amazon-personalize-api-gateway');

app.synth();