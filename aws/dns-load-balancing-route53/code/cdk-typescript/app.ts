#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Interface for DNS Load Balancing Stack properties
 */
interface DnsLoadBalancingStackProps extends cdk.StackProps {
  domainName: string;
  regions: string[];
  enableHealthChecks: boolean;
  healthCheckPath: string;
  snsTopicArn?: string;
}

/**
 * Interface for regional infrastructure properties
 */
interface RegionalInfrastructureProps {
  stackName: string;
  region: string;
  vpcCidr: string;
  enableNatGateway: boolean;
}

/**
 * Regional Infrastructure Stack
 * Creates VPC, ALB, and supporting infrastructure in a specific region
 */
class RegionalInfrastructureStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly applicationLoadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;
  public readonly loadBalancerDnsName: string;

  constructor(scope: Construct, id: string, props: RegionalInfrastructureProps & cdk.StackProps) {
    super(scope, id, props);

    // Create VPC with public and private subnets across multiple AZs
    this.vpc = new ec2.Vpc(this, 'VPC', {
      cidr: props.vpcCidr,
      maxAzs: 3,
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
        },
      ],
      natGateways: props.enableNatGateway ? 1 : 0,
    });

    // Security group for ALB
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP and HTTPS traffic
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic'
    );
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic'
    );

    // Create Application Load Balancer
    this.applicationLoadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    // Create target group for health checks
    this.targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      vpc: this.vpc,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200,301,302',
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
      },
    });

    // Create HTTP listener
    this.applicationLoadBalancer.addListener('HTTPListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [this.targetGroup],
    });

    // Store the DNS name for Route 53 configuration
    this.loadBalancerDnsName = this.applicationLoadBalancer.loadBalancerDnsName;

    // Add tags for resource organization
    cdk.Tags.of(this).add('Component', 'RegionalInfrastructure');
    cdk.Tags.of(this).add('Region', props.region);
    cdk.Tags.of(this).add('Environment', 'Production');

    // Outputs
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${props.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerArn', {
      value: this.applicationLoadBalancer.loadBalancerArn,
      description: 'Application Load Balancer ARN',
      exportName: `${props.stackName}-LoadBalancerArn`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.loadBalancerDnsName,
      description: 'Application Load Balancer DNS Name',
      exportName: `${props.stackName}-LoadBalancerDnsName`,
    });

    new cdk.CfnOutput(this, 'TargetGroupArn', {
      value: this.targetGroup.targetGroupArn,
      description: 'Target Group ARN',
      exportName: `${props.stackName}-TargetGroupArn`,
    });
  }
}

/**
 * DNS Load Balancing Stack
 * Creates Route 53 hosted zone, health checks, and DNS routing policies
 */
class DnsLoadBalancingStack extends cdk.Stack {
  public readonly hostedZone: route53.PublicHostedZone;
  public readonly healthChecks: route53.CfnHealthCheck[];
  public readonly snsTopicForAlerts: sns.Topic;

  constructor(scope: Construct, id: string, props: DnsLoadBalancingStackProps) {
    super(scope, id, props);

    // Create hosted zone for the domain
    this.hostedZone = new route53.PublicHostedZone(this, 'HostedZone', {
      zoneName: props.domainName,
      comment: `Hosted zone for DNS-based load balancing - ${props.domainName}`,
    });

    // Create SNS topic for health check notifications
    this.snsTopicForAlerts = new sns.Topic(this, 'HealthCheckAlerts', {
      displayName: 'Route 53 Health Check Alerts',
      topicName: 'route53-health-alerts',
    });

    // Initialize health checks array
    this.healthChecks = [];

    // Create health checks for each region (placeholder - will be configured after ALBs are created)
    if (props.enableHealthChecks) {
      props.regions.forEach((region, index) => {
        const healthCheck = new route53.CfnHealthCheck(this, `HealthCheck${region.replace('-', '')}`, {
          type: 'HTTP',
          resourcePath: props.healthCheckPath,
          fullyQualifiedDomainName: `placeholder-${region}.elb.amazonaws.com`, // Will be updated with actual ALB DNS
          port: 80,
          requestInterval: 30,
          failureThreshold: 3,
          tags: [
            {
              key: 'Name',
              value: `Health Check - ${region}`,
            },
            {
              key: 'Region',
              value: region,
            },
            {
              key: 'Environment',
              value: 'Production',
            },
          ],
        });

        this.healthChecks.push(healthCheck);
      });
    }

    // Add tags for resource organization
    cdk.Tags.of(this).add('Component', 'DNSLoadBalancing');
    cdk.Tags.of(this).add('Environment', 'Production');

    // Outputs
    new cdk.CfnOutput(this, 'HostedZoneId', {
      value: this.hostedZone.hostedZoneId,
      description: 'Route 53 Hosted Zone ID',
      exportName: `${this.stackName}-HostedZoneId`,
    });

    new cdk.CfnOutput(this, 'HostedZoneNameServers', {
      value: cdk.Fn.join(',', this.hostedZone.hostedZoneNameServers || []),
      description: 'Route 53 Hosted Zone Name Servers',
      exportName: `${this.stackName}-NameServers`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopicForAlerts.topicArn,
      description: 'SNS Topic ARN for health check alerts',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'DomainName', {
      value: props.domainName,
      description: 'Domain name for DNS load balancing',
      exportName: `${this.stackName}-DomainName`,
    });
  }

  /**
   * Create DNS routing policies after regional infrastructure is deployed
   */
  public createRoutingPolicies(regionalStacks: { [region: string]: RegionalInfrastructureStack }): void {
    const subdomain = `api.${this.hostedZone.zoneName}`;
    const regions = Object.keys(regionalStacks);

    // Update health checks with actual ALB DNS names
    regions.forEach((region, index) => {
      if (this.healthChecks[index]) {
        const healthCheck = this.healthChecks[index];
        // Note: In a real implementation, you would update the health check
        // with the actual ALB DNS name from the regional stack
        const cfnHealthCheck = healthCheck.node.defaultChild as route53.CfnHealthCheck;
        cfnHealthCheck.fullyQualifiedDomainName = regionalStacks[region].loadBalancerDnsName;
      }
    });

    // Create weighted routing records
    this.createWeightedRoutingRecords(subdomain, regionalStacks);

    // Create latency-based routing records
    this.createLatencyBasedRoutingRecords(subdomain, regionalStacks);

    // Create geolocation routing records
    this.createGeolocationRoutingRecords(subdomain, regionalStacks);

    // Create failover routing records
    this.createFailoverRoutingRecords(subdomain, regionalStacks);

    // Create multivalue answer routing records
    this.createMultivalueRoutingRecords(subdomain, regionalStacks);
  }

  /**
   * Create weighted routing records for traffic distribution
   */
  private createWeightedRoutingRecords(
    subdomain: string,
    regionalStacks: { [region: string]: RegionalInfrastructureStack }
  ): void {
    const regions = Object.keys(regionalStacks);
    const weights = [50, 30, 20]; // Primary, Secondary, Tertiary weights

    regions.forEach((region, index) => {
      const weight = weights[index] || 10; // Default weight for additional regions
      const healthCheckId = this.healthChecks[index]?.ref;

      new route53.CfnRecordSet(this, `WeightedRecord${region.replace('-', '')}`, {
        hostedZoneId: this.hostedZone.hostedZoneId,
        name: subdomain,
        type: 'A',
        setIdentifier: `${region}-Weighted`,
        weight: weight,
        ttl: 60,
        resourceRecords: ['1.2.3.4'], // Placeholder IP - in production, use ALB IPs or ALIAS records
        healthCheckId: healthCheckId,
      });
    });
  }

  /**
   * Create latency-based routing records for performance optimization
   */
  private createLatencyBasedRoutingRecords(
    subdomain: string,
    regionalStacks: { [region: string]: RegionalInfrastructureStack }
  ): void {
    const latencySubdomain = `latency.${subdomain}`;
    const regions = Object.keys(regionalStacks);

    regions.forEach((region, index) => {
      const healthCheckId = this.healthChecks[index]?.ref;

      new route53.CfnRecordSet(this, `LatencyRecord${region.replace('-', '')}`, {
        hostedZoneId: this.hostedZone.hostedZoneId,
        name: latencySubdomain,
        type: 'A',
        setIdentifier: `${region}-Latency`,
        region: region,
        ttl: 60,
        resourceRecords: ['1.2.3.4'], // Placeholder IP
        healthCheckId: healthCheckId,
      });
    });
  }

  /**
   * Create geolocation routing records for regional compliance
   */
  private createGeolocationRoutingRecords(
    subdomain: string,
    regionalStacks: { [region: string]: RegionalInfrastructureStack }
  ): void {
    const geoSubdomain = `geo.${subdomain}`;
    const regions = Object.keys(regionalStacks);

    // Define continent mappings for regions
    const regionToContinentMap: { [region: string]: string } = {
      'us-east-1': 'NA',
      'us-west-2': 'NA',
      'eu-west-1': 'EU',
      'eu-central-1': 'EU',
      'ap-southeast-1': 'AS',
      'ap-northeast-1': 'AS',
    };

    regions.forEach((region, index) => {
      const continent = regionToContinentMap[region];
      const healthCheckId = this.healthChecks[index]?.ref;

      if (continent) {
        new route53.CfnRecordSet(this, `GeoRecord${region.replace('-', '')}`, {
          hostedZoneId: this.hostedZone.hostedZoneId,
          name: geoSubdomain,
          type: 'A',
          setIdentifier: `${continent}-Geo`,
          geoLocation: {
            continentCode: continent,
          },
          ttl: 60,
          resourceRecords: ['1.2.3.4'], // Placeholder IP
          healthCheckId: healthCheckId,
        });
      }
    });

    // Create default geolocation record (fallback)
    const primaryRegion = regions[0];
    const primaryHealthCheckId = this.healthChecks[0]?.ref;

    new route53.CfnRecordSet(this, 'DefaultGeoRecord', {
      hostedZoneId: this.hostedZone.hostedZoneId,
      name: geoSubdomain,
      type: 'A',
      setIdentifier: 'Default-Geo',
      geoLocation: {
        countryCode: '*',
      },
      ttl: 60,
      resourceRecords: ['1.2.3.4'], // Placeholder IP
      healthCheckId: primaryHealthCheckId,
    });
  }

  /**
   * Create failover routing records for disaster recovery
   */
  private createFailoverRoutingRecords(
    subdomain: string,
    regionalStacks: { [region: string]: RegionalInfrastructureStack }
  ): void {
    const failoverSubdomain = `failover.${subdomain}`;
    const regions = Object.keys(regionalStacks);

    if (regions.length >= 2) {
      // Primary failover record
      const primaryHealthCheckId = this.healthChecks[0]?.ref;
      new route53.CfnRecordSet(this, 'PrimaryFailoverRecord', {
        hostedZoneId: this.hostedZone.hostedZoneId,
        name: failoverSubdomain,
        type: 'A',
        setIdentifier: 'Primary-Failover',
        failover: 'PRIMARY',
        ttl: 60,
        resourceRecords: ['1.2.3.4'], // Placeholder IP
        healthCheckId: primaryHealthCheckId,
      });

      // Secondary failover record
      const secondaryHealthCheckId = this.healthChecks[1]?.ref;
      new route53.CfnRecordSet(this, 'SecondaryFailoverRecord', {
        hostedZoneId: this.hostedZone.hostedZoneId,
        name: failoverSubdomain,
        type: 'A',
        setIdentifier: 'Secondary-Failover',
        failover: 'SECONDARY',
        ttl: 60,
        resourceRecords: ['5.6.7.8'], // Placeholder IP
        healthCheckId: secondaryHealthCheckId,
      });
    }
  }

  /**
   * Create multivalue answer routing records for DNS-level load balancing
   */
  private createMultivalueRoutingRecords(
    subdomain: string,
    regionalStacks: { [region: string]: RegionalInfrastructureStack }
  ): void {
    const multivalueSubdomain = `multivalue.${subdomain}`;
    const regions = Object.keys(regionalStacks);
    const placeholderIps = ['1.2.3.4', '5.6.7.8', '9.10.11.12'];

    regions.forEach((region, index) => {
      const healthCheckId = this.healthChecks[index]?.ref;
      const placeholderIp = placeholderIps[index] || '192.168.1.1';

      new route53.CfnRecordSet(this, `MultivalueRecord${region.replace('-', '')}`, {
        hostedZoneId: this.hostedZone.hostedZoneId,
        name: multivalueSubdomain,
        type: 'A',
        setIdentifier: `${region}-Multivalue`,
        ttl: 60,
        resourceRecords: [placeholderIp],
        healthCheckId: healthCheckId,
      });
    });
  }
}

/**
 * Main application class
 * Orchestrates the deployment of regional infrastructure and DNS load balancing
 */
class DnsLoadBalancingApplication extends Construct {
  constructor(scope: Construct, id: string) {
    super(scope, id);

    // Configuration
    const domainName = process.env.DOMAIN_NAME || 'example.com';
    const regions = (process.env.REGIONS || 'us-east-1,eu-west-1,ap-southeast-1').split(',');
    const enableHealthChecks = process.env.ENABLE_HEALTH_CHECKS !== 'false';
    const healthCheckPath = process.env.HEALTH_CHECK_PATH || '/health';

    // Regional infrastructure stacks
    const regionalStacks: { [region: string]: RegionalInfrastructureStack } = {};
    const vpcCidrs = ['10.0.0.0/16', '10.1.0.0/16', '10.2.0.0/16'];

    regions.forEach((region, index) => {
      const vpcCidr = vpcCidrs[index] || `10.${index + 3}.0.0/16`;
      
      regionalStacks[region] = new RegionalInfrastructureStack(scope, `RegionalInfra${region.replace('-', '')}`, {
        stackName: `dns-lb-regional-${region}`,
        region: region,
        vpcCidr: vpcCidr,
        enableNatGateway: false, // Disable NAT Gateway for cost optimization in demo
        env: {
          region: region,
        },
      });
    });

    // DNS load balancing stack
    const dnsStack = new DnsLoadBalancingStack(scope, 'DnsLoadBalancing', {
      domainName: domainName,
      regions: regions,
      enableHealthChecks: enableHealthChecks,
      healthCheckPath: healthCheckPath,
      env: {
        region: regions[0], // Deploy Route 53 resources in primary region
      },
    });

    // Configure routing policies after regional stacks are created
    dnsStack.createRoutingPolicies(regionalStacks);

    // Add dependencies to ensure proper deployment order
    Object.values(regionalStacks).forEach(stack => {
      dnsStack.addDependency(stack);
    });
  }
}

// CDK App initialization
const app = new cdk.App();

// Create the DNS load balancing application
new DnsLoadBalancingApplication(app, 'DnsLoadBalancingApp');

// Add global tags
cdk.Tags.of(app).add('Project', 'DNSLoadBalancing');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('ManagedBy', 'CDK');

app.synth();