#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as codecommit from 'aws-cdk-lib/aws-codecommit';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * CDK Stack for GitOps with CodeCommit and CodeBuild
 * This stack creates a complete CI/CD pipeline for containerized applications
 * following GitOps principles where Git operations trigger automated deployments
 */
class GitOpsWorkflowStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Stack parameters for customization
    const projectName = new cdk.CfnParameter(this, 'ProjectName', {
      type: 'String',
      description: 'Name of the GitOps project',
      default: 'gitops-demo',
      minLength: 3,
      maxLength: 50,
      allowedPattern: '[a-zA-Z0-9-]*',
      constraintDescription: 'Must be 3-50 characters long and contain only alphanumeric characters and hyphens'
    });

    const environment = new cdk.CfnParameter(this, 'Environment', {
      type: 'String',
      description: 'Deployment environment',
      default: 'dev',
      allowedValues: ['dev', 'staging', 'prod'],
      constraintDescription: 'Must be one of: dev, staging, prod'
    });

    const containerPort = new cdk.CfnParameter(this, 'ContainerPort', {
      type: 'Number',
      description: 'Port number for the application container',
      default: 3000,
      minValue: 1,
      maxValue: 65535
    });

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Fn.select(2, cdk.Fn.split('-', cdk.Fn.select(1, cdk.Fn.split('/', this.stackId))));

    // Create VPC for ECS cluster with public and private subnets
    const vpc = new ec2.Vpc(this, 'GitOpsVPC', {
      maxAzs: 2,
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
        }
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true
    });

    // Add VPC tags for better resource management
    cdk.Tags.of(vpc).add('Name', `${projectName.valueAsString}-vpc`);
    cdk.Tags.of(vpc).add('Environment', environment.valueAsString);
    cdk.Tags.of(vpc).add('Project', 'GitOps-Workflow');

    // Create S3 bucket for CodePipeline artifacts
    const artifactBucket = new s3.Bucket(this, 'ArtifactBucket', {
      bucketName: `${projectName.valueAsString}-artifacts-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [{
        id: 'artifact-cleanup',
        enabled: true,
        expiration: cdk.Duration.days(30),
        noncurrentVersionExpiration: cdk.Duration.days(7)
      }],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true
    });

    // Create CodeCommit repository for GitOps source control
    const repository = new codecommit.Repository(this, 'GitOpsRepository', {
      repositoryName: `${projectName.valueAsString}-repo`,
      description: 'GitOps repository for automated deployments with full audit trail',
      code: codecommit.Code.fromZipFile('initial-commit.zip', `
# GitOps Demo Repository

This repository demonstrates GitOps workflows with AWS CodeCommit and CodeBuild.

## Structure

- \`app/\` - Application source code
- \`infrastructure/\` - Infrastructure as Code definitions
- \`config/\` - CI/CD configuration files

## Getting Started

1. Clone this repository
2. Make changes to application code
3. Commit and push changes
4. Watch automated deployment pipeline execute

## GitOps Principles

- Declarative configuration
- Version-controlled infrastructure
- Automated deployments
- Observable systems
`)
    });

    // Create ECR repository for container images
    const ecrRepository = new ecr.Repository(this, 'ECRRepository', {
      repositoryName: `${projectName.valueAsString}-app`,
      imageScanOnPush: true,
      lifecycleRules: [{
        maxImageCount: 10,
        tagStatus: ecr.TagStatus.UNTAGGED
      }, {
        maxImageCount: 5,
        tagStatus: ecr.TagStatus.TAGGED,
        tagPrefixList: ['prod']
      }],
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create CloudWatch log group for application logs
    const logGroup = new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: `/ecs/${projectName.valueAsString}-app`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create ECS cluster for container orchestration
    const cluster = new ecs.Cluster(this, 'ECSCluster', {
      clusterName: `${projectName.valueAsString}-cluster`,
      vpc: vpc,
      containerInsights: true
    });

    // Create task execution role with necessary permissions
    const taskExecutionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy')
      ]
    });

    // Grant ECR permissions to task execution role
    ecrRepository.grantPull(taskExecutionRole);
    logGroup.grantWrite(taskExecutionRole);

    // Create ECS task definition for the application
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'TaskDefinition', {
      memoryLimitMiB: 512,
      cpu: 256,
      executionRole: taskExecutionRole
    });

    // Add container to task definition
    const container = taskDefinition.addContainer('app', {
      image: ecs.ContainerImage.fromEcrRepository(ecrRepository, 'latest'),
      memoryReservationMiB: 512,
      environment: {
        ENVIRONMENT: environment.valueAsString,
        APP_VERSION: '1.0.0'
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'ecs',
        logGroup: logGroup
      }),
      healthCheck: {
        command: ['CMD-SHELL', 'curl -f http://localhost:3000/health || exit 1'],
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        retries: 3,
        startPeriod: cdk.Duration.seconds(60)
      }
    });

    // Add port mapping for the application
    container.addPortMappings({
      containerPort: containerPort.valueAsNumber,
      protocol: ecs.Protocol.TCP
    });

    // Create Application Load Balancer
    const alb = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc: vpc,
      internetFacing: true,
      loadBalancerName: `${projectName.valueAsString}-alb`,
      securityGroup: new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
        vpc: vpc,
        description: 'Security group for Application Load Balancer',
        allowAllOutbound: true
      })
    });

    // Add ingress rule for HTTP traffic
    alb.connections.allowFromAnyIpv4(ec2.Port.tcp(80), 'Allow HTTP inbound traffic');

    // Create target group for ECS service
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'TargetGroup', {
      port: containerPort.valueAsNumber,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.IP,
      vpc: vpc,
      healthCheck: {
        enabled: true,
        path: '/health',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3
      }
    });

    // Create listener for ALB
    alb.addListener('ALBListener', {
      port: 80,
      defaultTargetGroups: [targetGroup]
    });

    // Create ECS service
    const service = new ecs.FargateService(this, 'ECSService', {
      cluster: cluster,
      taskDefinition: taskDefinition,
      desiredCount: 1,
      assignPublicIp: false,
      securityGroups: [new ec2.SecurityGroup(this, 'ServiceSecurityGroup', {
        vpc: vpc,
        description: 'Security group for ECS service',
        allowAllOutbound: true
      })],
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS
      },
      enableExecuteCommand: true
    });

    // Allow connections from ALB to ECS service
    service.connections.allowFrom(alb, ec2.Port.tcp(containerPort.valueAsNumber));

    // Attach service to target group
    service.attachToApplicationTargetGroup(targetGroup);

    // Create CodeBuild service role with comprehensive permissions
    const codeBuildRole = new iam.Role(this, 'CodeBuildRole', {
      assumedBy: new iam.ServicePrincipal('codebuild.amazonaws.com'),
      description: 'Service role for CodeBuild project with GitOps permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess')
      ]
    });

    // Grant ECR permissions to CodeBuild
    ecrRepository.grantPullPush(codeBuildRole);

    // Grant ECS permissions to CodeBuild for deployments
    codeBuildRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ecs:UpdateService',
        'ecs:DescribeServices',
        'ecs:DescribeTaskDefinition',
        'ecs:RegisterTaskDefinition'
      ],
      resources: ['*']
    }));

    // Grant IAM permissions for task definition updates
    codeBuildRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'iam:PassRole'
      ],
      resources: [taskExecutionRole.roleArn]
    }));

    // Create comprehensive buildspec for GitOps pipeline
    const buildSpec = codebuild.BuildSpec.fromObject({
      version: '0.2',
      phases: {
        pre_build: {
          commands: [
            'echo Logging in to Amazon ECR...',
            'aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URI',
            'COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)',
            'IMAGE_TAG=$COMMIT_HASH',
            'echo Build started on `date`',
            'echo Building the Docker image...'
          ]
        },
        build: {
          commands: [
            'cd app',
            'docker build -t $ECR_REPOSITORY_URI:latest .',
            'docker tag $ECR_REPOSITORY_URI:latest $ECR_REPOSITORY_URI:$IMAGE_TAG'
          ]
        },
        post_build: {
          commands: [
            'echo Build completed on `date`',
            'echo Pushing the Docker images...',
            'docker push $ECR_REPOSITORY_URI:latest',
            'docker push $ECR_REPOSITORY_URI:$IMAGE_TAG',
            'echo Writing image definitions file...',
            'printf \'[{"name":"app","imageUri":"%s"}]\' $ECR_REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json',
            'cat imagedefinitions.json'
          ]
        }
      },
      artifacts: {
        files: ['imagedefinitions.json']
      },
      env: {
        'exported-variables': ['IMAGE_TAG']
      }
    });

    // Create CodeBuild project for automated builds
    const codeBuildProject = new codebuild.Project(this, 'CodeBuildProject', {
      projectName: `${projectName.valueAsString}-build`,
      description: 'GitOps build project for automated CI/CD pipeline',
      source: codebuild.Source.codeCommit({
        repository: repository,
        branchOrRef: 'main'
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.AMAZON_LINUX_2_5,
        computeType: codebuild.ComputeType.SMALL,
        privileged: true,
        environmentVariables: {
          ECR_REPOSITORY_URI: {
            value: ecrRepository.repositoryUri
          },
          AWS_DEFAULT_REGION: {
            value: this.region
          },
          AWS_ACCOUNT_ID: {
            value: this.account
          },
          ENVIRONMENT: {
            value: environment.valueAsString
          }
        }
      },
      buildSpec: buildSpec,
      role: codeBuildRole,
      timeout: cdk.Duration.minutes(15)
    });

    // Create CodePipeline service role
    const codePipelineRole = new iam.Role(this, 'CodePipelineRole', {
      assumedBy: new iam.ServicePrincipal('codepipeline.amazonaws.com'),
      description: 'Service role for CodePipeline with GitOps permissions'
    });

    // Grant necessary permissions to CodePipeline
    artifactBucket.grantReadWrite(codePipelineRole);
    repository.grantPull(codePipelineRole);
    codeBuildProject.grantStartBuildAndViewLog(codePipelineRole);

    // Grant ECS permissions to CodePipeline for deployments
    codePipelineRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ecs:UpdateService',
        'ecs:DescribeServices',
        'ecs:DescribeTaskDefinition',
        'ecs:RegisterTaskDefinition'
      ],
      resources: ['*']
    }));

    // Grant IAM permissions for task definition updates
    codePipelineRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'iam:PassRole'
      ],
      resources: [taskExecutionRole.roleArn]
    }));

    // Create source output artifact
    const sourceOutput = new codepipeline.Artifact('SourceOutput');
    const buildOutput = new codepipeline.Artifact('BuildOutput');

    // Create comprehensive CodePipeline for GitOps workflow
    const pipeline = new codepipeline.Pipeline(this, 'GitOpsPipeline', {
      pipelineName: `${projectName.valueAsString}-pipeline`,
      artifactBucket: artifactBucket,
      role: codePipelineRole,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.CodeCommitSourceAction({
              actionName: 'Source',
              repository: repository,
              branch: 'main',
              output: sourceOutput,
              trigger: codepipeline_actions.CodeCommitTrigger.EVENTS
            })
          ]
        },
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'Build',
              project: codeBuildProject,
              input: sourceOutput,
              outputs: [buildOutput]
            })
          ]
        },
        {
          stageName: 'Deploy',
          actions: [
            new codepipeline_actions.EcsDeployAction({
              actionName: 'Deploy',
              service: service,
              input: buildOutput,
              deploymentTimeout: cdk.Duration.minutes(10)
            })
          ]
        }
      ]
    });

    // Add comprehensive stack outputs for verification and integration
    new cdk.CfnOutput(this, 'RepositoryCloneURL', {
      value: repository.repositoryCloneUrlHttp,
      description: 'CodeCommit repository clone URL for GitOps workflow',
      exportName: `${this.stackName}-RepositoryCloneURL`
    });

    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: ecrRepository.repositoryUri,
      description: 'ECR repository URI for container images',
      exportName: `${this.stackName}-ECRRepositoryURI`
    });

    new cdk.CfnOutput(this, 'PipelineName', {
      value: pipeline.pipelineName,
      description: 'CodePipeline name for GitOps automation',
      exportName: `${this.stackName}-PipelineName`
    });

    new cdk.CfnOutput(this, 'ApplicationLoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'Application Load Balancer DNS name for accessing the application',
      exportName: `${this.stackName}-ApplicationLoadBalancerDNS`
    });

    new cdk.CfnOutput(this, 'ECSClusterName', {
      value: cluster.clusterName,
      description: 'ECS cluster name for container orchestration',
      exportName: `${this.stackName}-ECSClusterName`
    });

    new cdk.CfnOutput(this, 'ECSServiceName', {
      value: service.serviceName,
      description: 'ECS service name for application deployment',
      exportName: `${this.stackName}-ECSServiceName`
    });

    new cdk.CfnOutput(this, 'ApplicationURL', {
      value: `http://${alb.loadBalancerDnsName}`,
      description: 'Application URL for testing the GitOps deployment',
      exportName: `${this.stackName}-ApplicationURL`
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch log group name for application logs',
      exportName: `${this.stackName}-LogGroupName`
    });

    // Add resource tags for better organization and cost tracking
    const commonTags = {
      Project: 'GitOps-Workflow',
      Environment: environment.valueAsString,
      ManagedBy: 'CDK',
      Recipe: 'gitops-workflows-aws-codecommit-codebuild'
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }
}

// Create CDK app and instantiate the stack
const app = new cdk.App();

new GitOpsWorkflowStack(app, 'GitOpsWorkflowStack', {
  description: 'CDK Stack for GitOps workflows with AWS CodeCommit, CodeBuild, and ECS (qs-1234567890)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  tags: {
    Project: 'GitOps-Workflow',
    Recipe: 'gitops-workflows-aws-codecommit-codebuild',
    Version: '1.0.0'
  }
});