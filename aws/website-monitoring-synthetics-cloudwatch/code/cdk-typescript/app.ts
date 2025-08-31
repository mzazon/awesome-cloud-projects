#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as synthetics from 'aws-cdk-lib/aws-synthetics';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { AwsSolutionsChecks } from 'cdk-nag';
import { NagSuppressions } from 'cdk-nag';

/**
 * Properties for the Website Monitoring Stack
 */
export interface WebsiteMonitoringStackProps extends cdk.StackProps {
  /**
   * The website URL to monitor
   * @default 'https://example.com'
   */
  readonly websiteUrl?: string;

  /**
   * Email address for alert notifications
   * @default 'your-email@example.com'
   */
  readonly notificationEmail?: string;

  /**
   * Canary execution schedule
   * @default 'rate(5 minutes)'
   */
  readonly canarySchedule?: string;

  /**
   * Canary timeout in seconds
   * @default 60
   */
  readonly canaryTimeoutSeconds?: number;

  /**
   * Success rate threshold for alarms (percentage)
   * @default 90
   */
  readonly successThreshold?: number;

  /**
   * Response time threshold for alarms (milliseconds)
   * @default 10000
   */
  readonly responseTimeThreshold?: number;
}

/**
 * CDK Stack for Website Monitoring with CloudWatch Synthetics
 * 
 * This stack creates a comprehensive website monitoring solution using:
 * - CloudWatch Synthetics canary for automated testing
 * - S3 bucket for storing canary artifacts
 * - CloudWatch alarms for availability and performance monitoring
 * - SNS topic for alert notifications
 * - CloudWatch dashboard for visualization
 */
export class WebsiteMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: WebsiteMonitoringStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const websiteUrl = props.websiteUrl || 'https://example.com';
    const notificationEmail = props.notificationEmail || 'your-email@example.com';
    const canarySchedule = props.canarySchedule || 'rate(5 minutes)';
    const canaryTimeoutSeconds = props.canaryTimeoutSeconds || 60;
    const successThreshold = props.successThreshold || 90;
    const responseTimeThreshold = props.responseTimeThreshold || 10000;

    // Generate unique suffix for resources
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-8);
    const canaryName = `website-monitor-${uniqueSuffix}`;

    // S3 Bucket for Synthetics artifacts
    const artifactsBucket = new s3.Bucket(this, 'SyntheticsArtifactsBucket', {
      bucketName: `synthetics-artifacts-${uniqueSuffix}`,
      versioned: true,
      lifecycleRules: [
        {
          id: 'SyntheticsArtifactRetention',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
          expiration: cdk.Duration.days(90),
        },
      ],
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // IAM Role for Synthetics Canary
    const canaryRole = new iam.Role(this, 'SyntheticsCanaryRole', {
      roleName: `SyntheticsCanaryRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchSyntheticsExecutionRolePolicy'),
      ],
      inlinePolicies: {
        S3ArtifactsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                artifactsBucket.bucketArn,
                `${artifactsBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Canary script for website monitoring
    const canaryScript = `
const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const checkWebsite = async function () {
    let page = await synthetics.getPage();
    
    // Navigate to website with performance monitoring
    const response = await synthetics.executeStepFunction('loadHomepage', async function () {
        return await page.goto('${websiteUrl}', {
            waitUntil: 'networkidle0',
            timeout: 30000
        });
    });
    
    // Verify successful response
    if (response.status() < 200 || response.status() > 299) {
        throw new Error(\`Failed to load page: \${response.status()}\`);
    }
    
    // Check for critical page elements
    await synthetics.executeStepFunction('verifyPageElements', async function () {
        await page.waitForSelector('body', { timeout: 10000 });
        
        // Verify page title exists
        const title = await page.title();
        if (!title || title.length === 0) {
            throw new Error('Page title is missing');
        }
        
        log.info(\`Page title: \${title}\`);
        
        // Check for JavaScript errors
        const errors = await page.evaluate(() => {
            return window.console.errors || [];
        });
        
        if (errors.length > 0) {
            log.warn(\`JavaScript errors detected: \${errors.length}\`);
        }
    });
    
    // Capture performance metrics
    await synthetics.executeStepFunction('captureMetrics', async function () {
        const metrics = await page.evaluate(() => {
            const navigation = performance.getEntriesByType('navigation')[0];
            return {
                loadTime: navigation.loadEventEnd - navigation.loadEventStart,
                domContentLoaded: navigation.domContentLoadedEventEnd - navigation.domContentLoadedEventStart,
                responseTime: navigation.responseEnd - navigation.requestStart
            };
        });
        
        // Log custom metrics
        log.info(\`Load time: \${metrics.loadTime}ms\`);
        log.info(\`DOM content loaded: \${metrics.domContentLoaded}ms\`);
        log.info(\`Response time: \${metrics.responseTime}ms\`);
        
        // Set custom CloudWatch metrics
        await synthetics.addUserAgentMetric('LoadTime', metrics.loadTime, 'Milliseconds');
        await synthetics.addUserAgentMetric('ResponseTime', metrics.responseTime, 'Milliseconds');
    });
};

exports.handler = async () => {
    return await synthetics.executeStep('checkWebsite', checkWebsite);
};`;

    // CloudWatch Synthetics Canary
    const canary = new synthetics.Canary(this, 'WebsiteMonitoringCanary', {
      canaryName: canaryName,
      runtime: synthetics.Runtime.SYNTHETICS_NODEJS_PUPPETEER_10_0,
      test: synthetics.Test.custom({
        code: synthetics.Code.fromInline(canaryScript),
        handler: 'index.handler',
      }),
      schedule: synthetics.Schedule.expression(canarySchedule),
      role: canaryRole,
      artifactsBucketLocation: {
        bucket: artifactsBucket,
        prefix: 'canary-artifacts',
      },
      timeToLive: cdk.Duration.seconds(canaryTimeoutSeconds),
      memory: synthetics.Memory.MB_960,
      enableAutoDeleteLambdas: true,
      successRetentionPeriod: cdk.Duration.days(31),
      failureRetentionPeriod: cdk.Duration.days(31),
      startAfterCreation: true,
    });

    // SNS Topic for alerts
    const alertsTopic = new sns.Topic(this, 'SyntheticsAlertsTopic', {
      topicName: `synthetics-alerts-${uniqueSuffix}`,
      displayName: 'Website Monitoring Alerts',
    });

    // Email subscription to SNS topic
    alertsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail)
    );

    // CloudWatch Alarm for canary failures
    const failureAlarm = new cloudwatch.Alarm(this, 'CanaryFailureAlarm', {
      alarmName: `${canaryName}-FailureAlarm`,
      alarmDescription: 'Alert when website monitoring canary fails',
      metric: canary.metricSuccessPercent({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: successThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    failureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertsTopic));

    // CloudWatch Alarm for high response times
    const responseTimeAlarm = new cloudwatch.Alarm(this, 'CanaryResponseTimeAlarm', {
      alarmName: `${canaryName}-ResponseTimeAlarm`,
      alarmDescription: 'Alert when website response time is high',
      metric: canary.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: responseTimeThreshold,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    responseTimeAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertsTopic));

    // CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'WebsiteMonitoringDashboard', {
      dashboardName: `Website-Monitoring-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Website Monitoring Overview',
            left: [
              canary.metricSuccessPercent({
                period: cdk.Duration.minutes(5),
                statistic: 'Average',
              }),
            ],
            right: [
              canary.metricDuration({
                period: cdk.Duration.minutes(5),
                statistic: 'Average',
              }),
            ],
            width: 12,
            height: 6,
            leftYAxis: {
              min: 0,
              max: 100,
            },
          }),
          new cloudwatch.GraphWidget({
            title: 'Test Results',
            left: [
              canary.metricFailed({
                period: cdk.Duration.minutes(5),
                statistic: 'Sum',
              }),
              canary.metricSucceeded({
                period: cdk.Duration.minutes(5),
                statistic: 'Sum',
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Add CDK Nag suppressions for specific requirements
    NagSuppressions.addResourceSuppressions(
      canaryRole,
      [
        {
          id: 'AwsSolutions-IAM4',
          reason: 'CloudWatchSyntheticsExecutionRolePolicy is required for Synthetics canary execution and follows AWS best practices.',
        },
      ]
    );

    NagSuppressions.addResourceSuppressions(
      artifactsBucket,
      [
        {
          id: 'AwsSolutions-S3-1',
          reason: 'S3 server access logging is not required for synthetics artifacts bucket as it is used for temporary storage.',
        },
      ]
    );

    // Outputs
    new cdk.CfnOutput(this, 'CanaryName', {
      value: canary.canaryName,
      description: 'Name of the CloudWatch Synthetics canary',
    });

    new cdk.CfnOutput(this, 'ArtifactsBucketName', {
      value: artifactsBucket.bucketName,
      description: 'S3 bucket storing canary artifacts',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for monitoring',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertsTopic.topicArn,
      description: 'SNS topic ARN for alert notifications',
    });

    new cdk.CfnOutput(this, 'WebsiteUrl', {
      value: websiteUrl,
      description: 'Website URL being monitored',
    });

    new cdk.CfnOutput(this, 'NotificationEmail', {
      value: notificationEmail,
      description: 'Email address for notifications (confirm subscription)',
    });
  }
}

// Create the CDK App
const app = new cdk.App();

// Apply CDK Nag for security best practices
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));

// Create the stack with configurable properties
new WebsiteMonitoringStack(app, 'WebsiteMonitoringStack', {
  description: 'Website Monitoring with CloudWatch Synthetics - CDK TypeScript Implementation',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Configurable properties - override via CDK context or environment variables
  websiteUrl: app.node.tryGetContext('websiteUrl') || process.env.WEBSITE_URL || 'https://example.com',
  notificationEmail: app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL || 'your-email@example.com',
  canarySchedule: app.node.tryGetContext('canarySchedule') || process.env.CANARY_SCHEDULE || 'rate(5 minutes)',
  canaryTimeoutSeconds: parseInt(app.node.tryGetContext('canaryTimeoutSeconds')) || parseInt(process.env.CANARY_TIMEOUT_SECONDS || '60'),
  successThreshold: parseInt(app.node.tryGetContext('successThreshold')) || parseInt(process.env.SUCCESS_THRESHOLD || '90'),
  responseTimeThreshold: parseInt(app.node.tryGetContext('responseTimeThreshold')) || parseInt(process.env.RESPONSE_TIME_THRESHOLD || '10000'),
});