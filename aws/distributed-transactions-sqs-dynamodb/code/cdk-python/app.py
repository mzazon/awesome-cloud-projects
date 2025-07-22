#!/usr/bin/env python3
"""
CDK Python Application for Distributed Transaction Processing with SQS

This application implements the Saga pattern using Amazon SQS FIFO queues for event-driven
transaction coordination and Amazon DynamoDB for reliable state management with built-in
transaction support.

The architecture includes:
- Transaction orchestrator Lambda function
- Order, payment, and inventory processing services
- SQS FIFO queues for reliable message delivery
- DynamoDB tables for state management
- API Gateway for transaction initiation
- CloudWatch monitoring and alarms
"""

import os
from aws_cdk import (
    App,
    Duration,
    Stack,
    StackProps,
    aws_apigateway as apigateway,
    aws_cloudwatch as cloudwatch,
    aws_dynamodb as dynamodb,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
    aws_sqs as sqs,
)
from constructs import Construct


class DistributedTransactionProcessingStack(Stack):
    """
    CDK Stack for Distributed Transaction Processing with SQS.
    
    This stack implements the Saga pattern for coordinating distributed transactions
    across multiple microservices using AWS managed services.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create DynamoDB tables
        self._create_dynamodb_tables()
        
        # Create SQS queues
        self._create_sqs_queues()
        
        # Create Lambda functions
        self._create_lambda_functions()
        
        # Create API Gateway
        self._create_api_gateway()
        
        # Create monitoring resources
        self._create_monitoring()
        
        # Initialize sample data
        self._initialize_sample_data()

    def _create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables for transaction state and business data."""
        
        # Saga state table for transaction coordination
        self.saga_state_table = dynamodb.Table(
            self, "SagaStateTable",
            table_name=f"{self.stack_name}-saga-state",
            partition_key=dynamodb.Attribute(
                name="TransactionId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            time_to_live_attribute="TTL",
            point_in_time_recovery=True,
            removal_policy=self.removal_policy
        )

        # Orders table
        self.orders_table = dynamodb.Table(
            self, "OrdersTable",
            table_name=f"{self.stack_name}-orders",
            partition_key=dynamodb.Attribute(
                name="OrderId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=self.removal_policy
        )

        # Payments table
        self.payments_table = dynamodb.Table(
            self, "PaymentsTable",
            table_name=f"{self.stack_name}-payments",
            partition_key=dynamodb.Attribute(
                name="PaymentId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=self.removal_policy
        )

        # Inventory table
        self.inventory_table = dynamodb.Table(
            self, "InventoryTable",
            table_name=f"{self.stack_name}-inventory",
            partition_key=dynamodb.Attribute(
                name="ProductId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=self.removal_policy
        )

    def _create_sqs_queues(self) -> None:
        """Create SQS FIFO queues for transaction coordination."""
        
        # Dead letter queue for failed messages
        self.dead_letter_queue = sqs.Queue(
            self, "DeadLetterQueue",
            queue_name=f"{self.stack_name}-dlq.fifo",
            fifo=True,
            content_based_deduplication=True,
            message_retention_period=Duration.days(14),
            removal_policy=self.removal_policy
        )

        # Order processing queue
        self.order_queue = sqs.Queue(
            self, "OrderProcessingQueue",
            queue_name=f"{self.stack_name}-order-processing.fifo",
            fifo=True,
            content_based_deduplication=True,
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            removal_policy=self.removal_policy
        )

        # Payment processing queue
        self.payment_queue = sqs.Queue(
            self, "PaymentProcessingQueue",
            queue_name=f"{self.stack_name}-payment-processing.fifo",
            fifo=True,
            content_based_deduplication=True,
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            removal_policy=self.removal_policy
        )

        # Inventory update queue
        self.inventory_queue = sqs.Queue(
            self, "InventoryUpdateQueue",
            queue_name=f"{self.stack_name}-inventory-update.fifo",
            fifo=True,
            content_based_deduplication=True,
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            removal_policy=self.removal_policy
        )

        # Compensation queue for rollback operations
        self.compensation_queue = sqs.Queue(
            self, "CompensationQueue",
            queue_name=f"{self.stack_name}-compensation.fifo",
            fifo=True,
            content_based_deduplication=True,
            message_retention_period=Duration.days(14),
            visibility_timeout=Duration.minutes(5),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            removal_policy=self.removal_policy
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for transaction processing."""
        
        # Common Lambda execution role
        lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "DynamoDBAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:DeleteItem",
                                "dynamodb:Query",
                                "dynamodb:Scan",
                                "dynamodb:BatchGetItem",
                                "dynamodb:BatchWriteItem",
                                "dynamodb:ConditionCheckItem"
                            ],
                            resources=[
                                self.saga_state_table.table_arn,
                                self.orders_table.table_arn,
                                self.payments_table.table_arn,
                                self.inventory_table.table_arn
                            ]
                        )
                    ]
                ),
                "SQSAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sqs:SendMessage",
                                "sqs:ReceiveMessage",
                                "sqs:DeleteMessage",
                                "sqs:GetQueueAttributes",
                                "sqs:GetQueueUrl"
                            ],
                            resources=[
                                self.order_queue.queue_arn,
                                self.payment_queue.queue_arn,
                                self.inventory_queue.queue_arn,
                                self.compensation_queue.queue_arn,
                                self.dead_letter_queue.queue_arn
                            ]
                        )
                    ]
                )
            }
        )

        # Common environment variables
        common_env = {
            "SAGA_STATE_TABLE": self.saga_state_table.table_name,
            "ORDER_TABLE": self.orders_table.table_name,
            "PAYMENT_TABLE": self.payments_table.table_name,
            "INVENTORY_TABLE": self.inventory_table.table_name,
            "ORDER_QUEUE_URL": self.order_queue.queue_url,
            "PAYMENT_QUEUE_URL": self.payment_queue.queue_url,
            "INVENTORY_QUEUE_URL": self.inventory_queue.queue_url,
            "COMPENSATION_QUEUE_URL": self.compensation_queue.queue_url,
            "DLQ_URL": self.dead_letter_queue.queue_url
        }

        # Transaction orchestrator Lambda
        self.orchestrator_function = lambda_.Function(
            self, "TransactionOrchestrator",
            function_name=f"{self.stack_name}-orchestrator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_orchestrator_code()),
            environment=common_env,
            role=lambda_role,
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Transaction orchestrator for distributed saga pattern"
        )

        # Compensation handler Lambda
        self.compensation_handler = lambda_.Function(
            self, "CompensationHandler",
            function_name=f"{self.stack_name}-compensation-handler",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handle_compensation",
            code=lambda_.Code.from_inline(self._get_orchestrator_code()),
            environment=common_env,
            role=lambda_role,
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Compensation handler for failed transactions"
        )

        # Order service Lambda
        self.order_service = lambda_.Function(
            self, "OrderService",
            function_name=f"{self.stack_name}-order-service",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_order_service_code()),
            environment=common_env,
            role=lambda_role,
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Order processing service"
        )

        # Payment service Lambda
        self.payment_service = lambda_.Function(
            self, "PaymentService",
            function_name=f"{self.stack_name}-payment-service",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_payment_service_code()),
            environment=common_env,
            role=lambda_role,
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Payment processing service"
        )

        # Inventory service Lambda
        self.inventory_service = lambda_.Function(
            self, "InventoryService",
            function_name=f"{self.stack_name}-inventory-service",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_inventory_service_code()),
            environment=common_env,
            role=lambda_role,
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Inventory management service"
        )

        # Configure SQS event sources
        self.order_service.add_event_source(
            lambda_event_sources.SqsEventSource(
                queue=self.order_queue,
                batch_size=1,
                max_batching_window=Duration.seconds(5)
            )
        )

        self.payment_service.add_event_source(
            lambda_event_sources.SqsEventSource(
                queue=self.payment_queue,
                batch_size=1,
                max_batching_window=Duration.seconds(5)
            )
        )

        self.inventory_service.add_event_source(
            lambda_event_sources.SqsEventSource(
                queue=self.inventory_queue,
                batch_size=1,
                max_batching_window=Duration.seconds(5)
            )
        )

        self.compensation_handler.add_event_source(
            lambda_event_sources.SqsEventSource(
                queue=self.compensation_queue,
                batch_size=1,
                max_batching_window=Duration.seconds(5)
            )
        )

    def _create_api_gateway(self) -> None:
        """Create API Gateway for transaction initiation."""
        
        # REST API
        self.api = apigateway.RestApi(
            self, "TransactionAPI",
            rest_api_name=f"{self.stack_name}-transaction-api",
            description="Distributed Transaction Processing API",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization"]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=100,
                throttling_burst_limit=200,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )

        # Transactions resource
        transactions_resource = self.api.root.add_resource("transactions")

        # POST method for transaction initiation
        transactions_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(
                self.orchestrator_function,
                proxy=True,
                integration_responses=[
                    apigateway.IntegrationResponse(
                        status_code="200",
                        response_headers={
                            "Access-Control-Allow-Origin": "'*'"
                        }
                    )
                ]
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_headers={
                        "Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms."""
        
        # CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "TransactionDashboard",
            dashboard_name=f"{self.stack_name}-transactions"
        )

        # Lambda metrics widget
        lambda_metrics_widget = cloudwatch.GraphWidget(
            title="Transaction Orchestrator Metrics",
            left=[
                self.orchestrator_function.metric_invocations(
                    period=Duration.minutes(5)
                ),
                self.orchestrator_function.metric_errors(
                    period=Duration.minutes(5)
                ),
                self.orchestrator_function.metric_duration(
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        # SQS metrics widget
        sqs_metrics_widget = cloudwatch.GraphWidget(
            title="SQS Queue Metrics",
            left=[
                self.order_queue.metric_number_of_messages_sent(
                    period=Duration.minutes(5)
                ),
                self.order_queue.metric_number_of_messages_received(
                    period=Duration.minutes(5)
                ),
                self.order_queue.metric_approximate_number_of_messages_visible(
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        self.dashboard.add_widgets(lambda_metrics_widget, sqs_metrics_widget)

        # Alarms for failed transactions
        self.failed_transactions_alarm = cloudwatch.Alarm(
            self, "FailedTransactionsAlarm",
            alarm_name=f"{self.stack_name}-failed-transactions",
            alarm_description="Alert when transactions fail",
            metric=self.orchestrator_function.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Alarm for SQS message age
        self.message_age_alarm = cloudwatch.Alarm(
            self, "MessageAgeAlarm",
            alarm_name=f"{self.stack_name}-message-age",
            alarm_description="Alert when messages age in queue",
            metric=self.order_queue.metric_approximate_age_of_oldest_message(
                period=Duration.minutes(5)
            ),
            threshold=600,  # 10 minutes
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

    def _initialize_sample_data(self) -> None:
        """Initialize sample inventory data using custom resource."""
        
        # Lambda function for custom resource
        init_data_function = lambda_.Function(
            self, "InitializeDataFunction",
            function_name=f"{self.stack_name}-init-data",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_init_data_code()),
            environment={
                "INVENTORY_TABLE": self.inventory_table.table_name
            },
            role=iam.Role(
                self, "InitDataRole",
                assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name(
                        "service-role/AWSLambdaBasicExecutionRole"
                    )
                ],
                inline_policies={
                    "DynamoDBAccess": iam.PolicyDocument(
                        statements=[
                            iam.PolicyStatement(
                                effect=iam.Effect.ALLOW,
                                actions=[
                                    "dynamodb:PutItem",
                                    "dynamodb:GetItem",
                                    "dynamodb:DeleteItem"
                                ],
                                resources=[self.inventory_table.table_arn]
                            )
                        ]
                    )
                }
            ),
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Custom resource to initialize data
        from aws_cdk import custom_resources
        custom_resources.Provider(
            self, "InitDataProvider",
            on_event_handler=init_data_function
        )

    @property
    def removal_policy(self):
        """Get the removal policy based on environment."""
        return self.removal_policy_value if hasattr(self, 'removal_policy_value') else None

    def _get_orchestrator_code(self) -> str:
        """Get the orchestrator Lambda function code."""
        return """
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
ORDER_QUEUE_URL = os.environ['ORDER_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        # Initialize transaction
        transaction_id = str(uuid.uuid4())
        order_data = json.loads(event['body'])
        
        # Create saga state record
        saga_table = dynamodb.Table(SAGA_STATE_TABLE)
        saga_table.put_item(
            Item={
                'TransactionId': transaction_id,
                'Status': 'STARTED',
                'CurrentStep': 'ORDER_PROCESSING',
                'Steps': ['ORDER_PROCESSING', 'PAYMENT_PROCESSING', 'INVENTORY_UPDATE'],
                'CompletedSteps': [],
                'OrderData': order_data,
                'Timestamp': datetime.utcnow().isoformat(),
                'TTL': int(datetime.utcnow().timestamp()) + 86400  # 24 hours TTL
            }
        )
        
        # Start transaction by sending to order queue
        message_body = {
            'transactionId': transaction_id,
            'step': 'ORDER_PROCESSING',
            'data': order_data
        }
        
        sqs.send_message(
            QueueUrl=ORDER_QUEUE_URL,
            MessageBody=json.dumps(message_body),
            MessageGroupId=transaction_id
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'transactionId': transaction_id,
                'status': 'STARTED',
                'message': 'Transaction initiated successfully'
            })
        }
        
    except Exception as e:
        print(f"Error in orchestrator: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'error': str(e)
            })
        }

def handle_compensation(event, context):
    try:
        # Process compensation messages
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            failed_step = message_body['failedStep']
            
            # Update saga state to failed
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET #status = :status, FailedStep = :failed_step',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':status': 'FAILED',
                    ':failed_step': failed_step
                }
            )
            
            print(f"Transaction {transaction_id} failed at step {failed_step}")
            
    except Exception as e:
        print(f"Error in compensation handler: {str(e)}")
        raise
"""

    def _get_order_service_code(self) -> str:
        """Get the order service Lambda function code."""
        return """
import json
import boto3
import uuid
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

ORDER_TABLE = os.environ['ORDER_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
PAYMENT_QUEUE_URL = os.environ['PAYMENT_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            order_data = message_body['data']
            
            # Generate order ID
            order_id = str(uuid.uuid4())
            
            # Create order record
            order_table = dynamodb.Table(ORDER_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            order_table.put_item(
                Item={
                    'OrderId': order_id,
                    'TransactionId': transaction_id,
                    'CustomerId': order_data['customerId'],
                    'ProductId': order_data['productId'],
                    'Quantity': order_data['quantity'],
                    'Amount': order_data['amount'],
                    'Status': 'PENDING',
                    'Timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Update saga state
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step',
                ExpressionAttributeValues={
                    ':step': ['ORDER_PROCESSING'],
                    ':next_step': 'PAYMENT_PROCESSING'
                }
            )
            
            # Send message to payment queue
            payment_message = {
                'transactionId': transaction_id,
                'step': 'PAYMENT_PROCESSING',
                'data': {
                    'orderId': order_id,
                    'customerId': order_data['customerId'],
                    'amount': order_data['amount']
                }
            }
            
            sqs.send_message(
                QueueUrl=PAYMENT_QUEUE_URL,
                MessageBody=json.dumps(payment_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Order {order_id} created for transaction {transaction_id}")
            
    except Exception as e:
        print(f"Error in order service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'ORDER_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
"""

    def _get_payment_service_code(self) -> str:
        """Get the payment service Lambda function code."""
        return """
import json
import boto3
import uuid
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

PAYMENT_TABLE = os.environ['PAYMENT_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
INVENTORY_QUEUE_URL = os.environ['INVENTORY_QUEUE_URL']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            payment_data = message_body['data']
            
            # Simulate payment processing (90% success rate)
            if random.random() < 0.1:
                raise Exception("Payment processing failed - insufficient funds")
            
            # Generate payment ID
            payment_id = str(uuid.uuid4())
            
            # Create payment record
            payment_table = dynamodb.Table(PAYMENT_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            payment_table.put_item(
                Item={
                    'PaymentId': payment_id,
                    'TransactionId': transaction_id,
                    'OrderId': payment_data['orderId'],
                    'CustomerId': payment_data['customerId'],
                    'Amount': payment_data['amount'],
                    'Status': 'PROCESSED',
                    'Timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Update saga state
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step',
                ExpressionAttributeValues={
                    ':step': ['PAYMENT_PROCESSING'],
                    ':next_step': 'INVENTORY_UPDATE'
                }
            )
            
            # Get original order data for inventory update
            saga_response = saga_table.get_item(
                Key={'TransactionId': transaction_id}
            )
            order_data = saga_response['Item']['OrderData']
            
            # Send message to inventory queue
            inventory_message = {
                'transactionId': transaction_id,
                'step': 'INVENTORY_UPDATE',
                'data': {
                    'orderId': payment_data['orderId'],
                    'paymentId': payment_id,
                    'productId': order_data['productId'],
                    'quantity': order_data['quantity']
                }
            }
            
            sqs.send_message(
                QueueUrl=INVENTORY_QUEUE_URL,
                MessageBody=json.dumps(inventory_message),
                MessageGroupId=transaction_id
            )
            
            print(f"Payment {payment_id} processed for transaction {transaction_id}")
            
    except Exception as e:
        print(f"Error in payment service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'PAYMENT_PROCESSING',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
"""

    def _get_inventory_service_code(self) -> str:
        """Get the inventory service Lambda function code."""
        return """
import json
import boto3
import os
import random
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sqs = boto3.client('sqs')

INVENTORY_TABLE = os.environ['INVENTORY_TABLE']
SAGA_STATE_TABLE = os.environ['SAGA_STATE_TABLE']
COMPENSATION_QUEUE_URL = os.environ['COMPENSATION_QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = json.loads(record['body'])
            transaction_id = message_body['transactionId']
            inventory_data = message_body['data']
            
            # Simulate inventory check (85% success rate)
            if random.random() < 0.15:
                raise Exception("Insufficient inventory available")
            
            # Update inventory using DynamoDB transaction
            inventory_table = dynamodb.Table(INVENTORY_TABLE)
            saga_table = dynamodb.Table(SAGA_STATE_TABLE)
            
            # Try to update inventory atomically
            try:
                inventory_table.update_item(
                    Key={'ProductId': inventory_data['productId']},
                    UpdateExpression='SET QuantityAvailable = QuantityAvailable - :quantity, LastUpdated = :timestamp',
                    ConditionExpression='QuantityAvailable >= :quantity',
                    ExpressionAttributeValues={
                        ':quantity': inventory_data['quantity'],
                        ':timestamp': datetime.utcnow().isoformat()
                    }
                )
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                raise Exception("Insufficient inventory - conditional check failed")
            
            # Update saga state to completed
            saga_table.update_item(
                Key={'TransactionId': transaction_id},
                UpdateExpression='SET CompletedSteps = list_append(CompletedSteps, :step), CurrentStep = :next_step, #status = :status',
                ExpressionAttributeNames={'#status': 'Status'},
                ExpressionAttributeValues={
                    ':step': ['INVENTORY_UPDATE'],
                    ':next_step': 'COMPLETED',
                    ':status': 'COMPLETED'
                }
            )
            
            print(f"Inventory updated for transaction {transaction_id}, product {inventory_data['productId']}")
            
    except Exception as e:
        print(f"Error in inventory service: {str(e)}")
        # Send compensation message
        compensation_message = {
            'transactionId': transaction_id,
            'failedStep': 'INVENTORY_UPDATE',
            'error': str(e)
        }
        
        sqs.send_message(
            QueueUrl=COMPENSATION_QUEUE_URL,
            MessageBody=json.dumps(compensation_message),
            MessageGroupId=transaction_id
        )
        
        raise
"""

    def _get_init_data_code(self) -> str:
        """Get the initialization data Lambda function code."""
        return """
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')

INVENTORY_TABLE = os.environ['INVENTORY_TABLE']

def handler(event, context):
    request_type = event['RequestType']
    
    if request_type == 'Create':
        try:
            # Initialize sample inventory data
            inventory_table = dynamodb.Table(INVENTORY_TABLE)
            
            sample_products = [
                {
                    'ProductId': 'PROD-001',
                    'ProductName': 'Premium Laptop',
                    'QuantityAvailable': 50,
                    'Price': 1299.99,
                    'LastUpdated': datetime.utcnow().isoformat()
                },
                {
                    'ProductId': 'PROD-002',
                    'ProductName': 'Wireless Headphones',
                    'QuantityAvailable': 100,
                    'Price': 199.99,
                    'LastUpdated': datetime.utcnow().isoformat()
                },
                {
                    'ProductId': 'PROD-003',
                    'ProductName': 'Smartphone',
                    'QuantityAvailable': 25,
                    'Price': 799.99,
                    'LastUpdated': datetime.utcnow().isoformat()
                }
            ]
            
            # Insert sample products
            for product in sample_products:
                inventory_table.put_item(Item=product)
            
            return {
                'Status': 'SUCCESS',
                'PhysicalResourceId': 'sample-inventory-data',
                'Data': {
                    'Message': 'Sample inventory data initialized successfully'
                }
            }
            
        except Exception as e:
            print(f"Error initializing data: {str(e)}")
            return {
                'Status': 'FAILED',
                'PhysicalResourceId': 'sample-inventory-data',
                'Reason': str(e)
            }
    
    elif request_type == 'Delete':
        try:
            # Clean up sample data
            inventory_table = dynamodb.Table(INVENTORY_TABLE)
            
            sample_product_ids = ['PROD-001', 'PROD-002', 'PROD-003']
            
            for product_id in sample_product_ids:
                try:
                    inventory_table.delete_item(
                        Key={'ProductId': product_id}
                    )
                except Exception as e:
                    print(f"Error deleting product {product_id}: {str(e)}")
            
            return {
                'Status': 'SUCCESS',
                'PhysicalResourceId': 'sample-inventory-data',
                'Data': {
                    'Message': 'Sample inventory data cleaned up successfully'
                }
            }
            
        except Exception as e:
            print(f"Error cleaning up data: {str(e)}")
            return {
                'Status': 'SUCCESS',  # Don't fail deletion
                'PhysicalResourceId': 'sample-inventory-data',
                'Reason': str(e)
            }
    
    else:
        return {
            'Status': 'SUCCESS',
            'PhysicalResourceId': 'sample-inventory-data'
        }
"""


# CDK App
app = App()

# Create stack
stack = DistributedTransactionProcessingStack(
    app, "DistributedTransactionProcessingStack",
    description="Distributed Transaction Processing with SQS using Saga pattern"
)

# Add stack tags
stack.tags.set_tag("Project", "DistributedTransactionProcessing")
stack.tags.set_tag("Environment", "Development")
stack.tags.set_tag("Recipe", "distributed-transaction-processing-sqs-dynamodb")

app.synth()