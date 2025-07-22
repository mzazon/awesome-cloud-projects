#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Interface for common stack properties
 */
interface MultiClusterStackProps extends cdk.StackProps {
  readonly clusterName: string;
  readonly region: string;
  readonly vpcCidr: string;
  readonly transitGatewayAsn: number;
  readonly isPrimary?: boolean;
}

/**
 * Cross-region networking stack for Transit Gateway peering
 */
class CrossRegionNetworkingStack extends cdk.Stack {
  public readonly primaryTransitGatewayId: string;
  public readonly secondaryTransitGatewayId: string;
  public readonly serviceNetworkId: string;

  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    primaryTgwId: string;
    secondaryTgwId: string;
    primaryRegion: string;
    secondaryRegion: string;
  }) {
    super(scope, id, props);

    this.primaryTransitGatewayId = props.primaryTgwId;
    this.secondaryTransitGatewayId = props.secondaryTgwId;

    // Create Transit Gateway peering attachment
    const tgwPeering = new ec2.CfnTransitGatewayPeeringAttachment(this, 'TGWPeering', {
      transitGatewayId: this.primaryTransitGatewayId,
      peerTransitGatewayId: this.secondaryTransitGatewayId,
      peerRegion: props.secondaryRegion,
      tags: [
        {
          key: 'Name',
          value: 'multi-cluster-tgw-peering'
        }
      ]
    });

    // Create VPC Lattice Service Network for cross-cluster service discovery
    const serviceNetwork = new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `multi-cluster-service-network-${cdk.Aws.ACCOUNT_ID}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'Name',
          value: `multi-cluster-service-network-${cdk.Aws.ACCOUNT_ID}`
        }
      ]
    });

    this.serviceNetworkId = serviceNetwork.attrId;

    // Output important values for cross-stack references
    new cdk.CfnOutput(this, 'TGWPeeringAttachmentId', {
      value: tgwPeering.ref,
      description: 'Transit Gateway Peering Attachment ID',
      exportName: 'TGWPeeringAttachmentId'
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      value: this.serviceNetworkId,
      description: 'VPC Lattice Service Network ID',
      exportName: 'ServiceNetworkId'
    });
  }
}

/**
 * Multi-cluster EKS stack with cross-region networking capabilities
 */
class MultiClusterEKSStack extends cdk.Stack {
  public readonly cluster: eks.Cluster;
  public readonly vpc: ec2.Vpc;
  public readonly transitGateway: ec2.CfnTransitGateway;

  constructor(scope: Construct, id: string, props: MultiClusterStackProps) {
    super(scope, id, props);

    // Create VPC with multiple AZs for high availability
    this.vpc = new ec2.Vpc(this, 'VPC', {
      cidr: props.vpcCidr,
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        }
      ],
      natGateways: 2, // One NAT Gateway per AZ for high availability
    });

    // Tag VPC and subnets for proper EKS integration
    cdk.Tags.of(this.vpc).add('Name', `${props.clusterName}-vpc`);
    
    // Tag private subnets for EKS
    this.vpc.privateSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/internal-elb', '1');
      cdk.Tags.of(subnet).add('kubernetes.io/cluster/' + props.clusterName, 'owned');
    });

    // Tag public subnets for EKS
    this.vpc.publicSubnets.forEach((subnet, index) => {
      cdk.Tags.of(subnet).add('kubernetes.io/role/elb', '1');
      cdk.Tags.of(subnet).add('kubernetes.io/cluster/' + props.clusterName, 'owned');
    });

    // Create Transit Gateway for cross-region connectivity
    this.transitGateway = new ec2.CfnTransitGateway(this, 'TransitGateway', {
      amazonSideAsn: props.transitGatewayAsn,
      autoAcceptSharedAttachments: 'enable',
      defaultRouteTableAssociation: 'enable',
      defaultRouteTablePropagation: 'enable',
      description: `${props.region} region Transit Gateway`,
      tags: [
        {
          key: 'Name',
          value: `${props.clusterName}-tgw`
        }
      ]
    });

    // Create Transit Gateway VPC attachment
    const tgwVpcAttachment = new ec2.CfnTransitGatewayVpcAttachment(this, 'TGWVpcAttachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: this.vpc.vpcId,
      subnetIds: this.vpc.privateSubnets.map(subnet => subnet.subnetId),
      tags: [
        {
          key: 'Name',
          value: `${props.clusterName}-tgw-attachment`
        }
      ]
    });

    // Create IAM role for EKS cluster
    const clusterRole = new iam.Role(this, 'ClusterRole', {
      assumedBy: new iam.ServicePrincipal('eks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSClusterPolicy'),
      ],
      roleName: `${props.clusterName}-cluster-role`,
    });

    // Create IAM role for EKS node groups
    const nodeGroupRole = new iam.Role(this, 'NodeGroupRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
      ],
      roleName: `${props.clusterName}-nodegroup-role`,
    });

    // Create CloudWatch log group for EKS cluster logs
    const clusterLogGroup = new logs.LogGroup(this, 'ClusterLogGroup', {
      logGroupName: `/aws/eks/${props.clusterName}/cluster`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create EKS cluster with comprehensive logging
    this.cluster = new eks.Cluster(this, 'EKSCluster', {
      clusterName: props.clusterName,
      version: eks.KubernetesVersion.V1_28,
      vpc: this.vpc,
      vpcSubnets: [
        {
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        }
      ],
      role: clusterRole,
      endpointAccess: eks.EndpointAccess.PUBLIC_AND_PRIVATE,
      clusterLogging: [
        eks.ClusterLoggingTypes.API,
        eks.ClusterLoggingTypes.AUDIT,
        eks.ClusterLoggingTypes.AUTHENTICATOR,
        eks.ClusterLoggingTypes.CONTROLLER_MANAGER,
        eks.ClusterLoggingTypes.SCHEDULER,
      ],
      outputClusterName: true,
      outputConfigCommand: true,
    });

    // Create managed node group with optimized configuration
    const nodeGroup = this.cluster.addNodegroupCapacity('DefaultNodeGroup', {
      nodeGroupName: `${props.clusterName}-nodes`,
      instanceTypes: [new ec2.InstanceType('m5.large')],
      minSize: 2,
      maxSize: 6,
      desiredSize: 3,
      subnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      nodeRole: nodeGroupRole,
      capacityType: eks.CapacityType.ON_DEMAND,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      diskSize: 100,
      tags: {
        'Name': `${props.clusterName}-node`,
        'Environment': 'production',
        'ManagedBy': 'CDK'
      }
    });

    // Install VPC Lattice Gateway API Controller
    const vpcLatticeController = this.cluster.addHelmChart('VPCLatticeController', {
      chart: 'gateway-api-controller',
      repository: 'https://aws.github.io/aws-application-networking-k8s',
      namespace: 'aws-application-networking-system',
      createNamespace: true,
      values: {
        image: {
          repository: 'public.ecr.aws/aws-application-networking-k8s/aws-gateway-controller',
          tag: 'v1.0.0'
        },
        serviceAccount: {
          create: true,
          name: 'gateway-api-controller'
        },
        clusterName: props.clusterName,
        region: props.region,
      },
    });

    // Install AWS Load Balancer Controller for ALB integration
    const albController = this.cluster.addHelmChart('AWSLoadBalancerController', {
      chart: 'aws-load-balancer-controller',
      repository: 'https://aws.github.io/eks-charts',
      namespace: 'kube-system',
      values: {
        clusterName: props.clusterName,
        serviceAccount: {
          create: true,
          name: 'aws-load-balancer-controller',
        },
        region: props.region,
        vpcId: this.vpc.vpcId,
      },
    });

    // Create service account for VPC Lattice with appropriate IAM permissions
    const vpcLatticeServiceAccount = this.cluster.addServiceAccount('VPCLatticeServiceAccount', {
      name: 'vpc-lattice-service-account',
      namespace: 'aws-application-networking-system',
    });

    // Add VPC Lattice permissions to service account
    vpcLatticeServiceAccount.addToPrincipalPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'vpc-lattice:*',
        'iam:CreateServiceLinkedRole',
        'ec2:DescribeVpcs',
        'ec2:DescribeSubnets',
        'ec2:DescribeSecurityGroups',
        'logs:CreateLogDelivery',
        'logs:GetLogDelivery',
        'logs:UpdateLogDelivery',
        'logs:DeleteLogDelivery',
        'logs:ListLogDeliveries',
      ],
      resources: ['*'],
    }));

    // Add ALB controller permissions
    const albServiceAccount = this.cluster.addServiceAccount('ALBServiceAccount', {
      name: 'aws-load-balancer-controller',
      namespace: 'kube-system',
    });

    albServiceAccount.addToPrincipalPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'iam:CreateServiceLinkedRole',
        'ec2:DescribeAccountAttributes',
        'ec2:DescribeAddresses',
        'ec2:DescribeAvailabilityZones',
        'ec2:DescribeInternetGateways',
        'ec2:DescribeVpcs',
        'ec2:DescribeVpcPeeringConnections',
        'ec2:DescribeSubnets',
        'ec2:DescribeSecurityGroups',
        'ec2:DescribeInstances',
        'ec2:DescribeNetworkInterfaces',
        'ec2:DescribeTags',
        'ec2:GetCoipPoolUsage',
        'ec2:GetManagedPrefixListEntries',
        'ec2:DescribeCoipPools',
        'elasticloadbalancing:*',
        'acm:ListCertificates',
        'acm:DescribeCertificate',
        'iam:ListServerCertificates',
        'iam:GetServerCertificate',
        'waf-regional:*',
        'wafv2:*',
        'shield:*',
        'cognito-idp:DescribeUserPoolClient',
      ],
      resources: ['*'],
    }));

    // Outputs for cross-stack references and verification
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'EKS Cluster Name',
      exportName: `${props.clusterName}-ClusterName`
    });

    new cdk.CfnOutput(this, 'ClusterEndpoint', {
      value: this.cluster.clusterEndpoint,
      description: 'EKS Cluster Endpoint',
      exportName: `${props.clusterName}-ClusterEndpoint`
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      description: 'EKS Cluster ARN',
      exportName: `${props.clusterName}-ClusterArn`
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${props.clusterName}-VpcId`
    });

    new cdk.CfnOutput(this, 'TransitGatewayId', {
      value: this.transitGateway.ref,
      description: 'Transit Gateway ID',
      exportName: `${props.clusterName}-TransitGatewayId`
    });

    new cdk.CfnOutput(this, 'KubectlConfigCommand', {
      value: `aws eks update-kubeconfig --name ${this.cluster.clusterName} --region ${props.region} --alias ${props.clusterName}`,
      description: 'kubectl configuration command',
    });

    // Output security group ID for potential custom rules
    new cdk.CfnOutput(this, 'ClusterSecurityGroupId', {
      value: this.cluster.clusterSecurityGroupId,
      description: 'EKS Cluster Security Group ID',
      exportName: `${props.clusterName}-ClusterSecurityGroupId`
    });
  }
}

/**
 * Route 53 Global DNS stack for health checks and failover
 */
class GlobalDNSStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    primaryRegion: string;
    secondaryRegion: string;
    domainName: string;
  }) {
    super(scope, id, props);

    // Create Route 53 hosted zone (optional - may already exist)
    const hostedZone = new route53.PublicHostedZone(this, 'HostedZone', {
      zoneName: props.domainName,
      comment: 'Multi-cluster EKS global DNS zone'
    });

    // Health checks will be created after VPC Lattice endpoints are available
    // This is a placeholder for demonstration - in practice, you would
    // create health checks pointing to your VPC Lattice service endpoints

    // Output hosted zone details
    new cdk.CfnOutput(this, 'HostedZoneId', {
      value: hostedZone.hostedZoneId,
      description: 'Route 53 Hosted Zone ID',
      exportName: 'GlobalDNSHostedZoneId'
    });

    new cdk.CfnOutput(this, 'NameServers', {
      value: cdk.Fn.join(',', hostedZone.hostedZoneNameServers || []),
      description: 'Route 53 Name Servers',
    });
  }
}

/**
 * Main CDK application
 */
const app = new cdk.App();

// Configuration - these can be customized via CDK context or environment variables
const config = {
  primaryRegion: app.node.tryGetContext('primaryRegion') || 'us-east-1',
  secondaryRegion: app.node.tryGetContext('secondaryRegion') || 'us-west-2',
  account: app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT,
  domainName: app.node.tryGetContext('domainName') || 'multi-cluster-demo.com',
  primaryClusterName: app.node.tryGetContext('primaryClusterName') || `eks-primary-${Date.now().toString(36)}`,
  secondaryClusterName: app.node.tryGetContext('secondaryClusterName') || `eks-secondary-${Date.now().toString(36)}`
};

// Validate account ID is available
if (!config.account) {
  throw new Error('Account ID is required. Set CDK_DEFAULT_ACCOUNT environment variable or use cdk deploy with --profile');
}

// Create primary region stack
const primaryStack = new MultiClusterEKSStack(app, 'PrimaryEKSStack', {
  env: {
    account: config.account,
    region: config.primaryRegion,
  },
  clusterName: config.primaryClusterName,
  region: config.primaryRegion,
  vpcCidr: '10.1.0.0/16',
  transitGatewayAsn: 64512,
  isPrimary: true,
  description: 'Multi-cluster EKS primary region stack with Transit Gateway and VPC Lattice',
});

// Create secondary region stack
const secondaryStack = new MultiClusterEKSStack(app, 'SecondaryEKSStack', {
  env: {
    account: config.account,
    region: config.secondaryRegion,
  },
  clusterName: config.secondaryClusterName,
  region: config.secondaryRegion,
  vpcCidr: '10.2.0.0/16',
  transitGatewayAsn: 64513,
  isPrimary: false,
  description: 'Multi-cluster EKS secondary region stack with Transit Gateway and VPC Lattice',
});

// Create cross-region networking stack (deployed in primary region)
const crossRegionStack = new CrossRegionNetworkingStack(app, 'CrossRegionNetworkingStack', {
  env: {
    account: config.account,
    region: config.primaryRegion,
  },
  primaryTgwId: primaryStack.transitGateway.ref,
  secondaryTgwId: secondaryStack.transitGateway.ref,
  primaryRegion: config.primaryRegion,
  secondaryRegion: config.secondaryRegion,
  description: 'Cross-region networking stack for Transit Gateway peering and VPC Lattice service network',
});

// Create global DNS stack (deployed in primary region)
const globalDnsStack = new GlobalDNSStack(app, 'GlobalDNSStack', {
  env: {
    account: config.account,
    region: config.primaryRegion,
  },
  primaryRegion: config.primaryRegion,
  secondaryRegion: config.secondaryRegion,
  domainName: config.domainName,
  description: 'Global DNS stack for Route 53 health checks and failover routing',
});

// Add dependencies to ensure proper deployment order
crossRegionStack.addDependency(primaryStack);
crossRegionStack.addDependency(secondaryStack);
globalDnsStack.addDependency(crossRegionStack);

// Add stack tags for better resource management
const commonTags = {
  Project: 'MultiClusterEKS',
  Environment: 'Production',
  ManagedBy: 'CDK',
  Recipe: 'multi-cluster-eks-deployments-cross-region-networking'
};

Object.entries(commonTags).forEach(([key, value]) => {
  cdk.Tags.of(primaryStack).add(key, value);
  cdk.Tags.of(secondaryStack).add(key, value);
  cdk.Tags.of(crossRegionStack).add(key, value);
  cdk.Tags.of(globalDnsStack).add(key, value);
});

app.synth();