#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

/**
 * Properties for the MicroSegmentationStack
 */
interface MicroSegmentationStackProps extends cdk.StackProps {
  readonly vpcCidr?: string;
  readonly enableFlowLogs?: boolean;
  readonly enableMonitoring?: boolean;
}

/**
 * CDK Stack for Securing Networks with Micro-Segmentation using NACLs and Security Groupsexisting_folder_name
 * 
 * This stack creates:
 * - VPC with multiple security zones (DMZ, Web, App, Database, Management, Monitoring)
 * - Custom NACLs for each security zone with specific traffic rules
 * - Advanced security groups with layered access controls
 * - VPC Flow Logs for network monitoring
 * - CloudWatch alarms for security monitoring
 */
class MicroSegmentationStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly securityZones: { [key: string]: SecurityZone };
  public readonly flowLogGroup?: logs.LogGroup;
  public readonly flowLogRole?: iam.Role;

  constructor(scope: Construct, id: string, props: MicroSegmentationStackProps = {}) {
    super(scope, id, props);

    // Create VPC for micro-segmentation
    this.vpc = new ec2.Vpc(this, 'MicroSegmentationVPC', {
      cidr: props.vpcCidr || '10.0.0.0/16',
      maxAzs: 1, // Use single AZ for simplicity in this example
      natGateways: 0, // No NAT gateways needed for this architecture
      subnetConfiguration: [],
      enableDnsHostnames: true,
      enableDnsSupport: true,
      restrictDefaultSecurityGroup: true,
    });

    // Tag the VPC
    cdk.Tags.of(this.vpc).add('Name', 'MicroSegmentationVPC');
    cdk.Tags.of(this.vpc).add('Environment', 'Production');

    // Create security zones with their respective subnets, NACLs, and security groups
    this.securityZones = this.createSecurityZones();

    // Configure NACL rules for each security zone
    this.configureNACLRules();

    // Configure security group rules with cross-zone references
    this.configureSecurityGroupRules();

    // Set up VPC Flow Logs if enabled
    if (props.enableFlowLogs !== false) {
      this.setupVPCFlowLogs();
    }

    // Set up CloudWatch monitoring if enabled
    if (props.enableMonitoring !== false) {
      this.setupCloudWatchMonitoring();
    }

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Create security zones with subnets, NACLs, and security groups
   */
  private createSecurityZones(): { [key: string]: SecurityZone } {
    const zones: { [key: string]: SecurityZone } = {};

    // Define security zone configurations
    const zoneConfigs = [
      { name: 'DMZ', cidr: '10.0.1.0/24', description: 'Internet-facing zone for load balancers' },
      { name: 'Web', cidr: '10.0.2.0/24', description: 'Web tier for application servers' },
      { name: 'App', cidr: '10.0.3.0/24', description: 'Application tier for business logic' },
      { name: 'Database', cidr: '10.0.4.0/24', description: 'Database tier for data storage' },
      { name: 'Management', cidr: '10.0.5.0/24', description: 'Management and bastion hosts' },
      { name: 'Monitoring', cidr: '10.0.6.0/24', description: 'Monitoring and logging services' }
    ];

    // Create each security zone
    zoneConfigs.forEach(config => {
      zones[config.name] = new SecurityZone(this, `${config.name}Zone`, {
        vpc: this.vpc,
        zoneName: config.name,
        cidrBlock: config.cidr,
        description: config.description
      });
    });

    return zones;
  }

  /**
   * Configure NACL rules for each security zone
   */
  private configureNACLRules(): void {
    // DMZ NACL Rules (Internet-facing)
    this.configureDMZNACLRules();

    // Web Tier NACL Rules
    this.configureWebNACLRules();

    // Application Tier NACL Rules
    this.configureAppNACLRules();

    // Database Tier NACL Rules (most restrictive)
    this.configureDatabaseNACLRules();

    // Management NACL Rules
    this.configureManagementNACLRules();

    // Monitoring NACL Rules
    this.configureMonitoringNACLRules();
  }

  /**
   * Configure DMZ NACL rules for internet-facing traffic
   */
  private configureDMZNACLRules(): void {
    const dmzNacl = this.securityZones['DMZ'].networkAcl;

    // Inbound Rules - Allow HTTP/HTTPS from Internet
    dmzNacl.addEntry('DMZ-Inbound-HTTP', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(80),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    dmzNacl.addEntry('DMZ-Inbound-HTTPS', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(443),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow ephemeral ports for return traffic
    dmzNacl.addEntry('DMZ-Inbound-Ephemeral', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(1024, 65535),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Outbound Rules - Allow to Web Tier
    dmzNacl.addEntry('DMZ-Outbound-Web-HTTP', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(80),
      cidr: ec2.AclCidr.ipv4('10.0.2.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    dmzNacl.addEntry('DMZ-Outbound-Web-HTTPS', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(443),
      cidr: ec2.AclCidr.ipv4('10.0.2.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow ephemeral ports to Internet
    dmzNacl.addEntry('DMZ-Outbound-Internet-Ephemeral', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(1024, 65535),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });
  }

  /**
   * Configure Web Tier NACL rules
   */
  private configureWebNACLRules(): void {
    const webNacl = this.securityZones['Web'].networkAcl;

    // Inbound - Allow from DMZ only
    webNacl.addEntry('Web-Inbound-DMZ-HTTP', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(80),
      cidr: ec2.AclCidr.ipv4('10.0.1.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    webNacl.addEntry('Web-Inbound-DMZ-HTTPS', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(443),
      cidr: ec2.AclCidr.ipv4('10.0.1.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow SSH from Management
    webNacl.addEntry('Web-Inbound-Management-SSH', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(22),
      cidr: ec2.AclCidr.ipv4('10.0.5.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow monitoring from Monitoring zone
    webNacl.addEntry('Web-Inbound-Monitoring-SNMP', {
      ruleNumber: 130,
      protocol: ec2.AclProtocol.tcp(161),
      cidr: ec2.AclCidr.ipv4('10.0.6.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Outbound - Allow to App Tier
    webNacl.addEntry('Web-Outbound-App-8080', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(8080),
      cidr: ec2.AclCidr.ipv4('10.0.3.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow return traffic to DMZ
    webNacl.addEntry('Web-Outbound-DMZ-Return', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(1024, 65535),
      cidr: ec2.AclCidr.ipv4('10.0.1.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow HTTPS to Internet for updates
    webNacl.addEntry('Web-Outbound-Internet-HTTPS', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(443),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });
  }

  /**
   * Configure Application Tier NACL rules
   */
  private configureAppNACLRules(): void {
    const appNacl = this.securityZones['App'].networkAcl;

    // Inbound - Allow from Web Tier only
    appNacl.addEntry('App-Inbound-Web-8080', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(8080),
      cidr: ec2.AclCidr.ipv4('10.0.2.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow SSH from Management
    appNacl.addEntry('App-Inbound-Management-SSH', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(22),
      cidr: ec2.AclCidr.ipv4('10.0.5.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow monitoring
    appNacl.addEntry('App-Inbound-Monitoring-SNMP', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(161),
      cidr: ec2.AclCidr.ipv4('10.0.6.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Outbound - Allow to Database
    appNacl.addEntry('App-Outbound-Database-MySQL', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(3306),
      cidr: ec2.AclCidr.ipv4('10.0.4.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow return traffic to Web Tier
    appNacl.addEntry('App-Outbound-Web-Return', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(1024, 65535),
      cidr: ec2.AclCidr.ipv4('10.0.2.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow HTTPS for external APIs
    appNacl.addEntry('App-Outbound-Internet-HTTPS', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(443),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });
  }

  /**
   * Configure Database Tier NACL rules (most restrictive)
   */
  private configureDatabaseNACLRules(): void {
    const dbNacl = this.securityZones['Database'].networkAcl;

    // Inbound - Allow from App Tier only
    dbNacl.addEntry('Database-Inbound-App-MySQL', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(3306),
      cidr: ec2.AclCidr.ipv4('10.0.3.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow SSH from Management only
    dbNacl.addEntry('Database-Inbound-Management-SSH', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(22),
      cidr: ec2.AclCidr.ipv4('10.0.5.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Inbound - Allow monitoring
    dbNacl.addEntry('Database-Inbound-Monitoring-SNMP', {
      ruleNumber: 120,
      protocol: ec2.AclProtocol.tcp(161),
      cidr: ec2.AclCidr.ipv4('10.0.6.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Outbound - Allow return traffic to App Tier
    dbNacl.addEntry('Database-Outbound-App-Return', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(1024, 65535),
      cidr: ec2.AclCidr.ipv4('10.0.3.0/24'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow HTTPS for patches (restricted)
    dbNacl.addEntry('Database-Outbound-Internet-HTTPS', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.tcp(443),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });
  }

  /**
   * Configure Management NACL rules
   */
  private configureManagementNACLRules(): void {
    const mgmtNacl = this.securityZones['Management'].networkAcl;

    // Inbound - Allow VPN access
    mgmtNacl.addEntry('Management-Inbound-VPN-SSH', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.tcp(22),
      cidr: ec2.AclCidr.ipv4('10.0.0.0/8'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Outbound - Allow access to all internal zones
    mgmtNacl.addEntry('Management-Outbound-Internal', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.allTraffic(),
      cidr: ec2.AclCidr.ipv4('10.0.0.0/16'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow Internet access
    mgmtNacl.addEntry('Management-Outbound-Internet', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.allTraffic(),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });
  }

  /**
   * Configure Monitoring NACL rules
   */
  private configureMonitoringNACLRules(): void {
    const monNacl = this.securityZones['Monitoring'].networkAcl;

    // Inbound - Allow monitoring traffic from all zones
    monNacl.addEntry('Monitoring-Inbound-All-Zones', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.allTraffic(),
      cidr: ec2.AclCidr.ipv4('10.0.0.0/16'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.INBOUND
    });

    // Outbound - Allow monitoring responses
    monNacl.addEntry('Monitoring-Outbound-All-Zones', {
      ruleNumber: 100,
      protocol: ec2.AclProtocol.allTraffic(),
      cidr: ec2.AclCidr.ipv4('10.0.0.0/16'),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });

    // Outbound - Allow Internet access for monitoring services
    monNacl.addEntry('Monitoring-Outbound-Internet', {
      ruleNumber: 110,
      protocol: ec2.AclProtocol.allTraffic(),
      cidr: ec2.AclCidr.anyIpv4(),
      traffic: ec2.AclTraffic.allowAll(),
      direction: ec2.TrafficDirection.OUTBOUND
    });
  }

  /**
   * Configure security group rules with cross-zone references
   */
  private configureSecurityGroupRules(): void {
    // DMZ Security Group Rules (Load Balancer)
    this.securityZones['DMZ'].securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP from Internet'
    );

    this.securityZones['DMZ'].securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS from Internet'
    );

    // Web Tier Security Group Rules
    this.securityZones['Web'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['DMZ'].securityGroup.securityGroupId),
      ec2.Port.tcp(80),
      'Allow HTTP from DMZ'
    );

    this.securityZones['Web'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['DMZ'].securityGroup.securityGroupId),
      ec2.Port.tcp(443),
      'Allow HTTPS from DMZ'
    );

    this.securityZones['Web'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['Management'].securityGroup.securityGroupId),
      ec2.Port.tcp(22),
      'Allow SSH from Management'
    );

    // App Tier Security Group Rules
    this.securityZones['App'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['Web'].securityGroup.securityGroupId),
      ec2.Port.tcp(8080),
      'Allow application traffic from Web Tier'
    );

    this.securityZones['App'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['Management'].securityGroup.securityGroupId),
      ec2.Port.tcp(22),
      'Allow SSH from Management'
    );

    // Database Security Group Rules (most restrictive)
    this.securityZones['Database'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['App'].securityGroup.securityGroupId),
      ec2.Port.tcp(3306),
      'Allow MySQL from App Tier only'
    );

    this.securityZones['Database'].securityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.securityZones['Management'].securityGroup.securityGroupId),
      ec2.Port.tcp(22),
      'Allow SSH from Management'
    );

    // Management Security Group Rules
    this.securityZones['Management'].securityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/8'),
      ec2.Port.tcp(22),
      'Allow SSH from private networks'
    );

    // Monitoring Security Group Rules
    this.securityZones['Monitoring'].securityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/16'),
      ec2.Port.tcp(161),
      'Allow SNMP from all VPC zones'
    );

    this.securityZones['Monitoring'].securityGroup.addIngressRule(
      ec2.Peer.ipv4('10.0.0.0/16'),
      ec2.Port.tcpRange(8000, 9000),
      'Allow custom monitoring ports from VPC'
    );
  }

  /**
   * Set up VPC Flow Logs for network monitoring
   */
  private setupVPCFlowLogs(): void {
    // Create IAM role for VPC Flow Logs
    this.flowLogRole = new iam.Role(this, 'VPCFlowLogsRole', {
      assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/VPCFlowLogsDeliveryRolePolicy')
      ]
    });

    // Create CloudWatch Log Group for Flow Logs
    this.flowLogGroup = new logs.LogGroup(this, 'VPCFlowLogsGroup', {
      logGroupName: '/aws/vpc/microsegmentation/flowlogs',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Enable VPC Flow Logs
    new ec2.FlowLog(this, 'VPCFlowLogs', {
      resourceType: ec2.FlowLogResourceType.fromVpc(this.vpc),
      destination: ec2.FlowLogDestination.toCloudWatchLogs(this.flowLogGroup, this.flowLogRole),
      trafficType: ec2.FlowLogTrafficType.ALL
    });
  }

  /**
   * Set up CloudWatch monitoring and alarms
   */
  private setupCloudWatchMonitoring(): void {
    if (!this.flowLogGroup) return;

    // Create metric filter for rejected traffic
    const rejectedTrafficFilter = new logs.MetricFilter(this, 'RejectedTrafficFilter', {
      logGroup: this.flowLogGroup,
      metricNamespace: 'VPC/Security',
      metricName: 'RejectedPackets',
      filterPattern: logs.FilterPattern.literal('[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action="REJECT", flowlogstatus]'),
      metricValue: '1'
    });

    // Create alarm for high rejected traffic
    new cloudwatch.Alarm(this, 'HighRejectedTrafficAlarm', {
      metric: rejectedTrafficFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 1000,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'High number of rejected packets detected in VPC',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Create metric filter for suspicious port scanning
    const portScanFilter = new logs.MetricFilter(this, 'PortScanFilter', {
      logGroup: this.flowLogGroup,
      metricNamespace: 'VPC/Security',
      metricName: 'PortScanAttempts',
      filterPattern: logs.FilterPattern.literal('[version, account, eni, source, destination, srcport, destport="22" || destport="3389" || destport="1433" || destport="3306", protocol, packets, bytes, windowstart, windowend, action="REJECT", flowlogstatus]'),
      metricValue: '1'
    });

    // Create alarm for port scanning attempts
    new cloudwatch.Alarm(this, 'PortScanDetectionAlarm', {
      metric: portScanFilter.metric({
        statistic: 'Sum',
        period: cdk.Duration.minutes(5)
      }),
      threshold: 50,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      alarmDescription: 'Potential port scanning activity detected',
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
  }

  /**
   * Create CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the micro-segmentation environment'
    });

    new cdk.CfnOutput(this, 'VPCCidr', {
      value: this.vpc.vpcCidrBlock,
      description: 'CIDR block of the VPC'
    });

    // Output security zone information
    Object.entries(this.securityZones).forEach(([zoneName, zone]) => {
      new cdk.CfnOutput(this, `${zoneName}SubnetId`, {
        value: zone.subnet.subnetId,
        description: `Subnet ID for ${zoneName} security zone`
      });

      new cdk.CfnOutput(this, `${zoneName}SecurityGroupId`, {
        value: zone.securityGroup.securityGroupId,
        description: `Security Group ID for ${zoneName} zone`
      });

      new cdk.CfnOutput(this, `${zoneName}NACLId`, {
        value: zone.networkAcl.networkAclId,
        description: `Network ACL ID for ${zoneName} zone`
      });
    });

    if (this.flowLogGroup) {
      new cdk.CfnOutput(this, 'FlowLogGroupName', {
        value: this.flowLogGroup.logGroupName,
        description: 'CloudWatch Log Group name for VPC Flow Logs'
      });
    }
  }
}

/**
 * Properties for a SecurityZone construct
 */
interface SecurityZoneProps {
  readonly vpc: ec2.Vpc;
  readonly zoneName: string;
  readonly cidrBlock: string;
  readonly description: string;
}

/**
 * Security Zone construct that creates a subnet, NACL, and security group
 */
class SecurityZone extends Construct {
  public readonly subnet: ec2.Subnet;
  public readonly networkAcl: ec2.NetworkAcl;
  public readonly securityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props: SecurityZoneProps) {
    super(scope, id);

    // Create subnet for this security zone
    this.subnet = new ec2.Subnet(this, 'Subnet', {
      vpc: props.vpc,
      cidrBlock: props.cidrBlock,
      availabilityZone: props.vpc.availabilityZones[0],
      mapPublicIpOnLaunch: props.zoneName === 'DMZ' // Only DMZ should have public IPs
    });

    // Tag the subnet
    cdk.Tags.of(this.subnet).add('Name', `${props.zoneName}-subnet`);
    cdk.Tags.of(this.subnet).add('Zone', props.zoneName.toLowerCase());

    // Create custom Network ACL for this zone
    this.networkAcl = new ec2.NetworkAcl(this, 'NetworkAcl', {
      vpc: props.vpc,
      networkAclName: `${props.zoneName}-nacl`
    });

    // Tag the NACL
    cdk.Tags.of(this.networkAcl).add('Name', `${props.zoneName}-nacl`);
    cdk.Tags.of(this.networkAcl).add('Zone', props.zoneName.toLowerCase());

    // Associate the NACL with the subnet
    new ec2.SubnetNetworkAclAssociation(this, 'NACLAssociation', {
      subnet: this.subnet,
      networkAcl: this.networkAcl
    });

    // Create security group for this zone
    this.securityGroup = new ec2.SecurityGroup(this, 'SecurityGroup', {
      vpc: props.vpc,
      securityGroupName: `${props.zoneName}-sg`,
      description: props.description,
      allowAllOutbound: false // Start with restrictive outbound rules
    });

    // Tag the security group
    cdk.Tags.of(this.securityGroup).add('Name', `${props.zoneName}-sg`);
    cdk.Tags.of(this.securityGroup).add('Zone', props.zoneName.toLowerCase());

    // Add basic outbound rules based on zone type
    if (props.zoneName === 'DMZ') {
      // DMZ can access internet and internal zones
      this.securityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.allTraffic(),
        'Allow all outbound traffic for DMZ'
      );
    } else if (props.zoneName === 'Management') {
      // Management can access all zones
      this.securityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.allTraffic(),
        'Allow all outbound traffic for Management'
      );
    } else if (props.zoneName === 'Monitoring') {
      // Monitoring can access all zones
      this.securityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.allTraffic(),
        'Allow all outbound traffic for Monitoring'
      );
    } else {
      // Other zones have limited outbound access
      this.securityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.tcp(443),
        'Allow HTTPS outbound'
      );
      this.securityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.tcp(53),
        'Allow DNS outbound'
      );
      this.securityGroup.addEgressRule(
        ec2.Peer.anyIpv4(),
        ec2.Port.udp(53),
        'Allow DNS outbound'
      );
    }
  }
}

/**
 * Main CDK Application
 */
const app = new cdk.App();

// Create the micro-segmentation stack
new MicroSegmentationStack(app, 'MicroSegmentationStack', {
  description: 'Network micro-segmentation with NACLs and advanced security groups',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  // Stack configuration
  vpcCidr: '10.0.0.0/16',
  enableFlowLogs: true,
  enableMonitoring: true,
  // Add stack tags
  tags: {
    Project: 'MicroSegmentation',
    Environment: 'Production',
    Owner: 'SecurityTeam'
  }
});

// Synthesize the CloudFormation template
app.synth();