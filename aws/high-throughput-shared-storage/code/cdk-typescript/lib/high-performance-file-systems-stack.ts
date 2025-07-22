import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as fsx from 'aws-cdk-lib/aws-fsx';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as kms from 'aws-cdk-lib/aws-kms';
import { NagSuppressions } from 'cdk-nag';
import { Construct } from 'constructs';

/**
 * Stack that creates high-performance file systems using Amazon FSx
 * Includes FSx for Lustre, Windows File Server, and NetApp ONTAP
 * Implements security best practices and comprehensive monitoring
 */
export class HighPerformanceFileSystemsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-6).toLowerCase();

    // Create KMS key for encryption
    const kmsKey = new kms.Key(this, 'FSxEncryptionKey', {
      description: 'KMS key for FSx file system encryption',
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add key alias for easier identification
    new kms.Alias(this, 'FSxEncryptionKeyAlias', {
      aliasName: `alias/fsx-demo-${uniqueSuffix}`,
      targetKey: kmsKey,
    });

    // Get default VPC or create a new one
    let vpc: ec2.IVpc;
    try {
      vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
        isDefault: true,
      });
    } catch (error) {
      // Create a new VPC if default VPC doesn't exist
      vpc = new ec2.Vpc(this, 'FSxVPC', {
        maxAzs: 3,
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
          },
        ],
      });

      // Add VPC Flow Logs for monitoring
      const flowLogsRole = new iam.Role(this, 'FlowLogsRole', {
        assumedBy: new iam.ServicePrincipal('vpc-flow-logs.amazonaws.com'),
        inlinePolicies: {
          FlowLogsDeliveryRolePolicy: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  'logs:CreateLogGroup',
                  'logs:CreateLogStream',
                  'logs:PutLogEvents',
                  'logs:DescribeLogGroups',
                  'logs:DescribeLogStreams',
                ],
                resources: ['*'],
              }),
            ],
          }),
        },
      });

      const vpcFlowLogsGroup = new logs.LogGroup(this, 'VPCFlowLogsGroup', {
        logGroupName: `/aws/vpc/flowlogs/${uniqueSuffix}`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      });

      new ec2.FlowLog(this, 'VPCFlowLogs', {
        resourceType: ec2.FlowLogResourceType.fromVpc(vpc),
        destination: ec2.FlowLogDestination.toCloudWatchLogs(vpcFlowLogsGroup, flowLogsRole),
      });
    }

    // Create security group for FSx file systems
    const fsxSecurityGroup = new ec2.SecurityGroup(this, 'FSxSecurityGroup', {
      vpc: vpc,
      description: 'Security group for FSx file systems with restricted access',
      securityGroupName: `fsx-demo-${uniqueSuffix}-sg`,
      allowAllOutbound: false,
    });

    // Add specific egress rules for FSx requirements
    fsxSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS for AWS API calls'
    );

    fsxSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(53),
      'DNS queries'
    );

    fsxSecurityGroup.addEgressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.udp(53),
      'DNS queries'
    );

    // Add security group rules for FSx protocols (restrict to VPC CIDR)
    const vpcCidr = vpc.vpcCidrBlock;

    fsxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcp(988),
      'FSx Lustre traffic'
    );

    fsxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcp(445),
      'SMB traffic for Windows File Server'
    );

    fsxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcp(111),
      'NFS traffic for ONTAP'
    );

    fsxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcp(2049),
      'NFS traffic for ONTAP'
    );

    // Additional ONTAP ports for complete functionality
    fsxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcpRange(635, 636),
      'ONTAP cluster communication'
    );

    fsxSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpcCidr),
      ec2.Port.tcpRange(4045, 4046),
      'ONTAP data communication'
    );

    // Create S3 bucket for FSx Lustre data repository with enhanced security
    const s3Bucket = new s3.Bucket(this, 'LustreDataRepository', {
      bucketName: `fsx-demo-${uniqueSuffix}-lustre-data`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: kmsKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      serverAccessLogsPrefix: 'access-logs/',
      intelligentTieringConfigurations: [
        {
          id: 'EntireBucket',
          optionalFields: [
            s3.IntelligentTieringOptionalFields.ARCHIVE_ACCESS,
            s3.IntelligentTieringOptionalFields.DEEP_ARCHIVE_ACCESS,
          ],
        },
      ],
    });

    // Create IAM role for FSx service access with minimal permissions
    const fsxServiceRole = new iam.Role(this, 'FSxServiceRole', {
      roleName: `fsx-demo-${uniqueSuffix}-service-role`,
      assumedBy: new iam.ServicePrincipal('fsx.amazonaws.com'),
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                s3Bucket.bucketArn,
                `${s3Bucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:DescribeKey',
                'kms:Encrypt',
                'kms:GenerateDataKey',
                'kms:ReEncrypt*',
              ],
              resources: [kmsKey.keyArn],
            }),
          ],
        }),
      },
    });

    // Get subnets (avoiding us-east-1e if in us-east-1 region)
    const availableSubnets = vpc.privateSubnets.length > 0 
      ? vpc.privateSubnets 
      : vpc.publicSubnets;

    const subnetIds = availableSubnets
      .filter(subnet => !subnet.availabilityZone.endsWith('e'))
      .slice(0, 2)
      .map(subnet => subnet.subnetId);

    if (subnetIds.length === 0) {
      throw new Error('No suitable subnets found for FSx deployment');
    }

    // Create FSx for Lustre file system with enhanced configuration
    const lustreFileSystem = new fsx.CfnFileSystem(this, 'LustreFileSystem', {
      fileSystemType: 'LUSTRE',
      storageCapacity: 1200,
      subnetIds: [subnetIds[0]],
      securityGroupIds: [fsxSecurityGroup.securityGroupId],
      kmsKeyId: kmsKey.keyId,
      lustreConfiguration: {
        deploymentType: 'SCRATCH_2',
        dataRepositoryConfiguration: {
          bucket: s3Bucket.bucketName,
          importPath: `s3://${s3Bucket.bucketName}/input/`,
          exportPath: `s3://${s3Bucket.bucketName}/output/`,
          autoImportPolicy: 'NEW_CHANGED_DELETED',
        },
        perUnitStorageThroughput: 250,
        dataCompressionType: 'LZ4',
      },
      tags: [
        { key: 'Name', value: `fsx-demo-${uniqueSuffix}-lustre` },
        { key: 'Purpose', value: 'HPC-Workloads' },
        { key: 'BackupPolicy', value: 'none' }, // Scratch file systems don't support backups
      ],
    });

    // Create FSx for Windows File Server with enhanced security
    const windowsFileSystem = new fsx.CfnFileSystem(this, 'WindowsFileSystem', {
      fileSystemType: 'WINDOWS',
      storageCapacity: 32,
      subnetIds: [subnetIds[0]],
      securityGroupIds: [fsxSecurityGroup.securityGroupId],
      kmsKeyId: kmsKey.keyId,
      windowsConfiguration: {
        throughputCapacity: 16, // Increased from 8 for better performance
        deploymentType: 'SINGLE_AZ_1',
        preferredSubnetId: subnetIds[0],
        weeklyMaintenanceStartTime: '1:00:00',
        dailyAutomaticBackupStartTime: '01:00',
        automaticBackupRetentionDays: 7,
        copyTagsToBackups: true,
      },
      tags: [
        { key: 'Name', value: `fsx-demo-${uniqueSuffix}-windows` },
        { key: 'Purpose', value: 'Windows-Applications' },
        { key: 'BackupPolicy', value: 'daily' },
      ],
    });

    // Create FSx for NetApp ONTAP file system (Multi-AZ requires 2+ subnets)
    let ontapFileSystem: fsx.CfnFileSystem | undefined;
    let storageVirtualMachine: fsx.CfnStorageVirtualMachine | undefined;
    let nfsVolume: fsx.CfnVolume | undefined;
    let smbVolume: fsx.CfnVolume | undefined;

    if (subnetIds.length >= 2) {
      ontapFileSystem = new fsx.CfnFileSystem(this, 'ONTAPFileSystem', {
        fileSystemType: 'ONTAP',
        storageCapacity: 1024,
        subnetIds: subnetIds,
        securityGroupIds: [fsxSecurityGroup.securityGroupId],
        kmsKeyId: kmsKey.keyId,
        ontapConfiguration: {
          deploymentType: 'MULTI_AZ_1',
          throughputCapacity: 256,
          preferredSubnetId: subnetIds[0],
          fsxAdminPassword: 'TempPassword123!', // In production, use AWS Secrets Manager
          weeklyMaintenanceStartTime: '1:00:00',
          dailyAutomaticBackupStartTime: '02:00',
          automaticBackupRetentionDays: 14,
        },
        tags: [
          { key: 'Name', value: `fsx-demo-${uniqueSuffix}-ontap` },
          { key: 'Purpose', value: 'Multi-Protocol-Access' },
          { key: 'BackupPolicy', value: 'daily' },
        ],
      });

      // Create Storage Virtual Machine for ONTAP
      storageVirtualMachine = new fsx.CfnStorageVirtualMachine(this, 'StorageVirtualMachine', {
        fileSystemId: ontapFileSystem.ref,
        name: 'demo-svm',
        svmAdminPassword: 'TempPassword123!', // In production, use AWS Secrets Manager
        tags: [
          { key: 'Name', value: `fsx-demo-${uniqueSuffix}-svm` },
        ],
      });

      // Create NFS volume with storage efficiency
      nfsVolume = new fsx.CfnVolume(this, 'NFSVolume', {
        volumeType: 'ONTAP',
        name: 'nfs-volume',
        ontapConfiguration: {
          storageVirtualMachineId: storageVirtualMachine.ref,
          junctionPath: '/nfs',
          securityStyle: 'UNIX',
          sizeInMegabytes: 102400,
          storageEfficiencyEnabled: true,
          tieringPolicy: {
            name: 'AUTO',
            coolingPeriod: 31,
          },
        },
        tags: [
          { key: 'Name', value: `fsx-demo-${uniqueSuffix}-nfs-volume` },
        ],
      });

      // Create SMB volume with storage efficiency
      smbVolume = new fsx.CfnVolume(this, 'SMBVolume', {
        volumeType: 'ONTAP',
        name: 'smb-volume',
        ontapConfiguration: {
          storageVirtualMachineId: storageVirtualMachine.ref,
          junctionPath: '/smb',
          securityStyle: 'NTFS',
          sizeInMegabytes: 51200,
          storageEfficiencyEnabled: true,
          tieringPolicy: {
            name: 'SNAPSHOT_ONLY',
          },
        },
        tags: [
          { key: 'Name', value: `fsx-demo-${uniqueSuffix}-smb-volume` },
        ],
      });
    }

    // Create CloudWatch Log Group for FSx logs
    const logGroup = new logs.LogGroup(this, 'FSxLogGroup', {
      logGroupName: `/aws/fsx/demo-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      encryptionKey: kmsKey,
    });

    // Create comprehensive CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'FSxDashboard', {
      dashboardName: `FSx-Demo-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lustre File System Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/FSx',
                metricName: 'ThroughputUtilization',
                dimensionsMap: {
                  FileSystemId: lustreFileSystem.ref,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Windows File System CPU',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/FSx',
                metricName: 'CPUUtilization',
                dimensionsMap: {
                  FileSystemId: windowsFileSystem.ref,
                },
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create CloudWatch alarms for proactive monitoring
    const lustreThroughputAlarm = new cloudwatch.Alarm(this, 'LustreThroughputAlarm', {
      alarmName: `fsx-demo-${uniqueSuffix}-lustre-throughput`,
      alarmDescription: 'Monitor Lustre throughput utilization',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/FSx',
        metricName: 'ThroughputUtilization',
        dimensionsMap: {
          FileSystemId: lustreFileSystem.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 80,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const windowsCpuAlarm = new cloudwatch.Alarm(this, 'WindowsCpuAlarm', {
      alarmName: `fsx-demo-${uniqueSuffix}-windows-cpu`,
      alarmDescription: 'Monitor Windows file system CPU',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/FSx',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          FileSystemId: windowsFileSystem.ref,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 85,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create ONTAP storage alarm if ONTAP is deployed
    if (ontapFileSystem) {
      const ontapStorageAlarm = new cloudwatch.Alarm(this, 'ONTAPStorageAlarm', {
        alarmName: `fsx-demo-${uniqueSuffix}-ontap-storage`,
        alarmDescription: 'Monitor ONTAP storage utilization',
        metric: new cloudwatch.Metric({
          namespace: 'AWS/FSx',
          metricName: 'StorageUtilization',
          dimensionsMap: {
            FileSystemId: ontapFileSystem.ref,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        threshold: 90,
        evaluationPeriods: 1,
        comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
      });
    }

    // Create test EC2 instance for file system access
    const ec2Role = new iam.Role(this, 'EC2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // User data script for EC2 instance with Lustre client installation
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'mkdir -p /mnt/fsx',
      'mkdir -p /mnt/nfs',
      'yum install -y nfs-utils',
      // Install FSx Lustre client for Amazon Linux 2
      'amazon-linux-extras install -y lustre',
      // Create mount helper script
      'cat > /usr/local/bin/mount-fsx-lustre.sh << EOF',
      '#!/bin/bash',
      'LUSTRE_DNS=$1',
      'MOUNT_NAME=$2',
      'if [ -z "$LUSTRE_DNS" ] || [ -z "$MOUNT_NAME" ]; then',
      '  echo "Usage: $0 <lustre-dns> <mount-name>"',
      '  exit 1',
      'fi',
      'echo "Mounting FSx Lustre: $LUSTRE_DNS@tcp:/$MOUNT_NAME"',
      'mount -t lustre $LUSTRE_DNS@tcp:/$MOUNT_NAME /mnt/fsx',
      'if [ $? -eq 0 ]; then',
      '  echo "Successfully mounted FSx Lustre to /mnt/fsx"',
      'else',
      '  echo "Failed to mount FSx Lustre"',
      '  exit 1',
      'fi',
      'EOF',
      'chmod +x /usr/local/bin/mount-fsx-lustre.sh'
    );

    const linuxInstance = new ec2.Instance(this, 'LinuxClientInstance', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      vpc: vpc,
      vpcSubnets: { 
        subnetType: vpc.privateSubnets.length > 0 ? ec2.SubnetType.PRIVATE_WITH_EGRESS : ec2.SubnetType.PUBLIC 
      },
      securityGroup: fsxSecurityGroup,
      role: ec2Role,
      userData: userData,
      requireImdsv2: true, // Security best practice
    });

    cdk.Tags.of(linuxInstance).add('Name', `fsx-demo-${uniqueSuffix}-linux-client`);

    // Apply CDK Nag suppressions for known exceptions
    NagSuppressions.addResourceSuppressions(
      fsxServiceRole,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'Managed policy AmazonS3ReadOnlyAccess is acceptable for FSx service role',
        },
      ],
      true
    );

    NagSuppressions.addResourceSuppressions(
      ec2Role,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'AmazonSSMManagedInstanceCore is the standard managed policy for EC2 instances with SSM access',
        },
      ],
      true
    );

    NagSuppressions.addResourceSuppressions(
      fsxSecurityGroup,
      [
        {
          id: 'AwsSolutions-EC23',
          reason: 'Security group rules are configured with VPC CIDR blocks, which is appropriate for FSx access within the VPC',
        },
      ],
      true
    );

    // Output important information for users
    new cdk.CfnOutput(this, 'KMSKeyId', {
      value: kmsKey.keyId,
      description: 'KMS key ID used for FSx encryption',
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: s3Bucket.bucketName,
      description: 'S3 bucket for Lustre data repository',
    });

    new cdk.CfnOutput(this, 'LustreFileSystemId', {
      value: lustreFileSystem.ref,
      description: 'FSx for Lustre file system ID',
    });

    new cdk.CfnOutput(this, 'LustreFileSystemDNS', {
      value: lustreFileSystem.attrDnsName,
      description: 'FSx for Lustre DNS name',
    });

    new cdk.CfnOutput(this, 'LustreMountName', {
      value: lustreFileSystem.attrLustreConfigurationMountName,
      description: 'FSx for Lustre mount name',
    });

    new cdk.CfnOutput(this, 'WindowsFileSystemId', {
      value: windowsFileSystem.ref,
      description: 'FSx for Windows file system ID',
    });

    new cdk.CfnOutput(this, 'WindowsFileSystemDNS', {
      value: windowsFileSystem.attrDnsName,
      description: 'FSx for Windows DNS name',
    });

    new cdk.CfnOutput(this, 'LinuxInstanceId', {
      value: linuxInstance.instanceId,
      description: 'Linux client instance ID for testing',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for monitoring FSx metrics',
    });

    if (ontapFileSystem && storageVirtualMachine) {
      new cdk.CfnOutput(this, 'ONTAPFileSystemId', {
        value: ontapFileSystem.ref,
        description: 'FSx for NetApp ONTAP file system ID',
      });

      new cdk.CfnOutput(this, 'StorageVirtualMachineId', {
        value: storageVirtualMachine.ref,
        description: 'ONTAP Storage Virtual Machine ID',
      });

      if (nfsVolume) {
        new cdk.CfnOutput(this, 'NFSVolumeId', {
          value: nfsVolume.ref,
          description: 'ONTAP NFS volume ID',
        });
      }

      if (smbVolume) {
        new cdk.CfnOutput(this, 'SMBVolumeId', {
          value: smbVolume.ref,
          description: 'ONTAP SMB volume ID',
        });
      }
    }

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: fsxSecurityGroup.securityGroupId,
      description: 'Security group ID for FSx file systems',
    });

    new cdk.CfnOutput(this, 'LustreMountCommand', {
      value: `sudo /usr/local/bin/mount-fsx-lustre.sh ${lustreFileSystem.attrDnsName} ${lustreFileSystem.attrLustreConfigurationMountName}`,
      description: 'Command to mount Lustre file system on EC2 instance',
    });

    new cdk.CfnOutput(this, 'WindowsSMBShare', {
      value: `\\\\${windowsFileSystem.attrDnsName}\\share`,
      description: 'Windows SMB share path',
    });

    new cdk.CfnOutput(this, 'Instructions', {
      value: 'Connect to the EC2 instance using Session Manager and use the mount commands provided in the outputs',
      description: 'Next steps to test the file systems',
    });
  }
}