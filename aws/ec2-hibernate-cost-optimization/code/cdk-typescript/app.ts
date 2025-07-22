#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Interface defining the properties for the EC2 Hibernation Cost Optimization Stack
 */
export interface EC2HibernationStackProps extends cdk.StackProps {
  /**
   * The instance type for the hibernation-enabled EC2 instance
   * @default m5.large
   */
  readonly instanceType?: ec2.InstanceType;

  /**
   * The key pair name for EC2 access
   * If not provided, a new key pair will be created
   */
  readonly keyPairName?: string;

  /**
   * Email address for SNS notifications
   * @default undefined (no email subscription)
   */
  readonly notificationEmail?: string;

  /**
   * CPU utilization threshold for hibernation alerts
   * @default 10
   */
  readonly cpuThreshold?: number;

  /**
   * EBS volume size in GB
   * @default 30
   */
  readonly volumeSize?: number;

  /**
   * Whether to enable detailed monitoring
   * @default false
   */
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * CDK Stack for EC2 Hibernation Cost Optimization
 * 
 * This stack creates:
 * - An EC2 instance with hibernation enabled
 * - Encrypted EBS root volume
 * - CloudWatch alarms for cost monitoring
 * - SNS topic for notifications
 * - IAM roles with appropriate permissions
 */
export class EC2HibernationStack extends cdk.Stack {
  public readonly instance: ec2.Instance;
  public readonly vpc: ec2.Vpc;
  public readonly snsTopic: sns.Topic;
  public readonly cpuAlarm: cloudwatch.Alarm;
  public readonly keyPair: ec2.KeyPair;

  constructor(scope: Construct, id: string, props: EC2HibernationStackProps = {}) {
    super(scope, id, props);

    // Stack parameters with defaults
    const instanceType = props.instanceType || ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE);
    const cpuThreshold = props.cpuThreshold || 10;
    const volumeSize = props.volumeSize || 30;
    const enableDetailedMonitoring = props.enableDetailedMonitoring || false;

    // Create VPC for the instance
    this.vpc = new ec2.Vpc(this, 'HibernationVPC', {
      maxAzs: 2,
      cidr: '10.0.0.0/16',
      natGateways: 0, // No NAT gateways for cost optimization
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Add VPC flow logs for monitoring
    new ec2.FlowLog(this, 'VPCFlowLog', {
      resourceType: ec2.FlowLogResourceType.fromVpc(this.vpc),
      destination: ec2.FlowLogDestination.toCloudWatchLogs(
        new logs.LogGroup(this, 'VPCFlowLogGroup', {
          logGroupName: `/aws/vpc/flowlogs/${this.stackName}`,
          retention: logs.RetentionDays.ONE_WEEK,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        })
      ),
    });

    // Create security group for the instance
    const securityGroup = new ec2.SecurityGroup(this, 'HibernationSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for hibernation demo instance',
      allowAllOutbound: true,
    });

    // Allow SSH access from anywhere (for demo purposes)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    // Allow ICMP for basic connectivity testing
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.allIcmp(),
      'Allow ICMP'
    );

    // Create key pair if not provided
    if (!props.keyPairName) {
      this.keyPair = new ec2.KeyPair(this, 'HibernationKeyPair', {
        keyPairName: `hibernate-demo-key-${this.stackName.toLowerCase()}`,
        type: ec2.KeyPairType.RSA,
        format: ec2.KeyPairFormat.PEM,
      });
    }

    // Get the latest Amazon Linux 2 AMI that supports hibernation
    const amzn2Ami = ec2.MachineImage.latestAmazonLinux2({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
      edition: ec2.AmazonLinuxEdition.STANDARD,
      virtualization: ec2.AmazonLinuxVirt.HVM,
      storage: ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
    });

    // Create IAM role for the instance
    const instanceRole = new iam.Role(this, 'HibernationInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for hibernation demo instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add permissions for CloudWatch metrics
    instanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cloudwatch:PutMetricData',
        'cloudwatch:GetMetricStatistics',
        'cloudwatch:ListMetrics',
      ],
      resources: ['*'],
    }));

    // Add permissions for EC2 hibernation operations
    instanceRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ec2:DescribeInstances',
        'ec2:DescribeInstanceAttribute',
        'ec2:ModifyInstanceAttribute',
        'ec2:StopInstances',
        'ec2:StartInstances',
      ],
      resources: ['*'],
      conditions: {
        StringEquals: {
          'ec2:ResourceTag/Purpose': 'HibernationDemo',
        },
      },
    }));

    // User data script for instance configuration
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y htop stress-ng',
      
      // Install CloudWatch agent
      'yum install -y amazon-cloudwatch-agent',
      
      // Create a simple hibernation test script
      'cat > /home/ec2-user/hibernation-test.sh << EOF',
      '#!/bin/bash',
      'echo "Creating hibernation test environment..."',
      'echo "Current time: $(date)" > /home/ec2-user/hibernation-state.txt',
      'echo "Process ID: $$" >> /home/ec2-user/hibernation-state.txt',
      'echo "Uptime: $(uptime)" >> /home/ec2-user/hibernation-state.txt',
      'echo "Memory usage:" >> /home/ec2-user/hibernation-state.txt',
      'free -h >> /home/ec2-user/hibernation-state.txt',
      'echo "Test file created for hibernation state verification"',
      'EOF',
      
      'chmod +x /home/ec2-user/hibernation-test.sh',
      'chown ec2-user:ec2-user /home/ec2-user/hibernation-test.sh',
      
      // Run the hibernation test script
      'su - ec2-user -c "/home/ec2-user/hibernation-test.sh"',
      
      // Send CloudWatch custom metric
      'aws cloudwatch put-metric-data --region ' + this.region + ' --namespace "Custom/Hibernation" --metric-data MetricName=InstanceInitialized,Value=1,Unit=Count'
    );

    // Create the EC2 instance with hibernation enabled
    this.instance = new ec2.Instance(this, 'HibernationInstance', {
      vpc: this.vpc,
      instanceType: instanceType,
      machineImage: amzn2Ami,
      securityGroup: securityGroup,
      keyName: props.keyPairName || this.keyPair.keyPairName,
      role: instanceRole,
      userData: userData,
      detailedMonitoring: enableDetailedMonitoring,
      
      // Enable hibernation
      hibernationConfiguration: {
        enabled: true,
      },
      
      // Configure encrypted EBS root volume
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(volumeSize, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
            deleteOnTermination: true,
          }),
        },
      ],
      
      // Add tags for identification and automation
      resourceSignalTimeout: cdk.Duration.minutes(10),
    });

    // Add tags to the instance
    cdk.Tags.of(this.instance).add('Name', `hibernate-demo-instance-${this.stackName}`);
    cdk.Tags.of(this.instance).add('Purpose', 'HibernationDemo');
    cdk.Tags.of(this.instance).add('Environment', 'Demo');
    cdk.Tags.of(this.instance).add('CostCenter', 'Development');

    // Create SNS topic for notifications
    this.snsTopic = new sns.Topic(this, 'HibernationNotifications', {
      displayName: 'EC2 Hibernation Notifications',
      topicName: `hibernate-notifications-${this.stackName}`,
    });

    // Subscribe email to SNS topic if provided
    if (props.notificationEmail) {
      this.snsTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create CloudWatch alarm for low CPU utilization
    this.cpuAlarm = new cloudwatch.Alarm(this, 'LowCPUAlarm', {
      alarmName: `LowCPU-${this.stackName}`,
      alarmDescription: 'Alarm when CPU utilization is consistently low - hibernation candidate',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        dimensionsMap: {
          InstanceId: this.instance.instanceId,
        },
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: cpuThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 6, // 30 minutes of low CPU
      datapointsToAlarm: 5,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the alarm
    this.cpuAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.snsTopic)
    );

    // Create CloudWatch alarm for instance state changes
    const instanceStateAlarm = new cloudwatch.Alarm(this, 'InstanceStateAlarm', {
      alarmName: `InstanceState-${this.stackName}`,
      alarmDescription: 'Monitor instance state changes including hibernation',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'StatusCheckFailed',
        dimensionsMap: {
          InstanceId: this.instance.instanceId,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add SNS action to the state alarm
    instanceStateAlarm.addAlarmAction(
      new cloudwatch.SnsAction(this.snsTopic)
    );

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'HibernationDashboard', {
      dashboardName: `EC2-Hibernation-${this.stackName}`,
    });

    // Add widgets to the dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'CPU Utilization',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              InstanceId: this.instance.instanceId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      }),
      
      new cloudwatch.GraphWidget({
        title: 'Network I/O',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'NetworkIn',
            dimensionsMap: {
              InstanceId: this.instance.instanceId,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'NetworkOut',
            dimensionsMap: {
              InstanceId: this.instance.instanceId,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      }),
      
      new cloudwatch.SingleValueWidget({
        title: 'Instance Status',
        metrics: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'StatusCheckFailed',
            dimensionsMap: {
              InstanceId: this.instance.instanceId,
            },
            statistic: 'Maximum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 6,
        height: 6,
      }),
      
      new cloudwatch.SingleValueWidget({
        title: 'Custom Hibernation Metric',
        metrics: [
          new cloudwatch.Metric({
            namespace: 'Custom/Hibernation',
            metricName: 'InstanceInitialized',
            statistic: 'Sum',
            period: cdk.Duration.hours(1),
          }),
        ],
        width: 6,
        height: 6,
      })
    );

    // Output important resource information
    new cdk.CfnOutput(this, 'InstanceId', {
      value: this.instance.instanceId,
      description: 'EC2 Instance ID with hibernation enabled',
    });

    new cdk.CfnOutput(this, 'InstancePublicIP', {
      value: this.instance.instancePublicIp,
      description: 'Public IP address of the hibernation instance',
    });

    new cdk.CfnOutput(this, 'KeyPairName', {
      value: props.keyPairName || this.keyPair.keyPairName,
      description: 'Key pair name for SSH access',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'SNS topic ARN for hibernation notifications',
    });

    new cdk.CfnOutput(this, 'CPUAlarmName', {
      value: this.cpuAlarm.alarmName,
      description: 'CloudWatch alarm name for low CPU utilization',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'SSHCommand', {
      value: `ssh -i ${props.keyPairName || this.keyPair.keyPairName}.pem ec2-user@${this.instance.instancePublicIp}`,
      description: 'SSH command to connect to the instance',
    });

    new cdk.CfnOutput(this, 'HibernateCommand', {
      value: `aws ec2 stop-instances --instance-ids ${this.instance.instanceId} --hibernate --region ${this.region}`,
      description: 'AWS CLI command to hibernate the instance',
    });

    new cdk.CfnOutput(this, 'ResumeCommand', {
      value: `aws ec2 start-instances --instance-ids ${this.instance.instanceId} --region ${this.region}`,
      description: 'AWS CLI command to resume the hibernated instance',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Get context parameters
const stackName = app.node.tryGetContext('stackName') || 'EC2HibernationDemo';
const notificationEmail = app.node.tryGetContext('notificationEmail');
const keyPairName = app.node.tryGetContext('keyPairName');
const cpuThreshold = app.node.tryGetContext('cpuThreshold') || 10;
const enableDetailedMonitoring = app.node.tryGetContext('enableDetailedMonitoring') === 'true';

// Create the stack
new EC2HibernationStack(app, stackName, {
  description: 'EC2 Hibernation Cost Optimization Demo Stack',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  notificationEmail,
  keyPairName,
  cpuThreshold: parseInt(cpuThreshold),
  enableDetailedMonitoring,
  
  // Add stack tags
  tags: {
    Project: 'EC2-Hibernation-Demo',
    Environment: 'Demo',
    CostCenter: 'Development',
    Owner: 'DevOps-Team',
  },
});

// Synthesize the app
app.synth();