#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for Simple Resource Monitoring with CloudWatch and SNS
 * 
 * This stack creates:
 * - An EC2 instance for monitoring
 * - An SNS topic for notifications
 * - A CloudWatch alarm for CPU utilization
 * - Email subscription to the SNS topic
 */
export class SimpleResourceMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Get parameters from context or environment variables
    const userEmail = this.node.tryGetContext('userEmail') || process.env.USER_EMAIL;
    if (!userEmail) {
      throw new Error('User email must be provided via context (--context userEmail=your@email.com) or USER_EMAIL environment variable');
    }

    // Create VPC (using default VPC for simplicity, or create a minimal one)
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // Create security group for EC2 instance
    const securityGroup = new ec2.SecurityGroup(this, 'MonitoringDemoSecurityGroup', {
      vpc,
      description: 'Security group for monitoring demo EC2 instance',
      allowAllOutbound: true
    });

    // Allow SSH access from anywhere (for testing purposes only)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );

    // Create IAM role for EC2 instance with SSM permissions
    const ec2Role = new iam.Role(this, 'EC2MonitoringRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 monitoring demo instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
      ]
    });

    // Create instance profile
    const instanceProfile = new iam.CfnInstanceProfile(this, 'EC2InstanceProfile', {
      roles: [ec2Role.roleName],
      instanceProfileName: `${id}-ec2-instance-profile`
    });

    // Get the latest Amazon Linux 2023 AMI
    const amzn2023Ami = ec2.MachineImage.latestAmazonLinux2023({
      edition: ec2.AmazonLinuxEdition.STANDARD,
      virtualization: ec2.AmazonLinuxVirt.HVM,
      storage: ec2.AmazonLinuxStorage.GENERAL_PURPOSE
    });

    // Create EC2 instance for monitoring
    const monitoringInstance = new ec2.Instance(this, 'MonitoringDemoInstance', {
      vpc,
      securityGroup,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T2, ec2.InstanceSize.MICRO),
      machineImage: amzn2023Ami,
      role: ec2Role,
      keyName: this.node.tryGetContext('keyPairName'), // Optional: specify key pair if needed
      userData: ec2.UserData.forLinux(),
      userDataCausesReplacement: false
    });

    // Add user data script for stress testing tools
    monitoringInstance.addUserData(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y stress-ng htop',
      '# Create a simple script for CPU stress testing',
      'cat > /home/ec2-user/stress-test.sh << EOF',
      '#!/bin/bash',
      'echo "Starting CPU stress test..."',
      'stress-ng --cpu 4 --timeout 300s',
      'echo "CPU stress test completed"',
      'EOF',
      'chmod +x /home/ec2-user/stress-test.sh',
      'chown ec2-user:ec2-user /home/ec2-user/stress-test.sh'
    );

    // Create SNS topic for alerts
    const cpuAlertsTopic = new sns.Topic(this, 'CpuAlertsTopic', {
      displayName: 'CPU Utilization Alerts',
      description: 'SNS topic for CPU utilization monitoring alerts'
    });

    // Subscribe email to SNS topic
    cpuAlertsTopic.addSubscription(
      new subscriptions.EmailSubscription(userEmail)
    );

    // Create CloudWatch alarm for high CPU utilization
    const highCpuAlarm = new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `${id}-high-cpu-alarm`,
      alarmDescription: 'Alert when CPU exceeds 70% for 2 consecutive periods',
      metric: monitoringInstance.metricCPUUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Stats.AVERAGE
      }),
      threshold: 70,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });

    // Add SNS action to the alarm
    highCpuAlarm.addAlarmAction(
      new actions.SnsAction(cpuAlertsTopic)
    );

    // Add OK action to notify when alarm returns to normal
    highCpuAlarm.addOkAction(
      new actions.SnsAction(cpuAlertsTopic)
    );

    // Create additional alarms for comprehensive monitoring
    const statusCheckAlarm = new cloudwatch.Alarm(this, 'StatusCheckAlarm', {
      alarmName: `${id}-status-check-alarm`,
      alarmDescription: 'Alert when instance status check fails',
      metric: monitoringInstance.metricStatusCheckFailed({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Stats.MAXIMUM
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING
    });

    statusCheckAlarm.addAlarmAction(new actions.SnsAction(cpuAlertsTopic));

    // Outputs for verification and testing
    new cdk.CfnOutput(this, 'InstanceId', {
      value: monitoringInstance.instanceId,
      description: 'EC2 Instance ID for monitoring'
    });

    new cdk.CfnOutput(this, 'InstancePublicIp', {
      value: monitoringInstance.instancePublicIp,
      description: 'Public IP address of the monitoring instance'
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: cpuAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for alerts'
    });

    new cdk.CfnOutput(this, 'HighCpuAlarmArn', {
      value: highCpuAlarm.alarmArn,
      description: 'ARN of the high CPU utilization alarm'
    });

    new cdk.CfnOutput(this, 'StatusCheckAlarmArn', {
      value: statusCheckAlarm.alarmArn,
      description: 'ARN of the status check alarm'
    });

    new cdk.CfnOutput(this, 'UserEmail', {
      value: userEmail,
      description: 'Email address subscribed to alerts'
    });

    new cdk.CfnOutput(this, 'StressTestCommand', {
      value: `aws ssm send-command --document-name "AWS-RunShellScript" --instance-ids ${monitoringInstance.instanceId} --parameters 'commands=["/home/ec2-user/stress-test.sh"]'`,
      description: 'Command to trigger CPU load for testing the alarm'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'SimpleResourceMonitoring');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Recipe', 'simple-resource-monitoring-cloudwatch-sns');
  }
}

// CDK App
const app = new cdk.App();

// Create the stack
new SimpleResourceMonitoringStack(app, 'SimpleResourceMonitoringStack', {
  description: 'Simple Resource Monitoring with CloudWatch and SNS - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  }
});

// Add stack-level tags
cdk.Tags.of(app).add('CreatedBy', 'CDK');
cdk.Tags.of(app).add('Recipe', 'simple-resource-monitoring-cloudwatch-sns');