import * as cdk from 'aws-cdk-lib';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';

export interface BudgetMonitoringStackProps extends cdk.StackProps {
  /**
   * Monthly budget amount in USD
   */
  readonly budgetAmount: number;
  
  /**
   * Email address for budget notifications
   */
  readonly notificationEmail: string;
}

/**
 * Stack that implements comprehensive budget monitoring with AWS Budgets and SNS
 * 
 * Features:
 * - Monthly cost budget with configurable spending limit
 * - Multi-threshold alerting (80% and 100% actual spend, 80% forecasted)
 * - SNS topic for reliable notification delivery
 * - Email subscription with proper security configurations
 */
export class BudgetMonitoringStack extends cdk.Stack {
  public readonly snsTopic: sns.Topic;
  public readonly budget: budgets.CfnBudget;

  constructor(scope: Construct, id: string, props: BudgetMonitoringStackProps) {
    super(scope, id, props);

    // Validate input parameters
    if (props.budgetAmount <= 0) {
      throw new Error('Budget amount must be greater than 0');
    }

    if (!this.isValidEmail(props.notificationEmail)) {
      throw new Error('Invalid email address provided');
    }

    // Create SNS topic for budget notifications
    this.snsTopic = new sns.Topic(this, 'BudgetAlertsTopic', {
      displayName: 'Budget Monitoring Alerts',
      topicName: `budget-alerts-${this.generateRandomSuffix()}`,
    });

    // Add email subscription to SNS topic
    this.snsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(props.notificationEmail)
    );

    // Create comprehensive budget with multiple notification thresholds
    this.budget = new budgets.CfnBudget(this, 'MonthlyBudget', {
      budget: {
        budgetName: `monthly-cost-budget-${this.generateRandomSuffix()}`,
        budgetType: 'COST',
        timeUnit: 'MONTHLY',
        budgetLimit: {
          amount: props.budgetAmount,
          unit: 'USD',
        },
        timePeriod: {
          start: this.getCurrentMonthStart(),
          end: '3706473600', // Far future date (2087)
        },
        costTypes: {
          includeCredit: true,
          includeDiscount: true,
          includeOtherSubscription: true,
          includeRecurring: true,
          includeRefund: true,
          includeSubscription: true,
          includeSupport: true,
          includeTax: true,
          includeUpfront: true,
          useBlended: false,
        },
      },
      notificationsWithSubscribers: [
        // 80% actual spend threshold
        {
          notification: {
            comparisonOperator: 'GREATER_THAN',
            notificationType: 'ACTUAL',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              address: this.snsTopic.topicArn,
              subscriptionType: 'SNS',
            },
          ],
        },
        // 100% actual spend threshold
        {
          notification: {
            comparisonOperator: 'GREATER_THAN',
            notificationType: 'ACTUAL',
            threshold: 100,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              address: this.snsTopic.topicArn,
              subscriptionType: 'SNS',
            },
          ],
        },
        // 80% forecasted spend threshold
        {
          notification: {
            comparisonOperator: 'GREATER_THAN',
            notificationType: 'FORECASTED',
            threshold: 80,
            thresholdType: 'PERCENTAGE',
          },
          subscribers: [
            {
              address: this.snsTopic.topicArn,
              subscriptionType: 'SNS',
            },
          ],
        },
      ],
    });

    // Grant AWS Budgets permission to publish to SNS topic
    this.snsTopic.addToResourcePolicy(
      new cdk.aws_iam.PolicyStatement({
        sid: 'AllowBudgetsToPublish',
        effect: cdk.aws_iam.Effect.ALLOW,
        principals: [new cdk.aws_iam.ServicePrincipal('budgets.amazonaws.com')],
        actions: ['sns:Publish'],
        resources: [this.snsTopic.topicArn],
        conditions: {
          StringEquals: {
            'aws:SourceAccount': this.account,
          },
        },
      })
    );

    // Create stack outputs for verification and integration
    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'ARN of the SNS topic for budget notifications',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'BudgetName', {
      value: this.budget.budget.budgetName,
      description: 'Name of the created budget',
      exportName: `${this.stackName}-BudgetName`,
    });

    new cdk.CfnOutput(this, 'BudgetAmount', {
      value: props.budgetAmount.toString(),
      description: 'Monthly budget amount in USD',
      exportName: `${this.stackName}-BudgetAmount`,
    });

    new cdk.CfnOutput(this, 'NotificationEmail', {
      value: props.notificationEmail,
      description: 'Email address for budget notifications',
    });
  }

  /**
   * Validates email address format
   */
  private isValidEmail(email: string): boolean {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
  }

  /**
   * Generates a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }

  /**
   * Gets the start of the current month in epoch format
   */
  private getCurrentMonthStart(): string {
    const now = new Date();
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
    return Math.floor(startOfMonth.getTime() / 1000).toString();
  }
}