#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as datasync from 'aws-cdk-lib/aws-datasync';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';

/**
 * Properties for the FileSystemSynchronizationStack
 */
interface FileSystemSynchronizationStackProps extends cdk.StackProps {
  /**
   * The CIDR block for the VPC
   * @default '10.0.0.0/16'
   */
  readonly vpcCidr?: string;
  
  /**
   * Email address for notifications
   * @default undefined
   */
  readonly notificationEmail?: string;
  
  /**
   * EFS throughput mode
   * @default 'provisioned'
   */
  readonly efsThroughputMode?: efs.ThroughputMode;
  
  /**
   * EFS provisioned throughput in MiBps
   * @default 100
   */
  readonly efsProvisionedThroughput?: number;
  
  /**
   * Environment name for resource tagging
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for File System Sync with DataSync and EFS
 * 
 * This stack creates:
 * - VPC with private subnet for secure EFS access
 * - Amazon EFS file system with encryption and provisioned throughput
 * - S3 bucket with sample data for testing synchronization
 * - DataSync service role with appropriate permissions
 * - DataSync locations for S3 and EFS
 * - DataSync task for automated file synchronization
 * - CloudWatch monitoring and SNS notifications
 * - Security groups with least privilege access
 */
export class FileSystemSynchronizationStack extends cdk.Stack {
  /**
   * The VPC created for the file synchronization infrastructure
   */
  public readonly vpc: ec2.Vpc;
  
  /**
   * The EFS file system for data synchronization target
   */
  public readonly fileSystem: efs.FileSystem;
  
  /**
   * The S3 bucket containing source data
   */
  public readonly sourceBucket: s3.Bucket;
  
  /**
   * The DataSync task for file synchronization
   */
  public readonly dataSyncTask: datasync.CfnTask;

  constructor(scope: Construct, id: string, props: FileSystemSynchronizationStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const vpcCidr = props.vpcCidr ?? '10.0.0.0/16';
    const environment = props.environment ?? 'dev';
    const efsThroughputMode = props.efsThroughputMode ?? efs.ThroughputMode.PROVISIONED;
    const efsProvisionedThroughput = props.efsProvisionedThroughput ?? 100;

    // Create VPC with private subnet for secure EFS access
    this.vpc = this.createVpc(vpcCidr, environment);
    
    // Create security group for EFS access
    const efsSecurityGroup = this.createEfsSecurityGroup(this.vpc, environment);
    
    // Create EFS file system with encryption and optimal configuration
    this.fileSystem = this.createEfsFileSystem(
      this.vpc, 
      efsSecurityGroup, 
      efsThroughputMode, 
      efsProvisionedThroughput, 
      environment
    );
    
    // Create S3 bucket with sample data for synchronization testing
    this.sourceBucket = this.createSourceBucket(environment);
    
    // Create IAM role for DataSync with necessary permissions
    const dataSyncRole = this.createDataSyncRole(this.sourceBucket, environment);
    
    // Create DataSync locations for S3 source and EFS destination
    const { s3Location, efsLocation } = this.createDataSyncLocations(
      this.sourceBucket,
      this.fileSystem,
      this.vpc,
      efsSecurityGroup,
      dataSyncRole,
      environment
    );
    
    // Create DataSync task for file synchronization
    this.dataSyncTask = this.createDataSyncTask(s3Location, efsLocation, environment);
    
    // Create monitoring and notifications
    this.createMonitoring(this.dataSyncTask, props.notificationEmail, environment);
    
    // Add comprehensive outputs for operational visibility
    this.createOutputs();
    
    // Apply consistent tagging across all resources
    this.applyTags(environment);
  }

  /**
   * Creates a VPC with private subnet optimized for EFS access
   */
  private createVpc(vpcCidr: string, environment: string): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'DataSyncVpc', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: 2, // Use 2 AZs for high availability
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
          cidrMask: 24,
        },
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        }
      ],
    });

    // Add VPC endpoints for AWS services to reduce data transfer costs
    vpc.addGatewayEndpoint('S3Endpoint', {
      service: ec2.GatewayVpcEndpointAwsService.S3,
      subnets: [{ subnetType: ec2.SubnetType.PRIVATE_ISOLATED }],
    });

    vpc.addInterfaceEndpoint('DataSyncEndpoint', {
      service: ec2.InterfaceVpcEndpointAwsService.DATASYNC,
      subnets: { subnetType: ec2.SubnetType.PRIVATE_ISOLATED },
    });

    cdk.Tags.of(vpc).add('Name', `${environment}-datasync-vpc`);
    return vpc;
  }

  /**
   * Creates security group for EFS with least privilege access
   */
  private createEfsSecurityGroup(vpc: ec2.Vpc, environment: string): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
      vpc,
      description: 'Security group for EFS access from DataSync',
      allowAllOutbound: false,
    });

    // Allow NFS traffic (port 2049) from within VPC
    securityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(2049),
      'Allow NFS access from VPC for DataSync operations'
    );

    cdk.Tags.of(securityGroup).add('Name', `${environment}-efs-security-group`);
    return securityGroup;
  }

  /**
   * Creates EFS file system with encryption and performance optimization
   */
  private createEfsFileSystem(
    vpc: ec2.Vpc, 
    securityGroup: ec2.SecurityGroup, 
    throughputMode: efs.ThroughputMode,
    provisionedThroughput: number,
    environment: string
  ): efs.FileSystem {
    const fileSystem = new efs.FileSystem(this, 'SyncTargetEfs', {
      vpc,
      encrypted: true, // Enable encryption at rest for security
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS, // Cost optimization
      performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode,
      provisionedThroughputPerSecond: throughputMode === efs.ThroughputMode.PROVISIONED 
        ? cdk.Size.mebibytes(provisionedThroughput) 
        : undefined,
      securityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    cdk.Tags.of(fileSystem).add('Name', `${environment}-datasync-efs`);
    return fileSystem;
  }

  /**
   * Creates S3 bucket with sample data for synchronization testing
   */
  private createSourceBucket(environment: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `datasync-source-${environment}-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true, // Enable versioning for data protection
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true, // Require SSL for all requests
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // Clean up on stack deletion
    });

    // Deploy sample files for testing synchronization
    new s3deploy.BucketDeployment(this, 'SampleData', {
      sources: [
        s3deploy.Source.data('sample1.txt', 'Sample file 1 content for DataSync testing'),
        s3deploy.Source.data('sample2.txt', 'Sample file 2 content for DataSync testing'),
        s3deploy.Source.data('test-folder/nested.txt', 'Nested file content for directory sync testing'),
        s3deploy.Source.data('large-file.txt', 'Large file content '.repeat(1000)), // ~17KB file for testing
      ],
      destinationBucket: bucket,
    });

    cdk.Tags.of(bucket).add('Name', `${environment}-datasync-source`);
    return bucket;
  }

  /**
   * Creates IAM role for DataSync with least privilege permissions
   */
  private createDataSyncRole(sourceBucket: s3.Bucket, environment: string): iam.Role {
    const role = new iam.Role(this, 'DataSyncServiceRole', {
      assumedBy: new iam.ServicePrincipal('datasync.amazonaws.com'),
      description: 'Service role for DataSync to access S3 and EFS resources',
    });

    // Grant read access to source S3 bucket
    sourceBucket.grantRead(role);

    // Add CloudWatch Logs permissions for monitoring
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
      ],
      resources: [
        `arn:aws:logs:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:log-group:/aws/datasync/*`,
      ],
    }));

    cdk.Tags.of(role).add('Name', `${environment}-datasync-role`);
    return role;
  }

  /**
   * Creates DataSync locations for S3 source and EFS destination
   */
  private createDataSyncLocations(
    sourceBucket: s3.Bucket,
    fileSystem: efs.FileSystem,
    vpc: ec2.Vpc,
    securityGroup: ec2.SecurityGroup,
    dataSyncRole: iam.Role,
    environment: string
  ): { s3Location: datasync.CfnLocationS3; efsLocation: datasync.CfnLocationEFS } {
    // Create S3 location for source data
    const s3Location = new datasync.CfnLocationS3(this, 'S3Location', {
      s3BucketArn: sourceBucket.bucketArn,
      s3Config: {
        bucketAccessRoleArn: dataSyncRole.roleArn,
      },
      tags: [
        {
          key: 'Name',
          value: `${environment}-datasync-s3-location`,
        },
      ],
    });

    // Create EFS location for destination
    const efsLocation = new datasync.CfnLocationEFS(this, 'EfsLocation', {
      efsFilesystemArn: fileSystem.fileSystemArn,
      ec2Config: {
        subnetArn: vpc.privateSubnets[0].subnetArn,
        securityGroupArns: [
          `arn:aws:ec2:${cdk.Aws.REGION}:${cdk.Aws.ACCOUNT_ID}:security-group/${securityGroup.securityGroupId}`,
        ],
      },
      tags: [
        {
          key: 'Name',
          value: `${environment}-datasync-efs-location`,
        },
      ],
    });

    return { s3Location, efsLocation };
  }

  /**
   * Creates DataSync task with optimal configuration for file synchronization
   */
  private createDataSyncTask(
    s3Location: datasync.CfnLocationS3,
    efsLocation: datasync.CfnLocationEFS,
    environment: string
  ): datasync.CfnTask {
    const task = new datasync.CfnTask(this, 'SyncTask', {
      sourceLocationArn: s3Location.attrLocationArn,
      destinationLocationArn: efsLocation.attrLocationArn,
      name: `${environment}-file-sync-task`,
      options: {
        // Data verification ensures integrity during transfer
        verifyMode: 'POINT_IN_TIME_CONSISTENT',
        // Always overwrite to ensure latest data
        overwriteMode: 'ALWAYS',
        // Preserve timestamps and permissions where possible
        atime: 'BEST_EFFORT',
        mtime: 'PRESERVE',
        uid: 'INT_VALUE',
        gid: 'INT_VALUE',
        // Keep deleted files to prevent accidental data loss
        preserveDeletedFiles: 'PRESERVE',
        preserveDevices: 'NONE',
        posixPermissions: 'PRESERVE',
        // No bandwidth throttling for fastest transfer
        bytesPerSecond: -1,
        // Enable task queueing for reliability
        taskQueueing: 'ENABLED',
        // Detailed logging for monitoring and troubleshooting
        logLevel: 'TRANSFER',
      },
      tags: [
        {
          key: 'Name',
          value: `${environment}-datasync-task`,
        },
      ],
    });

    return task;
  }

  /**
   * Creates CloudWatch monitoring and SNS notifications for DataSync operations
   */
  private createMonitoring(
    dataSyncTask: datasync.CfnTask,
    notificationEmail: string | undefined,
    environment: string
  ): void {
    // Create SNS topic for notifications
    const topic = new sns.Topic(this, 'DataSyncNotifications', {
      displayName: 'DataSync File Synchronization Notifications',
    });

    // Subscribe email if provided
    if (notificationEmail) {
      topic.addSubscription(new subscriptions.EmailSubscription(notificationEmail));
    }

    // Create CloudWatch alarm for task failures
    const taskFailureAlarm = new cloudwatch.Alarm(this, 'TaskFailureAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DataSync',
        metricName: 'TaskExecutionStatus',
        dimensionsMap: {
          TaskArn: dataSyncTask.attrTaskArn,
        },
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      alarmDescription: 'DataSync task execution failure',
    });

    taskFailureAlarm.addAlarmAction(new cloudwatch.AlarmAction(topic.topicArn));

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'DataSyncDashboard', {
      dashboardName: `${environment}-datasync-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'DataSync Task Execution Status',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DataSync',
                metricName: 'TaskExecutionStatus',
                dimensionsMap: {
                  TaskArn: dataSyncTask.attrTaskArn,
                },
              }),
            ],
            width: 12,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Data Transfer Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DataSync',
                metricName: 'BytesTransferred',
                dimensionsMap: {
                  TaskArn: dataSyncTask.attrTaskArn,
                },
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/DataSync',
                metricName: 'FilesTransferred',
                dimensionsMap: {
                  TaskArn: dataSyncTask.attrTaskArn,
                },
              }),
            ],
            width: 12,
          }),
        ],
      ],
    });

    cdk.Tags.of(topic).add('Name', `${environment}-datasync-notifications`);
    cdk.Tags.of(dashboard).add('Name', `${environment}-datasync-dashboard`);
  }

  /**
   * Creates comprehensive stack outputs for operational visibility
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the DataSync infrastructure',
      exportName: `${this.stackName}-VpcId`,
    });

    new cdk.CfnOutput(this, 'EfsFileSystemId', {
      value: this.fileSystem.fileSystemId,
      description: 'EFS File System ID for synchronization target',
      exportName: `${this.stackName}-EfsFileSystemId`,
    });

    new cdk.CfnOutput(this, 'EfsFileSystemArn', {
      value: this.fileSystem.fileSystemArn,
      description: 'EFS File System ARN for cross-stack references',
      exportName: `${this.stackName}-EfsFileSystemArn`,
    });

    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'S3 bucket name containing source data for synchronization',
      exportName: `${this.stackName}-SourceBucketName`,
    });

    new cdk.CfnOutput(this, 'SourceBucketArn', {
      value: this.sourceBucket.bucketArn,
      description: 'S3 bucket ARN for cross-stack references',
      exportName: `${this.stackName}-SourceBucketArn`,
    });

    new cdk.CfnOutput(this, 'DataSyncTaskArn', {
      value: this.dataSyncTask.attrTaskArn,
      description: 'DataSync task ARN for executing synchronization operations',
      exportName: `${this.stackName}-DataSyncTaskArn`,
    });

    new cdk.CfnOutput(this, 'DataSyncTaskName', {
      value: this.dataSyncTask.name!,
      description: 'DataSync task name for CLI operations',
      exportName: `${this.stackName}-DataSyncTaskName`,
    });

    // Provide useful CLI commands in outputs
    new cdk.CfnOutput(this, 'StartSyncCommand', {
      value: `aws datasync start-task-execution --task-arn ${this.dataSyncTask.attrTaskArn}`,
      description: 'AWS CLI command to start DataSync task execution',
    });

    new cdk.CfnOutput(this, 'EfsMountCommand', {
      value: `sudo mount -t efs -o tls ${this.fileSystem.fileSystemId}:/ /mnt/efs`,
      description: 'Command to mount EFS on EC2 instance (requires EFS utils)',
    });
  }

  /**
   * Applies consistent tagging across all stack resources
   */
  private applyTags(environment: string): void {
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Project', 'FileSystemSynchronization');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'DataSync-EFS-Integration');
  }
}

/**
 * CDK Application for file system synchronization infrastructure
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const vpcCidr = app.node.tryGetContext('vpcCidr') || process.env.VPC_CIDR || '10.0.0.0/16';

// Create the main stack
new FileSystemSynchronizationStack(app, 'FileSystemSynchronizationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  environment,
  notificationEmail,
  vpcCidr,
  description: 'CDK Stack for File System Sync with DataSync and EFS',
});

// Synthesize the application
app.synth();