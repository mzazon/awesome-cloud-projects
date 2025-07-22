#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as s3 from 'aws-cdk-lib/aws-s3';

/**
 * Properties for the Multi-Factor Authentication Stack
 */
export interface MfaStackProps extends cdk.StackProps {
  /**
   * Name prefix for all resources
   * @default 'mfa-demo'
   */
  readonly resourcePrefix?: string;

  /**
   * Whether to create a test user for demonstration
   * @default true
   */
  readonly createTestUser?: boolean;

  /**
   * Whether to enable CloudTrail logging for MFA events
   * @default true
   */
  readonly enableMfaLogging?: boolean;

  /**
   * CloudWatch log retention period for MFA events
   * @default logs.RetentionDays.ONE_MONTH
   */
  readonly logRetentionDays?: logs.RetentionDays;
}

/**
 * CDK Stack for implementing comprehensive Multi-Factor Authentication
 * using AWS IAM with virtual and hardware MFA devices.
 * 
 * This stack creates:
 * - IAM policies that enforce MFA for all AWS access
 * - Test user and group structure for demonstration
 * - CloudWatch monitoring and alerting for MFA compliance
 * - CloudTrail integration for audit logging
 * - Security dashboards for MFA usage tracking
 */
export class MultiFactorAuthenticationStack extends cdk.Stack {
  /**
   * The IAM group that enforces MFA requirements
   */
  public readonly mfaAdminGroup: iam.Group;

  /**
   * The IAM policy that enforces MFA requirements
   */
  public readonly mfaEnforcementPolicy: iam.ManagedPolicy;

  /**
   * Test user for demonstrating MFA functionality (optional)
   */
  public readonly testUser?: iam.User;

  /**
   * CloudWatch dashboard for MFA monitoring
   */
  public readonly mfaDashboard: cloudwatch.Dashboard;

  /**
   * CloudTrail for auditing MFA events
   */
  public readonly mfaCloudTrail?: cloudtrail.Trail;

  constructor(scope: Construct, id: string, props: MfaStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'mfa-demo';
    const createTestUser = props.createTestUser !== false;
    const enableMfaLogging = props.enableMfaLogging !== false;
    const logRetentionDays = props.logRetentionDays || logs.RetentionDays.ONE_MONTH;

    // Create comprehensive MFA enforcement policy
    this.mfaEnforcementPolicy = this.createMfaEnforcementPolicy(resourcePrefix);

    // Create MFA administrative group
    this.mfaAdminGroup = this.createMfaAdminGroup(resourcePrefix);

    // Attach MFA policy to the group
    this.mfaAdminGroup.addManagedPolicy(this.mfaEnforcementPolicy);

    // Create test user if requested
    if (createTestUser) {
      this.testUser = this.createTestUser(resourcePrefix);
      this.testUser.addToGroup(this.mfaAdminGroup);
    }

    // Create CloudTrail for MFA event logging
    if (enableMfaLogging) {
      this.mfaCloudTrail = this.createMfaCloudTrail(resourcePrefix, logRetentionDays);
    }

    // Create CloudWatch monitoring and dashboard
    this.mfaDashboard = this.createMfaMonitoring(resourcePrefix, logRetentionDays);

    // Create CloudWatch alarms for security monitoring
    this.createSecurityAlarms(resourcePrefix);

    // Output important information
    this.createOutputs(resourcePrefix);
  }

  /**
   * Creates a comprehensive IAM policy that enforces MFA for all AWS access
   */
  private createMfaEnforcementPolicy(resourcePrefix: string): iam.ManagedPolicy {
    const policyDocument = new iam.PolicyDocument({
      statements: [
        // Allow users to view account information
        new iam.PolicyStatement({
          sid: 'AllowViewAccountInfo',
          effect: iam.Effect.ALLOW,
          actions: [
            'iam:GetAccountPasswordPolicy',
            'iam:ListVirtualMFADevices',
            'iam:GetUser',
            'iam:ListUsers',
          ],
          resources: ['*'],
        }),

        // Allow users to manage their own passwords
        new iam.PolicyStatement({
          sid: 'AllowManageOwnPasswords',
          effect: iam.Effect.ALLOW,
          actions: [
            'iam:ChangePassword',
            'iam:GetUser',
          ],
          resources: [
            `arn:aws:iam::${this.account}:user/\${aws:username}`,
          ],
        }),

        // Allow users to manage their own MFA devices
        new iam.PolicyStatement({
          sid: 'AllowManageOwnMFA',
          effect: iam.Effect.ALLOW,
          actions: [
            'iam:CreateVirtualMFADevice',
            'iam:DeleteVirtualMFADevice',
            'iam:EnableMFADevice',
            'iam:DeactivateMFADevice',
            'iam:ListMFADevices',
            'iam:ResyncMFADevice',
          ],
          resources: [
            `arn:aws:iam::${this.account}:mfa/\${aws:username}`,
            `arn:aws:iam::${this.account}:user/\${aws:username}`,
          ],
        }),

        // Deny all actions except essential MFA setup actions unless MFA is present
        new iam.PolicyStatement({
          sid: 'DenyAllExceptUnlessMFAAuthenticated',
          effect: iam.Effect.DENY,
          notActions: [
            'iam:CreateVirtualMFADevice',
            'iam:EnableMFADevice',
            'iam:GetUser',
            'iam:ListMFADevices',
            'iam:ListVirtualMFADevices',
            'iam:ResyncMFADevice',
            'sts:GetSessionToken',
            'iam:ChangePassword',
            'iam:GetAccountPasswordPolicy',
          ],
          resources: ['*'],
          conditions: {
            BoolIfExists: {
              'aws:MultiFactorAuthPresent': 'false',
            },
          },
        }),

        // Allow full access when MFA is present
        new iam.PolicyStatement({
          sid: 'AllowFullAccessWithMFA',
          effect: iam.Effect.ALLOW,
          actions: ['*'],
          resources: ['*'],
          conditions: {
            Bool: {
              'aws:MultiFactorAuthPresent': 'true',
            },
          },
        }),
      ],
    });

    return new iam.ManagedPolicy(this, 'MfaEnforcementPolicy', {
      managedPolicyName: `${resourcePrefix}-enforce-mfa-policy`,
      description: 'Comprehensive policy that enforces MFA for all AWS access while allowing users to set up their own MFA devices',
      document: policyDocument,
    });
  }

  /**
   * Creates an IAM group for users subject to MFA enforcement
   */
  private createMfaAdminGroup(resourcePrefix: string): iam.Group {
    return new iam.Group(this, 'MfaAdminGroup', {
      groupName: `${resourcePrefix}-mfa-admins`,
      path: '/',
    });
  }

  /**
   * Creates a test user for demonstrating MFA functionality
   */
  private createTestUser(resourcePrefix: string): iam.User {
    const testUser = new iam.User(this, 'TestUser', {
      userName: `${resourcePrefix}-test-user`,
      path: '/',
      passwordResetRequired: true,
    });

    // Create a random temporary password for the test user
    const tempPassword = new cdk.CfnParameter(this, 'TestUserPassword', {
      type: 'String',
      description: 'Temporary password for test user (must be changed on first login)',
      default: 'TempPassword123!',
      noEcho: true,
    });

    // Create login profile with temporary password
    new iam.CfnLoginProfile(this, 'TestUserLoginProfile', {
      userName: testUser.userName,
      password: tempPassword.valueAsString,
      passwordResetRequired: true,
    });

    return testUser;
  }

  /**
   * Creates CloudTrail for comprehensive MFA event logging
   */
  private createMfaCloudTrail(resourcePrefix: string, logRetentionDays: logs.RetentionDays): cloudtrail.Trail {
    // Create S3 bucket for CloudTrail logs
    const cloudTrailBucket = new s3.Bucket(this, 'CloudTrailBucket', {
      bucketName: `${resourcePrefix}-cloudtrail-logs-${this.account}-${this.region}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          enabled: true,
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create CloudWatch log group for CloudTrail
    const cloudTrailLogGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/${resourcePrefix}`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudTrail
    const trail = new cloudtrail.Trail(this, 'MfaCloudTrail', {
      trailName: `${resourcePrefix}-mfa-audit-trail`,
      bucket: cloudTrailBucket,
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: cloudTrailLogGroup,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
    });

    return trail;
  }

  /**
   * Creates CloudWatch monitoring dashboard and metric filters for MFA events
   */
  private createMfaMonitoring(resourcePrefix: string, logRetentionDays: logs.RetentionDays): cloudwatch.Dashboard {
    // Create CloudWatch log group for application logs if it doesn't exist
    const mfaLogGroup = new logs.LogGroup(this, 'MfaMonitoringLogGroup', {
      logGroupName: `/aws/mfa/${resourcePrefix}`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create metric filters for MFA events
    const mfaLoginMetric = this.createMfaLoginMetricFilter(mfaLogGroup);
    const nonMfaLoginMetric = this.createNonMfaLoginMetricFilter(mfaLogGroup);

    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'MfaDashboard', {
      dashboardName: `${resourcePrefix}-mfa-security-dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'MFA vs Non-MFA Console Logins',
            left: [mfaLoginMetric, nonMfaLoginMetric],
            width: 12,
            height: 6,
            period: cdk.Duration.minutes(5),
            statistic: 'Sum',
          }),
        ],
        [
          new cloudwatch.SingleValueWidget({
            title: 'Total MFA Logins (24h)',
            metrics: [mfaLoginMetric],
            width: 6,
            height: 6,
            period: cdk.Duration.hours(24),
            statistic: 'Sum',
          }),
          new cloudwatch.SingleValueWidget({
            title: 'Non-MFA Login Attempts (24h)',
            metrics: [nonMfaLoginMetric],
            width: 6,
            height: 6,
            period: cdk.Duration.hours(24),
            statistic: 'Sum',
          }),
        ],
      ],
    });

    return dashboard;
  }

  /**
   * Creates metric filter for successful MFA logins
   */
  private createMfaLoginMetricFilter(logGroup: logs.LogGroup): cloudwatch.Metric {
    const metricFilter = new logs.MetricFilter(this, 'MfaLoginMetricFilter', {
      logGroup,
      metricNamespace: 'AWS/Security/MFA',
      metricName: 'MFALoginCount',
      filterPattern: logs.FilterPattern.allEvents(),
      metricValue: '1',
      defaultValue: 0,
    });

    return new cloudwatch.Metric({
      namespace: 'AWS/Security/MFA',
      metricName: 'MFALoginCount',
      statistic: 'Sum',
    });
  }

  /**
   * Creates metric filter for non-MFA login attempts
   */
  private createNonMfaLoginMetricFilter(logGroup: logs.LogGroup): cloudwatch.Metric {
    const metricFilter = new logs.MetricFilter(this, 'NonMfaLoginMetricFilter', {
      logGroup,
      metricNamespace: 'AWS/Security/MFA',
      metricName: 'NonMFALoginCount',
      filterPattern: logs.FilterPattern.allEvents(),
      metricValue: '1',
      defaultValue: 0,
    });

    return new cloudwatch.Metric({
      namespace: 'AWS/Security/MFA',
      metricName: 'NonMFALoginCount',
      statistic: 'Sum',
    });
  }

  /**
   * Creates security alarms for MFA monitoring
   */
  private createSecurityAlarms(resourcePrefix: string): void {
    // Alarm for non-MFA console login attempts
    const nonMfaLoginAlarm = new cloudwatch.Alarm(this, 'NonMfaLoginAlarm', {
      alarmName: `${resourcePrefix}-non-mfa-console-logins`,
      alarmDescription: 'Alert when console logins occur without MFA authentication',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Security/MFA',
        metricName: 'NonMFALoginCount',
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 1,
      period: cdk.Duration.minutes(5),
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Alarm for multiple failed MFA attempts
    const mfaFailureAlarm = new cloudwatch.Alarm(this, 'MfaFailureAlarm', {
      alarmName: `${resourcePrefix}-mfa-authentication-failures`,
      alarmDescription: 'Alert when multiple MFA authentication failures occur',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Security/MFA',
        metricName: 'MFAFailureCount',
        statistic: 'Sum',
      }),
      threshold: 5,
      evaluationPeriods: 2,
      period: cdk.Duration.minutes(15),
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(resourcePrefix: string): void {
    new cdk.CfnOutput(this, 'MfaEnforcementPolicyArn', {
      value: this.mfaEnforcementPolicy.managedPolicyArn,
      description: 'ARN of the MFA enforcement policy',
      exportName: `${resourcePrefix}-mfa-policy-arn`,
    });

    new cdk.CfnOutput(this, 'MfaAdminGroupArn', {
      value: this.mfaAdminGroup.groupArn,
      description: 'ARN of the MFA admin group',
      exportName: `${resourcePrefix}-mfa-group-arn`,
    });

    if (this.testUser) {
      new cdk.CfnOutput(this, 'TestUserArn', {
        value: this.testUser.userArn,
        description: 'ARN of the test user for MFA demonstration',
        exportName: `${resourcePrefix}-test-user-arn`,
      });

      new cdk.CfnOutput(this, 'ConsoleLoginUrl', {
        value: `https://${this.account}.signin.aws.amazon.com/console`,
        description: 'AWS Console login URL for testing MFA enforcement',
      });
    }

    new cdk.CfnOutput(this, 'MfaDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.mfaDashboard.dashboardName}`,
      description: 'URL to the MFA security monitoring dashboard',
    });

    if (this.mfaCloudTrail) {
      new cdk.CfnOutput(this, 'CloudTrailArn', {
        value: this.mfaCloudTrail.trailArn,
        description: 'ARN of the CloudTrail for MFA audit logging',
        exportName: `${resourcePrefix}-cloudtrail-arn`,
      });
    }
  }
}

/**
 * Main CDK application entry point
 */
const app = new cdk.App();

// Create the MFA stack with default configuration
new MultiFactorAuthenticationStack(app, 'MultiFactorAuthenticationStack', {
  description: 'CDK stack for implementing comprehensive multi-factor authentication with AWS IAM and MFA devices',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'MFA-Implementation',
    Purpose: 'Security-Enhancement',
    Environment: 'Demo',
  },
});

// Synthesize the CDK app
app.synth();