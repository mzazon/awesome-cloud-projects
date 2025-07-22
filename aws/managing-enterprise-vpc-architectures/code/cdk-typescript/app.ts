#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Interface for VPC configuration
 */
interface VpcConfig {
  name: string;
  cidr: string;
  environment: 'production' | 'development' | 'test' | 'shared';
}

/**
 * Interface for Transit Gateway route table configuration
 */
interface RouteTableConfig {
  name: string;
  environment: string;
  attachments: string[];
  propagations: string[];
  staticRoutes?: Array<{
    destinationCidr: string;
    attachmentId?: string;
    blackhole?: boolean;
  }>;
}

/**
 * Stack for Multi-VPC Architecture with Transit Gateway and Route Table Management
 * 
 * This stack implements a comprehensive multi-VPC architecture using AWS Transit Gateway
 * with custom route tables for network segmentation. It creates isolated routing domains
 * for production, development, and shared services while maintaining strict security boundaries.
 */
export class MultiVpcTransitGatewayStack extends cdk.Stack {
  private transitGateway: ec2.CfnTransitGateway;
  private vpcs: Map<string, ec2.Vpc> = new Map();
  private attachments: Map<string, ec2.CfnTransitGatewayVpcAttachment> = new Map();
  private routeTables: Map<string, ec2.CfnTransitGatewayRouteTable> = new Map();
  private securityGroups: Map<string, ec2.SecurityGroup> = new Map();

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // VPC Configuration - Defines network topology with appropriate CIDR blocks
    const vpcConfigs: VpcConfig[] = [
      { name: `prod-vpc-${randomSuffix}`, cidr: '10.0.0.0/16', environment: 'production' },
      { name: `dev-vpc-${randomSuffix}`, cidr: '10.1.0.0/16', environment: 'development' },
      { name: `test-vpc-${randomSuffix}`, cidr: '10.2.0.0/16', environment: 'test' },
      { name: `shared-vpc-${randomSuffix}`, cidr: '10.3.0.0/16', environment: 'shared' }
    ];

    // Create IAM role for VPC Flow Logs
    const flowLogsRole = this.createVpcFlowLogsRole();

    // Create VPCs with proper configuration
    this.createVpcs(vpcConfigs, flowLogsRole);

    // Create Transit Gateway with enhanced configuration
    this.createTransitGateway(randomSuffix);

    // Create VPC attachments to Transit Gateway
    this.createVpcAttachments();

    // Create custom route tables for network segmentation
    this.createCustomRouteTables(randomSuffix);

    // Configure route table associations
    this.configureRouteTableAssociations();

    // Configure route propagation for controlled access
    this.configureRoutePropagation();

    // Create static routes for specific network policies
    this.createStaticRoutes();

    // Update VPC route tables to use Transit Gateway
    this.updateVpcRouteTables();

    // Create security groups for Transit Gateway traffic
    this.createSecurityGroups(randomSuffix);

    // Set up CloudWatch monitoring and alarms
    this.setupCloudWatchMonitoring();

    // Create outputs for important resource identifiers
    this.createOutputs();
  }

  /**
   * Creates IAM role for VPC Flow Logs with appropriate permissions
   */
  private createVpcFlowLogsRole(): iam.Role {
    const flowLogsRole = new iam.Role(this, 'VpcFlowLogsRole', {
      roleName: `flowlogsRole-${this.region}-${this.account}`,
      assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
      description: 'IAM role for VPC Flow Logs to write to CloudWatch Logs',
    });

    // Attach policy for CloudWatch Logs access
    flowLogsRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess')
    );

    // Add inline policy for specific VPC Flow Logs permissions
    flowLogsRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams'
      ],
      resources: ['*']
    }));

    return flowLogsRole;
  }

  /**
   * Creates VPCs with appropriate configuration for each environment
   */
  private createVpcs(vpcConfigs: VpcConfig[], flowLogsRole: iam.Role): void {
    // Create CloudWatch Log Group for VPC Flow Logs
    const vpcFlowLogsGroup = new logs.LogGroup(this, 'VpcFlowLogsGroup', {
      logGroupName: '/aws/vpc/flowlogs',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    vpcConfigs.forEach(config => {
      // Create VPC with single AZ configuration for cost optimization
      const vpc = new ec2.Vpc(this, config.name, {
        vpcName: config.name,
        ipAddresses: ec2.IpAddresses.cidr(config.cidr),
        maxAzs: 1, // Single AZ for cost optimization in demo
        subnetConfiguration: [
          {
            cidrMask: 24,
            name: `${config.environment}-subnet`,
            subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          }
        ],
        enableDnsHostnames: true,
        enableDnsSupport: true,
      });

      // Add environment tag to VPC
      cdk.Tags.of(vpc).add('Environment', config.environment);
      cdk.Tags.of(vpc).add('Purpose', 'Transit Gateway Demo');

      // Enable VPC Flow Logs for network monitoring
      new ec2.CfnFlowLog(this, `${config.name}-flow-logs`, {
        resourceType: 'VPC',
        resourceIds: [vpc.vpcId],
        trafficType: 'ALL',
        logDestinationType: 'cloud-watch-logs',
        logGroupName: vpcFlowLogsGroup.logGroupName,
        deliverLogsPermissionArn: flowLogsRole.roleArn,
        tags: [{
          key: 'Name',
          value: `${config.name}-flow-logs`
        }]
      });

      this.vpcs.set(config.name, vpc);
    });
  }

  /**
   * Creates Transit Gateway with enhanced configuration for enterprise networking
   */
  private createTransitGateway(randomSuffix: string): void {
    this.transitGateway = new ec2.CfnTransitGateway(this, 'EnterpriseTransitGateway', {
      description: 'Enterprise Multi-VPC Transit Gateway for network segmentation',
      amazonSideAsn: 64512, // Private ASN for BGP routing
      autoAcceptSharedAttachments: 'disable', // Require explicit acceptance
      defaultRouteTableAssociation: 'disable', // Custom route table control
      defaultRouteTablePropagation: 'disable', // Explicit route propagation
      vpnEcmpSupport: 'enable', // Support for VPN redundancy
      dnsSupport: 'enable', // Enable DNS resolution across VPCs
      tags: [
        { key: 'Name', value: `enterprise-tgw-${randomSuffix}` },
        { key: 'Environment', value: 'production' },
        { key: 'Purpose', value: 'Multi-VPC Networking Hub' }
      ]
    });
  }

  /**
   * Creates VPC attachments to Transit Gateway for all VPCs
   */
  private createVpcAttachments(): void {
    this.vpcs.forEach((vpc, vpcName) => {
      // Get the private subnet for attachment
      const privateSubnet = vpc.isolatedSubnets[0];
      
      const attachment = new ec2.CfnTransitGatewayVpcAttachment(this, `${vpcName}-attachment`, {
        transitGatewayId: this.transitGateway.attrId,
        vpcId: vpc.vpcId,
        subnetIds: [privateSubnet.subnetId],
        tags: [
          { key: 'Name', value: `${vpcName}-attachment` },
          { key: 'VPC', value: vpcName }
        ]
      });

      // Ensure attachment is created after Transit Gateway
      attachment.addDependency(this.transitGateway);

      this.attachments.set(vpcName, attachment);
    });
  }

  /**
   * Creates custom route tables for network segmentation
   */
  private createCustomRouteTables(randomSuffix: string): void {
    const routeTableConfigs: RouteTableConfig[] = [
      {
        name: 'prod-route-table',
        environment: 'production',
        attachments: [`prod-vpc-${randomSuffix}`],
        propagations: [`shared-vpc-${randomSuffix}`]
      },
      {
        name: 'dev-route-table',
        environment: 'development',
        attachments: [`dev-vpc-${randomSuffix}`, `test-vpc-${randomSuffix}`],
        propagations: [`shared-vpc-${randomSuffix}`]
      },
      {
        name: 'shared-route-table',
        environment: 'shared',
        attachments: [`shared-vpc-${randomSuffix}`],
        propagations: [`prod-vpc-${randomSuffix}`, `dev-vpc-${randomSuffix}`, `test-vpc-${randomSuffix}`]
      }
    ];

    routeTableConfigs.forEach(config => {
      const routeTable = new ec2.CfnTransitGatewayRouteTable(this, config.name, {
        transitGatewayId: this.transitGateway.attrId,
        tags: [
          { key: 'Name', value: config.name },
          { key: 'Environment', value: config.environment },
          { key: 'Purpose', value: 'Network Segmentation' }
        ]
      });

      // Ensure route table is created after Transit Gateway
      routeTable.addDependency(this.transitGateway);

      this.routeTables.set(config.name, routeTable);
    });
  }

  /**
   * Configures route table associations for network segmentation
   */
  private configureRouteTableAssociations(): void {
    // Associate Production VPC with Production Route Table
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'prod-rt-association', {
      transitGatewayAttachmentId: this.attachments.get('prod-vpc-' + this.getRandomSuffix())!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('prod-route-table')!.attrId
    });

    // Associate Development VPC with Development Route Table
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'dev-rt-association', {
      transitGatewayAttachmentId: this.attachments.get('dev-vpc-' + this.getRandomSuffix())!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('dev-route-table')!.attrId
    });

    // Associate Test VPC with Development Route Table
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'test-rt-association', {
      transitGatewayAttachmentId: this.attachments.get('test-vpc-' + this.getRandomSuffix())!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('dev-route-table')!.attrId
    });

    // Associate Shared Services VPC with Shared Route Table
    new ec2.CfnTransitGatewayRouteTableAssociation(this, 'shared-rt-association', {
      transitGatewayAttachmentId: this.attachments.get('shared-vpc-' + this.getRandomSuffix())!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('shared-route-table')!.attrId
    });
  }

  /**
   * Configures route propagation for controlled access patterns
   */
  private configureRoutePropagation(): void {
    const suffix = this.getRandomSuffix();

    // Enable Production to access Shared Services
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'prod-to-shared-propagation', {
      transitGatewayAttachmentId: this.attachments.get(`shared-vpc-${suffix}`)!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('prod-route-table')!.attrId
    });

    // Enable Development/Test to access Shared Services
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'dev-to-shared-propagation', {
      transitGatewayAttachmentId: this.attachments.get(`shared-vpc-${suffix}`)!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('dev-route-table')!.attrId
    });

    // Enable Shared Services to access Production
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'shared-to-prod-propagation', {
      transitGatewayAttachmentId: this.attachments.get(`prod-vpc-${suffix}`)!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('shared-route-table')!.attrId
    });

    // Enable Shared Services to access Development
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'shared-to-dev-propagation', {
      transitGatewayAttachmentId: this.attachments.get(`dev-vpc-${suffix}`)!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('shared-route-table')!.attrId
    });

    // Enable Shared Services to access Test
    new ec2.CfnTransitGatewayRouteTablePropagation(this, 'shared-to-test-propagation', {
      transitGatewayAttachmentId: this.attachments.get(`test-vpc-${suffix}`)!.attrId,
      transitGatewayRouteTableId: this.routeTables.get('shared-route-table')!.attrId
    });
  }

  /**
   * Creates static routes for specific network policies including blackhole routes
   */
  private createStaticRoutes(): void {
    // Create blackhole route to block direct Dev-to-Prod communication
    new ec2.CfnTransitGatewayRoute(this, 'dev-to-prod-blackhole', {
      destinationCidrBlock: '10.0.0.0/16', // Production VPC CIDR
      transitGatewayRouteTableId: this.routeTables.get('dev-route-table')!.attrId,
      blackhole: true
    });

    const suffix = this.getRandomSuffix();

    // Create specific route for shared services access from production
    new ec2.CfnTransitGatewayRoute(this, 'prod-to-shared-route', {
      destinationCidrBlock: '10.3.0.0/16', // Shared Services VPC CIDR
      transitGatewayRouteTableId: this.routeTables.get('prod-route-table')!.attrId,
      transitGatewayAttachmentId: this.attachments.get(`shared-vpc-${suffix}`)!.attrId
    });

    // Create specific route for shared services access from development
    new ec2.CfnTransitGatewayRoute(this, 'dev-to-shared-route', {
      destinationCidrBlock: '10.3.0.0/16', // Shared Services VPC CIDR
      transitGatewayRouteTableId: this.routeTables.get('dev-route-table')!.attrId,
      transitGatewayAttachmentId: this.attachments.get(`shared-vpc-${suffix}`)!.attrId
    });
  }

  /**
   * Updates VPC route tables to direct traffic through Transit Gateway
   */
  private updateVpcRouteTables(): void {
    const suffix = this.getRandomSuffix();

    // Production VPC routes to shared services
    const prodVpc = this.vpcs.get(`prod-vpc-${suffix}`)!;
    prodVpc.isolatedSubnets.forEach((subnet, index) => {
      new ec2.CfnRoute(this, `prod-to-tgw-route-${index}`, {
        routeTableId: subnet.routeTable.routeTableId,
        destinationCidrBlock: '10.3.0.0/16', // Shared Services CIDR
        transitGatewayId: this.transitGateway.attrId
      });
    });

    // Development VPC routes to shared services
    const devVpc = this.vpcs.get(`dev-vpc-${suffix}`)!;
    devVpc.isolatedSubnets.forEach((subnet, index) => {
      new ec2.CfnRoute(this, `dev-to-tgw-route-${index}`, {
        routeTableId: subnet.routeTable.routeTableId,
        destinationCidrBlock: '10.3.0.0/16', // Shared Services CIDR
        transitGatewayId: this.transitGateway.attrId
      });
    });

    // Test VPC routes to shared services
    const testVpc = this.vpcs.get(`test-vpc-${suffix}`)!;
    testVpc.isolatedSubnets.forEach((subnet, index) => {
      new ec2.CfnRoute(this, `test-to-tgw-route-${index}`, {
        routeTableId: subnet.routeTable.routeTableId,
        destinationCidrBlock: '10.3.0.0/16', // Shared Services CIDR
        transitGatewayId: this.transitGateway.attrId
      });
    });

    // Shared Services VPC routes to all other environments
    const sharedVpc = this.vpcs.get(`shared-vpc-${suffix}`)!;
    sharedVpc.isolatedSubnets.forEach((subnet, index) => {
      new ec2.CfnRoute(this, `shared-to-tgw-route-${index}`, {
        routeTableId: subnet.routeTable.routeTableId,
        destinationCidrBlock: '10.0.0.0/8', // Broad routing for shared services
        transitGatewayId: this.transitGateway.attrId
      });
    });
  }

  /**
   * Creates security groups for Transit Gateway traffic control
   */
  private createSecurityGroups(randomSuffix: string): void {
    // Production Security Group
    const prodVpc = this.vpcs.get(`prod-vpc-${randomSuffix}`)!;
    const prodSg = new ec2.SecurityGroup(this, 'prod-tgw-sg', {
      vpc: prodVpc,
      securityGroupName: 'prod-tgw-sg',
      description: 'Security group for production Transit Gateway traffic',
      allowAllOutbound: true
    });

    // Allow HTTPS within production environment
    prodSg.addIngressRule(
      prodSg,
      ec2.Port.tcp(443),
      'HTTPS traffic within production environment'
    );

    // Allow DNS queries to shared services
    prodSg.addIngressRule(
      ec2.Peer.ipv4('10.3.0.0/16'),
      ec2.Port.tcp(53),
      'DNS TCP queries to shared services'
    );

    prodSg.addIngressRule(
      ec2.Peer.ipv4('10.3.0.0/16'),
      ec2.Port.udp(53),
      'DNS UDP queries to shared services'
    );

    this.securityGroups.set('production', prodSg);

    // Development Security Group
    const devVpc = this.vpcs.get(`dev-vpc-${randomSuffix}`)!;
    const devSg = new ec2.SecurityGroup(this, 'dev-tgw-sg', {
      vpc: devVpc,
      securityGroupName: 'dev-tgw-sg',
      description: 'Security group for development Transit Gateway traffic',
      allowAllOutbound: true
    });

    // Allow HTTP/HTTPS within development environment
    devSg.addIngressRule(
      ec2.Peer.ipv4('10.1.0.0/16'),
      ec2.Port.tcp(80),
      'HTTP traffic within development environment'
    );

    devSg.addIngressRule(
      ec2.Peer.ipv4('10.1.0.0/16'),
      ec2.Port.tcp(443),
      'HTTPS traffic within development environment'
    );

    // Allow SSH from test environment
    devSg.addIngressRule(
      ec2.Peer.ipv4('10.2.0.0/16'),
      ec2.Port.tcp(22),
      'SSH access from test environment'
    );

    this.securityGroups.set('development', devSg);

    cdk.Tags.of(prodSg).add('Environment', 'production');
    cdk.Tags.of(devSg).add('Environment', 'development');
  }

  /**
   * Sets up CloudWatch monitoring and alarms for Transit Gateway
   */
  private setupCloudWatchMonitoring(): void {
    // Create CloudWatch Log Group for Transit Gateway Flow Logs
    const tgwFlowLogsGroup = new logs.LogGroup(this, 'TransitGatewayFlowLogsGroup', {
      logGroupName: '/aws/transitgateway/flowlogs',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create CloudWatch Alarm for high data processing
    new cloudwatch.Alarm(this, 'TransitGatewayDataProcessingAlarm', {
      alarmName: 'TransitGateway-DataProcessing-High',
      alarmDescription: 'High data processing on Transit Gateway',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TransitGateway',
        metricName: 'BytesIn',
        dimensionsMap: {
          TransitGateway: this.transitGateway.attrId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 10000000000, // 10 GB
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create alarm for Transit Gateway attachment failures
    new cloudwatch.Alarm(this, 'TransitGatewayAttachmentFailureAlarm', {
      alarmName: 'TransitGateway-Attachment-Failures',
      alarmDescription: 'Monitor Transit Gateway attachment failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/TransitGateway',
        metricName: 'PacketDropCount',
        dimensionsMap: {
          TransitGateway: this.transitGateway.attrId
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1000,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2
    });
  }

  /**
   * Creates CloudFormation outputs for important resource identifiers
   */
  private createOutputs(): void {
    // Transit Gateway Output
    new cdk.CfnOutput(this, 'TransitGatewayId', {
      value: this.transitGateway.attrId,
      description: 'ID of the Transit Gateway',
      exportName: `${this.stackName}-TransitGatewayId`
    });

    // VPC Outputs
    this.vpcs.forEach((vpc, name) => {
      new cdk.CfnOutput(this, `${name}-VpcId`, {
        value: vpc.vpcId,
        description: `VPC ID for ${name}`,
        exportName: `${this.stackName}-${name}-VpcId`
      });
    });

    // Route Table Outputs
    this.routeTables.forEach((rt, name) => {
      new cdk.CfnOutput(this, `${name}-RouteTableId`, {
        value: rt.attrId,
        description: `Route Table ID for ${name}`,
        exportName: `${this.stackName}-${name}-RouteTableId`
      });
    });

    // Security Group Outputs
    this.securityGroups.forEach((sg, name) => {
      new cdk.CfnOutput(this, `${name}-SecurityGroupId`, {
        value: sg.securityGroupId,
        description: `Security Group ID for ${name} environment`,
        exportName: `${this.stackName}-${name}-SecurityGroupId`
      });
    });

    // Monitoring Output
    new cdk.CfnOutput(this, 'MonitoringSetup', {
      value: 'CloudWatch alarms and VPC Flow Logs configured',
      description: 'Status of monitoring configuration'
    });
  }

  /**
   * Helper method to extract random suffix from VPC names
   */
  private getRandomSuffix(): string {
    const firstVpcName = Array.from(this.vpcs.keys())[0];
    return firstVpcName.split('-').pop() || 'unknown';
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the main stack with appropriate configuration
new MultiVpcTransitGatewayStack(app, 'MultiVpcTransitGatewayStack', {
  description: 'Multi-VPC Architecture with Transit Gateway and Route Table Management',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  tags: {
    Project: 'TransitGatewayDemo',
    Environment: 'Development',
    CostCenter: 'Engineering',
    Owner: 'NetworkingTeam'
  }
});

app.synth();