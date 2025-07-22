#!/usr/bin/env python3
"""
CDK Python application for EventBridge Event-Driven Architecture Recipe

This application deploys a comprehensive event-driven architecture using:
- Amazon EventBridge custom event bus
- Lambda functions for event processing
- SNS topics for notifications
- SQS queues for batch processing
- IAM roles with least privilege access
- CloudWatch monitoring and logging
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sqs as sqs,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List


class EventDrivenArchitectureStack(Stack):
    """
    CDK Stack for EventBridge Event-Driven Architecture
    
    This stack creates a complete event-driven architecture demonstrating:
    - Custom EventBridge event bus for application events
    - Event rules for pattern-based routing
    - Multiple event targets (Lambda, SNS, SQS)
    - Proper IAM roles and permissions
    - CloudWatch monitoring and logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create custom EventBridge event bus
        self.event_bus = self._create_event_bus()
        
        # Create event processing infrastructure
        self.sns_topic = self._create_sns_topic()
        self.sqs_queue = self._create_sqs_queue()
        self.lambda_function = self._create_lambda_function()
        
        # Create EventBridge rules and targets
        self._create_event_rules()
        
        # Create CloudWatch dashboard for monitoring
        self._create_monitoring_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_event_bus(self) -> events.EventBus:
        """Create custom EventBridge event bus for e-commerce events"""
        
        event_bus = events.EventBus(
            self, "ECommerceEventBus",
            event_bus_name="ecommerce-events",
            description="Custom event bus for e-commerce application events"
        )
        
        # Add tags for resource management
        cdk.Tags.of(event_bus).add("Purpose", "EventDrivenArchitecture")
        cdk.Tags.of(event_bus).add("Environment", "Demo")
        
        return event_bus

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for order notifications"""
        
        topic = sns.Topic(
            self, "OrderNotificationsTopic",
            topic_name="order-notifications",
            display_name="Order Notifications",
            description="SNS topic for order-related notifications"
        )
        
        # Add tags
        cdk.Tags.of(topic).add("Purpose", "OrderNotifications")
        
        return topic

    def _create_sqs_queue(self) -> sqs.Queue:
        """Create SQS queue for batch event processing"""
        
        # Create dead letter queue for failed messages
        dlq = sqs.Queue(
            self, "EventProcessingDLQ",
            queue_name="event-processing-dlq",
            retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5)
        )
        
        # Create main processing queue
        queue = sqs.Queue(
            self, "EventProcessingQueue",
            queue_name="event-processing",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=dlq
            )
        )
        
        # Add tags
        cdk.Tags.of(queue).add("Purpose", "EventProcessing")
        cdk.Tags.of(dlq).add("Purpose", "DeadLetterQueue")
        
        return queue

    def _create_lambda_function(self) -> lambda_.Function:
        """Create Lambda function for event processing"""
        
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self, "EventProcessorLogGroup",
            log_group_name="/aws/lambda/event-processor",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "EventProcessorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for EventBridge event processor Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Create Lambda function
        lambda_function = lambda_.Function(
            self, "EventProcessorFunction",
            function_name="event-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            log_group=log_group,
            description="Process events from EventBridge custom bus",
            environment={
                "LOG_LEVEL": "INFO",
                "POWERTOOLS_SERVICE_NAME": "event-processor"
            }
        )
        
        # Add tags
        cdk.Tags.of(lambda_function).add("Purpose", "EventProcessing")
        
        return lambda_function

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for event routing"""
        
        # Rule 1: Route all order events to Lambda
        order_events_rule = events.Rule(
            self, "OrderEventsRule",
            rule_name="OrderEventsRule",
            event_bus=self.event_bus,
            description="Route order events to Lambda processor",
            event_pattern=events.EventPattern(
                source=["ecommerce.orders"],
                detail_type=["Order Created", "Order Updated", "Order Cancelled"]
            )
        )
        
        # Add Lambda target to order events rule
        order_events_rule.add_target(
            targets.LambdaFunction(
                self.lambda_function,
                retry_attempts=2,
                max_event_age=Duration.minutes(5)
            )
        )
        
        # Rule 2: Route high-value orders to SNS for immediate notification
        high_value_orders_rule = events.Rule(
            self, "HighValueOrdersRule",
            rule_name="HighValueOrdersRule",
            event_bus=self.event_bus,
            description="Route high-value orders to SNS for notifications",
            event_pattern=events.EventPattern(
                source=["ecommerce.orders"],
                detail_type=["Order Created"],
                detail={
                    "totalAmount": events.Match.any_of(
                        events.Match.greater_than(1000)
                    )
                }
            )
        )
        
        # Add SNS target to high-value orders rule
        high_value_orders_rule.add_target(
            targets.SnsTopic(
                self.sns_topic,
                message=events.RuleTargetInput.from_event_path("$.detail")
            )
        )
        
        # Rule 3: Route all events to SQS for batch processing
        all_events_rule = events.Rule(
            self, "AllEventsToSQSRule",
            rule_name="AllEventsToSQSRule",
            event_bus=self.event_bus,
            description="Route all events to SQS for batch processing",
            event_pattern=events.EventPattern(
                source=["ecommerce.orders", "ecommerce.users", "ecommerce.payments"]
            )
        )
        
        # Add SQS target to all events rule
        all_events_rule.add_target(
            targets.SqsQueue(
                self.sqs_queue,
                message_group_id="event-processing"
            )
        )
        
        # Rule 4: Route user registration events to Lambda
        user_registration_rule = events.Rule(
            self, "UserRegistrationRule",
            rule_name="UserRegistrationRule",
            event_bus=self.event_bus,
            description="Route user registration events to Lambda",
            event_pattern=events.EventPattern(
                source=["ecommerce.users"],
                detail_type=["User Registered"]
            )
        )
        
        # Add Lambda target to user registration rule
        user_registration_rule.add_target(
            targets.LambdaFunction(
                self.lambda_function,
                retry_attempts=2,
                max_event_age=Duration.minutes(5)
            )
        )

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring event-driven architecture"""
        
        # Import CloudWatch module for dashboard creation
        from aws_cdk import aws_cloudwatch as cloudwatch
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self, "EventDrivenArchitectureDashboard",
            dashboard_name="EventDrivenArchitecture",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="EventBridge Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Events",
                                metric_name="SuccessfulInvocations",
                                dimensions_map={
                                    "EventBusName": self.event_bus.event_bus_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Events",
                                metric_name="FailedInvocations",
                                dimensions_map={
                                    "EventBusName": self.event_bus.event_bus_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Lambda Function Metrics",
                        left=[
                            self.lambda_function.metric_invocations(
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            self.lambda_function.metric_errors(
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            self.lambda_function.metric_duration(
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="SQS Queue Metrics",
                        left=[
                            self.sqs_queue.metric_approximate_number_of_messages_visible(
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            self.sqs_queue.metric_approximate_number_of_messages_not_visible(
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Name of the custom EventBridge event bus",
            export_name="EventBusName"
        )
        
        CfnOutput(
            self, "EventBusArn",
            value=self.event_bus.event_bus_arn,
            description="ARN of the custom EventBridge event bus",
            export_name="EventBusArn"
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for notifications",
            export_name="SNSTopicArn"
        )
        
        CfnOutput(
            self, "SQSQueueUrl",
            value=self.sqs_queue.queue_url,
            description="URL of the SQS queue for batch processing",
            export_name="SQSQueueUrl"
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function for event processing",
            export_name="LambdaFunctionArn"
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for event processing",
            export_name="LambdaFunctionName"
        )

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for event processing"""
        
        return '''
import json
import logging
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process EventBridge events
    
    Args:
        event: EventBridge event data
        context: Lambda context object
        
    Returns:
        Response dictionary with processing results
    """
    
    try:
        logger.info(f"Received event: {json.dumps(event, indent=2)}")
        
        # Extract event details
        event_source = event.get('source', 'unknown')
        event_type = event.get('detail-type', 'unknown')
        event_detail = event.get('detail', {})
        
        # Process based on event type
        result = process_event(event_source, event_type, event_detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Event processed successfully',
                'eventSource': event_source,
                'eventType': event_type,
                'result': result,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_event(source: str, event_type: str, detail: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process different types of events based on source
    
    Args:
        source: Event source (e.g., 'ecommerce.orders')
        event_type: Event detail type
        detail: Event detail payload
        
    Returns:
        Processing result dictionary
    """
    
    if source == 'ecommerce.orders':
        return process_order_event(event_type, detail)
    elif source == 'ecommerce.users':
        return process_user_event(event_type, detail)
    elif source == 'ecommerce.payments':
        return process_payment_event(event_type, detail)
    else:
        return process_generic_event(event_type, detail)

def process_order_event(event_type: str, detail: Dict[str, Any]) -> Dict[str, Any]:
    """Process order-related events"""
    
    if event_type == 'Order Created':
        order_id = detail.get('orderId')
        customer_id = detail.get('customerId')
        total_amount = detail.get('totalAmount', 0)
        
        logger.info(f"Processing new order: {order_id} for customer {customer_id}")
        
        return {
            'action': 'order_processed',
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'priority': 'high' if total_amount > 1000 else 'normal'
        }
        
    elif event_type == 'Order Cancelled':
        order_id = detail.get('orderId')
        logger.info(f"Processing order cancellation: {order_id}")
        
        return {
            'action': 'order_cancelled',
            'orderId': order_id
        }
    
    return {'action': 'order_event_processed'}

def process_user_event(event_type: str, detail: Dict[str, Any]) -> Dict[str, Any]:
    """Process user-related events"""
    
    if event_type == 'User Registered':
        user_id = detail.get('userId')
        email = detail.get('email')
        
        logger.info(f"Processing new user registration: {user_id}")
        
        return {
            'action': 'user_registered',
            'userId': user_id,
            'email': email,
            'welcomeEmailSent': True
        }
    
    return {'action': 'user_event_processed'}

def process_payment_event(event_type: str, detail: Dict[str, Any]) -> Dict[str, Any]:
    """Process payment-related events"""
    
    if event_type == 'Payment Processed':
        payment_id = detail.get('paymentId')
        amount = detail.get('amount')
        
        logger.info(f"Processing payment: {payment_id} for amount {amount}")
        
        return {
            'action': 'payment_processed',
            'paymentId': payment_id,
            'amount': amount
        }
    
    return {'action': 'payment_event_processed'}

def process_generic_event(event_type: str, detail: Dict[str, Any]) -> Dict[str, Any]:
    """Process generic events"""
    
    logger.info(f"Processing generic event: {event_type}")
    
    return {
        'action': 'generic_event_processed',
        'eventType': event_type
    }
'''


# CDK Application
app = cdk.App()

# Create the stack
EventDrivenArchitectureStack(
    app, 
    "EventDrivenArchitectureStack",
    description="Event-driven architecture with EventBridge, Lambda, SNS, and SQS",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    )
)

# Add tags to the entire application
cdk.Tags.of(app).add("Project", "EventDrivenArchitecture")
cdk.Tags.of(app).add("Owner", "DevOps")

app.synth()