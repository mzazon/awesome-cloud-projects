#!/usr/bin/env node
import 'source-map-support/register';
import { App, Stack, StackProps, Tags, Duration, RemovalPolicy } from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as identitystore from 'aws-cdk-lib/aws-identitystore';
import * as sso from 'aws-cdk-lib/aws-sso';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';

/**
 * Interface for stack configuration properties
 */
interface IdentityFederationStackProps extends StackProps {
  /** External Identity Provider SAML metadata URL */
  readonly externalIdpMetadataUrl?: string;
  /** Development AWS Account ID for permission assignments */
  readonly developmentAccountId?: string;
  /** Production AWS Account ID for permission assignments */
  readonly productionAccountId?: string;
  /** Environment name for resource naming */
  readonly environmentName?: string;
  /** Enable audit logging (default: true) */
  readonly enableAuditLogging?: boolean;
  /** CloudTrail log retention in days (default: 365) */
  readonly auditLogRetentionDays?: number;
}

/**
 * AWS CDK Stack for Identity Federation with AWS SSO (IAM Identity Center)
 * 
 * This stack implements enterprise-grade identity federation using AWS IAM Identity Center,
 * providing centralized user management, role-based access control, and comprehensive
 * audit capabilities across multiple AWS accounts.
 * 
 * Key Features:
 * - IAM Identity Center instance with external identity provider integration
 * - Permission sets for different user roles (Developer, Administrator, Read-Only)
 * - Comprehensive audit logging via CloudTrail and CloudWatch
 * - Multi-account access assignments
 * - Security monitoring and alerting
 */
export class IdentityFederationStack extends Stack {
  // Core Identity Center resources
  public readonly identityCenterInstance: sso.CfnInstance;
  public readonly identityStore: identitystore.CfnIdentityStore;
  
  // Permission Sets for role-based access
  public readonly developerPermissionSet: sso.CfnPermissionSet;
  public readonly administratorPermissionSet: sso.CfnPermissionSet;
  public readonly readOnlyPermissionSet: sso.CfnPermissionSet;
  
  // Audit and monitoring resources
  public readonly auditBucket: s3.Bucket;
  public readonly auditTrail: cloudtrail.Trail;
  public readonly auditLogGroup: logs.LogGroup;
  public readonly monitoringDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: IdentityFederationStackProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const config = {
      environmentName: props.environmentName || 'production',
      enableAuditLogging: props.enableAuditLogging !== false,
      auditLogRetentionDays: props.auditLogRetentionDays || 365,
      externalIdpMetadataUrl: props.externalIdpMetadataUrl || 'https://your-idp.example.com/metadata',
      developmentAccountId: props.developmentAccountId,
      productionAccountId: props.productionAccountId
    };

    // Create IAM Identity Center instance
    this.identityCenterInstance = this.createIdentityCenterInstance(config.environmentName);
    
    // Create identity store
    this.identityStore = this.createIdentityStore();
    
    // Create permission sets for different user roles
    this.developerPermissionSet = this.createDeveloperPermissionSet();
    this.administratorPermissionSet = this.createAdministratorPermissionSet();
    this.readOnlyPermissionSet = this.createReadOnlyPermissionSet();
    
    // Set up external identity provider integration
    this.setupExternalIdentityProvider(config.externalIdpMetadataUrl);
    
    // Configure audit logging if enabled
    if (config.enableAuditLogging) {
      this.auditBucket = this.createAuditBucket();
      this.auditTrail = this.createAuditTrail(this.auditBucket);
      this.auditLogGroup = this.createAuditLogGroup(config.auditLogRetentionDays);
      this.monitoringDashboard = this.createMonitoringDashboard();
      this.setupSecurityAlerting();
    }
    
    // Create account assignments if account IDs are provided
    if (config.developmentAccountId) {
      this.createAccountAssignments(config.developmentAccountId, 'development');
    }
    
    if (config.productionAccountId) {
      this.createAccountAssignments(config.productionAccountId, 'production');
    }
    
    // Apply common tags to all resources
    Tags.of(this).add('Project', 'IdentityFederation');
    Tags.of(this).add('Environment', config.environmentName);
    Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Creates the IAM Identity Center instance
   */
  private createIdentityCenterInstance(environmentName: string): sso.CfnInstance {
    return new sso.CfnInstance(this, 'IdentityCenterInstance', {
      name: `enterprise-sso-${environmentName}`,
      tags: [
        {
          key: 'Environment',
          value: environmentName
        },
        {
          key: 'Purpose',
          value: 'IdentityFederation'
        }
      ]
    });
  }

  /**
   * Creates the identity store for user and group management
   */
  private createIdentityStore(): identitystore.CfnIdentityStore {
    return new identitystore.CfnIdentityStore(this, 'IdentityStore', {
      identityStoreId: this.identityCenterInstance.attrIdentityStoreId
    });
  }

  /**
   * Creates developer permission set with limited permissions
   */
  private createDeveloperPermissionSet(): sso.CfnPermissionSet {
    const permissionSet = new sso.CfnPermissionSet(this, 'DeveloperPermissionSet', {
      instanceArn: this.identityCenterInstance.attrInstanceArn,
      name: 'Developer',
      description: 'Development environment access with limited permissions',
      sessionDuration: 'PT8H', // 8 hours
      managedPolicies: [
        'arn:aws:iam::aws:policy/PowerUserAccess'
      ],
      inlinePolicy: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Deny',
            Action: [
              'iam:*',
              'organizations:*',
              'account:*',
              'billing:*',
              'aws-portal:*'
            ],
            Resource: '*'
          },
          {
            Effect: 'Allow',
            Action: [
              'iam:GetRole',
              'iam:GetRolePolicy',
              'iam:ListRoles',
              'iam:ListRolePolicies',
              'iam:PassRole'
            ],
            Resource: '*',
            Condition: {
              StringLike: {
                'iam:PassedToService': [
                  'lambda.amazonaws.com',
                  'ec2.amazonaws.com',
                  'ecs-tasks.amazonaws.com'
                ]
              }
            }
          }
        ]
      },
      tags: [
        {
          key: 'Role',
          value: 'Developer'
        }
      ]
    });

    return permissionSet;
  }

  /**
   * Creates administrator permission set with full access
   */
  private createAdministratorPermissionSet(): sso.CfnPermissionSet {
    const permissionSet = new sso.CfnPermissionSet(this, 'AdministratorPermissionSet', {
      instanceArn: this.identityCenterInstance.attrInstanceArn,
      name: 'Administrator',
      description: 'Full administrative access across all accounts',
      sessionDuration: 'PT4H', // 4 hours - shorter for high-privilege access
      managedPolicies: [
        'arn:aws:iam::aws:policy/AdministratorAccess'
      ],
      tags: [
        {
          key: 'Role',
          value: 'Administrator'
        }
      ]
    });

    return permissionSet;
  }

  /**
   * Creates read-only permission set for business users
   */
  private createReadOnlyPermissionSet(): sso.CfnPermissionSet {
    const permissionSet = new sso.CfnPermissionSet(this, 'ReadOnlyPermissionSet', {
      instanceArn: this.identityCenterInstance.attrInstanceArn,
      name: 'ReadOnly',
      description: 'Read-only access for business users and auditors',
      sessionDuration: 'PT12H', // 12 hours
      managedPolicies: [
        'arn:aws:iam::aws:policy/ReadOnlyAccess'
      ],
      inlinePolicy: {
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              's3:GetObject',
              's3:ListBucket',
              'cloudwatch:GetMetricStatistics',
              'cloudwatch:ListMetrics',
              'logs:DescribeLogGroups',
              'logs:DescribeLogStreams',
              'logs:FilterLogEvents',
              'quicksight:*'
            ],
            Resource: '*'
          }
        ]
      },
      tags: [
        {
          key: 'Role',
          value: 'ReadOnly'
        }
      ]
    });

    return permissionSet;
  }

  /**
   * Sets up external identity provider integration
   */
  private setupExternalIdentityProvider(metadataUrl: string): void {
    // Note: The CfnIdentityProvider construct is used here for SAML configuration
    // In practice, you would need to replace the metadata URL with your actual IdP
    new sso.CfnIdentityProvider(this, 'ExternalIdentityProvider', {
      instanceArn: this.identityCenterInstance.attrInstanceArn,
      name: 'ExternalSAMLProvider',
      identityProviderType: 'SAML',
      // Note: This would need to be configured with actual SAML metadata
      // The exact configuration depends on your identity provider
    });
  }

  /**
   * Creates S3 bucket for audit logs
   */
  private createAuditBucket(): s3.Bucket {
    const bucket = new s3.Bucket(this, 'AuditLogsBucket', {
      bucketName: `identity-audit-logs-${this.account}-${Math.random().toString(36).substring(7)}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.RETAIN, // Retain audit logs
      lifecycleRules: [
        {
          id: 'AuditLogLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90)
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: Duration.days(365)
            }
          ]
        }
      ]
    });

    // Add bucket policy for CloudTrail
    bucket.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
      actions: ['s3:PutObject'],
      resources: [bucket.arnForObjects('*')],
      conditions: {
        StringEquals: {
          's3:x-amz-acl': 'bucket-owner-full-control'
        }
      }
    }));

    bucket.addToResourcePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
      actions: ['s3:GetBucketAcl'],
      resources: [bucket.bucketArn]
    }));

    return bucket;
  }

  /**
   * Creates CloudTrail for audit logging
   */
  private createAuditTrail(auditBucket: s3.Bucket): cloudtrail.Trail {
    return new cloudtrail.Trail(this, 'IdentityFederationAuditTrail', {
      trailName: 'identity-federation-audit-trail',
      bucket: auditBucket,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      eventRuleProps: {
        includeManagementEvents: true,
        readWriteType: cloudtrail.ReadWriteType.ALL,
        includeDataEvents: [
          {
            bucket: auditBucket,
            objectPrefix: 'AWSLogs/'
          }
        ]
      }
    });
  }

  /**
   * Creates CloudWatch log group for Identity Center audit logs
   */
  private createAuditLogGroup(retentionDays: number): logs.LogGroup {
    return new logs.LogGroup(this, 'SSOAuditLogGroup', {
      logGroupName: '/aws/sso/audit-logs',
      retention: logs.RetentionDays.ONE_YEAR,
      removalPolicy: RemovalPolicy.RETAIN
    });
  }

  /**
   * Creates CloudWatch dashboard for monitoring
   */
  private createMonitoringDashboard(): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'IdentityFederationDashboard', {
      dashboardName: 'IdentityFederationDashboard',
      defaultInterval: Duration.hours(1)
    });

    // Add widgets for monitoring sign-in activities
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Identity Center Sign-in Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/SSO',
            metricName: 'SignInAttempts',
            statistic: 'Sum'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/SSO',
            metricName: 'SignInSuccesses',
            statistic: 'Sum'
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/SSO',
            metricName: 'SignInFailures',
            statistic: 'Sum'
          })
        ],
        width: 24
      })
    );

    return dashboard;
  }

  /**
   * Sets up security alerting for suspicious activities
   */
  private setupSecurityAlerting(): void {
    // Create SNS topic for security alerts
    const alertsTopic = new sns.Topic(this, 'IdentityAlertsTopc', {
      topicName: 'identity-federation-alerts',
      displayName: 'Identity Federation Security Alerts'
    });

    // Create alarm for excessive sign-in failures
    const signInFailureAlarm = new cloudwatch.Alarm(this, 'SignInFailureAlarm', {
      alarmName: 'IdentityFederation-ExcessiveSignInFailures',
      alarmDescription: 'Alert when there are excessive sign-in failures',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSO',
        metricName: 'SignInFailures',
        statistic: 'Sum'
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    signInFailureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertsTopic));

    // Create alarm for unusual sign-in patterns
    const unusualActivityAlarm = new cloudwatch.Alarm(this, 'UnusualActivityAlarm', {
      alarmName: 'IdentityFederation-UnusualActivity',
      alarmDescription: 'Alert for unusual sign-in activity patterns',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SSO',
        metricName: 'SignInAttempts',
        statistic: 'Sum'
      }),
      threshold: 100,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
    });

    unusualActivityAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertsTopic));
  }

  /**
   * Creates account assignments for different environments
   */
  private createAccountAssignments(accountId: string, environment: string): void {
    // Note: Account assignments typically require actual user/group IDs
    // These would be created after users and groups are provisioned in the identity store
    
    // This is a placeholder structure - actual assignments would be created
    // after SCIM provisioning or manual user/group creation
    
    // Example structure for when user/group IDs are available:
    /*
    new sso.CfnAccountAssignment(this, `DeveloperAssignment-${environment}`, {
      instanceArn: this.identityCenterInstance.attrInstanceArn,
      permissionSetArn: this.developerPermissionSet.attrPermissionSetArn,
      principalId: 'group-id-for-developers',
      principalType: 'GROUP',
      targetId: accountId,
      targetType: 'AWS_ACCOUNT'
    });
    */
  }
}

/**
 * CDK Application entry point
 */
const app = new App();

// Get configuration from CDK context or environment variables
const developmentAccountId = app.node.tryGetContext('developmentAccountId') || process.env.DEVELOPMENT_ACCOUNT_ID;
const productionAccountId = app.node.tryGetContext('productionAccountId') || process.env.PRODUCTION_ACCOUNT_ID;
const externalIdpMetadataUrl = app.node.tryGetContext('externalIdpMetadataUrl') || process.env.EXTERNAL_IDP_METADATA_URL;
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'production';

// Create the Identity Federation stack
new IdentityFederationStack(app, 'IdentityFederationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  developmentAccountId,
  productionAccountId,
  externalIdpMetadataUrl,
  environmentName,
  enableAuditLogging: true,
  auditLogRetentionDays: 365,
  description: 'AWS Identity Federation with IAM Identity Center - Enterprise SSO Solution'
});

// Synthesize the CloudFormation templates
app.synth();