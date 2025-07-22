#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ses from 'aws-cdk-lib/aws-ses';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import { Construct } from 'constructs';

/**
 * Properties for the AutomatedEmailNotificationStack
 */
interface AutomatedEmailNotificationStackProps extends cdk.StackProps {
  /** The verified sender email address for SES */
  readonly senderEmail: string;
  /** The default recipient email address for testing */
  readonly recipientEmail?: string;
  /** Environment name for resource naming */
  readonly environmentName?: string;
}

/**
 * CDK Stack for Automated Email Notification Systems
 * 
 * This stack creates a complete event-driven email notification system using:
 * - Amazon SES for email delivery
 * - AWS Lambda for email processing logic
 * - Amazon EventBridge for event routing and orchestration
 * - CloudWatch for monitoring and alerting
 */
export class AutomatedEmailNotificationStack extends cdk.Stack {
  /** The Lambda function that processes email notifications */
  public readonly emailProcessorFunction: lambda.Function;
  
  /** The custom EventBridge event bus */
  public readonly customEventBus: events.EventBus;
  
  /** The SES email template */
  public readonly emailTemplate: ses.CfnTemplate;

  constructor(scope: Construct, id: string, props: AutomatedEmailNotificationStackProps) {
    super(scope, id, props);

    // Validate required properties
    if (!props.senderEmail) {
      throw new Error('senderEmail property is required');
    }

    const environmentName = props.environmentName || 'dev';
    const projectName = `email-automation-${environmentName}`;

    // Create S3 bucket for Lambda deployment packages and logs
    const deploymentBucket = new s3.Bucket(this, 'DeploymentBucket', {
      bucketName: `lambda-deployment-${projectName}-${this.account}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    });

    // Create SES email template for notifications
    this.emailTemplate = new ses.CfnTemplate(this, 'NotificationTemplate', {
      template: {
        templateName: 'NotificationTemplate',
        subjectPart: '{{subject}}',
        htmlPart: `
          <html>
            <body style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
              <div style="background-color: #f8f9fa; padding: 20px; border-radius: 8px;">
                <h2 style="color: #343a40; margin-bottom: 20px;">{{title}}</h2>
                <div style="background-color: white; padding: 20px; border-radius: 4px; margin-bottom: 20px;">
                  <p style="color: #495057; line-height: 1.6;">{{message}}</p>
                </div>
                <div style="font-size: 12px; color: #6c757d;">
                  <p><strong>Timestamp:</strong> {{timestamp}}</p>
                  <p><strong>Event Source:</strong> {{source}}</p>
                </div>
              </div>
            </body>
          </html>
        `,
        textPart: `{{title}}\n\n{{message}}\n\nTimestamp: {{timestamp}}\nEvent Source: {{source}}`
      }
    });

    // Create IAM role for Lambda function with comprehensive permissions
    const lambdaRole = new iam.Role(this, 'EmailProcessorLambdaRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for email processor Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        'SESPermissions': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ses:SendEmail',
                'ses:SendRawEmail',
                'ses:SendTemplatedEmail',
                'ses:GetTemplate',
                'ses:ListTemplates'
              ],
              resources: ['*'], // SES resources don't support specific ARNs for these actions
            }),
          ],
        }),
        'CloudWatchPermissions': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for email processing with enhanced configuration
    this.emailProcessorFunction = new lambda.Function(this, 'EmailProcessorFunction', {
      functionName: `${projectName}-email-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      description: 'Processes events from EventBridge and sends email notifications via SES',
      environment: {
        SENDER_EMAIL: props.senderEmail,
        TEMPLATE_NAME: this.emailTemplate.ref,
        PROJECT_NAME: projectName,
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging with structured format
logger = logging.getLogger()
logger.setLevel(getattr(logging, os.environ.get('LOG_LEVEL', 'INFO')))

# Initialize AWS clients with error handling
try:
    ses_client = boto3.client('ses')
    cloudwatch = boto3.client('cloudwatch')
except Exception as e:
    logger.error(f"Failed to initialize AWS clients: {str(e)}")
    raise

def put_custom_metric(metric_name: str, value: float = 1.0, unit: str = 'Count') -> None:
    """Put custom metric to CloudWatch"""
    try:
        cloudwatch.put_metric_data(
            Namespace='EmailNotification/Custom',
            MetricData=[
                {
                    'MetricName': metric_name,
                    'Value': value,
                    'Unit': unit,
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
    except Exception as e:
        logger.warning(f"Failed to put metric {metric_name}: {str(e)}")

def extract_email_config(event: Dict[str, Any]) -> Dict[str, str]:
    """Extract email configuration from event with validation"""
    event_detail = event.get('detail', {})
    email_config = event_detail.get('emailConfig', {})
    
    # Default recipient fallback
    default_recipient = os.environ.get('DEFAULT_RECIPIENT', 'admin@example.com')
    
    return {
        'recipient': email_config.get('recipient', default_recipient),
        'subject': email_config.get('subject', f"Notification: {event.get('detail-type', 'Unknown Event')}"),
        'priority': email_config.get('priority', 'normal')
    }

def extract_content_data(event: Dict[str, Any]) -> Dict[str, str]:
    """Extract content data for email template"""
    event_detail = event.get('detail', {})
    event_source = event.get('source', 'unknown')
    event_type = event.get('detail-type', 'Unknown Event')
    
    return {
        'title': event_detail.get('title', event_type),
        'message': event_detail.get('message', 'No message provided'),
        'source': event_source,
        'timestamp': datetime.now().isoformat(),
        'event_id': event.get('id', 'unknown'),
        'region': event.get('region', 'unknown')
    }

def send_templated_email(recipient: str, subject: str, template_data: Dict[str, str]) -> str:
    """Send templated email via SES with comprehensive error handling"""
    template_name = os.environ.get('TEMPLATE_NAME', 'NotificationTemplate')
    sender_email = os.environ['SENDER_EMAIL']
    
    try:
        # Prepare template data with subject override
        template_data_with_subject = {**template_data, 'subject': subject}
        
        response = ses_client.send_templated_email(
            Source=sender_email,
            Destination={'ToAddresses': [recipient]},
            Template=template_name,
            TemplateData=json.dumps(template_data_with_subject)
        )
        
        message_id = response['MessageId']
        logger.info(f"Email sent successfully: {message_id} to {recipient}")
        put_custom_metric('EmailsSent')
        
        return message_id
        
    except ses_client.exceptions.MessageRejected as e:
        logger.error(f"SES message rejected: {str(e)}")
        put_custom_metric('EmailsRejected')
        raise
    except ses_client.exceptions.MailFromDomainNotVerifiedException as e:
        logger.error(f"Sender domain not verified: {str(e)}")
        put_custom_metric('EmailsFailedVerification')
        raise
    except Exception as e:
        logger.error(f"Failed to send email: {str(e)}")
        put_custom_metric('EmailsFailedOther')
        raise

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Main Lambda handler for processing email notification events"""
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        put_custom_metric('EventsProcessed')
        
        # Extract email configuration and content
        email_config = extract_email_config(event)
        content_data = extract_content_data(event)
        
        # Validate recipient email format (basic validation)
        recipient = email_config['recipient']
        if '@' not in recipient or '.' not in recipient:
            raise ValueError(f"Invalid recipient email format: {recipient}")
        
        # Send the email
        message_id = send_templated_email(
            recipient=recipient,
            subject=email_config['subject'],
            template_data=content_data
        )
        
        # Log success metrics
        put_custom_metric('EventsProcessedSuccessfully')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Email sent successfully',
                'messageId': message_id,
                'recipient': recipient,
                'timestamp': datetime.now().isoformat()
            }, default=str)
        }
        
    except ValueError as e:
        logger.error(f"Validation error: {str(e)}")
        put_custom_metric('ValidationErrors')
        return {
            'statusCode': 400,
            'body': json.dumps({'error': f'Validation error: {str(e)}'})
        }
    except Exception as e:
        logger.error(f"Error processing email notification: {str(e)}")
        put_custom_metric('ProcessingErrors')
        # Re-raise to trigger EventBridge retry mechanism
        raise e
`),
    });

    // Create custom EventBridge event bus for better organization
    this.customEventBus = new events.EventBus(this, 'CustomEventBus', {
      eventBusName: `${projectName}-event-bus`,
      description: 'Custom event bus for email notification events'
    });

    // Create EventBridge rule for standard email notifications
    const emailNotificationRule = new events.Rule(this, 'EmailNotificationRule', {
      eventBus: this.customEventBus,
      ruleName: `${projectName}-email-rule`,
      description: 'Route email notification requests to Lambda processor',
      eventPattern: {
        source: ['custom.application'],
        detailType: ['Email Notification Request'],
      },
      enabled: true,
    });

    // Add Lambda function as target for email notifications
    emailNotificationRule.addTarget(new targets.LambdaFunction(this.emailProcessorFunction, {
      maxEventAge: cdk.Duration.hours(2),
      retryAttempts: 3,
    }));

    // Create EventBridge rule for priority alerts
    const priorityAlertRule = new events.Rule(this, 'PriorityAlertRule', {
      eventBus: this.customEventBus,
      ruleName: `${projectName}-priority-rule`,
      description: 'Handle high priority alerts with immediate processing',
      eventPattern: {
        source: ['custom.application'],
        detailType: ['Priority Alert'],
        detail: {
          priority: ['high', 'critical']
        }
      },
      enabled: true,
    });

    // Add Lambda function as target for priority alerts
    priorityAlertRule.addTarget(new targets.LambdaFunction(this.emailProcessorFunction, {
      maxEventAge: cdk.Duration.minutes(30),
      retryAttempts: 5,
    }));

    // Create scheduled rule for daily reports (9 AM UTC)
    const dailyReportRule = new events.Rule(this, 'DailyReportRule', {
      ruleName: `${projectName}-daily-report`,
      description: 'Send daily email reports',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '9',
        day: '*',
        month: '*',
        year: '*'
      }),
      enabled: true,
    });

    // Add Lambda function as target for scheduled reports
    dailyReportRule.addTarget(new targets.LambdaFunction(this.emailProcessorFunction, {
      event: events.RuleTargetInput.fromObject({
        source: 'scheduled.reports',
        'detail-type': 'Daily Report',
        detail: {
          title: 'Daily System Report',
          message: 'This is your scheduled daily report from the email notification system.',
          emailConfig: {
            recipient: props.recipientEmail || props.senderEmail,
            subject: 'Daily System Report'
          }
        }
      }),
      maxEventAge: cdk.Duration.hours(1),
      retryAttempts: 2,
    }));

    // Create CloudWatch Log Group with retention policy
    const logGroup = new logs.LogGroup(this, 'EmailProcessorLogGroup', {
      logGroupName: `/aws/lambda/${this.emailProcessorFunction.functionName}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch alarms for monitoring
    const lambdaErrorAlarm = new cloudwatch.Alarm(this, 'LambdaErrorAlarm', {
      alarmName: `${projectName}-lambda-errors`,
      alarmDescription: 'Monitor Lambda function errors',
      metric: this.emailProcessorFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `${projectName}-lambda-duration`,
      alarmDescription: 'Monitor Lambda function duration',
      metric: this.emailProcessorFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average'
      }),
      threshold: 25000, // 25 seconds (83% of 30-second timeout)
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create SES bounce alarm (requires SES configuration set - optional)
    const sesBounceAlarm = new cloudwatch.Alarm(this, 'SESBounceAlarm', {
      alarmName: `${projectName}-ses-bounces`,
      alarmDescription: 'Monitor SES bounce rate',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SES',
        metricName: 'Bounce',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create custom metric filter for email processing errors
    new logs.MetricFilter(this, 'EmailProcessingErrorsFilter', {
      logGroup: logGroup,
      filterPattern: logs.FilterPattern.literal('ERROR'),
      metricNamespace: 'EmailNotification/Custom',
      metricName: 'EmailProcessingErrors',
      metricValue: '1',
      defaultValue: 0,
    });

    // Create custom metric filter for successful email sends
    new logs.MetricFilter(this, 'EmailsSentFilter', {
      logGroup: logGroup,
      filterPattern: logs.FilterPattern.literal('Email sent successfully'),
      metricNamespace: 'EmailNotification/Custom',
      metricName: 'EmailsSentFromLogs',
      metricValue: '1',
      defaultValue: 0,
    });

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'EmailNotificationDashboard', {
      dashboardName: `${projectName}-dashboard`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              this.emailProcessorFunction.metricInvocations(),
              this.emailProcessorFunction.metricErrors(),
            ],
            right: [
              this.emailProcessorFunction.metricDuration(),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Custom Email Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'EmailNotification/Custom',
                metricName: 'EmailsSent',
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
              new cloudwatch.Metric({
                namespace: 'EmailNotification/Custom',
                metricName: 'EmailsRejected',
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

    // Stack Outputs for easy reference
    new cdk.CfnOutput(this, 'EmailProcessorFunctionName', {
      value: this.emailProcessorFunction.functionName,
      description: 'Name of the email processor Lambda function',
      exportName: `${projectName}-lambda-function-name`,
    });

    new cdk.CfnOutput(this, 'CustomEventBusName', {
      value: this.customEventBus.eventBusName,
      description: 'Name of the custom EventBridge event bus',
      exportName: `${projectName}-event-bus-name`,
    });

    new cdk.CfnOutput(this, 'EmailTemplateName', {
      value: this.emailTemplate.ref,
      description: 'Name of the SES email template',
      exportName: `${projectName}-email-template-name`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${projectName}-dashboard`,
      description: 'URL to the CloudWatch dashboard',
    });

    new cdk.CfnOutput(this, 'TestEventCommand', {
      value: `aws events put-events --entries '[{"Source":"custom.application","DetailType":"Email Notification Request","Detail":"{\\"emailConfig\\":{\\"recipient\\":\\"${props.recipientEmail || props.senderEmail}\\",\\"subject\\":\\"Test Notification\\"},\\"title\\":\\"CDK Test Alert\\",\\"message\\":\\"This is a test notification from the CDK-deployed email system.\\"}","EventBusName":"${this.customEventBus.eventBusName}"}]'`,
      description: 'AWS CLI command to test the email notification system',
    });

    // Tags for cost allocation and management
    cdk.Tags.of(this).add('Project', projectName);
    cdk.Tags.of(this).add('Environment', environmentName);
    cdk.Tags.of(this).add('Service', 'EmailNotification');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

// CDK App definition
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const senderEmail = app.node.tryGetContext('senderEmail') || process.env.SENDER_EMAIL;
const recipientEmail = app.node.tryGetContext('recipientEmail') || process.env.RECIPIENT_EMAIL;
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';

if (!senderEmail) {
  throw new Error('senderEmail must be provided via CDK context or SENDER_EMAIL environment variable');
}

// Create the stack
new AutomatedEmailNotificationStack(app, 'AutomatedEmailNotificationStack', {
  senderEmail,
  recipientEmail,
  environmentName,
  description: 'Automated Email Notification System using SES, Lambda, and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();