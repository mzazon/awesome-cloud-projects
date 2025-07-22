#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as storagegateway from 'aws-cdk-lib/aws-storagegateway';

/**
 * Properties for the HybridCloudStorageStack
 */
interface HybridCloudStorageStackProps extends cdk.StackProps {
  /**
   * Environment identifier used for resource naming
   * @default 'dev'
   */
  readonly environment?: string;

  /**
   * Instance type for the Storage Gateway EC2 instance
   * @default 'm5.large'
   */
  readonly gatewayInstanceType?: ec2.InstanceType;

  /**
   * Size of the cache storage volume in GB
   * @default 100
   */
  readonly cacheStorageSize?: number;

  /**
   * Enable S3 bucket versioning
   * @default true
   */
  readonly enableS3Versioning?: boolean;

  /**
   * CIDR blocks allowed to access NFS shares
   * @default ['10.0.0.0/8']
   */
  readonly nfsClientCidrs?: string[];

  /**
   * Whether to deploy in existing VPC or create new one
   * @default false
   */
  readonly useExistingVpc?: boolean;

  /**
   * Existing VPC ID if useExistingVpc is true
   */
  readonly existingVpcId?: string;
}

/**
 * AWS CDK Stack for Hybrid Cloud Storage with AWS Storage Gateway
 * 
 * This stack deploys a complete hybrid cloud storage solution including:
 * - S3 bucket for cloud storage backend
 * - KMS key for encryption
 * - EC2-based Storage Gateway with cache storage
 * - IAM roles and policies
 * - CloudWatch logging
 * - Security groups and networking
 */
export class HybridCloudStorageStack extends cdk.Stack {
  public readonly s3Bucket: s3.Bucket;
  public readonly storageGatewayInstance: ec2.Instance;
  public readonly gatewayRole: iam.Role;
  public readonly kmsKey: kms.Key;

  constructor(scope: Construct, id: string, props: HybridCloudStorageStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const environment = props.environment ?? 'dev';
    const gatewayInstanceType = props.gatewayInstanceType ?? ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE);
    const cacheStorageSize = props.cacheStorageSize ?? 100;
    const enableS3Versioning = props.enableS3Versioning ?? true;
    const nfsClientCidrs = props.nfsClientCidrs ?? ['10.0.0.0/8'];

    // Create VPC or use existing
    let vpc: ec2.IVpc;
    if (props.useExistingVpc && props.existingVpcId) {
      vpc = ec2.Vpc.fromLookup(this, 'ExistingVpc', {
        vpcId: props.existingVpcId
      });
    } else {
      vpc = new ec2.Vpc(this, 'HybridStorageVpc', {
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
          }
        ],
        enableDnsHostnames: true,
        enableDnsSupport: true
      });

      // Add VPC Flow Logs for security monitoring
      new ec2.FlowLog(this, 'VpcFlowLog', {
        resourceType: ec2.FlowLogResourceType.fromVpc(vpc),
        destination: ec2.FlowLogDestination.toCloudWatchLogs()
      });
    }

    // Create KMS key for encryption
    this.kmsKey = new kms.Key(this, 'StorageGatewayKmsKey', {
      description: `Storage Gateway encryption key for ${environment} environment`,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    this.kmsKey.addAlias(`storage-gateway-key-${environment}`);

    // Create S3 bucket for Storage Gateway backend
    this.s3Bucket = new s3.Bucket(this, 'StorageGatewayBucket', {
      bucketName: `storage-gateway-bucket-${environment}-${this.account}-${this.region}`,
      versioned: enableS3Versioning,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.kmsKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            }
          ]
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      autoDeleteObjects: true // Only for development environments
    });

    // Create IAM role for Storage Gateway
    this.gatewayRole = new iam.Role(this, 'StorageGatewayRole', {
      assumedBy: new iam.ServicePrincipal('storagegateway.amazonaws.com'),
      description: 'IAM role for Storage Gateway to access S3 and CloudWatch',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/StorageGatewayServiceRole')
      ]
    });

    // Add additional permissions for S3 bucket access
    this.gatewayRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
        's3:ListBucket',
        's3:GetBucketLocation',
        's3:ListMultipartUploadParts',
        's3:AbortMultipartUpload'
      ],
      resources: [
        this.s3Bucket.bucketArn,
        `${this.s3Bucket.bucketArn}/*`
      ]
    }));

    // Add KMS permissions
    this.gatewayRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'kms:Decrypt',
        'kms:GenerateDataKey'
      ],
      resources: [this.kmsKey.keyArn]
    }));

    // Create CloudWatch Log Group for Storage Gateway
    const logGroup = new logs.LogGroup(this, 'StorageGatewayLogGroup', {
      logGroupName: `/aws/storagegateway/${environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create Security Group for Storage Gateway
    const storageGatewaySecurityGroup = new ec2.SecurityGroup(this, 'StorageGatewaySecurityGroup', {
      vpc,
      description: 'Security group for Storage Gateway instance',
      allowAllOutbound: true
    });

    // Add inbound rules for Storage Gateway
    storageGatewaySecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(80),
      'HTTP for activation'
    );

    storageGatewaySecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'HTTPS for management'
    );

    // Add NFS access for specified CIDR blocks
    nfsClientCidrs.forEach((cidr, index) => {
      storageGatewaySecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(2049),
        `NFS access for ${cidr}`
      );
    });

    // Add SMB access for specified CIDR blocks
    nfsClientCidrs.forEach((cidr, index) => {
      storageGatewaySecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(445),
        `SMB access for ${cidr}`
      );
    });

    // Add iSCSI access for Volume Gateway (port 3260)
    nfsClientCidrs.forEach((cidr, index) => {
      storageGatewaySecurityGroup.addIngressRule(
        ec2.Peer.ipv4(cidr),
        ec2.Port.tcp(3260),
        `iSCSI access for ${cidr}`
      );
    });

    // Get the latest Storage Gateway AMI
    const storageGatewayAmi = ec2.MachineImage.lookup({
      name: 'aws-storage-gateway-*',
      owners: ['amazon'],
      windows: false
    });

    // Create Storage Gateway EC2 instance
    this.storageGatewayInstance = new ec2.Instance(this, 'StorageGatewayInstance', {
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC // Storage Gateway needs internet access for activation
      },
      instanceType: gatewayInstanceType,
      machineImage: storageGatewayAmi,
      securityGroup: storageGatewaySecurityGroup,
      role: this.createEc2Role(),
      userData: this.createUserData(),
      blockDevices: [
        {
          deviceName: '/dev/sda1',
          volume: ec2.BlockDeviceVolume.ebs(80, {
            volumeType: ec2.EbsDeviceVolumeType.GP3,
            encrypted: true,
            kmsKey: this.kmsKey
          })
        }
      ]
    });

    // Create and attach cache storage volume
    const cacheVolume = new ec2.Volume(this, 'CacheStorageVolume', {
      availabilityZone: this.storageGatewayInstance.instanceAvailabilityZone,
      size: cdk.Size.gibibytes(cacheStorageSize),
      volumeType: ec2.EbsDeviceVolumeType.GP3,
      encrypted: true,
      kmsKey: this.kmsKey,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Attach cache volume to instance
    new ec2.CfnVolumeAttachment(this, 'CacheVolumeAttachment', {
      instanceId: this.storageGatewayInstance.instanceId,
      volumeId: cacheVolume.volumeId,
      device: '/dev/sdf'
    });

    // Create outputs for important resources
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.s3Bucket.bucketName,
      description: 'Name of the S3 bucket for Storage Gateway backend',
      exportName: `${this.stackName}-S3BucketName`
    });

    new cdk.CfnOutput(this, 'StorageGatewayInstanceId', {
      value: this.storageGatewayInstance.instanceId,
      description: 'Instance ID of the Storage Gateway',
      exportName: `${this.stackName}-StorageGatewayInstanceId`
    });

    new cdk.CfnOutput(this, 'StorageGatewayPublicIp', {
      value: this.storageGatewayInstance.instancePublicIp,
      description: 'Public IP address of the Storage Gateway',
      exportName: `${this.stackName}-StorageGatewayPublicIp`
    });

    new cdk.CfnOutput(this, 'StorageGatewayRoleArn', {
      value: this.gatewayRole.roleArn,
      description: 'ARN of the Storage Gateway IAM role',
      exportName: `${this.stackName}-StorageGatewayRoleArn`
    });

    new cdk.CfnOutput(this, 'KmsKeyId', {
      value: this.kmsKey.keyId,
      description: 'ID of the KMS key for encryption',
      exportName: `${this.stackName}-KmsKeyId`
    });

    new cdk.CfnOutput(this, 'ActivationUrl', {
      value: `http://${this.storageGatewayInstance.instancePublicIp}/?activationRegion=${this.region}`,
      description: 'URL for Storage Gateway activation'
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'HybridCloudStorage');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Create IAM role for EC2 instance
   */
  private createEc2Role(): iam.Role {
    const ec2Role = new iam.Role(this, 'StorageGatewayInstanceRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: 'IAM role for Storage Gateway EC2 instance',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore')
      ]
    });

    // Add permissions for Storage Gateway management
    ec2Role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'storagegateway:ActivateGateway',
        'storagegateway:AddCache',
        'storagegateway:DescribeGatewayInformation',
        'storagegateway:ListLocalDisks'
      ],
      resources: ['*']
    }));

    return ec2Role;
  }

  /**
   * Create user data script for Storage Gateway instance
   */
  private createUserData(): ec2.UserData {
    const userData = ec2.UserData.forLinux();
    
    userData.addCommands(
      '#!/bin/bash',
      'yum update -y',
      
      // Install CloudWatch agent for monitoring
      'yum install -y amazon-cloudwatch-agent',
      
      // Install AWS CLI v2
      'curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"',
      'unzip awscliv2.zip',
      'sudo ./aws/install',
      
      // Configure CloudWatch agent
      'cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF',
      '{',
      '  "metrics": {',
      '    "namespace": "AWS/StorageGateway",',
      '    "metrics_collected": {',
      '      "cpu": {',
      '        "measurement": ["cpu_usage_idle", "cpu_usage_iowait"],',
      '        "metrics_collection_interval": 60',
      '      },',
      '      "disk": {',
      '        "measurement": ["used_percent"],',
      '        "metrics_collection_interval": 60,',
      '        "resources": ["*"]',
      '      },',
      '      "diskio": {',
      '        "measurement": ["io_time"],',
      '        "metrics_collection_interval": 60,',
      '        "resources": ["*"]',
      '      },',
      '      "mem": {',
      '        "measurement": ["mem_used_percent"],',
      '        "metrics_collection_interval": 60',
      '      },',
      '      "netstat": {',
      '        "measurement": ["tcp_established", "tcp_time_wait"],',
      '        "metrics_collection_interval": 60',
      '      }',
      '    }',
      '  }',
      '}',
      'EOF',
      
      // Start CloudWatch agent
      '/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s',
      
      // Signal completion
      'echo "Storage Gateway instance initialization completed" > /var/log/storage-gateway-init.log'
    );

    return userData;
  }
}

/**
 * CDK Application for Hybrid Cloud Storage with AWS Storage Gateway
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;

// Validate required parameters
if (!account) {
  throw new Error('Account ID must be provided via CDK_DEFAULT_ACCOUNT environment variable or cdk context');
}

// Create the main stack
new HybridCloudStorageStack(app, `HybridCloudStorageStack-${environment}`, {
  env: {
    account,
    region
  },
  environment,
  description: `Hybrid Cloud Storage with AWS Storage Gateway (${environment})`,
  
  // Stack-specific configuration
  gatewayInstanceType: ec2.InstanceType.of(ec2.InstanceClass.M5, ec2.InstanceSize.LARGE),
  cacheStorageSize: 100,
  enableS3Versioning: true,
  nfsClientCidrs: ['10.0.0.0/8'],
  
  // Termination protection for production
  terminationProtection: environment === 'prod'
});

// Synthesize the CDK app
app.synth();