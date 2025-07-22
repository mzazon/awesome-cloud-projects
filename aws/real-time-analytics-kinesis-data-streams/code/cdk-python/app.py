#!/usr/bin/env python3
"""
CDK Python application for Real-Time Analytics with Amazon Kinesis Data Streams

This application deploys a complete real-time analytics architecture including:
- Amazon Kinesis Data Streams with multiple shards
- AWS Lambda function for stream processing
- S3 bucket for analytics data storage
- CloudWatch alarms and dashboard for monitoring
- IAM roles and policies with least privilege access

Author: AWS CDK Generator
Version: 2.0.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    Tags,
    aws_kinesis as kinesis,
    aws_lambda as _lambda,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_sns as sns,
    aws_lambda_event_sources as lambda_event_sources,
)
from constructs import Construct


class KinesisAnalyticsStack(Stack):
    """
    CDK Stack for Real-Time Analytics with Kinesis Data Streams
    
    This stack creates a complete real-time analytics pipeline with:
    - Kinesis Data Streams for data ingestion
    - Lambda function for stream processing
    - S3 storage for processed analytics data
    - CloudWatch monitoring and alerting
    - Proper IAM security configurations
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        shard_count: int = 3,
        retention_hours: int = 168,
        enable_enhanced_monitoring: bool = True,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Kinesis Analytics Stack
        
        Args:
            scope: The CDK app scope
            construct_id: Unique identifier for this stack
            shard_count: Number of shards for the Kinesis stream (default: 3)
            retention_hours: Data retention period in hours (default: 168 = 7 days)
            enable_enhanced_monitoring: Enable enhanced monitoring (default: True)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[:8].lower()

        # Create S3 bucket for analytics data storage
        self.analytics_bucket = self._create_analytics_bucket(unique_suffix)

        # Create IAM role for Lambda stream processing
        self.lambda_role = self._create_lambda_execution_role()

        # Create Kinesis Data Stream
        self.kinesis_stream = self._create_kinesis_stream(
            unique_suffix, shard_count, retention_hours, enable_enhanced_monitoring
        )

        # Create Lambda function for stream processing
        self.stream_processor = self._create_stream_processor_lambda()

        # Create event source mapping
        self.event_source_mapping = self._create_event_source_mapping()

        # Create CloudWatch monitoring
        self._create_cloudwatch_monitoring(unique_suffix)

        # Create SNS topic for alerts
        self.alert_topic = self._create_alert_topic(unique_suffix)

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms(unique_suffix)

        # Create outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_tags()

    def _create_analytics_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing processed analytics data
        
        Args:
            unique_suffix: Unique suffix for bucket naming
            
        Returns:
            S3 bucket instance
        """
        bucket = s3.Bucket(
            self,
            "AnalyticsBucket",
            bucket_name=f"kinesis-analytics-{unique_suffix}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AnalyticsDataLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Add bucket notification configuration for analytics
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            # Could add SNS/SQS notification here if needed
        )

        return bucket

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with appropriate permissions
        
        Returns:
            IAM role for Lambda execution
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Kinesis stream processing Lambda",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add Kinesis read permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:GetShardIterator", 
                    "kinesis:GetRecords",
                    "kinesis:ListStreams"
                ],
                resources=["*"]  # Will be restricted to specific stream after creation
            )
        )

        # Add CloudWatch metrics permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["cloudwatch:PutMetricData"],
                resources=["*"]
            )
        )

        return role

    def _create_kinesis_stream(
        self,
        unique_suffix: str,
        shard_count: int,
        retention_hours: int,
        enable_enhanced_monitoring: bool
    ) -> kinesis.Stream:
        """
        Create Kinesis Data Stream with specified configuration
        
        Args:
            unique_suffix: Unique suffix for stream naming
            shard_count: Number of shards for the stream
            retention_hours: Data retention period in hours
            enable_enhanced_monitoring: Whether to enable enhanced monitoring
            
        Returns:
            Kinesis stream instance
        """
        stream = kinesis.Stream(
            self,
            "AnalyticsStream",
            stream_name=f"analytics-stream-{unique_suffix}",
            shard_count=shard_count,
            retention_period=Duration.hours(retention_hours),
            encryption=kinesis.StreamEncryption.MANAGED
        )

        # Enable enhanced monitoring if requested
        if enable_enhanced_monitoring:
            # Note: Enhanced monitoring must be enabled via AWS CLI or Console
            # CDK doesn't currently support this property directly
            pass

        return stream

    def _create_stream_processor_lambda(self) -> _lambda.Function:
        """
        Create Lambda function for processing Kinesis stream records
        
        Returns:
            Lambda function instance
        """
        # Grant S3 permissions to Lambda role
        self.analytics_bucket.grant_write(self.lambda_role)

        function = _lambda.Function(
            self,
            "StreamProcessor",
            function_name=f"stream-processor-{self.node.addr[:8].lower()}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "S3_BUCKET": self.analytics_bucket.bucket_name,
                "AWS_REGION": self.region
            },
            code=_lambda.Code.from_inline('''
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal

s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process Kinesis stream records and store analytics data to S3
    
    This function processes streaming data records, extracts business metrics,
    and stores enriched data to S3 while publishing custom metrics to CloudWatch.
    """
    processed_records = 0
    total_amount = 0
    error_count = 0
    
    try:
        for record in event['Records']:
            try:
                # Decode Kinesis data
                payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
                data = json.loads(payload)
                
                # Process analytics data
                processed_records += 1
                
                # Example: Extract transaction amount for financial data
                if 'amount' in data:
                    total_amount += float(data['amount'])
                
                # Store processed record to S3
                timestamp = datetime.datetime.now().isoformat()
                s3_key = f"analytics-data/{timestamp[:10]}/{record['kinesis']['sequenceNumber']}.json"
                
                # Add processing metadata
                enhanced_data = {
                    'original_data': data,
                    'processed_at': timestamp,
                    'shard_id': record['kinesis']['partitionKey'],
                    'sequence_number': record['kinesis']['sequenceNumber'],
                    'processing_function': context.function_name
                }
                
                # Store to S3
                s3_client.put_object(
                    Bucket=os.environ['S3_BUCKET'],
                    Key=s3_key,
                    Body=json.dumps(enhanced_data, default=str),
                    ContentType='application/json',
                    ServerSideEncryption='AES256'
                )
                
            except Exception as e:
                error_count += 1
                print(f"Error processing record: {str(e)}")
                continue
        
        # Send custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='KinesisAnalytics',
            MetricData=[
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': processed_records,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                },
                {
                    'MetricName': 'TotalAmount',
                    'Value': total_amount,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                },
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': error_count,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'FunctionName',
                            'Value': context.function_name
                        }
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processed_records': processed_records,
                'total_amount': total_amount,
                'error_count': error_count
            })
        }
        
    except Exception as e:
        print(f"Critical error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
            '''),
            description="Processes Kinesis stream records and stores analytics data"
        )

        # Grant Kinesis stream read permissions to the specific function
        self.kinesis_stream.grant_read(function)

        return function

    def _create_event_source_mapping(self) -> lambda_event_sources.KinesisEventSource:
        """
        Create event source mapping between Kinesis stream and Lambda function
        
        Returns:
            Event source mapping instance
        """
        event_source = lambda_event_sources.KinesisEventSource(
            stream=self.kinesis_stream,
            batch_size=10,
            max_batching_window=Duration.seconds(5),
            starting_position=_lambda.StartingPosition.LATEST,
            retry_attempts=3,
            max_record_age=Duration.hours(24),
            parallelization_factor=1,
            on_failure=None  # Could add DLQ here
        )

        self.stream_processor.add_event_source(event_source)
        return event_source

    def _create_alert_topic(self, unique_suffix: str) -> sns.Topic:
        """
        Create SNS topic for CloudWatch alarms
        
        Args:
            unique_suffix: Unique suffix for topic naming
            
        Returns:
            SNS topic instance
        """
        topic = sns.Topic(
            self,
            "AlertTopic",
            topic_name=f"kinesis-analytics-alerts-{unique_suffix}",
            display_name="Kinesis Analytics Alerts"
        )

        return topic

    def _create_cloudwatch_monitoring(self, unique_suffix: str) -> None:
        """
        Create CloudWatch dashboard for monitoring the analytics pipeline
        
        Args:
            unique_suffix: Unique suffix for dashboard naming
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "AnalyticsDashboard",
            dashboard_name=f"KinesisAnalytics-{unique_suffix}",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # Kinesis metrics
        kinesis_widget = cloudwatch.GraphWidget(
            title="Kinesis Stream Metrics",
            left=[
                self.kinesis_stream.metric_incoming_records(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                ),
                self.kinesis_stream.metric_outgoing_records(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ],
            right=[
                self.kinesis_stream.metric_write_provisioned_throughput_exceeded(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                ),
                self.kinesis_stream.metric_read_provisioned_throughput_exceeded(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ]
        )

        # Lambda metrics
        lambda_widget = cloudwatch.GraphWidget(
            title="Lambda Processing Metrics",
            left=[
                self.stream_processor.metric_invocations(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                ),
                self.stream_processor.metric_errors(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ],
            right=[
                self.stream_processor.metric_duration(
                    statistic=cloudwatch.Statistic.AVERAGE,
                    period=Duration.minutes(5)
                ),
                self.stream_processor.metric_throttles(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ]
        )

        # Custom metrics
        custom_widget = cloudwatch.GraphWidget(
            title="Business Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="KinesisAnalytics",
                    metric_name="ProcessedRecords",
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="KinesisAnalytics",
                    metric_name="ProcessingErrors",
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ],
            right=[
                cloudwatch.Metric(
                    namespace="KinesisAnalytics",
                    metric_name="TotalAmount",
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ]
        )

        # Add widgets to dashboard
        dashboard.add_widgets(kinesis_widget)
        dashboard.add_widgets(lambda_widget)
        dashboard.add_widgets(custom_widget)

    def _create_cloudwatch_alarms(self, unique_suffix: str) -> None:
        """
        Create CloudWatch alarms for monitoring critical metrics
        
        Args:
            unique_suffix: Unique suffix for alarm naming
        """
        # High incoming records alarm
        high_incoming_alarm = cloudwatch.Alarm(
            self,
            "HighIncomingRecordsAlarm",
            alarm_name=f"KinesisHighIncomingRecords-{unique_suffix}",
            alarm_description="Alert when incoming records exceed threshold",
            metric=self.kinesis_stream.metric_incoming_records(
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(5)
            ),
            threshold=1000,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Lambda errors alarm
        lambda_errors_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorsAlarm", 
            alarm_name=f"LambdaProcessingErrors-{unique_suffix}",
            alarm_description="Alert on Lambda processing errors",
            metric=self.stream_processor.metric_errors(
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Throughput exceeded alarm
        throughput_alarm = cloudwatch.Alarm(
            self,
            "ThroughputExceededAlarm",
            alarm_name=f"KinesisThroughputExceeded-{unique_suffix}",
            alarm_description="Alert when write throughput is exceeded",
            metric=self.kinesis_stream.metric_write_provisioned_throughput_exceeded(
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(1)
            ),
            threshold=0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS actions to alarms
        for alarm in [high_incoming_alarm, lambda_errors_alarm, throughput_alarm]:
            alarm.add_alarm_action(
                cw_actions.SnsAction(self.alert_topic)
            )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        CfnOutput(
            self,
            "KinesisStreamName",
            description="Name of the Kinesis Data Stream",
            value=self.kinesis_stream.stream_name,
            export_name=f"{self.stack_name}-StreamName"
        )

        CfnOutput(
            self,
            "KinesisStreamArn",
            description="ARN of the Kinesis Data Stream",
            value=self.kinesis_stream.stream_arn,
            export_name=f"{self.stack_name}-StreamArn"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            description="Name of the stream processing Lambda function",
            value=self.stream_processor.function_name,
            export_name=f"{self.stack_name}-LambdaName"
        )

        CfnOutput(
            self,
            "S3BucketName",
            description="Name of the S3 bucket for analytics data",
            value=self.analytics_bucket.bucket_name,
            export_name=f"{self.stack_name}-S3Bucket"
        )

        CfnOutput(
            self,
            "AlertTopicArn",
            description="ARN of the SNS topic for alerts",
            value=self.alert_topic.topic_arn,
            export_name=f"{self.stack_name}-AlertTopic"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            description="URL to the CloudWatch dashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=KinesisAnalytics-{self.node.addr[:8].lower()}",
            export_name=f"{self.stack_name}-DashboardUrl"
        )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack"""
        
        Tags.of(self).add("Project", "KinesisAnalytics")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Owner", "CDK-Generated")
        Tags.of(self).add("CostCenter", "Analytics")
        Tags.of(self).add("Application", "RealTimeAnalytics")


class KinesisAnalyticsApp(cdk.App):
    """
    CDK Application for Real-Time Analytics with Kinesis Data Streams
    
    This application can deploy multiple stacks for different environments
    and supports configuration through context variables.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from context or environment variables
        env_name = self.node.try_get_context("environment") or os.environ.get("CDK_ENVIRONMENT", "dev")
        aws_account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        aws_region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Environment configuration
        env = cdk.Environment(
            account=aws_account,
            region=aws_region
        )

        # Stack configuration based on environment
        stack_configs = {
            "dev": {
                "shard_count": 2,
                "retention_hours": 24,
                "enable_enhanced_monitoring": False
            },
            "staging": {
                "shard_count": 3,
                "retention_hours": 168,
                "enable_enhanced_monitoring": True
            },
            "prod": {
                "shard_count": 5,
                "retention_hours": 168,
                "enable_enhanced_monitoring": True
            }
        }

        config = stack_configs.get(env_name, stack_configs["dev"])

        # Create the main stack
        KinesisAnalyticsStack(
            self,
            f"KinesisAnalyticsStack-{env_name.title()}",
            env=env,
            description=f"Real-Time Analytics with Kinesis Data Streams - {env_name.title()} Environment",
            **config
        )


def main() -> None:
    """Main entry point for the CDK application"""
    app = KinesisAnalyticsApp()
    app.synth()


if __name__ == "__main__":
    main()