#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as route53resolver from 'aws-cdk-lib/aws-route53resolver';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Interface defining VPC configuration for each region
 */
interface VpcConfig {
  readonly region: string;
  readonly cidrBlock: string;
  readonly role: 'hub' | 'spoke';
  readonly name: string;
}

/**
 * Interface defining VPC peering connection configuration
 */
interface PeeringConfig {
  readonly sourceVpcName: string;
  readonly targetVpcName: string;
  readonly sourceRegion: string;
  readonly targetRegion: string;
  readonly name: string;
}

/**
 * Stack for creating VPCs with subnets in a specific region
 */
class VpcStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly subnet: ec2.Subnet;

  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    vpcConfig: VpcConfig;
  }) {
    super(scope, id, props);

    // Create VPC with the specified CIDR block
    this.vpc = new ec2.Vpc(this, 'Vpc', {
      ipAddresses: ec2.IpAddresses.cidr(props.vpcConfig.cidrBlock),
      maxAzs: 1, // Use only one AZ for simplicity in this demo
      subnetConfiguration: [], // We'll create subnets manually for more control
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create a subnet for testing and applications
    this.subnet = new ec2.Subnet(this, 'TestSubnet', {
      vpc: this.vpc,
      cidrBlock: this.calculateSubnetCidr(props.vpcConfig.cidrBlock),
      availabilityZone: cdk.Stack.of(this).availabilityZones[0],
    });

    // Tag resources appropriately
    cdk.Tags.of(this.vpc).add('Name', `${props.vpcConfig.name}-vpc`);
    cdk.Tags.of(this.vpc).add('Region', props.vpcConfig.region);
    cdk.Tags.of(this.vpc).add('Role', props.vpcConfig.role);
    cdk.Tags.of(this.subnet).add('Name', `${props.vpcConfig.name}-subnet`);

    // Output VPC information
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: `VPC ID for ${props.vpcConfig.name}`,
      exportName: `${id}-VpcId`,
    });

    new cdk.CfnOutput(this, 'SubnetId', {
      value: this.subnet.subnetId,
      description: `Subnet ID for ${props.vpcConfig.name}`,
      exportName: `${id}-SubnetId`,
    });
  }

  /**
   * Calculate subnet CIDR from VPC CIDR
   * Takes the first /24 subnet from the VPC CIDR
   */
  private calculateSubnetCidr(vpcCidr: string): string {
    const [baseIp] = vpcCidr.split('/');
    const parts = baseIp.split('.');
    return `${parts[0]}.${parts[1]}.${parts[2]}.0/24`;
  }
}

/**
 * Stack for creating VPC peering connections between regions
 */
class VpcPeeringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    peeringConfigs: PeeringConfig[];
    vpcStacks: { [key: string]: VpcStack };
  }) {
    super(scope, id, props);

    // Create VPC peering connections
    props.peeringConfigs.forEach((config, index) => {
      const sourceVpc = props.vpcStacks[config.sourceVpcName].vpc;
      const targetVpcId = cdk.Fn.importValue(`${config.targetVpcName}-VpcId`);

      // Create cross-region VPC peering connection
      const peeringConnection = new ec2.CfnVPCPeeringConnection(this, `PeeringConnection${index}`, {
        vpcId: sourceVpc.vpcId,
        peerVpcId: targetVpcId,
        peerRegion: config.targetRegion,
        tags: [
          {
            key: 'Name',
            value: config.name,
          },
        ],
      });

      // Output peering connection ID
      new cdk.CfnOutput(this, `PeeringConnectionId${index}`, {
        value: peeringConnection.ref,
        description: `Peering connection ID for ${config.name}`,
        exportName: `${id}-PeeringConnection${index}`,
      });
    });
  }
}

/**
 * Stack for configuring complex routing tables with transit routing
 */
class RoutingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    vpcStack: VpcStack;
    routes: Array<{
      destinationCidr: string;
      peeringConnectionId: string;
      description: string;
    }>;
  }) {
    super(scope, id, props);

    const vpc = props.vpcStack.vpc;

    // Get the default route table
    const routeTable = vpc.node.findChild('DefaultRouteTable') as ec2.RouteTable;

    // Add routes for complex routing scenarios
    props.routes.forEach((route, index) => {
      new ec2.CfnRoute(this, `Route${index}`, {
        routeTableId: routeTable.routeTableId,
        destinationCidrBlock: route.destinationCidr,
        vpcPeeringConnectionId: route.peeringConnectionId,
      });
    });

    // Output route table information
    new cdk.CfnOutput(this, 'RouteTableId', {
      value: routeTable.routeTableId,
      description: 'Route table ID for complex routing',
      exportName: `${id}-RouteTableId`,
    });
  }
}

/**
 * Stack for Route 53 Resolver configuration
 */
class DnsResolverStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: cdk.StackProps & {
    vpcStacks: { [key: string]: VpcStack };
  }) {
    super(scope, id, props);

    // Create Route 53 Resolver rule for internal domain resolution
    const resolverRule = new route53resolver.CfnResolverRule(this, 'GlobalInternalDomainRule', {
      ruleType: 'FORWARD',
      domainName: 'internal.global.local',
      name: 'global-internal-domain',
      targetIps: [
        {
          ip: '10.0.1.100',
          port: '53',
        },
      ],
      tags: [
        {
          key: 'Name',
          value: 'global-internal-resolver',
        },
      ],
    });

    // Associate resolver rule with VPCs
    Object.entries(props.vpcStacks).forEach(([name, vpcStack], index) => {
      new route53resolver.CfnResolverRuleAssociation(this, `ResolverRuleAssociation${index}`, {
        resolverRuleId: resolverRule.ref,
        vpcId: vpcStack.vpc.vpcId,
      });
    });

    // Create CloudWatch alarm for DNS resolution monitoring
    const alarm = new cloudwatch.Alarm(this, 'DnsQueryFailuresAlarm', {
      alarmName: 'Route53-Resolver-Query-Failures',
      alarmDescription: 'High DNS query failures in Route53 Resolver',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53Resolver',
        metricName: 'QueryCount',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
        dimensionsMap: {
          ResolverRuleId: resolverRule.ref,
        },
      }),
      threshold: 100,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 1,
    });

    // Output resolver rule information
    new cdk.CfnOutput(this, 'ResolverRuleId', {
      value: resolverRule.ref,
      description: 'Route 53 Resolver rule ID',
      exportName: `${id}-ResolverRuleId`,
    });
  }
}

/**
 * Main CDK App for Multi-Region VPC Peering with Complex Routing
 */
class MultiRegionVpcPeeringApp extends Construct {
  constructor(scope: Construct, id: string) {
    super(scope, id);

    // Define VPC configurations for each region
    const vpcConfigs: VpcConfig[] = [
      {
        region: 'us-east-1',
        cidrBlock: '10.0.0.0/16',
        role: 'hub',
        name: 'hub',
      },
      {
        region: 'us-east-1',
        cidrBlock: '10.1.0.0/16',
        role: 'spoke',
        name: 'prod',
      },
      {
        region: 'us-east-1',
        cidrBlock: '10.2.0.0/16',
        role: 'spoke',
        name: 'dev',
      },
      {
        region: 'us-west-2',
        cidrBlock: '10.10.0.0/16',
        role: 'hub',
        name: 'dr-hub',
      },
      {
        region: 'us-west-2',
        cidrBlock: '10.11.0.0/16',
        role: 'spoke',
        name: 'dr-prod',
      },
      {
        region: 'eu-west-1',
        cidrBlock: '10.20.0.0/16',
        role: 'hub',
        name: 'eu-hub',
      },
      {
        region: 'eu-west-1',
        cidrBlock: '10.21.0.0/16',
        role: 'spoke',
        name: 'eu-prod',
      },
      {
        region: 'ap-southeast-1',
        cidrBlock: '10.30.0.0/16',
        role: 'spoke',
        name: 'apac',
      },
    ];

    // Define VPC peering configurations
    const peeringConfigs: PeeringConfig[] = [
      // Inter-region hub-to-hub peering
      {
        sourceVpcName: 'hub',
        targetVpcName: 'dr-hub',
        sourceRegion: 'us-east-1',
        targetRegion: 'us-west-2',
        name: 'hub-to-dr-hub-peering',
      },
      {
        sourceVpcName: 'hub',
        targetVpcName: 'eu-hub',
        sourceRegion: 'us-east-1',
        targetRegion: 'eu-west-1',
        name: 'hub-to-eu-hub-peering',
      },
      {
        sourceVpcName: 'dr-hub',
        targetVpcName: 'eu-hub',
        sourceRegion: 'us-west-2',
        targetRegion: 'eu-west-1',
        name: 'dr-hub-to-eu-hub-peering',
      },
      // Intra-region hub-to-spoke peering
      {
        sourceVpcName: 'hub',
        targetVpcName: 'prod',
        sourceRegion: 'us-east-1',
        targetRegion: 'us-east-1',
        name: 'hub-to-prod-peering',
      },
      {
        sourceVpcName: 'hub',
        targetVpcName: 'dev',
        sourceRegion: 'us-east-1',
        targetRegion: 'us-east-1',
        name: 'hub-to-dev-peering',
      },
      {
        sourceVpcName: 'dr-hub',
        targetVpcName: 'dr-prod',
        sourceRegion: 'us-west-2',
        targetRegion: 'us-west-2',
        name: 'dr-hub-to-dr-prod-peering',
      },
      {
        sourceVpcName: 'eu-hub',
        targetVpcName: 'eu-prod',
        sourceRegion: 'eu-west-1',
        targetRegion: 'eu-west-1',
        name: 'eu-hub-to-eu-prod-peering',
      },
      // Cross-region spoke-to-hub peering
      {
        sourceVpcName: 'apac',
        targetVpcName: 'eu-hub',
        sourceRegion: 'ap-southeast-1',
        targetRegion: 'eu-west-1',
        name: 'apac-to-eu-hub-peering',
      },
    ];

    // Group VPCs by region
    const vpcsByRegion: { [region: string]: VpcConfig[] } = {};
    vpcConfigs.forEach(config => {
      if (!vpcsByRegion[config.region]) {
        vpcsByRegion[config.region] = [];
      }
      vpcsByRegion[config.region].push(config);
    });

    // Create VPC stacks for each region
    const vpcStacks: { [key: string]: VpcStack } = {};
    Object.entries(vpcsByRegion).forEach(([region, configs]) => {
      configs.forEach(config => {
        const stackName = `${config.name}-vpc-${region.replace(/-/g, '')}`;
        vpcStacks[config.name] = new VpcStack(this, stackName, {
          env: { region: config.region },
          vpcConfig: config,
        });
      });
    });

    // Create VPC peering stacks
    const peeringsByRegion: { [region: string]: PeeringConfig[] } = {};
    peeringConfigs.forEach(config => {
      if (!peeringsByRegion[config.sourceRegion]) {
        peeringsByRegion[config.sourceRegion] = [];
      }
      peeringsByRegion[config.sourceRegion].push(config);
    });

    Object.entries(peeringsByRegion).forEach(([region, configs]) => {
      const stackName = `peering-${region.replace(/-/g, '')}`;
      new VpcPeeringStack(this, stackName, {
        env: { region },
        peeringConfigs: configs,
        vpcStacks,
      });
    });

    // Create Route 53 Resolver stack (in primary region)
    new DnsResolverStack(this, 'dns-resolver-useast1', {
      env: { region: 'us-east-1' },
      vpcStacks: {
        hub: vpcStacks['hub'],
        prod: vpcStacks['prod'],
        dev: vpcStacks['dev'],
      },
    });

    // Add comprehensive tagging
    cdk.Tags.of(this).add('Project', 'multi-region-vpc-peering');
    cdk.Tags.of(this).add('Environment', 'production');
    cdk.Tags.of(this).add('Owner', 'network-team');
    cdk.Tags.of(this).add('CostCenter', 'infrastructure');
  }
}

// Create the CDK App
const app = new cdk.App();

// Instantiate the multi-region VPC peering application
new MultiRegionVpcPeeringApp(app, 'MultiRegionVpcPeering');

// Add application-level tags
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Purpose', 'multi-region-networking-demo');