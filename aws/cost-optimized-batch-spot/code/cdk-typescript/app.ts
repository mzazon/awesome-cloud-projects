#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Cost-Optimized Batch Processing with Spot
 */
export class CostOptimizedBatchProcessingStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC or use default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // Create ECR repository for batch application
    const ecrRepository = new ecr.Repository(this, 'BatchRepository', {
      repositoryName: `batch-demo-${this.generateRandomSuffix()}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteImages: true,
    });

    // Create IAM service role for AWS Batch
    const batchServiceRole = new iam.Role(this, 'BatchServiceRole', {
      assumedBy: new iam.ServicePrincipal('batch.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBatchServiceRole'),
      ],
    });

    // Create IAM instance role for EC2 instances
    const instanceRole = new iam.Role(this, 'InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
      ],
    });

    // Create instance profile for EC2 instances
    const instanceProfile = new iam.CfnInstanceProfile(this, 'InstanceProfile', {
      roles: [instanceRole.roleName],
    });

    // Create IAM job execution role
    const jobExecutionRole = new iam.Role(this, 'JobExecutionRole', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonECSTaskExecutionRolePolicy'),
      ],
    });

    // Create security group for batch instances
    const securityGroup = new ec2.SecurityGroup(this, 'BatchSecurityGroup', {
      vpc,
      description: 'Security group for AWS Batch instances',
      allowAllOutbound: true,
    });

    // Create CloudWatch log group for batch jobs
    const logGroup = new logs.LogGroup(this, 'BatchLogGroup', {
      logGroupName: `/aws/batch/job`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create compute environment with Spot instances
    const computeEnvironment = new batch.ManagedEc2EcsComputeEnvironment(this, 'SpotComputeEnvironment', {
      computeEnvironmentName: `spot-compute-env-${this.generateRandomSuffix()}`,
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      securityGroups: [securityGroup],
      instanceRole: instanceProfile.attrArn,
      serviceRole: batchServiceRole,
      minvCpus: 0,
      maxvCpus: 100,
      desiredvCpus: 0,
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE2),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE2),
      ],
      spot: true,
      spotBidPercentage: 80,
      allocationStrategy: batch.AllocationStrategy.SPOT_CAPACITY_OPTIMIZED,
      updatePolicy: {
        terminateJobsOnUpdate: false,
        jobExecutionTimeoutMinutes: 30,
      },
      tags: {
        Environment: 'batch-demo',
        CostCenter: 'batch-processing',
      },
    });

    // Create job queue
    const jobQueue = new batch.JobQueue(this, 'SpotJobQueue', {
      jobQueueName: `spot-job-queue-${this.generateRandomSuffix()}`,
      priority: 1,
      computeEnvironments: [
        {
          computeEnvironment,
          order: 1,
        },
      ],
    });

    // Create job definition with retry strategy
    const jobDefinition = new batch.EcsJobDefinition(this, 'BatchJobDefinition', {
      jobDefinitionName: `batch-job-def-${this.generateRandomSuffix()}`,
      container: new batch.EcsEc2ContainerDefinition(this, 'BatchContainer', {
        image: batch.ContainerImage.fromEcrRepository(ecrRepository, 'latest'),
        vcpus: 1,
        memoryLimitMiB: 512,
        jobRole: jobExecutionRole,
        logging: new batch.LogDriver({
          logDriver: batch.LogDrivers.AWS_LOGS,
          options: {
            'awslogs-group': logGroup.logGroupName,
            'awslogs-region': this.region,
            'awslogs-stream-prefix': 'batch-job',
          },
        }),
      }),
      retryAttempts: 3,
      timeout: cdk.Duration.hours(1),
    });

    // Add custom retry strategy for Spot instance interruptions
    const cfnJobDefinition = jobDefinition.node.defaultChild as batch.CfnJobDefinition;
    cfnJobDefinition.addPropertyOverride('RetryStrategy', {
      attempts: 3,
      evaluateOnExit: [
        {
          onStatusReason: 'Host EC2*',
          action: 'RETRY',
        },
        {
          onReason: '*',
          action: 'EXIT',
        },
      ],
    });

    // Create outputs for reference
    new cdk.CfnOutput(this, 'ECRRepositoryURI', {
      value: ecrRepository.repositoryUri,
      description: 'ECR Repository URI for batch application',
    });

    new cdk.CfnOutput(this, 'JobQueueName', {
      value: jobQueue.jobQueueName,
      description: 'AWS Batch job queue name',
    });

    new cdk.CfnOutput(this, 'JobDefinitionName', {
      value: jobDefinition.jobDefinitionName,
      description: 'AWS Batch job definition name',
    });

    new cdk.CfnOutput(this, 'ComputeEnvironmentName', {
      value: computeEnvironment.computeEnvironmentName,
      description: 'AWS Batch compute environment name',
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'CloudWatch log group for batch jobs',
    });

    // Add deployment instructions as output
    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      value: [
        '1. Build and push Docker image to ECR:',
        `   aws ecr get-login-password --region ${this.region} | docker login --username AWS --password-stdin ${ecrRepository.repositoryUri}`,
        '   docker build -t batch-app .',
        `   docker tag batch-app:latest ${ecrRepository.repositoryUri}:latest`,
        `   docker push ${ecrRepository.repositoryUri}:latest`,
        '2. Submit a test job:',
        `   aws batch submit-job --job-name test-job --job-queue ${jobQueue.jobQueueName} --job-definition ${jobDefinition.jobDefinitionName}`,
      ].join('\n'),
      description: 'Instructions for deploying and testing the batch application',
    });
  }

  /**
   * Generate a random suffix for resource names
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack
new CostOptimizedBatchProcessingStack(app, 'CostOptimizedBatchProcessingStack', {
  description: 'Cost-optimized batch processing with AWS Batch and Spot Instances',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'cost-optimized-batch-processing',
    Environment: 'demo',
    CostCenter: 'batch-processing',
  },
});

// Synthesize the stack
app.synth();