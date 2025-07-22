"""
Real-time Data Processing Stack

This stack creates a serverless real-time data processing pipeline using:
- Amazon Kinesis Data Stream for ingesting streaming data
- AWS Lambda function for processing records
- S3 bucket for storing processed data
- IAM roles with least privilege access
- CloudWatch monitoring
"""

from typing import Dict, Any
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
)
from constructs import Construct


class RealTimeDataProcessingStack(Stack):
    """
    CDK Stack for Real-time Data Processing with Kinesis and Lambda
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get context values with defaults
        stream_name = self.node.try_get_context("stream_name") or "realtime-data-stream"
        shard_count = self.node.try_get_context("shard_count") or 3
        lambda_timeout = self.node.try_get_context("lambda_timeout") or 60
        lambda_memory = self.node.try_get_context("lambda_memory") or 256
        batch_size = self.node.try_get_context("batch_size") or 100
        max_batching_window = self.node.try_get_context("max_batching_window") or 5

        # Create S3 bucket for processed data
        self.processed_data_bucket = self._create_s3_bucket()

        # Create Kinesis Data Stream
        self.kinesis_stream = self._create_kinesis_stream(stream_name, shard_count)

        # Create Lambda execution role
        self.lambda_role = self._create_lambda_role()

        # Create Lambda function for processing
        self.processor_function = self._create_lambda_function(
            timeout=lambda_timeout,
            memory_size=lambda_memory
        )

        # Create event source mapping
        self.event_source_mapping = self._create_event_source_mapping(
            batch_size=batch_size,
            max_batching_window=max_batching_window
        )

        # Create CloudWatch log group with retention
        self._create_log_group()

        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing processed data with versioning and lifecycle policies.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "ProcessedDataBucket",
            bucket_name=f"processed-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo cleanup
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                    expiration=Duration.days(365)
                ),
                s3.LifecycleRule(
                    id="TransitionToIA",
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

        return bucket

    def _create_kinesis_stream(self, stream_name: str, shard_count: int) -> kinesis.Stream:
        """
        Create Kinesis Data Stream with specified number of shards.
        
        Args:
            stream_name: Name of the Kinesis stream
            shard_count: Number of shards for the stream
            
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self,
            "KinesisStream",
            stream_name=stream_name,
            shard_count=shard_count,
            retention_period=Duration.hours(24),  # Default retention
            encryption=kinesis.StreamEncryption.KMS,  # Server-side encryption
        )

        return stream

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege access.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Kinesis data processing Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaKinesisExecutionRole"),
            ]
        )

        # Add specific permissions for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:PutObjectAcl",
                    "s3:GetObject",
                    "s3:DeleteObject"
                ],
                resources=[
                    self.processed_data_bucket.bucket_arn,
                    f"{self.processed_data_bucket.bucket_arn}/*"
                ]
            )
        )

        return role

    def _create_lambda_function(self, timeout: int, memory_size: int) -> lambda_.Function:
        """
        Create Lambda function for processing Kinesis records.
        
        Args:
            timeout: Function timeout in seconds
            memory_size: Memory allocation in MB
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Lambda function code
        lambda_code = '''
import json
import base64
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['S3_BUCKET_NAME']

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis records and store processed data in S3
    """
    processed_records = []
    
    for record in event['Records']:
        try:
            # Decode the Kinesis record data
            kinesis_data = record['kinesis']
            encoded_data = kinesis_data['data']
            decoded_data = base64.b64decode(encoded_data).decode('utf-8')
            
            # Parse the JSON data
            try:
                json_data = json.loads(decoded_data)
            except json.JSONDecodeError:
                # If not JSON, treat as plain text
                json_data = {"message": decoded_data}
                
            # Add processing metadata
            processed_record = {
                "original_data": json_data,
                "processing_timestamp": datetime.utcnow().isoformat(),
                "partition_key": kinesis_data['partitionKey'],
                "sequence_number": kinesis_data['sequenceNumber'],
                "event_id": record['eventID'],
                "processed": True
            }
            
            processed_records.append(processed_record)
            
            print(f"Processed record with EventID: {record['eventID']}")
            
        except Exception as e:
            print(f"Error processing record {record.get('eventID', 'unknown')}: {str(e)}")
            continue
    
    # Store processed records in S3
    if processed_records:
        try:
            s3_key = f"processed-data/{datetime.utcnow().strftime('%Y/%m/%d/%H')}/batch-{context.aws_request_id}.json"
            
            s3_client.put_object(
                Bucket=BUCKET_NAME,
                Key=s3_key,
                Body=json.dumps(processed_records, indent=2),
                ContentType='application/json'
            )
            
            print(f"Successfully stored {len(processed_records)} processed records to S3: {s3_key}")
            
        except Exception as e:
            print(f"Error storing data to S3: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'processed_count': len(processed_records),
            'message': 'Successfully processed Kinesis records'
        })
    }
'''

        function = lambda_.Function(
            self,
            "KinesisDataProcessor",
            function_name="kinesis-data-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(timeout),
            memory_size=memory_size,
            role=self.lambda_role,
            environment={
                "S3_BUCKET_NAME": self.processed_data_bucket.bucket_name
            },
            description="Process streaming data from Kinesis and store in S3"
        )

        return function

    def _create_event_source_mapping(self, batch_size: int, max_batching_window: int) -> lambda_event_sources.KinesisEventSource:
        """
        Create event source mapping between Kinesis stream and Lambda function.
        
        Args:
            batch_size: Maximum number of records in each batch
            max_batching_window: Maximum time to wait for a batch in seconds
            
        Returns:
            lambda_event_sources.KinesisEventSource: The event source mapping
        """
        event_source = lambda_event_sources.KinesisEventSource(
            stream=self.kinesis_stream,
            starting_position=lambda_.StartingPosition.LATEST,
            batch_size=batch_size,
            max_batching_window=Duration.seconds(max_batching_window),
            retry_attempts=3,
            parallelization_factor=1,
            report_batch_item_failures=True
        )

        # Add the event source to the Lambda function
        self.processor_function.add_event_source(event_source)

        return event_source

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group with retention policy.
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "ProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.processor_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-KinesisStreamName"
        )

        CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="ARN of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-KinesisStreamArn"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.processor_function.function_name,
            description="Name of the Lambda processing function",
            export_name=f"{self.stack_name}-LambdaFunctionName"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.processor_function.function_arn,
            description="ARN of the Lambda processing function",
            export_name=f"{self.stack_name}-LambdaFunctionArn"
        )

        CfnOutput(
            self,
            "S3BucketName",
            value=self.processed_data_bucket.bucket_name,
            description="Name of the S3 bucket for processed data",
            export_name=f"{self.stack_name}-S3BucketName"
        )

        CfnOutput(
            self,
            "S3BucketArn",
            value=self.processed_data_bucket.bucket_arn,
            description="ARN of the S3 bucket for processed data",
            export_name=f"{self.stack_name}-S3BucketArn"
        )