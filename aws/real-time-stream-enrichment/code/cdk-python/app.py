#!/usr/bin/env python3
"""
CDK Application for Real-Time Stream Enrichment Pipeline

This application deploys a complete serverless stream enrichment pipeline using:
- Kinesis Data Streams for raw event ingestion
- EventBridge Pipes for stream processing orchestration
- Lambda for real-time event enrichment
- DynamoDB for reference data storage
- Kinesis Data Firehose for S3 delivery
- S3 for data lake storage with automatic partitioning

Author: AWS Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_kinesis as kinesis,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_kinesisfirehose as firehose,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
import json


class StreamEnrichmentStack(Stack):
    """
    CDK Stack for implementing real-time stream enrichment pipeline
    with Kinesis Data Firehose and EventBridge Pipes.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = cdk.Fn.select(0, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', self.stack_id))))

        # ===============================
        # S3 Bucket for Enriched Data
        # ===============================
        self.data_bucket = s3.Bucket(
            self, "EnrichedDataBucket",
            bucket_name=f"stream-enrichment-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
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
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # ===============================
        # DynamoDB Table for Reference Data
        # ===============================
        self.reference_table = dynamodb.Table(
            self, "ReferenceDataTable",
            table_name=f"reference-data-{unique_suffix}",
            partition_key=dynamodb.Attribute(
                name="productId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Add sample reference data
        self._add_sample_data()

        # ===============================
        # Kinesis Data Stream
        # ===============================
        self.data_stream = kinesis.Stream(
            self, "RawEventStream",
            stream_name=f"raw-events-{unique_suffix}",
            stream_mode=kinesis.StreamMode.ON_DEMAND,
            encryption=kinesis.StreamEncryption.MANAGED,
            retention_period=Duration.days(1)
        )

        # ===============================
        # Lambda Function for Enrichment
        # ===============================
        self.enrichment_function = self._create_enrichment_lambda(unique_suffix)

        # ===============================
        # IAM Role for Kinesis Data Firehose
        # ===============================
        self.firehose_role = iam.Role(
            self, "FirehoseDeliveryRole",
            role_name=f"firehose-delivery-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            inline_policies={
                "S3DeliveryPolicy": iam.PolicyDocument(
                    statements=[
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
                    ]
                )
            }
        )

        # ===============================
        # Kinesis Data Firehose Delivery Stream
        # ===============================
        self.delivery_stream = self._create_firehose_stream(unique_suffix)

        # ===============================
        # IAM Role for EventBridge Pipes
        # ===============================
        self.pipes_role = iam.Role(
            self, "PipesExecutionRole",
            role_name=f"pipes-execution-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("pipes.amazonaws.com"),
            inline_policies={
                "PipesExecutionPolicy": iam.PolicyDocument(
                    statements=[
                        # Kinesis Stream permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetRecords",
                                "kinesis:GetShardIterator",
                                "kinesis:ListStreams",
                                "kinesis:SubscribeToShard"
                            ],
                            resources=[self.data_stream.stream_arn]
                        ),
                        # Lambda permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["lambda:InvokeFunction"],
                            resources=[self.enrichment_function.function_arn]
                        ),
                        # Firehose permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "firehose:PutRecord",
                                "firehose:PutRecordBatch"
                            ],
                            resources=[self.delivery_stream.attr_arn]
                        )
                    ]
                )
            }
        )

        # ===============================
        # EventBridge Pipe (Manual creation required)
        # ===============================
        # Note: EventBridge Pipes L2 constructs are not yet available in CDK
        # This would need to be created manually or via CloudFormation custom resource
        self._create_eventbridge_pipe_instructions(unique_suffix)

        # ===============================
        # CloudWatch Log Groups
        # ===============================
        self.pipeline_log_group = logs.LogGroup(
            self, "PipelineLogGroup",
            log_group_name=f"/aws/enrichment-pipeline/{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # ===============================
        # Outputs
        # ===============================
        CfnOutput(
            self, "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for enriched data storage"
        )

        CfnOutput(
            self, "ReferenceTableName",
            value=self.reference_table.table_name,
            description="DynamoDB table containing reference data"
        )

        CfnOutput(
            self, "DataStreamName",
            value=self.data_stream.stream_name,
            description="Kinesis Data Stream for raw events"
        )

        CfnOutput(
            self, "EnrichmentFunctionName",
            value=self.enrichment_function.function_name,
            description="Lambda function for event enrichment"
        )

        CfnOutput(
            self, "FirehoseStreamName",
            value=self.delivery_stream.ref,
            description="Kinesis Data Firehose delivery stream"
        )

        CfnOutput(
            self, "PipesRoleArn",
            value=self.pipes_role.role_arn,
            description="IAM role for EventBridge Pipes execution"
        )

    def _create_enrichment_lambda(self, unique_suffix: str) -> lambda_.Function:
        """
        Create the Lambda function for event enrichment.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create IAM role for Lambda
        lambda_role = iam.Role(
            self, "EnrichmentLambdaRole",
            role_name=f"lambda-enrichment-role-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "DynamoDBReadPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["dynamodb:GetItem"],
                            resources=[self.reference_table.table_arn]
                        )
                    ]
                )
            }
        )

        # Lambda function code
        lambda_code = '''
import json
import base64
import boto3
import os
from datetime import datetime
from typing import Dict, List, Any

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['TABLE_NAME'])

def lambda_handler(event: List[Dict[str, Any]], context: Any) -> List[Dict[str, Any]]:
    """
    Enriches streaming events with reference data from DynamoDB.
    
    Args:
        event: List of Kinesis records to enrich
        context: Lambda execution context
        
    Returns:
        List of enriched event records
    """
    enriched_records = []
    
    for record in event:
        try:
            # Decode Kinesis data
            payload = json.loads(
                base64.b64decode(record['data']).decode('utf-8')
            )
            
            # Lookup product details
            product_id = payload.get('productId')
            if product_id:
                try:
                    response = table.get_item(
                        Key={'productId': product_id}
                    )
                    if 'Item' in response:
                        # Enrich the payload
                        payload['productName'] = response['Item']['productName']
                        payload['category'] = response['Item']['category']
                        payload['price'] = float(response['Item']['price'])
                        payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                        payload['enrichmentStatus'] = 'success'
                    else:
                        payload['enrichmentStatus'] = 'product_not_found'
                        payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
                except Exception as e:
                    payload['enrichmentStatus'] = 'error'
                    payload['enrichmentError'] = str(e)
                    payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
            else:
                payload['enrichmentStatus'] = 'no_product_id'
                payload['enrichmentTimestamp'] = datetime.utcnow().isoformat()
            
            enriched_records.append(payload)
            
        except Exception as e:
            # Handle malformed records
            error_record = {
                'originalRecord': record,
                'error': str(e),
                'enrichmentStatus': 'parse_error',
                'enrichmentTimestamp': datetime.utcnow().isoformat()
            }
            enriched_records.append(error_record)
    
    return enriched_records
'''

        return lambda_.Function(
            self, "EnrichmentFunction",
            function_name=f"enrich-events-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "TABLE_NAME": self.reference_table.table_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_firehose_stream(self, unique_suffix: str) -> firehose.CfnDeliveryStream:
        """
        Create Kinesis Data Firehose delivery stream for S3 delivery.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            
        Returns:
            firehose.CfnDeliveryStream: The created Firehose delivery stream
        """
        return firehose.CfnDeliveryStream(
            self, "EnrichedDataFirehose",
            delivery_stream_name=f"event-ingestion-{unique_suffix}",
            delivery_stream_type="DirectPut",
            extended_s3_destination_configuration=firehose.CfnDeliveryStream.ExtendedS3DestinationConfigurationProperty(
                role_arn=self.firehose_role.role_arn,
                bucket_arn=self.data_bucket.bucket_arn,
                prefix="enriched-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
                error_output_prefix="error-data/",
                compression_format="GZIP",
                buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                    size_in_m_bs=5,
                    interval_in_seconds=300
                ),
                cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                    enabled=True,
                    log_group_name=self.pipeline_log_group.log_group_name
                ),
                data_format_conversion_configuration=firehose.CfnDeliveryStream.DataFormatConversionConfigurationProperty(
                    enabled=False
                )
            )
        )

    def _add_sample_data(self) -> None:
        """Add sample reference data to DynamoDB table using custom resource."""
        # Lambda function to populate sample data
        populate_data_code = '''
import boto3
import json
import cfnresponse

def lambda_handler(event, context):
    """Custom resource to populate DynamoDB with sample data."""
    try:
        if event['RequestType'] == 'Create':
            dynamodb = boto3.resource('dynamodb')
            table = dynamodb.Table(event['ResourceProperties']['TableName'])
            
            # Sample data
            items = [
                {
                    'productId': 'PROD-001',
                    'productName': 'Smart Sensor',
                    'category': 'IoT Devices',
                    'price': '49.99'
                },
                {
                    'productId': 'PROD-002',
                    'productName': 'Temperature Monitor',
                    'category': 'IoT Devices',
                    'price': '79.99'
                },
                {
                    'productId': 'PROD-003',
                    'productName': 'Humidity Sensor',
                    'category': 'IoT Devices',
                    'price': '35.99'
                }
            ]
            
            # Insert items
            for item in items:
                table.put_item(Item=item)
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
        else:
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
'''

        # Lambda role for custom resource
        populate_role = iam.Role(
            self, "PopulateDataRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "DynamoDBWritePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["dynamodb:PutItem"],
                            resources=[self.reference_table.table_arn]
                        )
                    ]
                )
            }
        )

        # Lambda function for populating data
        populate_function = lambda_.Function(
            self, "PopulateDataFunction",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(populate_data_code),
            role=populate_role,
            timeout=Duration.seconds(60)
        )

        # Custom resource to trigger data population
        cdk.CustomResource(
            self, "PopulateDataCustomResource",
            service_token=populate_function.function_arn,
            properties={
                "TableName": self.reference_table.table_name
            }
        )

    def _create_eventbridge_pipe_instructions(self, unique_suffix: str) -> None:
        """
        Create instructions for manually creating EventBridge Pipe.
        
        Note: EventBridge Pipes L2 constructs are not yet available in CDK.
        This method outputs the necessary information to create the pipe manually.
        """
        CfnOutput(
            self, "EventBridgePipeInstructions",
            value=json.dumps({
                "pipeName": f"enrichment-pipe-{unique_suffix}",
                "sourceArn": self.data_stream.stream_arn,
                "enrichmentArn": self.enrichment_function.function_arn,
                "targetArn": self.delivery_stream.attr_arn,
                "roleArn": self.pipes_role.role_arn
            }, indent=2),
            description="Configuration for creating EventBridge Pipe manually"
        )


# CDK Application
app = cdk.App()

# Create the stack
StreamEnrichmentStack(
    app, "StreamEnrichmentStack",
    description="Real-time stream enrichment pipeline with Kinesis Data Firehose and EventBridge Pipes",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()