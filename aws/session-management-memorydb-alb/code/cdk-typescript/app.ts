#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as memorydb from 'aws-cdk-lib/aws-memorydb';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';
import { Construct } from 'constructs';

/**
 * Stack that implements distributed session management using MemoryDB for Redis
 * and Application Load Balancer for high availability and scalability
 */
class DistributedSessionManagementStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC with public and private subnets across 2 AZs
    const vpc = new ec2.Vpc(this, 'SessionVPC', {
      maxAzs: 2,
      cidr: '10.0.0.0/16',
      natGateways: 1, // Cost optimization - single NAT Gateway
      subnetConfiguration: [
        {
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'PrivateSubnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
        {
          name: 'MemoryDBSubnet',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 24,
        }
      ],
    });

    // Security group for ALB - allows HTTP/HTTPS from internet
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from internet'
    );

    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from internet'
    );

    // Security group for ECS tasks - allows traffic from ALB only
    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'ECSSecurityGroup', {
      vpc,
      description: 'Security group for ECS tasks',
      allowAllOutbound: true,
    });

    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(80),
      'Allow traffic from ALB to ECS tasks'
    );

    // Security group for MemoryDB - allows Redis traffic from ECS tasks only
    const memorydbSecurityGroup = new ec2.SecurityGroup(this, 'MemoryDBSecurityGroup', {
      vpc,
      description: 'Security group for MemoryDB cluster',
      allowAllOutbound: false,
    });

    memorydbSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.tcp(6379),
      'Allow Redis traffic from ECS tasks'
    );

    // Create MemoryDB subnet group for Multi-AZ deployment
    const memorydbSubnetGroup = new memorydb.CfnSubnetGroup(this, 'MemoryDBSubnetGroup', {
      subnetGroupName: `session-subnet-group-${randomSuffix}`,
      description: 'Subnet group for session management MemoryDB cluster',
      subnetIds: vpc.isolatedSubnets.map(subnet => subnet.subnetId),
    });

    // Create MemoryDB cluster for session storage with durability and Multi-AZ
    const memorydbCluster = new memorydb.CfnCluster(this, 'MemoryDBCluster', {
      clusterName: `session-memorydb-${randomSuffix}`,
      description: 'MemoryDB cluster for distributed session management',
      nodeType: 'db.r6g.large',
      numShards: 2,
      numReplicasPerShard: 1,
      subnetGroupName: memorydbSubnetGroup.subnetGroupName,
      securityGroupIds: [memorydbSecurityGroup.securityGroupId],
      parameterGroupName: 'default.memorydb-redis7',
      autoMinorVersionUpgrade: true,
      maintenanceWindow: 'sun:05:00-sun:06:00',
      snapshotRetentionLimit: 5,
      snapshotWindow: '03:00-04:00',
      tags: [
        {
          key: 'Name',
          value: `SessionMemoryDB-${randomSuffix}`
        },
        {
          key: 'Purpose',
          value: 'DistributedSessionManagement'
        }
      ]
    });

    // Add dependency to ensure subnet group is created first
    memorydbCluster.addDependency(memorydbSubnetGroup);

    // Store MemoryDB configuration in Systems Manager Parameter Store
    const memorydbEndpointParameter = new ssm.StringParameter(this, 'MemoryDBEndpointParameter', {
      parameterName: '/session-app/memorydb/endpoint',
      stringValue: memorydbCluster.attrClusterEndpointAddress,
      description: 'MemoryDB cluster endpoint for session storage',
    });

    new ssm.StringParameter(this, 'MemoryDBPortParameter', {
      parameterName: '/session-app/memorydb/port',
      stringValue: '6379',
      description: 'MemoryDB port for Redis connections',
    });

    new ssm.StringParameter(this, 'SessionTimeoutParameter', {
      parameterName: '/session-app/config/session-timeout',
      stringValue: '1800',
      description: 'Session timeout in seconds (30 minutes)',
    });

    new ssm.StringParameter(this, 'RedisDBParameter', {
      parameterName: '/session-app/config/redis-db',
      stringValue: '0',
      description: 'Redis database number for session storage',
    });

    // Create CloudWatch log group for ECS tasks
    const logGroup = new logs.LogGroup(this, 'SessionAppLogGroup', {
      logGroupName: '/ecs/session-app',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create ECS cluster
    const cluster = new ecs.Cluster(this, 'SessionCluster', {
      vpc,
      clusterName: `session-cluster-${randomSuffix}`,
      containerInsights: true,
    });

    // IAM role for ECS task execution with Parameter Store access
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'Task execution role for session management ECS tasks',
    });

    taskExecutionRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy')
    );

    taskExecutionRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:GetParameter',
        'ssm:GetParameters',
        'ssm:GetParametersByPath'
      ],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:parameter/session-app/*`
      ]
    }));

    // IAM role for ECS tasks
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'Task role for session management ECS tasks',
    });

    taskRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:GetParameter',
        'ssm:GetParameters',
        'ssm:GetParametersByPath'
      ],
      resources: [
        `arn:aws:ssm:${this.region}:${this.account}:parameter/session-app/*`
      ]
    }));

    // ECS Task Definition for session-aware web application
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'SessionAppTaskDefinition', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
      family: 'session-app',
    });

    // Container definition with session management capabilities
    const container = taskDefinition.addContainer('SessionAppContainer', {
      image: ecs.ContainerImage.fromRegistry('nginx:alpine'),
      containerName: 'session-app',
      memoryLimitMiB: 512,
      cpu: 256,
      essential: true,
      environment: {
        'APP_ENV': 'production',
        'REDIS_DB': '0'
      },
      secrets: {
        'REDIS_ENDPOINT': ecs.Secret.fromSsmParameter(memorydbEndpointParameter),
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'session-app',
        logGroup: logGroup,
      }),
      healthCheck: {
        command: [
          'CMD-SHELL',
          'curl -f http://localhost/ || exit 1'
        ],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    container.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'SessionALB', {
      vpc,
      internetFacing: true,
      loadBalancerName: `session-alb-${randomSuffix}`,
      securityGroup: albSecurityGroup,
    });

    // Target Group for ECS tasks
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'SessionTargetGroup', {
      vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      targetGroupName: `session-tg-${randomSuffix}`,
      healthCheck: {
        enabled: true,
        path: '/',
        protocol: elbv2.Protocol.HTTP,
        port: '80',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // ALB Listener
    const listener = alb.addListener('SessionALBListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // ECS Fargate Service with auto scaling
    const service = new ecs.FargateService(this, 'SessionAppService', {
      cluster,
      taskDefinition,
      serviceName: 'session-app-service',
      desiredCount: 2,
      minHealthyPercent: 50,
      maxHealthyPercent: 200,
      securityGroups: [ecsSecurityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      assignPublicIp: false,
      healthCheckGracePeriod: cdk.Duration.seconds(300),
      enableLogging: true,
      platformVersion: ecs.FargatePlatformVersion.LATEST,
    });

    // Attach service to target group
    service.attachToApplicationTargetGroup(targetGroup);

    // Auto Scaling for ECS Service
    const scalableTarget = service.autoScaleTaskCount({
      minCapacity: 2,
      maxCapacity: 10,
    });

    // CPU-based scaling policy
    scalableTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
      policyName: 'session-app-cpu-scaling',
    });

    // Memory-based scaling policy
    scalableTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 80,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
      policyName: 'session-app-memory-scaling',
    });

    // CloudWatch Dashboard for monitoring
    // Note: Dashboard creation would require additional imports and setup

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'VPCId', {
      value: vpc.vpcId,
      description: 'VPC ID for the session management infrastructure',
      exportName: `${this.stackName}-VPCId`,
    });

    new cdk.CfnOutput(this, 'ALBDNSName', {
      value: alb.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: `${this.stackName}-ALBDNSName`,
    });

    new cdk.CfnOutput(this, 'MemoryDBClusterEndpoint', {
      value: memorydbCluster.attrClusterEndpointAddress,
      description: 'MemoryDB cluster endpoint for session storage',
      exportName: `${this.stackName}-MemoryDBEndpoint`,
    });

    new cdk.CfnOutput(this, 'ECSClusterName', {
      value: cluster.clusterName,
      description: 'Name of the ECS cluster',
      exportName: `${this.stackName}-ECSClusterName`,
    });

    new cdk.CfnOutput(this, 'ECSServiceName', {
      value: service.serviceName,
      description: 'Name of the ECS service',
      exportName: `${this.stackName}-ECSServiceName`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'DistributedSessionManagement');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
  }
}

// CDK App
const app = new cdk.App();

// Stack configuration
const stackName = process.env.STACK_NAME || 'DistributedSessionManagementStack';
const awsRegion = process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1';
const awsAccount = process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT;

new DistributedSessionManagementStack(app, stackName, {
  stackName,
  description: 'CDK Stack for Distributed Session Management with MemoryDB',
  env: {
    account: awsAccount,
    region: awsRegion,
  },
  terminationProtection: false, // Set to true for production environments
});

app.synth();