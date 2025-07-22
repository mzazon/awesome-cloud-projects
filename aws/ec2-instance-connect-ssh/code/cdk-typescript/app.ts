#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_ec2 as ec2,
  aws_iam as iam,
  aws_cloudtrail as cloudtrail,
  aws_s3 as s3,
  aws_logs as logs,
  CfnOutput,
  RemovalPolicy,
  Stack,
  StackProps,
  Tags
} from 'aws-cdk-lib';

/**
 * Properties for the EC2 Instance Connect Stack
 */
interface Ec2InstanceConnectStackProps extends StackProps {
  /**
   * The VPC to deploy resources into. If not provided, the default VPC will be used.
   */
  readonly vpc?: ec2.IVpc;
  
  /**
   * Whether to create EC2 Instance Connect Endpoint for private instance access
   * @default true
   */
  readonly createInstanceConnectEndpoint?: boolean;
  
  /**
   * Whether to enable CloudTrail logging for audit purposes
   * @default true
   */
  readonly enableCloudTrail?: boolean;
  
  /**
   * The instance type for EC2 instances
   * @default t3.micro
   */
  readonly instanceType?: ec2.InstanceType;
  
  /**
   * Key prefix for resource naming
   * @default 'ec2-connect'
   */
  readonly resourcePrefix?: string;
}

/**
 * CDK Stack for implementing EC2 Instance Connect secure SSH access
 * 
 * This stack creates:
 * - VPC with public and private subnets
 * - Security groups for SSH access
 * - IAM policies and roles for EC2 Instance Connect
 * - EC2 instances in both public and private subnets
 * - EC2 Instance Connect Endpoint for private access
 * - CloudTrail for audit logging
 */
export class Ec2InstanceConnectStack extends Stack {
  public readonly vpc: ec2.Vpc;
  public readonly publicInstance: ec2.Instance;
  public readonly privateInstance: ec2.Instance;
  public readonly instanceConnectEndpoint?: ec2.CfnInstanceConnectEndpoint;
  public readonly cloudTrail?: cloudtrail.Trail;
  public readonly connectPolicy: iam.ManagedPolicy;
  public readonly connectUser: iam.User;

  constructor(scope: Construct, id: string, props: Ec2InstanceConnectStackProps = {}) {
    super(scope, id, props);

    const {
      vpc: existingVpc,
      createInstanceConnectEndpoint = true,
      enableCloudTrail = true,
      instanceType = ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      resourcePrefix = 'ec2-connect'
    } = props;

    // Create or use existing VPC
    this.vpc = existingVpc || this.createVpc(resourcePrefix);

    // Create security group for SSH access
    const sshSecurityGroup = this.createSecurityGroup(resourcePrefix);

    // Create IAM resources for EC2 Instance Connect
    const { policy, user } = this.createIamResources(resourcePrefix);
    this.connectPolicy = policy;
    this.connectUser = user;

    // Get the latest Amazon Linux 2023 AMI
    const machineImage = ec2.MachineImage.latestAmazonLinux2023({
      cpuType: ec2.AmazonLinuxCpuType.X86_64,
    });

    // Create public EC2 instance
    this.publicInstance = this.createPublicInstance({
      resourcePrefix,
      machineImage,
      instanceType,
      securityGroup: sshSecurityGroup,
      subnet: this.vpc.publicSubnets[0]
    });

    // Create private EC2 instance
    this.privateInstance = this.createPrivateInstance({
      resourcePrefix,
      machineImage,
      instanceType,
      securityGroup: sshSecurityGroup,
      subnet: this.vpc.privateSubnets[0]
    });

    // Create EC2 Instance Connect Endpoint for private instance access
    if (createInstanceConnectEndpoint) {
      this.instanceConnectEndpoint = this.createInstanceConnectEndpoint(
        resourcePrefix,
        sshSecurityGroup
      );
    }

    // Enable CloudTrail for audit logging
    if (enableCloudTrail) {
      this.cloudTrail = this.createCloudTrail(resourcePrefix);
    }

    // Create outputs for easy access to resource information
    this.createOutputs();

    // Add tags to all resources
    this.addTags(resourcePrefix);
  }

  /**
   * Creates a VPC with public and private subnets
   */
  private createVpc(resourcePrefix: string): ec2.Vpc {
    return new ec2.Vpc(this, 'Vpc', {
      vpcName: `${resourcePrefix}-vpc`,
      ipAddresses: ec2.IpAddresses.cidr('10.0.0.0/16'),
      maxAzs: 2,
      natGateways: 1,
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
   * Creates a security group allowing SSH access
   */
  private createSecurityGroup(resourcePrefix: string): ec2.SecurityGroup {
    const securityGroup = new ec2.SecurityGroup(this, 'SshSecurityGroup', {
      vpc: this.vpc,
      securityGroupName: `${resourcePrefix}-ssh-sg`,
      description: 'Security group for EC2 Instance Connect SSH access',
      allowAllOutbound: true,
    });

    // Allow SSH access from anywhere (restrict as needed for production)
    securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access for EC2 Instance Connect'
    );

    return securityGroup;
  }

  /**
   * Creates IAM resources for EC2 Instance Connect
   */
  private createIamResources(resourcePrefix: string): { policy: iam.ManagedPolicy; user: iam.User } {
    // Create IAM policy for EC2 Instance Connect
    const policy = new iam.ManagedPolicy(this, 'InstanceConnectPolicy', {
      managedPolicyName: `${resourcePrefix}-policy`,
      description: 'Policy for EC2 Instance Connect access',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['ec2-instance-connect:SendSSHPublicKey'],
          resources: ['*'],
          conditions: {
            StringEquals: {
              'ec2:osuser': 'ec2-user',
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:DescribeInstances',
            'ec2:DescribeVpcs',
            'ec2:DescribeInstanceConnectEndpoints',
          ],
          resources: ['*'],
        }),
      ],
    });

    // Create IAM user for testing (in production, use IAM roles or identity federation)
    const user = new iam.User(this, 'InstanceConnectUser', {
      userName: `${resourcePrefix}-user`,
      managedPolicies: [policy],
    });

    // Create access key for the user
    new iam.AccessKey(this, 'UserAccessKey', {
      user,
    });

    return { policy, user };
  }

  /**
   * Creates a public EC2 instance with Instance Connect support
   */
  private createPublicInstance(params: {
    resourcePrefix: string;
    machineImage: ec2.IMachineImage;
    instanceType: ec2.InstanceType;
    securityGroup: ec2.SecurityGroup;
    subnet: ec2.ISubnet;
  }): ec2.Instance {
    const { resourcePrefix, machineImage, instanceType, securityGroup, subnet } = params;

    const instance = new ec2.Instance(this, 'PublicInstance', {
      vpc: this.vpc,
      instanceType,
      machineImage,
      securityGroup,
      vpcSubnets: { subnets: [subnet] },
      instanceName: `${resourcePrefix}-public-instance`,
      // EC2 Instance Connect is pre-installed on Amazon Linux 2023
      userData: ec2.UserData.forLinux(),
    });

    // Ensure the instance has a public IP for direct SSH access
    instance.instance.associatePublicIpAddress = true;

    return instance;
  }

  /**
   * Creates a private EC2 instance for testing Instance Connect Endpoint
   */
  private createPrivateInstance(params: {
    resourcePrefix: string;
    machineImage: ec2.IMachineImage;
    instanceType: ec2.InstanceType;
    securityGroup: ec2.SecurityGroup;
    subnet: ec2.ISubnet;
  }): ec2.Instance {
    const { resourcePrefix, machineImage, instanceType, securityGroup, subnet } = params;

    return new ec2.Instance(this, 'PrivateInstance', {
      vpc: this.vpc,
      instanceType,
      machineImage,
      securityGroup,
      vpcSubnets: { subnets: [subnet] },
      instanceName: `${resourcePrefix}-private-instance`,
      // EC2 Instance Connect is pre-installed on Amazon Linux 2023
      userData: ec2.UserData.forLinux(),
    });
  }

  /**
   * Creates an EC2 Instance Connect Endpoint for private instance access
   */
  private createInstanceConnectEndpoint(
    resourcePrefix: string,
    securityGroup: ec2.SecurityGroup
  ): ec2.CfnInstanceConnectEndpoint {
    return new ec2.CfnInstanceConnectEndpoint(this, 'InstanceConnectEndpoint', {
      subnetId: this.vpc.privateSubnets[0].subnetId,
      securityGroupIds: [securityGroup.securityGroupId],
      tags: [
        {
          key: 'Name',
          value: `${resourcePrefix}-endpoint`,
        },
      ],
    });
  }

  /**
   * Creates CloudTrail for auditing EC2 Instance Connect usage
   */
  private createCloudTrail(resourcePrefix: string): cloudtrail.Trail {
    // Create S3 bucket for CloudTrail logs
    const cloudTrailBucket = new s3.Bucket(this, 'CloudTrailBucket', {
      bucketName: `${resourcePrefix}-cloudtrail-${this.account}-${this.region}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      enforceSSL: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'delete-old-logs',
          enabled: true,
          expiration: cdk.Duration.days(90),
        },
      ],
    });

    // Create CloudWatch log group for CloudTrail
    const logGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/${resourcePrefix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create CloudTrail
    const trail = new cloudtrail.Trail(this, 'CloudTrail', {
      trailName: `${resourcePrefix}-trail`,
      bucket: cloudTrailBucket,
      cloudWatchLogGroup: logGroup,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
    });

    // Add event selectors for EC2 Instance Connect API calls
    trail.addEventSelector({
      readWriteType: cloudtrail.ReadWriteType.ALL,
      includeManagementEvents: true,
      dataResources: [
        {
          type: 'AWS::EC2InstanceConnect::SendSSHPublicKey',
          values: ['*'],
        },
      ],
    });

    return trail;
  }

  /**
   * Creates CloudFormation outputs for important resource information
   */
  private createOutputs(): void {
    new CfnOutput(this, 'VpcId', {
      value: this.vpc.vpcId,
      description: 'VPC ID',
      exportName: `${this.stackName}-VpcId`,
    });

    new CfnOutput(this, 'PublicInstanceId', {
      value: this.publicInstance.instanceId,
      description: 'Public EC2 Instance ID',
      exportName: `${this.stackName}-PublicInstanceId`,
    });

    new CfnOutput(this, 'PublicInstanceIp', {
      value: this.publicInstance.instancePublicIp,
      description: 'Public EC2 Instance IP',
      exportName: `${this.stackName}-PublicInstanceIp`,
    });

    new CfnOutput(this, 'PrivateInstanceId', {
      value: this.privateInstance.instanceId,
      description: 'Private EC2 Instance ID',
      exportName: `${this.stackName}-PrivateInstanceId`,
    });

    new CfnOutput(this, 'PrivateInstanceIp', {
      value: this.privateInstance.instancePrivateIp,
      description: 'Private EC2 Instance IP',
      exportName: `${this.stackName}-PrivateInstanceIp`,
    });

    if (this.instanceConnectEndpoint) {
      new CfnOutput(this, 'InstanceConnectEndpointId', {
        value: this.instanceConnectEndpoint.attrId,
        description: 'EC2 Instance Connect Endpoint ID',
        exportName: `${this.stackName}-InstanceConnectEndpointId`,
      });
    }

    new CfnOutput(this, 'IamPolicyArn', {
      value: this.connectPolicy.managedPolicyArn,
      description: 'IAM Policy ARN for EC2 Instance Connect',
      exportName: `${this.stackName}-IamPolicyArn`,
    });

    new CfnOutput(this, 'IamUserName', {
      value: this.connectUser.userName,
      description: 'IAM User for EC2 Instance Connect testing',
      exportName: `${this.stackName}-IamUserName`,
    });

    if (this.cloudTrail) {
      new CfnOutput(this, 'CloudTrailArn', {
        value: this.cloudTrail.trailArn,
        description: 'CloudTrail ARN for audit logging',
        exportName: `${this.stackName}-CloudTrailArn`,
      });
    }

    // Output connection commands for easy testing
    new CfnOutput(this, 'ConnectToPublicInstance', {
      value: `aws ec2-instance-connect ssh --instance-id ${this.publicInstance.instanceId} --os-user ec2-user`,
      description: 'Command to connect to public instance',
    });

    new CfnOutput(this, 'ConnectToPrivateInstance', {
      value: `aws ec2-instance-connect ssh --instance-id ${this.privateInstance.instanceId} --os-user ec2-user --connection-type eice`,
      description: 'Command to connect to private instance via endpoint',
    });
  }

  /**
   * Adds tags to all resources in the stack
   */
  private addTags(resourcePrefix: string): void {
    Tags.of(this).add('Project', 'EC2InstanceConnect');
    Tags.of(this).add('Environment', 'Demo');
    Tags.of(this).add('Purpose', 'SecureSSHAccess');
    Tags.of(this).add('ResourcePrefix', resourcePrefix);
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'ec2-connect';
const enableCloudTrail = app.node.tryGetContext('enableCloudTrail') !== 'false';
const createInstanceConnectEndpoint = app.node.tryGetContext('createInstanceConnectEndpoint') !== 'false';

// Create the stack
new Ec2InstanceConnectStack(app, 'Ec2InstanceConnectStack', {
  resourcePrefix,
  enableCloudTrail,
  createInstanceConnectEndpoint,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'CDK Stack for EC2 Instance Connect secure SSH access implementation',
});

// Synthesize the CDK app
app.synth();