import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipelineActions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as applicationautoscaling from 'aws-cdk-lib/aws-applicationautoscaling';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

export interface App2ContainerStackProps extends cdk.StackProps {
  appName: string;
  environment: string;
}

/**
 * AWS App2Container Modernization Infrastructure Stack
 * 
 * This stack creates the complete infrastructure needed for modernizing
 * legacy applications using AWS App2Container, including:
 * - Container orchestration with Amazon ECS
 * - Container registry with Amazon ECR
 * - CI/CD pipeline with CodePipeline
 * - Load balancing and auto-scaling
 * - Monitoring and logging
 */
export class App2ContainerStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly cluster: ecs.Cluster;
  public readonly repository: ecr.Repository;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly codeRepository: codecommit.Repository;
  public readonly pipeline: codepipeline.Pipeline;

  constructor(scope: Construct, id: string, props: App2ContainerStackProps) {
    super(scope, id, props);

    const { appName, environment } = props;

    // Generate unique suffix for resource naming
    const suffix = this.node.addr.substring(0, 8);

    // Create VPC with public and private subnets across multiple AZs
    this.vpc = new ec2.Vpc(this, 'App2ContainerVpc', {
      maxAzs: 3,
      natGateways: 2, // For high availability
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'PublicSubnet',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'PrivateSubnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create S3 bucket for App2Container artifacts
    const artifactsBucket = new s3.Bucket(this, 'App2ContainerArtifacts', {
      bucketName: `app2container-artifacts-${suffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // Create ECR repository for container images
    this.repository = new ecr.Repository(this, 'App2ContainerRepository', {
      repositoryName: `${appName}-${suffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      lifecycleRules: [
        {
          description: 'Keep only 10 latest images',
          maxImageCount: 10,
          rulePriority: 1,
        },
      ],
    });

    // Create ECS cluster with Fargate capacity providers
    this.cluster = new ecs.Cluster(this, 'App2ContainerCluster', {
      clusterName: `app2container-cluster-${suffix}`,
      vpc: this.vpc,
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });

    // Create CloudWatch log group for application logs
    const logGroup = new logs.LogGroup(this, 'App2ContainerLogGroup', {
      logGroupName: `/ecs/${appName}-${suffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create IAM role for ECS task execution
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
      inlinePolicies: {
        ECRAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:GetAuthorizationToken',
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create IAM role for ECS tasks
    const taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [artifactsBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [artifactsBucket.bucketArn],
            }),
          ],
        }),
      },
    });

    // Create Fargate task definition
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'App2ContainerTaskDefinition', {
      memoryLimitMiB: 2048,
      cpu: 1024,
      executionRole: taskExecutionRole,
      taskRole: taskRole,
      family: `${appName}-${suffix}`,
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('App2ContainerContainer', {
      image: ecs.ContainerImage.fromRegistry('nginx:latest'), // Placeholder image
      containerName: `${appName}-container`,
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: logGroup,
      }),
      environment: {
        APP_NAME: appName,
        ENVIRONMENT: environment,
      },
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:80/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60),
      },
    });

    // Add port mapping
    container.addPortMappings({
      containerPort: 80,
      protocol: ecs.Protocol.TCP,
    });

    // Create Application Load Balancer
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'App2ContainerALB', {
      vpc: this.vpc,
      internetFacing: true,
      loadBalancerName: `app2container-alb-${suffix}`,
      securityGroup: this.createALBSecurityGroup(),
    });

    // Create target group
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'App2ContainerTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        interval: cdk.Duration.seconds(30),
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        timeout: cdk.Duration.seconds(5),
        unhealthyThresholdCount: 2,
        healthyThresholdCount: 5,
      },
      deregistrationDelay: cdk.Duration.seconds(30),
    });

    // Add listener to ALB
    this.loadBalancer.addListener('App2ContainerListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create ECS service
    const service = new ecs.FargateService(this, 'App2ContainerService', {
      cluster: this.cluster,
      taskDefinition: taskDefinition,
      serviceName: `${appName}-service-${suffix}`,
      desiredCount: 2,
      assignPublicIp: false,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [this.createECSSecurityGroup()],
      enableLogging: true,
      capacityProviderStrategies: [
        {
          capacityProvider: 'FARGATE',
          weight: 1,
        },
      ],
      enableExecuteCommand: true, // For debugging
    });

    // Attach target group to service
    service.attachToApplicationTargetGroup(targetGroup);

    // Configure auto scaling
    const scalableTarget = service.autoScaleTaskCount({
      minCapacity: 1,
      maxCapacity: 10,
    });

    // Add CPU-based scaling policy
    scalableTarget.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Add memory-based scaling policy
    scalableTarget.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 80,
      scaleInCooldown: cdk.Duration.seconds(300),
      scaleOutCooldown: cdk.Duration.seconds(300),
    });

    // Create CodeCommit repository for CI/CD
    this.codeRepository = new codecommit.Repository(this, 'App2ContainerCodeRepository', {
      repositoryName: `app2container-pipeline-${suffix}`,
      description: 'App2Container modernization pipeline repository',
    });

    // Create CodeBuild project
    const buildProject = this.createCodeBuildProject(artifactsBucket, suffix);

    // Create CI/CD pipeline
    this.pipeline = this.createPipeline(buildProject, service, suffix);

    // Create CloudWatch dashboard
    this.createCloudWatchDashboard(suffix);

    // Output important values
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for App2Container infrastructure',
    });

    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'ECS Cluster name for App2Container',
    });

    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: this.repository.repositoryUri,
      description: 'ECR Repository URI for container images',
    });

    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name',
    });

    new cdk.CfnOutput(this, 'CodeCommitRepositoryCloneUrl', {
      value: this.codeRepository.repositoryCloneUrlHttp,
      description: 'CodeCommit repository clone URL',
    });

    new cdk.CfnOutput(this, 'ArtifactsBucketName', {
      value: artifactsBucket.bucketName,
      description: 'S3 bucket for App2Container artifacts',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: service.serviceName,
      description: 'ECS Service name',
    });
  }

  /**
   * Create security group for Application Load Balancer
   */
  private createALBSecurityGroup(): ec2.SecurityGroup {
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for App2Container Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from anywhere
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from anywhere'
    );

    // Allow HTTPS traffic from anywhere (for future SSL configuration)
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from anywhere'
    );

    return albSecurityGroup;
  }

  /**
   * Create security group for ECS service
   */
  private createECSSecurityGroup(): ec2.SecurityGroup {
    const ecsSecurityGroup = new ec2.SecurityGroup(this, 'ECSSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for App2Container ECS service',
      allowAllOutbound: true,
    });

    // Allow traffic from ALB security group
    ecsSecurityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.createALBSecurityGroup().securityGroupId),
      ec2.Port.tcp(80),
      'Allow traffic from Application Load Balancer'
    );

    return ecsSecurityGroup;
  }

  /**
   * Create CodeBuild project for building container images
   */
  private createCodeBuildProject(artifactsBucket: s3.Bucket, suffix: string): codebuild.Project {
    // Create IAM role for CodeBuild
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSCodeBuildDeveloperAccess'),
      ],
      inlinePolicies: {
        ECRAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecr:BatchCheckLayerAvailability',
                'ecr:GetDownloadUrlForLayer',
                'ecr:BatchGetImage',
                'ecr:GetAuthorizationToken',
                'ecr:PutImage',
                'ecr:InitiateLayerUpload',
                'ecr:UploadLayerPart',
                'ecr:CompleteLayerUpload',
              ],
              resources: ['*'],
            }),
          ],
        }),
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [artifactsBucket.arnForObjects('*')],
            }),
          ],
        }),
      },
    });

    return new codebuild.Project(this, 'App2ContainerBuildProject', {
      projectName: `app2container-build-${suffix}`,
      role: codeBuildRole,
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        privileged: true, // Required for Docker builds
        computeType: codebuild.ComputeType.SMALL,
        environmentVariables: {
          AWS_DEFAULT_REGION: {
            value: this.region,
          },
          AWS_ACCOUNT_ID: {
            value: this.account,
          },
          IMAGE_REPO_NAME: {
            value: this.repository.repositoryName,
          },
          IMAGE_TAG: {
            value: 'latest',
          },
        },
      },
      source: codebuild.Source.codeCommit({
        repository: this.codeRepository,
      }),
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          pre_build: {
            commands: [
              'echo Logging in to Amazon ECR...',
              'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com',
            ],
          },
          build: {
            commands: [
              'echo Build started on `date`',
              'echo Building the Docker image...',
              'docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .',
              'docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG',
            ],
          },
          post_build: {
            commands: [
              'echo Build completed on `date`',
              'echo Pushing the Docker image...',
              'docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG',
              'echo Writing image definitions file...',
              'printf \'[{"name":"app2container-container","imageUri":"%s"}]\' $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG > imagedefinitions.json',
            ],
          },
        },
        artifacts: {
          files: ['imagedefinitions.json'],
        },
      }),
    });
  }

  /**
   * Create CI/CD pipeline
   */
  private createPipeline(buildProject: codebuild.Project, service: ecs.FargateService, suffix: string): codepipeline.Pipeline {
    // Create S3 bucket for pipeline artifacts
    const pipelineArtifactsBucket = new s3.Bucket(this, 'PipelineArtifacts', {
      bucketName: `pipeline-artifacts-${suffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
    });

    // Create pipeline artifacts
    const sourceOutput = new codepipeline.Artifact('SourceOutput');
    const buildOutput = new codepipeline.Artifact('BuildOutput');

    // Create CodePipeline role
    const pipelineRole = new iam.Role(this, 'PipelineRole', {
      assumedBy: new iam.ServicePrincipal('codepipeline.amazonaws.com'),
      inlinePolicies: {
        PipelinePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketVersioning',
                's3:GetObject',
                's3:GetObjectVersion',
                's3:PutObject',
              ],
              resources: [
                pipelineArtifactsBucket.bucketArn,
                pipelineArtifactsBucket.arnForObjects('*'),
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codecommit:CancelUploadArchive',
                'codecommit:GetBranch',
                'codecommit:GetCommit',
                'codecommit:GetRepository',
                'codecommit:ListBranches',
                'codecommit:ListRepositories',
              ],
              resources: [this.codeRepository.repositoryArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'codebuild:BatchGetBuilds',
                'codebuild:StartBuild',
              ],
              resources: [buildProject.projectArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ecs:DescribeServices',
                'ecs:DescribeTaskDefinition',
                'ecs:DescribeTasks',
                'ecs:ListTasks',
                'ecs:RegisterTaskDefinition',
                'ecs:UpdateService',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iam:PassRole',
              ],
              resources: ['*'],
              conditions: {
                StringEqualsIfExists: {
                  'iam:PassedToService': [
                    'ecs-tasks.amazonaws.com',
                  ],
                },
              },
            }),
          ],
        }),
      },
    });

    return new codepipeline.Pipeline(this, 'App2ContainerPipeline', {
      pipelineName: `app2container-pipeline-${suffix}`,
      role: pipelineRole,
      artifactBucket: pipelineArtifactsBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipelineActions.CodeCommitSourceAction({
              actionName: 'Source',
              repository: this.codeRepository,
              branch: 'main',
              output: sourceOutput,
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipelineActions.CodeBuildAction({
              actionName: 'Build',
              project: buildProject,
              input: sourceOutput,
              outputs: [buildOutput],
            }),
          ],
        },
        {
          stageName: 'Deploy',
          actions: [
            new codepipelineActions.EcsDeployAction({
              actionName: 'Deploy',
              service: service,
              input: buildOutput,
            }),
          ],
        },
      ],
    });
  }

  /**
   * Create CloudWatch dashboard for monitoring
   */
  private createCloudWatchDashboard(suffix: string): void {
    new cloudwatch.Dashboard(this, 'App2ContainerDashboard', {
      dashboardName: `App2Container-${suffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'ECS Service CPU Utilization',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ECS',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  ServiceName: `${this.cluster.clusterName}`,
                  ClusterName: this.cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'ECS Service Memory Utilization',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ECS',
                metricName: 'MemoryUtilization',
                dimensionsMap: {
                  ServiceName: `${this.cluster.clusterName}`,
                  ClusterName: this.cluster.clusterName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Application Load Balancer Request Count',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/ApplicationELB',
                metricName: 'RequestCount',
                dimensionsMap: {
                  LoadBalancer: this.loadBalancer.loadBalancerFullName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });
  }
}