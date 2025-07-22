import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as ecr from 'aws-cdk-lib/aws-ecr';
import * as batch from 'aws-cdk-lib/aws-batch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

export interface DistributedScientificComputingStackProps extends cdk.StackProps {
  nodeCount?: number;
  instanceTypes?: string[];
  maxvCpus?: number;
}

export class DistributedScientificComputingStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly efsFileSystem: efs.FileSystem;
  public readonly ecrRepository: ecr.Repository;
  public readonly batchComputeEnvironment: batch.ManagedEc2EcsComputeEnvironment;
  public readonly jobQueue: batch.JobQueue;
  public readonly jobDefinition: batch.MultiNodeJobDefinition;

  constructor(scope: Construct, id: string, props?: DistributedScientificComputingStackProps) {
    super(scope, id, props);

    const nodeCount = props?.nodeCount || 2;
    const instanceTypes = props?.instanceTypes || ['c5.large', 'c5.xlarge'];
    const maxvCpus = props?.maxvCpus || 256;

    // Create VPC for scientific computing workloads
    this.vpc = this.createNetworkingInfrastructure();

    // Create EFS file system for shared storage
    this.efsFileSystem = this.createSharedStorage();

    // Create ECR repository for MPI container images
    this.ecrRepository = this.createContainerRegistry();

    // Create IAM roles for Batch
    const { batchServiceRole, instanceProfile } = this.createIamRoles();

    // Create Batch compute environment
    this.batchComputeEnvironment = this.createComputeEnvironment(
      batchServiceRole,
      instanceProfile,
      instanceTypes,
      maxvCpus
    );

    // Create job queue
    this.jobQueue = this.createJobQueue();

    // Create multi-node job definition
    this.jobDefinition = this.createJobDefinition(nodeCount);

    // Create CloudWatch dashboard for monitoring
    this.createMonitoringDashboard();

    // Output important values
    this.createOutputs();
  }

  private createNetworkingInfrastructure(): ec2.Vpc {
    // Create VPC with public and private subnets
    const vpc = new ec2.Vpc(this, 'ScientificComputingVPC', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
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
        },
      ],
    });

    // Create security group for Batch multi-node jobs
    const batchSecurityGroup = new ec2.SecurityGroup(this, 'BatchSecurityGroup', {
      vpc,
      description: 'Security group for multi-node Batch jobs with MPI communication',
      allowAllOutbound: true,
    });

    // Allow all traffic within security group for MPI communication
    batchSecurityGroup.addIngressRule(
      batchSecurityGroup,
      ec2.Port.allTraffic(),
      'Allow all traffic between nodes for MPI communication'
    );

    // Allow SSH for debugging (optional)
    batchSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for debugging'
    );

    // Allow EFS NFS traffic
    batchSecurityGroup.addIngressRule(
      batchSecurityGroup,
      ec2.Port.tcp(2049),
      'Allow EFS NFS traffic'
    );

    // Store security group for use in other resources
    vpc.node.addMetadata('batchSecurityGroup', batchSecurityGroup);

    return vpc;
  }

  private createSharedStorage(): efs.FileSystem {
    // Get security group from VPC metadata
    const batchSecurityGroup = this.vpc.node.findChild('BatchSecurityGroup') as ec2.SecurityGroup;

    // Create EFS file system for shared data
    const fileSystem = new efs.FileSystem(this, 'ScientificDataFileSystem', {
      vpc: this.vpc,
      securityGroup: batchSecurityGroup,
      performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode: efs.ThroughputMode.PROVISIONED,
      provisionedThroughputPerSecond: cdk.Size.mebibytes(100),
      encrypted: true,
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
      outOfInfrequentAccessPolicy: efs.OutOfInfrequentAccessPolicy.AFTER_1_ACCESS,
      enableBackups: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For testing - use RETAIN in production
    });

    return fileSystem;
  }

  private createContainerRegistry(): ecr.Repository {
    // Create ECR repository for MPI container images
    const repository = new ecr.Repository(this, 'ScientificMpiRepository', {
      repositoryName: `scientific-mpi-${cdk.Names.uniqueId(this).toLowerCase()}`,
      imageScanOnPush: true,
      imageTagMutability: ecr.TagMutability.MUTABLE,
      lifecycleRules: [
        {
          maxImageCount: 10,
          description: 'Keep only 10 latest images',
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For testing - use RETAIN in production
    });

    return repository;
  }

  private createIamRoles(): { batchServiceRole: iam.Role; instanceProfile: iam.InstanceProfile } {
    // Create Batch service role
    const batchServiceRole = new iam.Role(this, 'BatchServiceRole', {
      assumedBy: new iam.ServicePrincipal('batch.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSBatchServiceRole'),
      ],
      description: 'Service role for AWS Batch to manage compute environments',
    });

    // Create instance role for EC2 instances
    const instanceRole = new iam.Role(this, 'BatchInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonEC2ContainerServiceforEC2Role'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
      description: 'Role for EC2 instances in Batch compute environment',
    });

    // Add additional permissions for EFS mounting
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

    // Create instance profile
    const instanceProfile = new iam.InstanceProfile(this, 'BatchInstanceProfile', {
      role: instanceRole,
    });

    return { batchServiceRole, instanceProfile };
  }

  private createComputeEnvironment(
    batchServiceRole: iam.Role,
    instanceProfile: iam.InstanceProfile,
    instanceTypes: string[],
    maxvCpus: number
  ): batch.ManagedEc2EcsComputeEnvironment {
    // Get security group from VPC
    const batchSecurityGroup = this.vpc.node.findChild('BatchSecurityGroup') as ec2.SecurityGroup;

    // Create managed compute environment for multi-node jobs
    const computeEnvironment = new batch.ManagedEc2EcsComputeEnvironment(this, 'ScientificComputeEnvironment', {
      vpc: this.vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      securityGroups: [batchSecurityGroup],
      instanceRole: instanceProfile,
      serviceRole: batchServiceRole,
      minvCpus: 0,
      maxvCpus,
      desiredvCpus: 0,
      instanceTypes: instanceTypes.map(type => new ec2.InstanceType(type)),
      spot: false, // Use On-Demand for reliable multi-node jobs
      useOptimalInstanceClasses: false, // Use specific instance types for predictable performance
      tags: {
        Environment: 'scientific-computing',
        Purpose: 'multi-node-mpi',
      },
    });

    return computeEnvironment;
  }

  private createJobQueue(): batch.JobQueue {
    // Create job queue for scientific computing jobs
    const jobQueue = new batch.JobQueue(this, 'ScientificJobQueue', {
      computeEnvironments: [
        {
          computeEnvironment: this.batchComputeEnvironment,
          order: 1,
        },
      ],
      priority: 1,
      jobQueueName: `scientific-queue-${cdk.Names.uniqueId(this).toLowerCase()}`,
    });

    return jobQueue;
  }

  private createJobDefinition(nodeCount: number): batch.MultiNodeJobDefinition {
    // Create multi-node parallel job definition
    const jobDefinition = new batch.MultiNodeJobDefinition(this, 'MpiJobDefinition', {
      jobDefinitionName: `mpi-job-${cdk.Names.uniqueId(this).toLowerCase()}`,
      mainNode: 0,
      nodeRangeProperties: [
        {
          targetNodes: '0:',
          container: {
            image: batch.EcsEc2ContainerDefinition.fromEcrRepository(this.ecrRepository, 'latest'),
            vcpus: 2,
            memoryLimitMiB: 4096,
            privileged: true,
            environment: {
              EFS_DNS_NAME: `${this.efsFileSystem.fileSystemId}.efs.${this.region}.amazonaws.com`,
              EFS_MOUNT_POINT: '/mnt/efs',
              OMPI_ALLOW_RUN_AS_ROOT: '1',
              OMPI_ALLOW_RUN_AS_ROOT_CONFIRM: '1',
            },
            volumes: [
              batch.EcsVolume.host({
                name: 'tmp',
                hostPath: '/tmp',
                containerPath: '/tmp',
              }),
            ],
          },
        },
      ],
      numNodes: nodeCount,
      retryAttempts: 1,
      timeout: cdk.Duration.hours(2),
    });

    return jobDefinition;
  }

  private createMonitoringDashboard(): void {
    // Create CloudWatch dashboard for monitoring Batch jobs
    const dashboard = new cloudwatch.Dashboard(this, 'ScientificComputingDashboard', {
      dashboardName: `ScientificComputing-${cdk.Names.uniqueId(this)}`,
    });

    // Add job metrics widgets
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Batch Job Status',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'SubmittedJobs',
            dimensionsMap: {
              JobQueue: this.jobQueue.jobQueueName,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'RunnableJobs',
            dimensionsMap: {
              JobQueue: this.jobQueue.jobQueueName,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Batch',
            metricName: 'RunningJobs',
            dimensionsMap: {
              JobQueue: this.jobQueue.jobQueueName,
            },
            statistic: 'Sum',
          }),
        ],
      }),
    );

    // Create CloudWatch alarm for failed jobs
    const failedJobsAlarm = new cloudwatch.Alarm(this, 'FailedJobsAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Batch',
        metricName: 'FailedJobs',
        dimensionsMap: {
          JobQueue: this.jobQueue.jobQueueName,
        },
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      alarmDescription: 'Alert when Batch jobs fail',
    });

    // Create log group for Batch job logs
    new logs.LogGroup(this, 'BatchJobLogGroup', {
      logGroupName: '/aws/batch/job',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  private createOutputs(): void {
    // Output important resource identifiers
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the scientific computing environment',
    });

    new cdk.CfnOutput(this, 'EfsFileSystemId', {
      value: this.efsFileSystem.fileSystemId,
      description: 'EFS File System ID for shared storage',
    });

    new cdk.CfnOutput(this, 'EcrRepositoryUri', {
      value: this.ecrRepository.repositoryUri,
      description: 'ECR Repository URI for MPI container images',
    });

    new cdk.CfnOutput(this, 'BatchComputeEnvironmentName', {
      value: this.batchComputeEnvironment.computeEnvironmentName,
      description: 'Batch Compute Environment name',
    });

    new cdk.CfnOutput(this, 'JobQueueName', {
      value: this.jobQueue.jobQueueName,
      description: 'Batch Job Queue name for submitting jobs',
    });

    new cdk.CfnOutput(this, 'JobDefinitionArn', {
      value: this.jobDefinition.jobDefinitionArn,
      description: 'Multi-node Job Definition ARN',
    });

    new cdk.CfnOutput(this, 'JobSubmissionCommand', {
      value: `aws batch submit-job --job-name scientific-test --job-queue ${this.jobQueue.jobQueueName} --job-definition ${this.jobDefinition.jobDefinitionName}`,
      description: 'Example command to submit a multi-node job',
    });
  }
}