#!/usr/bin/env python3
"""
CDK Python application for Centralized Logging with Amazon OpenSearch Service

This application deploys a complete centralized logging solution including:
- Amazon OpenSearch Service domain with security and encryption
- Kinesis Data Streams for scalable log ingestion
- Lambda function for intelligent log processing and enrichment
- Kinesis Data Firehose for reliable delivery to OpenSearch
- CloudWatch Logs subscription filters for automatic log forwarding
- S3 bucket for backup and failed delivery storage
- IAM roles and policies following least privilege principles
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_opensearch as opensearch,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_kinesisfirehose as firehose,
    aws_iam as iam,
    aws_s3 as s3,
    aws_logs as logs,
    aws_lambda_event_sources as lambda_event_sources,
)
from constructs import Construct
import os


class CentralizedLoggingStack(Stack):
    """
    CDK Stack for Centralized Logging with OpenSearch Service
    
    This stack creates a production-ready centralized logging infrastructure
    that automatically collects, processes, and analyzes log data from multiple
    AWS services using OpenSearch Service as the analytics engine.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.try_get_context("unique_suffix") or "cdkdemo"
        
        # Domain configuration
        domain_name = f"central-logging-{unique_suffix}"
        kinesis_stream_name = f"log-stream-{unique_suffix}"
        firehose_stream_name = f"log-delivery-{unique_suffix}"
        
        # Create S3 bucket for backup storage
        self.backup_bucket = self._create_backup_bucket(unique_suffix)
        
        # Create OpenSearch Service domain
        self.opensearch_domain = self._create_opensearch_domain(domain_name)
        
        # Create Kinesis Data Stream
        self.kinesis_stream = self._create_kinesis_stream(kinesis_stream_name)
        
        # Create Lambda function for log processing
        self.log_processor_function = self._create_log_processor_function(
            unique_suffix, firehose_stream_name
        )
        
        # Create Kinesis Data Firehose delivery stream
        self.firehose_stream = self._create_firehose_delivery_stream(
            firehose_stream_name, unique_suffix
        )
        
        # Create CloudWatch Logs service role
        self.cloudwatch_logs_role = self._create_cloudwatch_logs_role(unique_suffix)
        
        # Configure Lambda event source mapping
        self._configure_lambda_event_source()
        
        # Create stack outputs
        self._create_outputs()

    def _create_backup_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for failed delivery backup storage
        
        Returns:
            s3.Bucket: The created S3 bucket with versioning and encryption
        """
        bucket = s3.Bucket(
            self,
            "BackupBucket",
            bucket_name=f"central-logging-backup-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldBackups",
                    enabled=True,
                    expiration=Duration.days(90),
                    noncurrent_version_expiration=Duration.days(30),
                )
            ]
        )
        
        return bucket

    def _create_opensearch_domain(self, domain_name: str) -> opensearch.Domain:
        """
        Create Amazon OpenSearch Service domain with production settings
        
        Args:
            domain_name: Name for the OpenSearch domain
            
        Returns:
            opensearch.Domain: The created OpenSearch domain
        """
        domain = opensearch.Domain(
            self,
            "OpenSearchDomain",
            version=opensearch.EngineVersion.OPENSEARCH_2_9,
            domain_name=domain_name,
            capacity=opensearch.CapacityConfig(
                data_nodes=3,
                data_node_instance_type="t3.small.search",
                master_nodes=3,
                master_node_instance_type="t3.small.search",
                multi_az_with_standby_enabled=False,
            ),
            ebs=opensearch.EbsOptions(
                volume_size=20,
                volume_type=ec2.EbsDeviceVolumeType.GP3,
            ),
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=True,
                availability_zone_count=3,
            ),
            encryption_at_rest=opensearch.EncryptionAtRestOptions(
                enabled=True,
            ),
            node_to_node_encryption=True,
            enforce_https=True,
            tls_security_policy=opensearch.TLSSecurityPolicy.TLS_1_2,
            removal_policy=RemovalPolicy.DESTROY,
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=["es:*"],
                    resources=[f"arn:aws:es:{self.region}:{self.account}:domain/{domain_name}/*"],
                )
            ],
        )
        
        return domain

    def _create_kinesis_stream(self, stream_name: str) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for log ingestion
        
        Args:
            stream_name: Name for the Kinesis stream
            
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self,
            "KinesisStream",
            stream_name=stream_name,
            shard_count=2,
            retention_period=Duration.hours(24),
            stream_mode=kinesis.StreamMode.PROVISIONED,
        )
        
        return stream

    def _create_log_processor_function(self, unique_suffix: str, firehose_stream_name: str) -> lambda_.Function:
        """
        Create Lambda function for intelligent log processing
        
        Args:
            unique_suffix: Unique suffix for resource naming
            firehose_stream_name: Name of the Firehose delivery stream
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "LogProcessorLambdaRole",
            role_name=f"LogProcessorLambdaRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "LogProcessorPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetShardIterator",
                                "kinesis:GetRecords",
                                "kinesis:ListStreams",
                            ],
                            resources=[self.kinesis_stream.stream_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "firehose:PutRecord",
                                "firehose:PutRecordBatch",
                            ],
                            resources=[f"arn:aws:firehose:{self.region}:{self.account}:deliverystream/*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["cloudwatch:PutMetricData"],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

        # Create Lambda function
        function = lambda_.Function(
            self,
            "LogProcessorFunction",
            function_name=f"LogProcessor-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "FIREHOSE_STREAM_NAME": firehose_stream_name,
                "AWS_REGION": self.region,
            },
            code=lambda_.Code.from_inline(self._get_lambda_code()),
        )
        
        return function

    def _create_firehose_delivery_stream(self, stream_name: str, unique_suffix: str) -> firehose.CfnDeliveryStream:
        """
        Create Kinesis Data Firehose delivery stream to OpenSearch
        
        Args:
            stream_name: Name for the Firehose delivery stream
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            firehose.CfnDeliveryStream: The created Firehose delivery stream
        """
        # Create Firehose service role
        firehose_role = iam.Role(
            self,
            "FirehoseDeliveryRole",
            role_name=f"FirehoseDeliveryRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            inline_policies={
                "FirehoseDeliveryPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["es:ESHttpPost", "es:ESHttpPut"],
                            resources=[f"{self.opensearch_domain.domain_arn}/*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:AbortMultipartUpload",
                                "s3:GetBucketLocation",
                                "s3:GetObject",
                                "s3:ListBucket",
                                "s3:ListBucketMultipartUploads",
                                "s3:PutObject",
                            ],
                            resources=[
                                self.backup_bucket.bucket_arn,
                                f"{self.backup_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["logs:PutLogEvents"],
                            resources=[f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/kinesisfirehose/*"],
                        ),
                    ]
                )
            },
        )

        # Create Firehose delivery stream
        delivery_stream = firehose.CfnDeliveryStream(
            self,
            "FirehoseDeliveryStream",
            delivery_stream_name=stream_name,
            delivery_stream_type="DirectPut",
            amazon_open_search_serverless_destination_configuration=None,
            opensearch_destination_configuration=firehose.CfnDeliveryStream.OpenSearchDestinationConfigurationProperty(
                role_arn=firehose_role.role_arn,
                domain_arn=self.opensearch_domain.domain_arn,
                index_name="logs-%Y-%m-%d",
                index_rotation_period="OneDay",
                type_name="_doc",
                retry_duration=300,
                s3_backup_mode="FailedDocumentsOnly",
                s3_configuration=firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
                    role_arn=firehose_role.role_arn,
                    bucket_arn=self.backup_bucket.bucket_arn,
                    prefix="failed-logs/",
                    error_output_prefix="errors/",
                    buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                        size_in_m_bs=5,
                        interval_in_seconds=300,
                    ),
                    compression_format="GZIP",
                ),
                processing_configuration=firehose.CfnDeliveryStream.ProcessingConfigurationProperty(
                    enabled=False
                ),
                cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                    enabled=True,
                    log_group_name=f"/aws/kinesisfirehose/{stream_name}",
                ),
            ),
        )
        
        # Ensure OpenSearch domain is created before Firehose
        delivery_stream.add_dependency(self.opensearch_domain.node.default_child)
        
        return delivery_stream

    def _create_cloudwatch_logs_role(self, unique_suffix: str) -> iam.Role:
        """
        Create IAM role for CloudWatch Logs to write to Kinesis
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            iam.Role: The created CloudWatch Logs service role
        """
        role = iam.Role(
            self,
            "CloudWatchLogsRole",
            role_name=f"CWLogsToKinesisRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("logs.amazonaws.com"),
            inline_policies={
                "CWLogsToKinesisPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["kinesis:PutRecord", "kinesis:PutRecords"],
                            resources=[self.kinesis_stream.stream_arn],
                        )
                    ]
                )
            },
        )
        
        return role

    def _configure_lambda_event_source(self) -> None:
        """
        Configure Lambda event source mapping from Kinesis stream
        """
        self.log_processor_function.add_event_source(
            lambda_event_sources.KinesisEventSource(
                stream=self.kinesis_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=100,
                max_batching_window=Duration.seconds(10),
                retry_attempts=3,
            )
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resources
        """
        CfnOutput(
            self,
            "OpenSearchDomainEndpoint",
            description="OpenSearch Domain Endpoint",
            value=f"https://{self.opensearch_domain.domain_endpoint}",
        )
        
        CfnOutput(
            self,
            "OpenSearchDashboardsURL",
            description="OpenSearch Dashboards URL",
            value=f"https://{self.opensearch_domain.domain_endpoint}/_dashboards/",
        )
        
        CfnOutput(
            self,
            "KinesisStreamName",
            description="Kinesis Data Stream Name",
            value=self.kinesis_stream.stream_name,
        )
        
        CfnOutput(
            self,
            "KinesisStreamArn",
            description="Kinesis Data Stream ARN",
            value=self.kinesis_stream.stream_arn,
        )
        
        CfnOutput(
            self,
            "FirehoseDeliveryStreamName",
            description="Kinesis Data Firehose Delivery Stream Name",
            value=self.firehose_stream.delivery_stream_name,
        )
        
        CfnOutput(
            self,
            "BackupBucketName",
            description="S3 Backup Bucket Name",
            value=self.backup_bucket.bucket_name,
        )
        
        CfnOutput(
            self,
            "CloudWatchLogsRoleArn",
            description="CloudWatch Logs Service Role ARN (for subscription filters)",
            value=self.cloudwatch_logs_role.role_arn,
        )
        
        CfnOutput(
            self,
            "LogProcessorFunctionName",
            description="Log Processor Lambda Function Name",
            value=self.log_processor_function.function_name,
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code for log processing
        
        Returns:
            str: The complete Lambda function code
        """
        return '''
import json
import base64
import gzip
import boto3
import datetime
import os
import re
from typing import Dict, List, Any

firehose = boto3.client('firehose')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Process CloudWatch Logs data from Kinesis stream
    Enrich logs and forward to Kinesis Data Firehose
    """
    records_to_firehose = []
    error_count = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            compressed_payload = base64.b64decode(record['kinesis']['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Process each log event
            for log_event in log_data.get('logEvents', []):
                enriched_log = enrich_log_event(log_event, log_data)
                
                # Convert to JSON string for Firehose
                json_record = json.dumps(enriched_log) + '\\n'
                
                records_to_firehose.append({
                    'Data': json_record
                })
                
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            error_count += 1
            continue
    
    # Send processed records to Firehose
    if records_to_firehose:
        try:
            response = firehose.put_record_batch(
                DeliveryStreamName=os.environ['FIREHOSE_STREAM_NAME'],
                Records=records_to_firehose
            )
            
            failed_records = response.get('FailedPutCount', 0)
            if failed_records > 0:
                print(f"Failed to process {failed_records} records")
                
        except Exception as e:
            print(f"Error sending to Firehose: {str(e)}")
            error_count += len(records_to_firehose)
    
    # Send metrics to CloudWatch
    if error_count > 0:
        cloudwatch.put_metric_data(
            Namespace='CentralLogging/Processing',
            MetricData=[
                {
                    'MetricName': 'ProcessingErrors',
                    'Value': error_count,
                    'Unit': 'Count',
                    'Timestamp': datetime.datetime.utcnow()
                }
            ]
        )
    
    return {
        'statusCode': 200,
        'processedRecords': len(records_to_firehose),
        'errorCount': error_count
    }

def enrich_log_event(log_event: Dict, log_data: Dict) -> Dict:
    """
    Enrich log events with additional metadata and parsing
    """
    enriched = {
        '@timestamp': datetime.datetime.fromtimestamp(
            log_event['timestamp'] / 1000
        ).isoformat() + 'Z',
        'message': log_event.get('message', ''),
        'log_group': log_data.get('logGroup', ''),
        'log_stream': log_data.get('logStream', ''),
        'aws_account_id': log_data.get('owner', ''),
        'aws_region': os.environ.get('AWS_REGION', ''),
        'source_type': determine_source_type(log_data.get('logGroup', ''))
    }
    
    # Parse structured logs (JSON)
    try:
        if log_event['message'].strip().startswith('{'):
            parsed_message = json.loads(log_event['message'])
            enriched['parsed_message'] = parsed_message
            
            # Extract common fields
            if 'level' in parsed_message:
                enriched['log_level'] = parsed_message['level'].upper()
            if 'timestamp' in parsed_message:
                enriched['original_timestamp'] = parsed_message['timestamp']
                
    except (json.JSONDecodeError, KeyError):
        pass
    
    # Extract log level from message
    if 'log_level' not in enriched:
        enriched['log_level'] = extract_log_level(log_event['message'])
    
    # Add security context for security-related logs
    if is_security_related(log_event['message'], log_data.get('logGroup', '')):
        enriched['security_event'] = True
        enriched['priority'] = 'high'
    
    return enriched

def determine_source_type(log_group: str) -> str:
    """Determine the type of service generating the logs"""
    if '/aws/lambda/' in log_group:
        return 'lambda'
    elif '/aws/apigateway/' in log_group:
        return 'api-gateway'
    elif '/aws/rds/' in log_group:
        return 'rds'
    elif '/aws/vpc/flowlogs' in log_group:
        return 'vpc-flow-logs'
    elif 'cloudtrail' in log_group.lower():
        return 'cloudtrail'
    else:
        return 'application'

def extract_log_level(message: str) -> str:
    """Extract log level from message content"""
    log_levels = ['ERROR', 'WARN', 'WARNING', 'INFO', 'DEBUG', 'TRACE']
    message_upper = message.upper()
    
    for level in log_levels:
        if level in message_upper:
            return level
    
    return 'INFO'

def is_security_related(message: str, log_group: str) -> bool:
    """Identify potentially security-related log events"""
    security_keywords = [
        'authentication failed', 'access denied', 'unauthorized',
        'security group', 'iam', 'login failed', 'brute force',
        'suspicious', 'blocked', 'firewall', 'intrusion'
    ]
    
    message_lower = message.lower()
    log_group_lower = log_group.lower()
    
    # Check for security keywords
    for keyword in security_keywords:
        if keyword in message_lower:
            return True
    
    # Security-related log groups
    if any(term in log_group_lower for term in ['cloudtrail', 'security', 'auth', 'iam']):
        return True
    
    return False
'''


# Import ec2 for EBS volume type
from aws_cdk import aws_ec2 as ec2


class CentralizedLoggingApp(cdk.App):
    """
    CDK Application for Centralized Logging with OpenSearch Service
    """
    
    def __init__(self):
        super().__init__()
        
        # Get unique suffix from context or generate default
        unique_suffix = self.node.try_get_context("unique_suffix") or "cdkdemo"
        
        # Create the main stack
        CentralizedLoggingStack(
            self,
            "CentralizedLoggingStack",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
            description="Centralized Logging with Amazon OpenSearch Service - Production-ready log aggregation, processing, and analytics platform",
            tags={
                "Project": "CentralizedLogging",
                "Environment": "Production",
                "ManagedBy": "CDK",
                "CostCenter": "Infrastructure",
            },
        )


# Create and synthesize the application
app = CentralizedLoggingApp()
app.synth()