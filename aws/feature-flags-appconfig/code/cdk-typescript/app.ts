#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { FeatureFlagsAppConfigStack } from './lib/feature-flags-appconfig-stack';
import { AwsSolutionsChecks } from 'cdk-nag';
import { Aspects } from 'aws-cdk-lib';

/**
 * AWS CDK application for Feature Flags with AWS AppConfig
 * 
 * This application demonstrates how to:
 * - Create AWS AppConfig applications, environments, and configuration profiles
 * - Deploy feature flags with gradual rollout strategies
 * - Integrate Lambda functions with AppConfig using the AppConfig extension
 * - Implement monitoring with CloudWatch alarms for automatic rollback
 * - Apply security best practices with CDK Nag
 */
const app = new cdk.App();

// Create the main stack
const stack = new FeatureFlagsAppConfigStack(app, 'FeatureFlagsAppConfigStack', {
  /* 
   * Environment configuration - customize as needed
   * If you need to deploy to a specific account/region, configure here:
   * env: { 
   *   account: process.env.CDK_DEFAULT_ACCOUNT, 
   *   region: process.env.CDK_DEFAULT_REGION 
   * },
   */
  description: 'Feature flags implementation with AWS AppConfig, Lambda, and CloudWatch monitoring',
  
  // Stack-level tags for resource management and cost allocation
  tags: {
    'Project': 'FeatureFlagsDemo',
    'Environment': 'Development', // Change to Production, Staging as needed
    'Purpose': 'DemoApplication',
    'Owner': 'CDKTeam'
  }
});

// Apply AWS security best practices using CDK Nag
// This ensures the infrastructure follows AWS Well-Architected principles
Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Add stack-level tags that will be inherited by all resources
cdk.Tags.of(stack).add('StackName', 'FeatureFlagsAppConfigStack');
cdk.Tags.of(stack).add('CreatedBy', 'CDK');

app.synth();