#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for creating AWS Site-to-Site VPN connections
 * Implements secure IPsec tunnels between on-premises and AWS VPC
 */
export class VpnConnectionsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Parameters for customization
    const customerGatewayIp = new cdk.CfnParameter(this, 'CustomerGatewayIp', {
      type: 'String',
      description: 'Public IP address of your on-premises VPN device',
      default: '203.0.113.12',
      allowedPattern: '^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$',
      constraintDescription: 'Must be a valid IP address'
    });

    const customerGatewayBgpAsn = new cdk.CfnParameter(this, 'CustomerGatewayBgpAsn', {
      type: 'Number',
      description: 'BGP ASN for your on-premises network',
      default: 65000,
      minValue: 1,
      maxValue: 4294967295,
      constraintDescription: 'Must be a valid BGP ASN'
    });

    const awsBgpAsn = new cdk.CfnParameter(this, 'AwsBgpAsn', {
      type: 'Number',
      description: 'BGP ASN for AWS side',
      default: 64512,
      minValue: 1,
      maxValue: 4294967295,
      constraintDescription: 'Must be a valid BGP ASN'
    });

    const onPremisesNetworkCidr = new cdk.CfnParameter(this, 'OnPremisesNetworkCidr', {
      type: 'String',
      description: 'CIDR block for your on-premises network',
      default: '10.0.0.0/16',
      allowedPattern: '^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])(\\/([0-9]|[1-2][0-9]|3[0-2]))$',
      constraintDescription: 'Must be a valid CIDR block'
    });

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().substring(0, 6);

    // Create VPC with public and private subnets
    const vpc = new ec2.Vpc(this, 'VpnDemoVpc', {
      ipAddresses: ec2.IpAddresses.cidr('172.31.0.0/16'),
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for this demo
      subnetConfiguration: [
        {
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 20,
        },
        {
          name: 'PrivateSubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 20,
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Add tags to VPC
    cdk.Tags.of(vpc).add('Name', `vpn-demo-vpc-${uniqueSuffix}`);

    // Create Customer Gateway
    const customerGateway = new ec2.CfnCustomerGateway(this, 'CustomerGateway', {
      type: 'ipsec.1',
      ipAddress: customerGatewayIp.valueAsString,
      bgpAsn: customerGatewayBgpAsn.valueAsNumber,
      tags: [
        {
          key: 'Name',
          value: `vpn-demo-cgw-${uniqueSuffix}`
        }
      ]
    });

    // Create Virtual Private Gateway
    const vpnGateway = new ec2.CfnVPNGateway(this, 'VpnGateway', {
      type: 'ipsec.1',
      amazonSideAsn: awsBgpAsn.valueAsNumber,
      tags: [
        {
          key: 'Name',
          value: `vpn-demo-vgw-${uniqueSuffix}`
        }
      ]
    });

    // Attach VPN Gateway to VPC
    const vpnGatewayAttachment = new ec2.CfnVPCGatewayAttachment(this, 'VpnGatewayAttachment', {
      vpcId: vpc.vpcId,
      vpnGatewayId: vpnGateway.ref
    });

    // Create VPN Connection
    const vpnConnection = new ec2.CfnVPNConnection(this, 'VpnConnection', {
      type: 'ipsec.1',
      customerGatewayId: customerGateway.ref,
      vpnGatewayId: vpnGateway.ref,
      staticRoutesOnly: false, // Use BGP routing
      tags: [
        {
          key: 'Name',
          value: `vpn-demo-connection-${uniqueSuffix}`
        }
      ]
    });

    // Ensure VPN connection is created after gateway attachment
    vpnConnection.addDependency(vpnGatewayAttachment);

    // Create custom route table for VPN routes
    const vpnRouteTable = new ec2.CfnRouteTable(this, 'VpnRouteTable', {
      vpcId: vpc.vpcId,
      tags: [
        {
          key: 'Name',
          value: `vpn-demo-rt-${uniqueSuffix}`
        }
      ]
    });

    // Enable route propagation from VPN gateway
    const routePropagation = new ec2.CfnVPNGatewayRoutePropagation(this, 'RoutePropagation', {
      routeTableId: vpnRouteTable.ref,
      vpnGatewayId: vpnGateway.ref
    });

    // Associate private subnets with VPN route table
    const privateSubnets = vpc.privateSubnets;
    privateSubnets.forEach((subnet, index) => {
      // First, disassociate from default route table
      const defaultAssociation = subnet.node.findChild('RouteTableAssociation') as ec2.CfnSubnetRouteTableAssociation;
      
      // Create new association with VPN route table
      new ec2.CfnSubnetRouteTableAssociation(this, `VpnRouteTableAssociation${index}`, {
        subnetId: subnet.subnetId,
        routeTableId: vpnRouteTable.ref
      });
    });

    // Create Security Group for VPN testing
    const vpnSecurityGroup = new ec2.SecurityGroup(this, 'VpnSecurityGroup', {
      vpc,
      description: 'Security group for VPN testing',
      securityGroupName: `vpn-demo-sg-${uniqueSuffix}`,
      allowAllOutbound: true
    });

    // Add ingress rules for on-premises network
    vpnSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(onPremisesNetworkCidr.valueAsString),
      ec2.Port.tcp(22),
      'Allow SSH from on-premises network'
    );

    vpnSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(onPremisesNetworkCidr.valueAsString),
      ec2.Port.allIcmp(),
      'Allow ICMP from on-premises network'
    );

    // Allow traffic from same security group
    vpnSecurityGroup.addIngressRule(
      vpnSecurityGroup,
      ec2.Port.allTraffic(),
      'Allow all traffic from same security group'
    );

    // Create test EC2 instance in private subnet
    const testInstance = new ec2.Instance(this, 'TestInstance', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED
      },
      securityGroup: vpnSecurityGroup,
      keyName: undefined, // No key pair needed for this demo
      role: new iam.Role(this, 'TestInstanceRole', {
        assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
        ]
      })
    });

    // Add tags to test instance
    cdk.Tags.of(testInstance).add('Name', `vpn-demo-test-instance-${uniqueSuffix}`);

    // Create CloudWatch Dashboard for VPN monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'VpnMonitoringDashboard', {
      dashboardName: `VPN-Monitoring-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'VPN Connection Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VPN',
                metricName: 'VpnState',
                dimensionsMap: {
                  VpnId: vpnConnection.ref
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VPN',
                metricName: 'VpnTunnelState',
                dimensionsMap: {
                  VpnId: vpnConnection.ref
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          })
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'VPN Traffic',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/VPN',
                metricName: 'VpnPacketsReceived',
                dimensionsMap: {
                  VpnId: vpnConnection.ref
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/VPN',
                metricName: 'VpnPacketsSent',
                dimensionsMap: {
                  VpnId: vpnConnection.ref
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5)
              })
            ],
            width: 12,
            height: 6
          })
        ]
      ]
    });

    // Create CloudWatch Alarms for VPN tunnel monitoring
    const vpnTunnelAlarm = new cloudwatch.Alarm(this, 'VpnTunnelAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/VPN',
        metricName: 'VpnTunnelState',
        dimensionsMap: {
          VpnId: vpnConnection.ref
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
      alarmDescription: 'VPN tunnel is down',
      alarmName: `VPN-Tunnel-Down-${uniqueSuffix}`
    });

    // Outputs for reference and validation
    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID for the VPN demo environment'
    });

    new cdk.CfnOutput(this, 'CustomerGatewayId', {
      value: customerGateway.ref,
      description: 'Customer Gateway ID'
    });

    new cdk.CfnOutput(this, 'VpnGatewayId', {
      value: vpnGateway.ref,
      description: 'Virtual Private Gateway ID'
    });

    new cdk.CfnOutput(this, 'VpnConnectionId', {
      value: vpnConnection.ref,
      description: 'VPN Connection ID'
    });

    new cdk.CfnOutput(this, 'TestInstanceId', {
      value: testInstance.instanceId,
      description: 'Test EC2 Instance ID'
    });

    new cdk.CfnOutput(this, 'TestInstancePrivateIp', {
      value: testInstance.instancePrivateIp,
      description: 'Test EC2 Instance Private IP'
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: vpnSecurityGroup.securityGroupId,
      description: 'Security Group ID for VPN testing'
    });

    new cdk.CfnOutput(this, 'VpnRouteTableId', {
      value: vpnRouteTable.ref,
      description: 'Route Table ID for VPN routes'
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardName', {
      value: dashboard.dashboardName,
      description: 'CloudWatch Dashboard name for VPN monitoring'
    });

    new cdk.CfnOutput(this, 'VpnConfigurationCommand', {
      value: `aws ec2 describe-vpn-connections --vpn-connection-ids ${vpnConnection.ref} --query 'VpnConnections[0].CustomerGatewayConfiguration' --output text`,
      description: 'Command to download VPN configuration for your customer gateway'
    });
  }
}

// CDK App
const app = new cdk.App();

// Create the VPN connections stack
new VpnConnectionsStack(app, 'VpnConnectionsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS Site-to-Site VPN Connection Stack - Creates secure IPsec tunnels between on-premises and AWS VPC',
  tags: {
    Project: 'VPN-Demo',
    Environment: 'Demo',
    CreatedBy: 'CDK'
  }
});

app.synth();