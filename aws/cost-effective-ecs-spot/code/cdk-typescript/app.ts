#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Cost-Effective ECS Cluster Stack
 */
export interface CostEffectiveEcsClusterStackProps extends cdk.StackProps {
  /**
   * The VPC to deploy the cluster into. If not provided, a new VPC will be created.
   */
  readonly vpc?: ec2.IVpc;

  /**
   * The percentage of On-Demand instances to maintain (0-100).
   * The rest will be Spot instances.
   * @default 20
   */
  readonly onDemandPercentage?: number;

  /**
   * The maximum price per hour for Spot instances in USD.
   * @default "0.10"
   */
  readonly spotMaxPrice?: string;

  /**
   * The minimum number of instances in the Auto Scaling Group.
   * @default 1
   */
  readonly minCapacity?: number;

  /**
   * The maximum number of instances in the Auto Scaling Group.
   * @default 10
   */
  readonly maxCapacity?: number;

  /**
   * The desired number of instances in the Auto Scaling Group.
   * @default 3
   */
  readonly desiredCapacity?: number;

  /**
   * The target CPU utilization percentage for service auto scaling.
   * @default 60
   */
  readonly targetCpuUtilization?: number;

  /**
   * The desired number of tasks for the ECS service.
   * @default 6
   */
  readonly serviceDesiredCount?: number;

  /**
   * Environment name for resource tagging.
   * @default "production"
   */
  readonly environment?: string;
}

/**
 * Cost-Effective ECS Cluster Stack using EC2 Spot Instances
 * 
 * This stack creates:
 * - ECS cluster with Container Insights enabled
 * - Auto Scaling Group with mixed instance types and Spot/On-Demand mix
 * - Capacity provider for intelligent scaling
 * - ECS service with resilient configuration
 * - Application auto scaling for dynamic capacity management
 */
export class CostEffectiveEcsClusterStack extends cdk.Stack {
  /**
   * The ECS cluster created by this stack
   */
  public readonly cluster: ecs.Cluster;

  /**
   * The Auto Scaling Group managing the EC2 instances
   */
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;

  /**
   * The capacity provider for the cluster
   */
  public readonly capacityProvider: ecs.AsgCapacityProvider;

  /**
   * The ECS service running the application
   */
  public readonly service: ecs.Ec2Service;

  /**
   * The VPC used by the cluster
   */
  public readonly vpc: ec2.IVpc;

  constructor(scope: Construct, id: string, props: CostEffectiveEcsClusterStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const onDemandPercentage = props.onDemandPercentage ?? 20;
    const spotMaxPrice = props.spotMaxPrice ?? "0.10";
    const minCapacity = props.minCapacity ?? 1;
    const maxCapacity = props.maxCapacity ?? 10;
    const desiredCapacity = props.desiredCapacity ?? 3;
    const targetCpuUtilization = props.targetCpuUtilization ?? 60;
    const serviceDesiredCount = props.serviceDesiredCount ?? 6;
    const environment = props.environment ?? "production";

    // Use provided VPC or create a new one
    this.vpc = props.vpc ?? new ec2.Vpc(this, 'Vpc', {
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
      ],
    });

    // Create ECS cluster with Container Insights enabled
    this.cluster = new ecs.Cluster(this, 'Cluster', {
      clusterName: 'cost-optimized-cluster',
      vpc: this.vpc,
      containerInsights: true,
    });

    // Create IAM role for ECS instances
    const ecsInstanceRole = new iam.Role(this, 'EcsInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
      ],
    });

    // Create security group for ECS instances
    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'EcsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for ECS spot cluster instances',
      allowAllOutbound: true,
    });

    // Allow HTTP and HTTPS traffic
    ecsSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic'
    );
    ecsSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic'
    );

    // Allow dynamic port range for ECS tasks
    ecsSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.tcpRange(32768, 65535),
      'Allow dynamic port range for ECS tasks'
    );

    // Create launch template for mixed instance types
    const launchTemplate = new ec2.LaunchTemplate(this, 'LaunchTemplate', {
      launchTemplateName: 'ecs-spot-template',
      machineImage: ecs.EcsOptimizedImage.amazonLinux2(),
      securityGroup: ecsSecurityGroup,
      role: ecsInstanceRole,
      userData: ec2.UserData.forLinux(),
    });

    // Configure ECS cluster and spot instance draining
    launchTemplate.addUserData(
      `echo ECS_CLUSTER=${this.cluster.clusterName} >> /etc/ecs/ecs.config`,
      'echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config'
    );

    // Create Auto Scaling Group with mixed instance policy
    this.autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'AutoScalingGroup', {
      autoScalingGroupName: 'ecs-spot-asg',
      vpc: this.vpc,
      minCapacity: minCapacity,
      maxCapacity: maxCapacity,
      desiredCapacity: desiredCapacity,
      healthCheck: autoscaling.HealthCheck.ecs({
        grace: cdk.Duration.seconds(300),
      }),
      mixedInstancesPolicy: {
        launchTemplate: launchTemplate,
        launchTemplateOverrides: [
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE) },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.M4, ec2.InstanceSize.LARGE) },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE) },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.C4, ec2.InstanceSize.LARGE) },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.R5, ec2.InstanceSize.LARGE) },
        ],
        instancesDistribution: {
          onDemandAllocationStrategy: autoscaling.OnDemandAllocationStrategy.PRIORITIZED,
          onDemandBaseCapacity: 1,
          onDemandPercentageAboveBaseCapacity: onDemandPercentage,
          spotAllocationStrategy: autoscaling.SpotAllocationStrategy.DIVERSIFIED,
          spotInstancePools: 4,
          spotMaxPrice: spotMaxPrice,
        },
      },
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
    });

    // Add tags to the Auto Scaling Group
    cdk.Tags.of(this.autoScalingGroup).add('Name', 'ECS-Spot-ASG');
    cdk.Tags.of(this.autoScalingGroup).add('Environment', environment);
    cdk.Tags.of(this.autoScalingGroup).add('CostOptimized', 'true');

    // Create capacity provider for the cluster
    this.capacityProvider = new ecs.AsgCapacityProvider(this, 'CapacityProvider', {
      capacityProviderName: 'spot-capacity-provider',
      autoScalingGroup: this.autoScalingGroup,
      enableManagedScaling: true,
      enableManagedTerminationProtection: true,
      targetCapacityPercent: 80,
      minimumScalingStepSize: 1,
      maximumScalingStepSize: 3,
    });

    // Associate capacity provider with cluster
    this.cluster.addAsgCapacityProvider(this.capacityProvider);

    // Create log group for the application
    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: '/ecs/spot-resilient-app',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create task definition for the application
    const taskDefinition = new ecs.Ec2TaskDefinition(this, 'TaskDefinition', {
      family: 'spot-resilient-app',
      networkMode: ecs.NetworkMode.BRIDGE,
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('WebServer', {
      image: ecs.ContainerImage.fromRegistry('public.ecr.aws/docker/library/nginx:latest'),
      memoryLimitMiB: 512,
      cpu: 256,
      essential: true,
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

    // Add port mapping with dynamic port assignment
    container.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // Create ECS service with resilient configuration
    this.service = new ecs.Ec2Service(this, 'Service', {
      serviceName: 'spot-resilient-service',
      cluster: this.cluster,
      taskDefinition: taskDefinition,
      desiredCount: serviceDesiredCount,
      capacityProviderStrategies: [
        {
          capacityProvider: this.capacityProvider.capacityProviderName,
          weight: 1,
          base: 2,
        },
      ],
      deploymentConfiguration: {
        maximumPercent: 200,
        minimumHealthyPercent: 50,
        deploymentCircuitBreaker: {
          enable: true,
          rollback: true,
        },
      },
      enableExecuteCommand: true,
    });

    // Configure service auto scaling
    const scalableTarget = this.service.autoScaleTaskCount({
      minCapacity: 2,
      maxCapacity: 20,
    });

    // Add CPU-based scaling policy
    scalableTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: targetCpuUtilization,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Add memory-based scaling policy
    scalableTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('CostOptimized', 'true');
    cdk.Tags.of(this).add('Project', 'cost-effective-ecs-cluster');

    // Outputs
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'Name of the ECS cluster',
      exportName: 'EcsClusterName',
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      description: 'ARN of the ECS cluster',
      exportName: 'EcsClusterArn',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: this.service.serviceName,
      description: 'Name of the ECS service',
      exportName: 'EcsServiceName',
    });

    new cdk.CfnOutput(this, 'ServiceArn', {
      value: this.service.serviceArn,
      description: 'ARN of the ECS service',
      exportName: 'EcsServiceArn',
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group',
      exportName: 'AutoScalingGroupName',
    });

    new cdk.CfnOutput(this, 'CapacityProviderName', {
      value: this.capacityProvider.capacityProviderName,
      description: 'Name of the capacity provider',
      exportName: 'CapacityProviderName',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'ID of the VPC',
      exportName: 'VpcId',
    });

    new cdk.CfnOutput(this, 'CostOptimizationSummary', {
      value: `Configured for ${100 - onDemandPercentage}% Spot instances with max price $${spotMaxPrice}/hour`,
      description: 'Cost optimization configuration summary',
    });
  }
}

/**
 * CDK App for Cost-Effective ECS Cluster
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'production';
const onDemandPercentage = parseInt(app.node.tryGetContext('onDemandPercentage') || process.env.ON_DEMAND_PERCENTAGE || '20');
const spotMaxPrice = app.node.tryGetContext('spotMaxPrice') || process.env.SPOT_MAX_PRICE || '0.10';
const targetCpuUtilization = parseInt(app.node.tryGetContext('targetCpuUtilization') || process.env.TARGET_CPU_UTILIZATION || '60');

// Create the stack
new CostEffectiveEcsClusterStack(app, 'CostEffectiveEcsClusterStack', {
  description: 'Cost-effective ECS cluster using EC2 Spot instances for 50-70% cost savings',
  environment,
  onDemandPercentage,
  spotMaxPrice,
  targetCpuUtilization,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'cost-effective-ecs-cluster',
    Environment: environment,
    CostOptimized: 'true',
    DeployedBy: 'CDK',
  },
});

app.synth();