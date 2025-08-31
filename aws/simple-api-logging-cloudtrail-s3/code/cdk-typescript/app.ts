#!/usr/bin/env node

/**
 * Simple API Logging with CloudTrail and S3
 * 
 * This CDK application creates a comprehensive audit logging solution that captures
 * all AWS API activities and stores them securely in S3 with real-time monitoring
 * through CloudWatch Logs. The solution includes automated alerting for root account
 * usage and follows AWS security best practices.
 * 
 * Architecture:
 * - CloudTrail trail for multi-region API logging
 * - S3 bucket for long-term audit log storage with encryption
 * - CloudWatch Logs for real-time log streaming and analysis
 * - CloudWatch alarms for root account usage monitoring
 * - SNS notifications for security alerts
 * 
 * Security Features:
 * - Server-side encryption (SSE-S3) for S3 bucket
 * - S3 bucket versioning for audit trail protection
 * - Public access blocked on S3 bucket
 * - Log file validation enabled for integrity verification
 * - Least privilege IAM policies for CloudTrail service role
 * - Source ARN conditions in bucket policy for enhanced security
 * 
 * Cost Optimization:
 * - CloudWatch Logs retention set to 30 days
 * - S3 lifecycle policies can be added for long-term cost management
 * - Uses standard S3 storage class (can be optimized with Intelligent Tiering)
 * 
 * @author AWS CDK Team
 * @version 1.0.0
 * @since 2025-01-16
 */

import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Construct } from 'constructs';

/**
 * Interface defining configuration properties for the CloudTrail logging stack
 */
interface SimpleApiLoggingProps extends cdk.StackProps {
  /**
   * The name prefix for all resources created in this stack
   * @default 'simple-api-logging'
   */
  readonly resourcePrefix?: string;

  /**
   * CloudWatch Logs retention period in days
   * @default 30 days
   */
  readonly logRetentionDays?: logs.RetentionDays;

  /**
   * Whether to enable CloudTrail Insights for detecting unusual API activity
   * @default false (to minimize costs)
   */
  readonly enableInsights?: boolean;

  /**
   * Email address for SNS notifications (optional)
   * If provided, creates an email subscription for root account alerts
   */
  readonly notificationEmail?: string;

  /**
   * Whether to include global service events in the trail
   * @default true
   */
  readonly includeGlobalServiceEvents?: boolean;

  /**
   * Whether to enable multi-region logging
   * @default true
   */
  readonly isMultiRegionTrail?: boolean;
}

/**
 * CDK Stack for Simple API Logging with CloudTrail and S3
 * 
 * This stack creates a comprehensive audit logging solution that:
 * 1. Captures all AWS API calls using CloudTrail
 * 2. Stores logs securely in S3 with encryption and versioning
 * 3. Streams logs to CloudWatch for real-time monitoring
 * 4. Monitors for root account usage with automated alerts
 * 5. Follows AWS security and compliance best practices
 */
class SimpleApiLoggingStack extends cdk.Stack {
  /**
   * The S3 bucket storing CloudTrail logs
   */
  public readonly logsBucket: s3.Bucket;

  /**
   * The CloudTrail trail capturing API events
   */
  public readonly trail: cloudtrail.Trail;

  /**
   * The CloudWatch Log Group for real-time log streaming
   */
  public readonly logGroup: logs.LogGroup;

  /**
   * The SNS topic for security notifications
   */
  public readonly alertTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: SimpleApiLoggingProps = {}) {
    super(scope, id, props);

    // Extract configuration with defaults
    const resourcePrefix = props.resourcePrefix ?? 'simple-api-logging';
    const logRetentionDays = props.logRetentionDays ?? logs.RetentionDays.ONE_MONTH;
    const enableInsights = props.enableInsights ?? false;
    const includeGlobalServiceEvents = props.includeGlobalServiceEvents ?? true;
    const isMultiRegionTrail = props.isMultiRegionTrail ?? true;

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    const accountId = cdk.Stack.of(this).account;
    const region = cdk.Stack.of(this).region;

    // Create S3 bucket for CloudTrail logs with security best practices
    this.logsBucket = new s3.Bucket(this, 'CloudTrailLogsBucket', {
      bucketName: `${resourcePrefix}-logs-${accountId}-${uniqueSuffix}`,
      
      // Security configurations
      encryption: s3.BucketEncryption.S3_MANAGED, // Server-side encryption with S3-managed keys
      versioned: true, // Enable versioning for audit trail protection
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Block all public access
      enforceSSL: true, // Require SSL for all requests
      
      // Lifecycle management
      lifecycleRules: [
        {
          id: 'cloudtrail-log-lifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30), // Move to IA after 30 days
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90), // Move to Glacier after 90 days
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365), // Move to Deep Archive after 1 year
            },
          ],
          // Optional: Uncomment to enable automatic deletion after 7 years
          // expiration: cdk.Duration.days(2555), // 7 years retention
        },
      ],
      
      // Cleanup configuration for non-production environments
      removalPolicy: cdk.RemovalPolicy.RETAIN, // Retain bucket on stack deletion for audit compliance
      autoDeleteObjects: false, // Never auto-delete audit logs
    });

    // Create CloudWatch Log Group for real-time log streaming
    this.logGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/${resourcePrefix}-${uniqueSuffix}`,
      retention: logRetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Can be destroyed as logs are also in S3
    });

    // Create IAM role for CloudTrail to write to CloudWatch Logs
    const cloudTrailRole = new iam.Role(this, 'CloudTrailLogsRole', {
      roleName: `${resourcePrefix}-cloudtrail-logs-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('cloudtrail.amazonaws.com'),
      description: 'Service role for CloudTrail to write logs to CloudWatch Logs',
      inlinePolicies: {
        CloudWatchLogsPolicy: new iam.PolicyDocument({
          statements: [
            // Permission to create log streams
            new iam.PolicyStatement({
              sid: 'AWSCloudTrailCreateLogStream',
              effect: iam.Effect.ALLOW,
              actions: ['logs:CreateLogStream'],
              resources: [
                `arn:aws:logs:${region}:${accountId}:log-group:${this.logGroup.logGroupName}:log-stream:*`,
              ],
            }),
            // Permission to put log events
            new iam.PolicyStatement({
              sid: 'AWSCloudTrailPutLogEvents',
              effect: iam.Effect.ALLOW,
              actions: ['logs:PutLogEvents'],
              resources: [
                `arn:aws:logs:${region}:${accountId}:log-group:${this.logGroup.logGroupName}:log-stream:*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create CloudTrail trail with comprehensive logging configuration
    this.trail = new cloudtrail.Trail(this, 'ApiLoggingTrail', {
      trailName: `${resourcePrefix}-trail-${uniqueSuffix}`,
      
      // S3 configuration
      bucket: this.logsBucket,
      s3KeyPrefix: 'AWSLogs/', // Standard prefix for CloudTrail logs
      
      // CloudWatch Logs configuration
      sendToCloudWatchLogs: true,
      cloudWatchLogsRetention: logRetentionDays,
      cloudWatchLogGroup: this.logGroup,
      cloudWatchLogsRole: cloudTrailRole,
      
      // Trail configuration
      includeGlobalServiceEvents: includeGlobalServiceEvents, // Include global services like IAM, CloudFront
      isMultiRegionTrail: isMultiRegionTrail, // Log events from all regions
      enableFileValidation: true, // Enable log file integrity validation
      
      // Management events configuration (includes API calls)
      managementEvents: cloudtrail.ReadWriteType.ALL,
      
      // Insights configuration for detecting unusual activity patterns
      ...(enableInsights && {
        insightTypes: [
          cloudtrail.InsightType.API_CALL_RATE, // Detect unusual API call volume
          cloudtrail.InsightType.API_ERROR_RATE, // Detect unusual error rates
        ],
      }),
    });

    // Configure S3 bucket policy to allow CloudTrail access with enhanced security
    this.logsBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSCloudTrailAclCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['s3:GetBucketAcl'],
        resources: [this.logsBucket.bucketArn],
        conditions: {
          StringEquals: {
            'aws:SourceArn': this.trail.trailArn,
          },
        },
      })
    );

    this.logsBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSCloudTrailWrite',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [`${this.logsBucket.bucketArn}/AWSLogs/${accountId}/*`],
        conditions: {
          StringEquals: {
            's3:x-amz-acl': 'bucket-owner-full-control',
            'aws:SourceArn': this.trail.trailArn,
          },
        },
      })
    );

    // Create SNS topic for security notifications
    this.alertTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `${resourcePrefix}-security-alerts-${uniqueSuffix}`,
      displayName: 'CloudTrail Security Alerts',
      description: 'Notifications for CloudTrail security events like root account usage',
    });

    // Add email subscription if provided
    if (props.notificationEmail) {
      this.alertTopic.addSubscription(
        new cdk.aws_sns_subscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create metric filter for root account usage detection
    const rootAccountMetricFilter = new logs.MetricFilter(this, 'RootAccountUsageMetricFilter', {
      logGroup: this.logGroup,
      metricNamespace: 'CloudTrailMetrics',
      metricName: 'RootAccountUsageCount',
      metricValue: '1',
      defaultValue: 0,
      filterName: 'RootAccountUsage',
      // Filter pattern to detect root account usage (excluding AWS service events)
      filterPattern: logs.FilterPattern.allTerms(
        '{ $.userIdentity.type = "Root" }',
        '{ $.userIdentity.invokedBy NOT EXISTS }',
        '{ $.eventType != "AwsServiceEvent" }'
      ),
    });

    // Create CloudWatch alarm for root account usage
    const rootAccountAlarm = new cloudwatch.Alarm(this, 'RootAccountUsageAlarm', {
      alarmName: `${resourcePrefix}-root-account-usage-${uniqueSuffix}`,
      alarmDescription: 'Alert when AWS root account is used for API calls',
      metric: rootAccountMetricFilter.metric({
        statistic: cloudwatch.Stats.SUM,
        period: cdk.Duration.minutes(5), // Check every 5 minutes
      }),
      threshold: 1, // Alert on any root account usage
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1, // Trigger immediately
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING, // Don't alarm when no data
    });

    // Add SNS notification action to the alarm
    rootAccountAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));

    // Create additional metric filters for other security events

    // Console sign-in failures
    const consoleSignInFailureFilter = new logs.MetricFilter(this, 'ConsoleSignInFailureMetricFilter', {
      logGroup: this.logGroup,
      metricNamespace: 'CloudTrailMetrics',
      metricName: 'ConsoleSignInFailureCount',
      metricValue: '1',
      defaultValue: 0,
      filterName: 'ConsoleSignInFailure',
      filterPattern: logs.FilterPattern.allTerms(
        '{ $.eventName = "ConsoleLogin" }',
        '{ $.errorMessage EXISTS }'
      ),
    });

    // Create alarm for console sign-in failures
    const consoleSignInFailureAlarm = new cloudwatch.Alarm(this, 'ConsoleSignInFailureAlarm', {
      alarmName: `${resourcePrefix}-console-signin-failure-${uniqueSuffix}`,
      alarmDescription: 'Alert on AWS Console sign-in failures',
      metric: consoleSignInFailureFilter.metric({
        statistic: cloudwatch.Stats.SUM,
        period: cdk.Duration.minutes(15), // Check every 15 minutes
      }),
      threshold: 3, // Alert after 3 failures
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    consoleSignInFailureAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));

    // IAM policy changes
    const iamPolicyChangeFilter = new logs.MetricFilter(this, 'IAMPolicyChangeMetricFilter', {
      logGroup: this.logGroup,
      metricNamespace: 'CloudTrailMetrics',
      metricName: 'IAMPolicyChangeCount',
      metricValue: '1',
      defaultValue: 0,
      filterName: 'IAMPolicyChange',
      filterPattern: logs.FilterPattern.anyTerm(
        '{ $.eventName = DeleteGroupPolicy }',
        '{ $.eventName = DeleteRolePolicy }',
        '{ $.eventName = DeleteUserPolicy }',
        '{ $.eventName = PutGroupPolicy }',
        '{ $.eventName = PutRolePolicy }',
        '{ $.eventName = PutUserPolicy }',
        '{ $.eventName = CreatePolicy }',
        '{ $.eventName = DeletePolicy }',
        '{ $.eventName = CreatePolicyVersion }',
        '{ $.eventName = DeletePolicyVersion }'
      ),
    });

    // Create alarm for IAM policy changes
    const iamPolicyChangeAlarm = new cloudwatch.Alarm(this, 'IAMPolicyChangeAlarm', {
      alarmName: `${resourcePrefix}-iam-policy-change-${uniqueSuffix}`,
      alarmDescription: 'Alert on IAM policy changes',
      metric: iamPolicyChangeFilter.metric({
        statistic: cloudwatch.Stats.SUM,
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    iamPolicyChangeAlarm.addAlarmAction(new cw_actions.SnsAction(this.alertTopic));

    // CloudFormation stack outputs for reference
    new cdk.CfnOutput(this, 'CloudTrailLogsBucketName', {
      value: this.logsBucket.bucketName,
      description: 'Name of the S3 bucket storing CloudTrail logs',
      exportName: `${this.stackName}-CloudTrailLogsBucket`,
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.trail.trailArn,
      description: 'ARN of the CloudTrail trail',
      exportName: `${this.stackName}-CloudTrailArn`,
    });

    new cdk.CfnOutput(this, 'CloudWatchLogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'Name of the CloudWatch Log Group for CloudTrail',
      exportName: `${this.stackName}-CloudWatchLogGroup`,
    });

    new cdk.CfnOutput(this, 'SecurityAlertsTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for security alerts',
      exportName: `${this.stackName}-SecurityAlertsTopic`,
    });

    // Add tags to all resources in the stack for cost tracking and management
    cdk.Tags.of(this).add('Project', 'SimpleApiLogging');
    cdk.Tags.of(this).add('Environment', props.env?.account ? 'Production' : 'Development');
    cdk.Tags.of(this).add('Owner', 'SecurityTeam');
    cdk.Tags.of(this).add('CostCenter', 'Security');
    cdk.Tags.of(this).add('Purpose', 'AuditLogging');
  }
}

/**
 * CDK Application entry point
 * 
 * This creates and deploys the Simple API Logging stack with CloudTrail and S3.
 * The application can be customized by modifying the stack properties below.
 */
const app = new cdk.App();

// Create the main stack with default configuration
new SimpleApiLoggingStack(app, 'SimpleApiLoggingStack', {
  // Stack properties
  description: 'Simple API Logging with CloudTrail and S3 - Comprehensive audit logging solution',
  
  // Environment configuration (uses CDK CLI environment or defaults)
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },

  // Custom properties (uncomment and modify as needed)
  // resourcePrefix: 'my-org-api-logging',
  // logRetentionDays: logs.RetentionDays.THREE_MONTHS,
  // enableInsights: true, // Enable for production environments
  // notificationEmail: 'security-team@example.com',
  // includeGlobalServiceEvents: true,
  // isMultiRegionTrail: true,

  // Termination protection for production environments
  terminationProtection: false, // Set to true for production
});

// Optional: Create additional stacks for different environments
// Uncomment and customize as needed for multi-environment deployments

/*
// Development environment stack
new SimpleApiLoggingStack(app, 'SimpleApiLoggingStackDev', {
  description: 'Simple API Logging - Development Environment',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'us-east-1',
  },
  resourcePrefix: 'dev-api-logging',
  logRetentionDays: logs.RetentionDays.ONE_WEEK,
  enableInsights: false, // Disable to reduce costs
  isMultiRegionTrail: false, // Single region for dev
  terminationProtection: false,
});

// Production environment stack
new SimpleApiLoggingStack(app, 'SimpleApiLoggingStackProd', {
  description: 'Simple API Logging - Production Environment',
  env: {
    account: 'PROD_ACCOUNT_ID',
    region: 'us-east-1',
  },
  resourcePrefix: 'prod-api-logging',
  logRetentionDays: logs.RetentionDays.ONE_YEAR,
  enableInsights: true, // Enable for advanced threat detection
  notificationEmail: 'security-alerts@company.com',
  isMultiRegionTrail: true,
  terminationProtection: true, // Protect production resources
});
*/

// Synthesize the CDK application
app.synth();