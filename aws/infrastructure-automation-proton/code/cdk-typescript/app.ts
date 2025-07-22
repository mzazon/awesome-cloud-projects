#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ecsPatterns from 'aws-cdk-lib/aws-ecs-patterns';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipelineActions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import { Construct } from 'constructs';

/**
 * AWS Proton Environment Template Stack
 * 
 * Creates a standardized environment with VPC, ECS cluster, and supporting infrastructure
 * that can be used as a foundation for Proton service deployments.
 */
class ProtonEnvironmentStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly cluster: ecs.Cluster;
  public readonly templateBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC with public and private subnets across multiple AZs
    // This provides the network foundation for all services in the environment
    this.vpc = new ec2.Vpc(this, 'ProtonVPC', {
      maxAzs: 3,
      natGateways: 2, // For high availability
      cidr: '10.0.0.0/16',
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
        {
          cidrMask: 24,
          name: 'Isolated',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Create ECS Cluster for containerized workloads
    // Enable CloudWatch Container Insights for monitoring
    this.cluster = new ecs.Cluster(this, 'ProtonECSCluster', {
      vpc: this.vpc,
      clusterName: 'proton-environment-cluster',
      containerInsights: true,
      enableFargateCapacityProviders: true,
    });

    // Add EC2 capacity provider for cost optimization when needed
    const autoScalingGroup = new cdk.aws_autoscaling.AutoScalingGroup(this, 'ECSAutoScalingGroup', {
      vpc: this.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      machineImage: ecs.EcsOptimizedImage.amazonLinux2(),
      minCapacity: 0,
      maxCapacity: 10,
      desiredCapacity: 0,
    });

    const capacityProvider = new ecs.AsgCapacityProvider(this, 'ECSCapacityProvider', {
      autoScalingGroup,
      enableManagedScaling: true,
      enableManagedTerminationProtection: false,
    });

    this.cluster.addAsgCapacityProvider(capacityProvider);

    // Create S3 bucket for storing Proton template bundles
    // This bucket will store the compressed template archives
    this.templateBucket = new s3.Bucket(this, 'ProtonTemplateBucket', {
      bucketName: `proton-templates-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM service role for AWS Proton
    // This role allows Proton to provision infrastructure on your behalf
    const protonServiceRole = new iam.Role(this, 'ProtonServiceRole', {
      roleName: `ProtonServiceRole-${cdk.Aws.REGION}`,
      assumedBy: new iam.ServicePrincipal('proton.amazonaws.com'),
      description: 'Service role for AWS Proton to provision infrastructure',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSProtonServiceRole'),
      ],
    });

    // Add additional permissions for CloudFormation and ECS operations
    protonServiceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudformation:*',
        'ecs:*',
        'ec2:*',
        'elasticloadbalancing:*',
        'logs:*',
        'iam:PassRole',
        'application-autoscaling:*',
      ],
      resources: ['*'],
    }));

    // Output important values for Proton template creation
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for Proton service templates',
      exportName: 'ProtonEnvironmentVpcId',
    });

    new cdk.CfnOutput(this, 'ECSClusterName', {
      value: this.cluster.clusterName,
      description: 'ECS Cluster name for service deployments',
      exportName: 'ProtonEnvironmentECSCluster',
    });

    new cdk.CfnOutput(this, 'ECSClusterArn', {
      value: this.cluster.clusterArn,
      description: 'ECS Cluster ARN for service deployments',
      exportName: 'ProtonEnvironmentECSClusterArn',
    });

    new cdk.CfnOutput(this, 'TemplateBucketName', {
      value: this.templateBucket.bucketName,
      description: 'S3 bucket for storing Proton templates',
      exportName: 'ProtonTemplateBucket',
    });

    new cdk.CfnOutput(this, 'ProtonServiceRoleArn', {
      value: protonServiceRole.roleArn,
      description: 'AWS Proton service role ARN',
      exportName: 'ProtonServiceRoleArn',
    });

    new cdk.CfnOutput(this, 'PrivateSubnetIds', {
      value: this.vpc.privateSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Private subnet IDs for service deployments',
      exportName: 'ProtonPrivateSubnetIds',
    });

    new cdk.CfnOutput(this, 'PublicSubnetIds', {
      value: this.vpc.publicSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Public subnet IDs for load balancers',
      exportName: 'ProtonPublicSubnetIds',
    });
  }
}

/**
 * AWS Proton Service Template Stack
 * 
 * Creates a Fargate-based web service with load balancer, auto-scaling,
 * and monitoring capabilities. This template can be used by Proton to
 * deploy services into the environment created above.
 */
class ProtonServiceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Import VPC from environment template
    // In actual Proton deployment, this would use template variables
    const vpc = ec2.Vpc.fromLookup(this, 'ImportedVPC', {
      isDefault: false,
      // This would be replaced with {{environment.outputs.VpcId}} in Proton
      vpcId: 'vpc-placeholder',
    });

    // Import ECS Cluster from environment template
    const cluster = ecs.Cluster.fromClusterAttributes(this, 'ImportedCluster', {
      // This would be replaced with {{environment.outputs.ECSClusterName}} in Proton
      clusterName: 'proton-environment-cluster',
      vpc: vpc,
    });

    // Create CloudWatch log group for service logs
    const logGroup = new logs.LogGroup(this, 'ServiceLogGroup', {
      // This would be replaced with /aws/ecs/{{service.name}}-{{service_instance.name}} in Proton
      logGroupName: '/aws/ecs/web-service-dev-instance',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Application Load Balanced Fargate Service
    // This provides a complete web service with load balancer and auto-scaling
    const fargateService = new ecsPatterns.ApplicationLoadBalancedFargateService(this, 'WebService', {
      cluster: cluster,
      // Service name would be {{service.name}}-{{service_instance.name}} in Proton
      serviceName: 'web-service-dev-instance',
      taskImageOptions: {
        // Container image would be {{service_instance.inputs.image}} in Proton
        image: ecs.ContainerImage.fromRegistry('nginx:latest'),
        // Container port would be {{service_instance.inputs.port}} in Proton
        containerPort: 80,
        environment: {
          // Environment would be {{service_instance.inputs.environment}} in Proton
          NODE_ENV: 'development',
          // Service name would be {{service.name}} in Proton
          SERVICE_NAME: 'web-service',
        },
        logDriver: ecs.LogDrivers.awsLogs({
          streamPrefix: 'web-service',
          logGroup: logGroup,
        }),
      },
      // Memory would be {{service_instance.inputs.memory}} in Proton
      memoryLimitMiB: 512,
      // CPU would be {{service_instance.inputs.cpu}} in Proton
      cpu: 256,
      // Desired count would be {{service_instance.inputs.desired_count}} in Proton
      desiredCount: 2,
      publicLoadBalancer: true,
      listenerPort: 80,
    });

    // Configure health check for the load balancer target group
    fargateService.targetGroup.configureHealthCheck({
      // Health check path would be {{service_instance.inputs.health_check_path}} in Proton
      path: '/',
      healthyHttpCodes: '200,404',
      interval: cdk.Duration.seconds(30),
      timeout: cdk.Duration.seconds(5),
      healthyThresholdCount: 2,
      unhealthyThresholdCount: 3,
    });

    // Configure auto-scaling for the ECS service
    const scaling = fargateService.service.autoScaleTaskCount({
      // Min capacity would be {{service_instance.inputs.min_capacity}} in Proton
      minCapacity: 1,
      // Max capacity would be {{service_instance.inputs.max_capacity}} in Proton
      maxCapacity: 10,
    });

    // Scale based on CPU utilization
    scaling.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: 70,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(2),
    });

    // Scale based on memory utilization
    scaling.scaleOnMemoryUtilization('MemoryScaling', {
      targetUtilizationPercent: 80,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(2),
    });

    // Create CloudWatch alarms for monitoring
    const cpuAlarm = new cdk.aws_cloudwatch.Alarm(this, 'HighCpuAlarm', {
      metric: fargateService.service.metricCpuUtilization({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 3,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const memoryAlarm = new cdk.aws_cloudwatch.Alarm(this, 'HighMemoryAlarm', {
      metric: fargateService.service.metricMemoryUtilization({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 85,
      evaluationPeriods: 3,
      treatMissingData: cdk.aws_cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important service information
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: fargateService.loadBalancer.loadBalancerDnsName,
      description: 'Load Balancer DNS name for accessing the service',
    });

    new cdk.CfnOutput(this, 'ServiceArn', {
      value: fargateService.service.serviceArn,
      description: 'ECS Service ARN',
    });

    new cdk.CfnOutput(this, 'ServiceName', {
      value: fargateService.service.serviceName,
      description: 'ECS Service name',
    });

    new cdk.CfnOutput(this, 'TaskDefinitionArn', {
      value: fargateService.taskDefinition.taskDefinitionArn,
      description: 'ECS Task Definition ARN',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch Log Group name for service logs',
    });
  }
}

/**
 * CI/CD Pipeline Stack for Proton Templates
 * 
 * Creates a CodePipeline that automatically builds and deploys Proton templates
 * when source code changes are committed to the repository.
 */
class ProtonPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create CodeCommit repository for storing template source code
    const templateRepository = new codecommit.Repository(this, 'ProtonTemplateRepository', {
      repositoryName: 'proton-templates',
      description: 'Repository for AWS Proton template source code',
    });

    // Create S3 bucket for pipeline artifacts
    const artifactBucket = new s3.Bucket(this, 'PipelineArtifacts', {
      bucketName: `proton-pipeline-artifacts-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'delete-old-artifacts',
          enabled: true,
          expiration: cdk.Duration.days(30),
        },
      ],
    });

    // Create IAM role for CodeBuild
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'Role for CodeBuild to build and deploy Proton templates',
    });

    // Add permissions for CodeBuild to work with Proton and S3
    codeBuildRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        'proton:*',
        'cdk:*',
        'cloudformation:*',
      ],
      resources: ['*'],
    }));

    // Create CodeBuild project for building and deploying templates
    const buildProject = new codebuild.Project(this, 'ProtonTemplateBuild', {
      projectName: 'proton-template-build',
      description: 'Build and deploy Proton templates from CDK source',
      source: codebuild.Source.codeCommit({
        repository: templateRepository,
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_7_0,
        computeType: codebuild.ComputeType.SMALL,
        privileged: true, // Required for Docker builds
      },
      role: codeBuildRole,
      buildSpec: codebuild.BuildSpec.fromObject({
        version: '0.2',
        phases: {
          install: {
            'runtime-versions': {
              nodejs: '18',
            },
            commands: [
              'npm install -g aws-cdk',
              'npm install -g typescript',
            ],
          },
          pre_build: {
            commands: [
              'echo Logging in to Amazon ECR...',
              'aws --version',
              'echo Build started on `date`',
            ],
          },
          build: {
            commands: [
              'echo Build phase started on `date`',
              'cd environment-template',
              'npm install',
              'npm run build',
              'cdk synth',
              'cd ../service-template',
              'npm install',
              'npm run build',
              'cdk synth',
              'cd ..',
              'echo Creating template bundles...',
              './create-template-bundles.sh',
            ],
          },
          post_build: {
            commands: [
              'echo Build completed on `date`',
              'echo Uploading template bundles to S3...',
              'aws s3 cp environment-template-v1.tar.gz s3://${TEMPLATE_BUCKET}/',
              'aws s3 cp service-template-v1.tar.gz s3://${TEMPLATE_BUCKET}/',
              'echo Template bundles uploaded successfully',
            ],
          },
        },
        artifacts: {
          files: [
            '**/*',
          ],
        },
      }),
      environmentVariables: {
        TEMPLATE_BUCKET: {
          type: codebuild.BuildEnvironmentVariableType.PLAINTEXT,
          value: `proton-templates-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
        },
      },
    });

    // Create CodePipeline
    const sourceOutput = new codepipeline.Artifact('SourceOutput');

    const pipeline = new codepipeline.Pipeline(this, 'ProtonTemplatePipeline', {
      pipelineName: 'proton-template-pipeline',
      artifactBucket: artifactBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipelineActions.CodeCommitSourceAction({
              actionName: 'Source',
              repository: templateRepository,
              output: sourceOutput,
              branch: 'main',
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipelineActions.CodeBuildAction({
              actionName: 'BuildAndDeploy',
              project: buildProject,
              input: sourceOutput,
            }),
          ],
        },
      ],
    });

    // Output repository information
    new cdk.CfnOutput(this, 'RepositoryName', {
      value: templateRepository.repositoryName,
      description: 'CodeCommit repository name for Proton templates',
    });

    new cdk.CfnOutput(this, 'RepositoryCloneUrl', {
      value: templateRepository.repositoryCloneUrlHttp,
      description: 'Repository clone URL for development',
    });

    new cdk.CfnOutput(this, 'PipelineName', {
      value: pipeline.pipelineName,
      description: 'CodePipeline name for template deployment',
    });
  }
}

// Create CDK App and instantiate stacks
const app = new cdk.App();

// Environment stack - creates foundational infrastructure
const environmentStack = new ProtonEnvironmentStack(app, 'ProtonEnvironmentStack', {
  description: 'AWS Proton Environment Template - VPC and ECS infrastructure',
  tags: {
    'Proton:Template': 'Environment',
    'Purpose': 'Infrastructure-Automation',
  },
});

// Service stack - creates service deployment template
const serviceStack = new ProtonServiceStack(app, 'ProtonServiceStack', {
  description: 'AWS Proton Service Template - Fargate web service',
  tags: {
    'Proton:Template': 'Service',
    'Purpose': 'Infrastructure-Automation',
  },
});

// Pipeline stack - creates CI/CD for template management
const pipelineStack = new ProtonPipelineStack(app, 'ProtonPipelineStack', {
  description: 'CI/CD Pipeline for AWS Proton templates',
  tags: {
    'Proton:Template': 'Pipeline',
    'Purpose': 'Infrastructure-Automation',
  },
});

// Add dependencies
serviceStack.addDependency(environmentStack);