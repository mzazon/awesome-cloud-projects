#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as scheduler from 'aws-cdk-lib/aws-scheduler';
import * as fis from 'aws-cdk-lib/aws-fis';

/**
 * Props for the ChaosEngineeringStack
 */
export interface ChaosEngineeringStackProps extends cdk.StackProps {
  /**
   * Email address for SNS notifications
   * @default 'your-email@example.com'
   */
  readonly notificationEmail?: string;
  
  /**
   * Schedule expression for automated chaos tests
   * @default 'cron(0 2 * * ? *)' - Daily at 2 AM
   */
  readonly scheduleExpression?: string;
  
  /**
   * Whether to enable the automated schedule
   * @default false
   */
  readonly enableSchedule?: boolean;
  
  /**
   * Environment suffix for resource naming
   * @default random 6-character string
   */
  readonly environmentSuffix?: string;
}

/**
 * CDK Stack for implementing chaos engineering testing with AWS FIS and EventBridge
 * 
 * This stack creates:
 * - IAM roles for FIS experiments and EventBridge
 * - SNS topic for notifications
 * - CloudWatch alarms for stop conditions
 * - FIS experiment template
 * - EventBridge rules for experiment notifications
 * - Optional scheduled chaos tests
 * - CloudWatch dashboard for monitoring
 */
export class ChaosEngineeringStack extends cdk.Stack {
  public readonly snsTopicArn: string;
  public readonly fisExperimentTemplateId: string;
  public readonly dashboardUrl: string;

  constructor(scope: Construct, id: string, props: ChaosEngineeringStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const suffix = props.environmentSuffix || this.generateRandomSuffix();
    
    // Parameters
    const notificationEmail = props.notificationEmail || 'your-email@example.com';
    const scheduleExpression = props.scheduleExpression || 'cron(0 2 * * ? *)';
    const enableSchedule = props.enableSchedule || false;

    // Create SNS topic for notifications
    const alertsTopic = new sns.Topic(this, 'FISAlertsTopic', {
      topicName: `fis-alerts-${suffix}`,
      displayName: 'AWS FIS Chaos Engineering Alerts',
    });

    // Add email subscription to SNS topic
    alertsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail)
    );

    this.snsTopicArn = alertsTopic.topicArn;

    // Create IAM role for FIS experiments
    const fisRole = new iam.Role(this, 'FISExperimentRole', {
      roleName: `FISExperimentRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('fis.amazonaws.com'),
      description: 'IAM role for AWS FIS chaos engineering experiments',
      managedPolicies: [
        // Note: In production, use a more restrictive custom policy
        iam.ManagedPolicy.fromAwsManagedPolicyName('PowerUserAccess'),
      ],
    });

    // Create CloudWatch alarms for stop conditions
    const errorAlarm = new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: `FIS-HighErrorRate-${suffix}`,
      alarmDescription: 'Stop FIS experiment on high error rate',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/ApplicationELB',
        metricName: '4XXError',
        statistic: 'Sum',
        period: cdk.Duration.minutes(1),
      }),
      threshold: 50,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const cpuAlarm = new cloudwatch.Alarm(this, 'HighCPUAlarm', {
      alarmName: `FIS-HighCPU-${suffix}`,
      alarmDescription: 'Monitor CPU utilization during experiments',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/EC2',
        metricName: 'CPUUtilization',
        statistic: 'Average',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 90,
      evaluationPeriods: 1,
    });

    // Create FIS experiment template
    const experimentTemplate = new fis.CfnExperimentTemplate(this, 'ChaosExperimentTemplate', {
      description: 'Multi-action chaos experiment for resilience testing',
      roleArn: fisRole.roleArn,
      
      // Stop conditions - safety mechanisms
      stopConditions: [
        {
          source: 'aws:cloudwatch:alarm',
          value: errorAlarm.alarmArn,
        },
      ],

      // Target selection - EC2 instances with ChaosReady tag
      targets: {
        'ec2-instances': {
          resourceType: 'aws:ec2:instance',
          selectionMode: 'COUNT(1)',
          resourceTags: {
            'ChaosReady': 'true',
          },
        },
      },

      // Experiment actions
      actions: {
        'cpu-stress': {
          actionId: 'aws:ssm:send-command',
          description: 'Inject CPU stress on EC2 instances',
          parameters: {
            documentArn: `arn:aws:ssm:${this.region}::document/AWSFIS-Run-CPU-Stress`,
            documentParameters: JSON.stringify({
              DurationSeconds: '120',
              CPU: '0',
              LoadPercent: '80',
            }),
            duration: 'PT3M',
          },
          targets: {
            Instances: 'ec2-instances',
          },
        },
        'terminate-instance': {
          actionId: 'aws:ec2:terminate-instances',
          description: 'Terminate EC2 instance to test recovery',
          targets: {
            Instances: 'ec2-instances',
          },
          startAfter: ['cpu-stress'],
        },
      },

      tags: {
        Environment: 'Testing',
        Purpose: 'ChaosEngineering',
        CreatedBy: 'CDK',
      },
    });

    this.fisExperimentTemplateId = experimentTemplate.ref;

    // Create IAM role for EventBridge
    const eventBridgeRole = new iam.Role(this, 'EventBridgeFISRole', {
      roleName: `EventBridgeFISRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
      description: 'IAM role for EventBridge to publish FIS notifications',
    });

    // Grant SNS publish permissions to EventBridge role
    alertsTopic.grantPublish(eventBridgeRole);

    // Create EventBridge rule for FIS state changes
    const fisStateChangeRule = new events.Rule(this, 'FISStateChangeRule', {
      ruleName: `FIS-ExperimentStateChanges-${suffix}`,
      description: 'Capture all FIS experiment state changes',
      eventPattern: {
        source: ['aws.fis'],
        detailType: ['FIS Experiment State Change'],
      },
    });

    // Add SNS target to EventBridge rule
    fisStateChangeRule.addTarget(
      new targets.SnsTopic(alertsTopic, {
        message: events.RuleTargetInput.fromObject({
          experimentId: events.EventField.fromPath('$.detail.experiment-id'),
          state: events.EventField.fromPath('$.detail.state.status'),
          reason: events.EventField.fromPath('$.detail.state.reason'),
          timestamp: events.EventField.fromPath('$.time'),
        }),
      })
    );

    // Create IAM role for EventBridge Scheduler (if enabled)
    let schedulerRole: iam.Role | undefined;
    if (enableSchedule) {
      schedulerRole = new iam.Role(this, 'SchedulerFISRole', {
        roleName: `SchedulerFISRole-${suffix}`,
        assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
        description: 'IAM role for EventBridge Scheduler to start FIS experiments',
      });

      // Grant FIS start experiment permissions
      schedulerRole.addToPolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['fis:StartExperiment'],
          resources: [
            `arn:aws:fis:${this.region}:${this.account}:experiment-template/${experimentTemplate.ref}`,
            `arn:aws:fis:${this.region}:${this.account}:experiment/*`,
          ],
        })
      );

      // Create EventBridge schedule for automated chaos tests
      new scheduler.CfnSchedule(this, 'DailyChaosSchedule', {
        name: `FIS-DailyChaosTest-${suffix}`,
        description: 'Automated daily chaos engineering tests',
        scheduleExpression: scheduleExpression,
        target: {
          arn: 'arn:aws:scheduler:::aws-sdk:fis:startExperiment',
          roleArn: schedulerRole.roleArn,
          input: JSON.stringify({
            ExperimentTemplateId: experimentTemplate.ref,
          }),
        },
        flexibleTimeWindow: {
          mode: 'OFF',
        },
      });
    }

    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'ChaosMonitoringDashboard', {
      dashboardName: `chaos-monitoring-${suffix}`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Add FIS experiment metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'FIS Experiment Status',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/FIS',
            metricName: 'ExperimentsStarted',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/FIS',
            metricName: 'ExperimentsStopped',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/FIS',
            metricName: 'ExperimentsFailed',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
      })
    );

    // Add application health metrics widget
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Application Health During Experiments',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/EC2',
            metricName: 'CPUUtilization',
            statistic: 'Average',
            period: cdk.Duration.minutes(1),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/ApplicationELB',
            metricName: 'TargetResponseTime',
            statistic: 'Average',
            period: cdk.Duration.minutes(1),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/ApplicationELB',
            metricName: 'HTTPCode_Target_4XX_Count',
            statistic: 'Sum',
            period: cdk.Duration.minutes(1),
          }),
        ],
        width: 12,
      })
    );

    this.dashboardUrl = `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`;

    // Stack Outputs
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      description: 'ARN of the SNS topic for FIS alerts',
      value: alertsTopic.topicArn,
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'FISExperimentTemplateId', {
      description: 'ID of the FIS experiment template',
      value: experimentTemplate.ref,
      exportName: `${this.stackName}-FISTemplateId`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      description: 'URL to the CloudWatch dashboard',
      value: this.dashboardUrl,
      exportName: `${this.stackName}-DashboardURL`,
    });

    new cdk.CfnOutput(this, 'FISRoleArn', {
      description: 'ARN of the FIS experiment role',
      value: fisRole.roleArn,
      exportName: `${this.stackName}-FISRoleArn`,
    });

    new cdk.CfnOutput(this, 'ErrorAlarmArn', {
      description: 'ARN of the high error rate alarm (stop condition)',
      value: errorAlarm.alarmArn,
      exportName: `${this.stackName}-ErrorAlarmArn`,
    });

    if (enableSchedule && schedulerRole) {
      new cdk.CfnOutput(this, 'SchedulerRoleArn', {
        description: 'ARN of the EventBridge Scheduler role',
        value: schedulerRole.roleArn,
        exportName: `${this.stackName}-SchedulerRoleArn`,
      });
    }
  }

  /**
   * Generate a random 6-character suffix for resource naming
   */
  private generateRandomSuffix(): string {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < 6; i++) {
      result += chars.charAt(Math.floor(Math.random() * chars.length));
    }
    return result;
  }
}

// CDK App
const app = new cdk.App();

// Get context values
const notificationEmail = app.node.tryGetContext('notificationEmail') || 'your-email@example.com';
const scheduleExpression = app.node.tryGetContext('scheduleExpression') || 'cron(0 2 * * ? *)';
const enableSchedule = app.node.tryGetContext('enableSchedule') === 'true';
const environmentSuffix = app.node.tryGetContext('environmentSuffix');

// Create the stack
new ChaosEngineeringStack(app, 'ChaosEngineeringStack', {
  description: 'Chaos Engineering with AWS FIS and EventBridge - CDK TypeScript',
  notificationEmail,
  scheduleExpression,
  enableSchedule,
  environmentSuffix,
  
  // Add stack-level tags
  tags: {
    Project: 'ChaosEngineering',
    Environment: 'Testing',
    CreatedBy: 'CDK',
    Purpose: 'ResilienceTesting',
  },
  
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();