#!/usr/bin/env python3
"""
Advanced DynamoDB Streaming Architectures with Global Tables
CDK Python Application

This CDK application deploys a sophisticated DynamoDB Global Tables architecture
with advanced streaming capabilities using both DynamoDB Streams and Kinesis Data Streams.
"""

import os
from typing import Dict, List

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    RemovalPolicy,
    Duration,
    aws_dynamodb as dynamodb,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_events as events,
    aws_cloudwatch as cloudwatch,
    aws_lambda_event_sources as lambda_events,
    aws_logs as logs,
)
from constructs import Construct


class DynamoDBStreamingStack(Stack):
    """
    Stack that creates DynamoDB Global Tables with comprehensive streaming architecture.
    
    This stack includes:
    - Multi-region DynamoDB Global Tables with streams
    - Kinesis Data Streams for analytics
    - Lambda functions for stream processing
    - CloudWatch dashboards and monitoring
    - EventBridge integration for business events
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        table_name: str,
        stream_name: str,
        enable_global_tables: bool = True,
        replica_regions: List[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.table_name = table_name
        self.stream_name = stream_name
        self.replica_regions = replica_regions or ["eu-west-1", "ap-southeast-1"]
        
        # Create core infrastructure
        self.table = self._create_dynamodb_table()
        self.kinesis_stream = self._create_kinesis_stream()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create Lambda functions
        self.stream_processor = self._create_stream_processor_lambda()
        self.kinesis_processor = self._create_kinesis_processor_lambda()
        
        # Configure event source mappings
        self._configure_event_source_mappings()
        
        # Create monitoring and dashboard
        self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table with streams and Global Secondary Index.
        
        Returns:
            DynamoDB table with comprehensive configuration for e-commerce use case
        """
        table = dynamodb.Table(
            self,
            "ECommerceTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="PK",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="SK",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            table_class=dynamodb.TableClass.STANDARD,
        )

        # Add Global Secondary Index for alternate access patterns
        table.add_global_secondary_index(
            index_name="GSI1",
            partition_key=dynamodb.Attribute(
                name="GSI1PK",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="GSI1SK",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )

        # Add tags for resource management
        cdk.Tags.of(table).add("Application", "ECommerce")
        cdk.Tags.of(table).add("Environment", "Production")
        cdk.Tags.of(table).add("Purpose", "GlobalTables")

        return table

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for analytics and extended retention.
        
        Returns:
            Kinesis stream configured for high-throughput analytics
        """
        stream = kinesis.Stream(
            self,
            "ECommerceKinesisStream",
            stream_name=self.stream_name,
            shard_count=3,
            retention_period=Duration.days(7),  # Extended retention for analytics
            stream_mode=kinesis.StreamMode.PROVISIONED,
        )

        # Enable enhanced monitoring
        stream.metric_incoming_records().create_alarm(
            self,
            "HighIncomingRecords",
            threshold=10000,
            evaluation_periods=2,
        )

        cdk.Tags.of(stream).add("Application", "ECommerce")
        cdk.Tags.of(stream).add("Purpose", "Analytics")

        return stream

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution with necessary permissions.
        
        Returns:
            IAM role with permissions for DynamoDB, Kinesis, EventBridge, and CloudWatch
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add custom policy for DynamoDB Streams
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:DescribeStream",
                    "dynamodb:GetRecords",
                    "dynamodb:GetShardIterator",
                    "dynamodb:ListStreams",
                ],
                resources=[f"{self.table.table_arn}/stream/*"],
            )
        )

        # Add permissions for Kinesis
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:GetRecords",
                    "kinesis:GetShardIterator",
                    "kinesis:ListStreams",
                    "kinesis:PutRecord",
                    "kinesis:PutRecords",
                ],
                resources=[self.kinesis_stream.stream_arn],
            )
        )

        # Add permissions for EventBridge
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "events:PutEvents",
                ],
                resources=["*"],
            )
        )

        # Add permissions for CloudWatch Metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_stream_processor_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for processing DynamoDB Streams.
        
        Returns:
            Lambda function configured for DynamoDB Streams processing
        """
        function = lambda_.Function(
            self,
            "StreamProcessor",
            function_name=f"{self.table_name}-stream-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_stream_processor_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "TABLE_NAME": self.table_name,
                "REGION": self.region,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            dead_letter_queue_enabled=True,
            reserved_concurrent_executions=10,
        )

        return function

    def _create_kinesis_processor_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for processing Kinesis Data Streams.
        
        Returns:
            Lambda function configured for Kinesis analytics processing
        """
        function = lambda_.Function(
            self,
            "KinesisProcessor",
            function_name=f"{self.stream_name}-kinesis-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_kinesis_processor_code()),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "STREAM_NAME": self.stream_name,
                "REGION": self.region,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            dead_letter_queue_enabled=True,
            reserved_concurrent_executions=10,
        )

        return function

    def _configure_event_source_mappings(self) -> None:
        """Configure event source mappings for both DynamoDB Streams and Kinesis."""
        
        # DynamoDB Streams event source mapping
        self.stream_processor.add_event_source(
            lambda_events.DynamoEventSource(
                table=self.table,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
                retry_attempts=3,
                parallelization_factor=1,
                report_batch_item_failures=True,
            )
        )

        # Kinesis Data Streams event source mapping
        self.kinesis_processor.add_event_source(
            lambda_events.KinesisEventSource(
                stream=self.kinesis_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=100,
                max_batching_window=Duration.seconds(10),
                parallelization_factor=2,
                retry_attempts=3,
                report_batch_item_failures=True,
            )
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring the global streaming architecture.
        
        Returns:
            CloudWatch dashboard with comprehensive metrics
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "ECommerceGlobalDashboard",
            dashboard_name="ECommerce-Global-Monitoring",
        )

        # DynamoDB metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="DynamoDB Capacity Consumption",
                left=[
                    self.table.metric_consumed_read_capacity_units(),
                    self.table.metric_consumed_write_capacity_units(),
                ],
                width=12,
                height=6,
            )
        )

        # Kinesis metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Kinesis Stream Metrics",
                left=[
                    self.kinesis_stream.metric_incoming_records(),
                    self.kinesis_stream.metric_outgoing_records(),
                ],
                width=12,
                height=6,
            )
        )

        # Lambda metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Performance",
                left=[
                    self.stream_processor.metric_invocations(),
                    self.stream_processor.metric_errors(),
                    self.kinesis_processor.metric_invocations(),
                    self.kinesis_processor.metric_errors(),
                ],
                width=12,
                height=6,
            )
        )

        # Custom business metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Business Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="ECommerce/Global",
                        metric_name="NewOrders",
                        dimensions_map={"EntityType": "Order"},
                    ),
                    cloudwatch.Metric(
                        namespace="ECommerce/Global",
                        metric_name="InventoryChange",
                        dimensions_map={"EntityType": "Product"},
                    ),
                ],
                width=12,
                height=6,
            )
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        
        cdk.CfnOutput(
            self,
            "TableName",
            value=self.table.table_name,
            description="DynamoDB table name for the e-commerce application",
        )

        cdk.CfnOutput(
            self,
            "TableArn",
            value=self.table.table_arn,
            description="DynamoDB table ARN",
        )

        cdk.CfnOutput(
            self,
            "StreamArn",
            value=self.table.table_stream_arn or "",
            description="DynamoDB Streams ARN",
        )

        cdk.CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Kinesis Data Stream name",
        )

        cdk.CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="Kinesis Data Stream ARN",
        )

        cdk.CfnOutput(
            self,
            "StreamProcessorFunction",
            value=self.stream_processor.function_name,
            description="DynamoDB Stream processor Lambda function name",
        )

        cdk.CfnOutput(
            self,
            "KinesisProcessorFunction",
            value=self.kinesis_processor.function_name,
            description="Kinesis Stream processor Lambda function name",
        )

    def _get_stream_processor_code(self) -> str:
        """
        Return the Lambda function code for DynamoDB Streams processing.
        
        Returns:
            Python code as string for stream processing
        """
        return '''
import json
import boto3
import os
from decimal import Decimal
from typing import Dict, Any, List

dynamodb = boto3.resource('dynamodb')
eventbridge = boto3.client('events')
cloudwatch = boto3.client('cloudwatch')

def decimal_default(obj):
    """JSON serializer for Decimal objects."""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process DynamoDB Streams records for real-time business logic.
    
    Args:
        event: DynamoDB Streams event
        context: Lambda context
        
    Returns:
        Response with processing status
    """
    try:
        processed_records = 0
        failed_records = []
        
        for record in event['Records']:
            try:
                if record['eventName'] in ['INSERT', 'MODIFY', 'REMOVE']:
                    process_record(record)
                    processed_records += 1
            except Exception as e:
                print(f"Error processing record {record.get('eventID', 'unknown')}: {str(e)}")
                failed_records.append(record.get('eventID', 'unknown'))
        
        print(f"Successfully processed {processed_records} records")
        if failed_records:
            print(f"Failed to process {len(failed_records)} records: {failed_records}")
            
        return {
            'statusCode': 200,
            'batchItemFailures': [{'itemIdentifier': record_id} for record_id in failed_records]
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        raise

def process_record(record: Dict[str, Any]) -> None:
    """Process individual DynamoDB Stream record."""
    event_name = record['eventName']
    table_name = record['eventSourceARN'].split('/')[-3]
    
    # Extract item data
    if 'NewImage' in record['dynamodb']:
        new_image = record['dynamodb']['NewImage']
        pk = new_image.get('PK', {}).get('S', '')
        
        # Process different entity types
        if pk.startswith('PRODUCT#'):
            process_product_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))
        elif pk.startswith('ORDER#'):
            process_order_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))
        elif pk.startswith('USER#'):
            process_user_event(event_name, new_image, record.get('dynamodb', {}).get('OldImage'))

def process_product_event(event_name: str, new_image: Dict[str, Any], old_image: Dict[str, Any] = None) -> None:
    """Process product-related events."""
    if event_name == 'MODIFY' and old_image:
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        
        if old_stock != new_stock:
            send_inventory_alert(new_image, old_stock, new_stock)
            send_inventory_metric(new_image, old_stock, new_stock)

def process_order_event(event_name: str, new_image: Dict[str, Any], old_image: Dict[str, Any] = None) -> None:
    """Process order-related events."""
    if event_name == 'INSERT':
        send_order_notification(new_image)
        send_order_metric(new_image)
    elif event_name == 'MODIFY' and old_image:
        status_changed = check_order_status_change(new_image, old_image)
        if status_changed:
            send_status_update(new_image)

def process_user_event(event_name: str, new_image: Dict[str, Any], old_image: Dict[str, Any] = None) -> None:
    """Process user-related events."""
    if event_name == 'MODIFY':
        send_user_activity_event(new_image)

def send_inventory_alert(product: Dict[str, Any], old_stock: int, new_stock: int) -> None:
    """Send inventory change alert to EventBridge."""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.inventory',
                'DetailType': 'Inventory Change',
                'Detail': json.dumps({
                    'productId': product.get('PK', {}).get('S', ''),
                    'oldStock': old_stock,
                    'newStock': new_stock,
                    'timestamp': product.get('UpdatedAt', {}).get('S', ''),
                    'region': os.environ.get('REGION', 'unknown')
                }, default=decimal_default)
            }]
        )
    except Exception as e:
        print(f"Error sending inventory alert: {str(e)}")

def send_order_notification(order: Dict[str, Any]) -> None:
    """Send new order notification to EventBridge."""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.orders',
                'DetailType': 'New Order',
                'Detail': json.dumps({
                    'orderId': order.get('PK', {}).get('S', ''),
                    'customerId': order.get('CustomerId', {}).get('S', ''),
                    'amount': order.get('TotalAmount', {}).get('N', ''),
                    'timestamp': order.get('CreatedAt', {}).get('S', ''),
                    'region': os.environ.get('REGION', 'unknown')
                }, default=decimal_default)
            }]
        )
    except Exception as e:
        print(f"Error sending order notification: {str(e)}")

def send_status_update(order: Dict[str, Any]) -> None:
    """Send order status update to EventBridge."""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.orders',
                'DetailType': 'Order Status Update',
                'Detail': json.dumps({
                    'orderId': order.get('PK', {}).get('S', ''),
                    'status': order.get('Status', {}).get('S', ''),
                    'timestamp': order.get('UpdatedAt', {}).get('S', ''),
                    'region': os.environ.get('REGION', 'unknown')
                }, default=decimal_default)
            }]
        )
    except Exception as e:
        print(f"Error sending status update: {str(e)}")

def send_user_activity_event(user: Dict[str, Any]) -> None:
    """Send user activity event to EventBridge."""
    try:
        eventbridge.put_events(
            Entries=[{
                'Source': 'ecommerce.users',
                'DetailType': 'User Activity',
                'Detail': json.dumps({
                    'userId': user.get('PK', {}).get('S', ''),
                    'lastActive': user.get('LastActiveAt', {}).get('S', ''),
                    'timestamp': user.get('UpdatedAt', {}).get('S', ''),
                    'region': os.environ.get('REGION', 'unknown')
                }, default=decimal_default)
            }]
        )
    except Exception as e:
        print(f"Error sending user activity event: {str(e)}")

def send_inventory_metric(product: Dict[str, Any], old_stock: int, new_stock: int) -> None:
    """Send inventory change metrics to CloudWatch."""
    try:
        stock_change = new_stock - old_stock
        change_type = 'Increase' if stock_change > 0 else 'Decrease'
        
        cloudwatch.put_metric_data(
            Namespace='ECommerce/Global',
            MetricData=[{
                'MetricName': 'InventoryChange',
                'Value': abs(stock_change),
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Product'},
                    {'Name': 'ChangeType', 'Value': change_type}
                ]
            }]
        )
    except Exception as e:
        print(f"Error sending inventory metric: {str(e)}")

def send_order_metric(order: Dict[str, Any]) -> None:
    """Send order metrics to CloudWatch."""
    try:
        amount = float(order.get('TotalAmount', {}).get('N', '0'))
        
        cloudwatch.put_metric_data(
            Namespace='ECommerce/Global',
            MetricData=[
                {
                    'MetricName': 'NewOrders',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
                },
                {
                    'MetricName': 'OrderValue',
                    'Value': amount,
                    'Unit': 'None',
                    'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
                }
            ]
        )
    except Exception as e:
        print(f"Error sending order metric: {str(e)}")

def check_order_status_change(new_image: Dict[str, Any], old_image: Dict[str, Any]) -> bool:
    """Check if order status has changed."""
    if not old_image:
        return False
    old_status = old_image.get('Status', {}).get('S', '')
    new_status = new_image.get('Status', {}).get('S', '')
    return old_status != new_status
'''

    def _get_kinesis_processor_code(self) -> str:
        """
        Return the Lambda function code for Kinesis Data Streams processing.
        
        Returns:
            Python code as string for analytics processing
        """
        return '''
import json
import boto3
import base64
from datetime import datetime
from typing import Dict, Any, List

cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis Data Streams records for analytics and monitoring.
    
    Args:
        event: Kinesis event
        context: Lambda context
        
    Returns:
        Response with processing status
    """
    try:
        metrics_data = []
        processed_records = 0
        failed_records = []
        
        for record in event['Records']:
            try:
                # Decode Kinesis data
                payload = json.loads(base64.b64decode(record['kinesis']['data']))
                
                # Extract metrics based on event type
                if payload.get('eventName') == 'INSERT':
                    process_insert_metrics(payload, metrics_data)
                elif payload.get('eventName') == 'MODIFY':
                    process_modify_metrics(payload, metrics_data)
                elif payload.get('eventName') == 'REMOVE':
                    process_remove_metrics(payload, metrics_data)
                
                processed_records += 1
                
            except Exception as e:
                print(f"Error processing record: {str(e)}")
                failed_records.append(record.get('kinesis', {}).get('sequenceNumber', 'unknown'))
        
        # Send aggregated metrics to CloudWatch
        if metrics_data:
            send_metrics(metrics_data)
        
        print(f"Successfully processed {processed_records} records")
        if failed_records:
            print(f"Failed to process {len(failed_records)} records")
            
        return {
            'statusCode': 200,
            'body': f'Processed {processed_records} records',
            'batchItemFailures': [{'itemIdentifier': record_id} for record_id in failed_records]
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        raise

def process_insert_metrics(payload: Dict[str, Any], metrics_data: List[Dict[str, Any]]) -> None:
    """Process INSERT events for metrics."""
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        amount = float(new_image.get('TotalAmount', {}).get('N', '0'))
        metrics_data.extend([
            {
                'MetricName': 'NewOrders',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
            },
            {
                'MetricName': 'OrderValue',
                'Value': amount,
                'Unit': 'None',
                'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
            }
        ])
    elif pk.startswith('PRODUCT#'):
        metrics_data.append({
            'MetricName': 'NewProducts',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Product'}]
        })
    elif pk.startswith('USER#'):
        metrics_data.append({
            'MetricName': 'NewUsers',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'User'}]
        })

def process_modify_metrics(payload: Dict[str, Any], metrics_data: List[Dict[str, Any]]) -> None:
    """Process MODIFY events for metrics."""
    dynamodb_data = payload.get('dynamodb', {})
    new_image = dynamodb_data.get('NewImage', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = new_image.get('PK', {}).get('S', '')
    
    if pk.startswith('PRODUCT#') and old_image:
        # Track inventory changes
        old_stock = int(old_image.get('Stock', {}).get('N', '0'))
        new_stock = int(new_image.get('Stock', {}).get('N', '0'))
        stock_change = new_stock - old_stock
        
        if stock_change != 0:
            change_type = 'Increase' if stock_change > 0 else 'Decrease'
            metrics_data.append({
                'MetricName': 'InventoryChange',
                'Value': abs(stock_change),
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Product'},
                    {'Name': 'ChangeType', 'Value': change_type}
                ]
            })
            
            # Track low stock alerts
            if new_stock <= 10:  # Low stock threshold
                metrics_data.append({
                    'MetricName': 'LowStockAlert',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [{'Name': 'EntityType', 'Value': 'Product'}]
                })
                
    elif pk.startswith('ORDER#') and old_image:
        # Track order status changes
        old_status = old_image.get('Status', {}).get('S', '')
        new_status = new_image.get('Status', {}).get('S', '')
        
        if old_status != new_status:
            metrics_data.append({
                'MetricName': 'OrderStatusChange',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EntityType', 'Value': 'Order'},
                    {'Name': 'FromStatus', 'Value': old_status},
                    {'Name': 'ToStatus', 'Value': new_status}
                ]
            })
            
    elif pk.startswith('USER#'):
        # Track user activity
        metrics_data.append({
            'MetricName': 'UserActivity',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'User'}]
        })

def process_remove_metrics(payload: Dict[str, Any], metrics_data: List[Dict[str, Any]]) -> None:
    """Process REMOVE events for metrics."""
    dynamodb_data = payload.get('dynamodb', {})
    old_image = dynamodb_data.get('OldImage', {})
    pk = old_image.get('PK', {}).get('S', '')
    
    if pk.startswith('ORDER#'):
        metrics_data.append({
            'MetricName': 'CancelledOrders',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Order'}]
        })
    elif pk.startswith('PRODUCT#'):
        metrics_data.append({
            'MetricName': 'DeletedProducts',
            'Value': 1,
            'Unit': 'Count',
            'Dimensions': [{'Name': 'EntityType', 'Value': 'Product'}]
        })

def send_metrics(metrics_data: List[Dict[str, Any]]) -> None:
    """Send metrics to CloudWatch."""
    try:
        # CloudWatch has a limit of 20 metrics per call
        batch_size = 20
        for i in range(0, len(metrics_data), batch_size):
            batch = metrics_data[i:i + batch_size]
            
            cloudwatch.put_metric_data(
                Namespace='ECommerce/Global',
                MetricData=[{
                    **metric,
                    'Timestamp': datetime.utcnow()
                } for metric in batch]
            )
            
        print(f"Successfully sent {len(metrics_data)} metrics to CloudWatch")
        
    except Exception as e:
        print(f"Error sending metrics to CloudWatch: {str(e)}")
        raise
'''


class MultiRegionGlobalTablesApp(cdk.App):
    """
    CDK Application for deploying DynamoDB Global Tables across multiple regions.
    
    This application creates the infrastructure in multiple regions to demonstrate
    the full Global Tables architecture with streaming capabilities.
    """

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Configuration
        table_name = self.node.try_get_context("table_name") or "ecommerce-global-demo"
        stream_name = self.node.try_get_context("stream_name") or "ecommerce-events-demo"
        primary_region = self.node.try_get_context("primary_region") or "us-east-1"
        replica_regions = self.node.try_get_context("replica_regions") or ["eu-west-1", "ap-southeast-1"]

        # Deploy primary stack
        primary_stack = DynamoDBStreamingStack(
            self,
            f"DynamoDBStreamingStack-{primary_region}",
            table_name=table_name,
            stream_name=stream_name,
            replica_regions=replica_regions,
            env=Environment(region=primary_region),
        )

        # Deploy replica stacks (for demonstration - Global Tables are created automatically)
        for region in replica_regions:
            replica_stack = DynamoDBStreamingStack(
                self,
                f"DynamoDBStreamingStack-{region}",
                table_name=table_name,
                stream_name=stream_name,
                replica_regions=replica_regions,
                env=Environment(region=region),
            )

            # Add dependency to ensure primary is created first
            replica_stack.add_dependency(primary_stack)


# Create the app
app = MultiRegionGlobalTablesApp()

# Add global tags
cdk.Tags.of(app).add("Project", "AdvancedDynamoDBStreaming")
cdk.Tags.of(app).add("Owner", "DevOps-Team")
cdk.Tags.of(app).add("CostCenter", "Engineering")

# Synthesize the app
app.synth()