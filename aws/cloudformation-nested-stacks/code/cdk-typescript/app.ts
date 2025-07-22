#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_ec2 as ec2,
  aws_iam as iam,
  aws_elasticloadbalancingv2 as elbv2,
  aws_autoscaling as autoscaling,
  aws_rds as rds,
  aws_secretsmanager as secretsmanager,
  aws_logs as logs,
  CfnOutput,
  Stack,
  StackProps,
  Tags,
  RemovalPolicy,
} from 'aws-cdk-lib';

/**
 * Environment configuration for different deployment stages
 */
interface EnvironmentConfig {
  instanceType: ec2.InstanceType;
  minSize: number;
  maxSize: number;
  desiredCapacity: number;
  dbInstanceClass: ec2.InstanceClass;
  dbInstanceSize: ec2.InstanceSize;
  dbAllocatedStorage: number;
  multiAz: boolean;
  deletionProtection: boolean;
}

/**
 * Environment-specific configurations following the CloudFormation template mappings
 */
const ENVIRONMENT_CONFIGS: Record<string, EnvironmentConfig> = {
  development: {
    instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
    minSize: 1,
    maxSize: 2,
    desiredCapacity: 1,
    dbInstanceClass: ec2.InstanceClass.T3,
    dbInstanceSize: ec2.InstanceSize.MICRO,
    dbAllocatedStorage: 20,
    multiAz: false,
    deletionProtection: false,
  },
  staging: {
    instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.SMALL),
    minSize: 2,
    maxSize: 4,
    desiredCapacity: 2,
    dbInstanceClass: ec2.InstanceClass.T3,
    dbInstanceSize: ec2.InstanceSize.SMALL,
    dbAllocatedStorage: 50,
    multiAz: false,
    deletionProtection: false,
  },
  production: {
    instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MEDIUM),
    minSize: 2,
    maxSize: 6,
    desiredCapacity: 3,
    dbInstanceClass: ec2.InstanceClass.T3,
    dbInstanceSize: ec2.InstanceSize.MEDIUM,
    dbAllocatedStorage: 100,
    multiAz: true,
    deletionProtection: true,
  },
};

/**
 * Network Layer Stack - Creates VPC, subnets, NAT gateways, and routing
 * Equivalent to network-template.yaml in the CloudFormation version
 */
export class NetworkStack extends Stack {
  public readonly vpc: ec2.Vpc;
  public readonly publicSubnets: ec2.ISubnet[];
  public readonly privateSubnets: ec2.ISubnet[];

  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    // Create VPC with public and private subnets across 2 AZs
    this.vpc = new ec2.Vpc(this, 'VPC', {
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      enableDnsHostnames: true,
      enableDnsSupport: true,
      subnetConfiguration: [
        {
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
          cidrMask: 24,
        },
        {
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS,
          cidrMask: 24,
        },
      ],
      natGateways: 2, // One NAT gateway per AZ for high availability
    });

    // Store subnet references for cross-stack access
    this.publicSubnets = this.vpc.publicSubnets;
    this.privateSubnets = this.vpc.privateSubnets;

    // Add tags to all VPC resources
    Tags.of(this.vpc).add('Environment', this.node.tryGetContext('environment') || 'development');
    Tags.of(this.vpc).add('Project', this.node.tryGetContext('projectName') || 'webapp');

    // Export VPC and subnet information for other stacks
    new CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      exportName: `${this.stackName}-VpcId`,
      description: 'VPC ID for cross-stack references',
    });

    new CfnOutput(this, 'VpcCidr', {
      value: this.vpc.vpcCidrBlock,
      exportName: `${this.stackName}-VpcCidr`,
      description: 'VPC CIDR block',
    });

    new CfnOutput(this, 'PublicSubnetIds', {
      value: this.publicSubnets.map(subnet => subnet.subnetId).join(','),
      exportName: `${this.stackName}-PublicSubnetIds`,
      description: 'Public subnet IDs for ALB placement',
    });

    new CfnOutput(this, 'PrivateSubnetIds', {
      value: this.privateSubnets.map(subnet => subnet.subnetId).join(','),
      exportName: `${this.stackName}-PrivateSubnetIds`,
      description: 'Private subnet IDs for application and database',
    });
  }
}

/**
 * Security Layer Stack - Creates security groups and IAM roles
 * Equivalent to security-template.yaml in the CloudFormation version
 */
export class SecurityStack extends Stack {
  public readonly albSecurityGroup: ec2.SecurityGroup;
  public readonly applicationSecurityGroup: ec2.SecurityGroup;
  public readonly bastionSecurityGroup: ec2.SecurityGroup;
  public readonly databaseSecurityGroup: ec2.SecurityGroup;
  public readonly ec2Role: iam.Role;
  public readonly rdsMonitoringRole: iam.Role;

  constructor(scope: Construct, id: string, vpc: ec2.IVpc, props?: StackProps) {
    super(scope, id, props);

    const environment = this.node.tryGetContext('environment') || 'development';
    const projectName = this.node.tryGetContext('projectName') || 'webapp';

    // Application Load Balancer Security Group
    this.albSecurityGroup = new ec2.SecurityGroup(this, 'ALBSecurityGroup', {
      vpc,
      description: 'Security group for Application Load Balancer',
      allowAllOutbound: true,
    });

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

    // Bastion Host Security Group
    this.bastionSecurityGroup = new ec2.SecurityGroup(this, 'BastionSecurityGroup', {
      vpc,
      description: 'Security group for bastion host',
      allowAllOutbound: true,
    });

    this.bastionSecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access from internet'
    );

    // Application Security Group
    this.applicationSecurityGroup = new ec2.SecurityGroup(this, 'ApplicationSecurityGroup', {
      vpc,
      description: 'Security group for application instances',
      allowAllOutbound: true,
    });

    this.applicationSecurityGroup.addIngressRule(
      this.albSecurityGroup,
      ec2.Port.tcp(80),
      'Allow HTTP traffic from ALB'
    );

    this.applicationSecurityGroup.addIngressRule(
      this.bastionSecurityGroup,
      ec2.Port.tcp(22),
      'Allow SSH from bastion host'
    );

    // Database Security Group
    this.databaseSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for database',
      allowAllOutbound: false,
    });

    this.databaseSecurityGroup.addIngressRule(
      this.applicationSecurityGroup,
      ec2.Port.tcp(3306),
      'Allow MySQL access from application'
    );

    // IAM Role for EC2 instances
    this.ec2Role = new iam.Role(this, 'EC2InstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instances with CloudWatch and SSM permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject'],
              resources: [`arn:aws:s3:::${projectName}-${environment}-*/*`],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [`arn:aws:s3:::${projectName}-${environment}-*`],
            }),
          ],
        }),
      },
    });

    // IAM Role for RDS Enhanced Monitoring
    this.rdsMonitoringRole = new iam.Role(this, 'RDSEnhancedMonitoringRole', {
      assumedBy: new iam.ServicePrincipal('monitoring.rds.amazonaws.com'),
      description: 'IAM role for RDS Enhanced Monitoring',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRDSEnhancedMonitoringRole'),
      ],
    });

    // Add tags to security resources
    Tags.of(this).add('Environment', environment);
    Tags.of(this).add('Project', projectName);
    Tags.of(this).add('Component', 'Security');

    // Export security group IDs and IAM role ARNs for other stacks
    new CfnOutput(this, 'ALBSecurityGroupId', {
      value: this.albSecurityGroup.securityGroupId,
      exportName: `${this.stackName}-ALBSecurityGroupId`,
      description: 'ALB Security Group ID',
    });

    new CfnOutput(this, 'ApplicationSecurityGroupId', {
      value: this.applicationSecurityGroup.securityGroupId,
      exportName: `${this.stackName}-ApplicationSecurityGroupId`,
      description: 'Application Security Group ID',
    });

    new CfnOutput(this, 'DatabaseSecurityGroupId', {
      value: this.databaseSecurityGroup.securityGroupId,
      exportName: `${this.stackName}-DatabaseSecurityGroupId`,
      description: 'Database Security Group ID',
    });

    new CfnOutput(this, 'EC2RoleArn', {
      value: this.ec2Role.roleArn,
      exportName: `${this.stackName}-EC2RoleArn`,
      description: 'EC2 Instance Role ARN',
    });

    new CfnOutput(this, 'RDSMonitoringRoleArn', {
      value: this.rdsMonitoringRole.roleArn,
      exportName: `${this.stackName}-RDSMonitoringRoleArn`,
      description: 'RDS Monitoring Role ARN',
    });
  }
}

/**
 * Application Layer Stack - Creates load balancer, auto scaling, and database
 * Equivalent to application-template.yaml in the CloudFormation version
 */
export class ApplicationStack extends Stack {
  public readonly loadBalancer: elbv2.ApplicationLoadBalancer;
  public readonly autoScalingGroup: autoscaling.AutoScalingGroup;
  public readonly database: rds.DatabaseInstance;
  public readonly databaseSecret: secretsmanager.Secret;

  constructor(
    scope: Construct,
    id: string,
    vpc: ec2.IVpc,
    publicSubnets: ec2.ISubnet[],
    privateSubnets: ec2.ISubnet[],
    securityGroups: {
      alb: ec2.ISecurityGroup;
      application: ec2.ISecurityGroup;
      database: ec2.ISecurityGroup;
    },
    ec2Role: iam.IRole,
    rdsMonitoringRole: iam.IRole,
    props?: StackProps
  ) {
    super(scope, id, props);

    const environment = this.node.tryGetContext('environment') || 'development';
    const projectName = this.node.tryGetContext('projectName') || 'webapp';
    const config = ENVIRONMENT_CONFIGS[environment];

    // Create CloudWatch Log Group for application logs
    const logGroup = new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: `/aws/ec2/${projectName}-${environment}/httpd/access`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // User data script for EC2 instances (equivalent to CloudFormation UserData)
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y httpd',
      'systemctl start httpd',
      'systemctl enable httpd',
      '',
      '# Create simple health check endpoint',
      `echo '<html><body><h1>Application Running</h1><p>Environment: ${environment}</p></body></html>' > /var/www/html/index.html`,
      `echo 'OK' > /var/www/html/health`,
      '',
      '# Install CloudWatch agent',
      'yum install -y amazon-cloudwatch-agent',
      '',
      '# Configure CloudWatch agent',
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << \'CWCONFIG\'',
      '{',
      '  "logs": {',
      '    "logs_collected": {',
      '      "files": {',
      '        "collect_list": [',
      '          {',
      '            "file_path": "/var/log/httpd/access_log",',
      `            "log_group_name": "${logGroup.logGroupName}",`,
      '            "log_stream_name": "{instance_id}"',
      '          }',
      '        ]',
      '      }',
      '    }',
      '  }',
      '}',
      'CWCONFIG',
      '',
      '# Start CloudWatch agent',
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\',
      '  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s'
    );

    // Launch Template for Auto Scaling Group
    const launchTemplate = new ec2.LaunchTemplate(this, 'ApplicationLaunchTemplate', {
      launchTemplateName: `${projectName}-${environment}-template`,
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      instanceType: config.instanceType,
      securityGroup: securityGroups.application,
      role: ec2Role,
      userData,
      requireImdsv2: true, // Enforce IMDSv2 for security
    });

    // Application Load Balancer
    this.loadBalancer = new elbv2.ApplicationLoadBalancer(this, 'ApplicationLoadBalancer', {
      vpc,
      internetFacing: true,
      vpcSubnets: { subnets: publicSubnets },
      securityGroup: securityGroups.alb,
      loadBalancerName: `${projectName}-${environment}-alb`,
    });

    // Target Group for the load balancer
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'ApplicationTargetGroup', {
      vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targetType: elbv2.TargetType.INSTANCE,
      healthCheck: {
        enabled: true,
        path: '/health',
        protocol: elbv2.Protocol.HTTP,
        interval: cdk.Duration.seconds(30),
        timeout: cdk.Duration.seconds(5),
        healthyThresholdCount: 2,
        unhealthyThresholdCount: 3,
      },
      deregistrationDelay: cdk.Duration.seconds(300),
      targetGroupName: `${projectName}-${environment}-tg`,
    });

    // Load Balancer Listener
    this.loadBalancer.addListener('ApplicationListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Auto Scaling Group
    this.autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'ApplicationAutoScalingGroup', {
      vpc,
      vpcSubnets: { subnets: privateSubnets },
      launchTemplate,
      minCapacity: config.minSize,
      maxCapacity: config.maxSize,
      desiredCapacity: config.desiredCapacity,
      healthCheck: autoscaling.HealthCheck.elb({
        grace: cdk.Duration.seconds(300),
      }),
      autoScalingGroupName: `${projectName}-${environment}-asg`,
    });

    // Attach Auto Scaling Group to Target Group
    this.autoScalingGroup.attachToApplicationTargetGroup(targetGroup);

    // Database Subnet Group
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc,
      vpcSubnets: { subnets: privateSubnets },
      description: 'Subnet group for RDS database',
      subnetGroupName: `${projectName}-${environment}-db-subnet-group`,
    });

    // Database credentials in Secrets Manager
    this.databaseSecret = new secretsmanager.Secret(this, 'DatabaseSecret', {
      secretName: `${projectName}-${environment}-db-secret`,
      description: 'Database credentials for MySQL instance',
      generateSecretString: {
        secretStringTemplate: JSON.stringify({ username: 'admin' }),
        generateStringKey: 'password',
        passwordLength: 16,
        excludeCharacters: '"@/\\\'',
      },
    });

    // RDS Database Instance
    this.database = new rds.DatabaseInstance(this, 'DatabaseInstance', {
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0_35,
      }),
      instanceType: ec2.InstanceType.of(config.dbInstanceClass, config.dbInstanceSize),
      vpc,
      vpcSubnets: { subnets: privateSubnets },
      subnetGroup: dbSubnetGroup,
      securityGroups: [securityGroups.database],
      credentials: rds.Credentials.fromSecret(this.databaseSecret),
      allocatedStorage: config.dbAllocatedStorage,
      storageType: rds.StorageType.GP2,
      storageEncrypted: true,
      multiAz: config.multiAz,
      backupRetention: cdk.Duration.days(7),
      monitoringInterval: cdk.Duration.seconds(60),
      monitoringRole: rdsMonitoringRole,
      enablePerformanceInsights: true,
      deletionProtection: config.deletionProtection,
      removalPolicy: config.deletionProtection ? RemovalPolicy.RETAIN : RemovalPolicy.DESTROY,
      instanceIdentifier: `${projectName}-${environment}-db`,
    });

    // Add tags to application resources
    Tags.of(this).add('Environment', environment);
    Tags.of(this).add('Project', projectName);
    Tags.of(this).add('Component', 'Application');

    // Export application layer outputs
    new CfnOutput(this, 'LoadBalancerDNS', {
      value: this.loadBalancer.loadBalancerDnsName,
      exportName: `${this.stackName}-LoadBalancerDNS`,
      description: 'Application Load Balancer DNS name',
    });

    new CfnOutput(this, 'ApplicationURL', {
      value: `http://${this.loadBalancer.loadBalancerDnsName}`,
      exportName: `${this.stackName}-ApplicationURL`,
      description: 'Application URL',
    });

    new CfnOutput(this, 'DatabaseEndpoint', {
      value: this.database.instanceEndpoint.hostname,
      exportName: `${this.stackName}-DatabaseEndpoint`,
      description: 'RDS database endpoint',
    });

    new CfnOutput(this, 'DatabasePort', {
      value: this.database.instanceEndpoint.port.toString(),
      exportName: `${this.stackName}-DatabasePort`,
      description: 'RDS database port',
    });

    new CfnOutput(this, 'DatabaseSecretArn', {
      value: this.databaseSecret.secretArn,
      exportName: `${this.stackName}-DatabaseSecretArn`,
      description: 'Database secret ARN in Secrets Manager',
    });
  }
}

/**
 * Root Stack - Orchestrates all nested stacks with proper dependencies
 * Equivalent to root-stack-template.yaml in the CloudFormation version
 */
export class RootStack extends Stack {
  constructor(scope: Construct, id: string, props?: StackProps) {
    super(scope, id, props);

    const environment = this.node.tryGetContext('environment') || 'development';
    const projectName = this.node.tryGetContext('projectName') || 'webapp';

    // Deploy Network Stack first
    const networkStack = new NetworkStack(this, 'NetworkStack', {
      stackName: `${projectName}-${environment}-network`,
      description: 'Network infrastructure layer with VPC, subnets, and routing',
      ...props,
    });

    // Deploy Security Stack (depends on Network Stack)
    const securityStack = new SecurityStack(this, 'SecurityStack', networkStack.vpc, {
      stackName: `${projectName}-${environment}-security`,
      description: 'Security layer with IAM roles, security groups, and policies',
      ...props,
    });
    securityStack.addDependency(networkStack);

    // Deploy Application Stack (depends on both Network and Security Stacks)
    const applicationStack = new ApplicationStack(
      this,
      'ApplicationStack',
      networkStack.vpc,
      networkStack.publicSubnets,
      networkStack.privateSubnets,
      {
        alb: securityStack.albSecurityGroup,
        application: securityStack.applicationSecurityGroup,
        database: securityStack.databaseSecurityGroup,
      },
      securityStack.ec2Role,
      securityStack.rdsMonitoringRole,
      {
        stackName: `${projectName}-${environment}-application`,
        description: 'Application layer with load balancer, auto scaling, and database',
        ...props,
      }
    );
    applicationStack.addDependency(networkStack);
    applicationStack.addDependency(securityStack);

    // Add tags to all stacks
    Tags.of(this).add('Environment', environment);
    Tags.of(this).add('Project', projectName);
    Tags.of(this).add('StackType', 'Root');

    // Export root stack outputs
    new CfnOutput(this, 'NetworkStackId', {
      value: networkStack.stackId,
      exportName: `${this.stackName}-NetworkStackId`,
      description: 'Network stack ID',
    });

    new CfnOutput(this, 'SecurityStackId', {
      value: securityStack.stackId,
      exportName: `${this.stackName}-SecurityStackId`,
      description: 'Security stack ID',
    });

    new CfnOutput(this, 'ApplicationStackId', {
      value: applicationStack.stackId,
      exportName: `${this.stackName}-ApplicationStackId`,
      description: 'Application stack ID',
    });

    new CfnOutput(this, 'VpcId', {
      value: networkStack.vpc.vpcId,
      exportName: `${this.stackName}-VpcId`,
      description: 'VPC ID from nested network stack',
    });

    new CfnOutput(this, 'ApplicationURL', {
      value: `http://${applicationStack.loadBalancer.loadBalancerDnsName}`,
      exportName: `${this.stackName}-ApplicationURL`,
      description: 'Application URL',
    });

    new CfnOutput(this, 'DatabaseEndpoint', {
      value: applicationStack.database.instanceEndpoint.hostname,
      exportName: `${this.stackName}-DatabaseEndpoint`,
      description: 'Database endpoint from nested application stack',
    });
  }
}

/**
 * CDK Application Entry Point
 * This is where we instantiate and configure the CDK app and stacks
 */
const app = new cdk.App();

// Get context values for environment and project configuration
const environment = app.node.tryGetContext('environment') || 'development';
const projectName = app.node.tryGetContext('projectName') || 'webapp';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Validate environment parameter
const validEnvironments = ['development', 'staging', 'production'];
if (!validEnvironments.includes(environment)) {
  throw new Error(`Invalid environment: ${environment}. Must be one of: ${validEnvironments.join(', ')}`);
}

// Create the root stack which will deploy all nested stacks
new RootStack(app, 'NestedInfrastructureStack', {
  stackName: `${projectName}-${environment}-nested-infrastructure`,
  description: `Root stack for nested infrastructure deployment (${environment} environment)`,
  env: {
    account,
    region,
  },
  tags: {
    Environment: environment,
    Project: projectName,
    StackType: 'Root',
    ManagedBy: 'CDK',
  },
});

// Synthesize the CDK app
app.synth();