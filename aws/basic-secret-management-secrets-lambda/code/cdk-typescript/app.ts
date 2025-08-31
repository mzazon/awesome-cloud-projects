#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SecretsManagerLambdaStack } from './lib/secrets-manager-lambda-stack';

const app = new cdk.App();

new SecretsManagerLambdaStack(app, 'SecretsManagerLambdaStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Basic Secret Management with Secrets Manager and Lambda - CDK TypeScript Implementation',
});

// Add tags to the entire application
cdk.Tags.of(app).add('Project', 'BasicSecretManagement');
cdk.Tags.of(app).add('RecipeId', 'a1b2c3d4');
cdk.Tags.of(app).add('CreatedBy', 'CDK-TypeScript');