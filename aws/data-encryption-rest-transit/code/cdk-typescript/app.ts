#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';

/**
 * Stack for implementing comprehensive data encryption at rest and in transit
 * 
 * This stack creates:
 * - Customer-managed KMS key for encryption
 * - S3 bucket with server-side encryption using KMS
 * - RDS MySQL instance with encryption at rest
 * - EC2 instance with encrypted EBS volumes
 * - Secrets Manager for secure credential storage
 * - DynamoDB table with encryption
 * - CloudTrail for audit logging
 * - SSL/TLS certificate management (optional)
 * 
 * Security features implemented:
 * - Defense in depth with multiple encryption layers
 * - Centralized key management with AWS KMS
 * - Comprehensive audit logging
 * - Network isolation and security groups
 * - Least privilege IAM permissions
 */
export class DataEncryptionRestTransitStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // Create VPC for network isolation
    const vpc = new ec2.Vpc(this, 'EncryptionDemoVpc', {
      maxAzs: 2,
      cidr: '10.0.0.0/16',
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
        {
          cidrMask: 24,
          name: 'Database',
          subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
        },
      ],
    });

    // Create customer-managed KMS key for encryption
    const encryptionKey = new kms.Key(this, 'EncryptionKey', {
      description: 'Customer managed key for data encryption demo',
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      enableKeyRotation: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'Enable root permissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'Allow use of the key for encryption services',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:CreateGrant',
              'kms:DescribeKey',
            ],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create alias for the KMS key
    const keyAlias = new kms.Alias(this, 'EncryptionKeyAlias', {
      aliasName: `alias/encryption-demo-${randomSuffix}`,
      targetKey: encryptionKey,
    });

    // Create S3 bucket with server-side encryption using KMS
    const encryptedBucket = new s3.Bucket(this, 'EncryptedDataBucket', {
      bucketName: `encrypted-data-bucket-${randomSuffix}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: encryptionKey,
      bucketKeyEnabled: true, // Reduces KMS API calls and costs
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
    });

    // Create CloudTrail bucket for audit logging
    const cloudtrailBucket = new s3.Bucket(this, 'CloudTrailBucket', {
      bucketName: `cloudtrail-logs-${randomSuffix}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: encryptionKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
    });

    // Create database credentials in Secrets Manager
    const dbCredentials = new secretsmanager.Secret(this, 'DatabaseCredentials', {
      secretName: `database-credentials-${randomSuffix}`,
      description: 'Database credentials for encryption demo',
      encryptionKey: encryptionKey,
      generateSecretString: {
        secretStringTemplate: JSON.stringify({
          username: 'admin',
          engine: 'mysql',
          port: 3306,
          dbname: 'encrypteddemo',
        }),
        generateStringKey: 'password',
        excludeCharacters: '"@/\\\'',
        passwordLength: 16,
        requireEachIncludedType: true,
      },
    });

    // Create security group for RDS
    const dbSecurityGroup = new ec2.SecurityGroup(this, 'DatabaseSecurityGroup', {
      vpc,
      description: 'Security group for encrypted RDS database',
      allowAllOutbound: false,
    });

    // Allow MySQL access from within VPC
    dbSecurityGroup.addIngressRule(
      ec2.Peer.ipv4(vpc.vpcCidrBlock),
      ec2.Port.tcp(3306),
      'Allow MySQL access from within VPC'
    );

    // Create RDS subnet group
    const dbSubnetGroup = new rds.SubnetGroup(this, 'DatabaseSubnetGroup', {
      vpc,
      description: 'Subnet group for encrypted RDS demo',
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
    });

    // Create encrypted RDS MySQL instance
    const database = new rds.DatabaseInstance(this, 'EncryptedDatabase', {
      instanceIdentifier: `encrypted-db-${randomSuffix}`,
      engine: rds.DatabaseInstanceEngine.mysql({
        version: rds.MysqlEngineVersion.VER_8_0,
      }),
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      credentials: rds.Credentials.fromSecret(dbCredentials),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PRIVATE_ISOLATED,
      },
      securityGroups: [dbSecurityGroup],
      subnetGroup: dbSubnetGroup,
      storageEncrypted: true,
      storageEncryptionKey: encryptionKey,
      allocatedStorage: 20,
      storageType: rds.StorageType.GP2,
      backupRetention: cdk.Duration.days(7),
      deletionProtection: false, // For demo purposes only
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
    });

    // Update secret with RDS endpoint
    new secretsmanager.SecretTargetAttachment(this, 'SecretTargetAttachment', {
      secret: dbCredentials,
      target: database,
    });

    // Create security group for EC2
    const ec2SecurityGroup = new ec2.SecurityGroup(this, 'EC2SecurityGroup', {
      vpc,
      description: 'Security group for encrypted EC2 demo',
      allowAllOutbound: true,
    });

    // Allow SSH and HTTPS access
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'Allow SSH access'
    );
    ec2SecurityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(443),
      'Allow HTTPS access'
    );

    // Create IAM role for EC2 instance
    const ec2Role = new iam.Role(this, 'EC2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject', 's3:DeleteObject'],
              resources: [encryptedBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [encryptedBucket.bucketArn],
            }),
          ],
        }),
        KMSAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:GenerateDataKey',
                'kms:DescribeKey',
              ],
              resources: [encryptionKey.keyArn],
            }),
          ],
        }),
        SecretsManagerAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['secretsmanager:GetSecretValue'],
              resources: [dbCredentials.secretArn],
            }),
          ],
        }),
      },
    });

    // Create instance profile for EC2
    const instanceProfile = new iam.CfnInstanceProfile(this, 'EC2InstanceProfile', {
      roles: [ec2Role.roleName],
    });

    // Create key pair for EC2 access
    const keyPair = new ec2.KeyPair(this, 'EncryptionDemoKeyPair', {
      keyPairName: `encryption-demo-key-${randomSuffix}`,
      type: ec2.KeyPairType.RSA,
      format: ec2.KeyPairFormat.PEM,
    });

    // Create EC2 instance with encrypted EBS volumes
    const ec2Instance = new ec2.Instance(this, 'EncryptedEC2Instance', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T3, ec2.InstanceSize.MICRO),
      machineImage: ec2.MachineImage.latestAmazonLinux2(),
      vpc,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
      securityGroup: ec2SecurityGroup,
      keyName: keyPair.keyPairName,
      role: ec2Role,
      blockDevices: [
        {
          deviceName: '/dev/xvda',
          volume: ec2.BlockDeviceVolume.ebs(8, {
            volumeType: ec2.EbsDeviceVolumeType.GP2,
            encrypted: true,
            kmsKey: encryptionKey,
            deleteOnTermination: true,
          }),
        },
      ],
      userData: ec2.UserData.forLinux(),
    });

    // Create encrypted DynamoDB table
    const dynamoTable = new dynamodb.Table(this, 'EncryptedDynamoTable', {
      tableName: `encrypted-table-${randomSuffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      encryption: dynamodb.TableEncryption.CUSTOMER_MANAGED,
      encryptionKey: encryptionKey,
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
    });

    // Create Lambda function with encrypted environment variables
    const encryptedLambda = new lambda.Function(this, 'EncryptedLambdaFunction', {
      functionName: `encrypted-lambda-${randomSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        
        exports.handler = async (event) => {
          console.log('Lambda function with encrypted environment variables');
          
          return {
            statusCode: 200,
            body: JSON.stringify({
              message: 'Function executed successfully with encrypted environment',
              timestamp: new Date().toISOString()
            })
          };
        };
      `),
      environment: {
        BUCKET_NAME: encryptedBucket.bucketName,
        DB_SECRET_ARN: dbCredentials.secretArn,
        DYNAMO_TABLE_NAME: dynamoTable.tableName,
      },
      environmentEncryption: encryptionKey,
    });

    // Grant Lambda permissions to access encrypted resources
    encryptedBucket.grantReadWrite(encryptedLambda);
    dbCredentials.grantRead(encryptedLambda);
    dynamoTable.grantReadWriteData(encryptedLambda);

    // Create Application Load Balancer for TLS termination
    const alb = new elbv2.ApplicationLoadBalancer(this, 'EncryptedALB', {
      vpc,
      internetFacing: true,
      loadBalancerName: `encrypted-alb-${randomSuffix}`,
    });

    // Create target group for EC2 instance
    const targetGroup = new elbv2.ApplicationTargetGroup(this, 'EC2TargetGroup', {
      vpc,
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [new elbv2.InstanceTarget(ec2Instance)],
      healthCheck: {
        enabled: true,
        path: '/',
        protocol: elbv2.Protocol.HTTP,
      },
    });

    // Add HTTP listener (in production, redirect to HTTPS)
    const httpListener = alb.addListener('HTTPListener', {
      port: 80,
      protocol: elbv2.ApplicationProtocol.HTTP,
      defaultTargetGroups: [targetGroup],
    });

    // Create CloudTrail for encryption events logging
    const trail = new cloudtrail.Trail(this, 'EncryptionEventsTrail', {
      trailName: `encryption-demo-trail-${randomSuffix}`,
      bucket: cloudtrailBucket,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      eventSelectors: [
        {
          readWriteType: cloudtrail.ReadWriteType.ALL,
          includeManagementEvents: true,
          dataResources: [
            {
              type: 'AWS::KMS::Key',
              values: ['arn:aws:kms:*:*:key/*'],
            },
            {
              type: 'AWS::S3::Object',
              values: [`${encryptedBucket.bucketArn}/*`],
            },
          ],
        },
      ],
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'KMSKeyId', {
      value: encryptionKey.keyId,
      description: 'KMS Key ID for encryption',
    });

    new cdk.CfnOutput(this, 'KMSKeyAlias', {
      value: keyAlias.aliasName,
      description: 'KMS Key Alias',
    });

    new cdk.CfnOutput(this, 'S3BucketName', {
      value: encryptedBucket.bucketName,
      description: 'Encrypted S3 Bucket Name',
    });

    new cdk.CfnOutput(this, 'RDSEndpoint', {
      value: database.instanceEndpoint.hostname,
      description: 'RDS Database Endpoint',
    });

    new cdk.CfnOutput(this, 'SecretArn', {
      value: dbCredentials.secretArn,
      description: 'Database Credentials Secret ARN',
    });

    new cdk.CfnOutput(this, 'EC2InstanceId', {
      value: ec2Instance.instanceId,
      description: 'EC2 Instance ID with Encrypted EBS',
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: dynamoTable.tableName,
      description: 'Encrypted DynamoDB Table Name',
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: encryptedLambda.functionName,
      description: 'Lambda Function with Encrypted Environment Variables',
    });

    new cdk.CfnOutput(this, 'LoadBalancerDNS', {
      value: alb.loadBalancerDnsName,
      description: 'Application Load Balancer DNS Name',
    });

    new cdk.CfnOutput(this, 'KeyPairName', {
      value: keyPair.keyPairName,
      description: 'Key Pair Name for EC2 Access',
    });

    new cdk.CfnOutput(this, 'CloudTrailName', {
      value: trail.trailName,
      description: 'CloudTrail Name for Encryption Events',
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'DataEncryptionDemo');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Purpose', 'EncryptionAtRestAndInTransit');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the stack
new DataEncryptionRestTransitStack(app, 'DataEncryptionRestTransitStack', {
  description: 'Comprehensive data encryption at rest and in transit implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Application', 'DataEncryptionDemo');
cdk.Tags.of(app).add('ManagedBy', 'CDK');
cdk.Tags.of(app).add('Owner', 'DevOps');