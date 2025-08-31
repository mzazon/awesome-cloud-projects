#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as ce from 'aws-cdk-lib/aws-ce';
import { Construct } from 'constructs';

/**
 * Properties for the Cost Monitoring Stack
 */
export interface CostMonitoringStackProps extends cdk.StackProps {
  readonly monthlyBudgetLimit: number;
  readonly notificationEmails: string[];
  readonly budgetName?: string;
  readonly costCenterTags?: { [key: string]: string };
}

/**
 * AWS Cost Monitoring Stack with Budget Alerts and SNS Notifications
 * 
 * This stack implements comprehensive cost monitoring using:
 * - AWS Budgets with multiple graduated thresholds (50%, 75%, 90%, 100% forecasted)
 * - SNS topic for email notifications
 * - Cost Explorer integration for historical analysis
 * - CloudWatch dashboard for cost visualization
 * - Cost Anomaly Detection for intelligent monitoring
 */
export class CostMonitoringStack extends cdk.Stack {
  public readonly alertTopic: sns.Topic;
  public readonly budget: budgets.CfnBudget;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: CostMonitoringStackProps) {
    super(scope, id, props);

    // Validate input parameters
    this.validateInputs(props);

    // Create SNS Topic for budget notifications
    this.alertTopic = this.createNotificationTopic(props.notificationEmails);

    // Create AWS Budget with graduated alert thresholds
    this.budget = this.createBudgetWithThresholds(props);

    // Create Cost Anomaly Detection for additional monitoring
    this.createCostAnomalyDetection();

    // Create CloudWatch Dashboard for cost visualization
    this.dashboard = this.createCostDashboard();

    // Apply resource tagging for cost allocation
    this.addCostTags(props.costCenterTags);

    // Output important resource ARNs
    this.createOutputs();
  }

  /**
   * Validates input parameters to ensure they meet requirements
   */
  private validateInputs(props: CostMonitoringStackProps): void {
    if (props.monthlyBudgetLimit <= 0) {
      throw new Error('Monthly budget limit must be greater than 0');
    }

    if (props.notificationEmails.length === 0) {
      throw new Error('At least one notification email must be provided');
    }

    // Validate email format using regex
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    props.notificationEmails.forEach(email => {
      if (!emailRegex.test(email.trim())) {
        throw new Error(`Invalid email format: ${email}`);
      }
    });
  }

  /**
   * Creates SNS topic for budget alert notifications with email subscriptions
   */
  private createNotificationTopic(emails: string[]): sns.Topic {
    const topic = new sns.Topic(this, 'BudgetAlertTopic', {
      displayName: 'AWS Cost Monitoring Budget Alerts',
      topicName: `budget-alerts-${this.account}`,
      enforceSSL: true,
    });

    // Add email subscriptions for each provided email address
    emails.forEach((email, index) => {
      topic.addSubscription(
        new subscriptions.EmailSubscription(email.trim(), {
          json: false, // Send plain text emails for better readability
        })
      );
    });

    // Grant AWS Budgets service permission to publish to the topic
    topic.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AllowBudgetServicePublish',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('budgets.amazonaws.com')],
        actions: ['sns:Publish'],
        resources: [topic.topicArn],
        conditions: {
          StringEquals: {
            'aws:SourceAccount': this.account,
          },
        },
      })
    );

    return topic;
  }

  /**
   * Creates AWS Budget with multiple graduated alert thresholds
   */
  private createBudgetWithThresholds(props: CostMonitoringStackProps): budgets.CfnBudget {
    const budgetName = props.budgetName || `monthly-cost-budget-${this.account}`;
    
    // Get current date for budget start period
    const currentDate = new Date();
    const budgetStartDate = new Date(currentDate.getFullYear(), currentDate.getMonth(), 1);

    // Define graduated alert thresholds
    const alertThresholds = [
      { percentage: 50, type: 'ACTUAL', description: 'Early Warning - 50% of budget reached' },
      { percentage: 75, type: 'ACTUAL', description: 'Action Required - 75% of budget reached' },
      { percentage: 90, type: 'ACTUAL', description: 'Critical Alert - 90% of budget reached' },
      { percentage: 100, type: 'FORECASTED', description: 'Budget Forecast - 100% forecasted spend' },
    ];

    const budget = new budgets.CfnBudget(this, 'MonthlyCostBudget', {
      budget: {
        budgetName,
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        timePeriod: {
          start: budgetStartDate.toISOString().split('T')[0],
          end: '2087-06-15', // Far future end date for ongoing monitoring
        },
        budgetLimit: {
          amount: props.monthlyBudgetLimit,
          unit: 'USD',
        },
        // Comprehensive cost tracking configuration
        costTypes: {
          includeTax: true,
          includeSubscription: true,
          useBlended: false,
          includeRefund: false,
          includeCredit: false,
          includeUpfront: true,
          includeRecurring: true,
          includeOtherSubscription: true,
          includeSupport: true,
          includeDiscount: true,
          useAmortized: false,
        },
        // Filter out refunds and credits for accurate monitoring
        costFilters: {},
      },
      // Configure notifications for each threshold
      notificationsWithSubscribers: alertThresholds.map((threshold) => ({
        notification: {
          notificationType: threshold.type as 'ACTUAL' | 'FORECASTED',
          comparisonOperator: 'GREATER_THAN',
          threshold: threshold.percentage,
          thresholdType: 'PERCENTAGE',
          notificationState: 'ALARM',
        },
        subscribers: [
          {
            subscriptionType: 'SNS',
            address: this.alertTopic.topicArn,
          },
        ],
      })),
    });

    // Ensure SNS topic policy is created before budget
    budget.node.addDependency(this.alertTopic);

    return budget;
  }

  /**
   * Creates Cost Anomaly Detection for intelligent spending anomaly alerts
   */
  private createCostAnomalyDetection(): void {
    // Create anomaly detector for service-level monitoring
    const anomalyDetector = new ce.CfnAnomalyDetector(this, 'ServiceCostAnomalyDetector', {
      anomalyDetectorName: `cost-anomaly-detector-${this.account}`,
      monitorType: 'DIMENSIONAL',
      monitorSpecification: {
        dimension: 'SERVICE',
        matchOptions: ['EQUALS'],
        values: ['Amazon Elastic Compute Cloud - Compute', 'AWS Lambda', 'Amazon Simple Storage Service', 'Amazon Relational Database Service'],
      },
    });

    // Create anomaly subscription for daily monitoring
    new ce.CfnAnomalySubscription(this, 'CostAnomalySubscription', {
      subscriptionName: `cost-anomaly-subscription-${this.account}`,
      frequency: 'DAILY',
      monitorArnList: [anomalyDetector.attrAnomalyDetectorArn],
      subscribers: [
        {
          type: 'SNS',
          address: this.alertTopic.topicArn,
        },
      ],
      threshold: 50, // Alert on anomalies >= $50
      thresholdExpression: 'GREATER_THAN_OR_EQUAL_TO',
    });
  }

  /**
   * Creates CloudWatch Dashboard for cost monitoring visualization
   */
  private createCostDashboard(): cloudwatch.Dashboard {
    const dashboard = new cloudwatch.Dashboard(this, 'CostMonitoringDashboard', {
      dashboardName: `cost-monitoring-${this.account}`,
    });

    // Create billing metric for estimated charges
    const estimatedChargesMetric = new cloudwatch.Metric({
      namespace: 'AWS/Billing',
      metricName: 'EstimatedCharges',
      dimensionsMap: {
        Currency: 'USD',
      },
      statistic: cloudwatch.Stats.MAXIMUM,
      period: cdk.Duration.hours(6),
    });

    // Add widgets to dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Monthly Estimated Charges Trend',
        left: [estimatedChargesMetric],
        width: 12,
        height: 6,
        period: cdk.Duration.hours(6),
        statistic: cloudwatch.Stats.MAXIMUM,
        view: cloudwatch.GraphWidgetView.TIME_SERIES,
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Current Month Estimate (USD)',
        metrics: [estimatedChargesMetric],
        width: 6,
        height: 4,
        sparkline: true,
      }),
      new cloudwatch.TextWidget({
        markdown: [
          '## Cost Monitoring Dashboard',
          '',
          '**Budget Limit:** $' + this.node.tryGetContext('monthlyBudgetLimit') || 'Not specified',
          '',
          '**Alert Thresholds:**',
          '- 🟡 50% - Early Warning',
          '- 🟠 75% - Action Required', 
          '- 🔴 90% - Critical Alert',
          '- 🔮 100% - Forecasted Exceed',
          '',
          '**Features:**',
          '- Real-time cost monitoring',
          '- Email notifications via SNS',
          '- Cost anomaly detection',
          '- Historical trend analysis',
        ].join('\n'),
        width: 6,
        height: 4,
      })
    );

    return dashboard;
  }

  /**
   * Applies consistent resource tagging for cost allocation and management
   */
  private addCostTags(costCenterTags?: { [key: string]: string }): void {
    const defaultTags = {
      Project: 'CostMonitoring',
      Environment: this.node.tryGetContext('environment') || 'production',
      Owner: 'FinOps',
      Service: 'BudgetManagement',
      AutoShutdown: 'false',
    };

    const allTags = { ...defaultTags, ...costCenterTags };

    // Apply tags to all resources in the stack
    Object.entries(allTags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }

  /**
   * Creates CloudFormation outputs for important resource references
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.alertTopic.topicArn,
      description: 'ARN of the SNS topic for budget alerts',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'BudgetName', {
      value: this.budget.budget.budgetName!,
      description: 'Name of the created AWS Budget',
      exportName: `${this.stackName}-BudgetName`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch cost monitoring dashboard',
      exportName: `${this.stackName}-DashboardURL`,
    });

    new cdk.CfnOutput(this, 'BudgetLimit', {
      value: this.budget.budget.budgetLimit!.amount!.toString() + ' USD',
      description: 'Monthly budget limit amount',
      exportName: `${this.stackName}-BudgetLimit`,
    });
  }
}

// CDK Application entry point
const app = new cdk.App();

// Environment configuration - Budget resources must be in us-east-1
const environment = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: 'us-east-1', // AWS Budgets requires us-east-1 region
};

// Configuration from context or environment variables
const monthlyBudgetLimit = parseFloat(app.node.tryGetContext('monthlyBudgetLimit') || process.env.MONTHLY_BUDGET_LIMIT || '100');
const notificationEmails = (app.node.tryGetContext('notificationEmails') || process.env.NOTIFICATION_EMAILS || 'your-email@example.com')
  .split(',')
  .map((email: string) => email.trim())
  .filter(Boolean);

const costCenterTags = {
  CostCenter: app.node.tryGetContext('costCenter') || process.env.COST_CENTER || 'Engineering',
  Department: app.node.tryGetContext('department') || process.env.DEPARTMENT || 'Technology',
};

// Stack properties
const stackProps: CostMonitoringStackProps = {
  env: environment,
  monthlyBudgetLimit,
  notificationEmails,
  costCenterTags,
  description: 'AWS Cost Monitoring with Budgets, SNS notifications, and Cost Explorer integration',
  tags: {
    Application: 'CostMonitoring',
    Version: '1.0.0',
    CreatedBy: 'CDK',
  },
};

// Create the Cost Monitoring Stack
new CostMonitoringStack(app, 'CostMonitoringStack', stackProps);

// Synthesize the app
app.synth();