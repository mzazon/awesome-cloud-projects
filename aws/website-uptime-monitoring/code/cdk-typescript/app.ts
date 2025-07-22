#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cwActions from 'aws-cdk-lib/aws-cloudwatch-actions';

/**
 * Properties for the Website Uptime Monitoring Stack
 */
export interface WebsiteUptimeMonitoringStackProps extends cdk.StackProps {
  /**
   * The website URL to monitor (without protocol)
   * @example 'httpbin.org'
   */
  readonly websiteDomain: string;

  /**
   * The path to monitor on the website
   * @default '/status/200'
   */
  readonly resourcePath?: string;

  /**
   * The port to use for health checks
   * @default 443 (HTTPS)
   */
  readonly port?: number;

  /**
   * The protocol to use for health checks
   * @default 'HTTPS'
   */
  readonly protocol?: 'HTTP' | 'HTTPS';

  /**
   * Email address to receive notifications
   */
  readonly notificationEmail: string;

  /**
   * Health check request interval in seconds
   * @default 30
   */
  readonly requestInterval?: number;

  /**
   * Number of consecutive failures before marking as unhealthy
   * @default 3
   */
  readonly failureThreshold?: number;

  /**
   * Environment name for resource tagging
   * @default 'production'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for Website Uptime Monitoring using Route 53 Health Checks
 * 
 * This stack creates:
 * - Route 53 Health Check for website monitoring
 * - SNS Topic for email notifications
 * - CloudWatch Alarm for health check failures
 * - CloudWatch Dashboard for metrics visualization
 */
export class WebsiteUptimeMonitoringStack extends cdk.Stack {
  public readonly healthCheck: route53.CfnHealthCheck;
  public readonly snsTopic: sns.Topic;
  public readonly alarm: cloudwatch.Alarm;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: WebsiteUptimeMonitoringStackProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.websiteDomain) {
      throw new Error('websiteDomain is required');
    }
    if (!props.notificationEmail) {
      throw new Error('notificationEmail is required');
    }

    // Set default values
    const resourcePath = props.resourcePath ?? '/status/200';
    const port = props.port ?? 443;
    const protocol = props.protocol ?? 'HTTPS';
    const requestInterval = props.requestInterval ?? 30;
    const failureThreshold = props.failureThreshold ?? 3;
    const environment = props.environment ?? 'production';

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);

    // Create SNS Topic for notifications
    this.snsTopic = new sns.Topic(this, 'UptimeAlertsTopic', {
      topicName: `website-uptime-alerts-${uniqueSuffix}`,
      displayName: `Website Uptime Alerts - ${props.websiteDomain}`,
      fifo: false,
    });

    // Add email subscription to SNS topic
    this.snsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail)
    );

    // Apply tags to SNS Topic
    cdk.Tags.of(this.snsTopic).add('Name', `website-uptime-alerts-${uniqueSuffix}`);
    cdk.Tags.of(this.snsTopic).add('Purpose', 'UptimeMonitoring');
    cdk.Tags.of(this.snsTopic).add('Environment', environment);

    // Create Route 53 Health Check
    this.healthCheck = new route53.CfnHealthCheck(this, 'WebsiteHealthCheck', {
      type: protocol,
      fullyQualifiedDomainName: props.websiteDomain,
      resourcePath: resourcePath,
      port: port,
      requestInterval: requestInterval,
      failureThreshold: failureThreshold,
      measureLatency: true,
      enableSni: protocol === 'HTTPS',
      tags: [
        {
          key: 'Name',
          value: `website-uptime-${uniqueSuffix}`,
        },
        {
          key: 'Purpose',
          value: 'UptimeMonitoring',
        },
        {
          key: 'Environment',
          value: environment,
        },
        {
          key: 'Owner',
          value: 'DevOps',
        },
      ],
    });

    // Create CloudWatch Alarm for health check failures
    this.alarm = new cloudwatch.Alarm(this, 'WebsiteDownAlarm', {
      alarmName: `website-down-${uniqueSuffix}`,
      alarmDescription: `Alert when ${props.websiteDomain} is down`,
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Route53',
        metricName: 'HealthCheckStatus',
        dimensionsMap: {
          HealthCheckId: this.healthCheck.ref,
        },
        statistic: 'Minimum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.BREACHING,
    });

    // Add SNS actions to the alarm
    this.alarm.addAlarmAction(new cwActions.SnsAction(this.snsTopic));
    this.alarm.addOkAction(new cwActions.SnsAction(this.snsTopic));

    // Create CloudWatch Dashboard
    this.dashboard = new cloudwatch.Dashboard(this, 'UptimeDashboard', {
      dashboardName: `website-uptime-dashboard-${uniqueSuffix}`,
    });

    // Add widgets to the dashboard
    this.dashboard.addWidgets(
      // Health Status Widget
      new cloudwatch.GraphWidget({
        title: 'Website Health Status',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Route53',
            metricName: 'HealthCheckStatus',
            dimensionsMap: {
              HealthCheckId: this.healthCheck.ref,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        leftYAxis: {
          min: 0,
          max: 1,
        },
        width: 12,
        height: 6,
      }),

      // Health Check Percentage Widget
      new cloudwatch.GraphWidget({
        title: 'Health Check Percentage',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Route53',
            metricName: 'HealthCheckPercentHealthy',
            dimensionsMap: {
              HealthCheckId: this.healthCheck.ref,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        leftYAxis: {
          min: 0,
          max: 100,
        },
        width: 12,
        height: 6,
      })
    );

    // Add connection time widget if measuring latency
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Connection Time (ms)',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Route53',
            metricName: 'ConnectionTime',
            dimensionsMap: {
              HealthCheckId: this.healthCheck.ref,
            },
            statistic: 'Average',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 24,
        height: 6,
      })
    );

    // Stack Outputs
    new cdk.CfnOutput(this, 'HealthCheckId', {
      value: this.healthCheck.ref,
      description: 'Route 53 Health Check ID',
      exportName: `${this.stackName}-HealthCheckId`,
    });

    new cdk.CfnOutput(this, 'SnsTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'SNS Topic ARN for notifications',
      exportName: `${this.stackName}-SnsTopicArn`,
    });

    new cdk.CfnOutput(this, 'AlarmName', {
      value: this.alarm.alarmName,
      description: 'CloudWatch Alarm name for website down alerts',
      exportName: `${this.stackName}-AlarmName`,
    });

    new cdk.CfnOutput(this, 'DashboardName', {
      value: this.dashboard.dashboardName,
      description: 'CloudWatch Dashboard name',
      exportName: `${this.stackName}-DashboardName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL',
    });

    new cdk.CfnOutput(this, 'MonitoredWebsite', {
      value: `${protocol.toLowerCase()}://${props.websiteDomain}${resourcePath}`,
      description: 'Website URL being monitored',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get configuration from context or environment variables
const websiteDomain = app.node.tryGetContext('websiteDomain') || process.env.WEBSITE_DOMAIN || 'httpbin.org';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const resourcePath = app.node.tryGetContext('resourcePath') || process.env.RESOURCE_PATH || '/status/200';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'production';

// Validate required parameters
if (!notificationEmail) {
  throw new Error('notificationEmail must be provided via CDK context or NOTIFICATION_EMAIL environment variable');
}

// Validate email format
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
if (!emailRegex.test(notificationEmail)) {
  throw new Error('Please provide a valid email address for notifications');
}

// Create the stack
new WebsiteUptimeMonitoringStack(app, 'WebsiteUptimeMonitoringStack', {
  websiteDomain,
  notificationEmail,
  resourcePath,
  environment,
  description: 'Website uptime monitoring system using Route 53 health checks, CloudWatch alarms, and SNS notifications',
  
  // Stack configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Enable termination protection for production
  terminationProtection: environment === 'production',
  
  // Stack tags
  tags: {
    Project: 'WebsiteUptimeMonitoring',
    Environment: environment,
    ManagedBy: 'CDK',
    CostCenter: 'Infrastructure',
  },
});

// Synthesize the app
app.synth();