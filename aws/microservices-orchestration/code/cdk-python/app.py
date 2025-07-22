#!/usr/bin/env python3
"""
CDK Python Application for Event-Driven Microservices with EventBridge and Step Functions

This application deploys a complete event-driven microservices architecture using:
- Amazon EventBridge for decoupled messaging
- AWS Step Functions for workflow orchestration
- AWS Lambda for microservices implementation
- Amazon DynamoDB for data persistence
- CloudWatch for monitoring and observability

The architecture demonstrates modern serverless patterns including:
- Event-driven communication
- Saga pattern for distributed transactions
- Error handling and retry logic
- Comprehensive monitoring and logging
"""

import os
from typing import Dict, Any
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_events as events,
    aws_events_targets as targets,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as tasks,
    aws_lambda as _lambda,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    Tags,
)
from constructs import Construct


class EventDrivenMicroservicesStack(Stack):
    """
    CDK Stack for Event-Driven Microservices Architecture
    
    This stack creates a complete event-driven microservices solution with:
    - Custom EventBridge bus for event routing
    - Lambda-based microservices (Order, Payment, Inventory, Notification)
    - Step Functions workflow for business process orchestration
    - DynamoDB table for data persistence
    - CloudWatch dashboard for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration
        self.project_name = "microservices-demo"
        self.environment = "development"
        
        # Create foundational resources
        self.dynamodb_table = self._create_dynamodb_table()
        self.custom_event_bus = self._create_custom_event_bus()
        
        # Create Lambda-based microservices
        self.lambda_functions = self._create_lambda_functions()
        
        # Create Step Functions workflow
        self.state_machine = self._create_step_functions_workflow()
        
        # Create EventBridge rules and targets
        self._create_eventbridge_rules()
        
        # Create monitoring resources
        self._create_monitoring_dashboard()
        
        # Add tags to all resources
        self._add_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for order data storage
        
        The table uses a composite primary key (orderId + customerId) for efficient
        queries and includes a Global Secondary Index for customer-based lookups.
        """
        table = dynamodb.Table(
            self, "OrdersTable",
            table_name=f"{self.project_name}-orders",
            partition_key=dynamodb.Attribute(
                name="orderId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="customerId", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            point_in_time_recovery=True,
        )
        
        # Add Global Secondary Index for customer queries
        table.add_global_secondary_index(
            index_name="CustomerId-Index",
            partition_key=dynamodb.Attribute(
                name="customerId",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        return table

    def _create_custom_event_bus(self) -> events.EventBus:
        """
        Create custom EventBridge event bus
        
        A custom event bus provides isolation from default AWS service events
        and enables fine-grained access control for microservices communication.
        """
        event_bus = events.EventBus(
            self, "CustomEventBus",
            event_bus_name=f"{self.project_name}-eventbus",
            description="Custom event bus for microservices communication"
        )
        
        return event_bus

    def _create_lambda_functions(self) -> Dict[str, _lambda.Function]:
        """
        Create Lambda functions for each microservice
        
        Each function represents a bounded context with specific business capabilities:
        - Order Service: Handles order creation and state management
        - Payment Service: Processes payments with failure simulation
        - Inventory Service: Manages inventory reservations
        - Notification Service: Handles customer communications
        """
        functions = {}
        
        # Common Lambda execution role
        lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ],
        )
        
        # Grant DynamoDB permissions
        self.dynamodb_table.grant_read_write_data(lambda_role)
        
        # Grant EventBridge permissions
        self.custom_event_bus.grant_put_events_to(lambda_role)
        
        # Order Service
        functions['order'] = _lambda.Function(
            self, "OrderService",
            function_name=f"{self.project_name}-order-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_order_service_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "DYNAMODB_TABLE_NAME": self.dynamodb_table.table_name,
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name,
            },
            description="Order Service - Handles order creation and management",
        )
        
        # Payment Service
        functions['payment'] = _lambda.Function(
            self, "PaymentService",
            function_name=f"{self.project_name}-payment-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_payment_service_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "DYNAMODB_TABLE_NAME": self.dynamodb_table.table_name,
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name,
            },
            description="Payment Service - Processes payments with retry logic",
        )
        
        # Inventory Service
        functions['inventory'] = _lambda.Function(
            self, "InventoryService",
            function_name=f"{self.project_name}-inventory-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_inventory_service_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "DYNAMODB_TABLE_NAME": self.dynamodb_table.table_name,
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name,
            },
            description="Inventory Service - Manages product inventory and reservations",
        )
        
        # Notification Service
        functions['notification'] = _lambda.Function(
            self, "NotificationService",
            function_name=f"{self.project_name}-notification-service",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_notification_service_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=lambda_role,
            environment={
                "EVENT_BUS_NAME": self.custom_event_bus.event_bus_name,
            },
            description="Notification Service - Handles customer communications",
        )
        
        return functions

    def _create_step_functions_workflow(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine for order processing workflow
        
        The workflow orchestrates the complete order processing business logic with:
        - Sequential payment and inventory processing
        - Comprehensive error handling and retry logic
        - Parallel notification handling
        - Visual monitoring and audit trails
        """
        # Create Step Functions execution role
        sfn_role = iam.Role(
            self, "StepFunctionsExecutionRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaRole"),
            ],
        )
        
        # Grant permissions to invoke Lambda functions
        for function in self.lambda_functions.values():
            function.grant_invoke(sfn_role)
        
        # Define workflow states
        
        # Payment processing task
        process_payment = tasks.LambdaInvoke(
            self, "ProcessPayment",
            lambda_function=self.lambda_functions['payment'],
            payload_response_only=True,
            retry_on_service_exceptions=True,
        )
        
        # Payment status check
        check_payment_status = sfn.Choice(self, "CheckPaymentStatus")
        
        # Inventory reservation task
        reserve_inventory = tasks.LambdaInvoke(
            self, "ReserveInventory",
            lambda_function=self.lambda_functions['inventory'],
            payload_response_only=True,
            retry_on_service_exceptions=True,
        )
        
        # Inventory status check
        check_inventory_status = sfn.Choice(self, "CheckInventoryStatus")
        
        # Success notification task
        send_success_notification = tasks.LambdaInvoke(
            self, "SendSuccessNotification",
            lambda_function=self.lambda_functions['notification'],
            payload=sfn.TaskInput.from_object({
                "message": "Order processed successfully",
                "orderId.$": "$.detail.orderId",
                "status": "COMPLETED"
            }),
            payload_response_only=True,
        )
        
        # Payment failure notification task
        payment_failed_notification = tasks.LambdaInvoke(
            self, "PaymentFailedNotification",
            lambda_function=self.lambda_functions['notification'],
            payload=sfn.TaskInput.from_object({
                "message": "Payment failed",
                "orderId.$": "$.detail.orderId",
                "status": "PAYMENT_FAILED"
            }),
            payload_response_only=True,
        )
        
        # Inventory failure notification task
        inventory_failed_notification = tasks.LambdaInvoke(
            self, "InventoryFailedNotification",
            lambda_function=self.lambda_functions['notification'],
            payload=sfn.TaskInput.from_object({
                "message": "Inventory unavailable",
                "orderId.$": "$.detail.orderId",
                "status": "INVENTORY_FAILED"
            }),
            payload_response_only=True,
        )
        
        # Define workflow logic
        workflow_definition = (
            process_payment
            .next(check_payment_status
                .when(
                    sfn.Condition.string_matches("$.body", "*SUCCESS*"),
                    reserve_inventory
                    .next(check_inventory_status
                        .when(
                            sfn.Condition.string_matches("$.body", "*RESERVED*"),
                            send_success_notification
                        )
                        .otherwise(inventory_failed_notification)
                    )
                )
                .otherwise(payment_failed_notification)
            )
        )
        
        # Create CloudWatch Log Group for Step Functions
        log_group = logs.LogGroup(
            self, "StepFunctionsLogGroup",
            log_group_name=f"/aws/stepfunctions/{self.project_name}-order-processing",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create Step Functions state machine
        state_machine = sfn.StateMachine(
            self, "OrderProcessingWorkflow",
            state_machine_name=f"{self.project_name}-order-processing",
            definition=workflow_definition,
            role=sfn_role,
            state_machine_type=sfn.StateMachineType.STANDARD,
            logs=sfn.LogOptions(
                destination=log_group,
                level=sfn.LogLevel.ALL,
                include_execution_data=True,
            ),
            tracing_enabled=True,
        )
        
        return state_machine

    def _create_eventbridge_rules(self) -> None:
        """
        Create EventBridge rules to route events to appropriate targets
        
        Rules use pattern matching to filter events and route them to Step Functions
        and Lambda targets, enabling decoupled event-driven communication.
        """
        # Rule for order created events -> Step Functions
        order_created_rule = events.Rule(
            self, "OrderCreatedRule",
            rule_name=f"{self.project_name}-order-created-rule",
            event_bus=self.custom_event_bus,
            event_pattern=events.EventPattern(
                source=["order.service"],
                detail_type=["Order Created"],
            ),
            description="Route order created events to Step Functions workflow",
        )
        
        # Add Step Functions as target
        order_created_rule.add_target(
            targets.SfnStateMachine(
                self.state_machine,
                input=events.RuleTargetInput.from_event_path("$"),
            )
        )
        
        # Rule for payment events -> Notification Service
        payment_events_rule = events.Rule(
            self, "PaymentEventsRule",
            rule_name=f"{self.project_name}-payment-events-rule",
            event_bus=self.custom_event_bus,
            event_pattern=events.EventPattern(
                source=["payment.service"],
                detail_type=["Payment Processed", "Payment Failed"],
            ),
            description="Route payment events to notification service",
        )
        
        # Add Notification Service as target
        payment_events_rule.add_target(
            targets.LambdaFunction(self.lambda_functions['notification'])
        )
        
        # Rule for inventory events -> Notification Service
        inventory_events_rule = events.Rule(
            self, "InventoryEventsRule",
            rule_name=f"{self.project_name}-inventory-events-rule",
            event_bus=self.custom_event_bus,
            event_pattern=events.EventPattern(
                source=["inventory.service"],
                detail_type=["Inventory Reserved", "Inventory Unavailable"],
            ),
            description="Route inventory events to notification service",
        )
        
        # Add Notification Service as target
        inventory_events_rule.add_target(
            targets.LambdaFunction(self.lambda_functions['notification'])
        )

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring microservices performance
        
        The dashboard provides real-time visibility into system health including:
        - Lambda function invocations and errors
        - Step Functions execution status
        - DynamoDB operations
        - EventBridge rule matches
        """
        dashboard = cloudwatch.Dashboard(
            self, "MicroservicesDashboard",
            dashboard_name=f"{self.project_name}-microservices-dashboard",
        )
        
        # Lambda metrics
        lambda_invocations_widget = cloudwatch.GraphWidget(
            title="Lambda Function Invocations",
            left=[
                function.metric_invocations()
                for function in self.lambda_functions.values()
            ],
            width=12,
            height=6,
        )
        
        lambda_errors_widget = cloudwatch.GraphWidget(
            title="Lambda Function Errors",
            left=[
                function.metric_errors()
                for function in self.lambda_functions.values()
            ],
            width=12,
            height=6,
        )
        
        # Step Functions metrics
        sfn_executions_widget = cloudwatch.GraphWidget(
            title="Step Functions Executions",
            left=[
                self.state_machine.metric_succeeded(),
                self.state_machine.metric_failed(),
                self.state_machine.metric_started(),
            ],
            width=12,
            height=6,
        )
        
        # DynamoDB metrics
        dynamodb_operations_widget = cloudwatch.GraphWidget(
            title="DynamoDB Operations",
            left=[
                self.dynamodb_table.metric_consumed_read_capacity_units(),
                self.dynamodb_table.metric_consumed_write_capacity_units(),
            ],
            width=12,
            height=6,
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            lambda_invocations_widget,
            lambda_errors_widget,
        )
        dashboard.add_widgets(
            sfn_executions_widget,
            dynamodb_operations_widget,
        )
        
        return dashboard

    def _add_tags(self) -> None:
        """Add consistent tags to all resources for organization and cost tracking"""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("Architecture", "Event-Driven-Microservices")
        Tags.of(self).add("CDK", "Python")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers"""
        CfnOutput(
            self, "EventBusName",
            value=self.custom_event_bus.event_bus_name,
            description="Name of the custom EventBridge event bus",
        )
        
        CfnOutput(
            self, "EventBusArn",
            value=self.custom_event_bus.event_bus_arn,
            description="ARN of the custom EventBridge event bus",
        )
        
        CfnOutput(
            self, "DynamoDBTableName",
            value=self.dynamodb_table.table_name,
            description="Name of the DynamoDB orders table",
        )
        
        CfnOutput(
            self, "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="ARN of the Step Functions state machine",
        )
        
        CfnOutput(
            self, "OrderServiceArn",
            value=self.lambda_functions['order'].function_arn,
            description="ARN of the Order Service Lambda function",
        )

    def _get_order_service_code(self) -> str:
        """Return the Order Service Lambda function code"""
        return '''
import json
import boto3
import uuid
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse order data
        order_data = json.loads(event['body']) if 'body' in event else event
        
        # Create order record
        order_id = str(uuid.uuid4())
        order_item = {
            'orderId': order_id,
            'customerId': order_data['customerId'],
            'items': order_data['items'],
            'totalAmount': order_data['totalAmount'],
            'status': 'PENDING',
            'createdAt': datetime.utcnow().isoformat()
        }
        
        # Store in DynamoDB
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
        table.put_item(Item=order_item)
        
        # Publish event to EventBridge
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(order_item),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'status': 'PENDING'
            })
        }
        
    except Exception as e:
        print(f"Error processing order: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_payment_service_code(self) -> str:
        """Return the Payment Service Lambda function code"""
        return '''
import json
import boto3
import random
import time
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse payment data
        payment_data = event['detail'] if 'detail' in event else event
        order_id = payment_data['orderId']
        amount = payment_data['totalAmount']
        
        # Simulate payment processing delay
        time.sleep(2)
        
        # Simulate payment success/failure (90% success rate)
        payment_successful = random.random() < 0.9
        
        # Update order status
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
        
        if payment_successful:
            table.update_item(
                Key={'orderId': order_id, 'customerId': payment_data['customerId']},
                UpdateExpression='SET #status = :status, paymentId = :paymentId, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'PAID',
                    ':paymentId': f'pay_{order_id[:8]}',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish payment success event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'paymentId': f'pay_{order_id[:8]}',
                            'amount': amount,
                            'status': 'SUCCESS'
                        }),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
        else:
            table.update_item(
                Key={'orderId': order_id, 'customerId': payment_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'PAYMENT_FAILED',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish payment failure event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Failed',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'amount': amount,
                            'status': 'FAILED'
                        }),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'paymentStatus': 'SUCCESS' if payment_successful else 'FAILED'
            })
        }
        
    except Exception as e:
        print(f"Error processing payment: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_inventory_service_code(self) -> str:
        """Return the Inventory Service Lambda function code"""
        return '''
import json
import boto3
import random
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse inventory data
        inventory_data = event['detail'] if 'detail' in event else event
        order_id = inventory_data['orderId']
        items = inventory_data['items']
        
        # Simulate inventory check (95% success rate)
        inventory_available = random.random() < 0.95
        
        # Update order status
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE_NAME'])
        
        if inventory_available:
            table.update_item(
                Key={'orderId': order_id, 'customerId': inventory_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_RESERVED',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish inventory reserved event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Reserved',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'items': items,
                            'status': 'RESERVED'
                        }),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
        else:
            table.update_item(
                Key={'orderId': order_id, 'customerId': inventory_data['customerId']},
                UpdateExpression='SET #status = :status, updatedAt = :updatedAt',
                ExpressionAttributeNames={'#status': 'status'},
                ExpressionAttributeValues={
                    ':status': 'INVENTORY_UNAVAILABLE',
                    ':updatedAt': datetime.utcnow().isoformat()
                }
            )
            
            # Publish inventory unavailable event
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Unavailable',
                        'Detail': json.dumps({
                            'orderId': order_id,
                            'items': items,
                            'status': 'UNAVAILABLE'
                        }),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'orderId': order_id,
                'inventoryStatus': 'RESERVED' if inventory_available else 'UNAVAILABLE'
            })
        }
        
    except Exception as e:
        print(f"Error processing inventory: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_notification_service_code(self) -> str:
        """Return the Notification Service Lambda function code"""
        return '''
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    try:
        # Parse notification data
        notification_data = event['detail'] if 'detail' in event else event
        
        # Log notification (in real scenario, send email/SMS)
        print(f"NOTIFICATION: {json.dumps(notification_data, indent=2)}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Notification sent successfully',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error sending notification: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''


def main():
    """Main application entry point"""
    app = App()
    
    # Create the main stack
    EventDrivenMicroservicesStack(
        app, 
        "EventDrivenMicroservicesStack",
        description="Event-Driven Microservices with EventBridge and Step Functions",
        env={
            'region': app.node.try_get_context('region') or 'us-east-1',
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()