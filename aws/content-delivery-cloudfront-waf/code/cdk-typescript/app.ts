#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { SecureContentDeliveryStack } from './lib/secure-content-delivery-stack';

const app = new cdk.App();

// Get configuration from context or use defaults
const config = {
  bucketName: app.node.tryGetContext('bucketName') || `secure-content-${Math.random().toString(36).substring(2, 8)}`,
  allowedCountries: app.node.tryGetContext('allowedCountries') || [],
  blockedCountries: app.node.tryGetContext('blockedCountries') || ['RU', 'CN'],
  rateLimitPerIp: app.node.tryGetContext('rateLimitPerIp') || 2000,
  environment: app.node.tryGetContext('environment') || 'dev'
};

new SecureContentDeliveryStack(app, 'SecureContentDeliveryStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Secure content delivery with CloudFront and AWS WAF protection',
  config,
  tags: {
    Project: 'SecureContentDelivery',
    Environment: config.environment,
    ManagedBy: 'CDK'
  }
});