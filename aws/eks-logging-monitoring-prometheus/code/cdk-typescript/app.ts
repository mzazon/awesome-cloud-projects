#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EksObservabilityStack } from './lib/eks-observability-stack';

const app = new cdk.App();

// Get configuration from context or environment
const account = process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account');
const region = process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1';

// Create the EKS observability stack
new EksObservabilityStack(app, 'EksObservabilityStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'EKS Cluster with comprehensive logging and monitoring using CloudWatch and Prometheus',
  
  // Stack configuration
  clusterName: app.node.tryGetContext('clusterName') || 'eks-observability-cluster',
  prometheusWorkspaceName: app.node.tryGetContext('prometheusWorkspaceName') || 'eks-prometheus-workspace',
  
  // Enable all control plane logging
  enableControlPlaneLogging: true,
  
  // Container Insights configuration
  enableContainerInsights: true,
  
  // Node group configuration
  nodeGroupConfig: {
    instanceTypes: ['t3.medium'],
    minSize: 2,
    maxSize: 4,
    desiredSize: 2,
  },
  
  // Tags for all resources
  tags: {
    Project: 'EKS-Observability',
    Environment: app.node.tryGetContext('environment') || 'dev',
    ManagedBy: 'CDK',
  },
});

app.synth();