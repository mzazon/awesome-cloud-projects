#!/usr/bin/env python3
"""
CDK Python application for Event-Driven Architectures with Amazon EventBridge

This application creates a complete event-driven architecture using Amazon EventBridge
as the central event router for an e-commerce platform. It demonstrates:
- Custom EventBridge event buses
- Event pattern matching and routing rules
- Lambda functions for event processing
- SQS integration for asynchronous processing
- CloudWatch Logs for event monitoring
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sqs as sqs,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy
)
from constructs import Construct
from typing import Dict, Any
import json


class EventDrivenArchitectureStack(Stack):
    """
    Stack for Microservices with EventBridge Routing
    
    This stack implements a complete e-commerce event-driven architecture with:
    - Custom event bus for domain isolation
    - Lambda functions for order processing and inventory management
    - SQS queue for asynchronous payment processing
    - EventBridge rules for intelligent event routing
    - CloudWatch Logs for comprehensive monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique identifier for resource naming
        unique_id = self.node.addr[-6:].lower()
        
        # Create custom event bus for e-commerce domain
        self.custom_event_bus = self._create_custom_event_bus(unique_id)
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions for event processing
        self.order_processor = self._create_order_processor_lambda(unique_id)
        self.inventory_manager = self._create_inventory_manager_lambda(unique_id)
        self.event_generator = self._create_event_generator_lambda(unique_id)
        
        # Create SQS queue for payment processing
        self.payment_queue = self._create_payment_processing_queue(unique_id)
        
        # Create CloudWatch log group for event monitoring
        self.event_log_group = self._create_event_log_group(unique_id)
        
        # Create EventBridge rules for event routing
        self._create_event_routing_rules(unique_id)
        
        # Create outputs for key resources
        self._create_outputs()

    def _create_custom_event_bus(self, unique_id: str) -> events.EventBus:
        """
        Create a custom EventBridge event bus for the e-commerce domain
        
        Custom event buses provide domain isolation and organizational boundaries
        for different business contexts, enabling specific security policies,
        monitoring, and access controls.
        """
        event_bus = events.EventBus(
            self, "EcommerceEventBus",
            event_bus_name=f"ecommerce-events-{unique_id}",
            description="Custom event bus for e-commerce platform events"
        )
        
        # Add tags for resource management
        cdk.Tags.of(event_bus).add("Purpose", "EcommerceDemoIntegration")
        cdk.Tags.of(event_bus).add("Domain", "E-commerce")
        
        return event_bus

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with EventBridge permissions
        
        This role provides necessary permissions for Lambda functions to:
        - Execute and write logs to CloudWatch
        - Publish events to EventBridge
        - Read from EventBridge rules and targets
        """
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name="EventBridgeDemoLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for EventBridge demo Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "EventBridgeInteractionPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "events:PutEvents",
                                "events:ListRules",
                                "events:DescribeRule"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_order_processor_lambda(self, unique_id: str) -> lambda_.Function:
        """
        Create Lambda function for processing order events
        
        This function demonstrates the producer-consumer pattern by:
        - Consuming "Order Created" events
        - Processing order logic
        - Producing "Order Processed" or "Order Processing Failed" events
        """
        order_processor_code = '''
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing order event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    customer_id = order_details.get('customerId', 'unknown')
    total_amount = order_details.get('totalAmount', 0)
    
    try:
        # Simulate order processing logic
        print(f"Processing order {order_id} for customer {customer_id}")
        print(f"Order total: ${total_amount}")
        
        # Emit order processed event
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'totalAmount': total_amount,
                        'status': 'processed',
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        print(f"Emitted order processed event: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order {order_id} processed successfully',
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        
        # Emit order failed event
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'ecommerce.order',
                    'DetailType': 'Order Processing Failed',
                    'Detail': json.dumps({
                        'orderId': order_id,
                        'customerId': customer_id,
                        'error': str(e),
                        'timestamp': datetime.utcnow().isoformat()
                    }),
                    'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

        function = lambda_.Function(
            self, "OrderProcessorFunction",
            function_name=f"eventbridge-demo-{unique_id}-order-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(order_processor_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name
            },
            description="Lambda function for processing order events in event-driven architecture"
        )
        
        return function

    def _create_inventory_manager_lambda(self, unique_id: str) -> lambda_.Function:
        """
        Create Lambda function for managing inventory events
        
        This function handles inventory decisions and demonstrates:
        - Event reaction patterns
        - Variable business outcomes (success/failure)
        - Downstream event emission based on availability
        """
        inventory_manager_code = '''
import json
import boto3
import os
from datetime import datetime

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    print(f"Processing inventory event: {json.dumps(event, indent=2)}")
    
    # Extract order details from the event
    order_details = event.get('detail', {})
    order_id = order_details.get('orderId', 'unknown')
    
    try:
        # Simulate inventory check and reservation
        print(f"Checking inventory for order {order_id}")
        
        # Simulate inventory availability (randomize for demo)
        import random
        inventory_available = random.choice([True, True, True, False])  # 75% success rate
        
        if inventory_available:
            # Emit inventory reserved event
            response = eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'reserved',
                            'reservationId': f"res-{order_id}-{int(datetime.now().timestamp())}",
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory reserved for order {order_id}',
                    'eventId': response['Entries'][0]['EventId']
                })
            }
        else:
            # Emit inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'ecommerce.inventory',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'status': 'unavailable',
                            'reason': 'Insufficient stock',
                            'timestamp': datetime.utcnow().isoformat()
                        }),
                        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
                    }
                ]
            )
            
            return {
                'statusCode': 200,
                'body': json.dumps({
                    'message': f'Inventory unavailable for order {order_id}'
                })
            }
        
    except Exception as e:
        print(f"Error managing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

        function = lambda_.Function(
            self, "InventoryManagerFunction",
            function_name=f"eventbridge-demo-{unique_id}-inventory-manager",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(inventory_manager_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name
            },
            description="Lambda function for managing inventory reservations in event-driven architecture"
        )
        
        return function

    def _create_event_generator_lambda(self, unique_id: str) -> lambda_.Function:
        """
        Create Lambda function to generate sample order events
        
        This function simulates API Gateway or application events that initiate
        order workflows, demonstrating how external systems integrate with EventBridge.
        """
        event_generator_code = '''
import json
import boto3
import os
from datetime import datetime
import random

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    # Generate sample order data
    order_id = f"ord-{int(datetime.now().timestamp())}-{random.randint(1000, 9999)}"
    customer_id = f"cust-{random.randint(1000, 9999)}"
    total_amount = round(random.uniform(25.99, 299.99), 2)
    
    # Create order event
    order_event = {
        'Source': 'ecommerce.api',
        'DetailType': 'Order Created',
        'Detail': json.dumps({
            'orderId': order_id,
            'customerId': customer_id,
            'totalAmount': total_amount,
            'items': [
                {
                    'productId': f'prod-{random.randint(100, 999)}',
                    'quantity': random.randint(1, 3),
                    'price': round(total_amount / random.randint(1, 3), 2)
                }
            ],
            'timestamp': datetime.utcnow().isoformat()
        }),
        'EventBusName': os.environ.get('EVENT_BUS_NAME', 'default')
    }
    
    try:
        response = eventbridge.put_events(Entries=[order_event])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Order event generated successfully',
                'orderId': order_id,
                'eventId': response['Entries'][0]['EventId']
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

        function = lambda_.Function(
            self, "EventGeneratorFunction",
            function_name=f"eventbridge-demo-{unique_id}-event-generator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(event_generator_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name
            },
            description="Lambda function for generating sample order events for testing"
        )
        
        return function

    def _create_payment_processing_queue(self, unique_id: str) -> sqs.Queue:
        """
        Create SQS queue for asynchronous payment processing
        
        SQS provides reliable, asynchronous message processing that decouples
        payment processing from the immediate order flow. The delay ensures
        inventory reservation is committed before payment processing begins.
        """
        queue = sqs.Queue(
            self, "PaymentProcessingQueue",
            queue_name=f"eventbridge-demo-{unique_id}-payment-processing",
            delivery_delay=Duration.seconds(30),
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return queue

    def _create_event_log_group(self, unique_id: str) -> logs.LogGroup:
        """
        Create CloudWatch log group for event monitoring
        
        Comprehensive event monitoring is essential for production event-driven
        systems. This log group captures all e-commerce events for observability,
        debugging, and audit purposes.
        """
        log_group = logs.LogGroup(
            self, "EventLogGroup",
            log_group_name=f"/aws/events/ecommerce-events-{unique_id}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_event_routing_rules(self, unique_id: str) -> None:
        """
        Create EventBridge rules for intelligent event routing
        
        EventBridge rules define the routing logic that connects event producers
        to consumers through pattern matching. These rules enable content-based
        routing where events are delivered based on structure, source, and metadata.
        """
        
        # Rule 1: Route new orders to order processing Lambda
        order_processing_rule = events.Rule(
            self, "OrderProcessingRule",
            rule_name=f"eventbridge-demo-{unique_id}-order-processing-rule",
            event_bus=self.custom_event_bus,
            description="Route new orders to processing Lambda",
            event_pattern=events.EventPattern(
                source=["ecommerce.api"],
                detail_type=["Order Created"],
                detail={
                    "totalAmount": events.Match.exists_check()
                }
            )
        )
        
        order_processing_rule.add_target(
            targets.LambdaFunction(self.order_processor)
        )
        
        # Rule 2: Route processed orders to inventory management
        inventory_check_rule = events.Rule(
            self, "InventoryCheckRule",
            rule_name=f"eventbridge-demo-{unique_id}-inventory-check-rule",
            event_bus=self.custom_event_bus,
            description="Route processed orders to inventory check",
            event_pattern=events.EventPattern(
                source=["ecommerce.order"],
                detail_type=["Order Processed"],
                detail={
                    "status": ["processed"]
                }
            )
        )
        
        inventory_check_rule.add_target(
            targets.LambdaFunction(self.inventory_manager)
        )
        
        # Rule 3: Route inventory reserved events to payment processing
        payment_processing_rule = events.Rule(
            self, "PaymentProcessingRule",
            rule_name=f"eventbridge-demo-{unique_id}-payment-processing-rule",
            event_bus=self.custom_event_bus,
            description="Route inventory reserved events to payment processing",
            event_pattern=events.EventPattern(
                source=["ecommerce.inventory"],
                detail_type=["Inventory Reserved"],
                detail={
                    "status": ["reserved"]
                }
            )
        )
        
        payment_processing_rule.add_target(
            targets.SqsQueue(self.payment_queue)
        )
        
        # Rule 4: Archive all events to CloudWatch Logs for monitoring
        monitoring_rule = events.Rule(
            self, "MonitoringRule",
            rule_name=f"eventbridge-demo-{unique_id}-monitoring-rule",
            event_bus=self.custom_event_bus,
            description="Archive all ecommerce events for monitoring",
            event_pattern=events.EventPattern(
                source=[{"prefix": "ecommerce."}]
            )
        )
        
        monitoring_rule.add_target(
            targets.CloudWatchLogGroup(self.event_log_group)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "CustomEventBusName",
            value=self.custom_event_bus.event_bus_name,
            description="Name of the custom EventBridge event bus",
            export_name=f"{self.stack_name}-EventBusName"
        )
        
        CfnOutput(
            self, "CustomEventBusArn",
            value=self.custom_event_bus.event_bus_arn,
            description="ARN of the custom EventBridge event bus",
            export_name=f"{self.stack_name}-EventBusArn"
        )
        
        CfnOutput(
            self, "OrderProcessorFunctionName",
            value=self.order_processor.function_name,
            description="Name of the order processor Lambda function",
            export_name=f"{self.stack_name}-OrderProcessorFunction"
        )
        
        CfnOutput(
            self, "InventoryManagerFunctionName",
            value=self.inventory_manager.function_name,
            description="Name of the inventory manager Lambda function",
            export_name=f"{self.stack_name}-InventoryManagerFunction"
        )
        
        CfnOutput(
            self, "EventGeneratorFunctionName",
            value=self.event_generator.function_name,
            description="Name of the event generator Lambda function",
            export_name=f"{self.stack_name}-EventGeneratorFunction"
        )
        
        CfnOutput(
            self, "PaymentQueueUrl",
            value=self.payment_queue.queue_url,
            description="URL of the payment processing SQS queue",
            export_name=f"{self.stack_name}-PaymentQueueUrl"
        )
        
        CfnOutput(
            self, "EventLogGroupName",
            value=self.event_log_group.log_group_name,
            description="Name of the CloudWatch log group for event monitoring",
            export_name=f"{self.stack_name}-EventLogGroup"
        )


# CDK App definition
app = cdk.App()

# Stack configuration from context or defaults
stack_name = app.node.try_get_context("stackName") or "EventDrivenArchitectureStack"
env_config = {
    "account": app.node.try_get_context("account"),
    "region": app.node.try_get_context("region")
}

# Create the stack
EventDrivenArchitectureStack(
    app, 
    stack_name,
    env=cdk.Environment(**env_config) if any(env_config.values()) else None,
    description="Event-driven architecture with Amazon EventBridge for e-commerce platform"
)

# Synthesize the CloudFormation template
app.synth()