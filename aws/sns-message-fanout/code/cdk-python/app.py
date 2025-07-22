#!/usr/bin/env python3
"""
CDK Python Application for SNS-SQS Message Fan-out Architecture

This application deploys a complete message fan-out solution using Amazon SNS
and multiple SQS queues with dead letter queues, message filtering, and
comprehensive monitoring.

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_sns as sns,
    aws_sqs as sqs,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class MessageFanOutStack(Stack):
    """
    CDK Stack for implementing SNS-SQS message fan-out architecture.
    
    This stack creates:
    - SNS topic for order events
    - Multiple SQS queues for different business functions
    - Dead letter queues for error handling
    - Message filtering subscriptions
    - CloudWatch alarms and dashboard
    - Proper IAM policies for secure access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "dev",
        enable_detailed_monitoring: bool = True,
        message_retention_days: int = 14,
        max_receive_count: int = 3,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.environment_name = environment_name
        self.enable_detailed_monitoring = enable_detailed_monitoring
        self.message_retention_days = message_retention_days
        self.max_receive_count = max_receive_count

        # Create dead letter queues first
        self.dead_letter_queues = self._create_dead_letter_queues()
        
        # Create primary processing queues
        self.processing_queues = self._create_processing_queues()
        
        # Create SNS topic
        self.sns_topic = self._create_sns_topic()
        
        # Create SNS subscriptions with filtering
        self._create_sns_subscriptions()
        
        # Create CloudWatch monitoring
        if self.enable_detailed_monitoring:
            self._create_cloudwatch_monitoring()
        
        # Create outputs
        self._create_outputs()

    def _create_dead_letter_queues(self) -> Dict[str, sqs.Queue]:
        """Create dead letter queues for error handling."""
        dlq_configs = [
            "inventory-dlq",
            "payment-dlq",
            "shipping-dlq",
            "analytics-dlq"
        ]
        
        dlqs = {}
        for dlq_name in dlq_configs:
            queue_name = f"{dlq_name}-{self.environment_name}"
            
            dlq = sqs.Queue(
                self,
                f"{dlq_name.replace('-', '_').title()}",
                queue_name=queue_name,
                retention_period=Duration.days(self.message_retention_days),
                visibility_timeout=Duration.seconds(60),
                removal_policy=RemovalPolicy.DESTROY,
            )
            
            # Add tags for resource management
            cdk.Tags.of(dlq).add("Environment", self.environment_name)
            cdk.Tags.of(dlq).add("Application", "message-fanout")
            cdk.Tags.of(dlq).add("QueueType", "DeadLetter")
            
            dlqs[dlq_name] = dlq
        
        return dlqs

    def _create_processing_queues(self) -> Dict[str, sqs.Queue]:
        """Create primary processing queues with DLQ configuration."""
        queue_configs = [
            {
                "name": "inventory-processing",
                "dlq_key": "inventory-dlq",
                "visibility_timeout": 300,
                "description": "Queue for inventory update and stock check events"
            },
            {
                "name": "payment-processing",
                "dlq_key": "payment-dlq",
                "visibility_timeout": 300,
                "description": "Queue for payment request and confirmation events"
            },
            {
                "name": "shipping-notifications",
                "dlq_key": "shipping-dlq",
                "visibility_timeout": 300,
                "description": "Queue for shipping notification and delivery update events"
            },
            {
                "name": "analytics-reporting",
                "dlq_key": "analytics-dlq",
                "visibility_timeout": 300,
                "description": "Queue for analytics and reporting events (all events)"
            }
        ]
        
        queues = {}
        for config in queue_configs:
            queue_name = f"{config['name']}-{self.environment_name}"
            
            # Create redrive policy
            redrive_policy = sqs.RedrivePolicy(
                max_receive_count=self.max_receive_count,
                dead_letter_queue=self.dead_letter_queues[config["dlq_key"]]
            )
            
            queue = sqs.Queue(
                self,
                f"{config['name'].replace('-', '_').title()}Queue",
                queue_name=queue_name,
                visibility_timeout=Duration.seconds(config["visibility_timeout"]),
                retention_period=Duration.days(self.message_retention_days),
                redrive_policy=redrive_policy,
                removal_policy=RemovalPolicy.DESTROY,
            )
            
            # Add tags for resource management
            cdk.Tags.of(queue).add("Environment", self.environment_name)
            cdk.Tags.of(queue).add("Application", "message-fanout")
            cdk.Tags.of(queue).add("QueueType", "Processing")
            cdk.Tags.of(queue).add("BusinessFunction", config["name"].split("-")[0].title())
            
            queues[config["name"]] = queue
        
        return queues

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for order events."""
        topic_name = f"order-events-{self.environment_name}"
        
        topic = sns.Topic(
            self,
            "OrderEventsTopic",
            topic_name=topic_name,
            display_name="Order Events Topic",
            fifo=False,
        )
        
        # Configure delivery policy for reliability
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowOrderApplicationPublish",
                effect=iam.Effect.ALLOW,
                principals=[iam.AccountRootPrincipal()],
                actions=["sns:Publish"],
                resources=[topic.topic_arn],
                conditions={
                    "StringEquals": {
                        "aws:RequestedRegion": self.region
                    }
                }
            )
        )
        
        # Add tags for resource management
        cdk.Tags.of(topic).add("Environment", self.environment_name)
        cdk.Tags.of(topic).add("Application", "message-fanout")
        cdk.Tags.of(topic).add("ResourceType", "SNSTopic")
        
        return topic

    def _create_sns_subscriptions(self) -> None:
        """Create SNS subscriptions with message filtering."""
        subscription_configs = [
            {
                "queue_name": "inventory-processing",
                "filter_policy": {
                    "eventType": sns.SubscriptionFilter.string_filter(
                        allowlist=["inventory_update", "stock_check"]
                    ),
                    "priority": sns.SubscriptionFilter.string_filter(
                        allowlist=["high", "medium"]
                    )
                },
                "description": "Inventory processing subscription with filtering"
            },
            {
                "queue_name": "payment-processing",
                "filter_policy": {
                    "eventType": sns.SubscriptionFilter.string_filter(
                        allowlist=["payment_request", "payment_confirmation"]
                    ),
                    "priority": sns.SubscriptionFilter.string_filter(
                        allowlist=["high"]
                    )
                },
                "description": "Payment processing subscription with filtering"
            },
            {
                "queue_name": "shipping-notifications",
                "filter_policy": {
                    "eventType": sns.SubscriptionFilter.string_filter(
                        allowlist=["shipping_notification", "delivery_update"]
                    ),
                    "priority": sns.SubscriptionFilter.string_filter(
                        allowlist=["high", "medium", "low"]
                    )
                },
                "description": "Shipping notifications subscription with filtering"
            },
            {
                "queue_name": "analytics-reporting",
                "filter_policy": None,  # No filter - receive all events
                "description": "Analytics reporting subscription without filtering"
            }
        ]
        
        for config in subscription_configs:
            queue = self.processing_queues[config["queue_name"]]
            
            # Create subscription
            subscription = sns.Subscription(
                self,
                f"{config['queue_name'].replace('-', '_').title()}Subscription",
                topic=self.sns_topic,
                endpoint=queue.queue_arn,
                protocol=sns.SubscriptionProtocol.SQS,
                filter_policy=config["filter_policy"],
                raw_message_delivery=False,
            )
            
            # Grant SNS permission to send messages to SQS
            queue.add_to_resource_policy(
                iam.PolicyStatement(
                    sid="AllowSNSDelivery",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("sns.amazonaws.com")],
                    actions=["sqs:SendMessage"],
                    resources=[queue.queue_arn],
                    conditions={
                        "ArnEquals": {
                            "aws:SourceArn": self.sns_topic.topic_arn
                        }
                    }
                )
            )

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch alarms and dashboard for monitoring."""
        # Create alarms for queue depth monitoring
        self._create_queue_depth_alarms()
        
        # Create SNS delivery failure alarm
        self._create_sns_failure_alarm()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()

    def _create_queue_depth_alarms(self) -> None:
        """Create CloudWatch alarms for queue depth monitoring."""
        alarm_configs = [
            {
                "queue_name": "inventory-processing",
                "threshold": 100,
                "alarm_name": "inventory-queue-depth"
            },
            {
                "queue_name": "payment-processing",
                "threshold": 50,
                "alarm_name": "payment-queue-depth"
            },
            {
                "queue_name": "shipping-notifications",
                "threshold": 200,
                "alarm_name": "shipping-queue-depth"
            },
            {
                "queue_name": "analytics-reporting",
                "threshold": 500,
                "alarm_name": "analytics-queue-depth"
            }
        ]
        
        for config in alarm_configs:
            queue = self.processing_queues[config["queue_name"]]
            
            cloudwatch.Alarm(
                self,
                f"{config['alarm_name'].replace('-', '_').title()}Alarm",
                alarm_name=f"{config['alarm_name']}-{self.environment_name}",
                alarm_description=f"Monitor {config['queue_name']} queue depth",
                metric=queue.metric_approximate_number_of_visible_messages(
                    statistic=cloudwatch.Statistic.AVERAGE,
                    period=Duration.minutes(5)
                ),
                threshold=config["threshold"],
                evaluation_periods=2,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
                treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
            )

    def _create_sns_failure_alarm(self) -> None:
        """Create CloudWatch alarm for SNS delivery failures."""
        cloudwatch.Alarm(
            self,
            "SnsFailureAlarm",
            alarm_name=f"sns-failed-deliveries-{self.environment_name}",
            alarm_description="Monitor SNS failed deliveries",
            metric=self.sns_topic.metric_number_of_notifications_failed(
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for comprehensive monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "MessageFanOutDashboard",
            dashboard_name=f"sns-fanout-dashboard-{self.environment_name}",
            widgets=[
                [
                    # SNS metrics widget
                    cloudwatch.GraphWidget(
                        title="SNS Message Publishing",
                        left=[
                            self.sns_topic.metric_number_of_messages_published(
                                statistic=cloudwatch.Statistic.SUM,
                                period=Duration.minutes(5)
                            )
                        ],
                        right=[
                            self.sns_topic.metric_number_of_notifications_failed(
                                statistic=cloudwatch.Statistic.SUM,
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                    )
                ],
                [
                    # SQS queue depths widget
                    cloudwatch.GraphWidget(
                        title="SQS Queue Depths",
                        left=[
                            queue.metric_approximate_number_of_visible_messages(
                                statistic=cloudwatch.Statistic.AVERAGE,
                                period=Duration.minutes(5),
                                label=queue_name
                            )
                            for queue_name, queue in self.processing_queues.items()
                        ],
                        width=12,
                    )
                ],
                [
                    # DLQ monitoring widget
                    cloudwatch.GraphWidget(
                        title="Dead Letter Queue Messages",
                        left=[
                            dlq.metric_approximate_number_of_visible_messages(
                                statistic=cloudwatch.Statistic.AVERAGE,
                                period=Duration.minutes(5),
                                label=dlq_name
                            )
                            for dlq_name, dlq in self.dead_letter_queues.items()
                        ],
                        width=12,
                    )
                ]
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        # SNS Topic outputs
        CfnOutput(
            self,
            "SnsTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for order events",
            export_name=f"MessageFanOut-{self.environment_name}-SnsTopicArn"
        )
        
        CfnOutput(
            self,
            "SnsTopicName",
            value=self.sns_topic.topic_name,
            description="Name of the SNS topic for order events",
            export_name=f"MessageFanOut-{self.environment_name}-SnsTopicName"
        )
        
        # SQS Queue outputs
        for queue_name, queue in self.processing_queues.items():
            CfnOutput(
                self,
                f"{queue_name.replace('-', '_').title()}QueueUrl",
                value=queue.queue_url,
                description=f"URL of the {queue_name} queue",
                export_name=f"MessageFanOut-{self.environment_name}-{queue_name.replace('-', '_').title()}QueueUrl"
            )
            
            CfnOutput(
                self,
                f"{queue_name.replace('-', '_').title()}QueueArn",
                value=queue.queue_arn,
                description=f"ARN of the {queue_name} queue",
                export_name=f"MessageFanOut-{self.environment_name}-{queue_name.replace('-', '_').title()}QueueArn"
            )
        
        # DLQ outputs
        for dlq_name, dlq in self.dead_letter_queues.items():
            CfnOutput(
                self,
                f"{dlq_name.replace('-', '_').title()}Url",
                value=dlq.queue_url,
                description=f"URL of the {dlq_name}",
                export_name=f"MessageFanOut-{self.environment_name}-{dlq_name.replace('-', '_').title()}Url"
            )


class MessageFanOutApp(App):
    """
    CDK Application for Message Fan-out Architecture.
    
    This application can be configured through environment variables:
    - ENVIRONMENT_NAME: Environment name (default: dev)
    - ENABLE_DETAILED_MONITORING: Enable detailed monitoring (default: true)
    - MESSAGE_RETENTION_DAYS: Message retention period in days (default: 14)
    - MAX_RECEIVE_COUNT: Maximum receive count for DLQ (default: 3)
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get configuration from environment variables
        environment_name = os.getenv("ENVIRONMENT_NAME", "dev")
        enable_detailed_monitoring = os.getenv("ENABLE_DETAILED_MONITORING", "true").lower() == "true"
        message_retention_days = int(os.getenv("MESSAGE_RETENTION_DAYS", "14"))
        max_receive_count = int(os.getenv("MAX_RECEIVE_COUNT", "3"))
        
        # Create the main stack
        MessageFanOutStack(
            self,
            f"MessageFanOutStack-{environment_name}",
            environment_name=environment_name,
            enable_detailed_monitoring=enable_detailed_monitoring,
            message_retention_days=message_retention_days,
            max_receive_count=max_receive_count,
            description=f"SNS-SQS Message Fan-out Architecture for {environment_name} environment",
            tags={
                "Application": "message-fanout",
                "Environment": environment_name,
                "ManagedBy": "CDK",
            }
        )


# Application entry point
def main() -> None:
    """Main entry point for the CDK application."""
    app = MessageFanOutApp()
    app.synth()


if __name__ == "__main__":
    main()