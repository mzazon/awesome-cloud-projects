#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  aws_sns as sns,
  aws_sqs as sqs,
  aws_lambda as lambda,
  aws_iam as iam,
  aws_lambda_event_sources as lambda_event_sources,
  aws_sns_subscriptions as sns_subscriptions,
  Duration,
  RemovalPolicy,
  CfnOutput,
  Stack,
  StackProps,
} from 'aws-cdk-lib';
import * as path from 'path';

/**
 * Properties for the ServerlessNotificationSystemStack
 */
export interface ServerlessNotificationSystemStackProps extends StackProps {
  /**
   * Environment name (e.g., 'dev', 'staging', 'prod')
   * @default 'dev'
   */
  readonly environmentName?: string;
  
  /**
   * Email address for testing notifications
   */
  readonly testEmail?: string;
  
  /**
   * Enable dead letter queue for failed messages
   * @default true
   */
  readonly enableDeadLetterQueue?: boolean;
  
  /**
   * Maximum number of retries before sending to DLQ
   * @default 3
   */
  readonly maxRetries?: number;
  
  /**
   * Lambda function timeout in seconds
   * @default 300
   */
  readonly lambdaTimeout?: number;
  
  /**
   * SQS batch size for Lambda event source mapping
   * @default 10
   */
  readonly sqsBatchSize?: number;
  
  /**
   * Maximum batching window in seconds
   * @default 5
   */
  readonly maxBatchingWindow?: number;
}

/**
 * Stack for serverless notification system using SNS, SQS, and Lambda
 * 
 * This stack creates:
 * - SNS topic for message distribution
 * - SQS queues for different notification types (email, SMS, webhook)
 * - Dead letter queue for failed messages
 * - Lambda functions for processing notifications
 * - IAM roles and policies for secure access
 * - Event source mappings for automatic message processing
 */
export class ServerlessNotificationSystemStack extends Stack {
  public readonly snsTopic: sns.Topic;
  public readonly emailQueue: sqs.Queue;
  public readonly smsQueue: sqs.Queue;
  public readonly webhookQueue: sqs.Queue;
  public readonly deadLetterQueue: sqs.Queue;
  public readonly emailLambda: lambda.Function;
  public readonly smsLambda: lambda.Function;
  public readonly webhookLambda: lambda.Function;
  public readonly dlqLambda: lambda.Function;

  constructor(scope: Construct, id: string, props: ServerlessNotificationSystemStackProps = {}) {
    super(scope, id, props);

    // Extract properties with defaults
    const environmentName = props.environmentName || 'dev';
    const testEmail = props.testEmail || 'test@example.com';
    const enableDeadLetterQueue = props.enableDeadLetterQueue ?? true;
    const maxRetries = props.maxRetries || 3;
    const lambdaTimeout = props.lambdaTimeout || 300;
    const sqsBatchSize = props.sqsBatchSize || 10;
    const maxBatchingWindow = props.maxBatchingWindow || 5;

    // Create dead letter queue first (if enabled)
    if (enableDeadLetterQueue) {
      this.deadLetterQueue = new sqs.Queue(this, 'NotificationDeadLetterQueue', {
        queueName: `notification-dlq-${environmentName}`,
        retentionPeriod: Duration.days(14),
        visibilityTimeout: Duration.seconds(lambdaTimeout),
        removalPolicy: RemovalPolicy.DESTROY,
      });
    }

    // Create SQS queues for different notification types
    const queueProps: Partial<sqs.QueueProps> = {
      visibilityTimeout: Duration.seconds(lambdaTimeout),
      retentionPeriod: Duration.days(14),
      removalPolicy: RemovalPolicy.DESTROY,
      ...(enableDeadLetterQueue && {
        deadLetterQueue: {
          queue: this.deadLetterQueue,
          maxReceiveCount: maxRetries,
        },
      }),
    };

    this.emailQueue = new sqs.Queue(this, 'EmailNotificationQueue', {
      queueName: `email-notifications-${environmentName}`,
      ...queueProps,
    });

    this.smsQueue = new sqs.Queue(this, 'SmsNotificationQueue', {
      queueName: `sms-notifications-${environmentName}`,
      ...queueProps,
    });

    this.webhookQueue = new sqs.Queue(this, 'WebhookNotificationQueue', {
      queueName: `webhook-notifications-${environmentName}`,
      ...queueProps,
    });

    // Create SNS topic
    this.snsTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `notification-system-${environmentName}`,
      displayName: 'Serverless Notification System',
      fifo: false,
    });

    // Create IAM role for Lambda functions
    const lambdaRole = new iam.Role(this, 'NotificationLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add SQS permissions to Lambda role
    const queueArns = [
      this.emailQueue.queueArn,
      this.smsQueue.queueArn,
      this.webhookQueue.queueArn,
    ];

    if (enableDeadLetterQueue) {
      queueArns.push(this.deadLetterQueue.queueArn);
    }

    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'sqs:ReceiveMessage',
          'sqs:DeleteMessage',
          'sqs:GetQueueAttributes',
          'sqs:SendMessage',
        ],
        resources: queueArns,
      })
    );

    // Add CloudWatch Logs permissions
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'logs:CreateLogGroup',
          'logs:CreateLogStream',
          'logs:PutLogEvents',
        ],
        resources: ['*'],
      })
    );

    // Lambda function code for email processing
    const emailHandlerCode = `
import json
import logging
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process email notification messages from SQS
    
    Args:
        event: Lambda event containing SQS records
        context: Lambda context object
        
    Returns:
        Processing result with status and message details
    """
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract notification details
            subject = message_body.get('subject', 'Notification')
            message = message_body.get('message', '')
            recipient = message_body.get('recipient', '${testEmail}')
            priority = message_body.get('priority', 'normal')
            timestamp = message_body.get('timestamp', '')
            
            # Log email processing (replace with actual email service integration)
            logger.info(f"Processing email notification:")
            logger.info(f"  Recipient: {recipient}")
            logger.info(f"  Subject: {subject}")
            logger.info(f"  Message: {message}")
            logger.info(f"  Priority: {priority}")
            logger.info(f"  Timestamp: {timestamp}")
            
            # TODO: Integrate with Amazon SES, SendGrid, or other email service
            # Example SES integration:
            # import boto3
            # ses_client = boto3.client('ses')
            # ses_client.send_email(
            #     Source='noreply@yourdomain.com',
            #     Destination={'ToAddresses': [recipient]},
            #     Message={
            #         'Subject': {'Data': subject},
            #         'Body': {'Text': {'Data': message}}
            #     }
            # )
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'success',
                'recipient': recipient,
                'subject': subject,
                'priority': priority
            })
            
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            # Message will be retried or sent to DLQ based on SQS configuration
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
`;

    // Lambda function code for SMS processing
    const smsHandlerCode = `
import json
import logging
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process SMS notification messages from SQS
    
    Args:
        event: Lambda event containing SQS records
        context: Lambda context object
        
    Returns:
        Processing result with status and message details
    """
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract notification details
            phone_number = message_body.get('phone_number', '+1234567890')
            message = message_body.get('message', '')
            priority = message_body.get('priority', 'normal')
            timestamp = message_body.get('timestamp', '')
            
            # Log SMS processing (replace with actual SMS service integration)
            logger.info(f"Processing SMS notification:")
            logger.info(f"  Phone: {phone_number}")
            logger.info(f"  Message: {message}")
            logger.info(f"  Priority: {priority}")
            logger.info(f"  Timestamp: {timestamp}")
            
            # TODO: Integrate with Amazon SNS SMS, Twilio, or other SMS service
            # Example SNS SMS integration:
            # import boto3
            # sns_client = boto3.client('sns')
            # sns_client.publish(
            #     PhoneNumber=phone_number,
            #     Message=message
            # )
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'success',
                'phone_number': phone_number,
                'priority': priority
            })
            
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            # Message will be retried or sent to DLQ based on SQS configuration
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
`;

    // Lambda function code for webhook processing
    const webhookHandlerCode = `
import json
import logging
import urllib3
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

http = urllib3.PoolManager()

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process webhook notification messages from SQS
    
    Args:
        event: Lambda event containing SQS records
        context: Lambda context object
        
    Returns:
        Processing result with status and message details
    """
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract webhook details
            webhook_url = message_body.get('webhook_url', '')
            payload = message_body.get('payload', {})
            headers = message_body.get('headers', {'Content-Type': 'application/json'})
            retry_count = message_body.get('retry_count', 0)
            timestamp = message_body.get('timestamp', '')
            
            if not webhook_url:
                logger.error("No webhook URL provided")
                continue
            
            # Send webhook request
            logger.info(f"Sending webhook to {webhook_url}")
            logger.info(f"Payload: {json.dumps(payload, indent=2)}")
            logger.info(f"Timestamp: {timestamp}")
            
            try:
                response = http.request(
                    'POST',
                    webhook_url,
                    body=json.dumps(payload),
                    headers=headers,
                    timeout=30
                )
                
                if response.status == 200:
                    logger.info(f"Webhook sent successfully to {webhook_url}")
                    status = 'success'
                else:
                    logger.warning(f"Webhook returned status {response.status}")
                    status = 'retry'
                    
            except Exception as webhook_error:
                logger.error(f"Webhook request failed: {str(webhook_error)}")
                status = 'failed'
                if retry_count < 3:
                    raise webhook_error  # Will trigger SQS retry
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': status,
                'webhook_url': webhook_url,
                'retry_count': retry_count
            })
            
        except Exception as e:
            logger.error(f"Error processing message {record['messageId']}: {str(e)}")
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
`;

    // Lambda function code for DLQ processing
    const dlqHandlerCode = `
import json
import logging
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process failed messages from Dead Letter Queue
    
    Args:
        event: Lambda event containing SQS records from DLQ
        context: Lambda context object
        
    Returns:
        Processing result with details of failed messages
    """
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Log failed message details for investigation
            logger.error(f"Processing failed message from DLQ:")
            logger.error(f"  Message ID: {record['messageId']}")
            logger.error(f"  Receipt Handle: {record['receiptHandle']}")
            logger.error(f"  Message Body: {json.dumps(message_body, indent=2)}")
            logger.error(f"  Attributes: {record.get('attributes', {})}")
            
            # TODO: Implement custom logic for failed messages:
            # - Send alert to monitoring system
            # - Store in database for manual review
            # - Retry with different parameters
            # - Forward to support team
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'logged',
                'action': 'manual_review_required'
            })
            
        except Exception as e:
            logger.error(f"Error processing DLQ message {record['messageId']}: {str(e)}")
            # Even DLQ processing errors should be logged but not re-raised
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'error',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
`;

    // Create Lambda functions
    const lambdaProps = {
      runtime: lambda.Runtime.PYTHON_3_9,
      role: lambdaRole,
      timeout: Duration.seconds(lambdaTimeout),
      memorySize: 256,
      environment: {
        ENVIRONMENT_NAME: environmentName,
        TEST_EMAIL: testEmail,
      },
    };

    this.emailLambda = new lambda.Function(this, 'EmailNotificationHandler', {
      functionName: `email-notification-handler-${environmentName}`,
      code: lambda.Code.fromInline(emailHandlerCode),
      handler: 'index.lambda_handler',
      description: 'Process email notifications from SQS queue',
      ...lambdaProps,
    });

    this.smsLambda = new lambda.Function(this, 'SmsNotificationHandler', {
      functionName: `sms-notification-handler-${environmentName}`,
      code: lambda.Code.fromInline(smsHandlerCode),
      handler: 'index.lambda_handler',
      description: 'Process SMS notifications from SQS queue',
      ...lambdaProps,
    });

    this.webhookLambda = new lambda.Function(this, 'WebhookNotificationHandler', {
      functionName: `webhook-notification-handler-${environmentName}`,
      code: lambda.Code.fromInline(webhookHandlerCode),
      handler: 'index.lambda_handler',
      description: 'Process webhook notifications from SQS queue',
      ...lambdaProps,
    });

    if (enableDeadLetterQueue) {
      this.dlqLambda = new lambda.Function(this, 'DlqNotificationHandler', {
        functionName: `dlq-notification-handler-${environmentName}`,
        code: lambda.Code.fromInline(dlqHandlerCode),
        handler: 'index.lambda_handler',
        description: 'Process failed messages from Dead Letter Queue',
        ...lambdaProps,
      });
    }

    // Create event source mappings
    const eventSourceProps = {
      batchSize: sqsBatchSize,
      maxBatchingWindow: Duration.seconds(maxBatchingWindow),
      reportBatchItemFailures: true,
    };

    new lambda_event_sources.SqsEventSource(this.emailQueue, eventSourceProps);
    this.emailLambda.addEventSource(new lambda_event_sources.SqsEventSource(this.emailQueue, eventSourceProps));

    this.smsLambda.addEventSource(new lambda_event_sources.SqsEventSource(this.smsQueue, eventSourceProps));

    this.webhookLambda.addEventSource(new lambda_event_sources.SqsEventSource(this.webhookQueue, eventSourceProps));

    if (enableDeadLetterQueue && this.dlqLambda) {
      this.dlqLambda.addEventSource(new lambda_event_sources.SqsEventSource(this.deadLetterQueue, eventSourceProps));
    }

    // Subscribe SQS queues to SNS topic with message filtering
    this.snsTopic.addSubscription(
      new sns_subscriptions.SqsSubscription(this.emailQueue, {
        rawMessageDelivery: true,
        filterPolicy: {
          notification_type: sns.SubscriptionFilter.stringFilter({
            allowlist: ['email', 'all'],
          }),
        },
      })
    );

    this.snsTopic.addSubscription(
      new sns_subscriptions.SqsSubscription(this.smsQueue, {
        rawMessageDelivery: true,
        filterPolicy: {
          notification_type: sns.SubscriptionFilter.stringFilter({
            allowlist: ['sms', 'all'],
          }),
        },
      })
    );

    this.snsTopic.addSubscription(
      new sns_subscriptions.SqsSubscription(this.webhookQueue, {
        rawMessageDelivery: true,
        filterPolicy: {
          notification_type: sns.SubscriptionFilter.stringFilter({
            allowlist: ['webhook', 'all'],
          }),
        },
      })
    );

    // CloudFormation Outputs
    new CfnOutput(this, 'SnsTopicArn', {
      value: this.snsTopic.topicArn,
      description: 'SNS Topic ARN for publishing notifications',
      exportName: `${environmentName}-NotificationTopicArn`,
    });

    new CfnOutput(this, 'EmailQueueUrl', {
      value: this.emailQueue.queueUrl,
      description: 'Email notification queue URL',
      exportName: `${environmentName}-EmailQueueUrl`,
    });

    new CfnOutput(this, 'SmsQueueUrl', {
      value: this.smsQueue.queueUrl,
      description: 'SMS notification queue URL',
      exportName: `${environmentName}-SmsQueueUrl`,
    });

    new CfnOutput(this, 'WebhookQueueUrl', {
      value: this.webhookQueue.queueUrl,
      description: 'Webhook notification queue URL',
      exportName: `${environmentName}-WebhookQueueUrl`,
    });

    if (enableDeadLetterQueue) {
      new CfnOutput(this, 'DeadLetterQueueUrl', {
        value: this.deadLetterQueue.queueUrl,
        description: 'Dead letter queue URL for failed messages',
        exportName: `${environmentName}-DeadLetterQueueUrl`,
      });
    }

    new CfnOutput(this, 'EmailLambdaArn', {
      value: this.emailLambda.functionArn,
      description: 'Email notification handler Lambda function ARN',
      exportName: `${environmentName}-EmailLambdaArn`,
    });

    new CfnOutput(this, 'SmsLambdaArn', {
      value: this.smsLambda.functionArn,
      description: 'SMS notification handler Lambda function ARN',
      exportName: `${environmentName}-SmsLambdaArn`,
    });

    new CfnOutput(this, 'WebhookLambdaArn', {
      value: this.webhookLambda.functionArn,
      description: 'Webhook notification handler Lambda function ARN',
      exportName: `${environmentName}-WebhookLambdaArn`,
    });

    if (enableDeadLetterQueue && this.dlqLambda) {
      new CfnOutput(this, 'DlqLambdaArn', {
        value: this.dlqLambda.functionArn,
        description: 'Dead letter queue handler Lambda function ARN',
        exportName: `${environmentName}-DlqLambdaArn`,
      });
    }
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environmentName = app.node.tryGetContext('environment') || process.env.ENVIRONMENT_NAME || 'dev';
const testEmail = app.node.tryGetContext('testEmail') || process.env.TEST_EMAIL || 'test@example.com';
const enableDeadLetterQueue = app.node.tryGetContext('enableDeadLetterQueue') ?? true;
const maxRetries = app.node.tryGetContext('maxRetries') || 3;
const lambdaTimeout = app.node.tryGetContext('lambdaTimeout') || 300;
const sqsBatchSize = app.node.tryGetContext('sqsBatchSize') || 10;
const maxBatchingWindow = app.node.tryGetContext('maxBatchingWindow') || 5;

// Create the stack
new ServerlessNotificationSystemStack(app, `ServerlessNotificationSystem-${environmentName}`, {
  environmentName,
  testEmail,
  enableDeadLetterQueue,
  maxRetries,
  lambdaTimeout,
  sqsBatchSize,
  maxBatchingWindow,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: `Serverless notification system with SNS, SQS, and Lambda for ${environmentName} environment`,
  tags: {
    Project: 'ServerlessNotificationSystem',
    Environment: environmentName,
    CreatedBy: 'CDK',
  },
});