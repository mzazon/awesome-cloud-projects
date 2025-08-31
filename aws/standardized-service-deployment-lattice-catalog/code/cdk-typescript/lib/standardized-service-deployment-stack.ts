import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecsPatterns from 'aws-cdk-lib/aws-ecs-patterns';
import * as servicecatalog from 'aws-cdk-lib/aws-servicecatalog';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import { NagSuppressions } from 'cdk-nag';

export interface StandardizedServiceDeploymentStackProps extends cdk.StackProps {
  serviceCatalogPortfolio: servicecatalog.Portfolio;
  networkProduct: servicecatalog.CloudFormationProduct;
  serviceProduct: servicecatalog.CloudFormationProduct;
}

/**
 * Main stack that demonstrates the standardized VPC Lattice deployment pattern
 * and provides example infrastructure for testing Service Catalog products
 */
export class StandardizedServiceDeploymentStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly ecsCluster: ecs.Cluster;
  public readonly sampleService: ecsPatterns.ApplicationLoadBalancedFargateService;

  constructor(scope: Construct, id: string, props: StandardizedServiceDeploymentStackProps) {
    super(scope, id, props);

    // Create VPC for demonstration
    this.vpc = this.createVpc();

    // Create ECS cluster and sample service
    this.ecsCluster = this.createEcsCluster();
    this.sampleService = this.createSampleService();

    // Create demonstration resources showing Service Catalog integration
    this.createDemonstrationResources(props);

    // Create monitoring and observability resources
    this.createMonitoringResources();

    // Create outputs
    this.createOutputs();

    // Apply CDK Nag suppressions
    this.applyCdkNagSuppressions();

    // Tag all resources
    cdk.Tags.of(this).add('Purpose', 'DemonstrationInfrastructure');
    cdk.Tags.of(this).add('Component', 'MainStack');
  }

  /**
   * Create VPC with public and private subnets
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'DemoVpc', {
      vpcName: 'vpc-lattice-demo',
      maxAzs: 2,
      natGateways: 1,
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
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
      enableDnsHostnames: true,
      enableDnsSupport: true,
      flowLogs: {
        cloudwatch: {
          destination: ec2.FlowLogDestination.toCloudWatchLogs(),
          trafficType: ec2.FlowLogTrafficType.REJECT,
        },
      },
    });
  }

  /**
   * Create ECS cluster for running containerized services
   */
  private createEcsCluster(): ecs.Cluster {
    return new ecs.Cluster(this, 'DemoCluster', {
      clusterName: 'vpc-lattice-demo-cluster',
      vpc: this.vpc,
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });
  }

  /**
   * Create sample ECS service to demonstrate VPC Lattice integration
   */
  private createSampleService(): ecsPatterns.ApplicationLoadBalancedFargateService {
    const service = new ecsPatterns.ApplicationLoadBalancedFargateService(this, 'SampleService', {
      serviceName: 'demo-service',
      cluster: this.ecsCluster,
      cpu: 256,
      memoryLimitMiB: 512,
      desiredCount: 2,
      taskImageOptions: {
        image: ecs.ContainerImage.fromRegistry('nginxdemos/hello'),
        containerName: 'demo-app',
        containerPort: 80,
        logDriver: ecs.LogDrivers.awsLogs({
          streamPrefix: 'demo-service',
          logGroup: new logs.LogGroup(this, 'ServiceLogGroup', {
            logGroupName: '/ecs/demo-service',
            retention: logs.RetentionDays.ONE_WEEK,
            removalPolicy: cdk.RemovalPolicy.DESTROY,
          }),
        }),
        environment: {
          ENV: 'demo',
          SERVICE_NAME: 'vpc-lattice-demo-service',
        },
      },
      publicLoadBalancer: false, // VPC Lattice will handle routing
      assignPublicIp: false,
      platformVersion: ecs.FargatePlatformVersion.LATEST,
      enableExecuteCommand: true,
    });

    // Configure health check
    service.targetGroup.configureHealthCheck({
      path: '/',
      healthyHttpCodes: '200',
      interval: cdk.Duration.seconds(30),
      timeout: cdk.Duration.seconds(5),
      healthyThresholdCount: 2,
      unhealthyThresholdCount: 3,
    });

    return service;
  }

  /**
   * Create resources to demonstrate Service Catalog integration
   */
  private createDemonstrationResources(props: StandardizedServiceDeploymentStackProps): void {
    // Create custom resource to demonstrate Service Catalog product deployment
    const demonstrationRole = new iam.Role(this, 'DemonstrationRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Service Catalog demonstration custom resource',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ServiceCatalogAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'servicecatalog:SearchProducts',
                'servicecatalog:DescribeProduct',
                'servicecatalog:DescribeProductAsAdmin',
                'servicecatalog:ListLaunchPaths',
                'servicecatalog:ProvisionProduct',
                'servicecatalog:DescribeProvisionedProduct',
                'servicecatalog:TerminateProvisionedProduct',
              ],
              resources: [
                props.serviceCatalogPortfolio.portfolioArn,
                props.networkProduct.productArn,
                props.serviceProduct.productArn,
              ],
            }),
          ],
        }),
      },
    });

    // Create a parameter to store VPC ID for Service Catalog templates
    const vpcParameter = new cdk.CfnParameter(this, 'VpcId', {
      type: 'String',
      default: this.vpc.vpcId,
      description: 'VPC ID for VPC Lattice service deployment',
    });

    // Store configuration for Service Catalog deployment
    new cdk.CfnOutput(this, 'ServiceCatalogConfiguration', {
      value: JSON.stringify({
        portfolioId: props.serviceCatalogPortfolio.portfolioId,
        networkProductId: props.networkProduct.productId,
        serviceProductId: props.serviceProduct.productId,
        vpcId: this.vpc.vpcId,
        targetType: 'ALB',
        targetArn: this.sampleService.loadBalancer.loadBalancerArn,
      }),
      description: 'Configuration for Service Catalog VPC Lattice deployment',
    });
  }

  /**
   * Create monitoring and observability resources
   */
  private createMonitoringResources(): void {
    // Create CloudWatch dashboard for monitoring
    const dashboard = new cdk.aws_cloudwatch.Dashboard(this, 'VpcLatticeDashboard', {
      dashboardName: 'VPC-Lattice-Standardized-Deployment',
    });

    // Add ECS service metrics
    dashboard.addWidgets(
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'ECS Service CPU and Memory',
        left: [this.sampleService.service.metricCpuUtilization()],
        right: [this.sampleService.service.metricMemoryUtilization()],
        width: 12,
      }),
      new cdk.aws_cloudwatch.GraphWidget({
        title: 'ALB Target Health',
        left: [
          this.sampleService.targetGroup.metricHealthyHostCount(),
          this.sampleService.targetGroup.metricUnHealthyHostCount(),
        ],
        width: 12,
      }),
    );

    // Create CloudWatch alarms
    new cdk.aws_cloudwatch.Alarm(this, 'HighCpuAlarm', {
      metric: this.sampleService.service.metricCpuUtilization(),
      threshold: 80,
      evaluationPeriods: 3,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'ECS service CPU utilization is above 80%',
    });

    new cdk.aws_cloudwatch.Alarm(this, 'UnhealthyTargetsAlarm', {
      metric: this.sampleService.targetGroup.metricUnHealthyHostCount(),
      threshold: 1,
      evaluationPeriods: 2,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'One or more targets are unhealthy',
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for VPC Lattice service deployment',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'PrivateSubnetIds', {
      value: this.vpc.privateSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Private subnet IDs',
      exportName: `${this.stackName}-PrivateSubnetIds`,
    });

    new cdk.CfnOutput(this, 'EcsClusterArn', {
      value: this.ecsCluster.clusterArn,
      description: 'ECS Cluster ARN',
      exportName: `${this.stackName}-EcsClusterArn`,
    });

    new cdk.CfnOutput(this, 'SampleServiceArn', {
      value: this.sampleService.service.serviceArn,
      description: 'Sample ECS Service ARN',
      exportName: `${this.stackName}-SampleServiceArn`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerArn', {
      value: this.sampleService.loadBalancer.loadBalancerArn,
      description: 'Application Load Balancer ARN for VPC Lattice target group',
      exportName: `${this.stackName}-LoadBalancerArn`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.sampleService.loadBalancer.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
      exportName: `${this.stackName}-LoadBalancerDnsName`,
    });
  }

  /**
   * Apply CDK Nag suppressions for acceptable patterns
   */
  private applyCdkNagSuppressions(): void {
    // Suppress ALB logging warning for demo purposes
    NagSuppressions.addResourceSuppressions(
      this.sampleService.loadBalancer,
      [
        {
          id: 'AwsSolutions-ELB2',
          reason: 'ALB access logging disabled for demo purposes to reduce costs',
        },
      ]
    );

    // Suppress ECS task definition warnings for demo
    NagSuppressions.addResourceSuppressions(
      this.sampleService.taskDefinition,
      [
        {
          id: 'AwsSolutions-ECS2',
          reason: 'Demo service uses environment variables for configuration',
        },
      ]
    );

    // Suppress VPC flow logs warning
    NagSuppressions.addResourceSuppressions(
      this.vpc,
      [
        {
          id: 'AwsSolutions-VPC7',
          reason: 'VPC flow logs are enabled for rejected traffic only to reduce costs in demo',
        },
      ]
    );
  }
}