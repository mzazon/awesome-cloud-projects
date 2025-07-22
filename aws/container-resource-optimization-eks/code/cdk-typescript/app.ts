#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ContainerResourceOptimizationStack } from './lib/container-resource-optimization-stack';

const app = new cdk.App();

// Get environment variables for stack configuration
const account = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID;
const region = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';

// Create the main stack
new ContainerResourceOptimizationStack(app, 'ContainerResourceOptimizationStack', {
  env: { account, region },
  description: 'Infrastructure for container resource optimization and right-sizing with Amazon EKS',
  
  // Stack configuration options
  stackName: 'container-resource-optimization',
  
  // Resource naming prefix
  resourcePrefix: 'cost-opt',
  
  // EKS cluster configuration
  clusterConfig: {
    version: cdk.aws_eks.KubernetesVersion.V1_28,
    capacity: {
      instanceTypes: [cdk.aws_ec2.InstanceType.of(cdk.aws_ec2.InstanceClass.M5, cdk.aws_ec2.InstanceSize.LARGE)],
      minCapacity: 2,
      maxCapacity: 10,
      desiredCapacity: 3
    },
    enableClusterLogging: true,
    enableFargateProfile: true
  },
  
  // Monitoring configuration
  monitoringConfig: {
    enableContainerInsights: true,
    createCostDashboard: true,
    enableCostAlerts: true,
    lowUtilizationThreshold: 30
  },
  
  // VPA configuration
  vpaConfig: {
    enableMetricsServer: true,
    enableVPA: true,
    updateMode: 'Off', // Start with recommendations only
    enableAutomation: false // Enable after testing
  }
});

// Apply common tags to all resources
cdk.Tags.of(app).add('Project', 'ContainerResourceOptimization');
cdk.Tags.of(app).add('Environment', 'production');
cdk.Tags.of(app).add('CostCenter', 'engineering');
cdk.Tags.of(app).add('Owner', 'platform-team');
cdk.Tags.of(app).add('Purpose', 'cost-optimization');