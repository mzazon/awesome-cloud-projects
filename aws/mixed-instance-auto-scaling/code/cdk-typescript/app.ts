#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

/**
 * Properties for the MixedInstancesAutoScalingStack
 */
interface MixedInstancesAutoScalingStackProps extends cdk.StackProps {
  /**
   * Minimum number of instances in the Auto Scaling group
   * @default 2
   */
  readonly minSize?: number;

  /**
   * Maximum number of instances in the Auto Scaling group
   * @default 10
   */
  readonly maxSize?: number;

  /**
   * Desired number of instances in the Auto Scaling group
   * @default 4
   */
  readonly desiredCapacity?: number;

  /**
   * Percentage of On-Demand instances above the base capacity
   * @default 20
   */
  readonly onDemandPercentageAboveBaseCapacity?: number;

  /**
   * Base number of On-Demand instances
   * @default 1
   */
  readonly onDemandBaseCapacity?: number;

  /**
   * Target CPU utilization for scaling policies
   * @default 70
   */
  readonly targetCpuUtilization?: number;

  /**
   * Environment name for tagging
   * @default 'Demo'
   */
  readonly environmentName?: string;
}

/**
 * CDK Stack for Mixed Instance Types Auto Scaling Group with Spot Instances
 * 
 * This stack creates a cost-optimized Auto Scaling solution that combines:
 * - Multiple instance types for diversification
 * - Spot Instances for cost savings (up to 90%)
 * - On-Demand instances for reliability
 * - Application Load Balancer for distribution
 * - CloudWatch monitoring and auto scaling
 * - SNS notifications for scaling events
 */
export class MixedInstancesAutoScalingStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly notificationTopic: sns.Topic;

  constructor(scope: Construct, id: string, props?: MixedInstancesAutoScalingStackProps) {
    super(scope, id, props);

    // Extract properties with defaults
    const minSize = props?.minSize ?? 2;
    const maxSize = props?.maxSize ?? 10;
    const desiredCapacity = props?.desiredCapacity ?? 4;
    const onDemandPercentageAboveBaseCapacity = props?.onDemandPercentageAboveBaseCapacity ?? 20;
    const onDemandBaseCapacity = props?.onDemandBaseCapacity ?? 1;
    const targetCpuUtilization = props?.targetCpuUtilization ?? 70;
    const environmentName = props?.environmentName ?? 'Demo';

    // Use default VPC or create a new one
    this.vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true,
    });

    // Create security group for instances with appropriate rules
    const securityGroup = new ec2.SecurityGroup(this, 'MixedInstancesSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for mixed instances Auto Scaling group',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from anywhere'
    );

    // Allow HTTPS traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from anywhere'
    );

    // Allow SSH access for debugging (consider restricting this in production)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for debugging'
    );

    // Create IAM role for EC2 instances with necessary permissions
    const instanceRole = new iam.Role(this, 'EC2InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Auto Scaling group instances',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Create user data script for instance initialization
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      // Update system and install Apache
      'yum update -y',
      'yum install -y httpd',
      
      // Get instance metadata for display
      'INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)',
      'INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)',
      'AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)',
      'SPOT_TERMINATION=$(curl -s http://169.254.169.254/latest/meta-data/spot/instance-action 2>/dev/null || echo "On-Demand")',
      
      // Create informative web page
      'cat > /var/www/html/index.html << \'EOF\'',
      '<!DOCTYPE html>',
      '<html>',
      '<head>',
      '    <title>Mixed Instance Auto Scaling Demo</title>',
      '    <style>',
      '        body { font-family: Arial, sans-serif; margin: 40px; }',
      '        .info { background: #f0f0f0; padding: 20px; border-radius: 5px; }',
      '        .spot { color: green; }',
      '        .ondemand { color: blue; }',
      '    </style>',
      '</head>',
      '<body>',
      '    <h1>Mixed Instance Auto Scaling Demo</h1>',
      '    <div class="info">',
      '        <h2>Instance Information</h2>',
      '        <p><strong>Instance ID:</strong> \'$INSTANCE_ID\'</p>',
      '        <p><strong>Instance Type:</strong> \'$INSTANCE_TYPE\'</p>',
      '        <p><strong>Availability Zone:</strong> \'$AZ\'</p>',
      '        <p><strong>Purchase Type:</strong> \'$SPOT_TERMINATION\'</p>',
      '        <p><strong>Timestamp:</strong> \'$(date)\'</p>',
      '    </div>',
      '    <h2>Auto Scaling Group Benefits</h2>',
      '    <ul>',
      '        <li>Cost optimization with Spot Instances</li>',
      '        <li>High availability across multiple AZs</li>',
      '        <li>Automatic scaling based on demand</li>',
      '        <li>Instance type diversification</li>',
      '    </ul>',
      '</body>',
      '</html>',
      'EOF',
      
      // Start and enable Apache
      'systemctl start httpd',
      'systemctl enable httpd',
      
      // Install and configure CloudWatch agent
      'yum install -y amazon-cloudwatch-agent',
      
      // Create CloudWatch agent configuration
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << \'EOF\'',
      '{',
      '    "metrics": {',
      '        "namespace": "AutoScaling/MixedInstances",',
      '        "metrics_collected": {',
      '            "cpu": {',
      '                "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],',
      '                "metrics_collection_interval": 60',
      '            },',
      '            "disk": {',
      '                "measurement": ["used_percent"],',
      '                "metrics_collection_interval": 60,',
      '                "resources": ["*"]',
      '            },',
      '            "mem": {',
      '                "measurement": ["mem_used_percent"],',
      '                "metrics_collection_interval": 60',
      '            }',
      '        }',
      '    }',
      '}',
      'EOF',
      
      // Start CloudWatch agent
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json'
    );

    // Get the latest Amazon Linux 2 AMI
    const amazonLinuxImage = ec2.MachineImage.latestAmazonLinux({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
      cpuType: ec2.AmazonLinuxCpuType.X86_64,
    });

    // Create launch template with base configuration
    const launchTemplate = new ec2.LaunchTemplate(this, 'MixedInstancesLaunchTemplate', {
      machineImage: amazonLinuxImage,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
      securityGroup: securityGroup,
      role: instanceRole,
      userData: userData,
      requireImdsv2: true, // Enable IMDSv2 for enhanced security
    });

    // Create Auto Scaling group with mixed instance policy
    this.autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'MixedInstancesASG', {
      vpc: this.vpc,
      launchTemplate: launchTemplate,
      minCapacity: minSize,
      maxCapacity: maxSize,
      desiredCapacity: desiredCapacity,
      healthCheck: autoscaling.HealthCheck.elb({
        grace: cdk.Duration.minutes(5),
      }),
      mixedInstancesPolicy: {
        instancesDistribution: {
          onDemandAllocationStrategy: autoscaling.OnDemandAllocationStrategy.PRIORITIZED,
          onDemandBaseCapacity: onDemandBaseCapacity,
          onDemandPercentageAboveBaseCapacity: onDemandPercentageAboveBaseCapacity,
          spotAllocationStrategy: autoscaling.SpotAllocationStrategy.DIVERSIFIED,
          spotInstancePools: 4,
          // No spotMaxPrice specified to use current market price
        },
        launchTemplateOverrides: [
          // General purpose instances
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE), weightedCapacity: 1 },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.XLARGE), weightedCapacity: 2 },
          // Compute optimized instances
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.LARGE), weightedCapacity: 1 },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.C5, ec2.InstanceSize.XLARGE), weightedCapacity: 2 },
          // Memory optimized instances
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.R5, ec2.InstanceSize.LARGE), weightedCapacity: 1 },
          { instanceType: ec2.InstanceType.of(ec2.InstanceClass.R5, ec2.InstanceSize.XLARGE), weightedCapacity: 2 },
        ],
      },
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC, // Use public subnets for web servers
      },
      capacityRebalance: true, // Enable capacity rebalancing for Spot instance management
    });

    // Add target tracking scaling policies
    this.autoScalingGroup.scaleOnCpuUtilization('CpuScaling', {
      targetUtilizationPercent: targetCpuUtilization,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
    });

    // Add network utilization scaling policy
    this.autoScalingGroup.scaleOnIncomingBytes('NetworkScaling', {
      targetBytesPerSecond: 1000000, // 1MB/s
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
    });

    // Create Application Load Balancer
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'MixedInstancesALB', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: securityGroup,
    });

    // Create target group with health checks
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'MixedInstancesTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      healthCheck: {
        enabled: true,
        path: '/',
        protocol: elbv2.Protocol.HTTP,
        port: '80',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      targets: [this.autoScalingGroup],
    });

    // Create listener for the load balancer
    this.loadBalancer.addListener('MixedInstancesListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create SNS topic for Auto Scaling notifications
    this.notificationTopic = new sns.Topic(this, 'AutoScalingNotifications', {
      displayName: 'Auto Scaling Group Notifications',
      topicName: 'mixed-instances-asg-notifications',
    });

    // Configure Auto Scaling group to send notifications
    this.autoScalingGroup.addNotificationTopic(this.notificationTopic);

    // Add tags to all resources
    const commonTags = {
      Environment: environmentName,
      Project: 'MixedInstancesAutoScaling',
      CreatedBy: 'CDK',
    };

    Object.entries(commonTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Add specific tags to Auto Scaling group
    cdk.Tags.of(this.autoScalingGroup).add('Name', 'MixedInstancesASG-Instance');

    // Outputs for reference and testing
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: 'MixedInstancesALB-DNS',
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling group',
      exportName: 'MixedInstancesASG-Name',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for notifications',
      exportName: 'MixedInstancesASG-SNS-Topic',
    });

    new cdk.CfnOutput(this, 'WebsiteURL', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}`,
      description: 'URL of the demo web application',
      exportName: 'MixedInstancesASG-WebsiteURL',
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: securityGroup.securityGroupId,
      description: 'ID of the security group',
      exportName: 'MixedInstancesASG-SecurityGroup',
    });
  }
}

/**
 * CDK Application for Mixed Instance Types Auto Scaling Group
 */
const app = new cdk.App();

// Get environment from context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || app.node.tryGetContext('account'),
  region: process.env.CDK_DEFAULT_REGION || app.node.tryGetContext('region') || 'us-east-1',
};

// Create the stack with customizable properties
new MixedInstancesAutoScalingStack(app, 'MixedInstancesAutoScalingStack', {
  env,
  description: 'Mixed Instance Types Auto Scaling Group with Spot Instances for cost optimization',
  
  // Customizable parameters - can be overridden via context
  minSize: app.node.tryGetContext('minSize') || 2,
  maxSize: app.node.tryGetContext('maxSize') || 10,
  desiredCapacity: app.node.tryGetContext('desiredCapacity') || 4,
  onDemandPercentageAboveBaseCapacity: app.node.tryGetContext('onDemandPercentageAboveBaseCapacity') || 20,
  onDemandBaseCapacity: app.node.tryGetContext('onDemandBaseCapacity') || 1,
  targetCpuUtilization: app.node.tryGetContext('targetCpuUtilization') || 70,
  environmentName: app.node.tryGetContext('environmentName') || 'Demo',
  
  // Stack-level tags
  tags: {
    Project: 'MixedInstancesAutoScaling',
    Purpose: 'Cost optimization and high availability demonstration',
    Repository: 'aws-recipes',
  },
});

// Synthesize the app
app.synth();