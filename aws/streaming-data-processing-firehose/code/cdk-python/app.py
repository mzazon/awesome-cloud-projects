#!/usr/bin/env python3
"""
CDK Python Application for Real-Time Data Processing with Kinesis Data Firehose

This application deploys a complete real-time data processing pipeline using:
- Amazon Kinesis Data Firehose for data streaming
- AWS Lambda for data transformation
- Amazon S3 for data lake storage
- Amazon OpenSearch for real-time analytics
- IAM roles and policies for secure access
- CloudWatch monitoring and alarms

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_kinesisfirehose as firehose,
    aws_opensearch as opensearch,
    aws_cloudwatch as cloudwatch,
    aws_sqs as sqs,
    aws_logs as logs,
)
from constructs import Construct


class RealtimeDataProcessingStack(Stack):
    """
    CDK Stack for Real-Time Data Processing with Kinesis Data Firehose
    
    This stack creates a complete streaming data pipeline with:
    - Kinesis Data Firehose delivery streams
    - Lambda functions for data transformation
    - S3 bucket for data storage
    - OpenSearch domain for real-time search
    - Monitoring and error handling
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        stream_name: str = "realtime-data-stream",
        opensearch_domain_name: str = "firehose-search",
        **kwargs
    ) -> None:
        """
        Initialize the Real-Time Data Processing Stack
        
        Args:
            scope: CDK construct scope
            construct_id: Stack identifier
            stream_name: Base name for Firehose streams
            opensearch_domain_name: Name for OpenSearch domain
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.stream_name = stream_name
        self.opensearch_domain_name = opensearch_domain_name

        # Create resources
        self.s3_bucket = self._create_s3_bucket()
        self.opensearch_domain = self._create_opensearch_domain()
        self.lambda_function = self._create_lambda_function()
        self.firehose_role = self._create_firehose_role()
        self.firehose_s3_stream = self._create_firehose_s3_stream()
        self.firehose_opensearch_stream = self._create_firehose_opensearch_stream()
        self.error_handling = self._create_error_handling()
        self.monitoring = self._create_monitoring()

        # Output important values
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for data storage with optimized configuration
        
        Returns:
            S3 bucket for storing processed data
        """
        bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"firehose-data-bucket-{self.account}-{self.region}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    status=s3.LifecycleRuleStatus.ENABLED,
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

        # Add bucket notification for monitoring
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3.NotificationKeyFilter(prefix="transformed-data/")
        )

        return bucket

    def _create_opensearch_domain(self) -> opensearch.Domain:
        """
        Create OpenSearch domain for real-time search and analytics
        
        Returns:
            OpenSearch domain for indexing streaming data
        """
        domain = opensearch.Domain(
            self,
            "OpenSearchDomain",
            domain_name=self.opensearch_domain_name,
            version=opensearch.EngineVersion.OPENSEARCH_1_3,
            capacity=opensearch.CapacityConfig(
                instance_type="t3.small.search",
                data_nodes=1,
                data_node_instance_type="t3.small.search"
            ),
            ebs=opensearch.EbsOptions(
                enabled=True,
                volume_size=20,
                volume_type=opensearch.EbsVolumeType.GP2
            ),
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=False
            ),
            logging=opensearch.LoggingOptions(
                slow_search_log_enabled=True,
                app_log_enabled=True,
                slow_index_log_enabled=True
            ),
            node_to_node_encryption=True,
            encryption_at_rest=opensearch.EncryptionAtRestOptions(
                enabled=True
            ),
            enforce_https=True,
            removal_policy=RemovalPolicy.DESTROY,
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["es:*"],
                    resources=[f"arn:aws:es:{self.region}:{self.account}:domain/{self.opensearch_domain_name}/*"]
                )
            ]
        )

        return domain

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Create Lambda function for data transformation and enrichment
        
        Returns:
            Lambda function for processing streaming data
        """
        # Create the Lambda function
        lambda_function = _lambda.Function(
            self,
            "TransformFunction",
            function_name=f"firehose-transform-{self.stream_name}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            retry_attempts=2,
            environment={
                "LOG_LEVEL": "INFO",
                "POWERTOOLS_SERVICE_NAME": "firehose-transform"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            architecture=_lambda.Architecture.ARM_64,
            tracing=_lambda.Tracing.ACTIVE
        )

        # Add permissions for CloudWatch Logs
        lambda_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["arn:aws:logs:*:*:*"]
            )
        )

        return lambda_function

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for data transformation
        
        Returns:
            Python code for Lambda function
        """
        return '''
import json
import base64
import boto3
from datetime import datetime
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Transform streaming data records with enrichment and validation
    
    Args:
        event: Kinesis Data Firehose transformation event
        context: Lambda context object
    
    Returns:
        Transformed records for delivery
    """
    output = []
    
    for record in event['records']:
        try:
            # Decode the data
            compressed_payload = base64.b64decode(record['data'])
            uncompressed_payload = compressed_payload.decode('utf-8')
            
            # Parse JSON data
            data = json.loads(uncompressed_payload)
            
            # Add timestamp and processing metadata
            data['processed_timestamp'] = datetime.utcnow().isoformat()
            data['processing_status'] = 'SUCCESS'
            data['lambda_request_id'] = context.aws_request_id
            
            # Enrich data with additional fields
            if 'user_id' in data:
                data['user_category'] = 'registered' if data['user_id'] else 'guest'
            
            if 'amount' in data:
                try:
                    amount_value = float(data['amount'])
                    data['amount_category'] = 'high' if amount_value > 100 else 'low'
                    data['amount_tier'] = get_amount_tier(amount_value)
                except (ValueError, TypeError):
                    data['amount_category'] = 'invalid'
                    data['amount_tier'] = 'unknown'
            
            # Add event categorization
            if 'event_type' in data:
                data['event_category'] = categorize_event(data['event_type'])
            
            # Validate required fields
            if not validate_record(data):
                logger.warning(f"Record validation failed: {data}")
                data['validation_status'] = 'FAILED'
            else:
                data['validation_status'] = 'PASSED'
            
            # Convert back to JSON with newline for proper formatting
            transformed_data = json.dumps(data, ensure_ascii=False) + '\\n'
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'Ok',
                'data': base64.b64encode(transformed_data.encode('utf-8')).decode('utf-8')
            }
            
            logger.info(f"Successfully transformed record {record['recordId']}")
            
        except Exception as e:
            # Handle transformation errors
            logger.error(f"Error processing record {record['recordId']}: {str(e)}")
            
            error_data = {
                'recordId': record['recordId'],
                'error': str(e),
                'error_type': type(e).__name__,
                'original_data': uncompressed_payload,
                'timestamp': datetime.utcnow().isoformat(),
                'processing_status': 'FAILED'
            }
            
            output_record = {
                'recordId': record['recordId'],
                'result': 'ProcessingFailed',
                'data': base64.b64encode(json.dumps(error_data).encode('utf-8')).decode('utf-8')
            }
        
        output.append(output_record)
    
    logger.info(f"Processed {len(output)} records")
    return {'records': output}

def get_amount_tier(amount):
    """Categorize amount into tiers for analytics"""
    if amount < 50:
        return 'small'
    elif amount < 200:
        return 'medium'
    elif amount < 1000:
        return 'large'
    else:
        return 'enterprise'

def categorize_event(event_type):
    """Categorize event types for analytics"""
    commerce_events = ['purchase', 'add_to_cart', 'remove_from_cart', 'checkout']
    engagement_events = ['view', 'click', 'scroll', 'hover']
    
    if event_type in commerce_events:
        return 'commerce'
    elif event_type in engagement_events:
        return 'engagement'
    else:
        return 'other'

def validate_record(data):
    """Validate record has required fields"""
    required_fields = ['event_id', 'timestamp']
    return all(field in data for field in required_fields)
'''

    def _create_firehose_role(self) -> iam.Role:
        """
        Create IAM role for Kinesis Data Firehose with necessary permissions
        
        Returns:
            IAM role for Firehose service
        """
        role = iam.Role(
            self,
            "FirehoseRole",
            role_name=f"FirehoseDeliveryRole-{self.stream_name}",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            description="Role for Kinesis Data Firehose delivery streams"
        )

        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:AbortMultipartUpload",
                    "s3:GetBucketLocation",
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:ListBucketMultipartUploads",
                    "s3:PutObject",
                    "s3:PutObjectAcl"
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*"
                ]
            )
        )

        # Add Lambda permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "lambda:InvokeFunction",
                    "lambda:GetFunctionConfiguration"
                ],
                resources=[self.lambda_function.function_arn]
            )
        )

        # Add OpenSearch permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "es:DescribeElasticsearchDomain",
                    "es:DescribeElasticsearchDomains",
                    "es:DescribeElasticsearchDomainConfig",
                    "es:ESHttpPost",
                    "es:ESHttpPut"
                ],
                resources=[f"{self.opensearch_domain.domain_arn}/*"]
            )
        )

        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["arn:aws:logs:*:*:*"]
            )
        )

        return role

    def _create_firehose_s3_stream(self) -> firehose.CfnDeliveryStream:
        """
        Create Kinesis Data Firehose delivery stream for S3 destination
        
        Returns:
            Firehose delivery stream for S3 storage
        """
        # Create log group for Firehose
        log_group = logs.LogGroup(
            self,
            "FirehoseS3LogGroup",
            log_group_name=f"/aws/kinesisfirehose/{self.stream_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create log stream
        log_stream = logs.LogStream(
            self,
            "FirehoseS3LogStream",
            log_group=log_group,
            log_stream_name="S3Delivery"
        )

        # Configure S3 destination
        s3_destination_configuration = firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
            bucket_arn=self.s3_bucket.bucket_arn,
            role_arn=self.firehose_role.role_arn,
            prefix="transformed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
            error_output_prefix="error-data/",
            buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                size_in_m_bs=5,
                interval_in_seconds=300
            ),
            compression_format="GZIP",
            cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                enabled=True,
                log_group_name=log_group.log_group_name,
                log_stream_name=log_stream.log_stream_name
            )
        )

        # Configure processing (Lambda transformation)
        processing_configuration = firehose.CfnDeliveryStream.ProcessingConfigurationProperty(
            enabled=True,
            processors=[
                firehose.CfnDeliveryStream.ProcessorProperty(
                    type="Lambda",
                    parameters=[
                        firehose.CfnDeliveryStream.ProcessorParameterProperty(
                            parameter_name="LambdaArn",
                            parameter_value=self.lambda_function.function_arn
                        ),
                        firehose.CfnDeliveryStream.ProcessorParameterProperty(
                            parameter_name="BufferSizeInMBs",
                            parameter_value="3"
                        ),
                        firehose.CfnDeliveryStream.ProcessorParameterProperty(
                            parameter_name="BufferIntervalInSeconds",
                            parameter_value="60"
                        )
                    ]
                )
            ]
        )

        # Configure data format conversion to Parquet
        data_format_conversion_configuration = firehose.CfnDeliveryStream.DataFormatConversionConfigurationProperty(
            enabled=True,
            output_format_configuration=firehose.CfnDeliveryStream.OutputFormatConfigurationProperty(
                serializer=firehose.CfnDeliveryStream.SerializerProperty(
                    parquet_ser_de=firehose.CfnDeliveryStream.ParquetSerDeProperty()
                )
            )
        )

        # Update S3 destination with all configurations
        s3_destination_configuration.processing_configuration = processing_configuration
        s3_destination_configuration.data_format_conversion_configuration = data_format_conversion_configuration

        # Create delivery stream
        delivery_stream = firehose.CfnDeliveryStream(
            self,
            "FirehoseS3Stream",
            delivery_stream_name=self.stream_name,
            delivery_stream_type="DirectPut",
            s3_destination_configuration=s3_destination_configuration
        )

        return delivery_stream

    def _create_firehose_opensearch_stream(self) -> firehose.CfnDeliveryStream:
        """
        Create Kinesis Data Firehose delivery stream for OpenSearch destination
        
        Returns:
            Firehose delivery stream for OpenSearch indexing
        """
        # Create log group for OpenSearch stream
        log_group = logs.LogGroup(
            self,
            "FirehoseOpenSearchLogGroup",
            log_group_name=f"/aws/kinesisfirehose/{self.stream_name}-opensearch",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create log stream
        log_stream = logs.LogStream(
            self,
            "FirehoseOpenSearchLogStream",
            log_group=log_group,
            log_stream_name="OpenSearchDelivery"
        )

        # Configure OpenSearch destination
        opensearch_destination_configuration = firehose.CfnDeliveryStream.ElasticsearchDestinationConfigurationProperty(
            domain_arn=self.opensearch_domain.domain_arn,
            role_arn=self.firehose_role.role_arn,
            index_name="realtime-events",
            type_name="_doc",
            index_rotation_period="OneDay",
            buffering_hints=firehose.CfnDeliveryStream.ElasticsearchBufferingHintsProperty(
                size_in_m_bs=1,
                interval_in_seconds=60
            ),
            retry_options=firehose.CfnDeliveryStream.ElasticsearchRetryOptionsProperty(
                duration_in_seconds=3600
            ),
            s3_backup_mode="AllDocuments",
            s3_configuration=firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
                bucket_arn=self.s3_bucket.bucket_arn,
                role_arn=self.firehose_role.role_arn,
                prefix="opensearch-backup/",
                buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                    size_in_m_bs=5,
                    interval_in_seconds=300
                ),
                compression_format="GZIP"
            ),
            processing_configuration=firehose.CfnDeliveryStream.ProcessingConfigurationProperty(
                enabled=True,
                processors=[
                    firehose.CfnDeliveryStream.ProcessorProperty(
                        type="Lambda",
                        parameters=[
                            firehose.CfnDeliveryStream.ProcessorParameterProperty(
                                parameter_name="LambdaArn",
                                parameter_value=self.lambda_function.function_arn
                            )
                        ]
                    )
                ]
            ),
            cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                enabled=True,
                log_group_name=log_group.log_group_name,
                log_stream_name=log_stream.log_stream_name
            )
        )

        # Create delivery stream
        delivery_stream = firehose.CfnDeliveryStream(
            self,
            "FirehoseOpenSearchStream",
            delivery_stream_name=f"{self.stream_name}-opensearch",
            delivery_stream_type="DirectPut",
            elasticsearch_destination_configuration=opensearch_destination_configuration
        )

        return delivery_stream

    def _create_error_handling(self) -> Dict[str, Any]:
        """
        Create error handling infrastructure including DLQ and error processing
        
        Returns:
            Dictionary containing error handling resources
        """
        # Create SQS Dead Letter Queue
        dlq = sqs.Queue(
            self,
            "FirehoseDLQ",
            queue_name=f"{self.stream_name}-dlq",
            visibility_timeout=Duration.minutes(5),
            message_retention_period=Duration.days(14),
            encryption=sqs.QueueEncryption.SQS_MANAGED
        )

        # Create error handling Lambda function
        error_handler = _lambda.Function(
            self,
            "ErrorHandler",
            function_name=f"firehose-error-handler-{self.stream_name}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline('''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """Handle failed records and send to DLQ"""
    sqs = boto3.client('sqs')
    
    for record in event.get('Records', []):
        if record.get('eventName') == 'ERROR':
            # Send failed record to DLQ
            try:
                sqs.send_message(
                    QueueUrl=os.environ['DLQ_URL'],
                    MessageBody=json.dumps({
                        'original_record': record,
                        'error_timestamp': datetime.utcnow().isoformat(),
                        'context': {
                            'request_id': context.aws_request_id,
                            'function_name': context.function_name
                        }
                    })
                )
            except Exception as e:
                print(f"Failed to send message to DLQ: {e}")
    
    return {'statusCode': 200}
            '''),
            timeout=Duration.minutes(1),
            memory_size=128,
            environment={
                'DLQ_URL': dlq.queue_url
            }
        )

        # Grant permissions to send messages to DLQ
        dlq.grant_send_messages(error_handler)

        return {
            'dlq': dlq,
            'error_handler': error_handler
        }

    def _create_monitoring(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for monitoring the data pipeline
        
        Returns:
            Dictionary containing monitoring alarms
        """
        alarms = {}

        # S3 delivery errors alarm
        alarms['s3_delivery_errors'] = cloudwatch.Alarm(
            self,
            "S3DeliveryErrors",
            alarm_name=f"{self.stream_name}-S3-DeliveryErrors",
            alarm_description="Monitor Firehose S3 delivery errors",
            metric=cloudwatch.Metric(
                namespace="AWS/KinesisFirehose",
                metric_name="DeliveryToS3.Records",
                dimensions_map={
                    "DeliveryStreamName": self.stream_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Lambda transformation errors alarm
        alarms['lambda_errors'] = cloudwatch.Alarm(
            self,
            "LambdaErrors",
            alarm_name=f"{self.lambda_function.function_name}-Errors",
            alarm_description="Monitor Lambda transformation errors",
            metric=self.lambda_function.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2
        )

        # OpenSearch delivery errors alarm
        alarms['opensearch_delivery_errors'] = cloudwatch.Alarm(
            self,
            "OpenSearchDeliveryErrors",
            alarm_name=f"{self.stream_name}-OpenSearch-DeliveryErrors",
            alarm_description="Monitor OpenSearch delivery errors",
            metric=cloudwatch.Metric(
                namespace="AWS/KinesisFirehose",
                metric_name="DeliveryToElasticsearch.Records",
                dimensions_map={
                    "DeliveryStreamName": f"{self.stream_name}-opensearch"
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Lambda duration alarm
        alarms['lambda_duration'] = cloudwatch.Alarm(
            self,
            "LambdaDuration",
            alarm_name=f"{self.lambda_function.function_name}-Duration",
            alarm_description="Monitor Lambda function duration",
            metric=self.lambda_function.metric_duration(
                period=Duration.minutes(5)
            ),
            threshold=240000,  # 4 minutes (close to 5 minute timeout)
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2
        )

        return alarms

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        cdk.CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket for storing processed data"
        )

        cdk.CfnOutput(
            self,
            "FirehoseS3StreamName",
            value=self.firehose_s3_stream.delivery_stream_name,
            description="Kinesis Data Firehose stream for S3 delivery"
        )

        cdk.CfnOutput(
            self,
            "FirehoseOpenSearchStreamName",
            value=self.firehose_opensearch_stream.delivery_stream_name,
            description="Kinesis Data Firehose stream for OpenSearch delivery"
        )

        cdk.CfnOutput(
            self,
            "OpenSearchDomainEndpoint",
            value=f"https://{self.opensearch_domain.domain_endpoint}",
            description="OpenSearch domain endpoint for real-time analytics"
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function for data transformation"
        )

        cdk.CfnOutput(
            self,
            "OpenSearchDashboardsUrl",
            value=f"https://{self.opensearch_domain.domain_endpoint}/_dashboards/",
            description="OpenSearch Dashboards URL for data visualization"
        )


# CDK App
app = cdk.App()

# Get configuration from context or environment variables
stream_name = app.node.try_get_context("stream_name") or os.environ.get("STREAM_NAME", "realtime-data-stream")
opensearch_domain_name = app.node.try_get_context("opensearch_domain_name") or os.environ.get("OPENSEARCH_DOMAIN_NAME", "firehose-search")

# Create the stack
RealtimeDataProcessingStack(
    app,
    "RealtimeDataProcessingStack",
    stream_name=stream_name,
    opensearch_domain_name=opensearch_domain_name,
    description="Real-time data processing pipeline with Kinesis Data Firehose",
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION")
    )
)

app.synth()