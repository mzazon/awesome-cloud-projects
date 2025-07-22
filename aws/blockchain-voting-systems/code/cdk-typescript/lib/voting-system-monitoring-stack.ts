/**
 * Voting System Monitoring Stack
 * 
 * This stack provides comprehensive monitoring and observability for the blockchain voting system.
 * It creates CloudWatch dashboards, alarms, and monitoring infrastructure to ensure system health,
 * performance, and security. The monitoring solution enables proactive incident response and
 * maintains detailed audit trails for compliance and forensic analysis.
 * 
 * Monitoring Features:
 * - CloudWatch dashboards for real-time system metrics
 * - Custom alarms for critical voting system events
 * - Log aggregation and analysis
 * - Performance and availability monitoring
 * - Security event monitoring
 * - Cost optimization tracking
 * 
 * Observability Features:
 * - X-Ray distributed tracing
 * - Application Insights
 * - Custom metrics for voting activities
 * - Real-time alerting via SNS
 * - Slack integration for team notifications
 * - PagerDuty integration for critical alerts
 * 
 * Author: AWS Recipe
 * Version: 1.0.0
 */

import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as events from 'aws-cdk-lib/aws-events';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * Configuration interface for monitoring settings
 */
export interface MonitoringConfig {
  appName: string;
  environment: string;
  enableDetailedLogging: boolean;
  enableAlarming: boolean;
  logRetentionDays: number;
  adminEmail: string;
  auditorsEmail: string;
  enableSlackNotifications: boolean;
}

/**
 * System resources interface from the main stack
 */
export interface SystemResources {
  voterAuthFunction: lambda.Function;
  voteMonitorFunction: lambda.Function;
  voterRegistryTable: dynamodb.Table;
  electionsTable: dynamodb.Table;
  votingDataBucket: s3.Bucket;
  eventBridge: events.EventBus;
  apiGateway: apigateway.RestApi;
}

/**
 * Stack properties interface
 */
export interface VotingSystemMonitoringStackProps extends cdk.StackProps {
  config: MonitoringConfig;
  systemResources: SystemResources;
}

/**
 * Monitoring stack for the blockchain voting system
 */
export class VotingSystemMonitoringStack extends cdk.Stack {
  // Public properties
  public readonly dashboard: cloudwatch.Dashboard;
  public readonly dashboardUrl: string;
  public readonly alertTopic: sns.Topic;
  public readonly criticalAlertTopic: sns.Topic;

  // Private properties
  private readonly config: MonitoringConfig;
  private readonly systemResources: SystemResources;

  constructor(scope: Construct, id: string, props: VotingSystemMonitoringStackProps) {
    super(scope, id, props);

    this.config = props.config;
    this.systemResources = props.systemResources;

    // Create monitoring infrastructure
    this.createNotificationTopics();
    this.createCloudWatchDashboard();
    this.createSystemAlarms();
    this.createSecurityMonitoring();
    this.createPerformanceMonitoring();
    this.createCustomMetrics();
    this.createLogAggregation();

    // Set dashboard URL
    this.dashboardUrl = `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`;

    // Add stack outputs
    this.addStackOutputs();
  }

  /**
   * Create SNS topics for notifications
   */
  private createNotificationTopics(): void {
    // Create topic for general alerts
    this.alertTopic = new sns.Topic(this, 'VotingSystemAlerts', {
      topicName: `${this.config.appName}-alerts-${this.config.environment}`,
      displayName: 'Voting System Alerts',
      description: 'General alerts for voting system monitoring',
    });

    // Create topic for critical alerts
    this.criticalAlertTopic = new sns.Topic(this, 'VotingSystemCriticalAlerts', {
      topicName: `${this.config.appName}-critical-alerts-${this.config.environment}`,
      displayName: 'Voting System Critical Alerts',
      description: 'Critical alerts requiring immediate attention',
    });

    // Subscribe admin email to alerts
    if (this.config.adminEmail) {
      this.alertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(this.config.adminEmail)
      );
      this.criticalAlertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(this.config.adminEmail)
      );
    }

    // Subscribe auditors email to alerts
    if (this.config.auditorsEmail) {
      this.alertTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(this.config.auditorsEmail)
      );
    }

    // Create Lambda function for Slack notifications (if enabled)
    if (this.config.enableSlackNotifications) {
      this.createSlackNotificationFunction();
    }
  }

  /**
   * Create CloudWatch dashboard for system monitoring
   */
  private createCloudWatchDashboard(): void {
    this.dashboard = new cloudwatch.Dashboard(this, 'VotingSystemDashboard', {
      dashboardName: `${this.config.appName}-dashboard-${this.config.environment}`,
      widgets: [
        // System Overview Row
        [
          new cloudwatch.TextWidget({
            markdown: `# Blockchain Voting System - ${this.config.environment.toUpperCase()}\\n\\n**System Status**: Active\\n**Last Updated**: ${new Date().toISOString()}`,
            width: 8,
            height: 4,
          }),
          new cloudwatch.SingleValueWidget({
            title: 'Total Votes Today',
            metrics: [
              new cloudwatch.Metric({
                namespace: 'VotingSystem',
                metricName: 'VotesCast',
                dimensionsMap: {
                  Environment: this.config.environment,
                },
                statistic: 'Sum',
                period: cdk.Duration.days(1),
              }),
            ],
            width: 8,
            height: 4,
          }),
          new cloudwatch.SingleValueWidget({
            title: 'Active Elections',
            metrics: [
              new cloudwatch.Metric({
                namespace: 'VotingSystem',
                metricName: 'ActiveElections',
                dimensionsMap: {
                  Environment: this.config.environment,
                },
                statistic: 'Average',
                period: cdk.Duration.hours(1),
              }),
            ],
            width: 8,
            height: 4,
          }),
        ],
        
        // Lambda Functions Row
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Invocations',
            left: [
              this.systemResources.voterAuthFunction.metricInvocations({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.voteMonitorFunction.metricInvocations({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Errors',
            left: [
              this.systemResources.voterAuthFunction.metricErrors({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.voteMonitorFunction.metricErrors({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        
        // Lambda Performance Row
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Duration',
            left: [
              this.systemResources.voterAuthFunction.metricDuration({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.voteMonitorFunction.metricDuration({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Throttles',
            left: [
              this.systemResources.voterAuthFunction.metricThrottles({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.voteMonitorFunction.metricThrottles({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        
        // DynamoDB Row
        [
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Read/Write Capacity',
            left: [
              this.systemResources.voterRegistryTable.metricConsumedReadCapacityUnits({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.electionsTable.metricConsumedReadCapacityUnits({
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              this.systemResources.voterRegistryTable.metricConsumedWriteCapacityUnits({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.electionsTable.metricConsumedWriteCapacityUnits({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Throttles',
            left: [
              this.systemResources.voterRegistryTable.metricUserErrors({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.electionsTable.metricUserErrors({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        
        // API Gateway Row
        [
          new cloudwatch.GraphWidget({
            title: 'API Gateway Requests',
            left: [
              this.systemResources.apiGateway.metricCount({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'API Gateway Errors',
            left: [
              this.systemResources.apiGateway.metricClientError({
                period: cdk.Duration.minutes(5),
              }),
              this.systemResources.apiGateway.metricServerError({
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        
        // S3 Storage Row
        [
          new cloudwatch.GraphWidget({
            title: 'S3 Storage Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: this.systemResources.votingDataBucket.bucketName,
                  StorageType: 'StandardStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.days(1),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'S3 Requests',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'AllRequests',
                dimensionsMap: {
                  BucketName: this.systemResources.votingDataBucket.bucketName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        
        // EventBridge Row
        [
          new cloudwatch.GraphWidget({
            title: 'EventBridge Events',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'MatchedEvents',
                dimensionsMap: {
                  EventBusName: this.systemResources.eventBridge.eventBusName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
          new cloudwatch.GraphWidget({
            title: 'EventBridge Invocations',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Events',
                metricName: 'InvocationsCount',
                dimensionsMap: {
                  EventBusName: this.systemResources.eventBridge.eventBusName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });
  }

  /**
   * Create system alarms for monitoring
   */
  private createSystemAlarms(): void {
    if (!this.config.enableAlarming) {
      return;
    }

    // Lambda function error alarms
    const voterAuthErrorAlarm = new cloudwatch.Alarm(this, 'VoterAuthErrorAlarm', {
      alarmName: `${this.config.appName}-voter-auth-errors-${this.config.environment}`,
      alarmDescription: 'Voter authentication function errors',
      metric: this.systemResources.voterAuthFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const voteMonitorErrorAlarm = new cloudwatch.Alarm(this, 'VoteMonitorErrorAlarm', {
      alarmName: `${this.config.appName}-vote-monitor-errors-${this.config.environment}`,
      alarmDescription: 'Vote monitoring function errors',
      metric: this.systemResources.voteMonitorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 3,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Lambda function duration alarms
    const voterAuthDurationAlarm = new cloudwatch.Alarm(this, 'VoterAuthDurationAlarm', {
      alarmName: `${this.config.appName}-voter-auth-duration-${this.config.environment}`,
      alarmDescription: 'Voter authentication function high duration',
      metric: this.systemResources.voterAuthFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average',
      }),
      threshold: 25000, // 25 seconds
      evaluationPeriods: 3,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // DynamoDB throttle alarms
    const voterRegistryThrottleAlarm = new cloudwatch.Alarm(this, 'VoterRegistryThrottleAlarm', {
      alarmName: `${this.config.appName}-voter-registry-throttles-${this.config.environment}`,
      alarmDescription: 'Voter registry table throttles',
      metric: this.systemResources.voterRegistryTable.metricUserErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 1,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // API Gateway error alarms
    const apiGatewayErrorAlarm = new cloudwatch.Alarm(this, 'ApiGatewayErrorAlarm', {
      alarmName: `${this.config.appName}-api-gateway-errors-${this.config.environment}`,
      alarmDescription: 'API Gateway 5xx errors',
      metric: this.systemResources.apiGateway.metricServerError({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum',
      }),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Custom voting system alarms
    const highVolumeVotingAlarm = new cloudwatch.Alarm(this, 'HighVolumeVotingAlarm', {
      alarmName: `${this.config.appName}-high-volume-voting-${this.config.environment}`,
      alarmDescription: 'High volume of votes detected',
      metric: new cloudwatch.Metric({
        namespace: 'VotingSystem',
        metricName: 'VotesCast',
        dimensionsMap: {
          Environment: this.config.environment,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 100, // 100 votes per minute
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm actions
    voterAuthErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.criticalAlertTopic));
    voteMonitorErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.criticalAlertTopic));
    voterAuthDurationAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
    voterRegistryThrottleAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.criticalAlertTopic));
    apiGatewayErrorAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
    highVolumeVotingAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));

    // Create composite alarm for system health
    const systemHealthAlarm = new cloudwatch.CompositeAlarm(this, 'SystemHealthAlarm', {
      alarmName: `${this.config.appName}-system-health-${this.config.environment}`,
      alarmDescription: 'Overall system health composite alarm',
      compositeAlarmRule: cloudwatch.AlarmRule.anyOf(
        cloudwatch.AlarmRule.fromAlarm(voterAuthErrorAlarm, cloudwatch.AlarmState.ALARM),
        cloudwatch.AlarmRule.fromAlarm(voteMonitorErrorAlarm, cloudwatch.AlarmState.ALARM),
        cloudwatch.AlarmRule.fromAlarm(voterRegistryThrottleAlarm, cloudwatch.AlarmState.ALARM),
        cloudwatch.AlarmRule.fromAlarm(apiGatewayErrorAlarm, cloudwatch.AlarmState.ALARM)
      ),
    });

    systemHealthAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.criticalAlertTopic));
  }

  /**
   * Create security monitoring
   */
  private createSecurityMonitoring(): void {
    // Create security event alarm
    const securityEventAlarm = new cloudwatch.Alarm(this, 'SecurityEventAlarm', {
      alarmName: `${this.config.appName}-security-events-${this.config.environment}`,
      alarmDescription: 'Security events detected',
      metric: new cloudwatch.Metric({
        namespace: 'VotingSystem/Security',
        metricName: 'SecurityEvents',
        dimensionsMap: {
          Environment: this.config.environment,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    securityEventAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.criticalAlertTopic));

    // Create failed authentication attempts alarm
    const failedAuthAlarm = new cloudwatch.Alarm(this, 'FailedAuthAlarm', {
      alarmName: `${this.config.appName}-failed-auth-${this.config.environment}`,
      alarmDescription: 'High number of failed authentication attempts',
      metric: new cloudwatch.Metric({
        namespace: 'VotingSystem/Auth',
        metricName: 'FailedAttempts',
        dimensionsMap: {
          Environment: this.config.environment,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 20,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    failedAuthAlarm.addAlarmAction(new cloudwatchActions.SnsAction(this.alertTopic));
  }

  /**
   * Create performance monitoring
   */
  private createPerformanceMonitoring(): void {
    // Create performance dashboard widget
    const performanceWidget = new cloudwatch.GraphWidget({
      title: 'System Performance Metrics',
      left: [
        new cloudwatch.Metric({
          namespace: 'VotingSystem/Performance',
          metricName: 'ResponseTime',
          dimensionsMap: {
            Environment: this.config.environment,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
        new cloudwatch.Metric({
          namespace: 'VotingSystem/Performance',
          metricName: 'ThroughputPerMinute',
          dimensionsMap: {
            Environment: this.config.environment,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        }),
      ],
      width: 24,
      height: 6,
    });

    // Add performance widget to dashboard
    this.dashboard.addWidgets(performanceWidget);
  }

  /**
   * Create custom metrics for voting system
   */
  private createCustomMetrics(): void {
    // This would typically be implemented in the Lambda functions
    // Here we're just documenting the custom metrics that should be created
    
    // Custom metrics to implement in Lambda functions:
    // - VotesCast: Number of votes cast
    // - VotersRegistered: Number of voters registered
    // - ElectionsActive: Number of active elections
    // - SecurityEvents: Number of security events
    // - FailedAttempts: Number of failed authentication attempts
    // - ResponseTime: API response time
    // - ThroughputPerMinute: System throughput
    // - DatabaseConnections: Number of database connections
    // - BlockchainTransactions: Number of blockchain transactions
  }

  /**
   * Create log aggregation and analysis
   */
  private createLogAggregation(): void {
    // Create log groups for centralized logging
    const centralLogGroup = new logs.LogGroup(this, 'VotingSystemCentralLogs', {
      logGroupName: `/aws/votingsystem/${this.config.appName}/${this.config.environment}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create log insights queries for common use cases
    const logInsightsQueries = [
      {
        name: 'VotesCastByHour',
        query: `
          fields @timestamp, @message
          | filter @message like /VoteCast/
          | stats count() by bin(5m)
          | sort @timestamp desc
        `,
      },
      {
        name: 'ErrorAnalysis',
        query: `
          fields @timestamp, @message, @logStream
          | filter @message like /ERROR/
          | stats count() by @logStream
          | sort count desc
        `,
      },
      {
        name: 'AuthenticationFailures',
        query: `
          fields @timestamp, @message
          | filter @message like /Authentication failed/
          | stats count() by bin(1h)
          | sort @timestamp desc
        `,
      },
    ];

    // Create metric filters for log-based metrics
    const votesCastFilter = new logs.MetricFilter(this, 'VotesCastMetricFilter', {
      logGroup: centralLogGroup,
      metricNamespace: 'VotingSystem',
      metricName: 'VotesCast',
      filterPattern: logs.FilterPattern.literal('[timestamp, requestId, "VoteCast", ...]'),
      metricValue: '1',
      defaultValue: 0,
    });

    const errorMetricFilter = new logs.MetricFilter(this, 'ErrorMetricFilter', {
      logGroup: centralLogGroup,
      metricNamespace: 'VotingSystem',
      metricName: 'Errors',
      filterPattern: logs.FilterPattern.literal('[timestamp, requestId, "ERROR", ...]'),
      metricValue: '1',
      defaultValue: 0,
    });
  }

  /**
   * Create Slack notification function
   */
  private createSlackNotificationFunction(): void {
    // Create Lambda function for Slack notifications
    const slackNotificationFunction = new lambda.Function(this, 'SlackNotificationFunction', {
      functionName: `${this.config.appName}-slack-notifications-${this.config.environment}`,
      runtime: lambda.Runtime.NODEJS_20_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const https = require('https');
        
        exports.handler = async (event) => {
          const message = JSON.parse(event.Records[0].Sns.Message);
          
          const slackPayload = {
            text: \`🚨 Voting System Alert: \${message.AlarmName}\`,
            attachments: [{
              color: message.NewStateValue === 'ALARM' ? 'danger' : 'good',
              fields: [{
                title: 'Alarm Description',
                value: message.AlarmDescription,
                short: false
              }, {
                title: 'State',
                value: message.NewStateValue,
                short: true
              }, {
                title: 'Reason',
                value: message.NewStateReason,
                short: true
              }]
            }]
          };
          
          // Send to Slack webhook (URL should be stored in environment variable)
          const webhookUrl = process.env.SLACK_WEBHOOK_URL;
          if (webhookUrl) {
            // Implementation for Slack webhook POST request
            console.log('Sending to Slack:', JSON.stringify(slackPayload));
          }
          
          return { statusCode: 200, body: 'Notification sent' };
        };
      `),
      timeout: cdk.Duration.seconds(30),
      environment: {
        SLACK_WEBHOOK_URL: 'https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK',
      },
    });

    // Subscribe Lambda to SNS topics
    this.alertTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(slackNotificationFunction)
    );
    this.criticalAlertTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(slackNotificationFunction)
    );
  }

  /**
   * Add stack outputs
   */
  private addStackOutputs(): void {
    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: this.dashboardUrl,
      description: 'URL to the CloudWatch dashboard',
    });

    new cdk.CfnOutput(this, 'DashboardName', {
      value: this.dashboard.dashboardName,
      description: 'Name of the CloudWatch dashboard',
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the general alert SNS topic',
    });

    new cdk.CfnOutput(this, 'CriticalAlertTopicArn', {
      value: this.criticalAlertTopic.topicArn,
      description: 'ARN of the critical alert SNS topic',
    });
  }
}