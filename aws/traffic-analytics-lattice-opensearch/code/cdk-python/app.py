#!/usr/bin/env python3
"""
Traffic Analytics with VPC Lattice and OpenSearch CDK Application

This CDK application creates a comprehensive traffic analytics solution using:
- VPC Lattice for service mesh networking with access logging
- Kinesis Data Firehose for real-time streaming data delivery
- Lambda for data transformation and enrichment
- OpenSearch Service for analytics and visualization
- S3 for backup storage and error handling

Author: AWS CDK Python Generator
Version: 1.0
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_opensearch as opensearch,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_s3 as s3,
    aws_kinesisfirehose as firehose,
    aws_vpclattice as lattice,
    aws_logs as logs,
    aws_ec2 as ec2,
)
import json


class TrafficAnalyticsStack(Stack):
    """
    CDK Stack for Traffic Analytics with VPC Lattice and OpenSearch
    
    This stack creates a complete traffic analytics pipeline that captures
    VPC Lattice access logs, transforms them through Lambda, and delivers
    them to OpenSearch Service for real-time analytics and visualization.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Define common tags for all resources
        common_tags = {
            "Project": "TrafficAnalytics",
            "Purpose": "VPCLatticeAnalytics",
            "Environment": "Demo"
        }

        # Apply tags to the stack
        for key, value in common_tags.items():
            cdk.Tags.of(self).add(key, value)

        # Create S3 bucket for backup storage and error records
        backup_bucket = self._create_backup_bucket()
        
        # Create Lambda function for data transformation
        transform_function = self._create_transform_function()
        
        # Create OpenSearch domain for analytics
        opensearch_domain = self._create_opensearch_domain()
        
        # Create Kinesis Data Firehose delivery stream
        firehose_stream = self._create_firehose_delivery_stream(
            opensearch_domain, transform_function, backup_bucket
        )
        
        # Create VPC Lattice service network
        service_network = self._create_vpc_lattice_network()
        
        # Create demo service for traffic generation
        demo_service = self._create_demo_service(service_network)
        
        # Create access log subscription
        self._create_access_log_subscription(service_network, firehose_stream)
        
        # Create outputs for important resources
        self._create_outputs(opensearch_domain, firehose_stream, service_network, demo_service)

    def _create_backup_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for backup storage and error records.
        
        Returns:
            s3.Bucket: The created S3 bucket with security configurations
        """
        bucket = s3.Bucket(
            self, "BackupBucket",
            bucket_name=f"vpc-lattice-backup-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldBackups",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
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

    def _create_transform_function(self) -> _lambda.Function:
        """
        Create Lambda function for transforming VPC Lattice access logs.
        
        Returns:
            _lambda.Function: The Lambda function for log transformation
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self, "TransformFunctionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Lambda function code for traffic log transformation
        lambda_code = """
import json
import base64
import gzip
import datetime
from typing import Any, Dict, List

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, List[Dict[str, Any]]]:
    \"\"\"
    Transform VPC Lattice access logs for OpenSearch analytics.
    
    This function processes streaming log data from Kinesis Data Firehose,
    enriches the logs with additional metadata, and formats them for
    optimal analytics performance in OpenSearch.
    
    Args:
        event: Kinesis Data Firehose transformation event
        context: Lambda context object
        
    Returns:
        Dict containing transformed records for Firehose delivery
    \"\"\"
    output = []
    
    for record in event['records']:
        try:
            # Decode and decompress the data
            compressed_payload = base64.b64decode(record['data'])
            uncompressed_payload = gzip.decompress(compressed_payload)
            log_data = json.loads(uncompressed_payload)
            
            # Transform and enrich each log entry
            for log_entry in log_data.get('logEvents', []):
                try:
                    # Parse the log message if it's JSON
                    if log_entry['message'].startswith('{'):
                        parsed_log = json.loads(log_entry['message'])
                        
                        # Add timestamp and enrichment fields
                        parsed_log['@timestamp'] = datetime.datetime.fromtimestamp(
                            log_entry['timestamp'] / 1000
                        ).isoformat()
                        parsed_log['log_group'] = log_data.get('logGroup', '')
                        parsed_log['log_stream'] = log_data.get('logStream', '')
                        
                        # Add derived fields for analytics
                        if 'responseCode' in parsed_log:
                            parsed_log['response_class'] = str(parsed_log['responseCode'])[0] + 'xx'
                            parsed_log['is_error'] = parsed_log['responseCode'] >= 400
                        
                        if 'responseTimeMs' in parsed_log:
                            parsed_log['response_time_bucket'] = categorize_response_time(
                                parsed_log['responseTimeMs']
                            )
                        
                        # Add geographic and network context if available
                        if 'sourceIpPort' in parsed_log:
                            parsed_log['source_ip'] = parsed_log['sourceIpPort'].split(':')[0]
                            
                        output_record = {
                            'recordId': record['recordId'],
                            'result': 'Ok',
                            'data': base64.b64encode(
                                (json.dumps(parsed_log) + '\\n').encode('utf-8')
                            ).decode('utf-8')
                        }
                    else:
                        # If not JSON, pass through with minimal processing
                        enhanced_log = {
                            'message': log_entry['message'],
                            '@timestamp': datetime.datetime.fromtimestamp(
                                log_entry['timestamp'] / 1000
                            ).isoformat(),
                            'log_group': log_data.get('logGroup', ''),
                            'log_stream': log_data.get('logStream', '')
                        }
                        
                        output_record = {
                            'recordId': record['recordId'],
                            'result': 'Ok',
                            'data': base64.b64encode(
                                (json.dumps(enhanced_log) + '\\n').encode('utf-8')
                            ).decode('utf-8')
                        }
                    
                    output.append(output_record)
                    
                except Exception as e:
                    print(f"Error processing log entry: {str(e)}")
                    # If processing fails, mark as processing failure
                    output.append({
                        'recordId': record['recordId'],
                        'result': 'ProcessingFailed'
                    })
        
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            # If record processing fails completely
            output.append({
                'recordId': record['recordId'],
                'result': 'ProcessingFailed'
            })
    
    return {'records': output}

def categorize_response_time(response_time_ms: float) -> str:
    \"\"\"Categorize response times for analytics aggregation.\"\"\"
    if response_time_ms < 100:
        return 'fast'
    elif response_time_ms < 500:
        return 'medium'
    elif response_time_ms < 2000:
        return 'slow'
    else:
        return 'very_slow'
"""

        transform_function = _lambda.Function(
            self, "TrafficTransformFunction",
            runtime=_lambda.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(1),
            memory_size=256,
            description="Transform VPC Lattice access logs for OpenSearch analytics",
            environment={
                "LOG_LEVEL": "INFO"
            }
        )

        return transform_function

    def _create_opensearch_domain(self) -> opensearch.Domain:
        """
        Create OpenSearch Service domain for traffic analytics.
        
        Returns:
            opensearch.Domain: The OpenSearch domain with security configurations
        """
        # Create OpenSearch domain with appropriate sizing
        domain = opensearch.Domain(
            self, "TrafficAnalyticsDomain",
            version=opensearch.EngineVersion.OPENSEARCH_2_11,
            capacity=opensearch.CapacityConfig(
                data_nodes=1,
                data_node_instance_type="t3.small.search"
            ),
            ebs=opensearch.EbsOptions(
                volume_size=20,
                volume_type=ec2.EbsDeviceVolumeType.GP3
            ),
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=False  # Single AZ for cost optimization in demo
            ),
            encryption_at_rest=opensearch.EncryptionAtRestOptions(
                enabled=True
            ),
            node_to_node_encryption=True,
            enforce_https=True,
            removal_policy=RemovalPolicy.DESTROY,
            # Configure access policy for the domain
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=["es:*"],
                    resources=[f"arn:aws:es:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:domain/traffic-analytics-domain/*"]
                )
            ]
        )

        return domain

    def _create_firehose_delivery_stream(
        self, 
        opensearch_domain: opensearch.Domain, 
        transform_function: _lambda.Function,
        backup_bucket: s3.Bucket
    ) -> firehose.CfnDeliveryStream:
        """
        Create Kinesis Data Firehose delivery stream for streaming data to OpenSearch.
        
        Args:
            opensearch_domain: Target OpenSearch domain
            transform_function: Lambda function for data transformation
            backup_bucket: S3 bucket for backup storage
            
        Returns:
            firehose.CfnDeliveryStream: The configured Firehose delivery stream
        """
        # Create IAM role for Firehose
        firehose_role = iam.Role(
            self, "FirehoseDeliveryRole",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            inline_policies={
                "FirehoseOpenSearchPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "es:DescribeDomain",
                                "es:DescribeDomains", 
                                "es:DescribeDomainConfig",
                                "es:ESHttpPost",
                                "es:ESHttpPut"
                            ],
                            resources=[opensearch_domain.domain_arn, f"{opensearch_domain.domain_arn}/*"]
                        ),
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
                            resources=[backup_bucket.bucket_arn, f"{backup_bucket.bucket_arn}/*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "lambda:InvokeFunction",
                                "lambda:GetFunctionConfiguration"
                            ],
                            resources=[transform_function.function_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create CloudWatch log group for Firehose
        log_group = logs.LogGroup(
            self, "FirehoseLogGroup",
            log_group_name=f"/aws/kinesisfirehose/vpc-lattice-stream",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        log_stream = logs.LogStream(
            self, "FirehoseLogStream",
            log_group=log_group,
            log_stream_name="delivery"
        )

        # Create Firehose delivery stream
        delivery_stream = firehose.CfnDeliveryStream(
            self, "VPCLatticeFirehoseStream",
            delivery_stream_name="vpc-lattice-traffic-stream",
            delivery_stream_type="DirectPut",
            amazon_open_search_serverless_destination_configuration=None,
            opensearch_destination_configuration=firehose.CfnDeliveryStream.OpensearchDestinationConfigurationProperty(
                domain_arn=opensearch_domain.domain_arn,
                index_name="vpc-lattice-traffic",
                role_arn=firehose_role.role_arn,
                s3_configuration=firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
                    bucket_arn=backup_bucket.bucket_arn,
                    role_arn=firehose_role.role_arn,
                    prefix="firehose-backup/",
                    buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                        size_in_m_bs=1,
                        interval_in_seconds=60
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
                                    parameter_value=transform_function.function_arn
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
        )

        # Add dependency on the log stream
        delivery_stream.add_dependency(log_stream.node.default_child)

        return delivery_stream

    def _create_vpc_lattice_network(self) -> lattice.CfnServiceNetwork:
        """
        Create VPC Lattice service network for microservices communication.
        
        Returns:
            lattice.CfnServiceNetwork: The VPC Lattice service network
        """
        service_network = lattice.CfnServiceNetwork(
            self, "DemoServiceNetwork", 
            name=f"traffic-analytics-network-{cdk.Aws.ACCOUNT_ID}",
            auth_type="AWS_IAM"
        )

        return service_network

    def _create_demo_service(self, service_network: lattice.CfnServiceNetwork) -> lattice.CfnService:
        """
        Create a demo VPC Lattice service for traffic generation.
        
        Args:
            service_network: The VPC Lattice service network
            
        Returns:
            lattice.CfnService: The demo service
        """
        # Create demo service
        demo_service = lattice.CfnService(
            self, "DemoService",
            name=f"demo-service-{cdk.Aws.ACCOUNT_ID}",
            auth_type="AWS_IAM"
        )

        # Associate service with service network
        lattice.CfnServiceNetworkServiceAssociation(
            self, "DemoServiceAssociation",
            service_identifier=demo_service.ref,
            service_network_identifier=service_network.ref
        )

        return demo_service

    def _create_access_log_subscription(
        self, 
        service_network: lattice.CfnServiceNetwork,
        firehose_stream: firehose.CfnDeliveryStream
    ) -> lattice.CfnAccessLogSubscription:
        """
        Create access log subscription for VPC Lattice traffic capture.
        
        Args:
            service_network: The VPC Lattice service network
            firehose_stream: The Kinesis Data Firehose delivery stream
            
        Returns:
            lattice.CfnAccessLogSubscription: The access log subscription
        """
        access_log_subscription = lattice.CfnAccessLogSubscription(
            self, "ServiceNetworkAccessLogs",
            resource_identifier=service_network.ref,
            destination_arn=f"arn:aws:firehose:{cdk.Aws.REGION}:{cdk.Aws.ACCOUNT_ID}:deliverystream/{firehose_stream.delivery_stream_name}"
        )

        return access_log_subscription

    def _create_outputs(
        self,
        opensearch_domain: opensearch.Domain,
        firehose_stream: firehose.CfnDeliveryStream,
        service_network: lattice.CfnServiceNetwork,
        demo_service: lattice.CfnService
    ) -> None:
        """
        Create CloudFormation outputs for key resources.
        
        Args:
            opensearch_domain: The OpenSearch domain
            firehose_stream: The Firehose delivery stream
            service_network: The VPC Lattice service network
            demo_service: The demo service
        """
        CfnOutput(
            self, "OpenSearchDomainEndpoint",
            value=opensearch_domain.domain_endpoint,
            description="OpenSearch domain endpoint for traffic analytics"
        )

        CfnOutput(
            self, "OpenSearchDashboardsURL",
            value=f"https://{opensearch_domain.domain_endpoint}/_dashboards",
            description="OpenSearch Dashboards URL for visualization"
        )

        CfnOutput(
            self, "FirehoseDeliveryStreamName",
            value=firehose_stream.delivery_stream_name or "vpc-lattice-traffic-stream",
            description="Kinesis Data Firehose delivery stream name"
        )

        CfnOutput(
            self, "ServiceNetworkId",
            value=service_network.ref,
            description="VPC Lattice service network ID"
        )

        CfnOutput(
            self, "ServiceNetworkArn",
            value=service_network.attr_arn,
            description="VPC Lattice service network ARN"
        )

        CfnOutput(
            self, "DemoServiceId",
            value=demo_service.ref,
            description="Demo VPC Lattice service ID"
        )

        CfnOutput(
            self, "DemoServiceArn",
            value=demo_service.attr_arn,
            description="Demo VPC Lattice service ARN"
        )


# CDK Application definition
app = cdk.App()

# Create the stack with appropriate environment
TrafficAnalyticsStack(
    app, 
    "TrafficAnalyticsStack",
    description="Traffic Analytics with VPC Lattice and OpenSearch - A comprehensive solution for service mesh observability",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

# Synthesize the CloudFormation template
app.synth()