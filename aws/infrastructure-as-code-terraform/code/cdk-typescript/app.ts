#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Stack for demonstrating Infrastructure as Code with AWS CDK
 * 
 * This stack creates:
 * - VPC with public subnets across multiple AZs
 * - Application Load Balancer for traffic distribution
 * - Auto Scaling Group with EC2 instances running web servers
 * - Security groups with appropriate access controls
 * - IAM roles with least privilege permissions
 */
export class TerraformIacDemoStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;

  constructor(scope: Construct, id: string, props?: TerraformIacDemoStackProps) {
    super(scope, id, props);

    // Extract configuration from props with sensible defaults
    const config = {
      projectName: props?.projectName || 'terraform-iac-demo',
      environment: props?.environment || 'dev',
      vpcCidr: props?.vpcCidr || '10.0.0.0/16',
      instanceType: props?.instanceType || ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      minCapacity: props?.minCapacity || 2,
      maxCapacity: props?.maxCapacity || 4,
      desiredCapacity: props?.desiredCapacity || 2
    };

    // Add comprehensive tags to all resources
    cdk.Tags.of(this).add('Project', config.projectName);
    cdk.Tags.of(this).add('Environment', config.environment);
    cdk.Tags.of(this).add('ManagedBy', 'aws-cdk');
    cdk.Tags.of(this).add('Recipe', 'infrastructure-as-code-terraform-aws');

    // Create VPC with public subnets for high availability
    this.vpc = this.createVpc(config);

    // Create security groups with appropriate access controls
    const securityGroup = this.createSecurityGroup(config);

    // Create IAM role for EC2 instances with minimal required permissions
    const instanceRole = this.createInstanceRole(config);

    // Create Application Load Balancer for traffic distribution
    this.loadBalancer = this.createLoadBalancer(config, securityGroup);

    // Create Auto Scaling Group with launch template
    this.autoScalingGroup = this.createAutoScalingGroup(config, securityGroup, instanceRole);

    // Create target group and attach to load balancer
    this.createTargetGroupAndListener(config);

    // Output important values for integration and verification
    this.createOutputs(config);
  }

  /**
   * Creates a VPC with public subnets across multiple availability zones
   * for high availability and fault tolerance
   */
  private createVpc(config: any): ec2.Vpc {
    const vpc = new ec2.Vpc(this, 'VPC', {
      ipAddresses: ec2.IpAddresses.cidr(config.vpcCidr),
      maxAzs: 2, // Use 2 AZs for high availability
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        }
      ],
      natGateways: 0, // No NAT gateways needed for this demo
    });

    // Tag VPC with descriptive name
    cdk.Tags.of(vpc).add('Name', `${config.projectName}-vpc`);

    return vpc;
  }

  /**
   * Creates security group with HTTP/HTTPS access from internet
   * and unrestricted outbound access for package installation
   */
  private createSecurityGroup(config: any): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'WebSecurityGroup', {
      vpc: this.vpc,
      description: 'Security group for web servers',
      allowAllOutbound: true,
    });

    // Allow HTTP traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'Allow HTTP traffic from internet'
    );

    // Allow HTTPS traffic from anywhere
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS traffic from internet'
    );

    cdk.Tags.of(securityGroup).add('Name', `${config.projectName}-web-sg`);

    return securityGroup;
  }

  /**
   * Creates IAM role for EC2 instances with minimal required permissions
   * following the principle of least privilege
   */
  private createInstanceRole(config: any): iam.Role {
    const role = new iam.Role(this, 'InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for web server instances',
      managedPolicies: [
        // Basic SSM access for potential management needs
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Allow CloudWatch logs if needed for monitoring
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:PutLogEvents',
        'logs:DescribeLogStreams',
        'logs:DescribeLogGroups'
      ],
      resources: ['*'],
    }));

    cdk.Tags.of(role).add('Name', `${config.projectName}-instance-role`);

    return role;
  }

  /**
   * Creates Application Load Balancer in public subnets
   * for distributing traffic across multiple instances
   */
  private createLoadBalancer(config: any, securityGroup: ec2.SecurityGroup): elbv2.ApplicationLoadBalancer {
    const alb = new elbv2.ApplicationLoadBalancer(this, 'WebALB', {
      vpc: this.vpc,
      internetFacing: true,
      securityGroup: securityGroup,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    cdk.Tags.of(alb).add('Name', `${config.projectName}-web-alb`);

    return alb;
  }

  /**
   * Creates Auto Scaling Group with launch template
   * for automatic scaling based on demand
   */
  private createAutoScalingGroup(config: any, securityGroup: ec2.SecurityGroup, instanceRole: iam.Role): autoscaling.AutoScalingGroup {
    // Create launch template with user data for web server setup
    const launchTemplate = new ec2.LaunchTemplate(this, 'WebLaunchTemplate', {
      instanceType: config.instanceType,
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      securityGroup: securityGroup,
      role: instanceRole,
      userData: ec2.UserData.forLinux(),
    });

    // Add user data commands to install and configure web server
    launchTemplate.userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      'echo "<h1>Hello from AWS CDK!</h1>" > /var/www/html/index.html',
      'echo "<p>Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id)</p>" >> /var/www/html/index.html',
      'echo "<p>Availability Zone: $(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)</p>" >> /var/www/html/index.html',
      'echo "<p>Deployment Method: AWS CDK TypeScript</p>" >> /var/www/html/index.html'
    );

    cdk.Tags.of(launchTemplate).add('Name', `${config.projectName}-web-lt`);

    // Create Auto Scaling Group
    const asg = new autoscaling.AutoScalingGroup(this, 'WebASG', {
      vpc: this.vpc,
      launchTemplate: launchTemplate,
      minCapacity: config.minCapacity,
      maxCapacity: config.maxCapacity,
      desiredCapacity: config.desiredCapacity,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      healthCheck: autoscaling.HealthCheck.elb({
        grace: cdk.Duration.seconds(300),
      }),
    });

    cdk.Tags.of(asg).add('Name', `${config.projectName}-web-asg`);

    return asg;
  }

  /**
   * Creates target group and listener for load balancer
   * with health checks and proper routing
   */
  private createTargetGroupAndListener(config: any): void {
    // Create target group for web servers
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'WebTargetGroup', {
      vpc: this.vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [this.autoScalingGroup],
      healthCheck: {
        enabled: true,
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 2,
        timeout: cdk.Duration.seconds(5),
        interval: cdk.Duration.seconds(30),
        path: '/',
        protocol: elbv2.Protocol.HTTP,
        port: '80',
      },
    });

    cdk.Tags.of(targetGroup).add('Name', `${config.projectName}-web-tg`);

    // Create listener for HTTP traffic
    new elbv2.ApplicationListener(this, 'WebListener', {
      loadBalancer: this.loadBalancer,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultAction: elbv2.ListenerAction.forward([targetGroup]),
    });
  }

  /**
   * Creates CloudFormation outputs for important resource identifiers
   * and integration points
   */
  private createOutputs(config: any): void {
    new cdk.CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'ID of the VPC',
      exportName: `${config.projectName}-vpc-id`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerDnsName', {
      value: this.loadBalancer.loadBalancerDnsName,
      description: 'DNS name of the Application Load Balancer',
      exportName: `${config.projectName}-alb-dns`,
    });

    new cdk.CfnOutput(this, 'LoadBalancerArn', {
      value: this.loadBalancer.loadBalancerArn,
      description: 'ARN of the Application Load Balancer',
      exportName: `${config.projectName}-alb-arn`,
    });

    new cdk.CfnOutput(this, 'AutoScalingGroupName', {
      value: this.autoScalingGroup.autoScalingGroupName,
      description: 'Name of the Auto Scaling Group',
      exportName: `${config.projectName}-asg-name`,
    });

    new cdk.CfnOutput(this, 'PublicSubnetIds', {
      value: this.vpc.publicSubnets.map(subnet => subnet.subnetId).join(','),
      description: 'IDs of public subnets',
      exportName: `${config.projectName}-public-subnet-ids`,
    });

    // Create a convenient output with the application URL
    new cdk.CfnOutput(this, 'ApplicationUrl', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}`,
      description: 'URL to access the web application',
    });
  }
}

/**
 * Interface defining configuration properties for the stack
 */
export interface TerraformIacDemoStackProps extends cdk.StackProps {
  readonly projectName?: string;
  readonly environment?: string;
  readonly vpcCidr?: string;
  readonly instanceType?: ec2.InstanceType;
  readonly minCapacity?: number;
  readonly maxCapacity?: number;
  readonly desiredCapacity?: number;
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or use defaults
const projectName = app.node.tryGetContext('projectName') || 'terraform-iac-demo';
const environment = app.node.tryGetContext('environment') || 'dev';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Create development stack
new TerraformIacDemoStack(app, 'TerraformIacDemoDevStack', {
  projectName: projectName,
  environment: 'dev',
  vpcCidr: '10.0.0.0/16',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
  minCapacity: 2,
  maxCapacity: 4,
  desiredCapacity: 2,
  env: {
    account: account,
    region: region,
  },
  description: 'Development environment for Infrastructure as Code demo using AWS CDK',
});

// Create staging stack with different configuration
new TerraformIacDemoStack(app, 'TerraformIacDemoStagingStack', {
  projectName: projectName,
  environment: 'staging',
  vpcCidr: '10.1.0.0/16',
  instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
  minCapacity: 2,
  maxCapacity: 6,
  desiredCapacity: 3,
  env: {
    account: account,
    region: region,
  },
  description: 'Staging environment for Infrastructure as Code demo using AWS CDK',
});

// Add application-level tags
cdk.Tags.of(app).add('Application', 'terraform-iac-demo');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('Recipe', 'infrastructure-as-code-terraform-aws');