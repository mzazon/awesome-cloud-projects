#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as codepipeline from 'aws-cdk-lib/aws-codepipeline';
import * as codepipeline_actions from 'aws-cdk-lib/aws-codepipeline-actions';
import * as codebuild from 'aws-cdk-lib/aws-codebuild';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the ProtonInfrastructureStack
 */
export interface ProtonInfrastructureStackProps extends cdk.StackProps {
  readonly environmentName: string;
  readonly vpcCidr: string;
  readonly enableContainerInsights?: boolean;
  readonly enableLogging?: boolean;
}

/**
 * VPC Construct for reusable networking components
 */
export class VpcConstruct extends Construct {
  public readonly vpc: ec2.Vpc;
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly privateSubnets: ec2.ISubnet[];

  constructor(scope: Construct, id: string, props: { vpcName: string; cidrBlock: string }) {
    super(scope, id);

    // Create VPC with public and private subnets across multiple AZs
    this.vpc = new ec2.Vpc(this, 'Vpc', {
      vpcName: props.vpcName,
      ipAddresses: ec2.IpAddresses.cidr(props.cidrBlock),
      maxAzs: 2,
      natGateways: 1,
      enableDnsHostnames: true,
      enableDnsSupport: true,
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
        }
      ]
    });

    this.publicSubnets = this.vpc.publicSubnets;
    this.privateSubnets = this.vpc.privateSubnets;

    // Add flow logs for security monitoring
    new ec2.FlowLog(this, 'VpcFlowLog', {
      resourceType: ec2.FlowLogResourceType.fromVpc(this.vpc),
      destination: ec2.FlowLogDestination.toCloudWatchLogs(),
    });

    // Output VPC information for Proton templates
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for Proton services',
      exportName: `${props.vpcName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'PublicSubnetIds', {
      value: this.publicSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Public subnet IDs',
      exportName: `${props.vpcName}-PublicSubnetIds`,
    });

    new cdk.CfnOutput(this, 'PrivateSubnetIds', {
      value: this.privateSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'Private subnet IDs',
      exportName: `${props.vpcName}-PrivateSubnetIds`,
    });
  }
}

/**
 * ECS Construct for container orchestration
 */
export class EcsConstruct extends Construct {
  public readonly cluster: ecs.Cluster;
  public readonly taskRole: iam.Role;
  public readonly executionRole: iam.Role;

  constructor(scope: Construct, id: string, props: { 
    clusterName: string; 
    vpc: ec2.Vpc; 
    enableContainerInsights?: boolean;
    enableLogging?: boolean;
  }) {
    super(scope, id);

    // Create ECS Cluster
    this.cluster = new ecs.Cluster(this, 'Cluster', {
      clusterName: props.clusterName,
      vpc: props.vpc,
      containerInsights: props.enableContainerInsights ?? true,
      enableFargateCapacityProviders: true,
    });

    // Create task execution role with required permissions
    this.executionRole = new iam.Role(this, 'TaskExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Create task role for application permissions
    this.taskRole = new iam.Role(this, 'TaskRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
    });

    // Create CloudWatch Log Group for ECS tasks
    if (props.enableLogging) {
      const logGroup = new logs.LogGroup(this, 'EcsLogGroup', {
        logGroupName: `/ecs/${props.clusterName}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      // Grant log permissions to execution role
      logGroup.grantWrite(this.executionRole);
    }

    // Output cluster information
    new cdk.CfnOutput(this, 'ClusterName', {
      value: this.cluster.clusterName,
      description: 'ECS Cluster Name',
      exportName: `${props.clusterName}-ClusterName`,
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: this.cluster.clusterArn,
      description: 'ECS Cluster ARN',
      exportName: `${props.clusterName}-ClusterArn`,
    });

    new cdk.CfnOutput(this, 'TaskExecutionRoleArn', {
      value: this.executionRole.roleArn,
      description: 'Task Execution Role ARN',
      exportName: `${props.clusterName}-TaskExecutionRoleArn`,
    });

    new cdk.CfnOutput(this, 'TaskRoleArn', {
      value: this.taskRole.roleArn,
      description: 'Task Role ARN',
      exportName: `${props.clusterName}-TaskRoleArn`,
    });
  }
}

/**
 * Proton Template Storage Construct
 */
export class ProtonTemplateStorageConstruct extends Construct {
  public readonly templateBucket: s3.Bucket;
  public readonly protonServiceRole: iam.Role;

  constructor(scope: Construct, id: string, props: { bucketName: string }) {
    super(scope, id);

    // Create S3 bucket for Proton templates
    this.templateBucket = new s3.Bucket(this, 'TemplateBucket', {
      bucketName: props.bucketName,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Proton service
    this.protonServiceRole = new iam.Role(this, 'ProtonServiceRole', {
      assumedBy: new iam.ServicePrincipal('proton.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSProtonFullAccess'),
      ],
      inlinePolicies: {
        'ProtonTemplateAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:ListBucket',
              ],
              resources: [
                this.templateBucket.bucketArn,
                this.templateBucket.arnForObjects('*'),
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudformation:CreateStack',
                'cloudformation:UpdateStack',
                'cloudformation:DeleteStack',
                'cloudformation:DescribeStacks',
                'cloudformation:DescribeStackEvents',
                'cloudformation:DescribeStackResources',
                'cloudformation:GetTemplate',
                'cloudformation:ValidateTemplate',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Grant Proton service access to the bucket
    this.templateBucket.grantRead(this.protonServiceRole);

    // Output bucket information
    new cdk.CfnOutput(this, 'TemplateBucketName', {
      value: this.templateBucket.bucketName,
      description: 'S3 Bucket for Proton templates',
      exportName: `${props.bucketName}-TemplateBucketName`,
    });

    new cdk.CfnOutput(this, 'ProtonServiceRoleArn', {
      value: this.protonServiceRole.roleArn,
      description: 'IAM Role ARN for Proton service',
      exportName: `${props.bucketName}-ProtonServiceRoleArn`,
    });
  }
}

/**
 * CI/CD Pipeline Construct for automated deployments
 */
export class CiCdPipelineConstruct extends Construct {
  public readonly pipeline: codepipeline.Pipeline;
  public readonly artifactBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props: {
    pipelineName: string;
    templateBucket: s3.Bucket;
    protonServiceRole: iam.Role;
  }) {
    super(scope, id);

    // Create artifact bucket for pipeline
    this.artifactBucket = new s3.Bucket(this, 'ArtifactBucket', {
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create CodeBuild project for template validation
    const buildProject = new codebuild.Project(this, 'TemplateBuildProject', {
      projectName: `${props.pipelineName}-template-validation`,
      source: codebuild.Source.codeCommit({
        repository: codebuild.Repository.fromRepositoryName(this, 'SourceRepo', 'proton-templates'),
      }),
      environment: {
        buildImage: codebuild.LinuxBuildImage.STANDARD_5_0,
        privileged: true,
      },
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
              'echo Validating CloudFormation templates...',
              'aws cloudformation validate-template --template-body file://environment-template/infrastructure.yaml',
              'echo Creating template bundle...',
              'tar -czf environment-template.tar.gz -C environment-template .',
            ],
          },
          post_build: {
            commands: [
              'echo Build completed on `date`',
              'echo Uploading template to S3...',
              `aws s3 cp environment-template.tar.gz s3://${props.templateBucket.bucketName}/`,
            ],
          },
        },
        artifacts: {
          files: [
            '**/*',
          ],
        },
      }),
    });

    // Grant necessary permissions to build project
    props.templateBucket.grantWrite(buildProject);
    buildProject.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudformation:ValidateTemplate',
        'ecr:BatchCheckLayerAvailability',
        'ecr:GetDownloadUrlForLayer',
        'ecr:BatchGetImage',
        'ecr:GetAuthorizationToken',
      ],
      resources: ['*'],
    }));

    // Create the pipeline
    const sourceOutput = new codepipeline.Artifact();
    const buildOutput = new codepipeline.Artifact();

    this.pipeline = new codepipeline.Pipeline(this, 'Pipeline', {
      pipelineName: props.pipelineName,
      artifactBucket: this.artifactBucket,
      stages: [
        {
          stageName: 'Source',
          actions: [
            new codepipeline_actions.S3SourceAction({
              actionName: 'Source',
              bucket: props.templateBucket,
              bucketKey: 'source.zip',
              output: sourceOutput,
            }),
          ],
        },
        {
          stageName: 'Build',
          actions: [
            new codepipeline_actions.CodeBuildAction({
              actionName: 'ValidateTemplates',
              project: buildProject,
              input: sourceOutput,
              outputs: [buildOutput],
            }),
          ],
        },
      ],
    });

    // Output pipeline information
    new cdk.CfnOutput(this, 'PipelineName', {
      value: this.pipeline.pipelineName,
      description: 'CI/CD Pipeline Name',
      exportName: `${props.pipelineName}-PipelineName`,
    });

    new cdk.CfnOutput(this, 'ArtifactBucketName', {
      value: this.artifactBucket.bucketName,
      description: 'Pipeline Artifact Bucket Name',
      exportName: `${props.pipelineName}-ArtifactBucketName`,
    });
  }
}

/**
 * Main stack for AWS Proton infrastructure automation
 */
export class ProtonInfrastructureStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ProtonInfrastructureStackProps) {
    super(scope, id, props);

    // Create VPC for the environment
    const vpcConstruct = new VpcConstruct(this, 'VpcConstruct', {
      vpcName: `${props.environmentName}-vpc`,
      cidrBlock: props.vpcCidr,
    });

    // Create ECS Cluster
    const ecsConstruct = new EcsConstruct(this, 'EcsConstruct', {
      clusterName: `${props.environmentName}-cluster`,
      vpc: vpcConstruct.vpc,
      enableContainerInsights: props.enableContainerInsights ?? true,
      enableLogging: props.enableLogging ?? true,
    });

    // Create Proton template storage
    const templateStorage = new ProtonTemplateStorageConstruct(this, 'TemplateStorage', {
      bucketName: `${props.environmentName}-proton-templates-${this.account}`,
    });

    // Create CI/CD pipeline
    const cicdPipeline = new CiCdPipelineConstruct(this, 'CiCdPipeline', {
      pipelineName: `${props.environmentName}-proton-pipeline`,
      templateBucket: templateStorage.templateBucket,
      protonServiceRole: templateStorage.protonServiceRole,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Environment', props.environmentName);
    cdk.Tags.of(this).add('Project', 'ProtonInfrastructureAutomation');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'DevOps-Platform');

    // Stack-level outputs
    new cdk.CfnOutput(this, 'StackName', {
      value: this.stackName,
      description: 'CloudFormation Stack Name',
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
    });

    new cdk.CfnOutput(this, 'AccountId', {
      value: this.account,
      description: 'AWS Account ID',
    });
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get environment configuration from context or environment variables
const environmentName = app.node.tryGetContext('environmentName') || process.env.ENVIRONMENT_NAME || 'dev';
const vpcCidr = app.node.tryGetContext('vpcCidr') || process.env.VPC_CIDR || '10.0.0.0/16';
const enableContainerInsights = app.node.tryGetContext('enableContainerInsights') === 'true' || 
                                process.env.ENABLE_CONTAINER_INSIGHTS === 'true';
const enableLogging = app.node.tryGetContext('enableLogging') === 'true' || 
                     process.env.ENABLE_LOGGING === 'true';

// Create the main stack
new ProtonInfrastructureStack(app, 'ProtonInfrastructureStack', {
  environmentName,
  vpcCidr,
  enableContainerInsights,
  enableLogging,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'AWS Proton Infrastructure Automation with CDK - Self-service infrastructure platform',
});

// Synthesize the app
app.synth();