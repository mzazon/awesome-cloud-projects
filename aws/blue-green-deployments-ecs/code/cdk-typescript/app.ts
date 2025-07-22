#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as codedeploy from 'aws-cdk-lib/aws-codedeploy';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * Stack for implementing blue-green deployments with ECS and CodeDeploy
 * This stack creates a complete blue-green deployment infrastructure including:
 * - VPC with public subnets across multiple AZs
 * - ECS Cluster with Fargate capacity
 * - Application Load Balancer with blue and green target groups
 * - ECR repository for container images
 * - CodeDeploy application for blue-green deployments
 * - IAM roles and policies
 */
class BlueGreenEcsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create VPC with public subnets across multiple AZs for high availability
    const vpc = new ec2.Vpc(this, 'BlueGreenVpc', {
      maxAzs: 2,
      natGateways: 0, // Using public subnets only for cost optimization
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Create security group for ECS tasks and load balancer
    const securityGroup = new ec2.SecurityGroup(this, 'BlueGreenSecurityGroup', {
      vpc,
      description: 'Security group for blue-green deployment ECS tasks',
      allowAllOutbound: true,
    });

    // Allow inbound HTTP traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from anywhere'
    );

    // Create ECS cluster with Fargate capacity provider
    const cluster = new ecs.Cluster(this, 'BlueGreenCluster', {
      vpc,
      clusterName: `bluegreen-cluster-${uniqueSuffix}`,
      containerInsights: true, // Enable container insights for monitoring
    });

    // Add Fargate capacity provider to the cluster
    cluster.addCapacityProvider('FARGATE');

    // Create ECR repository for container images
    const repository = new ecr.Repository(this, 'BlueGreenRepository', {
      repositoryName: `bluegreen-app-${uniqueSuffix}`,
      imageScanOnPush: true, // Enable vulnerability scanning
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Allow deletion during cleanup
    });

    // Create CloudWatch log group for ECS tasks
    const logGroup = new logs.LogGroup(this, 'BlueGreenLogGroup', {
      logGroupName: `/ecs/bluegreen-task-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create task execution role with permissions to pull images and create logs
    const taskExecutionRole = new iam.Role(this, 'BlueGreenTaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Create task definition for the containerized application
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'BlueGreenTaskDefinition', {
      family: `bluegreen-task-${uniqueSuffix}`,
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole: taskExecutionRole,
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('BlueGreenContainer', {
      containerName: 'bluegreen-container',
      image: ecs.ContainerImage.fromEcrRepository(repository, 'latest'),
      essential: true,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: logGroup,
      }),
    });

    // Expose port 80 for HTTP traffic
    container.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // Create Application Load Balancer
    const loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'BlueGreenLoadBalancer', {
      vpc,
      internetFacing: true,
      loadBalancerName: `bluegreen-alb-${uniqueSuffix}`,
      securityGroup,
    });

    // Create blue target group for current version
    const blueTargetGroup = new elbv2.ApplicationTargetGroup(this, 'BlueTargetGroup', {
      targetGroupName: `blue-tg-${uniqueSuffix}`,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      vpc,
      healthCheck: {
        path: '/',
        intervalSeconds: 30,
        timeoutSeconds: 5,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Create green target group for new version
    const greenTargetGroup = new elbv2.ApplicationTargetGroup(this, 'GreenTargetGroup', {
      targetGroupName: `green-tg-${uniqueSuffix}`,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      vpc,
      healthCheck: {
        path: '/',
        intervalSeconds: 30,
        timeoutSeconds: 5,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    // Create listener that initially points to blue target group
    const listener = loadBalancer.addListener('BlueGreenListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [blueTargetGroup],
    });

    // Create S3 bucket for CodeDeploy artifacts
    const deploymentBucket = new s3.Bucket(this, 'BlueGreenDeploymentBucket', {
      bucketName: `bluegreen-deployments-${uniqueSuffix}`,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create CodeDeploy service role
    const codeDeployRole = new iam.Role(this, 'BlueGreenCodeDeployRole', {
      assumedBy: new iam.ServicePrincipal('codedeploy.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSCodeDeployRoleForECS'),
      ],
    });

    // Create CodeDeploy application
    const codeDeployApplication = new codedeploy.EcsApplication(this, 'BlueGreenCodeDeployApplication', {
      applicationName: `bluegreen-app-${uniqueSuffix}`,
    });

    // Create ECS service with CodeDeploy deployment controller
    const service = new ecs.FargateService(this, 'BlueGreenService', {
      cluster,
      serviceName: `bluegreen-service-${uniqueSuffix}`,
      taskDefinition,
      desiredCount: 2,
      assignPublicIp: true,
      securityGroups: [securityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      deploymentController: {
        type: ecs.DeploymentControllerType.CODE_DEPLOY,
      },
      enableLogging: true,
    });

    // Attach service to blue target group
    service.attachToApplicationTargetGroup(blueTargetGroup);

    // Create CodeDeploy deployment group
    const deploymentGroup = new codedeploy.EcsDeploymentGroup(this, 'BlueGreenDeploymentGroup', {
      application: codeDeployApplication,
      deploymentGroupName: `bluegreen-dg-${uniqueSuffix}`,
      service,
      blueGreenDeploymentConfig: {
        blueTargetGroup,
        greenTargetGroup,
        listener,
      },
      deploymentConfig: codedeploy.EcsDeploymentConfig.ALL_AT_ONCE,
      role: codeDeployRole,
      autoRollback: {
        failedDeployment: true,
        stoppedDeployment: true,
      },
    });

    // Outputs for verification and integration
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster Name',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: service.serviceName,
      description: 'ECS Service Name',
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: loadBalancer.loadBalancerDnsName,
      description: 'Load Balancer DNS Name',
    });

    new cdk.CfnOutput(this, 'LoadBalancerUrl', {
      value: `http://${loadBalancer.loadBalancerDnsName}`,
      description: 'Application URL',
    });

    new cdk.CfnOutput(this, 'RepositoryUri', {
      value: repository.repositoryUri,
      description: 'ECR Repository URI',
    });

    new cdk.CfnOutput(this, 'BlueTargetGroupArn', {
      value: blueTargetGroup.targetGroupArn,
      description: 'Blue Target Group ARN',
    });

    new cdk.CfnOutput(this, 'GreenTargetGroupArn', {
      value: greenTargetGroup.targetGroupArn,
      description: 'Green Target Group ARN',
    });

    new cdk.CfnOutput(this, 'CodeDeployApplicationName', {
      value: codeDeployApplication.applicationName,
      description: 'CodeDeploy Application Name',
    });

    new cdk.CfnOutput(this, 'DeploymentGroupName', {
      value: deploymentGroup.deploymentGroupName,
      description: 'CodeDeploy Deployment Group Name',
    });

    new cdk.CfnOutput(this, 'DeploymentBucketName', {
      value: deploymentBucket.bucketName,
      description: 'S3 Bucket for CodeDeploy Artifacts',
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID',
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: securityGroup.securityGroupId,
      description: 'Security Group ID',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack with appropriate tags
new BlueGreenEcsStack(app, 'BlueGreenEcsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'BlueGreenDeployments',
    Environment: 'Development',
    Purpose: 'ECS Blue-Green Deployment Demo',
  },
});

// Synthesize the stack
app.synth();