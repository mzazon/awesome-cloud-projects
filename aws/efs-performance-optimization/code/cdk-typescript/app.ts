#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

/**
 * Stack for EFS Performance Optimization and Monitoring
 * 
 * This stack creates:
 * - EFS file system with performance optimization (General Purpose mode, Provisioned throughput)
 * - Multi-AZ mount targets with security groups
 * - CloudWatch dashboard for monitoring EFS performance
 * - CloudWatch alarms for proactive monitoring
 * - IAM roles for EC2 instances to access EFS
 */
export class EfsPerformanceOptimizationStack extends cdk.Stack {
  public readonly fileSystem: efs.FileSystem;
  public readonly securityGroup: ec2.SecurityGroup;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get default VPC or create one if it doesn't exist
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // Create security group for EFS mount targets
    this.securityGroup = new ec2.SecurityGroup(this, 'EfsSecurityGroup', {
      vpc: vpc,
      description: 'Security group for EFS mount targets',
      allowAllOutbound: false
    });

    // Allow NFS traffic (port 2049) from instances in the same security group
    this.securityGroup.addIngressRule(
      this.securityGroup,
      ec2.Port.tcp(2049),
      'Allow NFS traffic from EC2 instances'
    );

    // Create EFS file system with performance optimization
    this.fileSystem = new efs.FileSystem(this, 'PerformanceOptimizedEfs', {
      vpc: vpc,
      performanceMode: efs.PerformanceMode.GENERAL_PURPOSE,
      throughputMode: efs.ThroughputMode.PROVISIONED,
      provisionedThroughputPerSecond: cdk.Size.mebibytes(100),
      encrypted: true,
      securityGroup: this.securityGroup,
      enableBackupPolicy: true,
      lifecyclePolicy: efs.LifecyclePolicy.AFTER_30_DAYS,
      removalPolicy: cdk.RemovalPolicy.DESTROY // For demo purposes
    });

    // Add tags to the file system
    cdk.Tags.of(this.fileSystem).add('Name', 'PerformanceOptimizedEFS');
    cdk.Tags.of(this.fileSystem).add('Environment', 'production');
    cdk.Tags.of(this.fileSystem).add('Purpose', 'performance-optimized');

    // Create IAM role for EC2 instances
    const ec2Role = new iam.Role(this, 'EfsEc2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instances to access EFS',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonElasticFileSystemClientWrite')
      ]
    });

    // Create instance profile for EC2 role
    new iam.CfnInstanceProfile(this, 'EfsEc2InstanceProfile', {
      roles: [ec2Role.roleName],
      instanceProfileName: `EfsEc2Profile-${this.stackName}`
    });

    // Create CloudWatch dashboard for EFS monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'EfsPerformanceDashboard', {
      dashboardName: `EFS-Performance-${this.stackName}`,
      defaultInterval: cdk.Duration.minutes(5)
    });

    // Add widgets to the dashboard
    this.createDashboardWidgets();

    // Create CloudWatch alarms for performance monitoring
    this.createPerformanceAlarms();

    // Output important values
    new cdk.CfnOutput(this, 'FileSystemId', {
      value: this.fileSystem.fileSystemId,
      description: 'EFS File System ID'
    });

    new cdk.CfnOutput(this, 'FileSystemArn', {
      value: this.fileSystem.fileSystemArn,
      description: 'EFS File System ARN'
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: 'Security Group ID for EFS access'
    });

    new cdk.CfnOutput(this, 'EC2RoleArn', {
      value: ec2Role.roleArn,
      description: 'IAM Role ARN for EC2 instances'
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL'
    });

    new cdk.CfnOutput(this, 'MountCommand', {
      value: `sudo mount -t efs -o tls ${this.fileSystem.fileSystemId}:/ /mnt/efs`,
      description: 'Command to mount EFS on EC2 instances'
    });
  }

  /**
   * Create CloudWatch dashboard widgets for EFS monitoring
   */
  private createDashboardWidgets(): void {
    // IO Throughput widget
    const ioThroughputWidget = new cloudwatch.GraphWidget({
      title: 'EFS IO Throughput',
      left: [
        this.fileSystem.metricTotalIOBytes({
          statistic: cloudwatch.Statistic.SUM,
          period: cdk.Duration.minutes(5)
        }),
        this.fileSystem.metricReadIOBytes({
          statistic: cloudwatch.Statistic.SUM,
          period: cdk.Duration.minutes(5)
        }),
        this.fileSystem.metricWriteIOBytes({
          statistic: cloudwatch.Statistic.SUM,
          period: cdk.Duration.minutes(5)
        })
      ],
      width: 12,
      height: 6
    });

    // IO Latency widget
    const ioLatencyWidget = new cloudwatch.GraphWidget({
      title: 'EFS IO Latency',
      left: [
        this.fileSystem.metricTotalIOTime({
          statistic: cloudwatch.Statistic.AVERAGE,
          period: cdk.Duration.minutes(5)
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/EFS',
          metricName: 'ReadIOTime',
          dimensionsMap: {
            FileSystemId: this.fileSystem.fileSystemId
          },
          statistic: cloudwatch.Statistic.AVERAGE,
          period: cdk.Duration.minutes(5)
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/EFS',
          metricName: 'WriteIOTime',
          dimensionsMap: {
            FileSystemId: this.fileSystem.fileSystemId
          },
          statistic: cloudwatch.Statistic.AVERAGE,
          period: cdk.Duration.minutes(5)
        })
      ],
      width: 12,
      height: 6
    });

    // Client Connections widget
    const clientConnectionsWidget = new cloudwatch.GraphWidget({
      title: 'EFS Client Connections',
      left: [
        this.fileSystem.metricClientConnections({
          statistic: cloudwatch.Statistic.SUM,
          period: cdk.Duration.minutes(5)
        })
      ],
      width: 12,
      height: 6
    });

    // IO Limit Utilization widget
    const ioLimitWidget = new cloudwatch.GraphWidget({
      title: 'EFS IO Limit Utilization',
      left: [
        this.fileSystem.metricPercentIOLimit({
          statistic: cloudwatch.Statistic.AVERAGE,
          period: cdk.Duration.minutes(5)
        })
      ],
      width: 12,
      height: 6
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(
      ioThroughputWidget,
      ioLatencyWidget
    );
    this.dashboard.addWidgets(
      clientConnectionsWidget,
      ioLimitWidget
    );
  }

  /**
   * Create CloudWatch alarms for proactive performance monitoring
   */
  private createPerformanceAlarms(): void {
    // High throughput utilization alarm
    const highThroughputAlarm = new cloudwatch.Alarm(this, 'HighThroughputUtilizationAlarm', {
      alarmName: `EFS-High-Throughput-Utilization-${this.stackName}`,
      alarmDescription: 'EFS throughput utilization exceeds 80%',
      metric: this.fileSystem.metricPercentIOLimit({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // High client connections alarm
    const highClientConnectionsAlarm = new cloudwatch.Alarm(this, 'HighClientConnectionsAlarm', {
      alarmName: `EFS-High-Client-Connections-${this.stackName}`,
      alarmDescription: 'EFS client connections exceed 500',
      metric: this.fileSystem.metricClientConnections({
        statistic: cloudwatch.Statistic.SUM,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 500,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // High IO latency alarm
    const highIOLatencyAlarm = new cloudwatch.Alarm(this, 'HighIOLatencyAlarm', {
      alarmName: `EFS-High-IO-Latency-${this.stackName}`,
      alarmDescription: 'EFS average IO time exceeds 50ms',
      metric: this.fileSystem.metricTotalIOTime({
        statistic: cloudwatch.Statistic.AVERAGE,
        period: cdk.Duration.minutes(5)
      }),
      threshold: 50,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Output alarm ARNs
    new cdk.CfnOutput(this, 'HighThroughputAlarmArn', {
      value: highThroughputAlarm.alarmArn,
      description: 'High Throughput Utilization Alarm ARN'
    });

    new cdk.CfnOutput(this, 'HighClientConnectionsAlarmArn', {
      value: highClientConnectionsAlarm.alarmArn,
      description: 'High Client Connections Alarm ARN'
    });

    new cdk.CfnOutput(this, 'HighIOLatencyAlarmArn', {
      value: highIOLatencyAlarm.alarmArn,
      description: 'High IO Latency Alarm ARN'
    });
  }
}

/**
 * Optional: Demo EC2 instance for testing EFS performance
 * Uncomment this class and instantiate it in the main app if you want to include
 * a test EC2 instance with the EFS mount configured
 */
export class EfsTestInstanceStack extends cdk.Stack {
  constructor(scope: Construct, id: string, efsStack: EfsPerformanceOptimizationStack, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // User data script to mount EFS and install performance testing tools
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      // Update system
      'yum update -y',
      
      // Install EFS utilities and performance testing tools
      'yum install -y amazon-efs-utils fio iotop htop',
      
      // Create mount point
      'mkdir -p /mnt/efs',
      
      // Mount EFS with TLS encryption
      `echo "${efsStack.fileSystem.fileSystemId}.efs.${this.region}.amazonaws.com:/ /mnt/efs efs defaults,_netdev,tls" >> /etc/fstab`,
      'mount -a',
      
      // Set permissions
      'chmod 777 /mnt/efs',
      
      // Create test script for performance testing
      'cat > /home/ec2-user/efs-performance-test.sh << EOF',
      '#!/bin/bash',
      'echo "Starting EFS Performance Test..."',
      'echo "Testing write performance..."',
      'fio --name=write-test --ioengine=libaio --iodepth=32 --rw=write --bs=64k --direct=1 --size=1G --numjobs=4 --runtime=60 --group_reporting --filename=/mnt/efs/test-write',
      'echo "Testing read performance..."',
      'fio --name=read-test --ioengine=libaio --iodepth=32 --rw=read --bs=64k --direct=1 --size=1G --numjobs=4 --runtime=60 --group_reporting --filename=/mnt/efs/test-read',
      'echo "Cleaning up test files..."',
      'rm -f /mnt/efs/test-*',
      'echo "Performance test completed!"',
      'EOF',
      'chmod +x /home/ec2-user/efs-performance-test.sh',
      'chown ec2-user:ec2-user /home/ec2-user/efs-performance-test.sh'
    );

    // Create EC2 instance for testing
    const testInstance = new ec2.Instance(this, 'EfsTestInstance', {
      vpc: vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
      machineImage: new ec2.AmazonLinuxImage({
        generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2
      }),
      securityGroup: efsStack.securityGroup,
      userData: userData,
      role: iam.Role.fromRoleArn(this, 'ImportedRole', 
        `arn:aws:iam::${this.account}:role/EfsEc2Role-${efsStack.stackName}`,
        { mutable: false }
      )
    });

    // Add additional security group rule for SSH access (optional)
    efsStack.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for testing (remove in production)'
    );

    // Output instance information
    new cdk.CfnOutput(this, 'TestInstanceId', {
      value: testInstance.instanceId,
      description: 'EC2 Test Instance ID'
    });

    new cdk.CfnOutput(this, 'TestInstancePublicIp', {
      value: testInstance.instancePublicIp,
      description: 'EC2 Test Instance Public IP'
    });

    new cdk.CfnOutput(this, 'SshCommand', {
      value: `ssh -i your-key.pem ec2-user@${testInstance.instancePublicIp}`,
      description: 'SSH command to connect to test instance'
    });

    new cdk.CfnOutput(this, 'PerformanceTestCommand', {
      value: '/home/ec2-user/efs-performance-test.sh',
      description: 'Command to run EFS performance test'
    });
  }
}

// Main CDK App
const app = new cdk.App();

// Create the main EFS stack
const efsStack = new EfsPerformanceOptimizationStack(app, 'EfsPerformanceOptimizationStack', {
  description: 'Stack for EFS Performance Optimization and Monitoring',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Optionally create test instance stack (uncomment to deploy)
// const testInstanceStack = new EfsTestInstanceStack(app, 'EfsTestInstanceStack', efsStack, {
//   description: 'Optional EC2 instance for testing EFS performance',
//   env: {
//     account: process.env.CDK_DEFAULT_ACCOUNT,
//     region: process.env.CDK_DEFAULT_REGION,
//   },
// });

// Add dependencies if using test instance
// testInstanceStack.addDependency(efsStack);

app.synth();