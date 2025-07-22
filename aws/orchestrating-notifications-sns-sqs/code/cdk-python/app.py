#!/usr/bin/env python3
"""
AWS CDK Python Application for Serverless Notification Systems

This application creates a comprehensive serverless notification system using:
- Amazon SNS for message publishing and fan-out
- Amazon SQS for reliable message queuing and buffering
- AWS Lambda for custom message processing and delivery

The architecture supports multiple notification channels including email, SMS, 
webhooks, and custom processing logic with built-in error handling via dead 
letter queues.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
    aws_sns as sns,
    aws_sqs as sqs,
)
from constructs import Construct


class ServerlessNotificationSystemStack(Stack):
    """
    Main stack for the serverless notification system.
    
    This stack creates the complete infrastructure for a scalable notification
    system that can handle various types of events and deliver them to multiple
    endpoints without managing servers.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "dev",
        test_email: Optional[str] = None,
        **kwargs: StackProps,
    ) -> None:
        """
        Initialize the ServerlessNotificationSystemStack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            environment_name: Environment name for resource naming
            test_email: Email address for testing notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        self.test_email = test_email or "test@example.com"

        # Create the notification system components
        self._create_dead_letter_queue()
        self._create_processing_queues()
        self._create_sns_topic()
        self._create_queue_subscriptions()
        self._create_lambda_role()
        self._create_lambda_functions()
        self._create_event_source_mappings()
        self._create_outputs()

    def _create_dead_letter_queue(self) -> None:
        """Create the dead letter queue for handling failed messages."""
        self.dead_letter_queue = sqs.Queue(
            self,
            "NotificationDLQ",
            queue_name=f"notification-dlq-{self.environment_name}",
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
        )

        # Add tags for cost tracking and management
        cdk.Tags.of(self.dead_letter_queue).add("Environment", self.environment_name)
        cdk.Tags.of(self.dead_letter_queue).add("Component", "DeadLetterQueue")

    def _create_processing_queues(self) -> None:
        """Create SQS queues for different notification types."""
        
        # Dead letter queue configuration
        dead_letter_queue_config = sqs.DeadLetterQueue(
            max_receive_count=3,
            queue=self.dead_letter_queue
        )

        # Email processing queue
        self.email_queue = sqs.Queue(
            self,
            "EmailNotificationQueue",
            queue_name=f"email-notifications-{self.environment_name}",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            dead_letter_queue=dead_letter_queue_config,
        )

        # SMS processing queue
        self.sms_queue = sqs.Queue(
            self,
            "SmsNotificationQueue",
            queue_name=f"sms-notifications-{self.environment_name}",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            dead_letter_queue=dead_letter_queue_config,
        )

        # Webhook processing queue
        self.webhook_queue = sqs.Queue(
            self,
            "WebhookNotificationQueue",
            queue_name=f"webhook-notifications-{self.environment_name}",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            dead_letter_queue=dead_letter_queue_config,
        )

        # Add tags to all queues
        for queue in [self.email_queue, self.sms_queue, self.webhook_queue]:
            cdk.Tags.of(queue).add("Environment", self.environment_name)
            cdk.Tags.of(queue).add("Component", "ProcessingQueue")

    def _create_sns_topic(self) -> None:
        """Create SNS topic for message distribution."""
        self.notification_topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"notification-system-{self.environment_name}",
            display_name="Serverless Notification System",
        )

        # Add tags
        cdk.Tags.of(self.notification_topic).add("Environment", self.environment_name)
        cdk.Tags.of(self.notification_topic).add("Component", "MessageDistribution")

    def _create_queue_subscriptions(self) -> None:
        """Subscribe SQS queues to SNS topic with message filtering."""
        
        # Email queue subscription with filtering
        self.notification_topic.add_subscription(
            sns_subscriptions.SqsSubscription(
                self.email_queue,
                raw_message_delivery=True,
                filter_policy={
                    "notification_type": sns.SubscriptionFilter.string_filter(
                        allowlist=["email", "all"]
                    )
                },
            )
        )

        # SMS queue subscription with filtering
        self.notification_topic.add_subscription(
            sns_subscriptions.SqsSubscription(
                self.sms_queue,
                raw_message_delivery=True,
                filter_policy={
                    "notification_type": sns.SubscriptionFilter.string_filter(
                        allowlist=["sms", "all"]
                    )
                },
            )
        )

        # Webhook queue subscription with filtering
        self.notification_topic.add_subscription(
            sns_subscriptions.SqsSubscription(
                self.webhook_queue,
                raw_message_delivery=True,
                filter_policy={
                    "notification_type": sns.SubscriptionFilter.string_filter(
                        allowlist=["webhook", "all"]
                    )
                },
            )
        )

    def _create_lambda_role(self) -> None:
        """Create IAM role for Lambda functions."""
        self.lambda_role = iam.Role(
            self,
            "NotificationLambdaRole",
            role_name=f"NotificationLambdaRole-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add SQS permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sqs:ReceiveMessage",
                    "sqs:DeleteMessage",
                    "sqs:GetQueueAttributes",
                    "sqs:SendMessage",
                ],
                resources=[
                    self.email_queue.queue_arn,
                    self.sms_queue.queue_arn,
                    self.webhook_queue.queue_arn,
                    self.dead_letter_queue.queue_arn,
                ],
            )
        )

        # Add CloudWatch Logs permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for processing notifications."""
        
        # Common Lambda function configuration
        lambda_config = {
            "runtime": lambda_.Runtime.PYTHON_3_9,
            "timeout": Duration.minutes(5),
            "role": self.lambda_role,
            "environment": {
                "ENVIRONMENT": self.environment_name,
                "TEST_EMAIL": self.test_email,
            },
            "log_retention": logs.RetentionDays.ONE_WEEK,
        }

        # Email notification handler
        self.email_handler = lambda_.Function(
            self,
            "EmailNotificationHandler",
            function_name=f"EmailNotificationHandler-{self.environment_name}",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_email_handler_code()),
            description="Processes email notification messages from SQS",
            **lambda_config,
        )

        # SMS notification handler
        self.sms_handler = lambda_.Function(
            self,
            "SmsNotificationHandler",
            function_name=f"SmsNotificationHandler-{self.environment_name}",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_sms_handler_code()),
            description="Processes SMS notification messages from SQS",
            **lambda_config,
        )

        # Webhook notification handler
        self.webhook_handler = lambda_.Function(
            self,
            "WebhookNotificationHandler",
            function_name=f"WebhookNotificationHandler-{self.environment_name}",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_webhook_handler_code()),
            description="Processes webhook notification messages from SQS",
            **lambda_config,
        )

        # Dead letter queue processor
        self.dlq_processor = lambda_.Function(
            self,
            "DLQProcessor",
            function_name=f"DLQProcessor-{self.environment_name}",
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_dlq_processor_code()),
            description="Processes failed messages from dead letter queue",
            **lambda_config,
        )

        # Add tags to all functions
        for function in [self.email_handler, self.sms_handler, self.webhook_handler, self.dlq_processor]:
            cdk.Tags.of(function).add("Environment", self.environment_name)
            cdk.Tags.of(function).add("Component", "MessageProcessor")

    def _create_event_source_mappings(self) -> None:
        """Create event source mappings between SQS queues and Lambda functions."""
        
        # Email queue to email handler
        self.email_handler.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.email_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
            )
        )

        # SMS queue to SMS handler
        self.sms_handler.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.sms_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
            )
        )

        # Webhook queue to webhook handler
        self.webhook_handler.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.webhook_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
            )
        )

        # Dead letter queue to DLQ processor
        self.dlq_processor.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.dead_letter_queue,
                batch_size=5,
                max_batching_window=Duration.seconds(10),
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        # SNS Topic ARN
        cdk.CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for publishing notifications",
            export_name=f"NotificationTopicArn-{self.environment_name}",
        )

        # Queue URLs
        cdk.CfnOutput(
            self,
            "EmailQueueUrl",
            value=self.email_queue.queue_url,
            description="URL of the email notification queue",
            export_name=f"EmailQueueUrl-{self.environment_name}",
        )

        cdk.CfnOutput(
            self,
            "SmsQueueUrl",
            value=self.sms_queue.queue_url,
            description="URL of the SMS notification queue",
            export_name=f"SmsQueueUrl-{self.environment_name}",
        )

        cdk.CfnOutput(
            self,
            "WebhookQueueUrl",
            value=self.webhook_queue.queue_url,
            description="URL of the webhook notification queue",
            export_name=f"WebhookQueueUrl-{self.environment_name}",
        )

        # Lambda function ARNs
        cdk.CfnOutput(
            self,
            "EmailHandlerArn",
            value=self.email_handler.function_arn,
            description="ARN of the email notification handler Lambda function",
            export_name=f"EmailHandlerArn-{self.environment_name}",
        )

        cdk.CfnOutput(
            self,
            "WebhookHandlerArn",
            value=self.webhook_handler.function_arn,
            description="ARN of the webhook notification handler Lambda function",
            export_name=f"WebhookHandlerArn-{self.environment_name}",
        )

    def _get_email_handler_code(self) -> str:
        """Return the email handler Lambda function code."""
        return '''
import json
import logging
import os
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process email notification messages from SQS."""
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract notification details
            subject = message_body.get('subject', 'Notification')
            message = message_body.get('message', '')
            recipient = message_body.get('recipient', os.environ.get('TEST_EMAIL', 'test@example.com'))
            priority = message_body.get('priority', 'normal')
            
            # Log email details (in production, integrate with SES, SendGrid, etc.)
            logger.info(f"Processing email notification:")
            logger.info(f"  To: {recipient}")
            logger.info(f"  Subject: {subject}")
            logger.info(f"  Message: {message}")
            logger.info(f"  Priority: {priority}")
            
            # Simulate email sending success
            # In production, replace with actual email service integration
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
        '''

    def _get_sms_handler_code(self) -> str:
        """Return the SMS handler Lambda function code."""
        return '''
import json
import logging
import os
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process SMS notification messages from SQS."""
    
    processed_messages = []
    
    for record in event['Records']:
        try:
            # Parse message body
            message_body = json.loads(record['body'])
            
            # Extract notification details
            message = message_body.get('message', '')
            phone_number = message_body.get('phone_number', '+1234567890')
            priority = message_body.get('priority', 'normal')
            
            # Log SMS details (in production, integrate with SNS SMS, Twilio, etc.)
            logger.info(f"Processing SMS notification:")
            logger.info(f"  To: {phone_number}")
            logger.info(f"  Message: {message}")
            logger.info(f"  Priority: {priority}")
            
            # Simulate SMS sending success
            # In production, replace with actual SMS service integration
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'success',
                'phone_number': phone_number,
                'message': message,
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
        '''

    def _get_webhook_handler_code(self) -> str:
        """Return the webhook handler Lambda function code."""
        return '''
import json
import logging
import urllib3
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

http = urllib3.PoolManager()

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process webhook notification messages from SQS."""
    
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
            
            if not webhook_url:
                logger.error("No webhook URL provided")
                continue
            
            # Send webhook request
            logger.info(f"Sending webhook to {webhook_url}")
            
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
        '''

    def _get_dlq_processor_code(self) -> str:
        """Return the DLQ processor Lambda function code."""
        return '''
import json
import logging
from typing import Dict, List, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Process failed messages from dead letter queue."""
    
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
            
            # In production, you might want to:
            # 1. Send alerts to operations team
            # 2. Store in a persistent store for analysis
            # 3. Attempt manual retry with different parameters
            # 4. Route to different processing logic
            
            processed_messages.append({
                'messageId': record['messageId'],
                'status': 'logged',
                'action': 'investigated'
            })
            
        except Exception as e:
            logger.error(f"Error processing DLQ message {record['messageId']}: {str(e)}")
            # Don't re-raise for DLQ processing to avoid infinite loops
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': len(processed_messages),
            'messages': processed_messages
        })
    }
        '''


# Import sns_subscriptions here to avoid circular imports
from aws_cdk import aws_sns_subscriptions as sns_subscriptions


class NotificationPublisherStack(Stack):
    """
    Optional stack for creating resources to publish test notifications.
    
    This stack creates additional resources that can be used to publish
    test notifications to the notification system.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        notification_topic_arn: str,
        environment_name: str = "dev",
        **kwargs: StackProps,
    ) -> None:
        """
        Initialize the NotificationPublisherStack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            notification_topic_arn: ARN of the SNS topic to publish to
            environment_name: Environment name for resource naming
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        self.notification_topic = sns.Topic.from_topic_arn(
            self, "ImportedNotificationTopic", notification_topic_arn
        )

        self._create_publisher_function()

    def _create_publisher_function(self) -> None:
        """Create Lambda function for publishing test notifications."""
        
        # IAM role for the publisher function
        publisher_role = iam.Role(
            self,
            "PublisherRole",
            role_name=f"NotificationPublisherRole-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add SNS publish permissions
        publisher_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn],
            )
        )

        # Publisher function
        self.publisher_function = lambda_.Function(
            self,
            "NotificationPublisher",
            function_name=f"NotificationPublisher-{self.environment_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=publisher_role,
            timeout=Duration.minutes(1),
            environment={
                "TOPIC_ARN": self.notification_topic.topic_arn,
                "ENVIRONMENT": self.environment_name,
            },
            code=lambda_.Code.from_inline(self._get_publisher_code()),
            description="Publishes test notifications to the notification system",
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Add tags
        cdk.Tags.of(self.publisher_function).add("Environment", self.environment_name)
        cdk.Tags.of(self.publisher_function).add("Component", "TestPublisher")

        # Output the function ARN
        cdk.CfnOutput(
            self,
            "PublisherFunctionArn",
            value=self.publisher_function.function_arn,
            description="ARN of the notification publisher function",
            export_name=f"PublisherFunctionArn-{self.environment_name}",
        )

    def _get_publisher_code(self) -> str:
        """Return the publisher Lambda function code."""
        return '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """Publish test notifications to SNS topic."""
    
    topic_arn = os.environ['TOPIC_ARN']
    
    # Sample notifications for testing
    notifications = [
        {
            'type': 'email',
            'subject': 'Test Email Notification',
            'message': 'This is a test email notification from the CDK serverless notification system.',
            'recipient': 'test@example.com',
            'priority': 'high'
        },
        {
            'type': 'sms',
            'subject': 'Test SMS Notification',
            'message': 'This is a test SMS notification from the CDK serverless notification system.',
            'phone_number': '+1234567890',
            'priority': 'normal'
        },
        {
            'type': 'webhook',
            'subject': 'Test Webhook Notification',
            'message': 'This is a test webhook notification.',
            'webhook_url': 'https://httpbin.org/post',
            'payload': {
                'event': 'test_notification',
                'data': {'test': True, 'timestamp': datetime.utcnow().isoformat()}
            }
        },
        {
            'type': 'all',
            'subject': 'Broadcast Notification',
            'message': 'This notification will be sent to all channels.',
            'recipient': 'test@example.com',
            'phone_number': '+1234567890',
            'webhook_url': 'https://httpbin.org/post',
            'payload': {'broadcast': True}
        }
    ]
    
    published_messages = []
    
    for notification in notifications:
        notification_type = notification.pop('type')
        subject = notification.pop('subject')
        message = notification.pop('message')
        
        # Prepare message attributes for filtering
        message_attributes = {
            'notification_type': {
                'DataType': 'String',
                'StringValue': notification_type
            },
            'timestamp': {
                'DataType': 'String',
                'StringValue': datetime.utcnow().isoformat()
            }
        }
        
        # Prepare message body
        message_body = {
            'subject': subject,
            'message': message,
            'timestamp': datetime.utcnow().isoformat(),
            **notification
        }
        
        try:
            response = sns.publish(
                TopicArn=topic_arn,
                Message=json.dumps(message_body),
                Subject=subject,
                MessageAttributes=message_attributes
            )
            
            published_messages.append({
                'type': notification_type,
                'message_id': response['MessageId'],
                'subject': subject,
                'status': 'published'
            })
            
        except Exception as e:
            published_messages.append({
                'type': notification_type,
                'subject': subject,
                'status': 'failed',
                'error': str(e)
            })
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'published': len([m for m in published_messages if m['status'] == 'published']),
            'failed': len([m for m in published_messages if m['status'] == 'failed']),
            'messages': published_messages
        })
    }
        '''


def main() -> None:
    """Main application entry point."""
    app = cdk.App()

    # Get environment variables
    environment_name = app.node.try_get_context("environment") or "dev"
    test_email = app.node.try_get_context("testEmail") or os.environ.get("TEST_EMAIL")
    
    # AWS account and region
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    env = cdk.Environment(account=account, region=region)

    # Create the main notification system stack
    notification_stack = ServerlessNotificationSystemStack(
        app,
        f"ServerlessNotificationSystem-{environment_name}",
        environment_name=environment_name,
        test_email=test_email,
        env=env,
        description=f"Serverless notification system infrastructure for {environment_name} environment",
    )

    # Optionally create the publisher stack
    if app.node.try_get_context("createPublisher"):
        NotificationPublisherStack(
            app,
            f"NotificationPublisher-{environment_name}",
            notification_topic_arn=notification_stack.notification_topic.topic_arn,
            environment_name=environment_name,
            env=env,
            description=f"Test notification publisher for {environment_name} environment",
        )

    # Add global tags
    cdk.Tags.of(app).add("Project", "ServerlessNotificationSystem")
    cdk.Tags.of(app).add("Environment", environment_name)
    cdk.Tags.of(app).add("ManagedBy", "CDK")

    app.synth()


if __name__ == "__main__":
    main()