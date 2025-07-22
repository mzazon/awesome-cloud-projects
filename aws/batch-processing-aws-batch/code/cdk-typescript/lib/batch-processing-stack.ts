import * as cdk from 'aws-cdk-lib';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

export interface BatchProcessingStackProps extends cdk.StackProps {
  stackName: string;
}

/**
 * AWS CDK Stack for Batch Processing Workloads
 * 
 * This stack creates a complete AWS Batch infrastructure optimized for
 * containerized batch processing workloads with automatic scaling,
 * cost optimization through Spot instances, and comprehensive monitoring.
 */
export class BatchProcessingStack extends cdk.Stack {
  public readonly ecrRepository: ecr.Repository;
  public readonly computeEnvironment: batch.ManagedEc2EcsComputeEnvironment;
  public readonly jobQueue: batch.JobQueue;
  public readonly jobDefinition: batch.EcsJobDefinition;
  public readonly logGroup: logs.LogGroup;

  constructor(scope: Construct, id: string, props: BatchProcessingStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // Create VPC (use default VPC or create new one)
    const vpc = this.createOrGetVpc();

    // Create ECR Repository for container images
    this.ecrRepository = this.createEcrRepository(uniqueSuffix);

    // Create IAM Roles for AWS Batch
    const { batchServiceRole, instanceRole, instanceProfile } = this.createIamRoles(uniqueSuffix);

    // Create Security Group for Batch compute environment
    const securityGroup = this.createSecurityGroup(vpc, uniqueSuffix);

    // Create CloudWatch Log Group for batch jobs
    this.logGroup = this.createLogGroup(uniqueSuffix);

    // Create AWS Batch Compute Environment
    this.computeEnvironment = this.createComputeEnvironment(
      vpc,
      securityGroup,
      instanceProfile,
      batchServiceRole,
      uniqueSuffix
    );

    // Create Job Queue
    this.jobQueue = this.createJobQueue(this.computeEnvironment, uniqueSuffix);

    // Create Job Definition
    this.jobDefinition = this.createJobDefinition(this.ecrRepository, this.logGroup, uniqueSuffix);

    // Create CloudWatch Alarms for monitoring
    this.createCloudWatchAlarms(this.jobQueue, uniqueSuffix);

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Create or get existing VPC for the batch compute environment
   */
  private createOrGetVpc(): ec2.IVpc {
    // Try to use default VPC, otherwise create a new one
    return ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });
  }

  /**
   * Create ECR Repository with security best practices
   */
  private createEcrRepository(uniqueSuffix: string): ecr.Repository {
    const repository = new ecr.Repository(this, 'BatchRepository', {
      repositoryName: `batch-processing-${uniqueSuffix}`,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      lifecycleRules: [
        {
          description: 'Keep last 10 images',
          maxImageCount: 10,
        },
        {
          description: 'Delete untagged images after 1 day',
          maxImageAge: cdk.Duration.days(1),
          tagStatus: ecr.TagStatus.UNTAGGED,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Grant cross-account access if needed
    repository.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('batch.amazonaws.com')],
      actions: [
        'ecr:GetDownloadUrlForLayer',
        'ecr:BatchGetImage',
        'ecr:BatchCheckLayerAvailability',
      ],
    }));

    return repository;
  }

  /**
   * Create IAM roles required for AWS Batch
   */
  private createIamRoles(uniqueSuffix: string) {
    // AWS Batch Service Role
    const batchServiceRole = new iam.Role(this, 'BatchServiceRole', {
      roleName: `AWSBatchServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('batch.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBatchServiceRole'),
      ],
      description: 'IAM role for AWS Batch service to manage compute environments',
    });

    // ECS Instance Role for Batch compute instances
    const instanceRole = new iam.Role(this, 'BatchInstanceRole', {
      roleName: `ecsInstanceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
      ],
      description: 'IAM role for EC2 instances in AWS Batch compute environment',
    });

    // Add additional permissions for enhanced functionality
    instanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'ecr:GetAuthorizationToken',
        'ecr:BatchCheckLayerAvailability',
        'ecr:GetDownloadUrlForLayer',
        'ecr:BatchGetImage',
      ],
      resources: ['*'],
    }));

    // Create Instance Profile
    const instanceProfile = new iam.CfnInstanceProfile(this, 'BatchInstanceProfile', {
      instanceProfileName: `ecsInstanceProfile-${uniqueSuffix}`,
      roles: [instanceRole.roleName],
    });

    return { batchServiceRole, instanceRole, instanceProfile };
  }

  /**
   * Create Security Group for Batch compute environment
   */
  private createSecurityGroup(vpc: ec2.IVpc, uniqueSuffix: string): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'BatchSecurityGroup', {
      vpc,
      securityGroupName: `batch-sg-${uniqueSuffix}`,
      description: 'Security group for AWS Batch compute environment',
      allowAllOutbound: true,
    });

    // Add inbound rules if needed (none required for basic batch processing)
    // securityGroup.addIngressRule(
    //   ec2.Peer.anyIpv4(),
    //   ec2.Port.tcp(443),
    //   'Allow HTTPS inbound for container registry access'
    // );

    return securityGroup;
  }

  /**
   * Create CloudWatch Log Group for batch job logs
   */
  private createLogGroup(uniqueSuffix: string): logs.LogGroup {
    return new logs.LogGroup(this, 'BatchLogGroup', {
      logGroupName: '/aws/batch/job',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });
  }

  /**
   * Create AWS Batch Managed Compute Environment
   */
  private createComputeEnvironment(
    vpc: ec2.IVpc,
    securityGroup: ec2.SecurityGroup,
    instanceProfile: iam.CfnInstanceProfile,
    serviceRole: iam.Role,
    uniqueSuffix: string
  ): batch.ManagedEc2EcsComputeEnvironment {
    return new batch.ManagedEc2EcsComputeEnvironment(this, 'BatchComputeEnvironment', {
      computeEnvironmentName: `batch-compute-env-${uniqueSuffix}`,
      vpc,
      securityGroups: [securityGroup],
      
      // Use optimal instance types for cost-effectiveness
      instanceTypes: [ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE)],
      
      // Mixed instance policy for cost optimization
      spotBidPercentage: 50, // Use up to 50% Spot instances
      
      // Scaling configuration
      minvCpus: 0,           // Scale down to zero when no jobs
      maxvCpus: 100,         // Maximum compute capacity
      desiredvCpus: 0,       // Start with zero instances
      
      // Instance configuration
      instanceRole: instanceProfile.attrArn,
      serviceRole: serviceRole,
      
      // Use Amazon Linux 2 ECS-optimized AMI
      useOptimalInstanceClasses: true,
      
      // Enable detailed monitoring
      tags: {
        Name: `batch-compute-env-${uniqueSuffix}`,
        Purpose: 'BatchProcessing',
      },
    });
  }

  /**
   * Create Job Queue for batch job scheduling
   */
  private createJobQueue(
    computeEnvironment: batch.ManagedEc2EcsComputeEnvironment,
    uniqueSuffix: string
  ): batch.JobQueue {
    return new batch.JobQueue(this, 'BatchJobQueue', {
      jobQueueName: `batch-job-queue-${uniqueSuffix}`,
      priority: 1,
      computeEnvironments: [
        {
          computeEnvironment,
          order: 1,
        },
      ],
      enabled: true,
    });
  }

  /**
   * Create Job Definition for containerized batch jobs
   */
  private createJobDefinition(
    repository: ecr.Repository,
    logGroup: logs.LogGroup,
    uniqueSuffix: string
  ): batch.EcsJobDefinition {
    return new batch.EcsJobDefinition(this, 'BatchJobDefinition', {
      jobDefinitionName: `batch-job-def-${uniqueSuffix}`,
      
      // Container configuration
      container: batch.EcsEc2ContainerDefinition.fromEcsContainerDefinitionProps(this, 'BatchContainer', {
        image: batch.ContainerImage.fromEcrRepository(repository, 'latest'),
        cpu: 1,
        memoryLimitMiB: 512,
        
        // Environment variables for job configuration
        environment: {
          DATA_SIZE: '5000',
          PROCESSING_TIME: '120',
          AWS_DEFAULT_REGION: this.region,
        },
        
        // Logging configuration
        logging: batch.LogDriver.awsLogs({
          logGroup,
          streamPrefix: 'batch-job',
        }),
        
        // Job execution role (if needed for AWS service access)
        // executionRole: taskExecutionRole,
      }),
      
      // Job timeout configuration
      timeout: cdk.Duration.hours(1),
      
      // Retry configuration
      retryAttempts: 2,
    });
  }

  /**
   * Create CloudWatch Alarms for monitoring batch jobs
   */
  private createCloudWatchAlarms(jobQueue: batch.JobQueue, uniqueSuffix: string): void {
    // Alarm for failed jobs
    new cloudwatch.Alarm(this, 'BatchJobFailuresAlarm', {
      alarmName: `BatchJobFailures-${uniqueSuffix}`,
      alarmDescription: 'Alert when batch jobs fail',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Batch',
        metricName: 'FailedJobs',
        dimensionsMap: {
          JobQueue: jobQueue.jobQueueName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
    });

    // Alarm for high queue utilization
    new cloudwatch.Alarm(this, 'BatchQueueUtilizationAlarm', {
      alarmName: `BatchQueueUtilization-${uniqueSuffix}`,
      alarmDescription: 'Alert when job queue has high utilization',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Batch',
        metricName: 'RunnableJobs',
        dimensionsMap: {
          JobQueue: jobQueue.jobQueueName,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
    });
  }

  /**
   * Create CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'EcrRepositoryUri', {
      value: this.ecrRepository.repositoryUri,
      description: 'ECR Repository URI for batch processing container images',
      exportName: `${this.stackName}-EcrRepositoryUri`,
    });

    new cdk.CfnOutput(this, 'ComputeEnvironmentName', {
      value: this.computeEnvironment.computeEnvironmentName,
      description: 'AWS Batch Compute Environment Name',
      exportName: `${this.stackName}-ComputeEnvironmentName`,
    });

    new cdk.CfnOutput(this, 'JobQueueName', {
      value: this.jobQueue.jobQueueName,
      description: 'AWS Batch Job Queue Name',
      exportName: `${this.stackName}-JobQueueName`,
    });

    new cdk.CfnOutput(this, 'JobDefinitionArn', {
      value: this.jobDefinition.jobDefinitionArn,
      description: 'AWS Batch Job Definition ARN',
      exportName: `${this.stackName}-JobDefinitionArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'CloudWatch Log Group Name for batch job logs',
      exportName: `${this.stackName}-LogGroupName`,
    });
  }
}