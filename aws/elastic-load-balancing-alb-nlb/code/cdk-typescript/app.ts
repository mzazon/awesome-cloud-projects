#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Interface for stack props to customize deployment
 */
interface ElasticLoadBalancingStackProps extends cdk.StackProps {
  readonly vpcCidr?: string;
  readonly instanceType?: ec2.InstanceType;
  readonly desiredCapacity?: number;
  readonly projectName?: string;
}

/**
 * CDK Stack for Elastic Load Balancing with Application and Network Load Balancers
 * 
 * This stack creates:
 * - VPC with public and private subnets across multiple AZs
 * - Application Load Balancer (ALB) for HTTP/HTTPS traffic
 * - Network Load Balancer (NLB) for TCP/UDP traffic
 * - Auto Scaling Group with EC2 instances
 * - Target Groups for both load balancers
 * - Security Groups with proper network segmentation
 * - IAM roles and policies for EC2 instances
 */
class ElasticLoadBalancingStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly albSecurityGroup: ec2.SecurityGroup;
  public readonly nlbSecurityGroup: ec2.SecurityGroup;
  public readonly ec2SecurityGroup: ec2.SecurityGroup;
  public readonly applicationLoadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly networkLoadBalancer: elbv2.NetworkLoadBalancer;
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;
  public readonly albTargetGroup: elbv2.ApplicationTargetGroup;
  public readonly nlbTargetGroup: elbv2.NetworkTargetGroup;

  constructor(scope: Construct, id: string, props: ElasticLoadBalancingStackProps = {}) {
    super(scope, id, props);

    // Extract configuration from props with defaults
    const vpcCidr = props.vpcCidr || '10.0.0.0/16';
    const instanceType = props.instanceType || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO);
    const desiredCapacity = props.desiredCapacity || 2;
    const projectName = props.projectName || 'elb-demo';

    // Create VPC with public and private subnets
    this.vpc = new ec2.Vpc(this, 'ElbVpc', {
      cidr: vpcCidr,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      maxAzs: 3, // Use up to 3 AZs for high availability
      natGateways: 1, // Cost-optimized: use 1 NAT Gateway
      subnetConfiguration: [
        {
          name: 'public-subnet',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'private-subnet',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
    });

    // Create security group for Application Load Balancer
    this.albSecurityGroup = new ec2.SecurityGroup(this, 'AlbSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP and HTTPS traffic to ALB from internet
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from internet'
    );
    this.albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from internet'
    );

    // Create security group for Network Load Balancer
    this.nlbSecurityGroup = new ec2.SecurityGroup(this, 'NlbSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Network Load Balancer',
      allowAllOutbound: true,
    });

    // Allow TCP traffic to NLB from internet
    this.nlbSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow TCP traffic from internet'
    );

    // Create security group for EC2 instances
    this.ec2SecurityGroup = new ec2.SecurityGroup(this, 'Ec2SecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for EC2 instances behind load balancers',
      allowAllOutbound: true,
    });

    // Allow traffic from ALB to EC2 instances
    this.ec2SecurityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.albSecurityGroup.securityGroupId),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from ALB'
    );

    // Allow traffic from NLB to EC2 instances
    this.ec2SecurityGroup.addIngressRule(
      ec2.Peer.securityGroupId(this.nlbSecurityGroup.securityGroupId),
      ec2.Port.tcp(80),
      'Allow TCP traffic from NLB'
    );

    // Allow SSH access for management (optional - consider removing in production)
    this.ec2SecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for management'
    );

    // Create IAM role for EC2 instances
    const ec2Role = new iam.Role(this, 'Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instances in load balancer demo',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Create user data script for web server setup
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      'yum update -y',
      'yum install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      'echo "<h1>Hello from $(hostname -f)</h1>" > /var/www/html/index.html',
      'echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html',
      'echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html',
      'echo "<p>Load Balancer Demo</p>" >> /var/www/html/index.html'
    );

    // Create launch template for Auto Scaling Group
    const launchTemplate = new ec2.LaunchTemplate(this, 'LaunchTemplate', {
      instanceType: instanceType,
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      userData: userData,
      securityGroup: this.ec2SecurityGroup,
      role: ec2Role,
      requireImdsv2: true, // Security best practice
    });

    // Create Auto Scaling Group
    this.autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'AutoScalingGroup', {
      vpc: this.vpc,
      launchTemplate: launchTemplate,
      minCapacity: 1,
      maxCapacity: 6,
      desiredCapacity: desiredCapacity,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
      },
      healthCheck: autoscaling.HealthCheck.elb({
        grace: cdk.Duration.minutes(5),
      }),
      updatePolicy: autoscaling.UpdatePolicy.rollingUpdate({
        maxBatchSize: 1,
        minInstancesInService: 1,
        pauseTime: cdk.Duration.minutes(5),
      }),
    });

    // Create Application Load Balancer
    this.applicationLoadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: this.albSecurityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      loadBalancerName: `${projectName}-alb`,
    });

    // Create Network Load Balancer
    this.networkLoadBalancer = new elbv2.NetworkLoadBalancer(this, 'NetworkLoadBalancer', {
      vpc: this.vpc,
      internetFacing: true,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      loadBalancerName: `${projectName}-nlb`,
    });

    // Create target group for Application Load Balancer
    this.albTargetGroup = new elbv2.ApplicationTargetGroup(this, 'AlbTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      targetGroupName: `${projectName}-alb-tg`,
      healthCheck: {
        enabled: true,
        healthyHttpCodes: '200',
        interval: cdk.Duration.seconds(30),
        path: '/',
        port: '80',
        protocol: elbv2.Protocol.HTTP,
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 5,
      },
      // Configure target group attributes for optimization
      deregistrationDelay: cdk.Duration.seconds(30),
      stickinessCookieDuration: cdk.Duration.hours(24),
      stickinessCookieName: 'ALB-COOKIE',
    });

    // Create target group for Network Load Balancer
    this.nlbTargetGroup = new elbv2.NetworkTargetGroup(this, 'NlbTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.Protocol.TCP,
      targetType: elbv2.TargetType.INSTANCE,
      targetGroupName: `${projectName}-nlb-tg`,
      healthCheck: {
        enabled: true,
        interval: cdk.Duration.seconds(30),
        path: '/',
        port: '80',
        protocol: elbv2.Protocol.HTTP,
        timeout: cdk.Duration.seconds(6),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 2,
      },
      // Configure target group attributes for optimization
      deregistrationDelay: cdk.Duration.seconds(30),
      preserveClientIp: true,
    });

    // Attach Auto Scaling Group to target groups
    this.albTargetGroup.node.addDependency(this.autoScalingGroup);
    this.nlbTargetGroup.node.addDependency(this.autoScalingGroup);

    // Register Auto Scaling Group with target groups
    this.autoScalingGroup.attachToApplicationTargetGroup(this.albTargetGroup);
    this.autoScalingGroup.attachToNetworkTargetGroup(this.nlbTargetGroup);

    // Create listener for Application Load Balancer
    const albListener = this.applicationLoadBalancer.addListener('AlbListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [this.albTargetGroup],
    });

    // Create listener for Network Load Balancer
    const nlbListener = this.networkLoadBalancer.addListener('NlbListener', {
      port: 80,
      protocol: elbv2.Protocol.TCP,
      defaultTargetGroups: [this.nlbTargetGroup],
    });

    // Add scaling policies based on ALB metrics
    const scaleUpPolicy = this.autoScalingGroup.scaleOnMetric('ScaleUpPolicy', {
      metric: this.applicationLoadBalancer.metricRequestCount({
        statistic: 'Sum',
      }),
      scalingSteps: [
        { upper: 30, change: +1 },
        { lower: 50, change: +2 },
      ],
      adjustmentType: autoscaling.AdjustmentType.CHANGE_IN_CAPACITY,
      cooldown: cdk.Duration.minutes(5),
    });

    const scaleDownPolicy = this.autoScalingGroup.scaleOnMetric('ScaleDownPolicy', {
      metric: this.applicationLoadBalancer.metricRequestCount({
        statistic: 'Sum',
      }),
      scalingSteps: [
        { upper: 10, change: -1 },
      ],
      adjustmentType: autoscaling.AdjustmentType.CHANGE_IN_CAPACITY,
      cooldown: cdk.Duration.minutes(5),
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', projectName);
    cdk.Tags.of(this).add('Environment', 'demo');
    cdk.Tags.of(this).add('Purpose', 'elastic-load-balancing-demo');

    // CloudFormation outputs for verification and integration
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the load balancer demo',
      exportName: `${projectName}-vpc-id`,
    });

    new cdk.CfnOutput(this, 'ApplicationLoadBalancerDns', {
      value: this.applicationLoadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: `${projectName}-alb-dns`,
    });

    new cdk.CfnOutput(this, 'NetworkLoadBalancerDns', {
      value: this.networkLoadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Network Load Balancer',
      exportName: `${projectName}-nlb-dns`,
    });

    new cdk.CfnOutput(this, 'AlbTargetGroupArn', {
      value: this.albTargetGroup.targetGroupArn,
      description: 'ARN of the ALB target group',
      exportName: `${projectName}-alb-tg-arn`,
    });

    new cdk.CfnOutput(this, 'NlbTargetGroupArn', {
      value: this.nlbTargetGroup.targetGroupArn,
      description: 'ARN of the NLB target group',
      exportName: `${projectName}-nlb-tg-arn`,
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group',
      exportName: `${projectName}-asg-name`,
    });

    new cdk.CfnOutput(this, 'TestAlbCommand', {
      value: `curl -s http://${this.applicationLoadBalancer.loadBalancerDnsName}`,
      description: 'Command to test the Application Load Balancer',
    });

    new cdk.CfnOutput(this, 'TestNlbCommand', {
      value: `curl -s http://${this.networkLoadBalancer.loadBalancerDnsName}`,
      description: 'Command to test the Network Load Balancer',
    });

    new cdk.CfnOutput(this, 'LoadTestCommand', {
      value: `for i in {1..10}; do echo "Request $i:"; curl -s http://${this.applicationLoadBalancer.loadBalancerDnsName} | grep "Instance ID"; sleep 1; done`,
      description: 'Command to test load balancing distribution',
    });
  }
}

// Main CDK App
const app = new cdk.App();

// Get deployment configuration from context or environment
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'elb-demo';
const vpcCidr = app.node.tryGetContext('vpcCidr') || process.env.VPC_CIDR || '10.0.0.0/16';
const instanceType = app.node.tryGetContext('instanceType') || process.env.INSTANCE_TYPE || 't3.micro';
const desiredCapacity = parseInt(app.node.tryGetContext('desiredCapacity') || process.env.DESIRED_CAPACITY || '2');

// Create the stack
new ElasticLoadBalancingStack(app, 'ElasticLoadBalancingStack', {
  projectName,
  vpcCidr,
  instanceType: new ec2.InstanceType(instanceType),
  desiredCapacity,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Elastic Load Balancing with Application and Network Load Balancers - CDK TypeScript implementation',
});

// Add metadata to the app
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);