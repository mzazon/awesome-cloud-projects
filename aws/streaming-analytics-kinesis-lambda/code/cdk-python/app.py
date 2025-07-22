#!/usr/bin/env python3
"""
CDK Application for Serverless Real-Time Analytics Pipeline with Kinesis and Lambda

This CDK application deploys a complete serverless real-time analytics pipeline
consisting of:
- Amazon Kinesis Data Streams for data ingestion
- AWS Lambda for stream processing
- Amazon DynamoDB for storing processed results
- CloudWatch monitoring and alarms

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_lambda_event_sources as lambda_event_sources,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class ServerlessRealtimeAnalyticsStack(Stack):
    """
    CDK Stack for deploying a serverless real-time analytics pipeline.
    
    This stack creates all the necessary infrastructure components for processing
    real-time data streams using Kinesis, Lambda, and DynamoDB.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.shard_count = 2
        self.lambda_memory_size = 512
        self.lambda_timeout = Duration.minutes(5)
        self.batch_size = 100
        self.max_batching_window = Duration.seconds(5)

        # Create DynamoDB table for storing analytics results
        self.analytics_table = self._create_dynamodb_table()

        # Create Kinesis Data Stream
        self.kinesis_stream = self._create_kinesis_stream()

        # Create Lambda function for stream processing
        self.processor_function = self._create_lambda_function()

        # Create event source mapping
        self.event_source_mapping = self._create_event_source_mapping()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing processed analytics data.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "AnalyticsTable",
            table_name="analytics-results",
            partition_key=dynamodb.Attribute(
                name="eventId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

        # Add tags
        cdk.Tags.of(table).add("Project", "ServerlessRealtimeAnalytics")
        cdk.Tags.of(table).add("Component", "DataStorage")

        return table

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for data ingestion.
        
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self,
            "AnalyticsStream",
            stream_name="real-time-analytics-stream",
            shard_count=self.shard_count,
            retention_period=Duration.hours(24),
            stream_mode=kinesis.StreamMode.PROVISIONED,
        )

        # Add tags
        cdk.Tags.of(stream).add("Project", "ServerlessRealtimeAnalytics")
        cdk.Tags.of(stream).add("Component", "DataIngestion")

        return stream

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for processing Kinesis stream events.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create Lambda execution role with necessary permissions
        lambda_role = iam.Role(
            self,
            "KinesisLambdaProcessorRole",
            role_name="kinesis-lambda-processor-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add Kinesis permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:DescribeStreamSummary",
                    "kinesis:GetRecords",
                    "kinesis:GetShardIterator",
                    "kinesis:ListShards",
                    "kinesis:ListStreams",
                    "kinesis:SubscribeToShard",
                ],
                resources=[self.kinesis_stream.stream_arn],
            )
        )

        # Add DynamoDB permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=[self.analytics_table.table_arn],
            )
        )

        # Add CloudWatch permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["cloudwatch:PutMetricData"],
                resources=["*"],
            )
        )

        # Create Lambda function
        function = lambda_.Function(
            self,
            "KinesisStreamProcessor",
            function_name="kinesis-stream-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            memory_size=self.lambda_memory_size,
            timeout=self.lambda_timeout,
            environment={
                "DYNAMODB_TABLE": self.analytics_table.table_name,
                "AWS_ACCOUNT_ID": self.account,
                "AWS_REGION": self.region,
            },
            description="Processes Kinesis stream events for real-time analytics",
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Add tags
        cdk.Tags.of(function).add("Project", "ServerlessRealtimeAnalytics")
        cdk.Tags.of(function).add("Component", "StreamProcessing")

        return function

    def _create_event_source_mapping(self) -> lambda_event_sources.KinesisEventSource:
        """
        Create event source mapping between Kinesis and Lambda.
        
        Returns:
            lambda_event_sources.KinesisEventSource: The event source mapping
        """
        event_source = lambda_event_sources.KinesisEventSource(
            stream=self.kinesis_stream,
            batch_size=self.batch_size,
            max_batching_window=self.max_batching_window,
            starting_position=lambda_.StartingPosition.LATEST,
            retry_attempts=3,
            max_record_age=Duration.hours(1),
            bisect_batch_on_error=True,
            parallelization_factor=1,
        )

        # Add event source to Lambda function
        self.processor_function.add_event_source(event_source)

        return event_source

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring the pipeline."""
        
        # Lambda error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "KinesisLambdaProcessorErrors",
            alarm_name="KinesisLambdaProcessorErrors",
            alarm_description="Monitor Lambda processing errors",
            metric=self.processor_function.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

        # DynamoDB throttling alarm
        dynamodb_throttle_alarm = cloudwatch.Alarm(
            self,
            "DynamoDBThrottling",
            alarm_name="DynamoDBThrottling",
            alarm_description="Monitor DynamoDB throttling events",
            metric=self.analytics_table.metric_throttled_requests(
                period=Duration.minutes(5),
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

        # Lambda duration alarm
        lambda_duration_alarm = cloudwatch.Alarm(
            self,
            "KinesisLambdaProcessorDuration",
            alarm_name="KinesisLambdaProcessorDuration",
            alarm_description="Monitor Lambda execution duration",
            metric=self.processor_function.metric_duration(
                period=Duration.minutes(5),
                statistic="Average"
            ),
            threshold=240000,  # 4 minutes (80% of 5-minute timeout)
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Add tags to alarms
        for alarm in [lambda_error_alarm, dynamodb_throttle_alarm, lambda_duration_alarm]:
            cdk.Tags.of(alarm).add("Project", "ServerlessRealtimeAnalytics")
            cdk.Tags.of(alarm).add("Component", "Monitoring")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        
        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-KinesisStreamName",
        )

        CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="ARN of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-KinesisStreamArn",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.processor_function.function_name,
            description="Name of the Lambda processing function",
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.processor_function.function_arn,
            description="ARN of the Lambda processing function",
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )

        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.analytics_table.table_name,
            description="Name of the DynamoDB analytics table",
            export_name=f"{self.stack_name}-DynamoDBTableName",
        )

        CfnOutput(
            self,
            "DynamoDBTableArn",
            value=self.analytics_table.table_arn,
            description="ARN of the DynamoDB analytics table",
            export_name=f"{self.stack_name}-DynamoDBTableArn",
        )

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code as an inline string.
        
        Returns:
            str: The Lambda function code
        """
        return '''
import json
import boto3
import base64
import time
from datetime import datetime
from decimal import Decimal
import os

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Get table reference
table_name = os.environ.get('DYNAMODB_TABLE', 'analytics-results')
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    """
    Process Kinesis stream records and store analytics in DynamoDB
    """
    print(f"Received {len(event['Records'])} records from Kinesis")
    
    processed_records = 0
    failed_records = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload.decode('utf-8'))
            
            # Extract event information
            event_id = record['kinesis']['sequenceNumber']
            timestamp = int(record['kinesis']['approximateArrivalTimestamp'])
            
            # Process the data (example: calculate metrics)
            processed_data = process_analytics_data(data)
            
            # Store in DynamoDB
            store_analytics_result(event_id, timestamp, processed_data, data)
            
            # Send custom metrics to CloudWatch
            send_custom_metrics(processed_data)
            
            processed_records += 1
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            failed_records += 1
            continue
    
    print(f"Successfully processed {processed_records} records, {failed_records} failed")
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed': processed_records,
            'failed': failed_records
        })
    }

def process_analytics_data(data):
    """
    Process incoming data and calculate analytics metrics
    """
    processed = {
        'event_type': data.get('eventType', 'unknown'),
        'user_id': data.get('userId', 'anonymous'),
        'session_id': data.get('sessionId', ''),
        'device_type': data.get('deviceType', 'unknown'),
        'location': data.get('location', {}),
        'metrics': {}
    }
    
    # Calculate custom metrics based on event type
    if data.get('eventType') == 'page_view':
        processed['metrics'] = {
            'page_url': data.get('pageUrl', ''),
            'load_time': data.get('loadTime', 0),
            'bounce_rate': calculate_bounce_rate(data)
        }
    elif data.get('eventType') == 'purchase':
        processed['metrics'] = {
            'amount': Decimal(str(data.get('amount', 0))),
            'currency': data.get('currency', 'USD'),
            'items_count': data.get('itemsCount', 0)
        }
    elif data.get('eventType') == 'user_signup':
        processed['metrics'] = {
            'signup_method': data.get('signupMethod', 'email'),
            'campaign_source': data.get('campaignSource', 'direct')
        }
    
    return processed

def calculate_bounce_rate(data):
    """
    Example calculation for bounce rate analytics
    """
    session_length = data.get('sessionLength', 0)
    pages_viewed = data.get('pagesViewed', 1)
    
    # Simple bounce rate calculation
    if session_length < 30 and pages_viewed == 1:
        return 1.0  # High bounce rate
    else:
        return 0.0  # Low bounce rate

def store_analytics_result(event_id, timestamp, processed_data, raw_data):
    """
    Store processed analytics in DynamoDB
    """
    try:
        table.put_item(
            Item={
                'eventId': event_id,
                'timestamp': timestamp,
                'processedAt': int(time.time()),
                'eventType': processed_data['event_type'],
                'userId': processed_data['user_id'],
                'sessionId': processed_data['session_id'],
                'deviceType': processed_data['device_type'],
                'location': processed_data['location'],
                'metrics': processed_data['metrics'],
                'rawData': raw_data
            }
        )
    except Exception as e:
        print(f"Error storing data in DynamoDB: {str(e)}")
        raise

def send_custom_metrics(processed_data):
    """
    Send custom metrics to CloudWatch
    """
    try:
        # Send event type metrics
        cloudwatch.put_metric_data(
            Namespace='RealTimeAnalytics',
            MetricData=[
                {
                    'MetricName': 'EventsProcessed',
                    'Dimensions': [
                        {
                            'Name': 'EventType',
                            'Value': processed_data['event_type']
                        },
                        {
                            'Name': 'DeviceType',
                            'Value': processed_data['device_type']
                        }
                    ],
                    'Value': 1,
                    'Unit': 'Count'
                }
            ]
        )
        
        # Send purchase metrics if applicable
        if processed_data['event_type'] == 'purchase':
            cloudwatch.put_metric_data(
                Namespace='RealTimeAnalytics',
                MetricData=[
                    {
                        'MetricName': 'PurchaseAmount',
                        'Value': float(processed_data['metrics']['amount']),
                        'Unit': 'None'
                    }
                ]
            )
            
    except Exception as e:
        print(f"Error sending CloudWatch metrics: {str(e)}")
        # Don't raise exception to avoid processing failure
'''


class ServerlessRealtimeAnalyticsApp(cdk.App):
    """
    CDK Application for Serverless Real-Time Analytics Pipeline.
    """

    def __init__(self):
        super().__init__()

        # Get environment variables
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Create the stack
        ServerlessRealtimeAnalyticsStack(
            self,
            "ServerlessRealtimeAnalyticsStack",
            env=cdk.Environment(account=account, region=region),
            description="Serverless real-time analytics pipeline using Kinesis, Lambda, and DynamoDB",
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = ServerlessRealtimeAnalyticsApp()
    app.synth()