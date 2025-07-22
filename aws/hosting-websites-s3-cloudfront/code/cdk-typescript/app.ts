#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { StaticWebsiteStack } from './lib/static-website-stack';

const app = new cdk.App();

// Get configuration from context or environment variables
const domainName = app.node.tryGetContext('domainName') || process.env.DOMAIN_NAME;
const hostedZoneId = app.node.tryGetContext('hostedZoneId') || process.env.HOSTED_ZONE_ID;
const certificateArn = app.node.tryGetContext('certificateArn') || process.env.CERTIFICATE_ARN;

if (!domainName) {
  throw new Error('Domain name is required. Set DOMAIN_NAME environment variable or pass domainName in context');
}

new StaticWebsiteStack(app, 'StaticWebsiteStack', {
  domainName,
  hostedZoneId,
  certificateArn,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();