#!/usr/bin/env python3
"""
CDK Python Application for EventBridge Archive Event Replay Mechanisms

This application creates a complete event replay system using Amazon EventBridge Archive
to capture, filter, and replay events on-demand. The solution provides automated event
archiving with selective filtering, controlled replay mechanisms, and integration with
monitoring systems.

Architecture Components:
- Custom EventBridge Event Bus
- EventBridge Archive with retention policies
- Lambda function for event processing
- CloudWatch monitoring and alerting
- S3 bucket for logs and scripts
- IAM roles and policies with least privilege

Author: AWS CDK Generator
Version: 1.0
"""

import os
import json
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_s3 as s3,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct


class EventReplayMechanismsStack(Stack):
    """
    CDK Stack for EventBridge Archive Event Replay Mechanisms
    
    This stack creates a comprehensive event replay system that demonstrates
    how to implement event archiving, selective filtering, and controlled
    replay operations using AWS EventBridge.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment: str = "demo",
        event_retention_days: int = 30,
        enable_monitoring: bool = True,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the EventReplayMechanismsStack.
        
        Args:
            scope: The scope in which this stack is defined
            construct_id: The scoped construct ID
            environment: Environment name (demo, dev, prod)
            event_retention_days: Number of days to retain events in archive
            enable_monitoring: Whether to enable CloudWatch monitoring
            notification_email: Email address for SNS notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Store configuration
        self.environment = environment
        self.event_retention_days = event_retention_days
        self.enable_monitoring = enable_monitoring
        self.notification_email = notification_email
        
        # Create all stack resources
        self._create_s3_bucket()
        self._create_event_bus()
        self._create_lambda_function()
        self._create_event_rules()
        self._create_event_archive()
        self._create_monitoring_resources()
        self._create_outputs()

    def _create_s3_bucket(self) -> None:
        """Create S3 bucket for storing logs and replay scripts."""
        self.logs_bucket = s3.Bucket(
            self,
            "EventReplayLogsBucket",
            bucket_name=f"eventbridge-replay-logs-{self.environment}-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=s3.BucketVersioning.ENABLED,
            server_access_logs_prefix="access-logs/",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldLogs",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ],
        )
        
        # Add tags for resource management
        cdk.Tags.of(self.logs_bucket).add("Purpose", "EventReplayDemo")
        cdk.Tags.of(self.logs_bucket).add("Environment", self.environment)

    def _create_event_bus(self) -> None:
        """Create custom EventBridge event bus for event replay demonstration."""
        self.event_bus = events.EventBus(
            self,
            "EventReplayBus",
            event_bus_name=f"replay-demo-bus-{self.environment}",
            description="Custom event bus for event replay demonstration",
        )
        
        # Create event bus policy for cross-account access if needed
        self.event_bus.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowAccountAccess",
                effect=iam.Effect.ALLOW,
                principals=[iam.AccountRootPrincipal()],
                actions=[
                    "events:PutEvents",
                    "events:StartReplay",
                    "events:CancelReplay",
                    "events:DescribeReplay",
                ],
                resources=[self.event_bus.event_bus_arn],
            )
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for processing events and replays."""
        # Create IAM role for Lambda with least privilege
        self.lambda_role = iam.Role(
            self,
            "EventProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "EventProcessingPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/lambda/*"
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                            ],
                            resources=[f"{self.logs_bucket.bucket_arn}/*"],
                        ),
                    ]
                )
            },
        )
        
        # Create Lambda function code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process events and log details for replay analysis.
    
    This function demonstrates how to distinguish between original
    and replayed events, enabling different processing logic for
    replay scenarios.
    """
    try:
        # Log the complete event for debugging
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_time = event.get('time', datetime.utcnow().isoformat())
        event_id = event.get('id', 'unknown')
        
        # Check if this is a replayed event
        replay_name = event.get('replay-name')
        is_replay = bool(replay_name)
        
        if is_replay:
            logger.info(f"Processing REPLAYED event from: {replay_name}")
            logger.info(f"Event ID: {event_id}")
        else:
            logger.info(f"Processing ORIGINAL event: {event_id}")
        
        # Simulate business logic processing based on event source
        processing_result = process_event_by_source(event, is_replay)
        
        # Log processing metrics
        log_processing_metrics(event_source, event_type, is_replay, processing_result)
        
        # Return successful response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventId': event_id,
                'eventSource': event_source,
                'eventType': event_type,
                'isReplay': is_replay,
                'replayName': replay_name,
                'processingResult': processing_result
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        logger.error(f"Event details: {json.dumps(event, indent=2)}")
        raise

def process_event_by_source(event, is_replay):
    """Process events based on their source with replay-aware logic."""
    event_source = event.get('source', 'unknown')
    detail = event.get('detail', {})
    
    if event_source == 'myapp.orders':
        return process_order_event(detail, is_replay)
    elif event_source == 'myapp.users':
        return process_user_event(detail, is_replay)
    elif event_source == 'myapp.inventory':
        return process_inventory_event(detail, is_replay)
    else:
        logger.info(f"Processing generic event from: {event_source}")
        return {'status': 'processed', 'type': 'generic'}

def process_order_event(detail, is_replay):
    """Process order-related events with replay detection."""
    order_id = detail.get('orderId', 'unknown')
    amount = detail.get('amount', 0)
    customer_id = detail.get('customerId', 'unknown')
    
    if is_replay:
        # For replayed events, we might want to skip certain actions
        # like sending notifications or updating external systems
        logger.info(f"REPLAY: Order event for order {order_id} (amount: ${amount})")
        return {
            'status': 'replay_processed',
            'orderId': order_id,
            'amount': amount,
            'customerId': customer_id,
            'action': 'replay_analysis_only'
        }
    else:
        # For original events, perform full processing
        logger.info(f"ORIGINAL: Processing order {order_id} for customer {customer_id}")
        return {
            'status': 'fully_processed',
            'orderId': order_id,
            'amount': amount,
            'customerId': customer_id,
            'action': 'full_business_logic'
        }

def process_user_event(detail, is_replay):
    """Process user-related events with replay detection."""
    user_id = detail.get('userId', 'unknown')
    email = detail.get('email', 'unknown')
    
    if is_replay:
        logger.info(f"REPLAY: User event for user {user_id}")
        return {
            'status': 'replay_processed',
            'userId': user_id,
            'email': email,
            'action': 'replay_analysis_only'
        }
    else:
        logger.info(f"ORIGINAL: Processing user registration for {user_id}")
        return {
            'status': 'fully_processed',
            'userId': user_id,
            'email': email,
            'action': 'full_user_onboarding'
        }

def process_inventory_event(detail, is_replay):
    """Process inventory-related events with replay detection."""
    item_id = detail.get('itemId', 'unknown')
    quantity = detail.get('quantity', 0)
    
    if is_replay:
        logger.info(f"REPLAY: Inventory event for item {item_id}")
        return {
            'status': 'replay_processed',
            'itemId': item_id,
            'quantity': quantity,
            'action': 'replay_analysis_only'
        }
    else:
        logger.info(f"ORIGINAL: Processing inventory update for {item_id}")
        return {
            'status': 'fully_processed',
            'itemId': item_id,
            'quantity': quantity,
            'action': 'full_inventory_update'
        }

def log_processing_metrics(event_source, event_type, is_replay, processing_result):
    """Log metrics for monitoring and analysis."""
    metrics = {
        'timestamp': datetime.utcnow().isoformat(),
        'eventSource': event_source,
        'eventType': event_type,
        'isReplay': is_replay,
        'processingStatus': processing_result.get('status', 'unknown'),
        'processingAction': processing_result.get('action', 'unknown')
    }
    
    logger.info(f"METRICS: {json.dumps(metrics)}")
'''
        
        # Create Lambda function
        self.event_processor = lambda_.Function(
            self,
            "EventProcessor",
            function_name=f"replay-processor-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "ENVIRONMENT": self.environment,
                "LOG_LEVEL": "INFO",
                "S3_BUCKET": self.logs_bucket.bucket_name,
            },
            description="Process events and handle replay scenarios",
        )
        
        # Create custom log group with retention
        self.lambda_log_group = logs.LogGroup(
            self,
            "EventProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.event_processor.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for routing events to Lambda."""
        # Create rule for application events
        self.event_rule = events.Rule(
            self,
            "EventReplayRule",
            rule_name=f"replay-demo-rule-{self.environment}",
            event_bus=self.event_bus,
            description="Rule for processing application events",
            event_pattern=events.EventPattern(
                source=["myapp.orders", "myapp.users", "myapp.inventory"],
                detail_type=["Order Created", "User Registered", "Inventory Updated"],
            ),
        )
        
        # Add Lambda function as target
        self.event_rule.add_target(
            targets.LambdaFunction(
                self.event_processor,
                retry_attempts=3,
                max_event_age=Duration.hours(2),
                dead_letter_queue=self._create_dead_letter_queue(),
            )
        )

    def _create_dead_letter_queue(self) -> sns.Topic:
        """Create SNS topic for dead letter queue."""
        self.dlq_topic = sns.Topic(
            self,
            "EventProcessingDLQ",
            topic_name=f"event-processing-dlq-{self.environment}",
            display_name="Event Processing Dead Letter Queue",
        )
        
        # Add email subscription if provided
        if self.notification_email:
            self.dlq_topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )
        
        return self.dlq_topic

    def _create_event_archive(self) -> None:
        """Create EventBridge archive for event replay."""
        self.event_archive = events.Archive(
            self,
            "EventReplayArchive",
            archive_name=f"replay-demo-archive-{self.environment}",
            source_event_bus=self.event_bus,
            description="Archive for order and user events",
            event_pattern=events.EventPattern(
                source=["myapp.orders", "myapp.users"],
                detail_type=["Order Created", "User Registered"],
            ),
            retention=Duration.days(self.event_retention_days),
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and alerting resources."""
        if not self.enable_monitoring:
            return
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "EventReplayDashboard",
            dashboard_name=f"EventReplay-{self.environment}",
        )
        
        # Add Lambda metrics widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                width=12,
                height=6,
                left=[
                    self.event_processor.metric_invocations(
                        period=Duration.minutes(5)
                    ),
                    self.event_processor.metric_errors(
                        period=Duration.minutes(5)
                    ),
                    self.event_processor.metric_duration(
                        period=Duration.minutes(5)
                    ),
                ],
            )
        )
        
        # Create alarm for Lambda errors
        self.lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"EventProcessor-Errors-{self.environment}",
            alarm_description="Alert when Lambda function has errors",
            metric=self.event_processor.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        # Add SNS notification to alarm if email provided
        if self.notification_email:
            alarm_topic = sns.Topic(
                self,
                "EventReplayAlarms",
                topic_name=f"event-replay-alarms-{self.environment}",
            )
            alarm_topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )
            self.lambda_error_alarm.add_alarm_action(
                cloudwatch.SnsAction(alarm_topic)
            )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Name of the custom EventBridge event bus",
            export_name=f"EventReplayBusName-{self.environment}",
        )
        
        CfnOutput(
            self,
            "EventBusArn",
            value=self.event_bus.event_bus_arn,
            description="ARN of the custom EventBridge event bus",
            export_name=f"EventReplayBusArn-{self.environment}",
        )
        
        CfnOutput(
            self,
            "EventArchiveName",
            value=self.event_archive.archive_name,
            description="Name of the EventBridge archive",
            export_name=f"EventReplayArchiveName-{self.environment}",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.event_processor.function_name,
            description="Name of the event processing Lambda function",
            export_name=f"EventProcessorFunctionName-{self.environment}",
        )
        
        CfnOutput(
            self,
            "S3BucketName",
            value=self.logs_bucket.bucket_name,
            description="Name of the S3 bucket for logs and scripts",
            export_name=f"EventReplayLogsBucket-{self.environment}",
        )
        
        CfnOutput(
            self,
            "EventRuleName",
            value=self.event_rule.rule_name,
            description="Name of the EventBridge rule",
            export_name=f"EventReplayRuleName-{self.environment}",
        )


class EventReplayMechanismsApp(cdk.App):
    """CDK Application for EventBridge Archive Event Replay Mechanisms."""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from environment variables or use defaults
        environment = self.node.try_get_context("environment") or "demo"
        event_retention_days = int(self.node.try_get_context("eventRetentionDays") or "30")
        enable_monitoring = self.node.try_get_context("enableMonitoring") != "false"
        notification_email = self.node.try_get_context("notificationEmail")
        
        # Create the stack
        EventReplayMechanismsStack(
            self,
            f"EventReplayMechanismsStack-{environment}",
            environment=environment,
            event_retention_days=event_retention_days,
            enable_monitoring=enable_monitoring,
            notification_email=notification_email,
            description="EventBridge Archive Event Replay Mechanisms Stack",
        )


# Create the application
app = EventReplayMechanismsApp()
app.synth()