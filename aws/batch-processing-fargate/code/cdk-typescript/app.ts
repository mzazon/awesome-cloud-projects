#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the BatchProcessingStack
 */
interface BatchProcessingStackProps extends cdk.StackProps {
  /**
   * Maximum number of vCPUs for the compute environment
   * @default 256
   */
  readonly maxVcpus?: number;

  /**
   * Job timeout in seconds
   * @default 3600 (1 hour)
   */
  readonly jobTimeoutSeconds?: number;

  /**
   * Log retention period in days
   * @default 7
   */
  readonly logRetentionDays?: logs.RetentionDays;

  /**
   * Whether to create a new VPC or use the default VPC
   * @default false (use default VPC)
   */
  readonly createNewVpc?: boolean;
}

/**
 * AWS CDK Stack for Serverless Batch Processing with Fargate
 * 
 * This stack creates:
 * - ECR repository for container images
 * - IAM roles for Batch execution
 * - VPC configuration (optional)
 * - CloudWatch log group for job logging
 * - Batch compute environment using Fargate
 * - Batch job queue
 * - Sample job definition for batch processing
 */
export class BatchProcessingStack extends cdk.Stack {
  public readonly ecrRepository: ecr.Repository;
  public readonly computeEnvironment: batch.FargateComputeEnvironment;
  public readonly jobQueue: batch.JobQueue;
  public readonly jobDefinition: batch.EcsJobDefinition;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props?: BatchProcessingStackProps) {
    super(scope, id, props);

    // Configuration with defaults
    const maxVcpus = props?.maxVcpus ?? 256;
    const jobTimeoutSeconds = props?.jobTimeoutSeconds ?? 3600;
    const logRetentionDays = props?.logRetentionDays ?? logs.RetentionDays.ONE_WEEK;
    const createNewVpc = props?.createNewVpc ?? false;

    // VPC Configuration - use existing default VPC or create new one
    let vpc: ec2.IVpc;
    let securityGroup: ec2.SecurityGroup;

    if (createNewVpc) {
      // Create new VPC with public and private subnets
      vpc = new ec2.Vpc(this, 'BatchVpc', {
        maxAzs: 2,
        natGateways: 1,
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
      });

      // Create security group for Batch jobs
      securityGroup = new ec2.SecurityGroup(this, 'BatchSecurityGroup', {
        vpc,
        description: 'Security group for AWS Batch Fargate jobs',
        allowAllOutbound: true,
      });
    } else {
      // Use default VPC
      vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
        isDefault: true,
      });

      // Use default security group
      securityGroup = ec2.SecurityGroup.fromSecurityGroupId(
        this,
        'DefaultSecurityGroup',
        vpc.vpcDefaultSecurityGroup
      );
    }

    // ECR Repository for container images
    this.ecrRepository = new ecr.Repository(this, 'BatchProcessingRepository', {
      repositoryName: `batch-processing-demo-${cdk.Stack.of(this).account}`,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // CloudWatch Log Group for batch job logs
    this.logGroup = new logs.LogGroup(this, 'BatchJobLogGroup', {
      logGroupName: '/aws/batch/job',
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // IAM Execution Role for Fargate tasks
    const executionRole = new iam.Role(this, 'BatchExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'Execution role for AWS Batch Fargate tasks',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Grant ECR permissions to execution role
    this.ecrRepository.grantPull(executionRole);

    // Grant CloudWatch Logs permissions to execution role
    this.logGroup.grantWrite(executionRole);

    // IAM Job Role for the container (optional - for jobs that need AWS API access)
    const jobRole = new iam.Role(this, 'BatchJobRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      description: 'Job role for AWS Batch containers to access AWS services',
    });

    // Add basic CloudWatch permissions to job role
    jobRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogStream',
        'logs:PutLogEvents',
      ],
      resources: [this.logGroup.logGroupArn],
    }));

    // Fargate Compute Environment
    this.computeEnvironment = new batch.FargateComputeEnvironment(this, 'BatchComputeEnvironment', {
      vpc,
      securityGroups: [securityGroup],
      maxvCpus: maxVcpus,
      spot: false, // Use on-demand instances for predictable performance
      replaceComputeEnvironment: false,
      computeEnvironmentName: `batch-fargate-compute-${cdk.Stack.of(this).account}`,
    });

    // Job Queue
    this.jobQueue = new batch.JobQueue(this, 'BatchJobQueue', {
      jobQueueName: `batch-fargate-queue-${cdk.Stack.of(this).account}`,
      priority: 1,
      computeEnvironments: [
        {
          computeEnvironment: this.computeEnvironment,
          order: 1,
        },
      ],
    });

    // Container Image - use a placeholder that can be updated
    const containerImage = ecs.ContainerImage.fromEcrRepository(
      this.ecrRepository,
      'latest'
    );

    // Job Definition for Fargate
    this.jobDefinition = new batch.EcsJobDefinition(this, 'BatchJobDefinition', {
      jobDefinitionName: `batch-fargate-job-${cdk.Stack.of(this).account}`,
      platformCapabilities: [batch.PlatformCapabilities.FARGATE],
      container: new batch.EcsFargateContainerDefinition(this, 'BatchContainer', {
        image: containerImage,
        cpu: 0.25, // 0.25 vCPU
        memory: cdk.Size.mebibytes(512), // 512 MiB
        executionRole,
        jobRole,
        logging: ecs.LogDrivers.awsLogs({
          streamPrefix: 'batch-fargate',
          logGroup: this.logGroup,
        }),
        environment: {
          AWS_DEFAULT_REGION: cdk.Stack.of(this).region,
          JOB_QUEUE: this.jobQueue.jobQueueName,
        },
        assignPublicIp: true, // Required for Fargate tasks in public subnets
      }),
      timeout: cdk.Duration.seconds(jobTimeoutSeconds),
      retryAttempts: 3,
    });

    // Outputs
    new cdk.CfnOutput(this, 'EcrRepositoryUri', {
      value: this.ecrRepository.repositoryUri,
      description: 'ECR Repository URI for container images',
      exportName: `${cdk.Stack.of(this).stackName}-EcrRepositoryUri`,
    });

    new cdk.CfnOutput(this, 'ComputeEnvironmentArn', {
      value: this.computeEnvironment.computeEnvironmentArn,
      description: 'AWS Batch Compute Environment ARN',
      exportName: `${cdk.Stack.of(this).stackName}-ComputeEnvironmentArn`,
    });

    new cdk.CfnOutput(this, 'JobQueueArn', {
      value: this.jobQueue.jobQueueArn,
      description: 'AWS Batch Job Queue ARN',
      exportName: `${cdk.Stack.of(this).stackName}-JobQueueArn`,
    });

    new cdk.CfnOutput(this, 'JobDefinitionArn', {
      value: this.jobDefinition.jobDefinitionArn,
      description: 'AWS Batch Job Definition ARN',
      exportName: `${cdk.Stack.of(this).stackName}-JobDefinitionArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group for batch jobs',
      exportName: `${cdk.Stack.of(this).stackName}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'JobSubmissionCommand', {
      value: `aws batch submit-job --job-name sample-job-$(date +%s) --job-queue ${this.jobQueue.jobQueueName} --job-definition ${this.jobDefinition.jobDefinitionName}`,
      description: 'Sample command to submit a batch job',
    });

    // Tags
    cdk.Tags.of(this).add('Project', 'BatchProcessingWorkloads');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
};

// Stack configuration
const stackProps: BatchProcessingStackProps = {
  env,
  description: 'AWS Batch processing workloads with Fargate - CDK TypeScript implementation',
  maxVcpus: app.node.tryGetContext('maxVcpus') || 256,
  jobTimeoutSeconds: app.node.tryGetContext('jobTimeoutSeconds') || 3600,
  logRetentionDays: logs.RetentionDays.ONE_WEEK,
  createNewVpc: app.node.tryGetContext('createNewVpc') || false,
};

// Create the stack
new BatchProcessingStack(app, 'BatchProcessingWorkloadsStack', stackProps);

// Synthesize the app
app.synth();