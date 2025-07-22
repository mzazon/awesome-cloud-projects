import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Properties for the MultiRegionVpcConnectivityStack
 */
export interface MultiRegionVpcConnectivityStackProps extends cdk.StackProps {
  /** AWS region for this stack */
  region: string;
  /** Whether this is the primary region */
  isPrimary: boolean;
  /** Project name for resource naming */
  projectName: string;
  /** VPC CIDR blocks configuration */
  vpcCidrs: {
    vpcA: string;
    vpcB: string;
  };
  /** Transit Gateway ASN for BGP routing */
  transitGatewayAsn: number;
}

/**
 * Multi-Region VPC Connectivity Stack
 * 
 * This stack creates the core networking infrastructure for a multi-region
 * Transit Gateway architecture, including:
 * - Multiple VPCs with isolated network segments
 * - Transit Gateway for centralized routing
 * - VPC attachments to Transit Gateway
 * - Custom route tables for traffic control
 * - Security groups for cross-region communication
 * 
 * The stack is designed to be deployed in multiple regions to create
 * a distributed network architecture with centralized management.
 */
export class MultiRegionVpcConnectivityStack extends cdk.Stack {
  /** Transit Gateway ID for cross-stack references */
  public readonly transitGatewayId: string;
  
  /** Route Table ID for peering configuration */
  public readonly routeTableId: string;
  
  /** VPC A for application workloads */
  public readonly vpcA: ec2.Vpc;
  
  /** VPC B for application workloads */
  public readonly vpcB: ec2.Vpc;
  
  /** Security group for cross-region access */
  public readonly crossRegionSecurityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: MultiRegionVpcConnectivityStackProps) {
    super(scope, id, props);

    const regionSuffix = props.isPrimary ? 'primary' : 'secondary';

    // Create VPC A - Primary application network
    this.vpcA = new ec2.Vpc(this, 'VpcA', {
      vpcName: `${props.projectName}-${regionSuffix}-vpc-a`,
      ipAddresses: ec2.IpAddresses.cidr(props.vpcCidrs.vpcA),
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for this architecture
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Transit',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: 'Application',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create VPC B - Secondary application network
    this.vpcB = new ec2.Vpc(this, 'VpcB', {
      vpcName: `${props.projectName}-${regionSuffix}-vpc-b`,
      ipAddresses: ec2.IpAddresses.cidr(props.vpcCidrs.vpcB),
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for this architecture
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Transit',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
        {
          cidrMask: 24,
          name: 'Application',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create Transit Gateway for regional hub connectivity
    const transitGateway = new ec2.CfnTransitGateway(this, 'TransitGateway', {
      description: `${regionSuffix} region Transit Gateway for ${props.projectName}`,
      amazonSideAsn: props.transitGatewayAsn,
      defaultRouteTableAssociation: 'disable', // Use custom route tables
      defaultRouteTablePropagation: 'disable', // Use custom route tables
      dnsSupport: 'enable',
      vpnEcmpSupport: 'enable',
      tags: [
        {
          key: 'Name',
          value: `${props.projectName}-${regionSuffix}-tgw`
        }
      ]
    });

    this.transitGatewayId = transitGateway.attrId;

    // Create custom route table for controlled routing
    const routeTable = new ec2.CfnTransitGatewayRouteTable(this, 'RouteTable', {
      transitGatewayId: transitGateway.attrId,
      tags: [
        {
          key: 'Name',
          value: `${props.projectName}-${regionSuffix}-rt`
        }
      ]
    });

    this.routeTableId = routeTable.attrTransitGatewayRouteTableId;

    // Create VPC attachments to Transit Gateway
    const vpcAAttachment = new ec2.CfnTransitGatewayVpcAttachment(this, 'VpcAAttachment', {
      transitGatewayId: transitGateway.attrId,
      vpcId: this.vpcA.vpcId,
      subnetIds: this.vpcA.selectSubnets({ subnetGroupName: 'Transit' }).subnetIds,
      tags: [
        {
          key: 'Name',
          value: `${props.projectName}-${regionSuffix}-vpc-a-attachment`
        }
      ]
    });

    const vpcBAttachment = new ec2.CfnTransitGatewayVpcAttachment(this, 'VpcBAttachment', {
      transitGatewayId: transitGateway.attrId,
      vpcId: this.vpcB.vpcId,
      subnetIds: this.vpcB.selectSubnets({ subnetGroupName: 'Transit' }).subnetIds,
      tags: [
        {
          key: 'Name',
          value: `${props.projectName}-${regionSuffix}-vpc-b-attachment`
        }
      ]
    });

    // Associate VPC attachments with custom route table
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'VpcARouteTableAssociation', {
      transitGatewayAttachmentId: vpcAAttachment.attrId,
      transitGatewayRouteTableId: routeTable.attrTransitGatewayRouteTableId
    });

    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'VpcBRouteTableAssociation', {
      transitGatewayAttachmentId: vpcBAttachment.attrId,
      transitGatewayRouteTableId: routeTable.attrTransitGatewayRouteTableId
    });

    // Propagate routes from VPC attachments to route table
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'VpcARoutePropagation', {
      transitGatewayAttachmentId: vpcAAttachment.attrId,
      transitGatewayRouteTableId: routeTable.attrTransitGatewayRouteTableId
    });

    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'VpcBRoutePropagation', {
      transitGatewayAttachmentId: vpcBAttachment.attrId,
      transitGatewayRouteTableId: routeTable.attrTransitGatewayRouteTableId
    });

    // Create security group for cross-region communication testing
    this.crossRegionSecurityGroup = new ec2.SecurityGroup(this, 'CrossRegionSecurityGroup', {
      vpc: this.vpcA,
      securityGroupName: `${props.projectName}-${regionSuffix}-cross-region-sg`,
      description: 'Security group for cross-region connectivity testing',
      allowAllOutbound: true
    });

    // Add ICMP ingress rule for connectivity testing
    // In production, replace with specific application protocols and ports
    const remoteCidrs = props.isPrimary 
      ? ['10.3.0.0/16', '10.4.0.0/16'] // Secondary region VPC CIDRs
      : ['10.1.0.0/16', '10.2.0.0/16']; // Primary region VPC CIDRs

    remoteCidrs.forEach((cidr, index) => {
      this.crossRegionSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.allIcmp(),
        `Allow ICMP from remote region VPC ${index + 1}`
      );
    });

    // Add SSH access for testing instances (optional)
    this.crossRegionSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(22),
      'Allow SSH from RFC 1918 private networks'
    );

    // Add HTTP/HTTPS access for web applications (optional)
    this.crossRegionSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(80),
      'Allow HTTP from RFC 1918 private networks'
    );

    this.crossRegionSecurityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(443),
      'Allow HTTPS from RFC 1918 private networks'
    );

    // Create CloudFormation outputs for cross-stack references
    new cdk.CfnOutput(this, 'TransitGatewayId', {
      value: this.transitGatewayId,
      description: `Transit Gateway ID for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-tgw-id`
    });

    new cdk.CfnOutput(this, 'RouteTableId', {
      value: this.routeTableId,
      description: `Route Table ID for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-rt-id`
    });

    new cdk.CfnOutput(this, 'VpcAId', {
      value: this.vpcA.vpcId,
      description: `VPC A ID for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-vpc-a-id`
    });

    new cdk.CfnOutput(this, 'VpcBId', {
      value: this.vpcB.vpcId,
      description: `VPC B ID for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-vpc-b-id`
    });

    new cdk.CfnOutput(this, 'VpcACidr', {
      value: props.vpcCidrs.vpcA,
      description: `VPC A CIDR for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-vpc-a-cidr`
    });

    new cdk.CfnOutput(this, 'VpcBCidr', {
      value: props.vpcCidrs.vpcB,
      description: `VPC B CIDR for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-vpc-b-cidr`
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.crossRegionSecurityGroup.securityGroupId,
      description: `Cross-region security group ID for ${regionSuffix} region`,
      exportName: `${props.projectName}-${regionSuffix}-sg-id`
    });

    // Add resource tags for cost allocation and management
    cdk.Tags.of(this).add('Region', props.region);
    cdk.Tags.of(this).add('RegionType', props.isPrimary ? 'primary' : 'secondary');
    cdk.Tags.of(this).add('Component', 'networking');
  }
}