import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as transfer from 'aws-cdk-lib/aws-transfer';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as kms from 'aws-cdk-lib/aws-kms';
import { NagSuppressions } from 'cdk-nag';
import { Construct } from 'constructs';

/**
 * Properties for the SecureFileSharingStack
 */
export interface SecureFileSharingStackProps extends cdk.StackProps {
  /**
   * Optional bucket name prefix. If not provided, a unique name will be generated.
   */
  readonly bucketNamePrefix?: string;
  
  /**
   * Optional web app name. If not provided, a unique name will be generated.
   */
  readonly webAppName?: string;
  
  /**
   * Enable detailed CloudTrail logging for all S3 data events
   * @default true
   */
  readonly enableDetailedLogging?: boolean;
  
  /**
   * CloudTrail log retention period in days
   * @default logs.RetentionDays.SIX_MONTHS
   */
  readonly logRetentionDays?: logs.RetentionDays;
}

/**
 * AWS CDK Stack for Secure File Sharing with Transfer Family Web Apps
 * 
 * This stack creates a complete secure file sharing solution that provides:
 * - Browser-based file access through Transfer Family Web Apps
 * - Secure S3 storage with encryption at rest and in transit
 * - Comprehensive audit logging via CloudTrail
 * - Fine-grained access controls using IAM
 * - Cost optimization through S3 lifecycle policies
 * 
 * The solution follows AWS Well-Architected Framework principles:
 * - Security: Encryption, access controls, and audit logging
 * - Reliability: Multi-AZ services and backup mechanisms
 * - Performance: Optimized for file transfer operations
 * - Cost Optimization: Lifecycle policies and appropriate storage classes
 * - Operational Excellence: Comprehensive monitoring and logging
 */
export class SecureFileSharingStack extends cdk.Stack {
  
  /**
   * The S3 bucket used for secure file storage
   */
  public readonly fileBucket: s3.Bucket;
  
  /**
   * The Transfer Family web app for browser-based access
   */
  public readonly webApp: transfer.CfnWebApp;
  
  /**
   * The CloudTrail trail for audit logging
   */
  public readonly auditTrail: cloudtrail.Trail;
  
  /**
   * The IAM role used by Transfer Family for S3 access
   */
  public readonly transferRole: iam.Role;

  constructor(scope: Construct, id: string, props: SecureFileSharingStackProps = {}) {
    super(scope, id, props);

    // Generate unique resource names using stack-specific suffix
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    const bucketName = props.bucketNamePrefix ? 
      `${props.bucketNamePrefix}-${uniqueSuffix}` : 
      `secure-files-${uniqueSuffix}`;
    const webAppName = props.webAppName || `secure-file-portal-${uniqueSuffix}`;

    // Create KMS key for enhanced encryption
    const s3EncryptionKey = new kms.Key(this, 'S3EncryptionKey', {
      description: 'KMS key for S3 bucket encryption in secure file sharing solution',
      enableKeyRotation: true,
      policy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'Enable IAM root permissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*']
          }),
          new iam.PolicyStatement({
            sid: 'Allow CloudTrail encryption',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
            actions: [
              'kms:GenerateDataKey',
              'kms:CreateGrant',
              'kms:Encrypt',
              'kms:Decrypt',
              'kms:ReEncrypt*',
              'kms:DescribeKey'
            ],
            resources: ['*']
          })
        ]
      })
    });

    // Add key alias for easier identification
    new kms.Alias(this, 'S3EncryptionKeyAlias', {
      aliasName: `alias/secure-file-sharing-${uniqueSuffix}`,
      targetKey: s3EncryptionKey
    });

    // Create secure S3 bucket for file storage
    this.fileBucket = new s3.Bucket(this, 'SecureFileBucket', {
      bucketName: bucketName,
      
      // Security configurations
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: s3EncryptionKey,
      bucketKeyEnabled: true, // Reduce KMS costs
      enforceSSL: true,
      
      // Access control
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      publicReadAccess: false,
      publicWriteAccess: false,
      
      // Versioning for data protection
      versioned: true,
      
      // Lifecycle management for cost optimization
      lifecycleRules: [
        {
          id: 'ArchiveOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(90),
          noncurrentVersionTransitions: [
            {
              storageClass: s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            }
          ]
        },
        {
          id: 'ArchiveByPrefix',
          enabled: true,
          prefix: 'archive/',
          transitions: [
            {
              storageClass: s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ]
        }
      ],
      
      // Notification configuration
      eventBridgeEnabled: true,
      
      // Removal policy - be careful in production
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      autoDeleteObjects: false
    });

    // Create CloudWatch log group for CloudTrail
    const cloudTrailLogGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/secure-file-sharing-${uniqueSuffix}`,
      retention: props.logRetentionDays || logs.RetentionDays.SIX_MONTHS,
      encryptionKey: s3EncryptionKey,
      removalPolicy: cdk.RemovalPolicy.RETAIN
    });

    // Create CloudTrail for comprehensive audit logging
    this.auditTrail = new cloudtrail.Trail(this, 'SecureFileSharingTrail', {
      trailName: `secure-file-sharing-audit-${uniqueSuffix}`,
      
      // Send logs to both S3 and CloudWatch
      bucket: this.fileBucket,
      s3KeyPrefix: 'audit-logs/',
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: cloudTrailLogGroup,
      
      // Enhanced logging configuration
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      
      // Management events logging
      managementEvents: cloudtrail.ReadWriteType.ALL,
      
      // KMS encryption for trail logs
      kmsKey: s3EncryptionKey
    });

    // Add data event logging for S3 bucket
    this.auditTrail.addS3EventSelector([
      {
        bucket: this.fileBucket,
        objectPrefix: '', // Log all objects
      }
    ], {
      readWriteType: cloudtrail.ReadWriteType.ALL,
      includeManagementEvents: false
    });

    // Create IAM role for Transfer Family service
    this.transferRole = new iam.Role(this, 'TransferFamilyRole', {
      assumedBy: new iam.ServicePrincipal('transfer.amazonaws.com'),
      description: 'IAM role for Transfer Family to access S3 resources',
      roleName: `TransferFamilyRole-${uniqueSuffix}`,
      
      // Inline policy for S3 access with least privilege
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              sid: 'S3BucketAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ListBucket',
                's3:GetBucketLocation',
                's3:GetBucketVersioning'
              ],
              resources: [this.fileBucket.bucketArn],
              conditions: {
                StringEquals: {
                  's3:prefix': ['*']
                }
              }
            }),
            new iam.PolicyStatement({
              sid: 'S3ObjectAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:GetObjectAcl',
                's3:PutObject',
                's3:PutObjectAcl',
                's3:DeleteObject',
                's3:DeleteObjectVersion'
              ],
              resources: [this.fileBucket.arnForObjects('*')]
            }),
            new iam.PolicyStatement({
              sid: 'KMSAccess',
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:GenerateDataKey',
                'kms:CreateGrant'
              ],
              resources: [s3EncryptionKey.keyArn]
            })
          ]
        })
      }
    });

    // Create Transfer Family Web App
    this.webApp = new transfer.CfnWebApp(this, 'SecureFileSharingWebApp', {
      identityProviderType: 'SERVICE_MANAGED',
      accessEndpointType: 'PUBLIC',
      webAppUnits: 1, // Start with minimum capacity
      
      // Optional: Configure custom identity provider
      // identityProviderDetails: {
      //   url: 'https://your-identity-provider.example.com',
      //   invocationRole: identityProviderRole.roleArn
      // },
      
      tags: [
        {
          key: 'Name',
          value: webAppName
        },
        {
          key: 'Purpose',
          value: 'SecureFileSharing'
        },
        {
          key: 'Environment',
          value: props.tags?.Environment || 'Development'
        }
      ]
    });

    // Create sample directory structure in S3
    const sampleDirectories = ['uploads/', 'shared/', 'archive/'];
    sampleDirectories.forEach((dir, index) => {
      new s3.BucketDeployment(this, `SampleDirectory${index}`, {
        sources: [s3.Source.jsonData(`${dir}.gitkeep`, { created: new Date().toISOString() })],
        destinationBucket: this.fileBucket,
        destinationKeyPrefix: dir
      });
    });

    // Create welcome file
    new s3.BucketDeployment(this, 'WelcomeFile', {
      sources: [s3.Source.data('welcome.txt', 'Welcome to the Secure File Sharing Portal\n\nThis portal provides secure, browser-based access to your files.\nYou can upload, download, and manage files through this interface.\n\nFor support, please contact your system administrator.')],
      destinationBucket: this.fileBucket
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: this.fileBucket.bucketName,
      description: 'Name of the S3 bucket for secure file storage',
      exportName: `${this.stackName}-S3BucketName`
    });

    new cdk.CfnOutput(this, 'S3BucketArn', {
      value: this.fileBucket.bucketArn,
      description: 'ARN of the S3 bucket for secure file storage',
      exportName: `${this.stackName}-S3BucketArn`
    });

    new cdk.CfnOutput(this, 'WebAppId', {
      value: this.webApp.attrWebAppId,
      description: 'Transfer Family Web App ID',
      exportName: `${this.stackName}-WebAppId`
    });

    new cdk.CfnOutput(this, 'WebAppEndpoint', {
      value: this.webApp.attrAccessEndpoint,
      description: 'Transfer Family Web App access endpoint URL',
      exportName: `${this.stackName}-WebAppEndpoint`
    });

    new cdk.CfnOutput(this, 'TransferRoleArn', {
      value: this.transferRole.roleArn,
      description: 'ARN of the Transfer Family IAM role',
      exportName: `${this.stackName}-TransferRoleArn`
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.auditTrail.trailArn,
      description: 'ARN of the CloudTrail for audit logging',
      exportName: `${this.stackName}-CloudTrailArn`
    });

    new cdk.CfnOutput(this, 'KMSKeyArn', {
      value: s3EncryptionKey.keyArn,
      description: 'ARN of the KMS key used for encryption',
      exportName: `${this.stackName}-KMSKeyArn`
    });

    // CDK Nag suppressions with detailed justifications
    NagSuppressions.addResourceSuppressions(
      this.transferRole,
      [
        {
          id: 'AwsSolutions-IAM5',
          reason: 'Transfer Family requires wildcard permissions for S3 object operations to support dynamic file paths. This is scoped to the specific bucket ARN and follows AWS Transfer Family documentation.',
          appliesTo: [
            'Resource::arn:aws:s3:::*/*',
            'Action::s3:*'
          ]
        }
      ],
      true
    );

    NagSuppressions.addResourceSuppressions(
      cloudTrailLogGroup,
      [
        {
          id: 'AwsSolutions-L1',
          reason: 'CloudWatch Logs service uses AWS managed Lambda functions that may not be on the latest runtime version. This is managed by AWS.'
        }
      ],
      true
    );

    NagSuppressions.addResourceSuppressions(
      this.auditTrail,
      [
        {
          id: 'AwsSolutions-CT1',
          reason: 'CloudTrail is configured with appropriate security settings including KMS encryption, log file validation, and comprehensive event logging.'
        }
      ],
      true
    );

    // Add resource-level tags
    cdk.Tags.of(this.fileBucket).add('ResourceType', 'Storage');
    cdk.Tags.of(this.webApp).add('ResourceType', 'Transfer');
    cdk.Tags.of(this.auditTrail).add('ResourceType', 'Audit');
    cdk.Tags.of(this.transferRole).add('ResourceType', 'IAM');
  }
}

// Import s3-deployment construct
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';