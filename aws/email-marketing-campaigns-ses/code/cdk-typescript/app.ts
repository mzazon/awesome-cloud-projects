#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as ses from 'aws-cdk-lib/aws-ses';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Props for the EmailMarketingStack
 */
export interface EmailMarketingStackProps extends cdk.StackProps {
  /**
   * The domain to verify for sending emails
   * @default 'example.com'
   */
  readonly senderDomain?: string;
  
  /**
   * The email address to verify for sending emails
   * @default 'marketing@example.com'
   */
  readonly senderEmail?: string;
  
  /**
   * The email address to receive notifications
   * @default 'notifications@example.com'
   */
  readonly notificationEmail?: string;
  
  /**
   * Enable automated bounce handling
   * @default true
   */
  readonly enableBounceHandling?: boolean;
  
  /**
   * Enable weekly campaign automation
   * @default true
   */
  readonly enableCampaignAutomation?: boolean;
}

/**
 * CDK Stack for Email Marketing Campaigns with Amazon SES
 * 
 * This stack creates a comprehensive email marketing platform using:
 * - Amazon SES for email delivery
 * - S3 for template and subscriber list storage
 * - SNS for event notifications
 * - Lambda for automated bounce handling
 * - CloudWatch for monitoring and analytics
 * - EventBridge for campaign automation
 */
export class EmailMarketingStack extends cdk.Stack {
  public readonly emailBucket: s3.Bucket;
  public readonly emailEventsTopic: sns.Topic;
  public readonly configurationSet: ses.ConfigurationSet;
  public readonly bounceHandlerFunction: lambda.Function;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: EmailMarketingStackProps = {}) {
    super(scope, id, props);

    // Extract props with defaults
    const senderDomain = props.senderDomain ?? 'example.com';
    const senderEmail = props.senderEmail ?? 'marketing@example.com';
    const notificationEmail = props.notificationEmail ?? 'notifications@example.com';
    const enableBounceHandling = props.enableBounceHandling ?? true;
    const enableCampaignAutomation = props.enableCampaignAutomation ?? true;

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.tryGetContext('uniqueSuffix') || 
                        Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for email templates and subscriber lists
    this.emailBucket = new s3.Bucket(this, 'EmailMarketingBucket', {
      bucketName: `email-marketing-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // Create SNS topic for email event notifications
    this.emailEventsTopic = new sns.Topic(this, 'EmailEventsTopic', {
      topicName: `email-events-${uniqueSuffix}`,
      displayName: 'Email Marketing Events',
      fifo: false,
    });

    // Subscribe notification email to SNS topic
    this.emailEventsTopic.addSubscription(
      new snsSubscriptions.EmailSubscription(notificationEmail, {
        json: false,
      })
    );

    // Create SES configuration set for email tracking
    this.configurationSet = new ses.ConfigurationSet(this, 'MarketingConfigurationSet', {
      configurationSetName: `marketing-campaigns-${uniqueSuffix}`,
      suppressionOptions: {
        suppressedReasons: [
          ses.SuppressionReasons.BOUNCE,
          ses.SuppressionReasons.COMPLAINT,
        ],
      },
      deliveryOptions: {
        tlsPolicy: ses.TlsPolicy.REQUIRE,
      },
      reputationOptions: {
        reputationMetricsEnabled: true,
      },
      sendingOptions: {
        sendingEnabled: true,
      },
    });

    // Add SNS event destination to configuration set
    this.configurationSet.addEventDestination('SnsEventDestination', {
      destination: ses.EventDestination.snsTopic(this.emailEventsTopic),
      events: [
        ses.EmailSendingEvent.SEND,
        ses.EmailSendingEvent.BOUNCE,
        ses.EmailSendingEvent.COMPLAINT,
        ses.EmailSendingEvent.DELIVERY,
        ses.EmailSendingEvent.OPEN,
        ses.EmailSendingEvent.CLICK,
        ses.EmailSendingEvent.RENDERING_FAILURE,
        ses.EmailSendingEvent.DELIVERY_DELAY,
      ],
      enabled: true,
    });

    // Add CloudWatch event destination to configuration set
    this.configurationSet.addEventDestination('CloudWatchEventDestination', {
      destination: ses.EventDestination.cloudWatchDimensions({
        defaultDimensionValue: 'default',
        dimensionConfigurations: {
          MessageTag: {
            dimensionValueSource: ses.DimensionValueSource.MESSAGE_TAG,
            defaultDimensionValue: 'campaign',
          },
        },
      }),
      events: [
        ses.EmailSendingEvent.SEND,
        ses.EmailSendingEvent.BOUNCE,
        ses.EmailSendingEvent.COMPLAINT,
        ses.EmailSendingEvent.DELIVERY,
        ses.EmailSendingEvent.OPEN,
        ses.EmailSendingEvent.CLICK,
      ],
      enabled: true,
    });

    // Create email identities for domain and email verification
    const domainIdentity = new ses.EmailIdentity(this, 'DomainIdentity', {
      identity: ses.Identity.domain(senderDomain),
      dkimSigning: true,
    });

    const emailIdentity = new ses.EmailIdentity(this, 'EmailIdentity', {
      identity: ses.Identity.email(senderEmail),
    });

    // Create email templates for marketing campaigns
    const welcomeTemplate = new ses.CfnTemplate(this, 'WelcomeTemplate', {
      templateName: 'welcome-campaign',
      template: {
        templateName: 'welcome-campaign',
        subjectPart: 'Welcome to Our Community, {{name}}!',
        htmlPart: `
          <html>
            <body>
              <h2>Welcome {{name}}!</h2>
              <p>Thank you for joining our community. We are excited to have you aboard!</p>
              <p>As a welcome gift, use code <strong>WELCOME10</strong> for 10% off your first purchase.</p>
              <p>Best regards,<br/>The Marketing Team</p>
              <p><a href="{{unsubscribe_url}}">Unsubscribe</a></p>
            </body>
          </html>
        `,
        textPart: `
          Welcome {{name}}! 
          Thank you for joining our community. 
          Use code WELCOME10 for 10% off your first purchase. 
          Unsubscribe: {{unsubscribe_url}}
        `,
      },
    });

    const promotionTemplate = new ses.CfnTemplate(this, 'PromotionTemplate', {
      templateName: 'product-promotion',
      template: {
        templateName: 'product-promotion',
        subjectPart: 'Exclusive Offer: {{discount}}% Off {{product_name}}',
        htmlPart: `
          <html>
            <body>
              <h2>Special Offer for {{name}}!</h2>
              <p>Get {{discount}}% off our popular {{product_name}}!</p>
              <p>Limited time offer - expires {{expiry_date}}</p>
              <p><a href="{{product_url}}" style="background-color: #007bff; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">Shop Now</a></p>
              <p>Best regards,<br/>The Marketing Team</p>
              <p><a href="{{unsubscribe_url}}">Unsubscribe</a></p>
            </body>
          </html>
        `,
        textPart: `
          Special Offer for {{name}}! 
          Get {{discount}}% off {{product_name}}. 
          Expires {{expiry_date}}. 
          Shop: {{product_url}} 
          Unsubscribe: {{unsubscribe_url}}
        `,
      },
    });

    // Create Lambda function for automated bounce handling
    if (enableBounceHandling) {
      this.bounceHandlerFunction = new lambda.Function(this, 'BounceHandler', {
        functionName: `bounce-handler-${uniqueSuffix}`,
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'index.lambda_handler',
        code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    ses_client = boto3.client('sesv2')
    s3_client = boto3.client('s3')
    
    try:
        # Parse SNS message
        for record in event['Records']:
            message = json.loads(record['Sns']['Message'])
            
            if message.get('eventType') == 'bounce':
                # Add bounced email to suppression list
                mail_destination = message.get('mail', {}).get('destination', [])
                if mail_destination:
                    bounced_email = mail_destination[0]
                    
                    # Add to SES account-level suppression list
                    try:
                        ses_client.put_suppressed_destination(
                            EmailAddress=bounced_email,
                            Reason='BOUNCE'
                        )
                        logger.info(f"Added {bounced_email} to suppression list")
                    except Exception as e:
                        logger.error(f"Failed to add {bounced_email} to suppression list: {e}")
            
            elif message.get('eventType') == 'complaint':
                # Handle complaint events
                mail_destination = message.get('mail', {}).get('destination', [])
                if mail_destination:
                    complaint_email = mail_destination[0]
                    
                    # Add to SES account-level suppression list
                    try:
                        ses_client.put_suppressed_destination(
                            EmailAddress=complaint_email,
                            Reason='COMPLAINT'
                        )
                        logger.info(f"Added {complaint_email} to suppression list for complaint")
                    except Exception as e:
                        logger.error(f"Failed to add {complaint_email} to suppression list: {e}")
        
        return {'statusCode': 200, 'body': 'Successfully processed email events'}
        
    except Exception as e:
        logger.error(f"Error processing email events: {e}")
        return {'statusCode': 500, 'body': f'Error processing email events: {e}'}
        `),
        timeout: cdk.Duration.seconds(30),
        logRetention: logs.RetentionDays.ONE_WEEK,
        environment: {
          BUCKET_NAME: this.emailBucket.bucketName,
        },
      });

      // Grant necessary permissions to Lambda function
      this.bounceHandlerFunction.addToRolePolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'sesv2:PutSuppressedDestination',
            'sesv2:GetSuppressedDestination',
          ],
          resources: ['*'],
        })
      );

      this.bounceHandlerFunction.addToRolePolicy(
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
          ],
          resources: [
            this.emailBucket.arnForObjects('*'),
          ],
        })
      );

      // Subscribe Lambda function to SNS topic
      this.emailEventsTopic.addSubscription(
        new snsSubscriptions.LambdaSubscription(this.bounceHandlerFunction)
      );
    }

    // Create CloudWatch dashboard for email metrics
    this.dashboard = new cloudwatch.Dashboard(this, 'EmailMarketingDashboard', {
      dashboardName: `EmailMarketingDashboard-${uniqueSuffix}`,
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Email Campaign Metrics',
        width: 12,
        height: 6,
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/SES',
            metricName: 'Send',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/SES',
            metricName: 'Delivery',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/SES',
            metricName: 'Bounce',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/SES',
            metricName: 'Complaint',
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Email Delivery Rate',
        width: 6,
        height: 3,
        metrics: [
          new cloudwatch.MathExpression({
            expression: '(delivery / send) * 100',
            usingMetrics: {
              send: new cloudwatch.Metric({
                namespace: 'AWS/SES',
                metricName: 'Send',
                statistic: 'Sum',
                period: cdk.Duration.hours(1),
              }),
              delivery: new cloudwatch.Metric({
                namespace: 'AWS/SES',
                metricName: 'Delivery',
                statistic: 'Sum',
                period: cdk.Duration.hours(1),
              }),
            },
          }),
        ],
      }),
      new cloudwatch.SingleValueWidget({
        title: 'Bounce Rate',
        width: 6,
        height: 3,
        metrics: [
          new cloudwatch.MathExpression({
            expression: '(bounce / send) * 100',
            usingMetrics: {
              send: new cloudwatch.Metric({
                namespace: 'AWS/SES',
                metricName: 'Send',
                statistic: 'Sum',
                period: cdk.Duration.hours(1),
              }),
              bounce: new cloudwatch.Metric({
                namespace: 'AWS/SES',
                metricName: 'Bounce',
                statistic: 'Sum',
                period: cdk.Duration.hours(1),
              }),
            },
          }),
        ],
      }),
    );

    // Create CloudWatch alarms for bounce rate monitoring
    const highBounceRateAlarm = new cloudwatch.Alarm(this, 'HighBounceRateAlarm', {
      alarmName: `HighBounceRate-${uniqueSuffix}`,
      alarmDescription: 'Alert when bounce rate exceeds 5%',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/SES',
        metricName: 'Bounce',
        statistic: 'Sum',
        period: cdk.Duration.hours(1),
      }),
      threshold: 5,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm action to send notification
    highBounceRateAlarm.addAlarmAction(
      new cloudwatch.actions.SnsAction(this.emailEventsTopic)
    );

    // Create EventBridge rule for automated campaign scheduling
    if (enableCampaignAutomation) {
      const campaignRule = new events.Rule(this, 'WeeklyEmailCampaignRule', {
        ruleName: `WeeklyEmailCampaign-${uniqueSuffix}`,
        description: 'Trigger weekly email campaigns',
        schedule: events.Schedule.rate(cdk.Duration.days(7)),
        enabled: true,
      });

      // Create IAM role for campaign automation
      const campaignRole = new iam.Role(this, 'CampaignAutomationRole', {
        roleName: `CampaignAutomationRole-${uniqueSuffix}`,
        assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
        inlinePolicies: {
          CampaignPolicy: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  'ses:SendBulkEmail',
                  'ses:SendEmail',
                ],
                resources: ['*'],
              }),
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  's3:GetObject',
                  's3:PutObject',
                ],
                resources: [
                  this.emailBucket.arnForObjects('*'),
                ],
              }),
            ],
          }),
        },
      });

      // Note: In a production environment, you would add a Lambda function as a target
      // for the EventBridge rule to handle automated campaign sending
    }

    // Create sample subscriber list in S3
    const subscriberList = new s3.deployment.BucketDeployment(this, 'SampleSubscriberList', {
      sources: [
        s3.deployment.Source.data('subscribers/subscribers.json', JSON.stringify([
          {
            email: 'subscriber1@example.com',
            name: 'John Doe',
            segment: 'new_customers',
            preferences: ['electronics', 'books'],
          },
          {
            email: 'subscriber2@example.com',
            name: 'Jane Smith',
            segment: 'loyal_customers',
            preferences: ['fashion', 'home'],
          },
          {
            email: 'subscriber3@example.com',
            name: 'Bob Johnson',
            segment: 'new_customers',
            preferences: ['sports', 'electronics'],
          },
        ], null, 2)),
        s3.deployment.Source.data('suppression/bounced-emails.txt', ''),
      ],
      destinationBucket: this.emailBucket,
    });

    // Output important information
    new cdk.CfnOutput(this, 'EmailBucketName', {
      value: this.emailBucket.bucketName,
      description: 'S3 bucket name for email templates and subscriber lists',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: this.emailEventsTopic.topicArn,
      description: 'SNS topic ARN for email event notifications',
    });

    new cdk.CfnOutput(this, 'ConfigurationSetName', {
      value: this.configurationSet.configurationSetName,
      description: 'SES configuration set name for email tracking',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'CloudWatch dashboard URL for email campaign metrics',
    });

    new cdk.CfnOutput(this, 'SenderDomain', {
      value: senderDomain,
      description: 'Domain configured for email sending (requires DNS verification)',
    });

    new cdk.CfnOutput(this, 'SenderEmail', {
      value: senderEmail,
      description: 'Email address configured for sending (requires verification)',
    });

    if (enableBounceHandling && this.bounceHandlerFunction) {
      new cdk.CfnOutput(this, 'BounceHandlerFunctionName', {
        value: this.bounceHandlerFunction.functionName,
        description: 'Lambda function name for automated bounce handling',
      });
    }

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'EmailMarketingCampaigns');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}

/**
 * CDK Application for Email Marketing Campaigns
 */
class EmailMarketingApp extends cdk.App {
  constructor() {
    super();

    // Create the email marketing stack
    new EmailMarketingStack(this, 'EmailMarketingStack', {
      description: 'Email Marketing Campaigns with Amazon SES - CDK TypeScript Implementation',
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION,
      },
      // Configure these values for your deployment
      senderDomain: process.env.SENDER_DOMAIN || 'yourdomain.com',
      senderEmail: process.env.SENDER_EMAIL || 'marketing@yourdomain.com',
      notificationEmail: process.env.NOTIFICATION_EMAIL || 'notifications@yourdomain.com',
      enableBounceHandling: process.env.ENABLE_BOUNCE_HANDLING !== 'false',
      enableCampaignAutomation: process.env.ENABLE_CAMPAIGN_AUTOMATION !== 'false',
    });
  }
}

// Initialize the CDK app
const app = new EmailMarketingApp();