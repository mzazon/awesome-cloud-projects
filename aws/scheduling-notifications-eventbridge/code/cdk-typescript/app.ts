#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { 
  Stack, 
  StackProps, 
  CfnParameter, 
  CfnOutput, 
  Tags 
} from 'aws-cdk-lib';
import { 
  Topic, 
  Subscription, 
  SubscriptionProtocol 
} from 'aws-cdk-lib/aws-sns';
import { 
  Role, 
  ServicePrincipal, 
  PolicyStatement, 
  Effect 
} from 'aws-cdk-lib/aws-iam';
import { 
  CfnScheduleGroup, 
  CfnSchedule 
} from 'aws-cdk-lib/aws-scheduler';
import { Construct } from 'constructs';

/**
 * Interface defining the properties for the SimpleBusinessNotificationsStack
 */
interface SimpleBusinessNotificationsStackProps extends StackProps {
  /**
   * Email address for receiving business notifications
   */
  notificationEmail?: string;
  
  /**
   * Timezone for schedule expressions (default: America/New_York)
   */
  timezone?: string;
  
  /**
   * Environment name for resource tagging (default: dev)
   */
  environment?: string;
}

/**
 * CDK Stack for Simple Business Notifications using EventBridge Scheduler and SNS
 * 
 * This stack creates:
 * - SNS Topic for business notifications
 * - Email subscription to the SNS topic
 * - IAM role for EventBridge Scheduler with SNS publish permissions
 * - Schedule group for organizing business notification schedules
 * - Three example schedules: daily, weekly, and monthly business notifications
 */
export class SimpleBusinessNotificationsStack extends Stack {
  
  public readonly snsTopic: Topic;
  public readonly schedulerRole: Role;
  public readonly scheduleGroup: CfnScheduleGroup;

  constructor(scope: Construct, id: string, props: SimpleBusinessNotificationsStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const timezone = props.timezone || 'America/New_York';
    const environment = props.environment || 'dev';

    // CloudFormation parameter for email address
    const emailParameter = new CfnParameter(this, 'NotificationEmail', {
      type: 'String',
      description: 'Email address for receiving business notifications',
      constraintDescription: 'Must be a valid email address',
      default: props.notificationEmail || '',
      allowedPattern: '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
    });

    // Create SNS Topic for business notifications
    this.snsTopic = new Topic(this, 'BusinessNotificationsTopic', {
      topicName: `business-notifications-${environment}`,
      displayName: 'Business Notifications',
      description: 'SNS topic for automated business notifications and alerts'
    });

    // Create email subscription if email parameter is provided
    if (emailParameter.valueAsString) {
      const emailSubscription = new Subscription(this, 'EmailSubscription', {
        topic: this.snsTopic,
        protocol: SubscriptionProtocol.EMAIL,
        endpoint: emailParameter.valueAsString
      });

      // Add metadata to email subscription
      emailSubscription.node.addMetadata('Description', 'Email subscription for business notifications');
    }

    // Create IAM role for EventBridge Scheduler
    this.schedulerRole = new Role(this, 'EventBridgeSchedulerRole', {
      roleName: `eventbridge-scheduler-role-${environment}`,
      assumedBy: new ServicePrincipal('scheduler.amazonaws.com'),
      description: 'Execution role for EventBridge Scheduler to publish messages to SNS'
    });

    // Add SNS publish permissions to the scheduler role
    this.schedulerRole.addToPolicy(new PolicyStatement({
      effect: Effect.ALLOW,
      actions: ['sns:Publish'],
      resources: [this.snsTopic.topicArn],
      sid: 'AllowSNSPublish'
    }));

    // Create schedule group for organizing business notification schedules
    this.scheduleGroup = new CfnScheduleGroup(this, 'BusinessScheduleGroup', {
      name: `business-schedules-${environment}`,
      tags: [
        {
          key: 'Purpose',
          value: 'BusinessNotifications'
        },
        {
          key: 'Environment', 
          value: environment
        }
      ]
    });

    // Create daily business report schedule (9 AM on weekdays)
    const dailySchedule = new CfnSchedule(this, 'DailyBusinessReportSchedule', {
      name: 'daily-business-report',
      groupName: this.scheduleGroup.name,
      scheduleExpression: 'cron(0 9 ? * MON-FRI *)',
      scheduleExpressionTimezone: timezone,
      description: 'Daily business report notification sent at 9 AM on weekdays',
      target: {
        arn: this.snsTopic.topicArn,
        roleArn: this.schedulerRole.roleArn,
        snsParameters: {
          subject: 'Daily Business Report - Ready for Review',
          message: 'Good morning! Your daily business report is ready for review. Please check the dashboard for key metrics including sales performance, customer engagement, and operational status. Have a great day!'
        }
      },
      flexibleTimeWindow: {
        mode: 'FLEXIBLE',
        maximumWindowInMinutes: 15
      },
      state: 'ENABLED'
    });

    // Ensure the schedule group exists before creating schedules
    dailySchedule.addDependency(this.scheduleGroup);

    // Create weekly summary schedule (Monday 8 AM)
    const weeklySchedule = new CfnSchedule(this, 'WeeklyBusinessSummarySchedule', {
      name: 'weekly-summary',
      groupName: this.scheduleGroup.name,
      scheduleExpression: 'cron(0 8 ? * MON *)',
      scheduleExpressionTimezone: timezone,
      description: 'Weekly business summary notification sent on Monday mornings',
      target: {
        arn: this.snsTopic.topicArn,
        roleArn: this.schedulerRole.roleArn,
        snsParameters: {
          subject: 'Weekly Business Summary - New Week Ahead',
          message: 'Good Monday morning! Here is your weekly business summary with key achievements from last week and priorities for the week ahead. Review the quarterly goals progress and upcoming milestones. Let us make this week productive!'
        }
      },
      flexibleTimeWindow: {
        mode: 'FLEXIBLE',
        maximumWindowInMinutes: 30
      },
      state: 'ENABLED'
    });

    // Ensure the schedule group exists before creating schedules
    weeklySchedule.addDependency(this.scheduleGroup);

    // Create monthly reminder schedule (1st of each month at 10 AM)
    const monthlySchedule = new CfnSchedule(this, 'MonthlyBusinessReminderSchedule', {
      name: 'monthly-reminder',
      groupName: this.scheduleGroup.name,
      scheduleExpression: 'cron(0 10 1 * ? *)',
      scheduleExpressionTimezone: timezone,
      description: 'Monthly business reminder notification sent on the first day of each month',
      target: {
        arn: this.snsTopic.topicArn,
        roleArn: this.schedulerRole.roleArn,
        snsParameters: {
          subject: 'Monthly Business Reminder - Important Tasks',
          message: 'Welcome to a new month! This is your monthly reminder for important business tasks: review financial reports, update quarterly projections, conduct team performance reviews, and assess goal progress. Schedule time for strategic planning and process improvements.'
        }
      },
      flexibleTimeWindow: {
        mode: 'OFF'
      },
      state: 'ENABLED'
    });

    // Ensure the schedule group exists before creating schedules
    monthlySchedule.addDependency(this.scheduleGroup);

    // Add tags to all resources
    Tags.of(this).add('Project', 'SimpleBusinessNotifications');
    Tags.of(this).add('Environment', environment);
    Tags.of(this).add('ManagedBy', 'CDK');
    Tags.of(this).add('Purpose', 'BusinessNotifications');

    // CloudFormation outputs
    new CfnOutput(this, 'SNSTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'ARN of the SNS topic for business notifications',
      exportName: `${this.stackName}-SNSTopicArn`
    });

    new CfnOutput(this, 'SNSTopicName', {
      value: this.snsTopic.topicName,
      description: 'Name of the SNS topic for business notifications',
      exportName: `${this.stackName}-SNSTopicName`
    });

    new CfnOutput(this, 'SchedulerRoleArn', {
      value: this.schedulerRole.roleArn,
      description: 'ARN of the IAM role used by EventBridge Scheduler',
      exportName: `${this.stackName}-SchedulerRoleArn`
    });

    new CfnOutput(this, 'ScheduleGroupName', {
      value: this.scheduleGroup.name!,
      description: 'Name of the EventBridge Scheduler schedule group',
      exportName: `${this.stackName}-ScheduleGroupName`
    });

    new CfnOutput(this, 'NotificationEmailParameter', {
      value: emailParameter.valueAsString,
      description: 'Email address configured for business notifications',
      exportName: `${this.stackName}-NotificationEmail`
    });
  }
}

// CDK App initialization
const app = new cdk.App();

// Get context values for configuration
const environment = app.node.tryGetContext('environment') || 'dev';
const notificationEmail = app.node.tryGetContext('notificationEmail');
const timezone = app.node.tryGetContext('timezone') || 'America/New_York';

// Create the stack
new SimpleBusinessNotificationsStack(app, 'SimpleBusinessNotificationsStack', {
  stackName: `simple-business-notifications-${environment}`,
  description: 'Simple business notifications system using EventBridge Scheduler and SNS',
  notificationEmail,
  timezone,
  environment,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'SimpleBusinessNotifications',
    Environment: environment,
    ManagedBy: 'CDK'
  }
});

// Synthesize the CloudFormation template
app.synth();