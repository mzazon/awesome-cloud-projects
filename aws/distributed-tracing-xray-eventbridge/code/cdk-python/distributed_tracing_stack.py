"""
CDK Stack for implementing Distributed Tracing with X-Ray.

This stack creates a complete microservices architecture with:
- EventBridge custom bus for event routing
- Lambda functions with X-Ray tracing enabled
- API Gateway with distributed tracing
- EventBridge rules for event-driven communication
- Proper IAM roles and policies
"""

from typing import Dict, Any
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_lambda as _lambda,
    aws_apigateway as apigateway,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_logs as logs
)
from constructs import Construct


class DistributedTracingStack(Stack):
    """
    CDK Stack for Distributed Tracing with X-Ray.
    
    Creates a complete event-driven microservices architecture with
    comprehensive observability through AWS X-Ray distributed tracing.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create custom EventBridge bus
        self.event_bus = self._create_event_bus()
        
        # Create IAM role for Lambda functions
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda functions for microservices
        self.lambda_functions = self._create_lambda_functions()
        
        # Create API Gateway with X-Ray tracing
        self.api_gateway = self._create_api_gateway()
        
        # Create EventBridge rules and targets
        self._create_eventbridge_rules()
        
        # Output important values
        self._create_outputs()

    def _create_event_bus(self) -> events.EventBus:
        """Create custom EventBridge bus for event routing."""
        event_bus = events.EventBus(
            self, "DistributedTracingBus",
            event_bus_name="distributed-tracing-bus",
            description="Custom event bus for distributed tracing demo"
        )
        
        return event_bus

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions with required permissions."""
        role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for distributed tracing Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSXRayDaemonWriteAccess"
                )
            ]
        )
        
        # Add EventBridge permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "events:PutEvents"
                ],
                resources=[self.event_bus.event_bus_arn]
            )
        )
        
        return role

    def _create_lambda_functions(self) -> Dict[str, _lambda.Function]:
        """Create Lambda functions for each microservice."""
        functions = {}
        
        # Order Service Function
        functions['order'] = _lambda.Function(
            self, "OrderService",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="order_service.lambda_handler",
            code=_lambda.Code.from_inline(self._get_order_service_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            tracing=_lambda.Tracing.ACTIVE,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Order service for distributed tracing demo"
        )
        
        # Payment Service Function
        functions['payment'] = _lambda.Function(
            self, "PaymentService",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="payment_service.lambda_handler",
            code=_lambda.Code.from_inline(self._get_payment_service_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            tracing=_lambda.Tracing.ACTIVE,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Payment service for distributed tracing demo"
        )
        
        # Inventory Service Function
        functions['inventory'] = _lambda.Function(
            self, "InventoryService",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="inventory_service.lambda_handler",
            code=_lambda.Code.from_inline(self._get_inventory_service_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            tracing=_lambda.Tracing.ACTIVE,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Inventory service for distributed tracing demo"
        )
        
        # Notification Service Function
        functions['notification'] = _lambda.Function(
            self, "NotificationService",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="notification_service.lambda_handler",
            code=_lambda.Code.from_inline(self._get_notification_service_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            tracing=_lambda.Tracing.ACTIVE,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Notification service for distributed tracing demo"
        )
        
        return functions

    def _create_api_gateway(self) -> apigateway.RestApi:
        """Create API Gateway with X-Ray tracing enabled."""
        api = apigateway.RestApi(
            self, "DistributedTracingAPI",
            rest_api_name="distributed-tracing-api",
            description="API Gateway for distributed tracing demo",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                tracing_enabled=True,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )
        
        # Create /orders/{customerId} resource
        orders_resource = api.root.add_resource("orders")
        customer_resource = orders_resource.add_resource("{customerId}")
        
        # Create Lambda integration for order service
        order_integration = apigateway.LambdaIntegration(
            self.lambda_functions['order'],
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )
        
        # Add POST method
        customer_resource.add_method(
            "POST",
            order_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )
        
        return api

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules and targets for event routing."""
        
        # Rule for payment processing (triggered by order creation)
        payment_rule = events.Rule(
            self, "PaymentProcessingRule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["order.service"],
                detail_type=["Order Created"]
            ),
            description="Route order creation events to payment service"
        )
        payment_rule.add_target(targets.LambdaFunction(self.lambda_functions['payment']))
        
        # Rule for inventory updates (triggered by order creation)
        inventory_rule = events.Rule(
            self, "InventoryUpdateRule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["order.service"],
                detail_type=["Order Created"]
            ),
            description="Route order creation events to inventory service"
        )
        inventory_rule.add_target(targets.LambdaFunction(self.lambda_functions['inventory']))
        
        # Rule for notifications (triggered by payment and inventory events)
        notification_rule = events.Rule(
            self, "NotificationRule",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["payment.service", "inventory.service"],
                detail_type=["Payment Processed", "Inventory Updated"]
            ),
            description="Route completion events to notification service"
        )
        notification_rule.add_target(targets.LambdaFunction(self.lambda_functions['notification']))

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "APIGatewayURL",
            value=self.api_gateway.url,
            description="API Gateway endpoint URL"
        )
        
        CfnOutput(
            self, "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Custom EventBridge bus name"
        )
        
        CfnOutput(
            self, "EventBusArn",
            value=self.event_bus.event_bus_arn,
            description="Custom EventBridge bus ARN"
        )
        
        CfnOutput(
            self, "XRayServiceMapURL",
            value=f"https://console.aws.amazon.com/xray/home?region={self.region}#/service-map",
            description="X-Ray service map console URL"
        )

    def _get_order_service_code(self) -> str:
        """Return the order service Lambda function code."""
        return '''
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all
from datetime import datetime

# Patch AWS SDK calls for X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('order_service_handler')
def lambda_handler(event, context):
    # Extract trace context from API Gateway
    trace_header = event.get('headers', {}).get('X-Amzn-Trace-Id')
    
    # Create subsegment for order processing
    subsegment = xray_recorder.begin_subsegment('process_order')
    
    try:
        # Simulate order processing
        order_id = f"order-{datetime.now().strftime('%Y%m%d%H%M%S')}"
        customer_id = event.get('pathParameters', {}).get('customerId', 'anonymous')
        
        # Add metadata to trace
        subsegment.put_metadata('order_details', {
            'order_id': order_id,
            'customer_id': customer_id,
            'timestamp': datetime.now().isoformat()
        })
        
        # Publish event to EventBridge with trace context
        event_detail = {
            'orderId': order_id,
            'customerId': customer_id,
            'amount': 99.99,
            'status': 'created'
        }
        
        response = eventbridge.put_events(
            Entries=[
                {
                    'Source': 'order.service',
                    'DetailType': 'Order Created',
                    'Detail': json.dumps(event_detail),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        
        # Add annotation for filtering
        xray_recorder.put_annotation('order_id', order_id)
        xray_recorder.put_annotation('service_name', 'order-service')
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'X-Amzn-Trace-Id': trace_header
            },
            'body': json.dumps({
                'orderId': order_id,
                'status': 'created',
                'message': 'Order created successfully'
            })
        }
        
    except Exception as e:
        xray_recorder.put_annotation('error', str(e))
        raise e
    finally:
        xray_recorder.end_subsegment()
'''

    def _get_payment_service_code(self) -> str:
        """Return the payment service Lambda function code."""
        return '''
import json
import boto3
import os
import time
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('payment_service_handler')
def lambda_handler(event, context):
    # Process EventBridge event
    for record in event['Records']:
        detail = json.loads(record['body'])
        
        # Create subsegment for payment processing
        subsegment = xray_recorder.begin_subsegment('process_payment')
        
        try:
            order_id = detail['detail']['orderId']
            amount = detail['detail']['amount']
            
            # Add metadata to trace
            subsegment.put_metadata('payment_details', {
                'order_id': order_id,
                'amount': amount,
                'processor': 'stripe'
            })
            
            # Simulate payment processing delay
            time.sleep(0.5)
            
            # Publish payment processed event
            payment_event = {
                'orderId': order_id,
                'amount': amount,
                'paymentId': f"pay-{order_id}",
                'status': 'processed'
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'payment.service',
                        'DetailType': 'Payment Processed',
                        'Detail': json.dumps(payment_event),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
            
            # Add annotations for filtering
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'payment-service')
            xray_recorder.put_annotation('payment_amount', amount)
            
        except Exception as e:
            xray_recorder.put_annotation('error', str(e))
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200}
'''

    def _get_inventory_service_code(self) -> str:
        """Return the inventory service Lambda function code."""
        return '''
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for X-Ray tracing
patch_all()

eventbridge = boto3.client('events')

@xray_recorder.capture('inventory_service_handler')
def lambda_handler(event, context):
    for record in event['Records']:
        detail = json.loads(record['body'])
        
        subsegment = xray_recorder.begin_subsegment('update_inventory')
        
        try:
            order_id = detail['detail']['orderId']
            
            # Add metadata to trace
            subsegment.put_metadata('inventory_update', {
                'order_id': order_id,
                'items_reserved': 1,
                'warehouse': 'east-coast'
            })
            
            # Publish inventory updated event
            inventory_event = {
                'orderId': order_id,
                'status': 'reserved',
                'warehouse': 'east-coast'
            }
            
            eventbridge.put_events(
                Entries=[
                    {
                        'Source': 'inventory.service',
                        'DetailType': 'Inventory Updated',
                        'Detail': json.dumps(inventory_event),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }
                ]
            )
            
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'inventory-service')
            
        except Exception as e:
            xray_recorder.put_annotation('error', str(e))
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200}
'''

    def _get_notification_service_code(self) -> str:
        """Return the notification service Lambda function code."""
        return '''
import json
import boto3
import os
from aws_xray_sdk.core import xray_recorder
from aws_xray_sdk.core import patch_all

# Patch AWS SDK calls for X-Ray tracing
patch_all()

@xray_recorder.capture('notification_service_handler')
def lambda_handler(event, context):
    for record in event['Records']:
        detail = json.loads(record['body'])
        
        subsegment = xray_recorder.begin_subsegment('send_notification')
        
        try:
            order_id = detail['detail']['orderId']
            event_type = detail['detail-type']
            
            # Add metadata to trace
            subsegment.put_metadata('notification_sent', {
                'order_id': order_id,
                'event_type': event_type,
                'channel': 'email'
            })
            
            xray_recorder.put_annotation('order_id', order_id)
            xray_recorder.put_annotation('service_name', 'notification-service')
            xray_recorder.put_annotation('notification_type', event_type)
            
        except Exception as e:
            xray_recorder.put_annotation('error', str(e))
            raise e
        finally:
            xray_recorder.end_subsegment()

    return {'statusCode': 200}
'''