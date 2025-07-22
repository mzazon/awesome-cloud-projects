#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { KubernetesOperatorsStack } from './lib/kubernetes-operators-stack';

/**
 * CDK Application for Kubernetes Operators with AWS Resources
 * 
 * This application deploys infrastructure for creating Kubernetes operators
 * that manage AWS resources using AWS Controllers for Kubernetes (ACK).
 * 
 * The stack includes:
 * - EKS cluster with OIDC provider
 * - IAM roles for ACK controllers  
 * - S3 bucket for application storage
 * - Lambda function for serverless processing
 * - VPC with proper networking setup
 */

const app = new cdk.App();

// Get configuration from context or environment variables
const config = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
    region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1'
  },
  clusterName: app.node.tryGetContext('clusterName') || 'ack-operators-cluster',
  resourceSuffix: app.node.tryGetContext('resourceSuffix') || 'ack-demo',
  enableLogging: app.node.tryGetContext('enableLogging') !== 'false',
  nodeGroupInstanceTypes: app.node.tryGetContext('nodeGroupInstanceTypes') || ['t3.medium'],
  nodeGroupDesiredSize: Number(app.node.tryGetContext('nodeGroupDesiredSize')) || 2,
  nodeGroupMinSize: Number(app.node.tryGetContext('nodeGroupMinSize')) || 1,
  nodeGroupMaxSize: Number(app.node.tryGetContext('nodeGroupMaxSize')) || 4
};

// Create the main stack
const kubernetesOperatorsStack = new KubernetesOperatorsStack(app, 'KubernetesOperatorsStack', {
  env: config.env,
  description: 'Infrastructure for Kubernetes Operators managing AWS Resources with ACK',
  
  // Stack configuration
  clusterName: config.clusterName,
  resourceSuffix: config.resourceSuffix,
  enableLogging: config.enableLogging,
  nodeGroupInstanceTypes: config.nodeGroupInstanceTypes,
  nodeGroupDesiredSize: config.nodeGroupDesiredSize,
  nodeGroupMinSize: config.nodeGroupMinSize,
  nodeGroupMaxSize: config.nodeGroupMaxSize,
  
  // Add stack tags for resource management
  tags: {
    Project: 'KubernetesOperators',
    Environment: app.node.tryGetContext('environment') || 'development',
    Owner: app.node.tryGetContext('owner') || 'platform-team',
    CostCenter: app.node.tryGetContext('costCenter') || 'engineering',
    Recipe: 'kubernetes-operators-aws-resources'
  }
});

// Add additional tags to the app
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Repository', 'aws-recipes');