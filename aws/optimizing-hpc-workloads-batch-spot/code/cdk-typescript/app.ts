#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Properties for the HPC Batch Spot Stack
 */
export interface HpcBatchSpotStackProps extends cdk.StackProps {
  /**
   * Maximum number of vCPUs for the compute environment
   * @default 1000
   */
  readonly maxvCpus?: number;

  /**
   * Minimum number of vCPUs for the compute environment
   * @default 0
   */
  readonly minvCpus?: number;

  /**
   * Spot instance bid percentage (percentage of on-demand price)
   * @default 80
   */
  readonly spotBidPercentage?: number;

  /**
   * EFS provisioned throughput in MiBps
   * @default 100
   */
  readonly efsProvisionedThroughput?: number;

  /**
   * CloudWatch log retention in days
   * @default 7
   */
  readonly logRetentionDays?: logs.RetentionDays;

  /**
   * Environment name prefix for resource naming
   * @default 'hpc-batch'
   */
  readonly environmentName?: string;
}

/**
 * CDK Stack for Optimizing HPC Workloads with AWS Batch and Spot Instances
 * 
 * This stack creates:
 * - VPC with public and private subnets for isolated compute environments
 * - EFS file system for shared storage across compute instances
 * - IAM roles and policies for Batch service and EC2 instances
 * - Batch compute environment optimized for Spot instances
 * - Batch job queue for managing HPC workloads
 * - Job definition template for containerized HPC applications
 * - S3 bucket for data input/output storage
 * - CloudWatch monitoring and logging infrastructure
 * - Security groups with least-privilege access controls
 */
export class HpcBatchSpotStack extends cdk.Stack {
  /**
   * The VPC where all resources will be deployed
   */
  public readonly vpc: ec2.Vpc;

  /**
   * EFS file system for shared storage
   */
  public readonly efsFileSystem: efs.FileSystem;

  /**
   * S3 bucket for data storage
   */
  public readonly dataBucket: s3.Bucket;

  /**
   * Batch compute environment for Spot instances
   */
  public readonly computeEnvironment: batch.ManagedEc2EcsComputeEnvironment;

  /**
   * Batch job queue
   */
  public readonly jobQueue: batch.JobQueue;

  /**
   * Batch job definition for HPC workloads
   */
  public readonly jobDefinition: batch.EcsJobDefinition;

  constructor(scope: Construct, id: string, props: HpcBatchSpotStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const {
      maxvCpus = 1000,
      minvCpus = 0,
      spotBidPercentage = 80,
      efsProvisionedThroughput = 100,
      logRetentionDays = logs.RetentionDays.ONE_WEEK,
      environmentName = 'hpc-batch'
    } = props;

    // Create VPC with public and private subnets for optimal network isolation
    this.vpc = new ec2.Vpc(this, 'HpcVpc', {
      maxAzs: 3,
      natGateways: 1, // Cost optimization: single NAT gateway
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

    // Create S3 bucket for HPC data input/output with lifecycle policies
    this.dataBucket = new s3.Bucket(this, 'HpcDataBucket', {
      bucketName: `${environmentName}-data-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: false,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create security group for EFS with NFS access
    const efsSecurityGroup = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EFS file system',
      allowAllOutbound: false,
    });

    // Create security group for Batch compute instances
    const batchSecurityGroup = new ec2.SecurityGroup(this, 'BatchSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for AWS Batch compute environment',
      allowAllOutbound: true,
    });

    // Allow NFS traffic between Batch instances and EFS
    efsSecurityGroup.addIngressRule(
      batchSecurityGroup,
      ec2.Port.tcp(2049),
      'Allow NFS traffic from Batch compute instances'
    );

    // Create EFS file system for shared storage with performance optimization
    this.efsFileSystem = new efs.FileSystem(this, 'HpcSharedStorage', {
      vpc: this.vpc,
      fileSystemName: `${environmentName}-shared-storage`,
      performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode: efs.ThroughputMode.PROVISIONED,
      provisionedThroughputPerSecond: cdk.Size.mebibytes(efsProvisionedThroughput),
      securityGroup: efsSecurityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      encrypted: true,
    });

    // Create IAM role for Batch service
    const batchServiceRole = new iam.Role(this, 'BatchServiceRole', {
      assumedBy: new iam.ServicePrincipal('batch.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBatchServiceRole'),
      ],
      description: 'IAM role for AWS Batch service',
    });

    // Create IAM role for EC2 instances in Batch compute environment
    const instanceRole = new iam.Role(this, 'BatchInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
      ],
      description: 'IAM role for EC2 instances in Batch compute environment',
    });

    // Add additional permissions for S3 and EFS access
    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
        ],
        resources: [
          this.dataBucket.bucketArn,
          `${this.dataBucket.bucketArn}/*`,
        ],
      })
    );

    instanceRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'elasticfilesystem:DescribeFileSystems',
          'elasticfilesystem:DescribeMountTargets',
        ],
        resources: ['*'],
      })
    );

    // Create instance profile for EC2 instances
    const instanceProfile = new iam.CfnInstanceProfile(this, 'BatchInstanceProfile', {
      roles: [instanceRole.roleName],
      instanceProfileName: `${environmentName}-instance-profile`,
    });

    // Create CloudWatch log group for Batch jobs
    const logGroup = new logs.LogGroup(this, 'BatchJobLogGroup', {
      logGroupName: '/aws/batch/job',
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Batch compute environment optimized for Spot instances
    this.computeEnvironment = new batch.ManagedEc2EcsComputeEnvironment(this, 'SpotComputeEnvironment', {
      computeEnvironmentName: `${environmentName}-spot-compute`,
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [batchSecurityGroup],
      instanceRole: instanceProfile.attrArn,
      serviceRole: batchServiceRole,
      minvCpus: minvCpus,
      maxvCpus: maxvCpus,
      desiredvCpus: 0,
      // Use SPOT_CAPACITY_OPTIMIZED for better availability and lower interruption rates
      allocationStrategy: batch.AllocationStrategy.SPOT_CAPACITY_OPTIMIZED,
      // Mixed instance types for better Spot capacity diversity
      instanceTypes: [
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE2),
        ec2.InstanceType.of(ec2.InstanceClass.C4, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.C4, ec2.InstanceSize.XLARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
        ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE),
      ],
      spotBidPercentage: spotBidPercentage,
      useOptimalInstanceClasses: true,
      updatePolicy: {
        terminateJobsOnUpdate: false,
        jobExecutionTimeoutMinutes: 30,
      },
    });

    // Create Batch job queue
    this.jobQueue = new batch.JobQueue(this, 'HpcJobQueue', {
      jobQueueName: `${environmentName}-job-queue`,
      priority: 1,
      computeEnvironments: [
        {
          computeEnvironment: this.computeEnvironment,
          order: 1,
        },
      ],
    });

    // Create task definition for HPC jobs
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'HpcTaskDefinition', {
      memoryLimitMiB: 4096,
      cpu: 2048,
      taskRole: instanceRole,
      executionRole: instanceRole,
    });

    // Add EFS volume to task definition
    taskDefinition.addVolume({
      name: 'efs-storage',
      efsVolumeConfiguration: {
        fileSystemId: this.efsFileSystem.fileSystemId,
        transitEncryption: 'ENABLED',
      },
    });

    // Create container definition for HPC simulation
    const container = taskDefinition.addContainer('HpcContainer', {
      image: ecs.ContainerImage.fromRegistry('busybox'),
      memoryLimitMiB: 4096,
      cpu: 2048,
      command: [
        'sh',
        '-c',
        'echo "Starting HPC simulation at $(date)"; sleep 300; echo "Simulation completed at $(date)"',
      ],
      environment: {
        S3_BUCKET: this.dataBucket.bucketName,
        AWS_DEFAULT_REGION: cdk.Aws.REGION,
        EFS_MOUNT_POINT: '/shared',
      },
      logging: ecs.LogDrivers.awsLogs({
        streamPrefix: 'hpc-job',
        logGroup: logGroup,
      }),
    });

    // Add EFS mount point to container
    container.addMountPoints({
      sourceVolume: 'efs-storage',
      containerPath: '/shared',
      readOnly: false,
    });

    // Create Batch job definition
    this.jobDefinition = new batch.EcsJobDefinition(this, 'HpcJobDefinition', {
      jobDefinitionName: `${environmentName}-simulation`,
      container: new batch.EcsEc2ContainerDefinition(this, 'HpcContainerDefinition', {
        image: ecs.ContainerImage.fromRegistry('busybox'),
        memory: cdk.Size.mebibytes(4096),
        vcpus: 2,
        jobRole: instanceRole,
        command: [
          'sh',
          '-c',
          'echo "Starting HPC simulation at $(date)"; sleep 300; echo "Simulation completed at $(date)"',
        ],
        environment: {
          S3_BUCKET: this.dataBucket.bucketName,
          AWS_DEFAULT_REGION: cdk.Aws.REGION,
          EFS_MOUNT_POINT: '/shared',
        },
        logging: ecs.LogDrivers.awsLogs({
          streamPrefix: 'hpc-job',
          logGroup: logGroup,
        }),
        volumes: [
          {
            name: 'efs-storage',
            efsVolumeConfiguration: {
              fileSystemId: this.efsFileSystem.fileSystemId,
              transitEncryption: 'ENABLED',
            },
          },
        ],
        mountPoints: [
          {
            sourceVolume: 'efs-storage',
            containerPath: '/shared',
            readOnly: false,
          },
        ],
      }),
      retryAttempts: 3,
      timeout: cdk.Duration.hours(1),
    });

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'HpcBatchDashboard', {
      dashboardName: `${environmentName}-monitoring`,
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Batch Job Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'SubmittedJobs',
            dimensionsMap: {
              JobQueue: this.jobQueue.jobQueueName,
            },
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'RunnableJobs',
            dimensionsMap: {
              JobQueue: this.jobQueue.jobQueueName,
            },
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'RunningJobs',
            dimensionsMap: {
              JobQueue: this.jobQueue.jobQueueName,
            },
          }),
        ],
      }),
      new cloudwatch.GraphWidget({
        title: 'Compute Environment Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'AvailableCapacity',
            dimensionsMap: {
              ComputeEnvironment: this.computeEnvironment.computeEnvironmentName,
            },
          }),
        ],
      })
    );

    // Create CloudWatch alarm for failed jobs
    new cloudwatch.Alarm(this, 'FailedJobsAlarm', {
      alarmName: `${environmentName}-failed-jobs-alarm`,
      alarmDescription: 'Alert when Batch jobs fail',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Batch',
        metricName: 'FailedJobs',
        dimensionsMap: {
          JobQueue: this.jobQueue.jobQueueName,
        },
        statistic: 'Sum',
      }),
      threshold: 5,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'S3 bucket for HPC data storage',
      exportName: `${environmentName}-data-bucket`,
    });

    new cdk.CfnOutput(this, 'ComputeEnvironmentName', {
      value: this.computeEnvironment.computeEnvironmentName,
      description: 'Batch compute environment name',
      exportName: `${environmentName}-compute-environment`,
    });

    new cdk.CfnOutput(this, 'JobQueueName', {
      value: this.jobQueue.jobQueueName,
      description: 'Batch job queue name',
      exportName: `${environmentName}-job-queue`,
    });

    new cdk.CfnOutput(this, 'JobDefinitionName', {
      value: this.jobDefinition.jobDefinitionName,
      description: 'Batch job definition name',
      exportName: `${environmentName}-job-definition`,
    });

    new cdk.CfnOutput(this, 'EfsFileSystemId', {
      value: this.efsFileSystem.fileSystemId,
      description: 'EFS file system ID for shared storage',
      exportName: `${environmentName}-efs-filesystem`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID where resources are deployed',
      exportName: `${environmentName}-vpc-id`,
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'HPC-Batch-Optimization');
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('CostCenter', 'Research-Computing');
    cdk.Tags.of(this).add('Owner', 'HPC-Team');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the HPC Batch Spot stack
new HpcBatchSpotStack(app, 'HpcBatchSpotStack', {
  description: 'AWS CDK stack for optimizing HPC workloads with Batch and Spot instances',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Customize stack properties as needed
  maxvCpus: 1000,
  minvCpus: 0,
  spotBidPercentage: 80,
  efsProvisionedThroughput: 100,
  logRetentionDays: logs.RetentionDays.ONE_WEEK,
  environmentName: 'hpc-batch',
});

app.synth();