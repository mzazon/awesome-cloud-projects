#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { MultiRegionVpcConnectivityStack } from './lib/multi-region-vpc-connectivity-stack';
import { TransitGatewayPeeringStack } from './lib/transit-gateway-peering-stack';
import { MonitoringStack } from './lib/monitoring-stack';

/**
 * Multi-Region VPC Connectivity with Transit Gateway CDK Application
 * 
 * This CDK application creates a multi-region network architecture using AWS Transit Gateway
 * with cross-region peering to enable secure communication between VPCs across regions.
 * 
 * Architecture Components:
 * - Multiple VPCs in primary and secondary regions
 * - Transit Gateways in each region
 * - Cross-region peering connections
 * - Custom route tables for traffic control
 * - CloudWatch monitoring and dashboards
 * - Security groups for cross-region access
 */

const app = new cdk.App();

// Configuration for the multi-region deployment
const config = {
  projectName: process.env.PROJECT_NAME || 'multi-region-tgw',
  primaryRegion: process.env.PRIMARY_REGION || 'us-east-1',
  secondaryRegion: process.env.SECONDARY_REGION || 'us-west-2',
  
  // VPC CIDR blocks (ensure non-overlapping ranges)
  cidrs: {
    primaryVpcA: '10.1.0.0/16',
    primaryVpcB: '10.2.0.0/16',
    secondaryVpcA: '10.3.0.0/16',
    secondaryVpcB: '10.4.0.0/16'
  },

  // Transit Gateway ASN values for BGP routing
  asn: {
    primary: 64512,
    secondary: 64513
  }
};

// Environment configuration for cross-region deployment
const primaryEnv = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: config.primaryRegion
};

const secondaryEnv = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: config.secondaryRegion
};

try {
  // Create primary region stack
  const primaryStack = new MultiRegionVpcConnectivityStack(app, 'MultiRegionVpcConnectivity-Primary', {
    env: primaryEnv,
    description: 'Primary region infrastructure for multi-region VPC connectivity with Transit Gateway',
    region: config.primaryRegion,
    isPrimary: true,
    projectName: config.projectName,
    vpcCidrs: {
      vpcA: config.cidrs.primaryVpcA,
      vpcB: config.cidrs.primaryVpcB
    },
    transitGatewayAsn: config.asn.primary,
    tags: {
      Project: config.projectName,
      Environment: 'multi-region',
      Region: config.primaryRegion,
      Component: 'primary-infrastructure'
    }
  });

  // Create secondary region stack
  const secondaryStack = new MultiRegionVpcConnectivityStack(app, 'MultiRegionVpcConnectivity-Secondary', {
    env: secondaryEnv,
    description: 'Secondary region infrastructure for multi-region VPC connectivity with Transit Gateway',
    region: config.secondaryRegion,
    isPrimary: false,
    projectName: config.projectName,
    vpcCidrs: {
      vpcA: config.cidrs.secondaryVpcA,
      vpcB: config.cidrs.secondaryVpcB
    },
    transitGatewayAsn: config.asn.secondary,
    tags: {
      Project: config.projectName,
      Environment: 'multi-region',
      Region: config.secondaryRegion,
      Component: 'secondary-infrastructure'
    }
  });

  // Create cross-region peering stack (deployed in primary region)
  const peeringStack = new TransitGatewayPeeringStack(app, 'TransitGatewayPeering', {
    env: primaryEnv,
    description: 'Cross-region Transit Gateway peering and routing configuration',
    projectName: config.projectName,
    primaryTransitGatewayId: primaryStack.transitGatewayId,
    secondaryTransitGatewayId: secondaryStack.transitGatewayId,
    primaryRouteTableId: primaryStack.routeTableId,
    secondaryRouteTableId: secondaryStack.routeTableId,
    primaryRegion: config.primaryRegion,
    secondaryRegion: config.secondaryRegion,
    remoteCidrs: {
      primary: [config.cidrs.primaryVpcA, config.cidrs.primaryVpcB],
      secondary: [config.cidrs.secondaryVpcA, config.cidrs.secondaryVpcB]
    },
    tags: {
      Project: config.projectName,
      Environment: 'multi-region',
      Component: 'cross-region-peering'
    }
  });

  // Create monitoring stack for both regions
  const monitoringStack = new MonitoringStack(app, 'MultiRegionMonitoring', {
    env: primaryEnv,
    description: 'CloudWatch monitoring and dashboards for multi-region Transit Gateway',
    projectName: config.projectName,
    primaryTransitGatewayId: primaryStack.transitGatewayId,
    secondaryTransitGatewayId: secondaryStack.transitGatewayId,
    primaryRegion: config.primaryRegion,
    secondaryRegion: config.secondaryRegion,
    tags: {
      Project: config.projectName,
      Environment: 'multi-region',
      Component: 'monitoring'
    }
  });

  // Define stack dependencies to ensure proper deployment order
  peeringStack.addDependency(primaryStack);
  peeringStack.addDependency(secondaryStack);
  monitoringStack.addDependency(primaryStack);
  monitoringStack.addDependency(secondaryStack);

  // Add stack-level tags for resource management
  cdk.Tags.of(app).add('Project', config.projectName);
  cdk.Tags.of(app).add('ManagedBy', 'CDK');
  cdk.Tags.of(app).add('Architecture', 'multi-region-transit-gateway');

  console.log('✅ CDK Application initialized successfully');
  console.log(`Primary Region: ${config.primaryRegion}`);
  console.log(`Secondary Region: ${config.secondaryRegion}`);
  console.log(`Project Name: ${config.projectName}`);

} catch (error) {
  console.error('❌ Error initializing CDK application:', error);
  process.exit(1);
}