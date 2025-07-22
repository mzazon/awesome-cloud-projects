#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';

/**
 * Props for the ServerlessContainersFargateStack
 */
export interface ServerlessContainersFargateStackProps extends cdk.StackProps {
  /**
   * The name prefix for resources
   * @default 'FargateDemo'
   */
  readonly resourcePrefix?: string;
  
  /**
   * The container image URI. If not provided, an ECR repository will be created
   */
  readonly containerImageUri?: string;
  
  /**
   * The container port
   * @default 3000
   */
  readonly containerPort?: number;
  
  /**
   * The desired number of tasks
   * @default 3
   */
  readonly desiredCount?: number;
  
  /**
   * The CPU units for the task
   * @default 256
   */
  readonly cpu?: number;
  
  /**
   * The memory in MB for the task
   * @default 512
   */
  readonly memory?: number;
  
  /**
   * The minimum number of tasks for auto scaling
   * @default 2
   */
  readonly minCapacity?: number;
  
  /**
   * The maximum number of tasks for auto scaling
   * @default 10
   */
  readonly maxCapacity?: number;
  
  /**
   * Whether to enable vulnerability scanning on ECR repository
   * @default true
   */
  readonly enableVulnerabilityScanning?: boolean;
  
  /**
   * Log retention in days
   * @default 7
   */
  readonly logRetentionDays?: logs.RetentionDays;
}

/**
 * CDK Stack for deploying serverless containers with AWS Fargate and Application Load Balancer
 * 
 * This stack creates:
 * - VPC with public and private subnets across multiple AZs
 * - ECR repository for container images
 * - ECS cluster with Fargate capacity providers
 * - Application Load Balancer with target group and health checks
 * - ECS service with auto scaling configuration
 * - IAM roles and security groups with least privilege access
 * - CloudWatch log group for container logging
 */
export class ServerlessContainersFargateStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly cluster: ecs.Cluster;
  public readonly service: ecs.FargateService;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly repository: ecr.Repository;
  public readonly taskDefinition: ecs.FargateTaskDefinition;

  constructor(scope: Construct, id: string, props: ServerlessContainersFargateStackProps = {}) {
    super(scope, id, props);

    // Extract props with defaults
    const {
      resourcePrefix = 'FargateDemo',
      containerImageUri,
      containerPort = 3000,
      desiredCount = 3,
      cpu = 256,
      memory = 512,
      minCapacity = 2,
      maxCapacity = 10,
      enableVulnerabilityScanning = true,
      logRetentionDays = logs.RetentionDays.ONE_WEEK,
    } = props;

    // Create VPC with public and private subnets across multiple AZs
    this.vpc = new ec2.Vpc(this, 'VPC', {
      maxAzs: 3,
      natGateways: 1, // Cost optimization: use single NAT gateway
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

    // Add VPC Flow Logs for security monitoring
    new ec2.FlowLog(this, 'VPCFlowLog', {
      resourceType: ec2.FlowLogResourceType.fromVpc(this.vpc),
      destination: ec2.FlowLogDestination.toCloudWatchLogs(),
    });

    // Create ECR repository for container images
    this.repository = new ecr.Repository(this, 'ECRRepository', {
      repositoryName: `${resourcePrefix.toLowerCase()}-repo`,
      imageScanOnPush: enableVulnerabilityScanning,
      encryption: ecr.RepositoryEncryption.AES_256,
      lifecycleRules: [
        {
          description: 'Keep last 10 images',
          maxImageCount: 10,
          rulePriority: 1,
        },
      ],
    });

    // Create ECS cluster with Fargate capacity providers
    this.cluster = new ecs.Cluster(this, 'ECSCluster', {
      clusterName: `${resourcePrefix}-cluster`,
      vpc: this.vpc,
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });

    // Create CloudWatch log group for container logging
    const logGroup = new logs.LogGroup(this, 'LogGroup', {
      logGroupName: `/ecs/${resourcePrefix.toLowerCase()}-task`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for task execution (used by ECS to pull images and write logs)
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Add ECR permissions to task execution role
    taskExecutionRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ecr:GetAuthorizationToken',
          'ecr:BatchCheckLayerAvailability',
          'ecr:GetDownloadUrlForLayer',
          'ecr:BatchGetImage',
        ],
        resources: ['*'],
      })
    );

    // Create IAM role for tasks (used by application code)
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    // Add CloudWatch permissions to task role
    taskRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogStream',
          'logs:PutLogEvents',
          'cloudwatch:PutMetricData',
        ],
        resources: ['*'],
      })
    );

    // Create Fargate task definition
    this.taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDefinition', {
      family: `${resourcePrefix.toLowerCase()}-task`,
      cpu,
      memoryLimitMiB: memory,
      executionRole: taskExecutionRole,
      taskRole,
    });

    // Determine container image URI
    const imageUri = containerImageUri || `${this.repository.repositoryUri}:latest`;

    // Add container to task definition
    const container = this.taskDefinition.addContainer('Container', {
      image: ecs.ContainerImage.fromRegistry(imageUri),
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup,
      }),
      environment: {
        NODE_ENV: 'production',
        PORT: containerPort.toString(),
      },
      healthCheck: {
        command: [
          'CMD-SHELL',
          `curl -f http://localhost:${containerPort}/health || exit 1`,
        ],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    // Add port mapping to container
    container.addPortMappings({
      containerPort,
      protocol: ecs.Protocol.TCP,
    });

    // Create security group for ALB
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: false,
    });

    // Allow HTTP and HTTPS traffic to ALB
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

    // Create security group for Fargate tasks
    const fargateSecurityGroup = new ec2.SecurityGroup(this, 'FargateSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Fargate tasks',
      allowAllOutbound: true,
    });

    // Allow traffic from ALB to Fargate tasks
    fargateSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(containerPort),
      'Allow traffic from ALB'
    );

    // Create Application Load Balancer
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ALB', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: albSecurityGroup,
      loadBalancerName: `${resourcePrefix}-alb`,
    });

    // Create target group for Fargate service
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      port: containerPort,
      protocol: elbv2.ApplicationProtocol.HTTP,
      vpc: this.vpc,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        port: containerPort.toString(),
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        healthyHttpCodes: '200',
      },
    });

    // Add listener to ALB
    this.loadBalancer.addListener('Listener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create ECS service with Fargate
    this.service = new ecs.FargateService(this, 'Service', {
      cluster: this.cluster,
      taskDefinition: this.taskDefinition,
      serviceName: `${resourcePrefix}-service`,
      desiredCount,
      securityGroups: [fargateSecurityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      assignPublicIp: false,
      healthCheckGracePeriod: cdk.Duration.seconds(120),
      capacityProviderStrategies: [
        {
          capacityProvider: 'FARGATE',
          weight: 1,
          base: 1,
        },
        {
          capacityProvider: 'FARGATE_SPOT',
          weight: 4,
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

    // Attach service to target group
    this.service.attachToApplicationTargetGroup(targetGroup);

    // Configure auto scaling for the service
    const scalableTarget = this.service.autoScaleTaskCount({
      minCapacity,
      maxCapacity,
    });

    // Add CPU utilization scaling
    scalableTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Add memory utilization scaling
    scalableTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 80,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Add custom scaling based on ALB request count
    scalableTarget.scaleOnMetric('RequestCountScaling', {
      metric: targetGroup.metricRequestCountPerTarget({
        statistic: 'Sum',
      }),
      scalingSteps: [
        { upper: 10, change: -1 },
        { lower: 50, change: +1 },
        { lower: 100, change: +2 },
      ],
      adjustmentType: applicationautoscaling.AdjustmentType.CHANGE_IN_CAPACITY,
      cooldown: cdk.Duration.seconds(300),
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ServerlessContainersFargate');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Owner', 'CDK');

    // Output important information
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'LoadBalancerURL', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}`,
      description: 'URL of the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: this.repository.repositoryUri,
      description: 'URI of the ECR repository',
    });

    new cdk.CfnOutput(this, 'ECSClusterName', {
      value: this.cluster.clusterName,
      description: 'Name of the ECS cluster',
    });

    new cdk.CfnOutput(this, 'ECSServiceName', {
      value: this.service.serviceName,
      description: 'Name of the ECS service',
    });

    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'ID of the VPC',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'Name of the CloudWatch log group',
    });

    new cdk.CfnOutput(this, 'HealthCheckURL', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}/health`,
      description: 'Health check endpoint URL',
    });

    new cdk.CfnOutput(this, 'MetricsURL', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}/metrics`,
      description: 'Metrics endpoint URL',
    });
  }
}

// Main CDK application
const app = new cdk.App();

// Get context values or use defaults
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || 'FargateDemo';
const containerImageUri = app.node.tryGetContext('containerImageUri');
const containerPort = app.node.tryGetContext('containerPort') || 3000;
const desiredCount = app.node.tryGetContext('desiredCount') || 3;
const cpu = app.node.tryGetContext('cpu') || 256;
const memory = app.node.tryGetContext('memory') || 512;
const minCapacity = app.node.tryGetContext('minCapacity') || 2;
const maxCapacity = app.node.tryGetContext('maxCapacity') || 10;
const enableVulnerabilityScanning = app.node.tryGetContext('enableVulnerabilityScanning') ?? true;

// Create the stack
new ServerlessContainersFargateStack(app, 'ServerlessContainersFargateStack', {
  resourcePrefix,
  containerImageUri,
  containerPort,
  desiredCount,
  cpu,
  memory,
  minCapacity,
  maxCapacity,
  enableVulnerabilityScanning,
  logRetentionDays: logs.RetentionDays.ONE_WEEK,
  
  // Stack configuration
  description: 'Serverless containers with AWS Fargate and Application Load Balancer',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Enable termination protection for production
  terminationProtection: false,
});

// Synthesize the app
app.synth();