#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Props for the GravitonWorkloadStack
 */
interface GravitonWorkloadStackProps extends cdk.StackProps {
  /** The VPC to deploy resources into (optional, creates default if not provided) */
  vpc?: ec2.IVpc;
  /** The key pair name for EC2 instances (optional, creates one if not provided) */
  keyPairName?: string;
  /** Enable detailed monitoring for cost analysis */
  enableDetailedMonitoring?: boolean;
  /** Auto Scaling Group desired capacity */
  asgDesiredCapacity?: number;
  /** Auto Scaling Group minimum capacity */
  asgMinCapacity?: number;
  /** Auto Scaling Group maximum capacity */
  asgMaxCapacity?: number;
}

/**
 * CDK Stack for ARM-based Workloads with Graviton Processors
 * 
 * This stack demonstrates:
 * - Graviton3 (ARM64) EC2 instances with cost-optimized pricing
 * - x86 baseline instances for performance comparison
 * - Application Load Balancer for traffic distribution
 * - Auto Scaling Group for automatic capacity management
 * - CloudWatch monitoring and cost tracking
 * - Security groups with appropriate access controls
 */
class GravitonWorkloadStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly securityGroup: ec2.SecurityGroup;
  public readonly applicationLoadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly x86Instance: ec2.Instance;
  public readonly gravitonInstance: ec2.Instance;
  public readonly gravitonAutoScalingGroup: autoscaling.AutoScalingGroup;
  public readonly performanceDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: GravitonWorkloadStackProps = {}) {
    super(scope, id, props);

    // Use provided VPC or create a default one
    this.vpc = props.vpc || new ec2.Vpc(this, 'GravitonVpc', {
      maxAzs: 2,
      natGateways: 0, // Cost optimization: no NAT gateways for this demo
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Create security group for instances
    this.securityGroup = new ec2.SecurityGroup(this, 'GravitonSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Graviton workload demo',
      allowAllOutbound: true,
    });

    // Allow HTTP access from anywhere for web server testing
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP access for web server testing'
    );

    // Allow SSH access from anywhere for performance benchmarking
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for performance benchmarking'
    );

    // Create key pair for EC2 instances (if not provided)
    const keyPair = props.keyPairName ? 
      ec2.KeyPair.fromKeyPairName(this, 'ImportedKeyPair', props.keyPairName) :
      new ec2.KeyPair(this, 'GravitonKeyPair', {
        keyPairName: `graviton-demo-${this.node.addr}`,
      });

    // Create IAM role for EC2 instances with CloudWatch permissions
    const instanceRole = new iam.Role(this, 'GravitonInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Graviton demo instances',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // User data script for x86 instances
    const x86UserData = ec2.UserData.forLinux();
    x86UserData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y httpd stress-ng htop',
      'systemctl start httpd',
      'systemctl enable httpd',
      '',
      '# Install CloudWatch agent for x86',
      'wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm',
      'rpm -U amazon-cloudwatch-agent.rpm',
      '',
      '# Create simple web page showing architecture',
      'cat > /var/www/html/index.html << EOF',
      '<html>',
      '<body>',
      '<h1>x86 Architecture Server</h1>',
      '<p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>',
      '<p>Architecture: $(uname -m)</p>',
      '<p>Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>',
      '<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>',
      '</body>',
      '</html>',
      'EOF',
      '',
      '# Create benchmark script',
      'cat > /home/ec2-user/benchmark.sh << "SCRIPT"',
      '#!/bin/bash',
      'echo "Starting CPU benchmark on x86..."',
      'stress-ng --cpu 4 --timeout 60s --metrics-brief',
      'echo "Benchmark completed"',
      'SCRIPT',
      '',
      'chmod +x /home/ec2-user/benchmark.sh',
      'chown ec2-user:ec2-user /home/ec2-user/benchmark.sh'
    );

    // User data script for ARM instances
    const armUserData = ec2.UserData.forLinux();
    armUserData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y httpd stress-ng htop',
      'systemctl start httpd',
      'systemctl enable httpd',
      '',
      '# Install CloudWatch agent for ARM',
      'wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/arm64/latest/amazon-cloudwatch-agent.rpm',
      'rpm -U amazon-cloudwatch-agent.rpm',
      '',
      '# Create simple web page showing architecture',
      'cat > /var/www/html/index.html << EOF',
      '<html>',
      '<body>',
      '<h1>ARM64 Graviton Server</h1>',
      '<p>Instance: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>',
      '<p>Architecture: $(uname -m)</p>',
      '<p>Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>',
      '<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>',
      '</body>',
      '</html>',
      'EOF',
      '',
      '# Create benchmark script',
      'cat > /home/ec2-user/benchmark.sh << "SCRIPT"',
      '#!/bin/bash',
      'echo "Starting CPU benchmark on ARM64..."',
      'stress-ng --cpu 4 --timeout 60s --metrics-brief',
      'echo "Benchmark completed"',
      'SCRIPT',
      '',
      'chmod +x /home/ec2-user/benchmark.sh',
      'chown ec2-user:ec2-user /home/ec2-user/benchmark.sh'
    );

    // Launch x86 baseline instance for performance comparison
    this.x86Instance = new ec2.Instance(this, 'X86BaselineInstance', {
      vpc: this.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C6I, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      keyPair: keyPair,
      securityGroup: this.securityGroup,
      userData: x86UserData,
      role: instanceRole,
      detailedMonitoring: props.enableDetailedMonitoring ?? true,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    // Add tags for cost tracking and identification
    cdk.Tags.of(this.x86Instance).add('Name', 'graviton-demo-x86-baseline');
    cdk.Tags.of(this.x86Instance).add('Architecture', 'x86');
    cdk.Tags.of(this.x86Instance).add('Project', 'graviton-demo');

    // Launch ARM64 Graviton instance
    this.gravitonInstance = new ec2.Instance(this, 'GravitonInstance', {
      vpc: this.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C7G, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2({
        cpuType: ec2.AmazonLinuxCpuType.ARM_64,
      }),
      keyPair: keyPair,
      securityGroup: this.securityGroup,
      userData: armUserData,
      role: instanceRole,
      detailedMonitoring: props.enableDetailedMonitoring ?? true,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    // Add tags for cost tracking and identification
    cdk.Tags.of(this.gravitonInstance).add('Name', 'graviton-demo-arm-graviton');
    cdk.Tags.of(this.gravitonInstance).add('Architecture', 'arm64');
    cdk.Tags.of(this.gravitonInstance).add('Project', 'graviton-demo');

    // Create Application Load Balancer
    this.applicationLoadBalancer = new elbv2.ApplicationLoadBalancer(this, 'GravitonALB', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: this.securityGroup,
      loadBalancerName: `graviton-demo-alb-${this.node.addr}`,
    });

    // Create target group for mixed architecture instances
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'GravitonTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        path: '/',
        protocol: elbv2.Protocol.HTTP,
        port: '80',
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
        timeout: cdk.Duration.seconds(5),
        interval: cdk.Duration.seconds(30),
      },
      targetGroupName: `graviton-demo-tg-${this.node.addr}`,
    });

    // Register both instances to the target group
    targetGroup.addTarget(new elbv2.InstanceTarget(this.x86Instance));
    targetGroup.addTarget(new elbv2.InstanceTarget(this.gravitonInstance));

    // Create listener for the load balancer
    this.applicationLoadBalancer.addListener('GravitonListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.forward([targetGroup]),
    });

    // Create launch template for ARM instances in Auto Scaling Group
    const launchTemplate = new ec2.LaunchTemplate(this, 'GravitonLaunchTemplate', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.C7G, ec2.InstanceSize.LARGE),
      machineImage: ec2.MachineImage.latestAmazonLinux2({
        cpuType: ec2.AmazonLinuxCpuType.ARM_64,
      }),
      keyPair: keyPair,
      securityGroup: this.securityGroup,
      userData: armUserData,
      role: instanceRole,
      detailedMonitoring: props.enableDetailedMonitoring ?? true,
      launchTemplateName: `graviton-demo-lt-${this.node.addr}`,
    });

    // Create Auto Scaling Group with Graviton instances
    this.gravitonAutoScalingGroup = new autoscaling.AutoScalingGroup(this, 'GravitonASG', {
      vpc: this.vpc,
      launchTemplate: launchTemplate,
      minCapacity: props.asgMinCapacity ?? 1,
      maxCapacity: props.asgMaxCapacity ?? 3,
      desiredCapacity: props.asgDesiredCapacity ?? 2,
      healthCheck: autoscaling.HealthCheck.elb({
        grace: cdk.Duration.seconds(300),
      }),
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      autoScalingGroupName: `graviton-demo-asg-${this.node.addr}`,
    });

    // Add the Auto Scaling Group to the target group
    this.gravitonAutoScalingGroup.attachToApplicationTargetGroup(targetGroup);

    // Add tags to Auto Scaling Group instances
    cdk.Tags.of(this.gravitonAutoScalingGroup).add('Name', 'graviton-demo-asg-arm');
    cdk.Tags.of(this.gravitonAutoScalingGroup).add('Architecture', 'arm64');
    cdk.Tags.of(this.gravitonAutoScalingGroup).add('Project', 'graviton-demo');

    // Create CloudWatch Dashboard for performance comparison
    this.performanceDashboard = new cloudwatch.Dashboard(this, 'GravitonPerformanceDashboard', {
      dashboardName: `Graviton-Performance-Comparison-${this.node.addr}`,
    });

    // Add CPU utilization comparison widget
    this.performanceDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'CPU Utilization Comparison',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              InstanceId: this.x86Instance.instanceId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
            label: 'x86 Instance',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            dimensionsMap: {
              InstanceId: this.gravitonInstance.instanceId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
            label: 'ARM Instance',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add network performance comparison widget
    this.performanceDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Network Performance Comparison',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'NetworkIn',
            dimensionsMap: {
              InstanceId: this.x86Instance.instanceId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
            label: 'x86 Network In',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'NetworkIn',
            dimensionsMap: {
              InstanceId: this.gravitonInstance.instanceId,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
            label: 'ARM Network In',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Create cost monitoring alarm
    const costAlarm = new cloudwatch.Alarm(this, 'GravitonCostAlarm', {
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Billing',
        metricName: 'EstimatedCharges',
        dimensionsMap: {
          Currency: 'USD',
        },
        statistic: 'Maximum',
        period: cdk.Duration.hours(24),
      }),
      threshold: 50.0,
      evaluationPeriods: 1,
      alarmName: `graviton-demo-cost-alert-${this.node.addr}`,
      alarmDescription: 'Alert when estimated charges exceed threshold',
    });

    // Output important information
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the Graviton workload demo',
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: 'Security Group ID for the instances',
    });

    new cdk.CfnOutput(this, 'X86InstanceId', {
      value: this.x86Instance.instanceId,
      description: 'Instance ID of the x86 baseline instance',
    });

    new cdk.CfnOutput(this, 'X86InstancePublicIp', {
      value: this.x86Instance.instancePublicIp,
      description: 'Public IP address of the x86 baseline instance',
    });

    new cdk.CfnOutput(this, 'GravitonInstanceId', {
      value: this.gravitonInstance.instanceId,
      description: 'Instance ID of the Graviton ARM instance',
    });

    new cdk.CfnOutput(this, 'GravitonInstancePublicIp', {
      value: this.gravitonInstance.instancePublicIp,
      description: 'Public IP address of the Graviton ARM instance',
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.applicationLoadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'LoadBalancerUrl', {
      value: `http://${this.applicationLoadBalancer.loadBalancerDnsName}`,
      description: 'URL to access the load-balanced application',
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.gravitonAutoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group for Graviton instances',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.performanceDashboard.dashboardName}`,
      description: 'URL to the CloudWatch performance dashboard',
    });

    new cdk.CfnOutput(this, 'CostSavingsInfo', {
      value: 'c7g.large (ARM): $0.0691/hour vs c6i.large (x86): $0.0864/hour = 20% savings',
      description: 'Cost comparison between ARM and x86 instances',
    });

    new cdk.CfnOutput(this, 'KeyPairName', {
      value: keyPair.keyPairName,
      description: 'Name of the EC2 Key Pair for SSH access',
    });
  }
}

// Create the CDK app and instantiate the stack
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const stackName = app.node.tryGetContext('stackName') || process.env.CDK_STACK_NAME || 'GravitonWorkloadStack';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Create the stack with configuration
new GravitonWorkloadStack(app, stackName, {
  env: {
    account: account,
    region: region,
  },
  description: 'CDK Stack for ARM-based Workloads with Graviton Processors',
  // Optional configuration that can be overridden via CDK context
  enableDetailedMonitoring: app.node.tryGetContext('enableDetailedMonitoring') ?? true,
  asgDesiredCapacity: app.node.tryGetContext('asgDesiredCapacity') ?? 2,
  asgMinCapacity: app.node.tryGetContext('asgMinCapacity') ?? 1,
  asgMaxCapacity: app.node.tryGetContext('asgMaxCapacity') ?? 3,
  keyPairName: app.node.tryGetContext('keyPairName'), // Optional: use existing key pair
});

// Synthesize the CloudFormation template
app.synth();