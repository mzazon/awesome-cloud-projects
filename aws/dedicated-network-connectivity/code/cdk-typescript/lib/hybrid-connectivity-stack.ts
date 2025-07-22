import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as dx from 'aws-cdk-lib/aws-directconnect';
import * as route53resolver from 'aws-cdk-lib/aws-route53resolver';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

export interface HybridConnectivityStackProps extends cdk.StackProps {
  onPremisesCidr: string;
  onPremisesAsn: number;
  awsAsn: number;
  privateVifVlan: number;
  transitVifVlan: number;
  projectId: string;
  enableDnsResolution: boolean;
  enableMonitoring: boolean;
  enableFlowLogs: boolean;
}

export class HybridConnectivityStack extends cdk.Stack {
  public readonly transitGateway: ec2.CfnTransitGateway;
  public readonly directConnectGateway: dx.CfnDirectConnectGateway;
  public readonly productionVpc: ec2.Vpc;
  public readonly developmentVpc: ec2.Vpc;
  public readonly sharedServicesVpc: ec2.Vpc;

  constructor(scope: Construct, id: string, props: HybridConnectivityStackProps) {
    super(scope, id, props);

    // Create VPC infrastructure
    this.createVpcInfrastructure(props);

    // Create Transit Gateway
    this.createTransitGateway(props);

    // Create Direct Connect Gateway
    this.createDirectConnectGateway(props);

    // Attach VPCs to Transit Gateway
    this.attachVpcsToTransitGateway(props);

    // Associate Direct Connect Gateway with Transit Gateway
    this.associateDirectConnectGatewayWithTransitGateway(props);

    // Configure DNS resolution if enabled
    if (props.enableDnsResolution) {
      this.configureDnsResolution(props);
    }

    // Configure monitoring if enabled
    if (props.enableMonitoring) {
      this.configureMonitoring(props);
    }

    // Configure VPC Flow Logs if enabled
    if (props.enableFlowLogs) {
      this.configureFlowLogs(props);
    }

    // Create outputs
    this.createOutputs(props);
  }

  private createVpcInfrastructure(props: HybridConnectivityStackProps): void {
    // Production VPC
    this.productionVpc = new ec2.Vpc(this, 'ProductionVpc', {
      cidr: '10.1.0.0/16',
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 28,
          name: 'tgw',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Development VPC
    this.developmentVpc = new ec2.Vpc(this, 'DevelopmentVpc', {
      cidr: '10.2.0.0/16',
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 28,
          name: 'tgw',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Shared Services VPC
    this.sharedServicesVpc = new ec2.Vpc(this, 'SharedServicesVpc', {
      cidr: '10.3.0.0/16',
      maxAzs: 3,
      natGateways: 1,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
        {
          cidrMask: 28,
          name: 'tgw',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Add tags to VPCs
    cdk.Tags.of(this.productionVpc).add('Name', `Production-VPC-${props.projectId}`);
    cdk.Tags.of(this.productionVpc).add('Environment', 'Production');
    cdk.Tags.of(this.developmentVpc).add('Name', `Development-VPC-${props.projectId}`);
    cdk.Tags.of(this.developmentVpc).add('Environment', 'Development');
    cdk.Tags.of(this.sharedServicesVpc).add('Name', `Shared-Services-VPC-${props.projectId}`);
    cdk.Tags.of(this.sharedServicesVpc).add('Environment', 'Shared');
  }

  private createTransitGateway(props: HybridConnectivityStackProps): void {
    this.transitGateway = new ec2.CfnTransitGateway(this, 'TransitGateway', {
      amazonSideAsn: props.awsAsn,
      description: 'Corporate hybrid connectivity gateway',
      defaultRouteTableAssociation: 'enable',
      defaultRouteTablePropagation: 'enable',
      dnsSupport: 'enable',
      vpnEcmpSupport: 'enable',
      tags: [
        {
          key: 'Name',
          value: `corporate-tgw-${props.projectId}`,
        },
      ],
    });
  }

  private createDirectConnectGateway(props: HybridConnectivityStackProps): void {
    this.directConnectGateway = new dx.CfnDirectConnectGateway(this, 'DirectConnectGateway', {
      name: `corporate-dx-gateway-${props.projectId}`,
      amazonSideAsn: props.awsAsn,
    });
  }

  private attachVpcsToTransitGateway(props: HybridConnectivityStackProps): void {
    // Production VPC attachment
    new ec2.CfnTransitGatewayVpcAttachment(this, 'ProductionVpcAttachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: this.productionVpc.vpcId,
      subnetIds: this.productionVpc.isolatedSubnets.map(subnet => subnet.subnetId),
      tags: [
        {
          key: 'Name',
          value: 'Prod-TGW-Attachment',
        },
      ],
    });

    // Development VPC attachment
    new ec2.CfnTransitGatewayVpcAttachment(this, 'DevelopmentVpcAttachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: this.developmentVpc.vpcId,
      subnetIds: this.developmentVpc.isolatedSubnets.map(subnet => subnet.subnetId),
      tags: [
        {
          key: 'Name',
          value: 'Dev-TGW-Attachment',
        },
      ],
    });

    // Shared Services VPC attachment
    new ec2.CfnTransitGatewayVpcAttachment(this, 'SharedServicesVpcAttachment', {
      transitGatewayId: this.transitGateway.ref,
      vpcId: this.sharedServicesVpc.vpcId,
      subnetIds: this.sharedServicesVpc.isolatedSubnets.map(subnet => subnet.subnetId),
      tags: [
        {
          key: 'Name',
          value: 'Shared-TGW-Attachment',
        },
      ],
    });

    // Update route tables in each VPC to route on-premises traffic through Transit Gateway
    this.updateVpcRouteTables(props);
  }

  private updateVpcRouteTables(props: HybridConnectivityStackProps): void {
    const vpcs = [this.productionVpc, this.developmentVpc, this.sharedServicesVpc];
    
    vpcs.forEach((vpc, index) => {
      // Add route for on-premises traffic to private subnets
      vpc.privateSubnets.forEach((subnet, subnetIndex) => {
        new ec2.CfnRoute(this, `OnPremRoute-${index}-${subnetIndex}`, {
          routeTableId: subnet.routeTable.routeTableId,
          destinationCidrBlock: props.onPremisesCidr,
          transitGatewayId: this.transitGateway.ref,
        });
      });

      // Add route for on-premises traffic to isolated subnets
      vpc.isolatedSubnets.forEach((subnet, subnetIndex) => {
        new ec2.CfnRoute(this, `OnPremRouteIsolated-${index}-${subnetIndex}`, {
          routeTableId: subnet.routeTable.routeTableId,
          destinationCidrBlock: props.onPremisesCidr,
          transitGatewayId: this.transitGateway.ref,
        });
      });
    });
  }

  private associateDirectConnectGatewayWithTransitGateway(props: HybridConnectivityStackProps): void {
    new ec2.CfnTransitGatewayDirectConnectGatewayAttachment(this, 'DxGatewayAttachment', {
      transitGatewayId: this.transitGateway.ref,
      directConnectGatewayId: this.directConnectGateway.ref,
      tags: [
        {
          key: 'Name',
          value: `DX-TGW-Attachment-${props.projectId}`,
        },
      ],
    });
  }

  private configureDnsResolution(props: HybridConnectivityStackProps): void {
    // Create security group for resolver endpoints
    const resolverSecurityGroup = new ec2.SecurityGroup(this, 'ResolverSecurityGroup', {
      vpc: this.sharedServicesVpc,
      description: 'Security group for Route 53 Resolver endpoints',
      securityGroupName: `resolver-endpoints-sg-${props.projectId}`,
    });

    // Allow DNS traffic from on-premises
    resolverSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(props.onPremisesCidr),
      ec2.Port.udp(53),
      'Allow DNS UDP from on-premises'
    );

    resolverSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(props.onPremisesCidr),
      ec2.Port.tcp(53),
      'Allow DNS TCP from on-premises'
    );

    // Allow DNS traffic between VPCs
    const vpcCidrs = ['10.1.0.0/16', '10.2.0.0/16', '10.3.0.0/16'];
    vpcCidrs.forEach(cidr => {
      resolverSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.udp(53),
        `Allow DNS UDP from ${cidr}`
      );
      resolverSecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(53),
        `Allow DNS TCP from ${cidr}`
      );
    });

    // Create inbound resolver endpoint
    new route53resolver.CfnResolverEndpoint(this, 'InboundResolverEndpoint', {
      direction: 'INBOUND',
      ipAddresses: [
        {
          subnetId: this.sharedServicesVpc.isolatedSubnets[0].subnetId,
          ip: '10.3.1.100',
        },
      ],
      securityGroupIds: [resolverSecurityGroup.securityGroupId],
      name: `Inbound-Resolver-${props.projectId}`,
    });

    // Create outbound resolver endpoint
    new route53resolver.CfnResolverEndpoint(this, 'OutboundResolverEndpoint', {
      direction: 'OUTBOUND',
      ipAddresses: [
        {
          subnetId: this.sharedServicesVpc.isolatedSubnets[0].subnetId,
          ip: '10.3.1.101',
        },
      ],
      securityGroupIds: [resolverSecurityGroup.securityGroupId],
      name: `Outbound-Resolver-${props.projectId}`,
    });
  }

  private configureMonitoring(props: HybridConnectivityStackProps): void {
    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'DirectConnectDashboard', {
      dashboardName: `DirectConnect-${props.projectId}`,
    });

    // Note: Direct Connect metrics would be added here if connection ID is available
    // For now, we'll create Transit Gateway metrics
    const transitGatewayMetrics = new cloudwatch.GraphWidget({
      title: 'Transit Gateway Metrics',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'BytesIn',
          dimensionsMap: {
            TransitGateway: this.transitGateway.ref,
          },
          statistic: 'Sum',
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/TransitGateway',
          metricName: 'BytesOut',
          dimensionsMap: {
            TransitGateway: this.transitGateway.ref,
          },
          statistic: 'Sum',
        }),
      ],
    });

    dashboard.addWidgets(transitGatewayMetrics);

    // Create CloudWatch alarm for monitoring
    new cloudwatch.Alarm(this, 'TransitGatewayAlarm', {
      alarmName: `TGW-HighTraffic-${props.projectId}`,
      alarmDescription: 'High traffic on Transit Gateway',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TransitGateway',
        metricName: 'BytesIn',
        dimensionsMap: {
          TransitGateway: this.transitGateway.ref,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1000000000, // 1GB in bytes
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
  }

  private configureFlowLogs(props: HybridConnectivityStackProps): void {
    // Create IAM role for VPC Flow Logs
    const flowLogsRole = new iam.Role(this, 'FlowLogsRole', {
      assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/VPCFlowLogsDeliveryRolePolicy'),
      ],
    });

    // Create CloudWatch log group
    const logGroup = new logs.LogGroup(this, 'VpcFlowLogsGroup', {
      logGroupName: `/aws/vpc/flowlogs-${props.projectId}`,
      retention: logs.RetentionDays.ONE_MONTH,
    });

    // Create flow logs for each VPC
    const vpcs = [
      { vpc: this.productionVpc, name: 'Production' },
      { vpc: this.developmentVpc, name: 'Development' },
      { vpc: this.sharedServicesVpc, name: 'SharedServices' },
    ];

    vpcs.forEach(({ vpc, name }) => {
      new ec2.CfnFlowLog(this, `${name}FlowLog`, {
        resourceType: 'VPC',
        resourceId: vpc.vpcId,
        trafficType: 'ALL',
        logDestinationType: 'cloud-watch-logs',
        logGroupName: logGroup.logGroupName,
        deliverLogsPermissionArn: flowLogsRole.roleArn,
        tags: [
          {
            key: 'Name',
            value: `${name}-FlowLog-${props.projectId}`,
          },
        ],
      });
    });
  }

  private createOutputs(props: HybridConnectivityStackProps): void {
    // VPC outputs
    new cdk.CfnOutput(this, 'ProductionVpcId', {
      value: this.productionVpc.vpcId,
      description: 'Production VPC ID',
    });

    new cdk.CfnOutput(this, 'DevelopmentVpcId', {
      value: this.developmentVpc.vpcId,
      description: 'Development VPC ID',
    });

    new cdk.CfnOutput(this, 'SharedServicesVpcId', {
      value: this.sharedServicesVpc.vpcId,
      description: 'Shared Services VPC ID',
    });

    // Transit Gateway outputs
    new cdk.CfnOutput(this, 'TransitGatewayId', {
      value: this.transitGateway.ref,
      description: 'Transit Gateway ID',
    });

    // Direct Connect Gateway outputs
    new cdk.CfnOutput(this, 'DirectConnectGatewayId', {
      value: this.directConnectGateway.ref,
      description: 'Direct Connect Gateway ID',
    });

    // DNS resolver endpoint IPs
    if (props.enableDnsResolution) {
      new cdk.CfnOutput(this, 'InboundResolverEndpointIp', {
        value: '10.3.1.100',
        description: 'Inbound DNS Resolver Endpoint IP',
      });

      new cdk.CfnOutput(this, 'OutboundResolverEndpointIp', {
        value: '10.3.1.101',
        description: 'Outbound DNS Resolver Endpoint IP',
      });
    }

    // BGP configuration guidance
    new cdk.CfnOutput(this, 'BgpConfiguration', {
      value: `Configure BGP with ASN ${props.onPremisesAsn} on your on-premises router`,
      description: 'BGP Configuration Instructions',
    });

    // Virtual Interface configuration
    new cdk.CfnOutput(this, 'VirtualInterfaceConfig', {
      value: `Create Transit VIF with VLAN ${props.transitVifVlan} connected to DX Gateway ${this.directConnectGateway.ref}`,
      description: 'Virtual Interface Configuration',
    });
  }
}