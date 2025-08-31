#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Properties for the EC2 Launch Templates with Auto Scaling Stack
 */
interface Ec2LaunchTemplatesAutoScalingStackProps extends cdk.StackProps {
  /**
   * The instance type to use for EC2 instances
   * @default t2.micro
   */
  readonly instanceType?: ec2.InstanceType;

  /**
   * The minimum number of instances in the Auto Scaling group
   * @default 1
   */
  readonly minCapacity?: number;

  /**
   * The maximum number of instances in the Auto Scaling group
   * @default 4
   */
  readonly maxCapacity?: number;

  /**
   * The desired number of instances in the Auto Scaling group
   * @default 2
   */
  readonly desiredCapacity?: number;

  /**
   * The target CPU utilization percentage for scaling
   * @default 70
   */
  readonly targetCpuUtilization?: number;

  /**
   * VPC to deploy resources into. If not specified, uses default VPC
   */
  readonly vpc?: ec2.IVpc;
}

/**
 * CDK Stack for EC2 Launch Templates with Auto Scaling
 * 
 * This stack creates:
 * - Security Group with HTTP and SSH access
 * - Launch Template with user data for web server setup
 * - Auto Scaling Group with target tracking scaling policy
 * - CloudWatch metrics collection enabled
 */
export class Ec2LaunchTemplatesAutoScalingStack extends cdk.Stack {
  /**
   * The Auto Scaling Group created by this stack
   */
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;

  /**
   * The Launch Template created by this stack
   */
  public readonly launchTemplate: ec2.LaunchTemplate;

  /**
   * The Security Group created by this stack
   */
  public readonly securityGroup: ec2.SecurityGroup;

  constructor(scope: Construct, id: string, props?: Ec2LaunchTemplatesAutoScalingStackProps) {
    super(scope, id, props);

    // Use provided VPC or default VPC
    const vpc = props?.vpc ?? ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });

    // Get the latest Amazon Linux 2 AMI
    const amzn2Ami = ec2.MachineImage.latestAmazonLinux2({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
      edition: ec2.AmazonLinuxEdition.STANDARD,
      virtualization: ec2.AmazonLinuxVirt.HVM,
      storage: ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
    });

    // Create Security Group for EC2 instances
    this.securityGroup = new ec2.SecurityGroup(this, 'AutoScalingSecurityGroup', {
      vpc,
      description: 'Security group for Auto Scaling demo instances',
      allowAllOutbound: true,
    });

    // Add inbound rules for HTTP and SSH access
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP access from anywhere'
    );

    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access from anywhere'
    );

    // Create IAM role for EC2 instances with necessary permissions
    const instanceRole = new iam.Role(this, 'InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Auto Scaling group instances',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
      ],
    });

    // User data script to set up a simple web server
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      'echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html',
      'echo "<p>Instance launched at $(date)</p>" >> /var/www/html/index.html',
      'echo "<p>Auto Scaling Group: Demo</p>" >> /var/www/html/index.html'
    );

    // Create Launch Template with EC2 instance configuration
    this.launchTemplate = new ec2.LaunchTemplate(this, 'DemoLaunchTemplate', {
      launchTemplateName: `demo-launch-template-${this.stackName}`,
      machineImage: amzn2Ami,
      instanceType: props?.instanceType ?? ec2.InstanceType.of(
        ec2.InstanceClass.T2,
        ec2.InstanceSize.MICRO
      ),
      securityGroup: this.securityGroup,
      userData,
      role: instanceRole,
      detailedMonitoring: true, // Enable detailed CloudWatch monitoring
      requireImdsv2: true, // Require IMDSv2 for security best practices
    });

    // Apply tags to instances launched from this template
    cdk.Tags.of(this.launchTemplate).add('Name', 'AutoScaling-Instance');
    cdk.Tags.of(this.launchTemplate).add('Environment', 'Demo');
    cdk.Tags.of(this.launchTemplate).add('LaunchedBy', 'CDK');

    // Create Auto Scaling Group using the Launch Template
    this.autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'DemoAutoScalingGroup', {
      vpc,
      launchTemplate: this.launchTemplate,
      minCapacity: props?.minCapacity ?? 1,
      maxCapacity: props?.maxCapacity ?? 4,
      desiredCapacity: props?.desiredCapacity ?? 2,
      healthCheck: autoscaling.HealthCheck.ec2({
        grace: cdk.Duration.minutes(5),
      }),
      // Distribute instances across all available AZs for high availability
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      // Enable group metrics collection for CloudWatch
      groupMetrics: [autoscaling.GroupMetrics.all()],
    });

    // Apply tags to the Auto Scaling Group
    cdk.Tags.of(this.autoScalingGroup).add('Name', 'Demo-AutoScaling-Group');
    cdk.Tags.of(this.autoScalingGroup).add('Environment', 'Demo');

    // Create target tracking scaling policy for CPU utilization
    this.autoScalingGroup.scaleOnCpuUtilization('CpuTargetTracking', {
      targetUtilizationPercent: props?.targetCpuUtilization ?? 70,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
    });

    // Output important information for verification and testing
    new cdk.CfnOutput(this, 'LaunchTemplateId', {
      value: this.launchTemplate.launchTemplateId!,
      description: 'ID of the created Launch Template',
      exportName: `${this.stackName}-LaunchTemplateId`,
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group',
      exportName: `${this.stackName}-AutoScalingGroupName`,
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: 'ID of the Security Group',
      exportName: `${this.stackName}-SecurityGroupId`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'ID of the VPC used for deployment',
      exportName: `${this.stackName}-VpcId`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or use defaults
const stackName = app.node.tryGetContext('stackName') || 'Ec2LaunchTemplatesAutoScalingStack';
const instanceTypeString = app.node.tryGetContext('instanceType') || 't2.micro';
const minCapacity = app.node.tryGetContext('minCapacity') || 1;
const maxCapacity = app.node.tryGetContext('maxCapacity') || 4;
const desiredCapacity = app.node.tryGetContext('desiredCapacity') || 2;
const targetCpuUtilization = app.node.tryGetContext('targetCpuUtilization') || 70;

// Parse instance type from string
let instanceType: ec2.InstanceType;
try {
  const [instanceClass, instanceSize] = instanceTypeString.split('.');
  instanceType = ec2.InstanceType.of(
    instanceClass as ec2.InstanceClass,
    instanceSize as ec2.InstanceSize
  );
} catch (error) {
  console.warn(`Invalid instance type '${instanceTypeString}', using t2.micro as default`);
  instanceType = ec2.InstanceType.of(ec2.InstanceClass.T2, ec2.InstanceSize.MICRO);
}

// Create the stack with configuration
new Ec2LaunchTemplatesAutoScalingStack(app, stackName, {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'EC2 Launch Templates with Auto Scaling - CDK TypeScript Implementation',
  instanceType,
  minCapacity,
  maxCapacity,
  desiredCapacity,
  targetCpuUtilization,
  tags: {
    Project: 'AWS-Recipes',
    Recipe: 'ec2-launch-templates-auto-scaling',
    DeployedWith: 'CDK-TypeScript',
  },
});

// Synthesize the CloudFormation template
app.synth();