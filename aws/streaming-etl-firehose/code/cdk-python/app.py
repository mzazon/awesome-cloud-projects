#!/usr/bin/env python3
"""
CDK Application for Streaming ETL with Kinesis Data Firehose Transformations

This CDK application creates a complete streaming ETL pipeline using:
- Amazon Kinesis Data Firehose for data delivery
- AWS Lambda for real-time data transformation
- Amazon S3 for data storage with Parquet format conversion
- CloudWatch for monitoring and logging

The infrastructure follows AWS best practices for security, scalability, and cost optimization.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_kinesisfirehose as firehose,
    aws_logs as logs,
    CfnOutput,
    Tags,
)
from constructs import Construct


class StreamingEtlStack(Stack):
    """
    CDK Stack for Streaming ETL with Kinesis Data Firehose.
    
    This stack creates:
    - S3 bucket for processed data storage
    - Lambda function for data transformation
    - IAM roles with least privilege permissions
    - Kinesis Data Firehose delivery stream with Lambda processing
    - CloudWatch log groups for monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "dev",
        data_bucket_name: Optional[str] = None,
        lambda_function_name: Optional[str] = None,
        firehose_stream_name: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Streaming ETL Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            environment_name: Environment name (dev, staging, prod)
            data_bucket_name: Optional custom S3 bucket name
            lambda_function_name: Optional custom Lambda function name
            firehose_stream_name: Optional custom Firehose stream name
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names with environment prefix
        self.environment_name = environment_name
        unique_suffix = self.node.addr[-8:].lower()  # Use last 8 chars of node address
        
        self.bucket_name = data_bucket_name or f"streaming-etl-data-{environment_name}-{unique_suffix}"
        self.lambda_name = lambda_function_name or f"firehose-transform-{environment_name}-{unique_suffix}"
        self.stream_name = firehose_stream_name or f"streaming-etl-{environment_name}-{unique_suffix}"

        # Create S3 bucket for data storage
        self.data_bucket = self._create_data_bucket()
        
        # Create Lambda function for data transformation
        self.transform_function = self._create_transform_function()
        
        # Create IAM role for Firehose
        self.firehose_role = self._create_firehose_role()
        
        # Create Kinesis Data Firehose delivery stream
        self.delivery_stream = self._create_delivery_stream()
        
        # Create CloudWatch log group for monitoring
        self.log_group = self._create_log_group()
        
        # Add stack-level tags
        self._add_tags()
        
        # Create stack outputs
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing processed data with security best practices.
        
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=self.bucket_name,
            # Security configurations
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            # Lifecycle management
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ProcessedDataLifecycle",
                    enabled=True,
                    expiration=Duration.days(365),  # Delete after 1 year
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
            ],
            # Versioning for data protection
            versioned=True,
            # Removal policy (use RETAIN for production)
            removal_policy=RemovalPolicy.DESTROY if self.environment_name == "dev" else RemovalPolicy.RETAIN,
            # Auto delete objects for dev environment only
            auto_delete_objects=self.environment_name == "dev"
        )

        # Add bucket notification configuration for monitoring (optional)
        # This can be extended to trigger notifications on object creation
        
        return bucket

    def _create_transform_function(self) -> lambda_.Function:
        """
        Create Lambda function for data transformation with optimized configuration.
        
        Returns:
            Lambda Function construct
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "TransformFunctionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            description="Execution role for Firehose data transformation Lambda function"
        )

        # Lambda function code
        function_code = '''
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
    Transform data records for Kinesis Data Firehose.
    
    This function:
    1. Decodes incoming data records
    2. Parses JSON data
    3. Enriches data with timestamp and metadata
    4. Handles errors gracefully
    5. Returns transformed records in required format
    """
    output = []
    
    logger.info(f"Processing {len(event['records'])} records")
    
    for record in event['records']:
        # Initialize output record with recordId
        output_record = {
            'recordId': record['recordId'],
            'result': 'Ok'
        }
        
        try:
            # Decode the data
            compressed_payload = base64.b64decode(record['data'])
            uncompressed_payload = compressed_payload.decode('utf-8')
            
            # Parse JSON data
            data = json.loads(uncompressed_payload)
            
            # Transform and enrich the data
            transformed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'processed_at': datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S'),
                'event_type': data.get('event_type', 'unknown'),
                'user_id': data.get('user_id', 'anonymous'),
                'session_id': data.get('session_id', ''),
                'page_url': data.get('page_url', ''),
                'referrer': data.get('referrer', ''),
                'user_agent': data.get('user_agent', ''),
                'ip_address': data.get('ip_address', ''),
                # Add enrichment fields
                'is_mobile': 'Mobile' in data.get('user_agent', ''),
                'has_referrer': bool(data.get('referrer', '')),
                'domain': _extract_domain(data.get('page_url', '')),
                'processed_by': 'lambda-firehose-transform',
                'processing_version': '1.0'
            }
            
            # Add newline for proper JSON Lines format
            json_output = json.dumps(transformed_data) + '\\n'
            
            # Encode the transformed data
            output_record['data'] = base64.b64encode(
                json_output.encode('utf-8')
            ).decode('utf-8')
            
            logger.debug(f"Successfully processed record {record['recordId']}")
            
        except json.JSONDecodeError as e:
            logger.error(f"JSON decode error for record {record['recordId']}: {e}")
            output_record['result'] = 'ProcessingFailed'
            
        except Exception as e:
            logger.error(f"Unexpected error processing record {record['recordId']}: {e}")
            output_record['result'] = 'ProcessingFailed'
        
        output.append(output_record)
    
    logger.info(f"Processed {len(output)} records, "
                f"successful: {len([r for r in output if r['result'] == 'Ok'])}, "
                f"failed: {len([r for r in output if r['result'] == 'ProcessingFailed'])}")
    
    return {'records': output}

def _extract_domain(url):
    """Extract domain from URL."""
    try:
        if url.startswith(('http://', 'https://')):
            return url.split('/')[2]
        return ''
    except:
        return ''
'''

        function = lambda_.Function(
            self,
            "TransformFunction",
            function_name=self.lambda_name,
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=lambda_role,
            # Performance and cost optimization
            timeout=Duration.minutes(5),
            memory_size=256,  # Optimized for JSON processing
            reserved_concurrent_executions=50,  # Limit concurrent executions
            # Environment variables
            environment={
                "LOG_LEVEL": "INFO",
                "ENVIRONMENT": self.environment_name
            },
            # Enable detailed monitoring
            tracing=lambda_.Tracing.ACTIVE,
            description="Data transformation function for Kinesis Data Firehose streaming ETL pipeline"
        )

        return function

    def _create_firehose_role(self) -> iam.Role:
        """
        Create IAM role for Kinesis Data Firehose with least privilege permissions.
        
        Returns:
            IAM Role construct
        """
        # Create Firehose service role
        firehose_role = iam.Role(
            self,
            "FirehoseDeliveryRole",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            description="Service role for Kinesis Data Firehose delivery stream"
        )

        # S3 permissions for data delivery
        firehose_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:AbortMultipartUpload",
                    "s3:GetBucketLocation",
                    "s3:GetObject",
                    "s3:ListBucket",
                    "s3:ListBucketMultipartUploads",
                    "s3:PutObject"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )

        # Lambda invoke permissions
        firehose_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[self.transform_function.function_arn]
            )
        )

        # CloudWatch Logs permissions
        firehose_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]  # CloudWatch Logs requires wildcard for log group creation
            )
        )

        # Glue permissions for format conversion (if using Glue catalog)
        firehose_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "glue:GetTable",
                    "glue:GetTableVersion",
                    "glue:GetTableVersions"
                ],
                resources=["*"]  # Glue catalog access
            )
        )

        return firehose_role

    def _create_delivery_stream(self) -> firehose.CfnDeliveryStream:
        """
        Create Kinesis Data Firehose delivery stream with Lambda transformation and S3 delivery.
        
        Returns:
            CloudFormation Delivery Stream construct
        """
        # Define S3 destination configuration
        s3_destination_config = firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
            bucket_arn=self.data_bucket.bucket_arn,
            role_arn=self.firehose_role.role_arn,
            # Partitioning strategy for efficient querying
            prefix="processed-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
            error_output_prefix="error-data/",
            # Buffering configuration for cost optimization
            buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                size_in_m_bs=5,        # 5 MB buffer
                interval_in_seconds=300  # 5 minutes
            ),
            # Compression for storage cost optimization
            compression_format="GZIP",
            # CloudWatch logging
            cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                enabled=True,
                log_group_name=f"/aws/kinesisfirehose/{self.stream_name}",
                log_stream_name="S3Delivery"
            ),
            # Data format conversion to Parquet
            data_format_conversion_configuration=firehose.CfnDeliveryStream.DataFormatConversionConfigurationProperty(
                enabled=True,
                output_format_configuration=firehose.CfnDeliveryStream.OutputFormatConfigurationProperty(
                    serializer=firehose.CfnDeliveryStream.SerializerProperty(
                        parquet_ser_de=firehose.CfnDeliveryStream.ParquetSerDeProperty()
                    )
                ),
                schema_configuration=firehose.CfnDeliveryStream.SchemaConfigurationProperty(
                    database_name="default",
                    table_name="streaming_etl_data",
                    role_arn=self.firehose_role.role_arn
                )
            ),
            # Processing configuration for Lambda transformation
            processing_configuration=firehose.CfnDeliveryStream.ProcessingConfigurationProperty(
                enabled=True,
                processors=[
                    firehose.CfnDeliveryStream.ProcessorProperty(
                        type="Lambda",
                        parameters=[
                            firehose.CfnDeliveryStream.ProcessorParameterProperty(
                                parameter_name="LambdaArn",
                                parameter_value=self.transform_function.function_arn
                            ),
                            firehose.CfnDeliveryStream.ProcessorParameterProperty(
                                parameter_name="BufferSizeInMBs",
                                parameter_value="1"
                            ),
                            firehose.CfnDeliveryStream.ProcessorParameterProperty(
                                parameter_name="BufferIntervalInSeconds",
                                parameter_value="60"
                            )
                        ]
                    )
                ]
            )
        )

        # Create the delivery stream
        delivery_stream = firehose.CfnDeliveryStream(
            self,
            "DeliveryStream",
            delivery_stream_name=self.stream_name,
            delivery_stream_type="DirectPut",
            s3_destination_configuration=s3_destination_config,
            # Tags for resource management
            tags=[
                cdk.CfnTag(key="Environment", value=self.environment_name),
                cdk.CfnTag(key="Application", value="StreamingETL"),
                cdk.CfnTag(key="ManagedBy", value="CDK")
            ]
        )

        # Add dependency to ensure Lambda function is created first
        delivery_stream.add_dependency(self.transform_function.node.default_child)

        return delivery_stream

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for Firehose monitoring.
        
        Returns:
            CloudWatch LogGroup construct
        """
        log_group = logs.LogGroup(
            self,
            "FirehoseLogGroup",
            log_group_name=f"/aws/kinesisfirehose/{self.stream_name}",
            retention=logs.RetentionDays.ONE_MONTH,  # Adjust based on compliance requirements
            removal_policy=RemovalPolicy.DESTROY if self.environment_name == "dev" else RemovalPolicy.RETAIN
        )

        return log_group

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("Application", "StreamingETL")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "Analytics")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket name for processed data storage",
            export_name=f"{self.stack_name}-DataBucketName"
        )

        CfnOutput(
            self,
            "TransformFunctionName",
            value=self.transform_function.function_name,
            description="Lambda function name for data transformation",
            export_name=f"{self.stack_name}-TransformFunctionName"
        )

        CfnOutput(
            self,
            "DeliveryStreamName",
            value=self.delivery_stream.delivery_stream_name or self.stream_name,
            description="Kinesis Data Firehose delivery stream name",
            export_name=f"{self.stack_name}-DeliveryStreamName"
        )

        CfnOutput(
            self,
            "FirehoseRoleArn",
            value=self.firehose_role.role_arn,
            description="IAM role ARN for Firehose delivery stream",
            export_name=f"{self.stack_name}-FirehoseRoleArn"
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for Firehose monitoring",
            export_name=f"{self.stack_name}-LogGroupName"
        )


def create_app() -> App:
    """
    Create and configure the CDK application.
    
    Returns:
        CDK App instance
    """
    app = App()

    # Get environment configuration from context or environment variables
    environment_name = app.node.try_get_context("environment") or os.environ.get("ENVIRONMENT", "dev")
    
    # Get AWS account and region
    account = os.environ.get("CDK_DEFAULT_ACCOUNT") or app.node.try_get_context("account")
    region = os.environ.get("CDK_DEFAULT_REGION") or app.node.try_get_context("region")

    # Create environment configuration
    env = Environment(account=account, region=region) if account and region else None

    # Create the streaming ETL stack
    streaming_etl_stack = StreamingEtlStack(
        app,
        f"StreamingEtlStack-{environment_name}",
        environment_name=environment_name,
        env=env,
        description=f"Streaming ETL pipeline with Kinesis Data Firehose and Lambda transformations ({environment_name})",
        # Stack-level tags
        tags={
            "Project": "StreamingETL",
            "Environment": environment_name,
            "ManagedBy": "CDK"
        }
    )

    return app


# CDK App entry point
if __name__ == "__main__":
    app = create_app()
    app.synth()