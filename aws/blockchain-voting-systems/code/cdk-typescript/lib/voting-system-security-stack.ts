/**
 * Voting System Security Stack
 * 
 * This stack provides the security foundation for the blockchain voting system,
 * implementing defense-in-depth principles with encryption, access controls,
 * and monitoring. It creates the KMS keys, IAM roles, and security policies
 * required for secure voting operations.
 * 
 * Security Features:
 * - AWS KMS keys for encryption at rest and in transit
 * - IAM roles with least privilege access
 * - Security policies for blockchain access
 * - CloudTrail integration for audit logging
 * - GuardDuty integration for threat detection
 * - Config rules for compliance monitoring
 * 
 * Compliance Features:
 * - GDPR-compliant data protection
 * - SOC 2 Type II controls
 * - Election integrity safeguards
 * - Audit trail preservation
 * - Data residency controls
 * 
 * Author: AWS Recipe
 * Version: 1.0.0
 */

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as guardduty from 'aws-cdk-lib/aws-guardduty';
import * as config from 'aws-cdk-lib/aws-config';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Configuration interface for security settings
 */
export interface SecurityConfig {
  appName: string;
  environment: string;
  enableEncryption: boolean;
  enableKeyRotation: boolean;
  adminEmail: string;
}

/**
 * Stack properties interface
 */
export interface VotingSystemSecurityStackProps extends cdk.StackProps {
  config: SecurityConfig;
}

/**
 * Security stack for the blockchain voting system
 */
export class VotingSystemSecurityStack extends cdk.Stack {
  // Public properties for cross-stack references
  public readonly kmsKey: kms.Key;
  public readonly lambdaExecutionRole: iam.Role;
  public readonly blockchainAccessRole: iam.Role;
  public readonly apiGatewayRole: iam.Role;
  public readonly auditTrail: cloudtrail.Trail;

  // Private properties
  private readonly config: SecurityConfig;

  constructor(scope: Construct, id: string, props: VotingSystemSecurityStackProps) {
    super(scope, id, props);

    this.config = props.config;

    // Create security infrastructure
    this.createEncryptionInfrastructure();
    this.createAccessControlRoles();
    this.createAuditInfrastructure();
    this.createThreatDetection();
    this.createComplianceMonitoring();

    // Add stack outputs
    this.addStackOutputs();
  }

  /**
   * Create encryption infrastructure (KMS keys and policies)
   */
  private createEncryptionInfrastructure(): void {
    // Create KMS key for voting system encryption
    this.kmsKey = new kms.Key(this, 'VotingSystemKmsKey', {
      alias: `${this.config.appName}-encryption-key-${this.config.environment}`,
      description: 'KMS key for encrypting voting system data',
      enableKeyRotation: this.config.enableKeyRotation,
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      policy: new iam.PolicyDocument({
        statements: [
          // Allow root account full access
          new iam.PolicyStatement({
            sid: 'EnableIAMUserPermissions',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          // Allow CloudWatch Logs to use the key
          new iam.PolicyStatement({
            sid: 'AllowCloudWatchLogsAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('logs.amazonaws.com')],
            actions: [
              'kms:Encrypt',
              'kms:Decrypt',
              'kms:ReEncrypt*',
              'kms:GenerateDataKey*',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              ArnEquals: {
                'kms:EncryptionContext:aws:logs:arn': `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/lambda/${this.config.appName}-*`,
              },
            },
          }),
          // Allow S3 service to use the key
          new iam.PolicyStatement({
            sid: 'AllowS3ServiceAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': `s3.${this.region}.amazonaws.com`,
              },
            },
          }),
          // Allow DynamoDB service to use the key
          new iam.PolicyStatement({
            sid: 'AllowDynamoDBServiceAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('dynamodb.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': `dynamodb.${this.region}.amazonaws.com`,
              },
            },
          }),
          // Allow SNS service to use the key
          new iam.PolicyStatement({
            sid: 'AllowSNSServiceAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('sns.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
              'kms:DescribeKey',
            ],
            resources: ['*'],
            conditions: {
              StringEquals: {
                'kms:ViaService': `sns.${this.region}.amazonaws.com`,
              },
            },
          }),
        ],
      }),
      removalPolicy: this.config.environment === 'prod' 
        ? cdk.RemovalPolicy.RETAIN 
        : cdk.RemovalPolicy.DESTROY,
    });

    // Create KMS key alias for easier reference
    new kms.Alias(this, 'VotingSystemKmsAlias', {
      aliasName: `alias/${this.config.appName}-${this.config.environment}`,
      targetKey: this.kmsKey,
    });
  }

  /**
   * Create IAM roles with least privilege access
   */
  private createAccessControlRoles(): void {
    // Create Lambda execution role for voter authentication
    this.lambdaExecutionRole = new iam.Role(this, 'VotingLambdaExecutionRole', {
      roleName: `${this.config.appName}-lambda-execution-${this.config.environment}`,
      description: 'Execution role for voting system Lambda functions',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
      inlinePolicies: {
        VotingSystemAccess: new iam.PolicyDocument({
          statements: [
            // DynamoDB access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:BatchGetItem',
                'dynamodb:BatchWriteItem',
              ],
              resources: [
                `arn:aws:dynamodb:${this.region}:${this.account}:table/${this.config.appName}-*`,
                `arn:aws:dynamodb:${this.region}:${this.account}:table/${this.config.appName}-*/index/*`,
              ],
            }),
            // S3 access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                `arn:aws:s3:::${this.config.appName}-*`,
                `arn:aws:s3:::${this.config.appName}-*/*`,
              ],
            }),
            // KMS access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:Encrypt',
                'kms:GenerateDataKey',
                'kms:DescribeKey',
              ],
              resources: [this.kmsKey.keyArn],
            }),
            // EventBridge access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'events:PutEvents',
              ],
              resources: [
                `arn:aws:events:${this.region}:${this.account}:event-bus/${this.config.appName}-*`,
              ],
            }),
            // SNS access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
              ],
              resources: [
                `arn:aws:sns:${this.region}:${this.account}:${this.config.appName}-*`,
              ],
            }),
            // Cognito access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cognito-idp:AdminGetUser',
                'cognito-idp:AdminUpdateUserAttributes',
                'cognito-idp:AdminSetUserPassword',
                'cognito-idp:AdminCreateUser',
              ],
              resources: [
                `arn:aws:cognito-idp:${this.region}:${this.account}:userpool/*`,
              ],
            }),
            // CloudWatch Logs access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/lambda/${this.config.appName}-*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create role for blockchain access
    this.blockchainAccessRole = new iam.Role(this, 'BlockchainAccessRole', {
      roleName: `${this.config.appName}-blockchain-access-${this.config.environment}`,
      description: 'Role for accessing Amazon Managed Blockchain',
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      inlinePolicies: {
        BlockchainAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'managedblockchain:GetNetwork',
                'managedblockchain:GetNode',
                'managedblockchain:ListNodes',
                'managedblockchain:GetMember',
                'managedblockchain:CreateNode',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create API Gateway execution role
    this.apiGatewayRole = new iam.Role(this, 'ApiGatewayExecutionRole', {
      roleName: `${this.config.appName}-api-gateway-${this.config.environment}`,
      description: 'Execution role for API Gateway',
      assumedBy: new iam.ServicePrincipal('apigateway.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonAPIGatewayPushToCloudWatchLogs'),
      ],
      inlinePolicies: {
        LambdaInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
              ],
              resources: [
                `arn:aws:lambda:${this.region}:${this.account}:function:${this.config.appName}-*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create admin role for election management
    const adminRole = new iam.Role(this, 'VotingSystemAdminRole', {
      roleName: `${this.config.appName}-admin-${this.config.environment}`,
      description: 'Administrative role for voting system management',
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ArnPrincipal(`arn:aws:iam::${this.account}:root`)
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('ReadOnlyAccess'),
      ],
      inlinePolicies: {
        VotingSystemAdminAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:*',
                's3:*',
                'lambda:*',
                'events:*',
                'sns:*',
                'cognito-idp:*',
                'kms:Decrypt',
                'kms:Encrypt',
                'kms:GenerateDataKey',
                'kms:DescribeKey',
              ],
              resources: [
                `arn:aws:dynamodb:${this.region}:${this.account}:table/${this.config.appName}-*`,
                `arn:aws:s3:::${this.config.appName}-*`,
                `arn:aws:s3:::${this.config.appName}-*/*`,
                `arn:aws:lambda:${this.region}:${this.account}:function:${this.config.appName}-*`,
                `arn:aws:events:${this.region}:${this.account}:event-bus/${this.config.appName}-*`,
                `arn:aws:sns:${this.region}:${this.account}:${this.config.appName}-*`,
                `arn:aws:cognito-idp:${this.region}:${this.account}:userpool/*`,
                this.kmsKey.keyArn,
              ],
            }),
          ],
        }),
      },
    });

    // Create auditor role for read-only access
    const auditorRole = new iam.Role(this, 'VotingSystemAuditorRole', {
      roleName: `${this.config.appName}-auditor-${this.config.environment}`,
      description: 'Auditor role for read-only access to voting system',
      assumedBy: new iam.ArnPrincipal(`arn:aws:iam::${this.account}:root`),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('ReadOnlyAccess'),
      ],
      inlinePolicies: {
        VotingSystemAuditorAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:GetItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:BatchGetItem',
                's3:GetObject',
                's3:ListBucket',
                'kms:Decrypt',
                'kms:DescribeKey',
              ],
              resources: [
                `arn:aws:dynamodb:${this.region}:${this.account}:table/${this.config.appName}-*`,
                `arn:aws:s3:::${this.config.appName}-*`,
                `arn:aws:s3:::${this.config.appName}-*/*`,
                this.kmsKey.keyArn,
              ],
            }),
          ],
        }),
      },
    });
  }

  /**
   * Create audit infrastructure (CloudTrail)
   */
  private createAuditInfrastructure(): void {
    // Create S3 bucket for CloudTrail logs
    const auditBucket = new s3.Bucket(this, 'AuditLogsBucket', {
      bucketName: `${this.config.appName}-audit-logs-${this.config.environment}-${this.account}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.kmsKey,
      versioned: true,
      enforceSSL: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'AuditLogRetention',
          expiration: cdk.Duration.days(2555), // 7 years retention
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Create CloudTrail for audit logging
    this.auditTrail = new cloudtrail.Trail(this, 'VotingSystemAuditTrail', {
      trailName: `${this.config.appName}-audit-trail-${this.config.environment}`,
      bucket: auditBucket,
      s3KeyPrefix: 'cloudtrail-logs/',
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      encryptionKey: this.kmsKey,
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: new logs.LogGroup(this, 'AuditLogGroup', {
        logGroupName: `/aws/cloudtrail/${this.config.appName}-${this.config.environment}`,
        retention: logs.RetentionDays.ONE_YEAR,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    });

    // Add event selectors for specific resource monitoring
    this.auditTrail.addEventSelector(cloudtrail.DataResourceType.S3_OBJECT, [
      `${this.config.appName}-*/votes/*`,
      `${this.config.appName}-*/elections/*`,
    ]);

    this.auditTrail.addLambdaEventSelector([
      `arn:aws:lambda:${this.region}:${this.account}:function:${this.config.appName}-*`,
    ]);
  }

  /**
   * Create threat detection infrastructure (GuardDuty)
   */
  private createThreatDetection(): void {
    // Enable GuardDuty for threat detection
    const guardDutyDetector = new guardduty.CfnDetector(this, 'VotingSystemGuardDuty', {
      enable: true,
      findingPublishingFrequency: 'FIFTEEN_MINUTES',
      dataSources: {
        s3Logs: {
          enable: true,
        },
        kubernetes: {
          auditLogs: {
            enable: true,
          },
        },
        malwareProtection: {
          scanEc2InstanceWithFindings: {
            ebsVolumes: true,
          },
        },
      },
    });

    // Create custom threat intelligence set (if needed)
    // This would include IP addresses, domains, and other IoCs
    // specific to voting system threats
  }

  /**
   * Create compliance monitoring (Config)
   */
  private createComplianceMonitoring(): void {
    // Create S3 bucket for Config
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `${this.config.appName}-config-${this.config.environment}-${this.account}`,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: this.kmsKey,
      versioned: true,
      enforceSSL: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Config delivery channel
    const configDeliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      s3BucketName: configBucket.bucketName,
      configSnapshotDeliveryProperties: {
        deliveryFrequency: 'TwentyFour_Hours',
      },
    });

    // Create Config configuration recorder
    const configRecorder = new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      roleArn: this.createConfigRole().roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
      },
    });

    // Create Config rules for compliance monitoring
    const encryptionRule = new config.ManagedRule(this, 'EncryptionComplianceRule', {
      identifier: config.ManagedRuleIdentifiers.S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED,
      description: 'Checks that S3 buckets have server-side encryption enabled',
      inputParameters: {
        bucketName: `${this.config.appName}-*`,
      },
    });

    const dynamoEncryptionRule = new config.ManagedRule(this, 'DynamoEncryptionRule', {
      identifier: config.ManagedRuleIdentifiers.DYNAMODB_TABLE_ENCRYPTION_ENABLED,
      description: 'Checks that DynamoDB tables have encryption enabled',
    });

    const lambdaVpcRule = new config.ManagedRule(this, 'LambdaVpcRule', {
      identifier: config.ManagedRuleIdentifiers.LAMBDA_FUNCTION_PUBLIC_ACCESS_PROHIBITED,
      description: 'Checks that Lambda functions are not publicly accessible',
    });

    // Add dependencies
    configDeliveryChannel.addDependency(configRecorder);
    encryptionRule.addDependency(configRecorder);
    dynamoEncryptionRule.addDependency(configRecorder);
    lambdaVpcRule.addDependency(configRecorder);
  }

  /**
   * Create IAM role for Config service
   */
  private createConfigRole(): iam.Role {
    return new iam.Role(this, 'ConfigRole', {
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
    });
  }

  /**
   * Add stack outputs
   */
  private addStackOutputs(): void {
    new cdk.CfnOutput(this, 'KmsKeyId', {
      value: this.kmsKey.keyId,
      description: 'KMS key ID for voting system encryption',
    });

    new cdk.CfnOutput(this, 'KmsKeyArn', {
      value: this.kmsKey.keyArn,
      description: 'KMS key ARN for voting system encryption',
    });

    new cdk.CfnOutput(this, 'LambdaExecutionRoleArn', {
      value: this.lambdaExecutionRole.roleArn,
      description: 'Lambda execution role ARN',
    });

    new cdk.CfnOutput(this, 'BlockchainAccessRoleArn', {
      value: this.blockchainAccessRole.roleArn,
      description: 'Blockchain access role ARN',
    });

    new cdk.CfnOutput(this, 'ApiGatewayRoleArn', {
      value: this.apiGatewayRole.roleArn,
      description: 'API Gateway execution role ARN',
    });

    new cdk.CfnOutput(this, 'AuditTrailArn', {
      value: this.auditTrail.trailArn,
      description: 'CloudTrail audit trail ARN',
    });
  }
}