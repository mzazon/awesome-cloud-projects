#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import { AwsSolutionsChecks } from 'cdk-nag';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as ssm from 'aws-cdk-lib/aws-ssm';

/**
 * Properties for the SecureRemoteAccessStack
 */
export interface SecureRemoteAccessStackProps extends cdk.StackProps {
  /**
   * The name prefix for all resources
   * @default 'SecureRemoteAccess'
   */
  readonly resourcePrefix?: string;

  /**
   * The EC2 instance type to use for the demo instance
   * @default 't3.micro'
   */
  readonly instanceType?: string;

  /**
   * Whether to create a VPC or use the default VPC
   * @default false (uses default VPC)
   */
  readonly createVpc?: boolean;

  /**
   * CloudWatch log retention period in days
   * @default 30
   */
  readonly logRetentionDays?: number;

  /**
   * S3 bucket lifecycle policy - days to transition to IA
   * @default 30
   */
  readonly s3LifecycleDaysToIA?: number;

  /**
   * S3 bucket lifecycle policy - days to transition to Glacier
   * @default 90
   */
  readonly s3LifecycleDaysToGlacier?: number;

  /**
   * Additional tags to apply to all resources
   */
  readonly additionalTags?: { [key: string]: string };
}

/**
 * Stack that implements secure remote access using AWS Systems Manager Session Manager
 * 
 * This stack creates:
 * - IAM role for EC2 instances with Session Manager permissions
 * - S3 bucket for session logs with encryption and lifecycle policies
 * - CloudWatch log group for session monitoring
 * - EC2 instance configured for Session Manager access
 * - Session Manager logging configuration
 * - User policy template for controlled access
 */
export class SecureRemoteAccessStack extends cdk.Stack {
  public readonly instanceRole: iam.Role;
  public readonly sessionLogsBucket: s3.Bucket;
  public readonly sessionLogsGroup: logs.LogGroup;
  public readonly demoInstance: ec2.Instance;
  public readonly userPolicy: iam.ManagedPolicy;

  constructor(scope: Construct, id: string, props: SecureRemoteAccessStackProps = {}) {
    super(scope, id, props);

    // Extract props with defaults
    const resourcePrefix = props.resourcePrefix ?? 'SecureRemoteAccess';
    const instanceType = props.instanceType ?? 't3.micro';
    const createVpc = props.createVpc ?? false;
    const logRetentionDays = props.logRetentionDays ?? 30;
    const s3LifecycleDaysToIA = props.s3LifecycleDaysToIA ?? 30;
    const s3LifecycleDaysToGlacier = props.s3LifecycleDaysToGlacier ?? 90;

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);

    // Create VPC or use default
    const vpc = createVpc 
      ? this.createVpc(resourcePrefix)
      : ec2.Vpc.fromLookup(this, 'DefaultVpc', { isDefault: true });

    // Create IAM role for EC2 instances
    this.instanceRole = this.createInstanceRole(resourcePrefix, uniqueSuffix);

    // Create S3 bucket for session logs
    this.sessionLogsBucket = this.createSessionLogsBucket(
      resourcePrefix, 
      uniqueSuffix, 
      s3LifecycleDaysToIA,
      s3LifecycleDaysToGlacier
    );

    // Create CloudWatch log group for session logs
    this.sessionLogsGroup = this.createSessionLogsGroup(
      resourcePrefix, 
      uniqueSuffix, 
      logRetentionDays
    );

    // Configure Session Manager logging preferences
    this.configureSessionManagerLogging();

    // Create demo EC2 instance
    this.demoInstance = this.createDemoInstance(
      resourcePrefix,
      uniqueSuffix,
      vpc,
      instanceType
    );

    // Create user policy for Session Manager access
    this.userPolicy = this.createUserPolicy(resourcePrefix, uniqueSuffix);

    // Add tags to all resources
    this.addResourceTags(resourcePrefix, props.additionalTags);

    // Output important values
    this.createOutputs(uniqueSuffix);
  }

  /**
   * Create a new VPC with public and private subnets
   */
  private createVpc(resourcePrefix: string): ec2.Vpc {
    return new ec2.Vpc(this, `${resourcePrefix}Vpc`, {
      maxAzs: 2,
      natGateways: 0, // No NAT gateways needed for Session Manager
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
        {
          cidrMask: 24,
          name: 'Private',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
      enableDnsHostnames: true,
      enableDnsSupport: true,
    });
  }

  /**
   * Create IAM role for EC2 instances with Session Manager permissions
   */
  private createInstanceRole(resourcePrefix: string, uniqueSuffix: string): iam.Role {
    const role = new iam.Role(this, `${resourcePrefix}InstanceRole`, {
      roleName: `${resourcePrefix}InstanceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for EC2 instances to use AWS Systems Manager Session Manager',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    // Add custom policy for enhanced Session Manager capabilities
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'ssm:UpdateInstanceInformation',
        'ssmmessages:CreateControlChannel',
        'ssmmessages:CreateDataChannel',
        'ssmmessages:OpenControlChannel',
        'ssmmessages:OpenDataChannel',
      ],
      resources: ['*'],
      sid: 'SessionManagerPermissions',
    }));

    // Add permissions for CloudWatch logging
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'logs:CreateLogGroup',
        'logs:CreateLogStream',
        'logs:DescribeLogGroups',
        'logs:DescribeLogStreams',
        'logs:PutLogEvents',
      ],
      resources: [
        `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/sessionmanager/*`,
      ],
      sid: 'CloudWatchLogsPermissions',
    }));

    return role;
  }

  /**
   * Create S3 bucket for session logs with security best practices
   */
  private createSessionLogsBucket(
    resourcePrefix: string, 
    uniqueSuffix: string,
    lifecycleDaysToIA: number,
    lifecycleDaysToGlacier: number
  ): s3.Bucket {
    const bucket = new s3.Bucket(this, `${resourcePrefix}SessionLogsBucket`, {
      bucketName: `${resourcePrefix.toLowerCase()}-session-logs-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      lifecycleRules: [
        {
          id: 'SessionLogsLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(lifecycleDaysToIA),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(lifecycleDaysToGlacier),
            },
          ],
        },
      ],
      serverAccessLogsPrefix: 'access-logs/',
    });

    // Add bucket policy for Session Manager service
    bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'SessionManagerBucketPolicy',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('ssm.amazonaws.com')],
      actions: ['s3:PutObject'],
      resources: [`${bucket.bucketArn}/session-logs/*`],
      conditions: {
        StringEquals: {
          's3:x-amz-acl': 'bucket-owner-full-control',
        },
      },
    }));

    bucket.addToResourcePolicy(new iam.PolicyStatement({
      sid: 'SessionManagerBucketListPolicy',
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('ssm.amazonaws.com')],
      actions: ['s3:GetBucketAcl'],
      resources: [bucket.bucketArn],
    }));

    return bucket;
  }

  /**
   * Create CloudWatch log group for session monitoring
   */
  private createSessionLogsGroup(
    resourcePrefix: string, 
    uniqueSuffix: string, 
    retentionDays: number
  ): logs.LogGroup {
    return new logs.LogGroup(this, `${resourcePrefix}SessionLogsGroup`, {
      logGroupName: `/aws/sessionmanager/${resourcePrefix.toLowerCase()}-${uniqueSuffix}`,
      retention: retentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });
  }

  /**
   * Configure Session Manager logging preferences
   */
  private configureSessionManagerLogging(): void {
    // Create SSM document for session manager logging configuration
    new ssm.CfnDocument(this, 'SessionManagerLoggingConfig', {
      documentType: 'Session',
      documentFormat: 'JSON',
      content: {
        schemaVersion: '1.0',
        description: 'Session Manager logging configuration',
        sessionType: 'Standard_Stream',
        inputs: {
          s3BucketName: this.sessionLogsBucket.bucketName,
          s3KeyPrefix: 'session-logs/',
          s3EncryptionEnabled: true,
          cloudWatchLogGroupName: this.sessionLogsGroup.logGroupName,
          cloudWatchEncryptionEnabled: true,
          cloudWatchStreamingEnabled: true,
        },
      },
    });
  }

  /**
   * Create demo EC2 instance for testing Session Manager
   */
  private createDemoInstance(
    resourcePrefix: string,
    uniqueSuffix: string,
    vpc: ec2.IVpc,
    instanceType: string
  ): ec2.Instance {
    // Get latest Amazon Linux 2 AMI
    const amzn2Ami = new ec2.AmazonLinuxImage({
      generation: ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
      cpuType: ec2.AmazonLinuxCpuType.X86_64,
    });

    // Create security group with no inbound rules (Session Manager doesn't need them)
    const securityGroup = new ec2.SecurityGroup(this, `${resourcePrefix}SecurityGroup`, {
      vpc,
      securityGroupName: `${resourcePrefix}SecurityGroup-${uniqueSuffix}`,
      description: 'Security group for Session Manager demo instance - no inbound rules needed',
      allowAllOutbound: true, // Required for SSM agent communication
    });

    // User data script to ensure SSM agent is running
    const userData = ec2.UserData.forLinux();
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      'yum install -y amazon-ssm-agent',
      'systemctl enable amazon-ssm-agent',
      'systemctl start amazon-ssm-agent',
      '# Create a test user for demonstration',
      'useradd -m -s /bin/bash testuser',
      'echo "testuser:$(openssl rand -base64 32)" | chpasswd',
      '# Add some demo files',
      'echo "Welcome to Session Manager demo instance" > /home/ec2-user/welcome.txt',
      'echo "This instance is managed via AWS Systems Manager" > /home/ec2-user/info.txt',
      'chown ec2-user:ec2-user /home/ec2-user/*.txt'
    );

    const instance = new ec2.Instance(this, `${resourcePrefix}DemoInstance`, {
      instanceName: `${resourcePrefix}DemoInstance-${uniqueSuffix}`,
      vpc,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: amzn2Ami,
      role: this.instanceRole,
      securityGroup,
      userData,
      vpcSubnets: { subnetType: ec2.SubnetType.PUBLIC }, // Can be private too
      requireImdsv2: true, // Security best practice
    });

    // Add tags for identification and access control
    cdk.Tags.of(instance).add('Purpose', 'SessionManagerTesting');
    cdk.Tags.of(instance).add('ManagedBy', 'SessionManager');

    return instance;
  }

  /**
   * Create user policy for controlled Session Manager access
   */
  private createUserPolicy(resourcePrefix: string, uniqueSuffix: string): iam.ManagedPolicy {
    return new iam.ManagedPolicy(this, `${resourcePrefix}UserPolicy`, {
      managedPolicyName: `${resourcePrefix}UserPolicy-${uniqueSuffix}`,
      description: 'Policy for users to access EC2 instances via Session Manager',
      statements: [
        // Allow starting sessions on tagged instances
        new iam.PolicyStatement({
          sid: 'StartSessionOnTaggedInstances',
          effect: iam.Effect.ALLOW,
          actions: ['ssm:StartSession'],
          resources: [`arn:aws:ec2:${this.region}:${this.account}:instance/*`],
          conditions: {
            StringEquals: {
              'ssm:resourceTag/Purpose': 'SessionManagerTesting',
            },
          },
        }),
        // Allow describing instances and getting connection status
        new iam.PolicyStatement({
          sid: 'DescribeInstances',
          effect: iam.Effect.ALLOW,
          actions: [
            'ssm:DescribeInstanceInformation',
            'ssm:DescribeInstanceAssociationsStatus',
            'ssm:GetConnectionStatus',
          ],
          resources: ['*'],
        }),
        // Allow accessing Session Manager documents
        new iam.PolicyStatement({
          sid: 'AccessSessionManagerDocuments',
          effect: iam.Effect.ALLOW,
          actions: [
            'ssm:DescribeDocumentParameters',
            'ssm:DescribeDocument',
            'ssm:GetDocument',
          ],
          resources: [`arn:aws:ssm:*:*:document/*`],
        }),
        // Allow terminating own sessions
        new iam.PolicyStatement({
          sid: 'ManageOwnSessions',
          effect: iam.Effect.ALLOW,
          actions: [
            'ssm:TerminateSession',
            'ssm:ResumeSession',
          ],
          resources: [`arn:aws:ssm:*:*:session/\${aws:username}-*`],
        }),
      ],
    });
  }

  /**
   * Add tags to all resources in the stack
   */
  private addResourceTags(resourcePrefix: string, additionalTags?: { [key: string]: string }): void {
    const defaultTags = {
      Project: resourcePrefix,
      Purpose: 'SessionManagerDemo',
      ManagedBy: 'CDK',
    };

    const allTags = { ...defaultTags, ...additionalTags };

    Object.entries(allTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Create CloudFormation outputs
   */
  private createOutputs(uniqueSuffix: string): void {
    new cdk.CfnOutput(this, 'InstanceId', {
      value: this.demoInstance.instanceId,
      description: 'ID of the demo EC2 instance',
      exportName: `${this.stackName}-InstanceId`,
    });

    new cdk.CfnOutput(this, 'InstanceRoleArn', {
      value: this.instanceRole.roleArn,
      description: 'ARN of the IAM role for EC2 instances',
      exportName: `${this.stackName}-InstanceRoleArn`,
    });

    new cdk.CfnOutput(this, 'SessionLogsBucketName', {
      value: this.sessionLogsBucket.bucketName,
      description: 'Name of the S3 bucket for session logs',
      exportName: `${this.stackName}-SessionLogsBucketName`,
    });

    new cdk.CfnOutput(this, 'SessionLogsGroupName', {
      value: this.sessionLogsGroup.logGroupName,
      description: 'Name of the CloudWatch log group for session logs',
      exportName: `${this.stackName}-SessionLogsGroupName`,
    });

    new cdk.CfnOutput(this, 'UserPolicyArn', {
      value: this.userPolicy.managedPolicyArn,
      description: 'ARN of the user policy for Session Manager access',
      exportName: `${this.stackName}-UserPolicyArn`,
    });

    new cdk.CfnOutput(this, 'StartSessionCommand', {
      value: `aws ssm start-session --target ${this.demoInstance.instanceId}`,
      description: 'Command to start a Session Manager session',
    });

    new cdk.CfnOutput(this, 'UniqueResourceSuffix', {
      value: uniqueSuffix,
      description: 'Unique suffix used for resource naming',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Create the stack with default properties
const stack = new SecureRemoteAccessStack(app, 'SecureRemoteAccessStack', {
  description: 'Secure remote access implementation using AWS Systems Manager Session Manager (uksb-1tupboc57)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Apply CDK Nag for security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

app.synth();