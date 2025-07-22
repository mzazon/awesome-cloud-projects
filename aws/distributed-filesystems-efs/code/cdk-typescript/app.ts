#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as events from 'aws-cdk-lib/aws-events';

/**
 * Properties for the DistributedFileSystemsEfsStack
 */
export interface DistributedFileSystemsEfsStackProps extends cdk.StackProps {
  readonly vpcCidr?: string;
  readonly enableBackup?: boolean;
  readonly performanceMode?: efs.PerformanceMode;
  readonly throughputMode?: efs.ThroughputMode;
  readonly enableEncryption?: boolean;
}

/**
 * CDK Stack for building distributed file systems with Amazon EFS
 * 
 * This stack creates:
 * - A VPC with public and private subnets across 3 AZs
 * - An EFS file system with encryption and performance optimization
 * - Mount targets in each availability zone
 * - Access points for application-specific access control
 * - Security groups with proper NFS access rules
 * - EC2 instances for testing EFS functionality
 * - CloudWatch monitoring and logging
 * - AWS Backup configuration for automated backups
 * - Lifecycle policies for cost optimization
 */
export class DistributedFileSystemsEfsStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly fileSystem: efs.FileSystem;
  public readonly webContentAccessPoint: efs.AccessPoint;
  public readonly sharedDataAccessPoint: efs.AccessPoint;
  public readonly testInstances: ec2.Instance[];

  constructor(scope: Construct, id: string, props: DistributedFileSystemsEfsStackProps = {}) {
    super(scope, id, props);

    // Default values for optional properties
    const vpcCidr = props.vpcCidr || '10.0.0.0/16';
    const enableBackup = props.enableBackup !== false;
    const performanceMode = props.performanceMode || efs.PerformanceMode.GENERAL_PURPOSE;
    const throughputMode = props.throughputMode || efs.ThroughputMode.ELASTIC;
    const enableEncryption = props.enableEncryption !== false;

    // Create VPC with public and private subnets across 3 AZs
    this.vpc = new ec2.Vpc(this, 'EfsVpc', {
      ipAddresses: ec2.IpAddresses.cidr(vpcCidr),
      maxAzs: 3,
      natGateways: 1, // Cost optimization: use single NAT gateway
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
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag VPC for better resource management
    cdk.Tags.of(this.vpc).add('Purpose', 'EFS-Demo');
    cdk.Tags.of(this.vpc).add('Environment', 'Development');

    // Create KMS key for EFS encryption
    const efsKmsKey = enableEncryption ? new kms.Key(this, 'EfsKmsKey', {
      description: 'KMS key for EFS encryption',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    }) : undefined;

    // Create security group for EFS mount targets
    const efsSecurityGroup = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EFS mount targets',
      allowAllOutbound: false,
    });

    // Create security group for EC2 instances
    const ec2SecurityGroup = new ec2.SecurityGroup(this, 'Ec2SecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EFS client instances',
      allowAllOutbound: true,
    });

    // Allow NFS traffic from EC2 instances to EFS
    efsSecurityGroup.addIngressRule(
      ec2SecurityGroup,
      ec2.Port.tcp(2049),
      'Allow NFS traffic from EC2 instances'
    );

    // Allow SSH access to EC2 instances
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    // Allow HTTP access to EC2 instances
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP access'
    );

    // Create EFS file system with optimal configuration
    this.fileSystem = new efs.FileSystem(this, 'DistributedFileSystem', {
      vpc: this.vpc,
      performanceMode: performanceMode,
      throughputMode: throughputMode,
      encrypted: enableEncryption,
      kmsKey: efsKmsKey,
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
      transitionToArchivePolicy: efs.LifecyclePolicy.AFTER_90_DAYS,
      outOfInfrequentAccessPolicy: efs.LifecyclePolicy.AFTER_1_ACCESS,
      securityGroup: efsSecurityGroup,
      enableBackups: enableBackup,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create access point for web content with specific POSIX permissions
    this.webContentAccessPoint = new efs.AccessPoint(this, 'WebContentAccessPoint', {
      fileSystem: this.fileSystem,
      path: '/web-content',
      posixUser: {
        uid: 1000,
        gid: 1000,
      },
      creationInfo: {
        ownerUid: 1000,
        ownerGid: 1000,
        permissions: '755',
      },
    });

    // Create access point for shared data with restricted permissions
    this.sharedDataAccessPoint = new efs.AccessPoint(this, 'SharedDataAccessPoint', {
      fileSystem: this.fileSystem,
      path: '/shared-data',
      posixUser: {
        uid: 1001,
        gid: 1001,
      },
      creationInfo: {
        ownerUid: 1001,
        ownerGid: 1001,
        permissions: '750',
      },
    });

    // Create CloudWatch log group for EFS monitoring
    const efsLogGroup = new logs.LogGroup(this, 'EfsLogGroup', {
      logGroupName: `/aws/efs/${this.fileSystem.fileSystemId}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch dashboard for EFS monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'EfsDashboard', {
      dashboardName: `EFS-${this.fileSystem.fileSystemId}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'EFS Data Transfer',
            left: [
              this.fileSystem.metricTotalIOBytes({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              this.fileSystem.metricDataReadIOBytes({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              this.fileSystem.metricDataWriteIOBytes({
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'EFS Performance Metrics',
            left: [
              this.fileSystem.metricClientConnections({
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              this.fileSystem.metricTotalIOTime({
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Get the latest Amazon Linux 2 AMI
    const amazonLinux2 = ec2.MachineImage.latestAmazonLinux2({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
    });

    // Create IAM role for EC2 instances with EFS and CloudWatch permissions
    const ec2Role = new iam.Role(this, 'Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonElasticFileSystemClientFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // Create user data script for EFS client setup
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y amazon-efs-utils',
      'yum install -y amazon-cloudwatch-agent',
      '',
      '# Create mount points',
      'mkdir -p /mnt/efs',
      'mkdir -p /mnt/web-content',
      'mkdir -p /mnt/shared-data',
      '',
      '# Configure CloudWatch agent',
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF',
      JSON.stringify({
        logs: {
          logs_collected: {
            files: {
              collect_list: [
                {
                  file_path: '/var/log/messages',
                  log_group_name: efsLogGroup.logGroupName,
                  log_stream_name: '{instance_id}/var/log/messages',
                },
              ],
            },
          },
        },
      }),
      'EOF',
      '',
      '# Start CloudWatch agent',
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\',
      '    -a fetch-config -m ec2 -s \\',
      '    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json',
      '',
      '# Mount EFS file system',
      `echo "${this.fileSystem.fileSystemId}:/ /mnt/efs efs defaults,_netdev,tls,iam" >> /etc/fstab`,
      `echo "${this.fileSystem.fileSystemId}:/ /mnt/web-content efs defaults,_netdev,tls,iam,accesspoint=${this.webContentAccessPoint.accessPointId}" >> /etc/fstab`,
      `echo "${this.fileSystem.fileSystemId}:/ /mnt/shared-data efs defaults,_netdev,tls,iam,accesspoint=${this.sharedDataAccessPoint.accessPointId}" >> /etc/fstab`,
      '',
      '# Mount all filesystems',
      'mount -a',
      '',
      '# Create test files',
      'echo "Hello from $(hostname)" > /mnt/efs/test-$(hostname).txt',
      'echo "Web content from $(hostname)" > /mnt/web-content/web-$(hostname).txt',
      'echo "Shared data from $(hostname)" > /mnt/shared-data/data-$(hostname).txt',
    );

    // Create EC2 instances in different AZs
    this.testInstances = [];
    const availabilityZones = this.vpc.availabilityZones.slice(0, 2); // Use first 2 AZs

    availabilityZones.forEach((az, index) => {
      const instance = new ec2.Instance(this, `TestInstance${index + 1}`, {
        instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
        machineImage: amazonLinux2,
        vpc: this.vpc,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PUBLIC,
          availabilityZones: [az],
        },
        securityGroup: ec2SecurityGroup,
        role: ec2Role,
        userData: userData,
        userDataCausesReplacement: false,
        keyName: undefined, // No key pair needed for this demo
      });

      // Tag instance for identification
      cdk.Tags.of(instance).add('Name', `EFS-Test-Instance-${index + 1}`);
      cdk.Tags.of(instance).add('AvailabilityZone', az);
      
      this.testInstances.push(instance);
    });

    // Configure AWS Backup if enabled
    if (enableBackup) {
      // Create backup vault with encryption
      const backupVault = new backup.BackupVault(this, 'EfsBackupVault', {
        backupVaultName: `efs-backup-${this.fileSystem.fileSystemId}`,
        encryptionKey: efsKmsKey,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      // Create backup plan with daily backups
      const backupPlan = new backup.BackupPlan(this, 'EfsBackupPlan', {
        backupPlanName: `EFS-Daily-Backup-${this.fileSystem.fileSystemId}`,
        backupVault: backupVault,
        backupPlanRules: [
          {
            ruleName: 'Daily-Backup',
            scheduleExpression: events.Schedule.cron({
              hour: '2',
              minute: '0',
            }),
            startWindow: cdk.Duration.minutes(60),
            deleteAfter: cdk.Duration.days(30),
          },
        ],
      });

      // Create backup selection to include EFS
      new backup.BackupSelection(this, 'EfsBackupSelection', {
        backupPlan: backupPlan,
        selectionName: `EFS-Selection-${this.fileSystem.fileSystemId}`,
        resources: [
          backup.BackupResource.fromArn(
            `arn:aws:elasticfilesystem:${this.region}:${this.account}:file-system/${this.fileSystem.fileSystemId}`
          ),
        ],
      });
    }

    // Output important information
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the EFS deployment',
    });

    new cdk.CfnOutput(this, 'FileSystemId', {
      value: this.fileSystem.fileSystemId,
      description: 'EFS File System ID',
    });

    new cdk.CfnOutput(this, 'FileSystemArn', {
      value: this.fileSystem.fileSystemArn,
      description: 'EFS File System ARN',
    });

    new cdk.CfnOutput(this, 'WebContentAccessPointId', {
      value: this.webContentAccessPoint.accessPointId,
      description: 'Access Point ID for web content',
    });

    new cdk.CfnOutput(this, 'SharedDataAccessPointId', {
      value: this.sharedDataAccessPoint.accessPointId,
      description: 'Access Point ID for shared data',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=EFS-${this.fileSystem.fileSystemId}`,
      description: 'CloudWatch Dashboard URL',
    });

    new cdk.CfnOutput(this, 'TestInstanceIds', {
      value: this.testInstances.map(instance => instance.instanceId).join(', '),
      description: 'EC2 Test Instance IDs',
    });

    new cdk.CfnOutput(this, 'MountCommands', {
      value: [
        `sudo mount -t efs -o tls,iam ${this.fileSystem.fileSystemId}:/ /mnt/efs`,
        `sudo mount -t efs -o tls,iam,accesspoint=${this.webContentAccessPoint.accessPointId} ${this.fileSystem.fileSystemId}:/ /mnt/web-content`,
        `sudo mount -t efs -o tls,iam,accesspoint=${this.sharedDataAccessPoint.accessPointId} ${this.fileSystem.fileSystemId}:/ /mnt/shared-data`,
      ].join(' && '),
      description: 'Commands to mount EFS on EC2 instances',
    });
  }
}

// Create CDK app
const app = new cdk.App();

// Deploy the stack with default configuration
new DistributedFileSystemsEfsStack(app, 'DistributedFileSystemsEfsStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Building distributed file systems with Amazon EFS - CDK TypeScript implementation',
  tags: {
    Project: 'DistributedFileSystemsEfs',
    Environment: 'Development',
    CostCenter: 'Engineering',
  },
});

// Synthesize the CloudFormation template
app.synth();