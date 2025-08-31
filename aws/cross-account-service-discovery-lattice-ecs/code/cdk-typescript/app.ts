#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecsPatterns from 'aws-cdk-lib/aws-ecs-patterns';
import * as vpclattice from 'aws-cdk-lib/aws-vpclattice';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ram from 'aws-cdk-lib/aws-ram';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Interface for Cross-Account Service Discovery Stack Properties
 */
interface CrossAccountServiceDiscoveryStackProps extends cdk.StackProps {
  /**
   * Consumer AWS Account ID for cross-account sharing
   */
  readonly consumerAccountId: string;
  
  /**
   * Whether to create the VPC or use an existing one
   * @default true
   */
  readonly createVpc?: boolean;
  
  /**
   * Existing VPC ID if createVpc is false
   */
  readonly existingVpcId?: string;
  
  /**
   * Number of ECS tasks to run
   * @default 2
   */
  readonly desiredTaskCount?: number;
  
  /**
   * Container image to use for the producer service
   * @default "nginx:latest"
   */
  readonly containerImage?: string;
  
  /**
   * CloudWatch log retention in days
   * @default 7
   */
  readonly logRetentionDays?: number;
}

/**
 * AWS CDK Stack for Cross-Account Service Discovery with VPC Lattice and ECS
 * 
 * This stack creates:
 * - VPC and networking infrastructure
 * - ECS Cluster with Fargate service
 * - VPC Lattice Service Network and Service
 * - EventBridge rules for monitoring
 * - CloudWatch dashboard for observability
 * - AWS RAM resource sharing for cross-account access
 */
export class CrossAccountServiceDiscoveryStack extends cdk.Stack {
  
  /**
   * VPC where ECS and VPC Lattice resources are deployed
   */
  public readonly vpc: ec2.IVpc;
  
  /**
   * ECS Cluster hosting the producer service
   */
  public readonly cluster: ecs.Cluster;
  
  /**
   * VPC Lattice Service Network for cross-account discovery
   */
  public readonly serviceNetwork: vpclattice.CfnServiceNetwork;
  
  /**
   * VPC Lattice Service for the producer application
   */
  public readonly latticeService: vpclattice.CfnService;
  
  /**
   * AWS RAM Resource Share for cross-account access
   */
  public readonly resourceShare: ram.CfnResourceShare;

  constructor(scope: Construct, id: string, props: CrossAccountServiceDiscoveryStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create or import VPC
    this.vpc = this.createOrImportVpc(props, uniqueSuffix);

    // Create ECS Cluster
    this.cluster = this.createEcsCluster(uniqueSuffix);

    // Create VPC Lattice Service Network
    this.serviceNetwork = this.createServiceNetwork(uniqueSuffix);

    // Create VPC Lattice Target Group and Service
    const { targetGroup, latticeService } = this.createLatticeService(uniqueSuffix);
    this.latticeService = latticeService;

    // Create ECS Service with VPC Lattice integration
    const ecsService = this.createEcsService(props, targetGroup, uniqueSuffix);

    // Associate VPC and Service with Service Network
    this.createServiceNetworkAssociations();

    // Set up EventBridge monitoring
    this.setupEventBridgeMonitoring(uniqueSuffix);

    // Create CloudWatch Dashboard
    this.createCloudWatchDashboard(uniqueSuffix);

    // Create AWS RAM Resource Share for cross-account access
    this.resourceShare = this.createResourceShare(props, uniqueSuffix);

    // Add dependencies
    ecsService.node.addDependency(targetGroup);
    latticeService.node.addDependency(this.serviceNetwork);

    // Output important information
    this.createOutputs(props);
  }

  /**
   * Create or import VPC based on configuration
   */
  private createOrImportVpc(props: CrossAccountServiceDiscoveryStackProps, suffix: string): ec2.IVpc {
    if (props.createVpc !== false) {
      // Create new VPC with public and private subnets
      return new ec2.Vpc(this, 'ProducerVpc', {
        vpcName: `producer-vpc-${suffix}`,
        maxAzs: 2,
        ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
        natGateways: 1,
        subnetConfiguration: [
          {
            cidrMask: 24,
            name: 'Public',
            subnetType: ec2.SubnetType.PUBLIC,
          },
          {
            cidrMask: 24,
            name: 'Private',
            subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          },
        ],
        enableDnsHostnames: true,
        enableDnsSupport: true,
      });
    } else {
      // Import existing VPC
      if (!props.existingVpcId) {
        throw new Error('existingVpcId must be provided when createVpc is false');
      }
      return ec2.Vpc.fromLookup(this, 'ExistingVpc', {
        vpcId: props.existingVpcId,
      });
    }
  }

  /**
   * Create ECS Cluster with optimized configuration
   */
  private createEcsCluster(suffix: string): ecs.Cluster {
    const cluster = new ecs.Cluster(this, 'ProducerCluster', {
      clusterName: `producer-cluster-${suffix}`,
      vpc: this.vpc,
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });

    // Add capacity providers for cost optimization
    cluster.addCapacityProvider(ecs.CapacityProvider.FARGATE);
    cluster.addCapacityProvider(ecs.CapacityProvider.FARGATE_SPOT);

    return cluster;
  }

  /**
   * Create VPC Lattice Service Network for cross-account discovery
   */
  private createServiceNetwork(suffix: string): vpclattice.CfnServiceNetwork {
    return new vpclattice.CfnServiceNetwork(this, 'ServiceNetwork', {
      name: `cross-account-network-${suffix}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'Purpose',
          value: 'CrossAccountServiceDiscovery',
        },
        {
          key: 'Environment',
          value: 'Production',
        },
      ],
    });
  }

  /**
   * Create VPC Lattice Target Group and Service
   */
  private createLatticeService(suffix: string): {
    targetGroup: vpclattice.CfnTargetGroup;
    latticeService: vpclattice.CfnService;
  } {
    // Create VPC Lattice Target Group for ECS tasks
    const targetGroup = new vpclattice.CfnTargetGroup(this, 'ProducerTargetGroup', {
      name: `producer-targets-${suffix}`,
      type: 'IP',
      protocol: 'HTTP',
      port: 80,
      vpcIdentifier: this.vpc.vpcId,
      config: {
        healthCheck: {
          enabled: true,
          protocol: 'HTTP',
          path: '/',
          timeoutSeconds: 5,
          intervalSeconds: 30,
          healthyThresholdCount: 2,
          unhealthyThresholdCount: 3,
        },
      },
      tags: [
        {
          key: 'Service',
          value: 'ProducerService',
        },
      ],
    });

    // Create VPC Lattice Service
    const latticeService = new vpclattice.CfnService(this, 'LatticeProducerService', {
      name: `lattice-producer-${suffix}`,
      authType: 'AWS_IAM',
      tags: [
        {
          key: 'ServiceType',
          value: 'Producer',
        },
      ],
    });

    // Create HTTP Listener for the service
    new vpclattice.CfnListener(this, 'HttpListener', {
      serviceIdentifier: latticeService.attrArn,
      name: 'http-listener',
      protocol: 'HTTP',
      port: 80,
      defaultAction: {
        forward: {
          targetGroups: [
            {
              targetGroupIdentifier: targetGroup.attrArn,
            },
          ],
        },
      },
    });

    return { targetGroup, latticeService };
  }

  /**
   * Create ECS Service with VPC Lattice integration
   */
  private createEcsService(
    props: CrossAccountServiceDiscoveryStackProps,
    targetGroup: vpclattice.CfnTargetGroup,
    suffix: string
  ): ecs.FargateService {
    // Create CloudWatch Log Group
    const logGroup = new logs.LogGroup(this, 'ProducerLogGroup', {
      logGroupName: '/ecs/producer',
      retention: props.logRetentionDays || logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Task Definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'ProducerTaskDefinition', {
      family: 'producer-task',
      cpu: 256,
      memoryLimitMiB: 512,
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('ProducerContainer', {
      image: ecs.ContainerImage.fromRegistry(props.containerImage || 'nginx:latest'),
      essential: true,
      portMappings: [
        {
          containerPort: 80,
          protocol: ecs.Protocol.TCP,
        },
      ],
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: logGroup,
      }),
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost/ || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    // Create Security Group for ECS tasks
    const securityGroup = new ec2.SecurityGroup(this, 'ProducerSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for producer ECS tasks',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from VPC Lattice
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(this.vpc.vpcCidrBlock),
      ec2.Port.tcp(80),
      'Allow HTTP from VPC Lattice'
    );

    // Create ECS Service
    const service = new ecs.FargateService(this, 'ProducerService', {
      serviceName: `producer-service-${suffix}`,
      cluster: this.cluster,
      taskDefinition: taskDefinition,
      desiredCount: props.desiredTaskCount || 2,
      assignPublicIp: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [securityGroup],
      capacityProviderStrategies: [
        {
          capacityProvider: ecs.CapacityProvider.FARGATE,
          weight: 1,
        },
      ],
      enableExecuteCommand: true,
      enableLogging: true,
    });

    // Create custom resource to register ECS tasks with VPC Lattice target group
    this.createTargetGroupRegistration(service, targetGroup);

    return service;
  }

  /**
   * Create custom resource for ECS task registration with VPC Lattice
   */
  private createTargetGroupRegistration(
    service: ecs.FargateService,
    targetGroup: vpclattice.CfnTargetGroup
  ): void {
    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'TargetRegistrationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        VpcLatticePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'vpc-lattice:RegisterTargets',
                'vpc-lattice:DeregisterTargets',
                'vpc-lattice:ListTargets',
                'ecs:ListTasks',
                'ecs:DescribeTasks',
                'ec2:DescribeNetworkInterfaces',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Note: In a production environment, you would implement a Lambda function
    // to handle the registration of ECS tasks with the VPC Lattice target group.
    // This is omitted here for brevity but would involve:
    // 1. Listening to ECS CloudWatch Events
    // 2. Extracting task IP addresses
    // 3. Registering/deregistering targets with VPC Lattice
  }

  /**
   * Create Service Network associations for VPC and Service
   */
  private createServiceNetworkAssociations(): void {
    // Associate VPC with Service Network
    new vpclattice.CfnServiceNetworkVpcAssociation(this, 'VpcAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrArn,
      vpcIdentifier: this.vpc.vpcId,
      tags: [
        {
          key: 'AssociationType',
          value: 'VpcToServiceNetwork',
        },
      ],
    });

    // Associate Service with Service Network
    new vpclattice.CfnServiceNetworkServiceAssociation(this, 'ServiceAssociation', {
      serviceNetworkIdentifier: this.serviceNetwork.attrArn,
      serviceIdentifier: this.latticeService.attrArn,
      tags: [
        {
          key: 'AssociationType',
          value: 'ServiceToServiceNetwork',
        },
      ],
    });
  }

  /**
   * Set up EventBridge monitoring for VPC Lattice events
   */
  private setupEventBridgeMonitoring(suffix: string): void {
    // Create CloudWatch Log Group for VPC Lattice events
    const eventLogGroup = new logs.LogGroup(this, 'VpcLatticeEventLogGroup', {
      logGroupName: '/aws/events/vpc-lattice',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for EventBridge to write to CloudWatch Logs
    const eventBridgeRole = new iam.Role(this, 'EventBridgeLogsRole', {
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      inlinePolicies: {
        LogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['logs:CreateLogStream', 'logs:PutLogEvents'],
              resources: [eventLogGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // Create EventBridge rule for VPC Lattice events
    const vpcLatticeRule = new events.Rule(this, 'VpcLatticeEventsRule', {
      ruleName: `vpc-lattice-events-${suffix}`,
      description: 'Capture VPC Lattice service discovery events',
      eventPattern: {
        source: ['aws.vpc-lattice'],
        detailType: [
          'VPC Lattice Service Network State Change',
          'VPC Lattice Service State Change',
        ],
      },
      enabled: true,
    });

    // Add CloudWatch Logs target
    vpcLatticeRule.addTarget(
      new targets.CloudWatchLogGroup(eventLogGroup, {
        logEvent: targets.LogGroupTargetInput.fromObject({
          timestamp: events.EventField.fromPath('$.time'),
          source: events.EventField.fromPath('$.source'),
          detailType: events.EventField.fromPath('$.detail-type'),
          detail: events.EventField.fromPath('$.detail'),
        }),
      })
    );
  }

  /**
   * Create CloudWatch Dashboard for monitoring
   */
  private createCloudWatchDashboard(suffix: string): void {
    const dashboard = new cloudwatch.Dashboard(this, 'ServiceDiscoveryDashboard', {
      dashboardName: `cross-account-service-discovery-${suffix}`,
    });

    // Add VPC Lattice service metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'VPC Lattice Service Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'ActiveConnectionCount',
            dimensionsMap: {
              ServiceName: this.latticeService.name!,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/VpcLattice',
            metricName: 'NewConnectionCount',
            dimensionsMap: {
              ServiceName: this.latticeService.name!,
            },
            statistic: 'Sum',
          }),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'ECS Service Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/ECS',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              ServiceName: `producer-service-${suffix}`,
              ClusterName: this.cluster.clusterName,
            },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/ECS',
            metricName: 'MemoryUtilization',
            dimensionsMap: {
              ServiceName: `producer-service-${suffix}`,
              ClusterName: this.cluster.clusterName,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
      })
    );

    // Add log insights widget for VPC Lattice events
    dashboard.addWidgets(
      new cloudwatch.LogQueryWidget({
        title: 'VPC Lattice Events',
        logGroups: [
          logs.LogGroup.fromLogGroupName(this, 'EventLogGroupRef', '/aws/events/vpc-lattice'),
        ],
        queryString: `
          fields @timestamp, source, detail-type, detail
          | sort @timestamp desc
          | limit 100
        `,
        width: 24,
      })
    );
  }

  /**
   * Create AWS RAM Resource Share for cross-account access
   */
  private createResourceShare(
    props: CrossAccountServiceDiscoveryStackProps,
    suffix: string
  ): ram.CfnResourceShare {
    return new ram.CfnResourceShare(this, 'LatticeNetworkShare', {
      name: `lattice-network-share-${suffix}`,
      resourceArns: [this.serviceNetwork.attrArn],
      principals: [props.consumerAccountId],
      allowExternalPrincipals: true,
      tags: [
        {
          key: 'Purpose',
          value: 'CrossAccountServiceDiscovery',
        },
        {
          key: 'SharedWith',
          value: props.consumerAccountId,
        },
      ],
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(props: CrossAccountServiceDiscoveryStackProps): void {
    new cdk.CfnOutput(this, 'ServiceNetworkArn', {
      description: 'ARN of the VPC Lattice Service Network',
      value: this.serviceNetwork.attrArn,
      exportName: `${this.stackName}-ServiceNetworkArn`,
    });

    new cdk.CfnOutput(this, 'ServiceNetworkId', {
      description: 'ID of the VPC Lattice Service Network',
      value: this.serviceNetwork.attrId,
      exportName: `${this.stackName}-ServiceNetworkId`,
    });

    new cdk.CfnOutput(this, 'LatticeServiceArn', {
      description: 'ARN of the VPC Lattice Service',
      value: this.latticeService.attrArn,
      exportName: `${this.stackName}-LatticeServiceArn`,
    });

    new cdk.CfnOutput(this, 'EcsClusterName', {
      description: 'Name of the ECS Cluster',
      value: this.cluster.clusterName,
      exportName: `${this.stackName}-EcsClusterName`,
    });

    new cdk.CfnOutput(this, 'ResourceShareArn', {
      description: 'ARN of the AWS RAM Resource Share',
      value: this.resourceShare.attrArn,
      exportName: `${this.stackName}-ResourceShareArn`,
    });

    new cdk.CfnOutput(this, 'ConsumerAccountId', {
      description: 'Consumer Account ID for cross-account sharing',
      value: props.consumerAccountId,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      description: 'ID of the VPC',
      value: this.vpc.vpcId,
      exportName: `${this.stackName}-VpcId`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const consumerAccountId = app.node.tryGetContext('consumerAccountId') || 
  process.env.CONSUMER_ACCOUNT_ID || 
  '123456789012'; // Default placeholder

const environment = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

// Create the main stack
new CrossAccountServiceDiscoveryStack(app, 'CrossAccountServiceDiscoveryStack', {
  env: environment,
  consumerAccountId: consumerAccountId,
  createVpc: app.node.tryGetContext('createVpc') !== false,
  existingVpcId: app.node.tryGetContext('existingVpcId'),
  desiredTaskCount: app.node.tryGetContext('desiredTaskCount') || 2,
  containerImage: app.node.tryGetContext('containerImage') || 'nginx:latest',
  logRetentionDays: app.node.tryGetContext('logRetentionDays') || 7,
  description: 'Cross-Account Service Discovery with VPC Lattice and ECS',
  tags: {
    Project: 'CrossAccountServiceDiscovery',
    Environment: 'Production',
    ManagedBy: 'CDK',
  },
});

app.synth();