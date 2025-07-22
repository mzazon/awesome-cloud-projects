#!/usr/bin/env python3
"""
CQRS Event Sourcing with EventBridge and DynamoDB
AWS CDK Python Application

This CDK application implements a complete CQRS (Command Query Responsibility Segregation)
and Event Sourcing architecture using Amazon EventBridge and DynamoDB.

Author: AWS Recipe Generator
Version: 1.0
"""

import os
from typing import Dict, Any
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_dynamodb as dynamodb,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct


class CqrsEventSourcingStack(Stack):
    """
    CDK Stack implementing CQRS and Event Sourcing architecture.
    
    This stack creates:
    - Event Store (DynamoDB table with streams)
    - Read Model tables (User profiles, Order summaries)
    - Custom EventBridge bus
    - Lambda functions for command handling, stream processing, and projections
    - IAM roles with least privilege access
    - EventBridge rules for event routing
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.project_name = "cqrs-demo"
        
        # Create DynamoDB tables
        self._create_event_store()
        self._create_read_model_tables()
        
        # Create EventBridge infrastructure
        self._create_event_bus()
        
        # Create IAM roles
        self._create_iam_roles()
        
        # Create Lambda functions
        self._create_lambda_functions()
        
        # Create EventBridge rules and targets
        self._create_event_rules()
        
        # Create outputs
        self._create_outputs()

    def _create_event_store(self) -> None:
        """Create the Event Store DynamoDB table with streams enabled."""
        self.event_store_table = dynamodb.Table(
            self,
            "EventStoreTable",
            table_name=f"{self.project_name}-event-store",
            partition_key=dynamodb.Attribute(
                name="AggregateId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Version",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=10,
            write_capacity=10,
            stream=dynamodb.StreamViewType.NEW_IMAGE,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )
        
        # Add Global Secondary Index for event type and timestamp queries
        self.event_store_table.add_global_secondary_index(
            index_name="EventType-Timestamp-index",
            partition_key=dynamodb.Attribute(
                name="EventType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )

    def _create_read_model_tables(self) -> None:
        """Create read model tables for CQRS query operations."""
        # User profiles read model
        self.user_read_model_table = dynamodb.Table(
            self,
            "UserReadModelTable",
            table_name=f"{self.project_name}-user-profiles",
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add GSI for email lookup
        self.user_read_model_table.add_global_secondary_index(
            index_name="Email-index",
            partition_key=dynamodb.Attribute(
                name="Email",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        # Order summaries read model
        self.order_read_model_table = dynamodb.Table(
            self,
            "OrderReadModelTable",
            table_name=f"{self.project_name}-order-summaries",
            partition_key=dynamodb.Attribute(
                name="OrderId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add GSI for user-based queries
        self.order_read_model_table.add_global_secondary_index(
            index_name="UserId-index",
            partition_key=dynamodb.Attribute(
                name="UserId",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        # Add GSI for status-based queries
        self.order_read_model_table.add_global_secondary_index(
            index_name="Status-index",
            partition_key=dynamodb.Attribute(
                name="Status",
                type=dynamodb.AttributeType.STRING
            ),
            read_capacity=5,
            write_capacity=5,
            projection_type=dynamodb.ProjectionType.ALL,
        )

    def _create_event_bus(self) -> None:
        """Create custom EventBridge bus for domain events."""
        self.event_bus = events.EventBus(
            self,
            "CustomEventBus",
            event_bus_name=f"{self.project_name}-events",
        )
        
        # Create event archive for replay capabilities
        self.event_archive = events.Archive(
            self,
            "EventArchive",
            archive_name=f"{self.project_name}-events-archive",
            event_pattern=events.EventPattern(
                source=["cqrs.demo"]
            ),
            source_event_bus=self.event_bus,
            retention=Duration.days(30),
            description="Archive for CQRS event sourcing demo - enables event replay"
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles with least privilege access for Lambda functions."""
        # Command handler role - can only write to event store
        self.command_role = iam.Role(
            self,
            "CommandHandlerRole",
            role_name=f"{self.project_name}-command-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add DynamoDB permissions for event store
        self.event_store_table.grant_read_write_data(self.command_role)
        
        # Add EventBridge publish permissions
        self.event_bus.grant_put_events_to(self.command_role)
        
        # Projection handler role - can only read events and write to read models
        self.projection_role = iam.Role(
            self,
            "ProjectionHandlerRole",
            role_name=f"{self.project_name}-projection-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add DynamoDB permissions for read models
        self.user_read_model_table.grant_read_write_data(self.projection_role)
        self.order_read_model_table.grant_read_write_data(self.projection_role)

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for command handling and projections."""
        # Common Lambda configuration
        lambda_runtime = lambda_.Runtime.PYTHON_3_9
        lambda_timeout = Duration.seconds(30)
        
        # Command handler Lambda
        self.command_handler = lambda_.Function(
            self,
            "CommandHandler",
            function_name=f"{self.project_name}-command-handler",
            runtime=lambda_runtime,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_command_handler_code()),
            timeout=lambda_timeout,
            role=self.command_role,
            environment={
                "EVENT_STORE_TABLE": self.event_store_table.table_name,
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Stream processor Lambda
        self.stream_processor = lambda_.Function(
            self,
            "StreamProcessor",
            function_name=f"{self.project_name}-stream-processor",
            runtime=lambda_runtime,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_stream_processor_code()),
            timeout=Duration.seconds(60),
            role=self.command_role,
            environment={
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Add DynamoDB stream as event source
        self.stream_processor.add_event_source(
            lambda_event_sources.DynamoEventSource(
                table=self.event_store_table,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=10,
                retry_attempts=3,
            )
        )
        
        # User projection handler Lambda
        self.user_projection = lambda_.Function(
            self,
            "UserProjection",
            function_name=f"{self.project_name}-user-projection",
            runtime=lambda_runtime,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_user_projection_code()),
            timeout=lambda_timeout,
            role=self.projection_role,
            environment={
                "USER_READ_MODEL_TABLE": self.user_read_model_table.table_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Order projection handler Lambda
        self.order_projection = lambda_.Function(
            self,
            "OrderProjection",
            function_name=f"{self.project_name}-order-projection",
            runtime=lambda_runtime,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_order_projection_code()),
            timeout=lambda_timeout,
            role=self.projection_role,
            environment={
                "ORDER_READ_MODEL_TABLE": self.order_read_model_table.table_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )
        
        # Query handler Lambda
        self.query_handler = lambda_.Function(
            self,
            "QueryHandler",
            function_name=f"{self.project_name}-query-handler",
            runtime=lambda_runtime,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_query_handler_code()),
            timeout=lambda_timeout,
            role=self.projection_role,
            environment={
                "USER_READ_MODEL_TABLE": self.user_read_model_table.table_name,
                "ORDER_READ_MODEL_TABLE": self.order_read_model_table.table_name,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

    def _create_event_rules(self) -> None:
        """Create EventBridge rules for routing events to projection handlers."""
        # Rule for user events
        self.user_events_rule = events.Rule(
            self,
            "UserEventsRule",
            rule_name=f"{self.project_name}-user-events",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["cqrs.demo"],
                detail_type=["UserCreated", "UserProfileUpdated"]
            ),
        )
        
        # Add user projection as target
        self.user_events_rule.add_target(
            targets.LambdaFunction(self.user_projection)
        )
        
        # Rule for order events
        self.order_events_rule = events.Rule(
            self,
            "OrderEventsRule",
            rule_name=f"{self.project_name}-order-events",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["cqrs.demo"],
                detail_type=["OrderCreated", "OrderStatusUpdated"]
            ),
        )
        
        # Add order projection as target
        self.order_events_rule.add_target(
            targets.LambdaFunction(self.order_projection)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "EventStoreTableName",
            value=self.event_store_table.table_name,
            description="Name of the Event Store DynamoDB table",
        )
        
        CfnOutput(
            self,
            "UserReadModelTableName",
            value=self.user_read_model_table.table_name,
            description="Name of the User Read Model DynamoDB table",
        )
        
        CfnOutput(
            self,
            "OrderReadModelTableName",
            value=self.order_read_model_table.table_name,
            description="Name of the Order Read Model DynamoDB table",
        )
        
        CfnOutput(
            self,
            "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Name of the custom EventBridge bus",
        )
        
        CfnOutput(
            self,
            "CommandHandlerFunctionName",
            value=self.command_handler.function_name,
            description="Name of the command handler Lambda function",
        )
        
        CfnOutput(
            self,
            "QueryHandlerFunctionName",
            value=self.query_handler.function_name,
            description="Name of the query handler Lambda function",
        )

    def _get_command_handler_code(self) -> str:
        """Return the command handler Lambda function code."""
        return '''
import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        # Parse command from API Gateway or direct invocation
        command = json.loads(event['body']) if 'body' in event else event
        
        # Command validation
        command_type = command.get('commandType')
        aggregate_id = command.get('aggregateId', str(uuid.uuid4()))
        
        if not command_type:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'commandType is required'})
            }
        
        # Get current version for optimistic concurrency
        table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
        
        # Query existing events for this aggregate
        response = table.query(
            KeyConditionExpression='AggregateId = :id',
            ExpressionAttributeValues={':id': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        current_version = 0
        if response['Items']:
            current_version = int(response['Items'][0]['Version'])
        
        # Create domain event
        event_id = str(uuid.uuid4())
        new_version = current_version + 1
        timestamp = datetime.utcnow().isoformat()
        
        # Event payload based on command type
        event_data = create_event_from_command(command_type, command, aggregate_id)
        
        # Store event in event store
        table.put_item(
            Item={
                'AggregateId': aggregate_id,
                'Version': new_version,
                'EventId': event_id,
                'EventType': event_data['eventType'],
                'Timestamp': timestamp,
                'EventData': event_data['data'],
                'CommandId': command.get('commandId', str(uuid.uuid4())),
                'CorrelationId': command.get('correlationId', str(uuid.uuid4()))
            },
            ConditionExpression='attribute_not_exists(AggregateId) AND attribute_not_exists(Version)'
        )
        
        return {
            'statusCode': 201,
            'body': json.dumps({
                'aggregateId': aggregate_id,
                'version': new_version,
                'eventId': event_id
            })
        }
        
    except Exception as e:
        print(f"Error processing command: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }

def create_event_from_command(command_type, command, aggregate_id):
    """Transform commands into domain events"""
    
    if command_type == 'CreateUser':
        return {
            'eventType': 'UserCreated',
            'data': {
                'userId': aggregate_id,
                'email': command['email'],
                'name': command['name'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateUserProfile':
        return {
            'eventType': 'UserProfileUpdated',
            'data': {
                'userId': aggregate_id,
                'changes': command['changes'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'CreateOrder':
        return {
            'eventType': 'OrderCreated',
            'data': {
                'orderId': aggregate_id,
                'userId': command['userId'],
                'items': command['items'],
                'totalAmount': command['totalAmount'],
                'createdAt': datetime.utcnow().isoformat()
            }
        }
    
    elif command_type == 'UpdateOrderStatus':
        return {
            'eventType': 'OrderStatusUpdated',
            'data': {
                'orderId': aggregate_id,
                'status': command['status'],
                'updatedAt': datetime.utcnow().isoformat()
            }
        }
    
    else:
        raise ValueError(f"Unknown command type: {command_type}")
'''

    def _get_stream_processor_code(self) -> str:
        """Return the stream processor Lambda function code."""
        return '''
import json
import boto3
import os
from decimal import Decimal

eventbridge = boto3.client('events')

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            if record['eventName'] in ['INSERT']:
                # Extract event from DynamoDB stream
                dynamodb_event = record['dynamodb']['NewImage']
                
                # Convert DynamoDB format to normal format
                domain_event = {
                    'EventId': dynamodb_event['EventId']['S'],
                    'AggregateId': dynamodb_event['AggregateId']['S'],
                    'EventType': dynamodb_event['EventType']['S'],
                    'Version': int(dynamodb_event['Version']['N']),
                    'Timestamp': dynamodb_event['Timestamp']['S'],
                    'EventData': deserialize_dynamodb_item(dynamodb_event['EventData']['M']),
                    'CommandId': dynamodb_event.get('CommandId', {}).get('S'),
                    'CorrelationId': dynamodb_event.get('CorrelationId', {}).get('S')
                }
                
                # Publish to EventBridge
                eventbridge.put_events(
                    Entries=[{
                        'Source': 'cqrs.demo',
                        'DetailType': domain_event['EventType'],
                        'Detail': json.dumps(domain_event, default=str),
                        'EventBusName': os.environ['EVENT_BUS_NAME']
                    }]
                )
                
                print(f"Published event {domain_event['EventId']} to EventBridge")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error processing stream: {str(e)}")
        raise

def deserialize_dynamodb_item(item):
    """Convert DynamoDB item format to regular Python objects"""
    if isinstance(item, dict):
        if len(item) == 1:
            key, value = next(iter(item.items()))
            if key == 'S':
                return value
            elif key == 'N':
                return Decimal(value)
            elif key == 'B':
                return value
            elif key == 'SS':
                return set(value)
            elif key == 'NS':
                return set(Decimal(v) for v in value)
            elif key == 'BS':
                return set(value)
            elif key == 'M':
                return {k: deserialize_dynamodb_item(v) for k, v in value.items()}
            elif key == 'L':
                return [deserialize_dynamodb_item(v) for v in value]
            elif key == 'NULL':
                return None
            elif key == 'BOOL':
                return value
        else:
            return {k: deserialize_dynamodb_item(v) for k, v in item.items()}
    return item
'''

    def _get_user_projection_code(self) -> str:
        """Return the user projection Lambda function code."""
        return '''
import json
import boto3
import os

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
        
        if event_type == 'UserCreated':
            # Create user profile projection
            table.put_item(
                Item={
                    'UserId': event_data['userId'],
                    'Email': event_data['email'],
                    'Name': event_data['name'],
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version']
                }
            )
            print(f"Created user profile for {event_data['userId']}")
            
        elif event_type == 'UserProfileUpdated':
            # Update user profile projection
            update_expression = "SET UpdatedAt = :updated, Version = :version"
            expression_values = {
                ':updated': event_data['updatedAt'],
                ':version': detail['Version']
            }
            
            # Build update expression for changes
            for field, value in event_data['changes'].items():
                if field in ['Name', 'Email']:  # Allow only certain fields
                    update_expression += f", {field} = :{field.lower()}"
                    expression_values[f":{field.lower()}"] = value
            
            table.update_item(
                Key={'UserId': event_data['userId']},
                UpdateExpression=update_expression,
                ExpressionAttributeValues=expression_values
            )
            print(f"Updated user profile for {event_data['userId']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error in user projection: {str(e)}")
        raise
'''

    def _get_order_projection_code(self) -> str:
        """Return the order projection Lambda function code."""
        return '''
import json
import boto3
import os
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        detail = event['detail']
        event_type = detail['EventType']
        event_data = detail['EventData']
        
        table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
        
        if event_type == 'OrderCreated':
            # Create order summary projection
            table.put_item(
                Item={
                    'OrderId': event_data['orderId'],
                    'UserId': event_data['userId'],
                    'Items': event_data['items'],
                    'TotalAmount': Decimal(str(event_data['totalAmount'])),
                    'Status': 'Created',
                    'CreatedAt': event_data['createdAt'],
                    'UpdatedAt': event_data['createdAt'],
                    'Version': detail['Version']
                }
            )
            print(f"Created order summary for {event_data['orderId']}")
            
        elif event_type == 'OrderStatusUpdated':
            # Update order status in projection
            table.update_item(
                Key={'OrderId': event_data['orderId']},
                UpdateExpression="SET #status = :status, UpdatedAt = :updated, Version = :version",
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': event_data['status'],
                    ':updated': event_data['updatedAt'],
                    ':version': detail['Version']
                }
            )
            print(f"Updated order status for {event_data['orderId']}")
        
        return {'statusCode': 200}
        
    except Exception as e:
        print(f"Error in order projection: {str(e)}")
        raise
'''

    def _get_query_handler_code(self) -> str:
        """Return the query handler Lambda function code."""
        return '''
import json
import boto3
import os
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse query from API Gateway or direct invocation
        query = json.loads(event['body']) if 'body' in event else event
        query_type = query.get('queryType')
        
        if query_type == 'GetUserProfile':
            result = get_user_profile(query['userId'])
        elif query_type == 'GetUserByEmail':
            result = get_user_by_email(query['email'])
        elif query_type == 'GetOrdersByUser':
            result = get_orders_by_user(query['userId'])
        elif query_type == 'GetOrdersByStatus':
            result = get_orders_by_status(query['status'])
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown query type: {query_type}'})
            }
        
        return {
            'statusCode': 200,
            'body': json.dumps(result, default=decimal_encoder)
        }
        
    except Exception as e:
        print(f"Error processing query: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error'})
        }

def get_user_profile(user_id):
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.get_item(Key={'UserId': user_id})
    return response.get('Item')

def get_user_by_email(email):
    table = dynamodb.Table(os.environ['USER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Email-index',
        KeyConditionExpression=Key('Email').eq(email)
    )
    return response['Items'][0] if response['Items'] else None

def get_orders_by_user(user_id):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='UserId-index',
        KeyConditionExpression=Key('UserId').eq(user_id)
    )
    return response['Items']

def get_orders_by_status(status):
    table = dynamodb.Table(os.environ['ORDER_READ_MODEL_TABLE'])
    response = table.query(
        IndexName='Status-index',
        KeyConditionExpression=Key('Status').eq(status)
    )
    return response['Items']

def decimal_encoder(obj):
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
'''


# CDK App definition
app = cdk.App()

# Create the CQRS Event Sourcing stack
CqrsEventSourcingStack(
    app,
    "CqrsEventSourcingStack",
    description="CQRS and Event Sourcing implementation with EventBridge and DynamoDB",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
    ),
)

# Synthesize the CloudFormation template
app.synth()