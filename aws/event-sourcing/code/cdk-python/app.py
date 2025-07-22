#!/usr/bin/env python3
"""
Event Sourcing Architecture CDK Application

This CDK application creates a comprehensive event sourcing architecture using:
- EventBridge for event routing and publishing
- DynamoDB for event store and read models
- Lambda functions for command handling, projections, and queries
- SQS for dead letter queue handling
- CloudWatch for monitoring and alerting

The architecture implements Command Query Responsibility Segregation (CQRS) pattern
with complete event sourcing capabilities for financial transaction processing.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_dynamodb as dynamodb,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sqs as sqs,
    aws_cloudwatch as cloudwatch,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
    CfnOutput,
    Tags
)
import json


class EventSourcingStack(Stack):
    """
    CDK Stack for Event Sourcing Architecture
    
    This stack creates all infrastructure components needed for a production-ready
    event sourcing system including event store, read models, event bus, and 
    processing functions.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.environment_name = self.node.try_get_context("environment") or "dev"
        self.retention_days = self.node.try_get_context("retention_days") or 365
        
        # Create DynamoDB tables
        self.event_store_table = self._create_event_store_table()
        self.read_model_table = self._create_read_model_table()
        
        # Create EventBridge custom bus
        self.event_bus = self._create_event_bus()
        
        # Create Lambda execution role
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.command_handler = self._create_command_handler()
        self.projection_handler = self._create_projection_handler()
        self.query_handler = self._create_query_handler()
        
        # Create SQS Dead Letter Queue
        self.dead_letter_queue = self._create_dead_letter_queue()
        
        # Create EventBridge rules and targets
        self._create_event_rules()
        
        # Create monitoring and alarms
        self._create_monitoring()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_event_store_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for event store with proper indexing for event sourcing patterns.
        
        The table uses composite primary key (AggregateId, EventSequence) to ensure
        proper event ordering within aggregates. Global Secondary Index enables
        efficient querying by event type and timestamp.
        """
        table = dynamodb.Table(
            self, "EventStoreTable",
            table_name=f"event-store-{self.environment_name}",
            partition_key=dynamodb.Attribute(
                name="AggregateId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="EventSequence",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            table_class=dynamodb.TableClass.STANDARD
        )
        
        # Add Global Secondary Index for event type queries
        table.add_global_secondary_index(
            index_name="EventType-Timestamp-index",
            partition_key=dynamodb.Attribute(
                name="EventType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        return table

    def _create_read_model_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for read models (projections).
        
        This table stores materialized views for efficient querying,
        implementing the query side of CQRS pattern.
        """
        table = dynamodb.Table(
            self, "ReadModelTable",
            table_name=f"read-model-{self.environment_name}",
            partition_key=dynamodb.Attribute(
                name="AccountId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="ProjectionType",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )
        
        return table

    def _create_event_bus(self) -> events.EventBus:
        """
        Create custom EventBridge bus for event sourcing with archiving capability.
        
        The custom bus provides isolation from default bus and enables
        event replay capabilities through archives.
        """
        bus = events.EventBus(
            self, "EventSourcingBus",
            event_bus_name=f"event-sourcing-bus-{self.environment_name}",
            description="Event bus for financial transaction event sourcing"
        )
        
        # Create event archive for replay capability
        events.Archive(
            self, "EventArchive",
            source_event_bus=bus,
            archive_name=f"event-sourcing-archive-{self.environment_name}",
            description="Archive for event replay and audit compliance",
            retention=Duration.days(self.retention_days),
            event_pattern=events.EventPattern(
                source=["event-sourcing.financial"]
            )
        )
        
        return bus

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with least privilege access.
        
        The role provides necessary permissions for EventBridge, DynamoDB,
        and CloudWatch operations while maintaining security best practices.
        """
        role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"event-sourcing-lambda-role-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add DynamoDB permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:BatchGetItem",
                    "dynamodb:BatchWriteItem"
                ],
                resources=[
                    self.event_store_table.table_arn,
                    self.read_model_table.table_arn,
                    f"{self.event_store_table.table_arn}/index/*",
                    f"{self.read_model_table.table_arn}/index/*"
                ]
            )
        )
        
        # Add EventBridge permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "events:PutEvents",
                    "events:List*",
                    "events:Describe*"
                ],
                resources=[
                    self.event_bus.event_bus_arn,
                    f"arn:aws:events:{self.region}:{self.account}:rule/*"
                ]
            )
        )
        
        return role

    def _create_command_handler(self) -> lambda_.Function:
        """
        Create Lambda function for command processing.
        
        This function handles business commands, validates them, and converts
        them to immutable events stored in the event store.
        """
        function = lambda_.Function(
            self, "CommandHandler",
            function_name=f"command-handler-{self.environment_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_command_handler_code()),
            environment={
                "EVENT_STORE_TABLE": self.event_store_table.table_name,
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
                "ENVIRONMENT": self.environment_name
            },
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.lambda_role,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
            description="Processes business commands and generates events"
        )
        
        return function

    def _create_projection_handler(self) -> lambda_.Function:
        """
        Create Lambda function for projection processing.
        
        This function processes events from EventBridge and updates
        read models in the query-side database.
        """
        function = lambda_.Function(
            self, "ProjectionHandler",
            function_name=f"projection-handler-{self.environment_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_projection_handler_code()),
            environment={
                "READ_MODEL_TABLE": self.read_model_table.table_name,
                "ENVIRONMENT": self.environment_name
            },
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.lambda_role,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
            description="Processes events and updates read model projections"
        )
        
        return function

    def _create_query_handler(self) -> lambda_.Function:
        """
        Create Lambda function for query processing and event reconstruction.
        
        This function handles read queries, both current state (from projections)
        and historical state reconstruction (from events).
        """
        function = lambda_.Function(
            self, "QueryHandler",
            function_name=f"query-handler-{self.environment_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_query_handler_code()),
            environment={
                "EVENT_STORE_TABLE": self.event_store_table.table_name,
                "READ_MODEL_TABLE": self.read_model_table.table_name,
                "ENVIRONMENT": self.environment_name
            },
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.lambda_role,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
            description="Handles queries and event reconstruction"
        )
        
        return function

    def _create_dead_letter_queue(self) -> sqs.Queue:
        """
        Create SQS Dead Letter Queue for failed event processing.
        
        This queue captures events that fail processing after retries,
        enabling manual inspection and reprocessing.
        """
        queue = sqs.Queue(
            self, "DeadLetterQueue",
            queue_name=f"event-sourcing-dlq-{self.environment_name}",
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.seconds(300),
            encryption=sqs.QueueEncryption.SQS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        return queue

    def _create_event_rules(self) -> None:
        """
        Create EventBridge rules for event routing and processing.
        
        Rules filter events based on patterns and route them to appropriate targets.
        """
        # Rule for financial events
        financial_rule = events.Rule(
            self, "FinancialEventsRule",
            rule_name=f"financial-events-rule-{self.environment_name}",
            description="Route financial events to projection handler",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["event-sourcing.financial"],
                detail_type=["AccountCreated", "TransactionProcessed", "AccountClosed"]
            )
        )
        
        # Add Lambda target to financial events rule
        financial_rule.add_target(
            targets.LambdaFunction(
                self.projection_handler,
                dead_letter_queue=self.dead_letter_queue,
                retry_attempts=3
            )
        )
        
        # Rule for failed events
        failed_rule = events.Rule(
            self, "FailedEventsRule",
            rule_name=f"failed-events-rule-{self.environment_name}",
            description="Route failed events to dead letter queue",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["aws.events"],
                detail_type=["Event Processing Failed"]
            )
        )
        
        # Add SQS target for failed events
        failed_rule.add_target(
            targets.SqsQueue(self.dead_letter_queue)
        )

    def _create_monitoring(self) -> None:
        """
        Create CloudWatch alarms for monitoring system health.
        
        Monitors key metrics including DynamoDB throttling, Lambda errors,
        and EventBridge failed invocations.
        """
        # DynamoDB write throttles alarm
        cloudwatch.Alarm(
            self, "EventStoreWriteThrottlesAlarm",
            alarm_name=f"EventStore-WriteThrottles-{self.environment_name}",
            alarm_description="DynamoDB write throttles on event store",
            metric=self.event_store_table.metric_write_throttles(),
            threshold=5,
            evaluation_periods=2,
            period=Duration.minutes(5),
            statistic="Sum",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Lambda errors alarm
        cloudwatch.Alarm(
            self, "CommandHandlerErrorsAlarm",
            alarm_name=f"CommandHandler-Errors-{self.environment_name}",
            alarm_description="High error rate in command handler",
            metric=self.command_handler.metric_errors(),
            threshold=10,
            evaluation_periods=2,
            period=Duration.minutes(5),
            statistic="Sum",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # EventBridge failed invocations alarm
        cloudwatch.Alarm(
            self, "EventBridgeFailedInvocationsAlarm",
            alarm_name=f"EventBridge-FailedInvocations-{self.environment_name}",
            alarm_description="High number of failed event invocations",
            metric=cloudwatch.Metric(
                namespace="AWS/Events",
                metric_name="FailedInvocations",
                dimensions_map={
                    "EventBusName": self.event_bus.event_bus_name
                }
            ),
            threshold=5,
            evaluation_periods=2,
            period=Duration.minutes(5),
            statistic="Sum",
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self, "EventBusName",
            value=self.event_bus.event_bus_name,
            description="Name of the custom EventBridge bus"
        )
        
        CfnOutput(
            self, "EventStoreTableName",
            value=self.event_store_table.table_name,
            description="Name of the event store DynamoDB table"
        )
        
        CfnOutput(
            self, "ReadModelTableName",
            value=self.read_model_table.table_name,
            description="Name of the read model DynamoDB table"
        )
        
        CfnOutput(
            self, "CommandHandlerArn",
            value=self.command_handler.function_arn,
            description="ARN of the command handler Lambda function"
        )
        
        CfnOutput(
            self, "QueryHandlerArn",
            value=self.query_handler.function_arn,
            description="ARN of the query handler Lambda function"
        )
        
        CfnOutput(
            self, "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="URL of the dead letter queue"
        )

    def _add_tags(self) -> None:
        """Add consistent tags to all resources."""
        Tags.of(self).add("Project", "EventSourcing")
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Architecture", "CQRS-EventSourcing")
        Tags.of(self).add("ManagedBy", "AWS-CDK")

    def _get_command_handler_code(self) -> str:
        """Return the Lambda function code for command processing."""
        return '''
import json
import boto3
import uuid
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
events_client = boto3.client('events')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])

def lambda_handler(event, context):
    """
    Process business commands and generate events.
    
    Validates commands, determines event sequence, stores events,
    and publishes them to EventBridge.
    """
    try:
        # Parse command from event
        command = json.loads(event['body']) if 'body' in event else event
        logger.info(f"Processing command: {command}")
        
        # Generate event from command
        event_id = str(uuid.uuid4())
        aggregate_id = command['aggregateId']
        event_type = command['eventType']
        event_data = command['eventData']
        
        # Get next sequence number
        response = table.query(
            KeyConditionExpression='AggregateId = :aid',
            ExpressionAttributeValues={':aid': aggregate_id},
            ScanIndexForward=False,
            Limit=1
        )
        
        next_sequence = 1
        if response['Items']:
            next_sequence = response['Items'][0]['EventSequence'] + 1
        
        # Create event record
        timestamp = datetime.utcnow().isoformat()
        event_record = {
            'EventId': event_id,
            'AggregateId': aggregate_id,
            'EventSequence': next_sequence,
            'EventType': event_type,
            'EventData': event_data,
            'Timestamp': timestamp,
            'Version': '1.0'
        }
        
        # Store event in DynamoDB
        table.put_item(Item=event_record)
        logger.info(f"Stored event: {event_id}")
        
        # Publish event to EventBridge
        events_client.put_events(
            Entries=[
                {
                    'Source': 'event-sourcing.financial',
                    'DetailType': event_type,
                    'Detail': json.dumps(event_record),
                    'EventBusName': os.environ['EVENT_BUS_NAME']
                }
            ]
        )
        logger.info(f"Published event to EventBridge: {event_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'eventId': event_id,
                'aggregateId': aggregate_id,
                'sequence': next_sequence
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing command: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

    def _get_projection_handler_code(self) -> str:
        """Return the Lambda function code for projection processing."""
        return '''
import json
import boto3
import os
import logging
from decimal import Decimal

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    """
    Process events and update read model projections.
    
    Handles different event types and maintains materialized views
    for efficient querying.
    """
    try:
        # Process EventBridge events
        for record in event['Records']:
            detail = json.loads(record['body']) if 'body' in record else record['detail']
            logger.info(f"Processing event: {detail}")
            
            event_type = detail['EventType']
            aggregate_id = detail['AggregateId']
            event_data = detail['EventData']
            
            # Handle different event types
            if event_type == 'AccountCreated':
                handle_account_created(aggregate_id, event_data)
            elif event_type == 'TransactionProcessed':
                handle_transaction_processed(aggregate_id, event_data)
            elif event_type == 'AccountClosed':
                handle_account_closed(aggregate_id, event_data)
            else:
                logger.warning(f"Unknown event type: {event_type}")
                
        return {'statusCode': 200}
        
    except Exception as e:
        logger.error(f"Error processing projection: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def handle_account_created(aggregate_id, event_data):
    """Handle AccountCreated event by creating account summary projection."""
    read_model_table.put_item(
        Item={
            'AccountId': aggregate_id,
            'ProjectionType': 'AccountSummary',
            'Balance': Decimal('0.00'),
            'Status': 'Active',
            'CreatedAt': event_data['createdAt'],
            'TransactionCount': 0
        }
    )
    logger.info(f"Created account summary for: {aggregate_id}")

def handle_transaction_processed(aggregate_id, event_data):
    """Handle TransactionProcessed event by updating account balance."""
    # Update account balance
    response = read_model_table.get_item(
        Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'}
    )
    
    if 'Item' in response:
        current_balance = response['Item']['Balance']
        transaction_count = response['Item']['TransactionCount']
        
        new_balance = current_balance + Decimal(str(event_data['amount']))
        
        read_model_table.update_item(
            Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
            UpdateExpression='SET Balance = :balance, TransactionCount = :count, LastTransactionAt = :timestamp',
            ExpressionAttributeValues={
                ':balance': new_balance,
                ':count': transaction_count + 1,
                ':timestamp': event_data['timestamp']
            }
        )
        logger.info(f"Updated account balance for: {aggregate_id}")

def handle_account_closed(aggregate_id, event_data):
    """Handle AccountClosed event by updating account status."""
    read_model_table.update_item(
        Key={'AccountId': aggregate_id, 'ProjectionType': 'AccountSummary'},
        UpdateExpression='SET #status = :status, ClosedAt = :timestamp',
        ExpressionAttributeNames={'#status': 'Status'},
        ExpressionAttributeValues={
            ':status': 'Closed',
            ':timestamp': event_data['closedAt']
        }
    )
    logger.info(f"Closed account: {aggregate_id}")
'''

    def _get_query_handler_code(self) -> str:
        """Return the Lambda function code for query processing."""
        return '''
import json
import boto3
import os
import logging
from boto3.dynamodb.conditions import Key

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
event_store_table = dynamodb.Table(os.environ['EVENT_STORE_TABLE'])
read_model_table = dynamodb.Table(os.environ['READ_MODEL_TABLE'])

def lambda_handler(event, context):
    """
    Handle query requests for both current state and historical reconstruction.
    
    Supports multiple query types including aggregate events, account summaries,
    and state reconstruction at specific points in time.
    """
    try:
        query_type = event['queryType']
        logger.info(f"Processing query: {query_type}")
        
        if query_type == 'getAggregateEvents':
            return get_aggregate_events(event['aggregateId'])
        elif query_type == 'getAccountSummary':
            return get_account_summary(event['accountId'])
        elif query_type == 'reconstructState':
            return reconstruct_state(event['aggregateId'], event.get('upToSequence'))
        else:
            return {'statusCode': 400, 'body': json.dumps({'error': 'Unknown query type'})}
            
    except Exception as e:
        logger.error(f"Error processing query: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps({'error': str(e)})}

def get_aggregate_events(aggregate_id):
    """Get all events for a specific aggregate."""
    response = event_store_table.query(
        KeyConditionExpression=Key('AggregateId').eq(aggregate_id),
        ScanIndexForward=True
    )
    
    logger.info(f"Retrieved {len(response['Items'])} events for aggregate: {aggregate_id}")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'aggregateId': aggregate_id,
            'events': response['Items']
        }, default=str)
    }

def get_account_summary(account_id):
    """Get current account summary from read model."""
    response = read_model_table.get_item(
        Key={'AccountId': account_id, 'ProjectionType': 'AccountSummary'}
    )
    
    if 'Item' in response:
        logger.info(f"Retrieved account summary for: {account_id}")
        return {
            'statusCode': 200,
            'body': json.dumps(response['Item'], default=str)
        }
    else:
        logger.warning(f"Account not found: {account_id}")
        return {'statusCode': 404, 'body': json.dumps({'error': 'Account not found'})}

def reconstruct_state(aggregate_id, up_to_sequence=None):
    """Reconstruct aggregate state by replaying events."""
    # Build key condition
    key_condition = Key('AggregateId').eq(aggregate_id)
    
    if up_to_sequence:
        key_condition = key_condition & Key('EventSequence').lte(up_to_sequence)
    
    response = event_store_table.query(
        KeyConditionExpression=key_condition,
        ScanIndexForward=True
    )
    
    # Replay events to reconstruct state
    state = {'balance': 0, 'status': 'Unknown', 'transactionCount': 0}
    
    for event in response['Items']:
        event_type = event['EventType']
        event_data = event['EventData']
        
        if event_type == 'AccountCreated':
            state['status'] = 'Active'
            state['createdAt'] = event_data['createdAt']
        elif event_type == 'TransactionProcessed':
            state['balance'] += float(event_data['amount'])
            state['transactionCount'] += 1
        elif event_type == 'AccountClosed':
            state['status'] = 'Closed'
            state['closedAt'] = event_data['closedAt']
    
    logger.info(f"Reconstructed state for {aggregate_id} using {len(response['Items'])} events")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'aggregateId': aggregate_id,
            'reconstructedState': state,
            'eventsProcessed': len(response['Items'])
        }, default=str)
    }
'''


def main():
    """Main application entry point."""
    app = cdk.App()
    
    # Create stack with environment-specific configuration
    EventSourcingStack(
        app, 
        "EventSourcingStack",
        description="Event Sourcing Architecture with EventBridge and DynamoDB",
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()