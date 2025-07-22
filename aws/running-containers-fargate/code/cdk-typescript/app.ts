#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';

/**
 * Configuration interface for the Fargate stack
 */
interface FargateStackConfig {
  /** The container image URI (can be set after ECR repository creation) */
  containerImageUri?: string;
  /** Container port for the application */
  containerPort: number;
  /** Desired number of tasks to run */
  desiredCount: number;
  /** CPU units for the task (256, 512, 1024, 2048, 4096) */
  cpu: number;
  /** Memory in MB for the task */
  memory: number;
  /** Minimum capacity for auto-scaling */
  minCapacity: number;
  /** Maximum capacity for auto-scaling */
  maxCapacity: number;
  /** CPU utilization target for auto-scaling */
  cpuUtilizationTarget: number;
}

/**
 * CDK Stack for Running Containers with AWS Fargate
 * 
 * This stack creates:
 * - ECR repository for container images
 * - ECS cluster with Fargate capacity providers
 * - VPC with public subnets for demonstration (use private subnets + ALB in production)
 * - ECS service with auto-scaling capabilities
 * - CloudWatch log group for application logs
 * - IAM roles with least privilege access
 */
export class ServerlessContainersFargateStack extends cdk.Stack {
  private readonly config: FargateStackConfig;
  
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Stack configuration - customize these values as needed
    this.config = {
      containerPort: 3000,
      desiredCount: 2,
      cpu: 256,
      memory: 512,
      minCapacity: 1,
      maxCapacity: 10,
      cpuUtilizationTarget: 50
    };

    // Create ECR repository for container images
    const ecrRepository = this.createEcrRepository();
    
    // Create VPC for networking (using default VPC pattern for simplicity)
    const vpc = this.createVpc();
    
    // Create ECS cluster
    const cluster = this.createEcsCluster(vpc);
    
    // Create CloudWatch log group
    const logGroup = this.createLogGroup();
    
    // Create IAM roles
    const { taskRole, executionRole } = this.createIamRoles();
    
    // Create task definition
    const taskDefinition = this.createTaskDefinition(
      ecrRepository,
      logGroup,
      taskRole,
      executionRole
    );
    
    // Create security group
    const securityGroup = this.createSecurityGroup(vpc);
    
    // Create ECS service
    const service = this.createEcsService(
      cluster,
      taskDefinition,
      securityGroup,
      vpc
    );
    
    // Configure auto-scaling
    this.configureAutoScaling(service);
    
    // Output important information
    this.createOutputs(ecrRepository, cluster, service);
  }

  /**
   * Creates an ECR repository with vulnerability scanning enabled
   */
  private createEcrRepository(): ecr.Repository {
    const repository = new ecr.Repository(this, 'DemoAppRepository', {
      repositoryName: `demo-app-${this.node.addr.slice(-6)}`.toLowerCase(),
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Add lifecycle policy to manage image retention
    repository.addLifecycleRule({
      rulePriority: 1,
      description: 'Keep last 10 images',
      maxImageCount: 10,
    });

    return repository;
  }

  /**
   * Creates a VPC with public subnets for demonstration
   * In production, use private subnets with NAT gateway and Application Load Balancer
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'FargateVpc', {
      maxAzs: 2,
      natGateways: 0, // Using public subnets for simplicity
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }

  /**
   * Creates an ECS cluster with Fargate capacity providers
   */
  private createEcsCluster(vpc: ec2.Vpc): ecs.Cluster {
    const cluster = new ecs.Cluster(this, 'FargateCluster', {
      vpc,
      clusterName: `fargate-demo-${this.node.addr.slice(-6)}`.toLowerCase(),
      containerInsights: true, // Enable CloudWatch Container Insights
    });

    // Add Fargate capacity providers
    cluster.addCapacityProvider(ecs.CapacityProvider.FARGATE);
    cluster.addCapacityProvider(ecs.CapacityProvider.FARGATE_SPOT);

    return cluster;
  }

  /**
   * Creates a CloudWatch log group for application logs
   */
  private createLogGroup(): logs.LogGroup {
    return new logs.LogGroup(this, 'AppLogGroup', {
      logGroupName: `/ecs/demo-task-${this.node.addr.slice(-6)}`.toLowerCase(),
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates IAM roles for ECS task execution and task itself
   */
  private createIamRoles(): { taskRole: iam.Role; executionRole: iam.Role } {
    // Task execution role - used by ECS agent to pull images and send logs
    const executionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Task role - used by the application itself (add specific permissions as needed)
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      // Add additional policies here for application-specific AWS service access
    });

    return { taskRole, executionRole };
  }

  /**
   * Creates the ECS task definition with container configuration
   */
  private createTaskDefinition(
    ecrRepository: ecr.Repository,
    logGroup: logs.LogGroup,
    taskRole: iam.Role,
    executionRole: iam.Role
  ): ecs.FargateTaskDefinition {
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDefinition', {
      family: `demo-task-${this.node.addr.slice(-6)}`.toLowerCase(),
      cpu: this.config.cpu,
      memoryLimitMiB: this.config.memory,
      taskRole,
      executionRole,
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('DemoContainer', {
      // Use a placeholder image - update this after pushing your actual image
      image: this.config.containerImageUri 
        ? ecs.ContainerImage.fromRegistry(this.config.containerImageUri)
        : ecs.ContainerImage.fromRegistry(`${ecrRepository.repositoryUri}:latest`),
      
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup,
      }),
      
      // Health check configuration
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3000/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
      
      // Environment variables (add application-specific variables as needed)
      environment: {
        NODE_ENV: 'production',
        PORT: this.config.containerPort.toString(),
      },
    });

    // Add port mapping
    container.addPortMappings({
      containerPort: this.config.containerPort,
      protocol: ecs.Protocol.TCP,
    });

    return taskDefinition;
  }

  /**
   * Creates a security group for the Fargate tasks
   */
  private createSecurityGroup(vpc: ec2.Vpc): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'FargateSecurityGroup', {
      vpc,
      description: 'Security group for Fargate demo application',
      allowAllOutbound: true,
    });

    // Allow inbound traffic on the application port
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(this.config.containerPort),
      'Allow HTTP traffic'
    );

    return securityGroup;
  }

  /**
   * Creates the ECS service with Fargate launch type
   */
  private createEcsService(
    cluster: ecs.Cluster,
    taskDefinition: ecs.FargateTaskDefinition,
    securityGroup: ec2.SecurityGroup,
    vpc: ec2.Vpc
  ): ecs.FargateService {
    const service = new ecs.FargateService(this, 'DemoService', {
      cluster,
      taskDefinition,
      serviceName: 'demo-service',
      desiredCount: this.config.desiredCount,
      
      // Use mixed capacity provider strategy for cost optimization
      capacityProviderStrategies: [
        {
          capacityProvider: ecs.CapacityProvider.FARGATE,
          weight: 1,
        },
      ],
      
      // Network configuration
      assignPublicIp: true, // Required for public subnets
      securityGroups: [securityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      
      // Enable CloudWatch Container Insights
      enableLogging: true,
      
      // Enable ECS Exec for debugging
      enableExecuteCommand: true,
      
      // Circuit breaker for deployment safety
      circuitBreaker: {
        rollback: true,
      },
      
      // Deployment configuration
      minHealthyPercent: 50,
      maxHealthyPercent: 200,
    });

    return service;
  }

  /**
   * Configures auto-scaling for the ECS service
   */
  private configureAutoScaling(service: ecs.FargateService): void {
    // Register the service as a scalable target
    const scalableTarget = service.autoScaleTaskCount({
      minCapacity: this.config.minCapacity,
      maxCapacity: this.config.maxCapacity,
    });

    // Add CPU-based scaling policy
    scalableTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: this.config.cpuUtilizationTarget,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Add memory-based scaling policy as an additional metric
    scalableTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });
  }

  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(
    ecrRepository: ecr.Repository,
    cluster: ecs.Cluster,
    service: ecs.FargateService
  ): void {
    new cdk.CfnOutput(this, 'EcrRepositoryUri', {
      value: ecrRepository.repositoryUri,
      description: 'ECR Repository URI for pushing container images',
    });

    new cdk.CfnOutput(this, 'EcrRepositoryName', {
      value: ecrRepository.repositoryName,
      description: 'ECR Repository name',
    });

    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster name',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: service.serviceName,
      description: 'ECS Service name',
    });

    new cdk.CfnOutput(this, 'ServiceArn', {
      value: service.serviceArn,
      description: 'ECS Service ARN',
    });

    // Instructions for next steps
    new cdk.CfnOutput(this, 'NextSteps', {
      value: `
1. Build and push your container image to ${ecrRepository.repositoryUri}:latest
2. Update the ECS service to deploy the new image
3. Monitor the service in the ECS console and CloudWatch
      `.trim(),
      description: 'Next steps after deployment',
    });
  }
}

/**
 * CDK App entry point
 */
const app = new cdk.App();

// Create the stack with environment configuration
new ServerlessContainersFargateStack(app, 'ServerlessContainersFargateStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack-level tags
  tags: {
    Project: 'Serverless Containers with Fargate',
    Environment: 'Demo',
    ManagedBy: 'AWS CDK',
  },
  
  // Stack description
  description: 'CDK stack for Running Containers with AWS Fargate, ECS, and ECR',
});

// Synthesize the CloudFormation template
app.synth();