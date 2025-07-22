#!/usr/bin/env python3
"""
CDK Python application for Streaming Data Enrichment with Kinesis.

This application deploys a complete streaming data enrichment pipeline that processes
real-time events, enriches them with contextual data, and stores results for analytics.

Architecture Components:
- Amazon Kinesis Data Streams for data ingestion
- AWS Lambda for real-time data enrichment processing
- Amazon DynamoDB for fast lookup operations
- Amazon S3 for storing enriched data
- CloudWatch for monitoring and alerting

The solution enables real-time decision-making for applications like e-commerce
personalization, fraud detection, and customer analytics.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_lambda as _lambda,
    aws_kinesis as kinesis,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda_event_sources as lambda_event_sources,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags
)
from constructs import Construct
from typing import Dict, Any
import os


class DataEnrichmentStack(Stack):
    """
    CDK Stack for streaming data enrichment pipeline.
    
    This stack creates all the infrastructure needed for a real-time data
    enrichment pipeline using Kinesis Data Streams and Lambda functions.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Add stack-level tags
        Tags.of(self).add("Project", "DataEnrichment")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")

        # Create DynamoDB table for user profile lookups
        self.lookup_table = self._create_lookup_table()
        
        # Create S3 bucket for enriched data storage
        self.enriched_data_bucket = self._create_s3_bucket()
        
        # Create Lambda function for data enrichment
        self.enrichment_function = self._create_lambda_function()
        
        # Create Kinesis Data Stream
        self.data_stream = self._create_kinesis_stream()
        
        # Create event source mapping
        self.event_source_mapping = self._create_event_source_mapping()
        
        # Create CloudWatch alarms for monitoring
        self._create_cloudwatch_alarms()
        
        # Populate sample data in DynamoDB table
        self._populate_sample_data()
        
        # Create stack outputs
        self._create_outputs()

    def _create_lookup_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for fast user profile lookups.
        
        The table stores user profiles that will be joined with streaming events
        to provide enriched data for downstream analytics and decision-making.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "EnrichmentLookupTable",
            table_name=f"enrichment-lookup-table-{self.stack_name.lower()}",
            partition_key=dynamodb.Attribute(
                name="user_id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # For development only
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )
        
        # Add tags
        Tags.of(table).add("Purpose", "UserProfileLookup")
        Tags.of(table).add("DataType", "UserProfiles")
        
        return table

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing enriched streaming data.
        
        The bucket provides durable storage for enriched events with
        versioning enabled for data protection and audit capabilities.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self, "EnrichedDataBucket",
            bucket_name=f"enriched-data-bucket-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For development only
            auto_delete_objects=True,  # For development only
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldData",
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
        
        # Add tags
        Tags.of(bucket).add("Purpose", "EnrichedDataStorage")
        Tags.of(bucket).add("DataType", "EnrichedEvents")
        
        return bucket

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Create Lambda function for real-time data enrichment.
        
        The function processes batches of streaming records, enriches them
        with user profile data from DynamoDB, and stores results in S3.
        
        Returns:
            _lambda.Function: The created Lambda function
        """
        # Create Lambda function code
        lambda_code = '''
import json
import boto3
import base64
import datetime
import os
from decimal import Decimal
from typing import Dict, Any, List
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process Kinesis records and enrich them with user profile data.
    
    Args:
        event: Kinesis event containing records to process
        context: Lambda context object
        
    Returns:
        Processing result summary
    """
    # Get environment variables
    table_name = os.environ['TABLE_NAME']
    bucket_name = os.environ['BUCKET_NAME']
    
    table = dynamodb.Table(table_name)
    
    processed_records = 0
    failed_records = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            
            # Enrich data with user profile
            user_id = data.get('user_id')
            if user_id:
                try:
                    response = table.get_item(Key={'user_id': user_id})
                    if 'Item' in response:
                        # Add user profile data to event
                        user_profile = response['Item']
                        data['user_name'] = user_profile.get('name', 'Unknown')
                        data['user_email'] = user_profile.get('email', 'Unknown')
                        data['user_segment'] = user_profile.get('segment', 'Unknown')
                        data['user_location'] = user_profile.get('location', 'Unknown')
                        data['enrichment_source'] = 'dynamodb'
                    else:
                        data['user_name'] = 'Unknown'
                        data['user_segment'] = 'Unknown'
                        data['enrichment_source'] = 'default'
                        logger.warning(f"User profile not found for user_id: {user_id}")
                except Exception as e:
                    logger.error(f"Error enriching user data for {user_id}: {e}")
                    data['enrichment_error'] = str(e)
                    data['enrichment_source'] = 'error'
            
            # Add processing metadata
            data['processing_timestamp'] = datetime.datetime.utcnow().isoformat()
            data['enriched'] = True
            data['lambda_request_id'] = context.aws_request_id
            
            # Store enriched data in S3 with time-based partitioning
            timestamp = datetime.datetime.utcnow()
            partition_path = f"year={timestamp.year}/month={timestamp.month:02d}/day={timestamp.day:02d}/hour={timestamp.hour:02d}"
            key = f"enriched-data/{partition_path}/{record['kinesis']['sequenceNumber']}.json"
            
            try:
                s3.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=json.dumps(data, default=str),
                    ContentType='application/json',
                    Metadata={
                        'processing_timestamp': data['processing_timestamp'],
                        'source_shard': record['kinesis']['partitionKey']
                    }
                )
                processed_records += 1
                logger.info(f"Successfully processed record: {record['kinesis']['sequenceNumber']}")
            except Exception as e:
                logger.error(f"Error storing enriched data: {e}")
                failed_records += 1
                raise
                
        except Exception as e:
            logger.error(f"Error processing record {record.get('kinesis', {}).get('sequenceNumber', 'unknown')}: {e}")
            failed_records += 1
            # Continue processing other records
    
    result = {
        'statusCode': 200,
        'processedRecords': processed_records,
        'failedRecords': failed_records,
        'totalRecords': len(event['Records'])
    }
    
    logger.info(f"Processing complete: {result}")
    return result
'''

        function = _lambda.Function(
            self, "DataEnrichmentFunction",
            function_name=f"data-enrichment-function-{self.stack_name.lower()}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "TABLE_NAME": self.lookup_table.table_name,
                "BUCKET_NAME": self.enriched_data_bucket.bucket_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=_lambda.Tracing.ACTIVE,
            description="Real-time data enrichment function for streaming events"
        )
        
        # Grant permissions to access DynamoDB table
        self.lookup_table.grant_read_data(function)
        
        # Grant permissions to write to S3 bucket
        self.enriched_data_bucket.grant_write(function)
        
        # Add tags
        Tags.of(function).add("Purpose", "DataEnrichment")
        Tags.of(function).add("Runtime", "Python3.9")
        
        return function

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for real-time data ingestion.
        
        The stream provides scalable, durable ingestion of streaming events
        with automatic scaling and built-in monitoring capabilities.
        
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self, "DataEnrichmentStream",
            stream_name=f"data-enrichment-stream-{self.stack_name.lower()}",
            shard_count=2,
            retention_period=Duration.hours(24),
            encryption=kinesis.StreamEncryption.MANAGED,
            stream_mode=kinesis.StreamMode.PROVISIONED
        )
        
        # Add tags
        Tags.of(stream).add("Purpose", "DataIngestion")
        Tags.of(stream).add("ShardCount", "2")
        
        return stream

    def _create_event_source_mapping(self) -> _lambda.EventSourceMapping:
        """
        Create event source mapping between Kinesis and Lambda.
        
        This establishes the connection that automatically invokes the Lambda
        function when new records arrive in the Kinesis stream.
        
        Returns:
            _lambda.EventSourceMapping: The created event source mapping
        """
        event_source_mapping = _lambda.EventSourceMapping(
            self, "KinesisLambdaEventSourceMapping",
            target=self.enrichment_function,
            event_source_arn=self.data_stream.stream_arn,
            batch_size=10,
            max_batching_window=Duration.seconds(5),
            starting_position=_lambda.StartingPosition.LATEST,
            retry_attempts=3,
            max_record_age=Duration.hours(1),
            parallelization_factor=1,
            report_batch_item_failures=True
        )
        
        return event_source_mapping

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring pipeline health.
        
        These alarms provide proactive monitoring of Lambda function errors,
        Kinesis stream health, and overall pipeline performance.
        """
        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name=f"{self.enrichment_function.function_name}-Errors",
            alarm_description="Monitor Lambda function errors in data enrichment pipeline",
            metric=self.enrichment_function.metric_errors(
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Lambda function duration alarm
        lambda_duration_alarm = cloudwatch.Alarm(
            self, "LambdaDurationAlarm",
            alarm_name=f"{self.enrichment_function.function_name}-Duration",
            alarm_description="Monitor Lambda function duration for performance issues",
            metric=self.enrichment_function.metric_duration(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=30000,  # 30 seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Kinesis incoming records alarm
        kinesis_records_alarm = cloudwatch.Alarm(
            self, "KinesisIncomingRecordsAlarm",
            alarm_name=f"{self.data_stream.stream_name}-IncomingRecords",
            alarm_description="Monitor Kinesis stream for lack of incoming data",
            metric=cloudwatch.Metric(
                namespace="AWS/Kinesis",
                metric_name="IncomingRecords",
                dimensions_map={
                    "StreamName": self.data_stream.stream_name
                },
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(5)
            ),
            threshold=0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_OR_EQUAL_TO_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.BREACHING
        )

    def _populate_sample_data(self) -> None:
        """
        Populate DynamoDB table with sample user profile data.
        
        This creates sample data that can be used for testing the enrichment
        pipeline without requiring external data sources.
        """
        # Custom resource to populate sample data
        sample_data_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["dynamodb:PutItem"],
                    resources=[self.lookup_table.table_arn]
                )
            ]
        )
        
        sample_data_role = iam.Role(
            self, "SampleDataRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "SampleDataPolicy": sample_data_policy
            }
        )
        
        sample_data_code = '''
import json
import boto3
import cfnresponse

def lambda_handler(event, context):
    """Custom resource to populate sample data in DynamoDB table."""
    
    dynamodb = boto3.resource('dynamodb')
    table_name = event['ResourceProperties']['TableName']
    table = dynamodb.Table(table_name)
    
    sample_users = [
        {
            'user_id': 'user123',
            'name': 'John Doe',
            'email': 'john@example.com',
            'segment': 'premium',
            'location': 'New York'
        },
        {
            'user_id': 'user456',
            'name': 'Jane Smith',
            'email': 'jane@example.com',
            'segment': 'standard',
            'location': 'California'
        },
        {
            'user_id': 'user789',
            'name': 'Bob Johnson',
            'email': 'bob@example.com',
            'segment': 'premium',
            'location': 'Texas'
        }
    ]
    
    try:
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            for user in sample_users:
                table.put_item(Item=user)
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, 
                           {'Message': 'Sample data populated successfully'})
        elif event['RequestType'] == 'Delete':
            # No cleanup needed for sample data
            cfnresponse.send(event, context, cfnresponse.SUCCESS, 
                           {'Message': 'Sample data cleanup completed'})
    except Exception as e:
        print(f"Error: {e}")
        cfnresponse.send(event, context, cfnresponse.FAILED, 
                       {'Message': str(e)})
'''
        
        sample_data_function = _lambda.Function(
            self, "SampleDataFunction",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(sample_data_code),
            role=sample_data_role,
            timeout=Duration.minutes(2)
        )
        
        # Create custom resource
        cdk.CustomResource(
            self, "SampleDataResource",
            service_token=sample_data_function.function_arn,
            properties={
                "TableName": self.lookup_table.table_name
            }
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self, "KinesisStreamName",
            value=self.data_stream.stream_name,
            description="Name of the Kinesis Data Stream for data ingestion"
        )
        
        CfnOutput(
            self, "KinesisStreamArn",
            value=self.data_stream.stream_arn,
            description="ARN of the Kinesis Data Stream"
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.enrichment_function.function_name,
            description="Name of the data enrichment Lambda function"
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.enrichment_function.function_arn,
            description="ARN of the data enrichment Lambda function"
        )
        
        CfnOutput(
            self, "DynamoDBTableName",
            value=self.lookup_table.table_name,
            description="Name of the DynamoDB lookup table"
        )
        
        CfnOutput(
            self, "S3BucketName",
            value=self.enriched_data_bucket.bucket_name,
            description="Name of the S3 bucket for enriched data"
        )
        
        CfnOutput(
            self, "S3BucketArn",
            value=self.enriched_data_bucket.bucket_arn,
            description="ARN of the S3 bucket for enriched data"
        )


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stackName") or "DataEnrichmentStack"
    
    # Create the stack
    DataEnrichmentStack(
        app, 
        stack_name,
        description="Streaming data enrichment pipeline with Kinesis and Lambda",
        env=cdk.Environment(
            account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
            region=os.environ.get('CDK_DEFAULT_REGION')
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()