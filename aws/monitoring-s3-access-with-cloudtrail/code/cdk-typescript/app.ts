#!/usr/bin/env node
/**
 * S3 Access Logging and Security Monitoring with CloudTrail
 * 
 * This CDK application creates a comprehensive S3 access logging and security monitoring system
 * that combines S3 Server Access Logging with CloudTrail API monitoring. The solution provides
 * detailed access logs for compliance auditing, real-time security event detection through
 * CloudWatch and EventBridge, and automated alerting for suspicious activities.
 * 
 * Architecture includes:
 * - S3 buckets for source data and access logs
 * - CloudTrail with S3 data events
 * - CloudWatch Logs integration
 * - EventBridge rules for security monitoring
 * - Lambda function for advanced threat detection
 * - SNS topic for security alerts
 * - CloudWatch dashboard for operational visibility
 */

import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as events from 'aws-cdk-lib/aws-events';
import * as events_targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sns_subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

/**
 * Configuration interface for the S3 Security Monitor stack
 */
export interface S3SecurityMonitorStackProps extends cdk.StackProps {
  /**
   * Email address for security alerts
   * @default 'security@example.com'
   */
  readonly alertEmail?: string;
  
  /**
   * CloudWatch log retention in days
   * @default 30
   */
  readonly logRetentionDays?: number;
  
  /**
   * Lambda function timeout in seconds
   * @default 30
   */
  readonly lambdaTimeout?: number;
  
  /**
   * Prefix for resource names
   * @default 's3-security-monitor'
   */
  readonly resourcePrefix?: string;
}

/**
 * Stack for S3 Access Logging and Security Monitoring
 */
export class S3SecurityMonitorStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: S3SecurityMonitorStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const config = {
      alertEmail: props.alertEmail || 'security@example.com',
      logRetentionDays: props.logRetentionDays || 30,
      lambdaTimeout: props.lambdaTimeout || 30,
      resourcePrefix: props.resourcePrefix || 's3-security-monitor'
    };

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Stack.of(this).account.substring(6);

    // ========================================
    // S3 Buckets
    // ========================================

    // Source bucket for monitoring
    const sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${config.resourcePrefix}-source-${uniqueSuffix}`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(90),
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 access logs bucket
    const logsBucket = new s3.Bucket(this, 'LogsBucket', {
      bucketName: `${config.resourcePrefix}-logs-${uniqueSuffix}`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          expiration: cdk.Duration.days(365),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // CloudTrail S3 bucket
    const cloudTrailBucket = new s3.Bucket(this, 'CloudTrailBucket', {
      bucketName: `${config.resourcePrefix}-cloudtrail-${uniqueSuffix}`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldTrails',
          expiration: cdk.Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ========================================
    // S3 Server Access Logging Configuration
    // ========================================

    // Grant S3 logging service permission to write to logs bucket
    logsBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'S3ServerAccessLogsPolicy',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('logging.s3.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [logsBucket.arnForObjects('access-logs/*')],
        conditions: {
          ArnLike: {
            'aws:SourceArn': sourceBucket.bucketArn,
          },
          StringEquals: {
            'aws:SourceAccount': this.account,
          },
        },
      })
    );

    // Enable server access logging with date-based partitioning
    const cfnSourceBucket = sourceBucket.node.defaultChild as s3.CfnBucket;
    cfnSourceBucket.loggingConfiguration = {
      destinationBucketName: logsBucket.bucketName,
      logFilePrefix: 'access-logs/',
      targetObjectKeyFormat: {
        partitionedPrefix: {
          partitionDateSource: 'EventTime',
        },
      },
    };

    // ========================================
    // CloudWatch Log Group
    // ========================================

    const logGroup = new logs.LogGroup(this, 'CloudTrailLogGroup', {
      logGroupName: `/aws/cloudtrail/${config.resourcePrefix}`,
      retention: config.logRetentionDays as logs.RetentionDays,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ========================================
    // CloudTrail Configuration
    // ========================================

    // CloudTrail service role for CloudWatch Logs
    const cloudTrailRole = new iam.Role(this, 'CloudTrailLogsRole', {
      assumedBy: new iam.ServicePrincipal('cloudtrail.amazonaws.com'),
      inlinePolicies: {
        CloudTrailLogsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });

    // CloudTrail with S3 data events
    const trail = new cloudtrail.Trail(this, 'SecurityMonitoringTrail', {
      trailName: `${config.resourcePrefix}-trail`,
      bucket: cloudTrailBucket,
      s3KeyPrefix: 'cloudtrail-logs/',
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      cloudWatchLogGroup: logGroup,
      cloudWatchLogsRole: cloudTrailRole,
    });

    // Add S3 data events for the source bucket
    trail.addS3EventSelector([
      {
        bucket: sourceBucket,
        objectPrefix: '',
      },
    ]);

    // ========================================
    // SNS Topic for Security Alerts
    // ========================================

    const securityAlertsTopic = new sns.Topic(this, 'SecurityAlertsTopic', {
      topicName: `${config.resourcePrefix}-security-alerts`,
      displayName: 'S3 Security Alerts',
    });

    // Subscribe email to SNS topic
    securityAlertsTopic.addSubscription(
      new sns_subscriptions.EmailSubscription(config.alertEmail)
    );

    // ========================================
    // EventBridge Rules for Security Monitoring
    // ========================================

    // Rule for unauthorized access attempts
    const unauthorizedAccessRule = new events.Rule(this, 'UnauthorizedAccessRule', {
      ruleName: `${config.resourcePrefix}-unauthorized-access`,
      description: 'Detects unauthorized S3 access attempts',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventName: ['GetObject', 'PutObject', 'DeleteObject'],
          errorCode: ['AccessDenied', 'SignatureDoesNotMatch'],
        },
      },
    });

    // Add SNS target to EventBridge rule
    unauthorizedAccessRule.addTarget(
      new events_targets.SnsTopic(securityAlertsTopic, {
        message: events.RuleTargetInput.fromText(
          'Security Alert: Unauthorized S3 access attempt detected!\n\n' +
          'Event: ${detail.eventName}\n' +
          'Source IP: ${detail.sourceIPAddress}\n' +
          'User: ${detail.userIdentity.type}\n' +
          'Error: ${detail.errorCode}\n' +
          'Time: ${detail.eventTime}\n' +
          'Bucket: ${detail.requestParameters.bucketName}\n' +
          'Key: ${detail.requestParameters.key}'
        ),
      })
    );

    // Rule for suspicious administrative actions
    const suspiciousAdminRule = new events.Rule(this, 'SuspiciousAdminRule', {
      ruleName: `${config.resourcePrefix}-suspicious-admin`,
      description: 'Detects suspicious S3 administrative actions',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventName: ['PutBucketPolicy', 'PutBucketAcl', 'DeleteBucket', 'DeleteBucketPolicy'],
        },
      },
    });

    suspiciousAdminRule.addTarget(
      new events_targets.SnsTopic(securityAlertsTopic, {
        message: events.RuleTargetInput.fromText(
          'Security Alert: Suspicious S3 administrative action detected!\n\n' +
          'Event: ${detail.eventName}\n' +
          'Source IP: ${detail.sourceIPAddress}\n' +
          'User: ${detail.userIdentity.type}\n' +
          'ARN: ${detail.userIdentity.arn}\n' +
          'Time: ${detail.eventTime}\n' +
          'Bucket: ${detail.requestParameters.bucketName}'
        ),
      })
    );

    // ========================================
    // Lambda Function for Advanced Security Analysis
    // ========================================

    // Lambda execution role
    const lambdaRole = new iam.Role(this, 'SecurityMonitorLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        SecurityMonitorPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [
                securityAlertsTopic.topicArn,
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/lambda/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Lambda function for security monitoring
    const securityMonitorFunction = new lambda.Function(this, 'SecurityMonitorFunction', {
      functionName: `${config.resourcePrefix}-security-monitor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(config.lambdaTimeout),
      environment: {
        SNS_TOPIC_ARN: securityAlertsTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Advanced security monitoring function for S3 events
    Analyzes CloudTrail events for sophisticated threat patterns
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Parse EventBridge event
        if 'detail' in event:
            analyze_s3_event(event['detail'])
        
        return {
            'statusCode': 200,
            'body': json.dumps('Security monitoring completed successfully')
        }
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise

def analyze_s3_event(detail):
    """
    Analyze S3 event for security patterns
    """
    event_name = detail.get('eventName', '')
    source_ip = detail.get('sourceIPAddress', '')
    user_identity = detail.get('userIdentity', {})
    event_time = detail.get('eventTime', '')
    
    logger.info(f"Analyzing event: {event_name} from IP: {source_ip}")
    
    # Check for suspicious patterns
    if is_suspicious_activity(event_name, source_ip, user_identity, detail):
        send_advanced_alert(detail)

def is_suspicious_activity(event_name, source_ip, user_identity, detail):
    """
    Advanced security checks for suspicious activity
    """
    # High-risk administrative actions
    high_risk_actions = [
        'DeleteBucket', 'PutBucketPolicy', 'PutBucketAcl', 
        'DeleteBucketPolicy', 'PutBucketVersioning'
    ]
    
    # Check for high-risk administrative actions
    if event_name in high_risk_actions:
        logger.warning(f"High-risk action detected: {event_name}")
        return True
    
    # Check for unusual IP patterns (example: non-AWS IP ranges)
    if source_ip and not is_trusted_ip(source_ip):
        logger.warning(f"Access from untrusted IP: {source_ip}")
        return True
    
    # Check for unusual user patterns
    if user_identity.get('type') == 'Root' and event_name in ['GetObject', 'PutObject']:
        logger.warning(f"Root user data access detected: {event_name}")
        return True
    
    # Check for rapid sequential access (basic rate limiting check)
    if event_name in ['GetObject', 'PutObject'] and 'requestParameters' in detail:
        # This is a simplified check - in production, you'd use DynamoDB or ElastiCache
        # to track request patterns across invocations
        pass
    
    return False

def is_trusted_ip(ip_address):
    """
    Check if IP address is from trusted sources
    This is a simplified implementation - in production, you'd check against
    known good IP ranges, VPC CIDR blocks, etc.
    """
    # AWS service IP ranges (simplified check)
    aws_service_prefixes = ['aws', 'amazonaws.com']
    
    # Check if it's an AWS service
    if any(prefix in ip_address.lower() for prefix in aws_service_prefixes):
        return True
    
    # Check for internal IP ranges (RFC 1918)
    internal_prefixes = ['10.', '192.168.', '172.16.', '172.17.', '172.18.', '172.19.', '172.20.', '172.21.', '172.22.', '172.23.', '172.24.', '172.25.', '172.26.', '172.27.', '172.28.', '172.29.', '172.30.', '172.31.']
    
    if any(ip_address.startswith(prefix) for prefix in internal_prefixes):
        return True
    
    return False

def send_advanced_alert(detail):
    """
    Send advanced security alert via SNS
    """
    sns = boto3.client('sns')
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    event_name = detail.get('eventName', 'Unknown')
    source_ip = detail.get('sourceIPAddress', 'Unknown')
    user_identity = detail.get('userIdentity', {})
    event_time = detail.get('eventTime', 'Unknown')
    
    message = f"""
🚨 ADVANCED SECURITY ALERT 🚨

Suspicious S3 activity detected by Lambda security monitor:

Event Details:
- Action: {event_name}
- Source IP: {source_ip}
- User Type: {user_identity.get('type', 'Unknown')}
- User ARN: {user_identity.get('arn', 'Unknown')}
- Time: {event_time}
- AWS Region: {detail.get('awsRegion', 'Unknown')}

Request Details:
- Bucket: {detail.get('requestParameters', {}).get('bucketName', 'Unknown')}
- Key: {detail.get('requestParameters', {}).get('key', 'N/A')}

Response Details:
- Error Code: {detail.get('errorCode', 'N/A')}
- Error Message: {detail.get('errorMessage', 'N/A')}

This alert was generated by the Lambda-based security monitoring system.
Please investigate immediately.
"""
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject=f'🚨 S3 Security Alert: {event_name} from {source_ip}'
        )
        logger.info(f"Security alert sent for event: {event_name}")
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")
        raise
      `),
    });

    // Grant Lambda permission to be invoked by EventBridge
    securityMonitorFunction.addPermission('AllowEventBridgeInvoke', {
      principal: new iam.ServicePrincipal('events.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });

    // Add Lambda target to EventBridge rules
    unauthorizedAccessRule.addTarget(
      new events_targets.LambdaFunction(securityMonitorFunction)
    );

    suspiciousAdminRule.addTarget(
      new events_targets.LambdaFunction(securityMonitorFunction)
    );

    // ========================================
    // CloudWatch Dashboard
    // ========================================

    const dashboard = new cloudwatch.Dashboard(this, 'SecurityMonitoringDashboard', {
      dashboardName: `${config.resourcePrefix}-dashboard`,
    });

    // S3 Bucket Metrics Widget
    const bucketMetricsWidget = new cloudwatch.GraphWidget({
      title: 'S3 Bucket Metrics',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytes',
          dimensionsMap: {
            BucketName: sourceBucket.bucketName,
            StorageType: 'StandardStorage',
          },
          statistic: 'Average',
          period: cdk.Duration.hours(1),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'NumberOfObjects',
          dimensionsMap: {
            BucketName: sourceBucket.bucketName,
            StorageType: 'AllStorageTypes',
          },
          statistic: 'Average',
          period: cdk.Duration.hours(1),
        }),
      ],
    });

    // Lambda Function Metrics Widget
    const lambdaMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Security Monitor Lambda Metrics',
      width: 12,
      height: 6,
      left: [
        securityMonitorFunction.metricInvocations({
          period: cdk.Duration.minutes(5),
        }),
        securityMonitorFunction.metricErrors({
          period: cdk.Duration.minutes(5),
        }),
        securityMonitorFunction.metricDuration({
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    // CloudTrail Events Widget
    const cloudTrailEventsWidget = new cloudwatch.LogQueryWidget({
      title: 'Top S3 API Calls (Last 24h)',
      width: 24,
      height: 6,
      logGroups: [logGroup],
      queryLines: [
        'fields @timestamp, eventName, sourceIPAddress, userIdentity.type',
        'filter eventName like /GetObject|PutObject|DeleteObject/',
        'stats count() by eventName',
        'sort count desc',
        'limit 10',
      ],
    });

    // Security Events Widget
    const securityEventsWidget = new cloudwatch.LogQueryWidget({
      title: 'Security Events (Last 24h)',
      width: 24,
      height: 6,
      logGroups: [logGroup],
      queryLines: [
        'fields @timestamp, eventName, sourceIPAddress, errorCode, errorMessage',
        'filter errorCode = "AccessDenied" or eventName in ["PutBucketPolicy", "DeleteBucket", "PutBucketAcl"]',
        'stats count() by eventName, errorCode',
        'sort count desc',
        'limit 20',
      ],
    });

    // Add widgets to dashboard
    dashboard.addWidgets(bucketMetricsWidget, lambdaMetricsWidget);
    dashboard.addWidgets(cloudTrailEventsWidget);
    dashboard.addWidgets(securityEventsWidget);

    // ========================================
    // Stack Outputs
    // ========================================

    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: sourceBucket.bucketName,
      description: 'Name of the source S3 bucket being monitored',
    });

    new cdk.CfnOutput(this, 'LogsBucketName', {
      value: logsBucket.bucketName,
      description: 'Name of the S3 bucket storing access logs',
    });

    new cdk.CfnOutput(this, 'CloudTrailBucketName', {
      value: cloudTrailBucket.bucketName,
      description: 'Name of the S3 bucket storing CloudTrail logs',
    });

    new cdk.CfnOutput(this, 'CloudTrailLogGroupName', {
      value: logGroup.logGroupName,
      description: 'Name of the CloudWatch log group for CloudTrail events',
    });

    new cdk.CfnOutput(this, 'SecurityAlertsTopicArn', {
      value: securityAlertsTopic.topicArn,
      description: 'ARN of the SNS topic for security alerts',
    });

    new cdk.CfnOutput(this, 'SecurityMonitorFunctionName', {
      value: securityMonitorFunction.functionName,
      description: 'Name of the Lambda function for security monitoring',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${config.resourcePrefix}-dashboard`,
      description: 'URL to the CloudWatch dashboard',
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: trail.trailArn,
      description: 'ARN of the CloudTrail trail',
    });

    // ========================================
    // Tags
    // ========================================

    cdk.Tags.of(this).add('Project', 'S3SecurityMonitor');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('CostCenter', 'Security');
    cdk.Tags.of(this).add('Owner', 'SecurityTeam');
  }
}

// ========================================
// CDK App
// ========================================

const app = new cdk.App();

// Get configuration from context or environment variables
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL || 'security@example.com';
const logRetentionDays = parseInt(app.node.tryGetContext('logRetentionDays') || process.env.LOG_RETENTION_DAYS || '30');
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 's3-security-monitor';

new S3SecurityMonitorStack(app, 'S3SecurityMonitorStack', {
  description: 'S3 Access Logging and Security Monitoring with CloudTrail - Comprehensive security solution for S3 compliance and threat detection',
  alertEmail,
  logRetentionDays,
  resourcePrefix,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'S3SecurityMonitor',
    Environment: 'Production',
    CostCenter: 'Security',
    Owner: 'SecurityTeam',
  },
});