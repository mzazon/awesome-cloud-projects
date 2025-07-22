#!/usr/bin/env python3
"""
CDK Python Application for Real-Time Data Processing with Amazon Kinesis and Lambda

This application deploys a complete serverless real-time data processing pipeline 
that ingests events through Kinesis Data Streams, processes them with Lambda functions,
and stores results in DynamoDB with comprehensive monitoring and error handling.

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_dynamodb as dynamodb,
    aws_sqs as sqs,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
)
from constructs import Construct


class RealTimeDataProcessingStack(Stack):
    """
    CDK Stack for Real-Time Data Processing with Kinesis and Lambda
    
    This stack creates:
    - Kinesis Data Stream for event ingestion
    - Lambda function for stream processing
    - DynamoDB table for processed data storage
    - SQS Dead Letter Queue for error handling
    - CloudWatch alarms for monitoring
    - SNS topic for notifications (optional)
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.project_name = self.node.try_get_context("project_name") or "retail-events"
        self.environment = self.node.try_get_context("environment") or "dev"
        self.enable_sns_notifications = self.node.try_get_context("enable_sns_notifications") or False
        self.notification_email = self.node.try_get_context("notification_email")

        # Create common tags
        common_tags = {
            "Project": "RetailAnalytics",
            "Environment": self.environment,
            "ManagedBy": "CDK"
        }

        # Apply tags to all resources in this stack
        for key, value in common_tags.items():
            cdk.Tags.of(self).add(key, value)

        # Create infrastructure components
        self.kinesis_stream = self._create_kinesis_stream()
        self.dynamodb_table = self._create_dynamodb_table()
        self.dead_letter_queue = self._create_dead_letter_queue()
        self.lambda_function = self._create_lambda_function()
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()
        
        # Create SNS topic if notifications are enabled
        if self.enable_sns_notifications:
            self.sns_topic = self._create_sns_topic()

        # Create outputs
        self._create_outputs()

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for event ingestion
        
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self,
            "EventStream",
            stream_name=f"{self.project_name}-stream-{self.environment}",
            shard_count=1,  # Start with 1 shard, can be scaled up later
            retention_period=Duration.hours(24),  # Retain data for 24 hours
            stream_mode=kinesis.StreamMode.PROVISIONED,
            removal_policy=RemovalPolicy.DESTROY,  # Allow deletion for dev environments
        )

        # Enable server-side encryption
        stream.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("kinesis.amazonaws.com")],
                actions=["kms:Decrypt", "kms:GenerateDataKey"],
                resources=["*"],
            )
        )

        return stream

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing processed events
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "EventsTable",
            table_name=f"{self.project_name}-data-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="userId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="eventTimestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # Allow deletion for dev environments
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

        # Add Global Secondary Index for querying by event type
        table.add_global_secondary_index(
            index_name="EventTypeIndex",
            partition_key=dynamodb.Attribute(
                name="eventType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="eventTimestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )

        return table

    def _create_dead_letter_queue(self) -> sqs.Queue:
        """
        Create SQS Dead Letter Queue for failed event processing
        
        Returns:
            sqs.Queue: The created SQS queue
        """
        dlq = sqs.Queue(
            self,
            "DeadLetterQueue",
            queue_name=f"{self.project_name}-dlq-{self.environment}",
            retention_period=Duration.days(14),  # Retain failed messages for 14 days
            visibility_timeout=Duration.seconds(30),
            removal_policy=RemovalPolicy.DESTROY,
        )

        return dlq

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for processing Kinesis stream records
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create Lambda execution role with necessary permissions
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
            ],
        )

        # Add permissions for Kinesis, DynamoDB, SQS, and CloudWatch
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:GetRecords",
                    "kinesis:GetShardIterator",
                    "kinesis:ListShards",
                ],
                resources=[self.kinesis_stream.stream_arn],
            )
        )

        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["dynamodb:PutItem", "dynamodb:UpdateItem"],
                resources=[self.dynamodb_table.table_arn],
            )
        )

        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sqs:SendMessage"],
                resources=[self.dead_letter_queue.queue_arn],
            )
        )

        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["cloudwatch:PutMetricData"],
                resources=["*"],
            )
        )

        # Create Lambda function
        lambda_function = lambda_.Function(
            self,
            "EventProcessor",
            function_name=f"{self.project_name}-processor-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.minutes(2),
            memory_size=256,
            environment={
                "DYNAMODB_TABLE": self.dynamodb_table.table_name,
                "DLQ_URL": self.dead_letter_queue.queue_url,
                "LOG_LEVEL": "INFO",
            },
            tracing=lambda_.Tracing.ACTIVE,  # Enable X-Ray tracing
            retry_attempts=2,
            reserved_concurrent_executions=100,  # Limit concurrent executions
        )

        # Create log group with retention
        logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/{lambda_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Add Kinesis event source mapping
        lambda_function.add_event_source(
            lambda_event_sources.KinesisEventSource(
                stream=self.kinesis_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=100,
                max_batching_window=Duration.seconds(5),
                retry_attempts=3,
                max_record_age=Duration.hours(1),
                parallelization_factor=1,
                on_failure=lambda_event_sources.SqsDestination(self.dead_letter_queue),
            )
        )

        return lambda_function

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for monitoring the processing pipeline
        
        Returns:
            Dict[str, cloudwatch.Alarm]: Dictionary of created alarms
        """
        alarms = {}

        # Alarm for failed events
        alarms["failed_events"] = cloudwatch.Alarm(
            self,
            "FailedEventsAlarm",
            alarm_name=f"{self.project_name}-failed-events-{self.environment}",
            alarm_description="Alert when too many events fail processing",
            metric=cloudwatch.Metric(
                namespace="RetailEventProcessing",
                metric_name="FailedEvents",
                statistic="Sum",
            ),
            threshold=10,
            evaluation_periods=1,
            period=Duration.minutes(1),
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Alarm for Lambda errors
        alarms["lambda_errors"] = cloudwatch.Alarm(
            self,
            "LambdaErrorsAlarm",
            alarm_name=f"{self.project_name}-lambda-errors-{self.environment}",
            alarm_description="Alert when Lambda function has high error rate",
            metric=self.lambda_function.metric_errors(
                period=Duration.minutes(5),
                statistic="Sum",
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Alarm for Lambda duration
        alarms["lambda_duration"] = cloudwatch.Alarm(
            self,
            "LambdaDurationAlarm",
            alarm_name=f"{self.project_name}-lambda-duration-{self.environment}",
            alarm_description="Alert when Lambda function duration is high",
            metric=self.lambda_function.metric_duration(
                period=Duration.minutes(5),
                statistic="Average",
            ),
            threshold=Duration.seconds(30).to_milliseconds(),
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Alarm for DLQ message count
        alarms["dlq_messages"] = cloudwatch.Alarm(
            self,
            "DLQMessagesAlarm",
            alarm_name=f"{self.project_name}-dlq-messages-{self.environment}",
            alarm_description="Alert when messages accumulate in DLQ",
            metric=self.dead_letter_queue.metric_approximate_number_of_visible_messages(
                period=Duration.minutes(5),
                statistic="Average",
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        return alarms

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for alarm notifications (optional)
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "AlertTopic",
            topic_name=f"{self.project_name}-alerts-{self.environment}",
            display_name="Real-Time Processing Alerts",
        )

        # Add email subscription if email is provided
        if self.notification_email:
            topic.add_subscription(
                sns.Subscription(
                    self,
                    "EmailSubscription",
                    topic=topic,
                    endpoint=self.notification_email,
                    protocol=sns.SubscriptionProtocol.EMAIL,
                )
            )

        # Add SNS actions to alarms
        for alarm in self.cloudwatch_alarms.values():
            alarm.add_alarm_action(
                cloudwatch.SnsAction(topic)
            )

        return topic

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers"""
        
        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-kinesis-stream-name",
        )

        CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="ARN of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-kinesis-stream-arn",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function",
            export_name=f"{self.stack_name}-lambda-function-name",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function",
            export_name=f"{self.stack_name}-lambda-function-arn",
        )

        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.dynamodb_table.table_name,
            description="Name of the DynamoDB table",
            export_name=f"{self.stack_name}-dynamodb-table-name",
        )

        CfnOutput(
            self,
            "DynamoDBTableArn",
            value=self.dynamodb_table.table_arn,
            description="ARN of the DynamoDB table",
            export_name=f"{self.stack_name}-dynamodb-table-arn",
        )

        CfnOutput(
            self,
            "DeadLetterQueueUrl",
            value=self.dead_letter_queue.queue_url,
            description="URL of the Dead Letter Queue",
            export_name=f"{self.stack_name}-dlq-url",
        )

        if hasattr(self, 'sns_topic'):
            CfnOutput(
                self,
                "SNSTopicArn",
                value=self.sns_topic.topic_arn,
                description="ARN of the SNS topic for notifications",
                export_name=f"{self.stack_name}-sns-topic-arn",
            )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code as a string
        
        Returns:
            str: The Lambda function code
        """
        return '''
import json
import base64
import boto3
import time
import os
import uuid
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
cloudwatch = boto3.client('cloudwatch')
sqs = boto3.client('sqs')

def process_event(event_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process a single event and return enriched results
    
    Args:
        event_data: Raw event data from Kinesis
        
    Returns:
        Dict containing processed event data
    """
    # Extract required fields with defaults
    user_id = event_data.get('userId', 'unknown')
    event_type = event_data.get('eventType', 'unknown')
    product_id = event_data.get('productId', 'unknown')
    timestamp = int(event_data.get('timestamp', int(time.time() * 1000)))
    
    # Calculate event score based on type
    event_scores = {
        'view': 1,
        'add_to_cart': 5,
        'purchase': 10
    }
    event_score = event_scores.get(event_type, 1)
    
    # Generate insight based on event
    actions = {
        'view': 'viewed',
        'add_to_cart': 'added to cart',
        'purchase': 'purchased'
    }
    action = actions.get(event_type, 'interacted with')
    insight = f"User {user_id} {action} product {product_id}"
    
    # Create enriched data structure
    processed_data = {
        'userId': user_id,
        'eventTimestamp': timestamp,
        'eventType': event_type,
        'productId': product_id,
        'eventScore': event_score,
        'insight': insight,
        'processedAt': int(time.time() * 1000),
        'recordId': str(uuid.uuid4()),
        'sessionId': event_data.get('sessionId', str(uuid.uuid4())),
        'userAgent': event_data.get('userAgent', 'unknown'),
        'ipAddress': event_data.get('ipAddress', 'unknown')
    }
    
    return processed_data

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for processing Kinesis stream records
    
    Args:
        event: Lambda event containing Kinesis records
        context: Lambda runtime context
        
    Returns:
        Dict containing processing summary
    """
    processed_count = 0
    failed_count = 0
    failed_records = []
    
    logger.info(f"Processing {len(event['Records'])} records")
    
    # Process each record in the batch
    for record in event['Records']:
        try:
            # Decode and parse the record data
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            event_data = json.loads(payload)
            
            logger.debug(f"Processing event: {event_data}")
            
            # Process the event
            processed_data = process_event(event_data)
            
            # Store result in DynamoDB
            table.put_item(Item=processed_data)
            
            processed_count += 1
            logger.debug(f"Successfully processed record: {processed_data['recordId']}")
            
        except json.JSONDecodeError as e:
            failed_count += 1
            error_msg = f"JSON decode error: {str(e)}"
            logger.error(error_msg)
            failed_records.append({
                'record': record['kinesis']['data'],
                'error': error_msg,
                'error_type': 'JSON_DECODE_ERROR'
            })
            
        except KeyError as e:
            failed_count += 1
            error_msg = f"Missing required field: {str(e)}"
            logger.error(error_msg)
            failed_records.append({
                'record': record['kinesis']['data'],
                'error': error_msg,
                'error_type': 'MISSING_FIELD'
            })
            
        except Exception as e:
            failed_count += 1
            error_msg = f"Unexpected error: {str(e)}"
            logger.error(error_msg)
            failed_records.append({
                'record': record['kinesis']['data'],
                'error': error_msg,
                'error_type': 'PROCESSING_ERROR'
            })
    
    # Send failed records to DLQ
    if failed_records:
        try:
            for failed_record in failed_records:
                sqs.send_message(
                    QueueUrl=os.environ['DLQ_URL'],
                    MessageBody=json.dumps({
                        'error': failed_record['error'],
                        'errorType': failed_record['error_type'],
                        'record': failed_record['record'],
                        'timestamp': datetime.utcnow().isoformat(),
                        'functionName': context.function_name,
                        'requestId': context.aws_request_id
                    })
                )
        except Exception as dlq_error:
            logger.error(f"Error sending to DLQ: {str(dlq_error)}")
    
    # Send custom metrics to CloudWatch
    try:
        cloudwatch.put_metric_data(
            Namespace='RetailEventProcessing',
            MetricData=[
                {
                    'MetricName': 'ProcessedEvents',
                    'Value': processed_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                },
                {
                    'MetricName': 'FailedEvents',
                    'Value': failed_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                },
                {
                    'MetricName': 'ProcessingLatency',
                    'Value': context.get_remaining_time_in_millis(),
                    'Unit': 'Milliseconds',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                }
            ]
        )
    except Exception as metric_error:
        logger.error(f"Error publishing metrics: {str(metric_error)}")
    
    # Log processing summary
    logger.info(f"Processing complete - Processed: {processed_count}, Failed: {failed_count}")
    
    # Return summary for monitoring
    return {
        'statusCode': 200,
        'processed': processed_count,
        'failed': failed_count,
        'total': processed_count + failed_count,
        'requestId': context.aws_request_id
    }
'''


def main():
    """Main function to create and deploy the CDK application"""
    app = cdk.App()
    
    # Get environment from context or use default
    env_name = app.node.try_get_context("environment") or "dev"
    
    # Create the stack
    stack = RealTimeDataProcessingStack(
        app,
        f"RealTimeDataProcessing-{env_name}",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
        description=f"Real-Time Data Processing Stack for {env_name} environment",
    )
    
    # Add additional tags
    cdk.Tags.of(stack).add("Application", "RealTimeDataProcessing")
    cdk.Tags.of(stack).add("Owner", "DataEngineering")
    cdk.Tags.of(stack).add("CostCenter", "Analytics")
    
    app.synth()


if __name__ == "__main__":
    main()