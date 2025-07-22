#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

/**
 * CDK Stack for implementing Predictive Scaling with EC2 Auto Scaling and Machine Learning
 * 
 * This stack creates:
 * - VPC with public subnets across multiple AZs
 * - Auto Scaling Group with Launch Template
 * - Target Tracking and Predictive Scaling policies
 * - CloudWatch Dashboard for monitoring
 * - IAM roles and security groups
 */
export class PredictiveScalingStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create VPC with public subnets in multiple AZs for high availability
    this.vpc = new ec2.Vpc(this, 'PredictiveScalingVPC', {
      maxAzs: 2, // Use 2 AZs for cost optimization while maintaining HA
      cidr: '10.0.0.0/16',
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
      natGateways: 0, // No NAT gateways needed for public subnet demo
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });

    // Tag VPC resources for better organization
    cdk.Tags.of(this.vpc).add('Purpose', 'PredictiveScalingDemo');
    cdk.Tags.of(this.vpc).add('Environment', 'Production');

    // Create security group for EC2 instances
    const securityGroup = new ec2.SecurityGroup(this, 'PredictiveScalingSG', {
      vpc: this.vpc,
      description: 'Security group for Predictive Scaling demo instances',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from internet for demo web server
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from internet'
    );

    // Create IAM role for EC2 instances with CloudWatch permissions
    const instanceRole = new iam.Role(this, 'PredictiveScalingEC2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Predictive Scaling EC2 instances',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Create user data script for EC2 instances
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y httpd stress',
      'systemctl start httpd',
      'systemctl enable httpd',
      '',
      '# Create simple web page with instance metadata',
      'cat > /var/www/html/index.html << "EOF"',
      '<html>',
      '<head><title>Predictive Scaling Demo</title></head>',
      '<body>',
      '<h1>Predictive Scaling Demo</h1>',
      '<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>',
      '<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>',
      '<p>Instance Type: $(curl -s http://169.254.169.254/latest/meta-data/instance-type)</p>',
      '<p>Launch Time: $(date)</p>',
      '</body>',
      '</html>',
      'EOF',
      '',
      '# Create scheduled CPU load for demonstration',
      '# This simulates predictable load patterns for ML forecasting',
      'cat > /etc/cron.d/predictive-load << "EOF"',
      '# Create CPU load during business hours (8 AM - 8 PM UTC) on weekdays',
      '0 8 * * 1-5 root stress --cpu 2 --timeout 12h &',
      '# Create lower CPU load during weekends',
      '0 10 * * 6,0 root stress --cpu 1 --timeout 8h &',
      'EOF',
      '',
      '# Install CloudWatch agent for enhanced monitoring',
      'wget https://s3.amazonaws.com/amazoncloudwatch-agent/amazon_linux/amd64/latest/amazon-cloudwatch-agent.rpm',
      'rpm -U ./amazon-cloudwatch-agent.rpm',
      '',
      '# Configure CloudWatch agent (basic configuration)',
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << "EOF"',
      '{',
      '  "metrics": {',
      '    "namespace": "CWAgent",',
      '    "metrics_collected": {',
      '      "cpu": {',
      '        "measurement": ["cpu_usage_idle", "cpu_usage_iowait", "cpu_usage_user", "cpu_usage_system"],',
      '        "metrics_collection_interval": 60',
      '      },',
      '      "disk": {',
      '        "measurement": ["used_percent"],',
      '        "metrics_collection_interval": 60,',
      '        "resources": ["*"]',
      '      },',
      '      "mem": {',
      '        "measurement": ["mem_used_percent"],',
      '        "metrics_collection_interval": 60',
      '      }',
      '    }',
      '  }',
      '}',
      'EOF',
      '',
      '# Start CloudWatch agent',
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\',
      '  -a fetch-config -m ec2 -s \\',
      '  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json'
    );

    // Create Launch Template for Auto Scaling Group
    const launchTemplate = new ec2.LaunchTemplate(this, 'PredictiveScalingTemplate', {
      launchTemplateName: 'PredictiveScalingTemplate',
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      userData: userData,
      securityGroup: securityGroup,
      role: instanceRole,
      detailedMonitoring: true, // Enable detailed monitoring for better predictive scaling
    });

    // Create Auto Scaling Group with predictive scaling configuration
    this.autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'PredictiveScalingASG', {
      vpc: this.vpc,
      launchTemplate: launchTemplate,
      minCapacity: 2,
      maxCapacity: 10,
      desiredCapacity: 2,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      // Instance warmup time - critical for predictive scaling accuracy
      defaultInstanceWarmup: cdk.Duration.minutes(5),
      // Health check settings
      healthCheck: autoscaling.HealthCheck.ec2({
        grace: cdk.Duration.minutes(5),
      }),
      // Enable collection of group metrics for better visibility
      groupMetrics: [
        autoscaling.GroupMetrics.all(),
      ],
    });

    // Add tags to ASG and instances
    cdk.Tags.of(this.autoScalingGroup).add('Name', 'PredictiveScalingASG');
    cdk.Tags.of(this.autoScalingGroup).add('Environment', 'Production');
    cdk.Tags.of(this.autoScalingGroup).add('Purpose', 'PredictiveScalingDemo');

    // Create Target Tracking Scaling Policy
    // This handles reactive scaling for unexpected load changes
    const targetTrackingPolicy = this.autoScalingGroup.scaleOnCpuUtilization('CPUTargetTracking', {
      targetUtilizationPercent: 50,
      cooldown: cdk.Duration.minutes(5),
      disableScaleIn: false, // Allow scale-in to optimize costs
    });

    // Create Predictive Scaling Policy using CloudFormation resource
    // CDK doesn't have native L2 construct for predictive scaling yet
    const predictiveScalingPolicy = new cdk.CfnResource(this, 'PredictiveScalingPolicy', {
      type: 'AWS::AutoScaling::ScalingPolicy',
      properties: {
        AutoScalingGroupName: this.autoScalingGroup.autoScalingGroupName,
        PolicyName: 'PredictiveScalingPolicy',
        PolicyType: 'PredictiveScaling',
        PredictiveScalingConfiguration: {
          MetricSpecifications: [
            {
              TargetValue: 50.0,
              PredefinedMetricPairSpecification: {
                PredefinedMetricType: 'ASGCPUUtilization'
              }
            }
          ],
          // Start with ForecastOnly mode for evaluation
          Mode: 'ForecastOnly',
          // Launch instances 5 minutes before predicted demand
          SchedulingBufferTime: 300,
          // Allow exceeding max capacity by 10% if needed
          MaxCapacityBreachBehavior: 'IncreaseMaxCapacity',
          MaxCapacityBuffer: 10
        }
      }
    });

    // Ensure predictive scaling policy depends on ASG
    predictiveScalingPolicy.addDependency(this.autoScalingGroup.node.defaultChild as cdk.CfnResource);

    // Create CloudWatch Dashboard for monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'PredictiveScalingDashboard', {
      dashboardName: 'PredictiveScalingDashboard',
    });

    // Add CPU Utilization widget
    const cpuWidget = new cloudwatch.GraphWidget({
      title: 'ASG CPU Utilization',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'CPUUtilization',
          dimensionsMap: {
            AutoScalingGroupName: this.autoScalingGroup.autoScalingGroupName,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Add Instance Count widget
    const instanceCountWidget = new cloudwatch.GraphWidget({
      title: 'ASG Instance Count',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/AutoScaling',
          metricName: 'GroupInServiceInstances',
          dimensionsMap: {
            AutoScalingGroupName: this.autoScalingGroup.autoScalingGroupName,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/AutoScaling',
          metricName: 'GroupDesiredCapacity',
          dimensionsMap: {
            AutoScalingGroupName: this.autoScalingGroup.autoScalingGroupName,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Add Network I/O widget for additional monitoring
    const networkWidget = new cloudwatch.GraphWidget({
      title: 'Network I/O',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/EC2',
          metricName: 'NetworkIn',
          dimensionsMap: {
            AutoScalingGroupName: this.autoScalingGroup.autoScalingGroupName,
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
            AutoScalingGroupName: this.autoScalingGroup.autoScalingGroupName,
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 12,
      height: 6,
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(cpuWidget, instanceCountWidget);
    this.dashboard.addWidgets(networkWidget);

    // Output important information for validation and management
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: 'VPC ID for the Predictive Scaling demo',
      exportName: 'PredictiveScaling-VPC-ID',
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Auto Scaling Group name for managing predictive scaling',
      exportName: 'PredictiveScaling-ASG-Name',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=PredictiveScalingDashboard`,
      description: 'CloudWatch Dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'LaunchTemplateId', {
      value: launchTemplate.launchTemplateId!,
      description: 'Launch Template ID for the Auto Scaling Group',
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: securityGroup.securityGroupId,
      description: 'Security Group ID for EC2 instances',
    });

    // Output information about scaling policies
    new cdk.CfnOutput(this, 'TargetTrackingPolicyArn', {
      value: targetTrackingPolicy.scalingPolicyArn,
      description: 'Target Tracking Scaling Policy ARN',
    });

    new cdk.CfnOutput(this, 'PredictiveScalingInstructions', {
      value: 'Predictive scaling policy created in ForecastOnly mode. Monitor forecast accuracy for 24-48 hours, then switch to ForecastAndScale mode using AWS CLI or Console.',
      description: 'Next steps for enabling predictive scaling',
    });
  }
}

// Create CDK App and instantiate the stack
const app = new cdk.App();

// Stack configuration - customize these values as needed
const stackProps: cdk.StackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CDK Stack for Predictive Scaling with EC2 Auto Scaling and Machine Learning (recipe: predictive-scaling-ec2-autoscaling-machine-learning)',
  tags: {
    Project: 'PredictiveScalingDemo',
    Environment: 'Production',
    CostCenter: 'Engineering',
    Owner: 'DevOps-Team',
  },
};

// Instantiate the stack
const predictiveScalingStack = new PredictiveScalingStack(app, 'PredictiveScalingStack', stackProps);

// Add additional tags to the entire stack
cdk.Tags.of(predictiveScalingStack).add('Recipe', 'predictive-scaling-ec2-autoscaling-machine-learning');
cdk.Tags.of(predictiveScalingStack).add('CDKVersion', '2.100.0');
cdk.Tags.of(predictiveScalingStack).add('IaCTool', 'CDK-TypeScript');