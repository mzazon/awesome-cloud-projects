#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as servicediscovery from 'aws-cdk-lib/aws-servicediscovery';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the ECS Service Discovery Stack
 */
interface EcsServiceDiscoveryStackProps extends cdk.StackProps {
  /**
   * The VPC to deploy the resources in. If not provided, a new VPC will be created.
   */
  vpc?: ec2.IVpc;
  
  /**
   * The name of the service discovery namespace
   * @default 'internal.local'
   */
  namespaceName?: string;
  
  /**
   * The desired count for the web service
   * @default 2
   */
  webServiceDesiredCount?: number;
  
  /**
   * The desired count for the API service
   * @default 2
   */
  apiServiceDesiredCount?: number;
}

/**
 * CDK Stack for ECS Service Discovery with Route 53 and Application Load Balancer
 * 
 * This stack creates:
 * - VPC with public and private subnets (if not provided)
 * - ECS Fargate cluster
 * - AWS Cloud Map private DNS namespace
 * - Application Load Balancer with target groups
 * - ECS services with service discovery integration
 * - Security groups for proper traffic flow
 * - IAM roles for ECS task execution
 */
export class EcsServiceDiscoveryStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly cluster: ecs.Cluster;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly namespace: servicediscovery.PrivateDnsNamespace;

  constructor(scope: Construct, id: string, props: EcsServiceDiscoveryStackProps = {}) {
    super(scope, id, props);

    // Create or use existing VPC
    this.vpc = props.vpc ?? this.createVpc();

    // Create ECS cluster
    this.cluster = this.createEcsCluster();

    // Create service discovery namespace
    this.namespace = this.createServiceDiscoveryNamespace(props.namespaceName ?? 'internal.local');

    // Create security groups
    const { albSecurityGroup, ecsSecurityGroup } = this.createSecurityGroups();

    // Create Application Load Balancer
    this.loadBalancer = this.createApplicationLoadBalancer(albSecurityGroup);

    // Create target groups
    const { webTargetGroup, apiTargetGroup } = this.createTargetGroups();

    // Create ALB listeners and routing rules
    this.createAlbListeners(webTargetGroup, apiTargetGroup);

    // Create IAM execution role for ECS tasks
    const executionRole = this.createEcsExecutionRole();

    // Create ECS task definitions
    const { webTaskDefinition, apiTaskDefinition } = this.createTaskDefinitions(executionRole);

    // Create service discovery services
    const { webService: webDiscoveryService, apiService: apiDiscoveryService } = 
      this.createServiceDiscoveryServices();

    // Create ECS services with service discovery and load balancer integration
    this.createEcsServices(
      webTaskDefinition,
      apiTaskDefinition,
      webTargetGroup,
      apiTargetGroup,
      webDiscoveryService,
      apiDiscoveryService,
      ecsSecurityGroup,
      props.webServiceDesiredCount ?? 2,
      props.apiServiceDesiredCount ?? 2
    );

    // Create outputs
    this.createOutputs();
  }

  /**
   * Creates a new VPC with public and private subnets across multiple AZs
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'MicroservicesVpc', {
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
  }

  /**
   * Creates the ECS cluster with Fargate capacity providers
   */
  private createEcsCluster(): ecs.Cluster {
    const cluster = new ecs.Cluster(this, 'MicroservicesCluster', {
      vpc: this.vpc,
      clusterName: `microservices-cluster-${this.stackName.toLowerCase()}`,
      containerInsights: true, // Enable CloudWatch Container Insights
    });

    // Add Fargate capacity providers
    cluster.addDefaultCapacityProviderStrategy([
      {
        capacityProvider: 'FARGATE',
        weight: 1,
      },
      {
        capacityProvider: 'FARGATE_SPOT',
        weight: 0, // Can be increased for cost optimization
      },
    ]);

    return cluster;
  }

  /**
   * Creates the AWS Cloud Map private DNS namespace for service discovery
   */
  private createServiceDiscoveryNamespace(namespaceName: string): servicediscovery.PrivateDnsNamespace {
    return new servicediscovery.PrivateDnsNamespace(this, 'ServiceDiscoveryNamespace', {
      name: namespaceName,
      vpc: this.vpc,
      description: 'Private DNS namespace for microservices discovery',
    });
  }

  /**
   * Creates security groups for ALB and ECS tasks
   */
  private createSecurityGroups(): { albSecurityGroup: ec2.SecurityGroup; ecsSecurityGroup: ec2.SecurityGroup } {
    // Security group for Application Load Balancer
    const albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP and HTTPS traffic to ALB
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

    // Security group for ECS tasks
    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'EcsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for ECS tasks',
      allowAllOutbound: true,
    });

    // Allow traffic from ALB to ECS tasks
    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(3000),
      'Allow traffic from ALB to web service'
    );

    ecsSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(8080),
      'Allow traffic from ALB to API service'
    );

    // Allow internal communication between services
    ecsSecurityGroup.addIngressRule(
      ecsSecurityGroup,
      ec2.Port.allTraffic(),
      'Allow internal communication between services'
    );

    return { albSecurityGroup, ecsSecurityGroup };
  }

  /**
   * Creates the Application Load Balancer
   */
  private createApplicationLoadBalancer(securityGroup: ec2.SecurityGroup): elbv2.ApplicationLoadBalancer {
    return new elbv2.ApplicationLoadBalancer(this, 'MicroservicesAlb', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup,
      loadBalancerName: `microservices-alb-${this.stackName.toLowerCase()}`,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });
  }

  /**
   * Creates target groups for the web and API services
   */
  private createTargetGroups(): { webTargetGroup: elbv2.ApplicationTargetGroup; apiTargetGroup: elbv2.ApplicationTargetGroup } {
    const webTargetGroup = new elbv2.ApplicationTargetGroup(this, 'WebTargetGroup', {
      vpc: this.vpc,
      port: 3000,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        port: '3000',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    const apiTargetGroup = new elbv2.ApplicationTargetGroup(this, 'ApiTargetGroup', {
      vpc: this.vpc,
      port: 8080,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        port: '8080',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
    });

    return { webTargetGroup, apiTargetGroup };
  }

  /**
   * Creates ALB listeners and routing rules
   */
  private createAlbListeners(
    webTargetGroup: elbv2.ApplicationTargetGroup,
    apiTargetGroup: elbv2.ApplicationTargetGroup
  ): void {
    const listener = this.loadBalancer.addListener('HttpListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.forward([webTargetGroup]),
    });

    // Add listener rule for API service
    listener.addAction('ApiForwardAction', {
      priority: 100,
      conditions: [
        elbv2.ListenerCondition.pathPatterns(['/api/*']),
      ],
      action: elbv2.ListenerAction.forward([apiTargetGroup]),
    });
  }

  /**
   * Creates the IAM execution role for ECS tasks
   */
  private createEcsExecutionRole(): iam.Role {
    return new iam.Role(this, 'EcsTaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'ECS Task Execution Role for Fargate tasks',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });
  }

  /**
   * Creates ECS task definitions for web and API services
   */
  private createTaskDefinitions(executionRole: iam.Role): {
    webTaskDefinition: ecs.FargateTaskDefinition;
    apiTaskDefinition: ecs.FargateTaskDefinition;
  } {
    // Create log groups
    const webLogGroup = new logs.LogGroup(this, 'WebServiceLogGroup', {
      logGroupName: '/ecs/web-service',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const apiLogGroup = new logs.LogGroup(this, 'ApiServiceLogGroup', {
      logGroupName: '/ecs/api-service',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Web service task definition
    const webTaskDefinition = new ecs.FargateTaskDefinition(this, 'WebTaskDefinition', {
      family: `web-service-${this.stackName.toLowerCase()}`,
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole,
    });

    webTaskDefinition.addContainer('WebContainer', {
      image: ecs.ContainerImage.fromRegistry('nginx:alpine'),
      portMappings: [
        {
          containerPort: 80,
          hostPort: 3000,
          protocol: ecs.Protocol.TCP,
        },
      ],
      essential: true,
      logging: ecs.LogDrivers.awsLogs({
        logGroup: webLogGroup,
        streamPrefix: 'ecs',
      }),
    });

    // API service task definition
    const apiTaskDefinition = new ecs.FargateTaskDefinition(this, 'ApiTaskDefinition', {
      family: `api-service-${this.stackName.toLowerCase()}`,
      cpu: 256,
      memoryLimitMiB: 512,
      executionRole,
    });

    apiTaskDefinition.addContainer('ApiContainer', {
      image: ecs.ContainerImage.fromRegistry('httpd:alpine'),
      portMappings: [
        {
          containerPort: 80,
          hostPort: 8080,
          protocol: ecs.Protocol.TCP,
        },
      ],
      essential: true,
      logging: ecs.LogDrivers.awsLogs({
        logGroup: apiLogGroup,
        streamPrefix: 'ecs',
      }),
    });

    return { webTaskDefinition, apiTaskDefinition };
  }

  /**
   * Creates service discovery services for each microservice
   */
  private createServiceDiscoveryServices(): {
    webService: servicediscovery.Service;
    apiService: servicediscovery.Service;
  } {
    const webService = this.namespace.createService('WebDiscoveryService', {
      name: 'web',
      description: 'Service discovery for web service',
      dnsRecordType: servicediscovery.DnsRecordType.A,
      dnsTtl: cdk.Duration.minutes(5),
      routingPolicy: servicediscovery.RoutingPolicy.MULTIVALUE,
      healthCheck: {
        type: servicediscovery.HealthCheckType.HTTP,
        resourcePath: '/health',
        failureThreshold: 3,
      },
    });

    const apiService = this.namespace.createService('ApiDiscoveryService', {
      name: 'api',
      description: 'Service discovery for API service',
      dnsRecordType: servicediscovery.DnsRecordType.A,
      dnsTtl: cdk.Duration.minutes(5),
      routingPolicy: servicediscovery.RoutingPolicy.MULTIVALUE,
      healthCheck: {
        type: servicediscovery.HealthCheckType.HTTP,
        resourcePath: '/health',
        failureThreshold: 3,
      },
    });

    return { webService, apiService };
  }

  /**
   * Creates ECS services with service discovery and load balancer integration
   */
  private createEcsServices(
    webTaskDefinition: ecs.FargateTaskDefinition,
    apiTaskDefinition: ecs.FargateTaskDefinition,
    webTargetGroup: elbv2.ApplicationTargetGroup,
    apiTargetGroup: elbv2.ApplicationTargetGroup,
    webDiscoveryService: servicediscovery.Service,
    apiDiscoveryService: servicediscovery.Service,
    securityGroup: ec2.SecurityGroup,
    webDesiredCount: number,
    apiDesiredCount: number
  ): void {
    // Web service
    const webService = new ecs.FargateService(this, 'WebService', {
      cluster: this.cluster,
      taskDefinition: webTaskDefinition,
      serviceName: 'web-service',
      desiredCount: webDesiredCount,
      assignPublicIp: false,
      securityGroups: [securityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      cloudMapOptions: {
        cloudMapNamespace: this.namespace,
        name: 'web',
      },
      enableExecuteCommand: true, // Enable ECS Exec for debugging
    });

    // Attach web service to load balancer target group
    webService.attachToApplicationTargetGroup(webTargetGroup);

    // API service
    const apiService = new ecs.FargateService(this, 'ApiService', {
      cluster: this.cluster,
      taskDefinition: apiTaskDefinition,
      serviceName: 'api-service',
      desiredCount: apiDesiredCount,
      assignPublicIp: false,
      securityGroups: [securityGroup],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      cloudMapOptions: {
        cloudMapNamespace: this.namespace,
        name: 'api',
      },
      enableExecuteCommand: true, // Enable ECS Exec for debugging
    });

    // Attach API service to load balancer target group
    apiService.attachToApplicationTargetGroup(apiTargetGroup);

    // Configure auto scaling for both services
    this.configureAutoScaling(webService, 'WebService');
    this.configureAutoScaling(apiService, 'ApiService');
  }

  /**
   * Configures auto scaling for ECS services
   */
  private configureAutoScaling(service: ecs.FargateService, serviceName: string): void {
    const scaling = service.autoScaleTaskCount({
      minCapacity: 1,
      maxCapacity: 10,
    });

    // Scale based on CPU utilization
    scaling.scaleOnCpuUtilization(`${serviceName}CpuScaling`, {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(2),
    });

    // Scale based on memory utilization
    scaling.scaleOnMemoryUtilization(`${serviceName}MemoryScaling`, {
      targetUtilizationPercent: 80,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(2),
    });
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: `${this.stackName}-LoadBalancerDnsName`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerUrl', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}`,
      description: 'URL of the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'ApiUrl', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}/api/`,
      description: 'URL of the API service through the load balancer',
    });

    new cdk.CfnOutput(this, 'ServiceDiscoveryNamespace', {
      value: this.namespace.namespaceName,
      description: 'Service discovery namespace for internal communication',
      exportName: `${this.stackName}-ServiceDiscoveryNamespace`,
    });

    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'Name of the ECS cluster',
      exportName: `${this.stackName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'ID of the VPC',
      exportName: `${this.stackName}-VpcId`,
    });
  }
}

/**
 * CDK App - Entry point for the application
 */
const app = new cdk.App();

// Create the stack with default configuration
new EcsServiceDiscoveryStack(app, 'EcsServiceDiscoveryStack', {
  description: 'ECS Service Discovery with Route 53 and Application Load Balancer',
  
  // Uncomment and configure these properties as needed:
  // env: {
  //   account: process.env.CDK_DEFAULT_ACCOUNT,
  //   region: process.env.CDK_DEFAULT_REGION,
  // },
  
  // Custom configuration options:
  // namespaceName: 'internal.local',
  // webServiceDesiredCount: 2,
  // apiServiceDesiredCount: 2,
  
  // Tags applied to all resources
  tags: {
    Project: 'ECS-Service-Discovery',
    Environment: 'Development',
    ManagedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();