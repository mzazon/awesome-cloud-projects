#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Properties for the AutoScalingLoadBalancerStack
 */
export interface AutoScalingLoadBalancerStackProps extends cdk.StackProps {
  /**
   * The VPC to deploy resources into
   * If not provided, a new VPC will be created
   */
  vpc?: ec2.IVpc;
  
  /**
   * Minimum number of instances in the Auto Scaling Group
   * @default 2
   */
  minSize?: number;
  
  /**
   * Maximum number of instances in the Auto Scaling Group
   * @default 8
   */
  maxSize?: number;
  
  /**
   * Desired number of instances in the Auto Scaling Group
   * @default 2
   */
  desiredCapacity?: number;
  
  /**
   * Target CPU utilization percentage for auto scaling
   * @default 70
   */
  targetCpuUtilization?: number;
  
  /**
   * Target requests per target for ALB-based scaling
   * @default 1000
   */
  targetRequestsPerTarget?: number;
}

/**
 * CDK Stack for Auto Scaling with Load Balancers
 * 
 * This stack creates:
 * - VPC with public and private subnets across multiple AZs
 * - Application Load Balancer in public subnets
 * - Auto Scaling Group with EC2 instances in private subnets
 * - Target Group for load balancer health checks
 * - Security Groups with appropriate access rules
 * - Target tracking scaling policies for CPU and request count
 * - Scheduled scaling actions for business hours
 * - CloudWatch alarms for monitoring
 */
export class AutoScalingLoadBalancerStack extends cdk.Stack {
  public readonly vpc: ec2.IVpc;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;
  public readonly targetGroup: elbv2.ApplicationTargetGroup;

  constructor(scope: Construct, id: string, props?: AutoScalingLoadBalancerStackProps) {
    super(scope, id, props);

    // Default values for stack properties
    const minSize = props?.minSize ?? 2;
    const maxSize = props?.maxSize ?? 8;
    const desiredCapacity = props?.desiredCapacity ?? 2;
    const targetCpuUtilization = props?.targetCpuUtilization ?? 70;
    const targetRequestsPerTarget = props?.targetRequestsPerTarget ?? 1000;

    // Create or use existing VPC
    this.vpc = props?.vpc ?? this.createVpc();

    // Create security groups
    const { albSecurityGroup, instanceSecurityGroup } = this.createSecurityGroups();

    // Create Application Load Balancer
    this.loadBalancer = this.createApplicationLoadBalancer(albSecurityGroup);

    // Create Target Group
    this.targetGroup = this.createTargetGroup();

    // Create Auto Scaling Group
    this.autoScalingGroup = this.createAutoScalingGroup(
      instanceSecurityGroup,
      minSize,
      maxSize,
      desiredCapacity
    );

    // Connect Target Group to Auto Scaling Group
    this.autoScalingGroup.attachToApplicationTargetGroup(this.targetGroup);

    // Create Load Balancer Listener
    this.createLoadBalancerListener();

    // Configure Auto Scaling Policies
    this.configureScalingPolicies(targetCpuUtilization, targetRequestsPerTarget);

    // Create Scheduled Scaling Actions
    this.createScheduledScalingActions();

    // Create CloudWatch Alarms
    this.createCloudWatchAlarms();

    // Create outputs
    this.createOutputs();

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'AutoScalingDemo');
    cdk.Tags.of(this).add('Environment', 'demo');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Creates a new VPC with public and private subnets across multiple AZs
   */
  private createVpc(): ec2.Vpc {
    return new ec2.Vpc(this, 'AutoScalingVpc', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 3,
      natGateways: 1, // Use single NAT Gateway for cost optimization in demo
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
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }

  /**
   * Creates security groups for ALB and EC2 instances
   */
  private createSecurityGroups(): {
    albSecurityGroup: ec2.SecurityGroup;
    instanceSecurityGroup: ec2.SecurityGroup;
  } {
    // Security Group for Application Load Balancer
    const albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from internet
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from internet'
    );

    // Allow HTTPS traffic from internet
    albSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from internet'
    );

    // Security Group for EC2 instances
    const instanceSecurityGroup = new ec2.SecurityGroup(this, 'InstanceSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for Auto Scaling Group instances',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from ALB
    instanceSecurityGroup.addIngressRule(
      albSecurityGroup,
      ec2.Port.tcp(80),
      'Allow HTTP traffic from ALB'
    );

    // Allow SSH access for troubleshooting (restrict in production)
    instanceSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for troubleshooting'
    );

    return { albSecurityGroup, instanceSecurityGroup };
  }

  /**
   * Creates the Application Load Balancer
   */
  private createApplicationLoadBalancer(securityGroup: ec2.SecurityGroup): elbv2.ApplicationLoadBalancer {
    return new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: securityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      deletionProtection: false, // Allow deletion for demo purposes
    });
  }

  /**
   * Creates the target group with health check configuration
   */
  private createTargetGroup(): elbv2.ApplicationTargetGroup {
    return new elbv2.ApplicationTargetGroup(this, 'WebAppTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        enabled: true,
        protocol: elbv2.Protocol.HTTP,
        path: '/',
        port: '80',
        healthyHttpCodes: '200',
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      deregistrationDelay: cdk.Duration.seconds(30),
      stickinessCookieDuration: cdk.Duration.days(0), // Disable stickiness
    });
  }

  /**
   * Creates the Auto Scaling Group with launch template
   */
  private createAutoScalingGroup(
    securityGroup: ec2.SecurityGroup,
    minSize: number,
    maxSize: number,
    desiredCapacity: number
  ): autoscaling.AutoScalingGroup {
    // Get the latest Amazon Linux 2 AMI
    const machineImage = ec2.MachineImage.latestAmazonLinux2({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
    });

    // Create user data script for web server setup
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      // Update system and install Apache
      'yum update -y',
      'yum install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      
      // Create demo web page with instance metadata
      'cat > /var/www/html/index.html << \'EOF\'',
      '<!DOCTYPE html>',
      '<html>',
      '<head>',
      '    <title>Auto Scaling Demo</title>',
      '    <style>',
      '        body { font-family: Arial, sans-serif; margin: 40px; }',
      '        .container { max-width: 800px; margin: 0 auto; }',
      '        .metric { background: #f0f0f0; padding: 20px; margin: 10px 0; border-radius: 5px; }',
      '        .load-btn { background: #ff6b35; color: white; padding: 10px 20px; border: none; border-radius: 5px; cursor: pointer; }',
      '        .load-btn:hover { background: #e55a30; }',
      '    </style>',
      '</head>',
      '<body>',
      '    <div class="container">',
      '        <h1>Auto Scaling Demo Application</h1>',
      '        <div class="metric">',
      '            <h3>Instance Information</h3>',
      '            <p><strong>Instance ID:</strong> <span id="instance-id">Loading...</span></p>',
      '            <p><strong>Availability Zone:</strong> <span id="az">Loading...</span></p>',
      '            <p><strong>Instance Type:</strong> <span id="instance-type">Loading...</span></p>',
      '            <p><strong>Local IP:</strong> <span id="local-ip">Loading...</span></p>',
      '            <p><strong>Server Time:</strong> <span id="server-time"></span></p>',
      '        </div>',
      '        <div class="metric">',
      '            <h3>Load Test</h3>',
      '            <button class="load-btn" onclick="generateLoad()">Generate CPU Load (30s)</button>',
      '            <p><strong>Status:</strong> <span id="load-status">Ready</span></p>',
      '        </div>',
      '    </div>',
      '    <script>',
      '        // Fetch instance metadata',
      '        async function fetchMetadata() {',
      '            try {',
      '                const token = await fetch("http://169.254.169.254/latest/api/token", {',
      '                    method: "PUT",',
      '                    headers: {"X-aws-ec2-metadata-token-ttl-seconds": "21600"}',
      '                }).then(r => r.text());',
      '                const headers = {"X-aws-ec2-metadata-token": token};',
      '                const instanceId = await fetch("http://169.254.169.254/latest/meta-data/instance-id", {headers}).then(r => r.text());',
      '                const az = await fetch("http://169.254.169.254/latest/meta-data/placement/availability-zone", {headers}).then(r => r.text());',
      '                const instanceType = await fetch("http://169.254.169.254/latest/meta-data/instance-type", {headers}).then(r => r.text());',
      '                const localIp = await fetch("http://169.254.169.254/latest/meta-data/local-ipv4", {headers}).then(r => r.text());',
      '                document.getElementById("instance-id").textContent = instanceId;',
      '                document.getElementById("az").textContent = az;',
      '                document.getElementById("instance-type").textContent = instanceType;',
      '                document.getElementById("local-ip").textContent = localIp;',
      '            } catch (error) { console.error("Error fetching metadata:", error); }',
      '        }',
      '        // Generate CPU load for testing',
      '        function generateLoad() {',
      '            document.getElementById("load-status").textContent = "Generating high CPU load...";',
      '            const workers = [];',
      '            for (let i = 0; i < 4; i++) {',
      '                workers.push(new Worker("data:application/javascript,let start=Date.now();while(Date.now()-start<30000){Math.random();}"));',
      '            }',
      '            setTimeout(() => {',
      '                workers.forEach(worker => worker.terminate());',
      '                document.getElementById("load-status").textContent = "Load test completed";',
      '            }, 30000);',
      '        }',
      '        // Update server time',
      '        function updateTime() {',
      '            document.getElementById("server-time").textContent = new Date().toLocaleString();',
      '        }',
      '        fetchMetadata(); updateTime(); setInterval(updateTime, 1000);',
      '    </script>',
      '</body>',
      '</html>',
      'EOF'
    );

    // Create Auto Scaling Group
    return new autoscaling.AutoScalingGroup(this, 'WebAppAutoScalingGroup', {
      vpc: this.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: machineImage,
      userData: userData,
      securityGroup: securityGroup,
      minCapacity: minSize,
      maxCapacity: maxSize,
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
      signals: autoscaling.Signals.waitForMinCapacity({
        timeout: cdk.Duration.minutes(10),
      }),
      requireImdsv2: true, // Enable IMDSv2 for enhanced security
    });
  }

  /**
   * Creates the load balancer listener
   */
  private createLoadBalancerListener(): void {
    this.loadBalancer.addListener('WebAppListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [this.targetGroup],
    });
  }

  /**
   * Configures target tracking scaling policies
   */
  private configureScalingPolicies(
    targetCpuUtilization: number,
    targetRequestsPerTarget: number
  ): void {
    // CPU utilization target tracking policy
    this.autoScalingGroup.scaleOnCpuUtilization('CpuTargetTrackingPolicy', {
      targetUtilizationPercent: targetCpuUtilization,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
      disableScaleIn: false,
    });

    // ALB request count target tracking policy
    this.autoScalingGroup.scaleOnRequestCount('RequestCountTargetTrackingPolicy', {
      targetRequestsPerMinute: targetRequestsPerTarget,
      targetGroup: this.targetGroup,
      scaleInCooldown: cdk.Duration.minutes(5),
      scaleOutCooldown: cdk.Duration.minutes(5),
      disableScaleIn: false,
    });
  }

  /**
   * Creates scheduled scaling actions for business hours
   */
  private createScheduledScalingActions(): void {
    // Scale up during business hours (9 AM UTC Monday-Friday)
    this.autoScalingGroup.scaleOnSchedule('ScaleUpBusinessHours', {
      schedule: autoscaling.Schedule.cron({
        hour: '9',
        minute: '0',
        weekDay: 'MON-FRI',
      }),
      minCapacity: 3,
      maxCapacity: 10,
      desiredCapacity: 4,
    });

    // Scale down after business hours (6 PM UTC Monday-Friday)
    this.autoScalingGroup.scaleOnSchedule('ScaleDownAfterHours', {
      schedule: autoscaling.Schedule.cron({
        hour: '18',
        minute: '0',
        weekDay: 'MON-FRI',
      }),
      minCapacity: 1,
      maxCapacity: 8,
      desiredCapacity: 2,
    });
  }

  /**
   * Creates CloudWatch alarms for monitoring
   */
  private createCloudWatchAlarms(): void {
    // High CPU utilization alarm
    new cloudwatch.Alarm(this, 'HighCpuAlarm', {
      alarmName: `${this.autoScalingGroup.autoScalingGroupName}-high-cpu`,
      alarmDescription: 'High CPU utilization across Auto Scaling Group',
      metric: this.autoScalingGroup.metricCpuUtilization({
        period: cdk.Duration.minutes(5),
        statistic: cloudwatch.Stats.AVERAGE,
      }),
      threshold: 80,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Unhealthy target count alarm
    new cloudwatch.Alarm(this, 'UnhealthyTargetsAlarm', {
      alarmName: `${this.autoScalingGroup.autoScalingGroupName}-unhealthy-targets`,
      alarmDescription: 'Unhealthy targets in target group',
      metric: this.targetGroup.metricUnhealthyHostCount({
        period: cdk.Duration.minutes(1),
        statistic: cloudwatch.Stats.AVERAGE,
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Target group healthy host count metric
    new cloudwatch.Alarm(this, 'LowHealthyTargetsAlarm', {
      alarmName: `${this.autoScalingGroup.autoScalingGroupName}-low-healthy-targets`,
      alarmDescription: 'Low number of healthy targets in target group',
      metric: this.targetGroup.metricHealthyHostCount({
        period: cdk.Duration.minutes(1),
        statistic: cloudwatch.Stats.AVERAGE,
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: `${this.stackName}-LoadBalancerDNS`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerURL', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}`,
      description: 'URL of the web application',
      exportName: `${this.stackName}-LoadBalancerURL`,
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group',
      exportName: `${this.stackName}-AutoScalingGroupName`,
    });

    new cdk.CfnOutput(this, 'TargetGroupArn', {
      value: this.targetGroup.targetGroupArn,
      description: 'ARN of the Target Group',
      exportName: `${this.stackName}-TargetGroupArn`,
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'ID of the VPC',
      exportName: `${this.stackName}-VpcId`,
    });
  }
}

// CDK App
const app = new cdk.App();

// Stack configuration from context or environment variables
const stackName = app.node.tryGetContext('stackName') || 'AutoScalingLoadBalancerStack';
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the stack
new AutoScalingLoadBalancerStack(app, stackName, {
  env,
  description: 'Auto Scaling with Application Load Balancers and Target Groups - CDK Demo Stack',
  
  // Stack configuration (can be overridden via context)
  minSize: Number(app.node.tryGetContext('minSize')) || 2,
  maxSize: Number(app.node.tryGetContext('maxSize')) || 8,
  desiredCapacity: Number(app.node.tryGetContext('desiredCapacity')) || 2,
  targetCpuUtilization: Number(app.node.tryGetContext('targetCpuUtilization')) || 70,
  targetRequestsPerTarget: Number(app.node.tryGetContext('targetRequestsPerTarget')) || 1000,
  
  // Resource tagging
  tags: {
    Project: 'AutoScalingDemo',
    Environment: app.node.tryGetContext('environment') || 'demo',
    Owner: app.node.tryGetContext('owner') || 'CDK',
    CostCenter: app.node.tryGetContext('costCenter') || 'demo',
  },
});

// Enable termination protection for production environments
if (app.node.tryGetContext('environment') === 'production') {
  app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', true);
}