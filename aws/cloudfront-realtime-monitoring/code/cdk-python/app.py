#!/usr/bin/env python3
"""
CloudFront Real-time Monitoring and Analytics CDK Application

This CDK application implements a comprehensive real-time monitoring solution for
CloudFront distributions using Kinesis Data Streams, Lambda processing, OpenSearch,
and CloudWatch dashboards.

Author: CDK Recipe Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_cloudfront as cloudfront,
    aws_cloudfront_origins as origins,
    aws_s3 as s3,
    aws_iam as iam,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_dynamodb as dynamodb,
    aws_opensearch as opensearch,
    aws_kinesisfirehose as firehose,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_s3_deployment as s3_deployment,
)
from constructs import Construct
import json
from typing import Dict, Any


class CloudFrontMonitoringStack(Stack):
    """
    CDK Stack for CloudFront Real-time Monitoring and Analytics
    
    This stack creates:
    - CloudFront distribution with real-time logging
    - Kinesis Data Streams for log ingestion and processing
    - Lambda function for real-time log processing and enrichment
    - DynamoDB for metrics storage
    - OpenSearch for log analytics
    - Kinesis Data Firehose for data delivery
    - CloudWatch dashboard for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[:8].lower()
        
        # Create S3 buckets
        self.content_bucket = self._create_content_bucket(unique_suffix)
        self.logs_bucket = self._create_logs_bucket(unique_suffix)
        
        # Create Kinesis streams
        self.raw_stream = self._create_kinesis_stream(f"cf-realtime-logs-{unique_suffix}", 2)
        self.processed_stream = self._create_kinesis_stream(f"cf-realtime-logs-{unique_suffix}-processed", 1)
        
        # Create DynamoDB table for metrics
        self.metrics_table = self._create_metrics_table(unique_suffix)
        
        # Create OpenSearch domain
        self.opensearch_domain = self._create_opensearch_domain(unique_suffix)
        
        # Create Lambda function for log processing
        self.log_processor = self._create_log_processor_lambda(unique_suffix)
        
        # Create CloudFront distribution
        self.distribution = self._create_cloudfront_distribution(unique_suffix)
        
        # Create Kinesis Data Firehose
        self.firehose_stream = self._create_firehose_delivery_stream(unique_suffix)
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard(unique_suffix)
        
        # Deploy sample content
        self._deploy_sample_content()
        
        # Configure real-time logging (requires manual setup in console)
        self._output_real_time_logging_instructions()

    def _create_content_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for CloudFront content"""
        bucket = s3.Bucket(
            self, "ContentBucket",
            bucket_name=f"cf-content-{suffix}",
            versioned=False,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        CfnOutput(
            self, "ContentBucketName",
            value=bucket.bucket_name,
            description="S3 bucket containing CloudFront content"
        )
        
        return bucket

    def _create_logs_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for storing processed logs"""
        bucket = s3.Bucket(
            self, "LogsBucket",
            bucket_name=f"cf-logs-{suffix}",
            versioned=False,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="LogsLifecycle",
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
                    ],
                    expiration=Duration.days(365)
                )
            ]
        )
        
        CfnOutput(
            self, "LogsBucketName",
            value=bucket.bucket_name,
            description="S3 bucket for storing processed CloudFront logs"
        )
        
        return bucket

    def _create_kinesis_stream(self, name: str, shard_count: int) -> kinesis.Stream:
        """Create Kinesis Data Stream"""
        stream = kinesis.Stream(
            self, name.replace("-", "").title() + "Stream",
            stream_name=name,
            shard_count=shard_count,
            retention_period=Duration.days(1),
            encryption=kinesis.StreamEncryption.MANAGED
        )
        
        return stream

    def _create_metrics_table(self, suffix: str) -> dynamodb.Table:
        """Create DynamoDB table for storing processed metrics"""
        table = dynamodb.Table(
            self, "MetricsTable",
            table_name=f"cf-monitoring-{suffix}-metrics",
            partition_key=dynamodb.Attribute(
                name="MetricId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            time_to_live_attribute="TTL",
            point_in_time_recovery=True,
        )
        
        CfnOutput(
            self, "MetricsTableName",
            value=table.table_name,
            description="DynamoDB table for storing real-time metrics"
        )
        
        return table

    def _create_opensearch_domain(self, suffix: str) -> opensearch.Domain:
        """Create OpenSearch domain for log analytics"""
        domain = opensearch.Domain(
            self, "OpenSearchDomain",
            domain_name=f"cf-analytics-{suffix}",
            version=opensearch.EngineVersion.OPENSEARCH_2_3,
            cluster_config=opensearch.ClusterConfig(
                instance_type="t3.small.search",
                instance_count=1,
                dedicated_master_enabled=False,
            ),
            ebs=opensearch.EbsOptions(
                enabled=True,
                volume_type=cdk.aws_ec2.EbsDeviceVolumeType.GP3,
                volume_size=20,
            ),
            node_to_node_encryption=True,
            encryption_at_rest=opensearch.EncryptionAtRestOptions(
                enabled=True
            ),
            enforce_https=True,
            tls_security_policy=opensearch.TLSSecurityPolicy.TLS_1_2,
            removal_policy=RemovalPolicy.DESTROY,
            access_policies=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AnyPrincipal()],
                    actions=["es:*"],
                    resources=["*"],
                    conditions={
                        "IpAddress": {
                            "aws:SourceIp": ["0.0.0.0/0"]  # Restrict this in production
                        }
                    }
                )
            ]
        )
        
        CfnOutput(
            self, "OpenSearchEndpoint",
            value=f"https://{domain.domain_endpoint}",
            description="OpenSearch domain endpoint for log analytics"
        )
        
        CfnOutput(
            self, "OpenSearchDashboards",
            value=f"https://{domain.domain_endpoint}/_dashboards/",
            description="OpenSearch Dashboards URL"
        )
        
        return domain

    def _create_log_processor_lambda(self, suffix: str) -> lambda_.Function:
        """Create Lambda function for processing CloudFront logs"""
        
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "LogProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "CloudFrontLogProcessingPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetRecords",
                                "kinesis:GetShardIterator",
                                "kinesis:ListStreams",
                                "kinesis:PutRecord",
                                "kinesis:PutRecords"
                            ],
                            resources=[
                                self.raw_stream.stream_arn,
                                self.processed_stream.stream_arn
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:PutItem",
                                "dynamodb:GetItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query",
                                "dynamodb:Scan"
                            ],
                            resources=[self.metrics_table.table_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["cloudwatch:PutMetricData"],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Lambda function code
        lambda_code = '''
const AWS = require('aws-sdk');
const geoip = require('geoip-lite');

const cloudwatch = new AWS.CloudWatch();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const kinesis = new AWS.Kinesis();

const METRICS_TABLE = process.env.METRICS_TABLE;
const PROCESSED_STREAM = process.env.PROCESSED_STREAM;

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const processedRecords = [];
    const metrics = {
        totalRequests: 0,
        totalBytes: 0,
        errors4xx: 0,
        errors5xx: 0,
        cacheMisses: 0,
        regionCounts: {},
        statusCodes: {},
        userAgents: {}
    };
    
    for (const record of event.Records) {
        try {
            const data = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const logEntries = data.trim().split('\\n');
            
            for (const logEntry of logEntries) {
                const processedLog = await processLogEntry(logEntry, metrics);
                if (processedLog) {
                    processedRecords.push(processedLog);
                }
            }
        } catch (error) {
            console.error('Error processing record:', error);
        }
    }
    
    if (processedRecords.length > 0) {
        await sendToKinesis(processedRecords);
    }
    
    await storeMetrics(metrics);
    await sendCloudWatchMetrics(metrics);
    
    return {
        statusCode: 200,
        processedRecords: processedRecords.length
    };
};

async function processLogEntry(logEntry, metrics) {
    try {
        const fields = logEntry.split('\\t');
        
        if (fields.length < 20) {
            return null;
        }
        
        const timestamp = `${fields[0]} ${fields[1]}`;
        const edgeLocation = fields[2];
        const bytesDownloaded = parseInt(fields[3]) || 0;
        const clientIp = fields[4];
        const method = fields[5];
        const host = fields[6];
        const uri = fields[7];
        const status = parseInt(fields[8]) || 0;
        const referer = fields[9];
        const userAgent = fields[10];
        const edgeResultType = fields[13];
        
        const geoData = geoip.lookup(clientIp) || {};
        
        metrics.totalRequests++;
        metrics.totalBytes += bytesDownloaded;
        
        if (status >= 400 && status < 500) {
            metrics.errors4xx++;
        } else if (status >= 500) {
            metrics.errors5xx++;
        }
        
        if (edgeResultType === 'Miss') {
            metrics.cacheMisses++;
        }
        
        const region = geoData.region || 'Unknown';
        metrics.regionCounts[region] = (metrics.regionCounts[region] || 0) + 1;
        metrics.statusCodes[status] = (metrics.statusCodes[status] || 0) + 1;
        
        const uaCategory = categorizeUserAgent(userAgent);
        metrics.userAgents[uaCategory] = (metrics.userAgents[uaCategory] || 0) + 1;
        
        return {
            timestamp: new Date(timestamp).toISOString(),
            edgeLocation,
            clientIp,
            method,
            host,
            uri,
            status,
            bytesDownloaded,
            edgeResultType,
            userAgent: uaCategory,
            country: geoData.country || 'Unknown',
            region: geoData.region || 'Unknown',
            city: geoData.city || 'Unknown',
            cacheHit: edgeResultType !== 'Miss',
            isError: status >= 400,
            processingTime: Date.now()
        };
        
    } catch (error) {
        console.error('Error parsing log entry:', error);
        return null;
    }
}

function categorizeUserAgent(userAgent) {
    if (!userAgent || userAgent === '-') return 'Unknown';
    
    const ua = userAgent.toLowerCase();
    if (ua.includes('chrome')) return 'Chrome';
    if (ua.includes('firefox')) return 'Firefox';
    if (ua.includes('safari') && !ua.includes('chrome')) return 'Safari';
    if (ua.includes('edge')) return 'Edge';
    if (ua.includes('bot') || ua.includes('crawler')) return 'Bot';
    if (ua.includes('mobile')) return 'Mobile';
    
    return 'Other';
}

async function sendToKinesis(records) {
    const batchSize = 500;
    
    for (let i = 0; i < records.length; i += batchSize) {
        const batch = records.slice(i, i + batchSize);
        const kinesisRecords = batch.map(record => ({
            Data: JSON.stringify(record),
            PartitionKey: record.edgeLocation || 'default'
        }));
        
        try {
            await kinesis.putRecords({
                StreamName: PROCESSED_STREAM,
                Records: kinesisRecords
            }).promise();
        } catch (error) {
            console.error('Error sending to Kinesis:', error);
        }
    }
}

async function storeMetrics(metrics) {
    const timestamp = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + (7 * 24 * 60 * 60);
    
    try {
        await dynamodb.put({
            TableName: METRICS_TABLE,
            Item: {
                MetricId: `metrics-${Date.now()}`,
                Timestamp: timestamp,
                TotalRequests: metrics.totalRequests,
                TotalBytes: metrics.totalBytes,
                Errors4xx: metrics.errors4xx,
                Errors5xx: metrics.errors5xx,
                CacheMisses: metrics.cacheMisses,
                RegionCounts: metrics.regionCounts,
                StatusCodes: metrics.statusCodes,
                UserAgents: metrics.userAgents,
                TTL: ttl
            }
        }).promise();
    } catch (error) {
        console.error('Error storing metrics:', error);
    }
}

async function sendCloudWatchMetrics(metrics) {
    const metricData = [
        {
            MetricName: 'RequestCount',
            Value: metrics.totalRequests,
            Unit: 'Count',
            Timestamp: new Date()
        },
        {
            MetricName: 'BytesDownloaded',
            Value: metrics.totalBytes,
            Unit: 'Bytes',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate4xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors4xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'ErrorRate5xx',
            Value: metrics.totalRequests > 0 ? (metrics.errors5xx / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        },
        {
            MetricName: 'CacheMissRate',
            Value: metrics.totalRequests > 0 ? (metrics.cacheMisses / metrics.totalRequests) * 100 : 0,
            Unit: 'Percent',
            Timestamp: new Date()
        }
    ];
    
    try {
        await cloudwatch.putMetricData({
            Namespace: 'CloudFront/RealTime',
            MetricData: metricData
        }).promise();
    } catch (error) {
        console.error('Error sending CloudWatch metrics:', error);
    }
}
        '''

        # Create Lambda function
        function = lambda_.Function(
            self, "LogProcessor",
            function_name=f"cf-monitoring-{suffix}-log-processor",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "METRICS_TABLE": self.metrics_table.table_name,
                "PROCESSED_STREAM": self.processed_stream.stream_name
            },
            layers=[
                lambda_.LayerVersion.from_layer_version_arn(
                    self, "GeoIPLayer",
                    # Note: You would need to create a layer with geoip-lite package
                    layer_version_arn=f"arn:aws:lambda:{self.region}:553035198032:layer:nodejs18:5"
                )
            ]
        )

        # Add Kinesis event source
        function.add_event_source(
            lambda_event_sources.KinesisEventSource(
                stream=self.raw_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=100,
                max_batching_window=Duration.seconds(5)
            )
        )

        CfnOutput(
            self, "LogProcessorFunctionName",
            value=function.function_name,
            description="Lambda function for processing CloudFront logs"
        )

        return function

    def _create_cloudfront_distribution(self, suffix: str) -> cloudfront.Distribution:
        """Create CloudFront distribution with Origin Access Control"""
        
        # Create Origin Access Control
        oac = cloudfront.OriginAccessControl(
            self, "OriginAccessControl",
            description="Origin Access Control for monitoring demo",
            origin_access_control_origin_type=cloudfront.OriginAccessControlOriginType.S3,
            signing_behavior=cloudfront.OriginAccessControlSigningBehavior.ALWAYS,
            signing_protocol=cloudfront.OriginAccessControlSigningProtocol.SIGV4
        )

        # Create CloudFront distribution
        distribution = cloudfront.Distribution(
            self, "Distribution",
            comment="CloudFront distribution for real-time monitoring demo",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    bucket=self.content_bucket,
                    origin_access_control=oac
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                compress=True,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
            ),
            additional_behaviors={
                "/api/*": cloudfront.BehaviorOptions(
                    origin=origins.S3Origin(
                        bucket=self.content_bucket,
                        origin_access_control=oac
                    ),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                    compress=True,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_ALL,
                )
            },
            default_root_object="index.html",
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            http_version=cloudfront.HttpVersion.HTTP2,
            enable_ipv6=True,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021
        )

        # Grant CloudFront access to S3 bucket
        self.content_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[f"{self.content_bucket.bucket_arn}/*"],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{distribution.distribution_id}"
                    }
                }
            )
        )

        CfnOutput(
            self, "CloudFrontDistributionId",
            value=distribution.distribution_id,
            description="CloudFront distribution ID"
        )

        CfnOutput(
            self, "CloudFrontDomainName",
            value=distribution.distribution_domain_name,
            description="CloudFront distribution domain name"
        )

        CfnOutput(
            self, "CloudFrontURL",
            value=f"https://{distribution.distribution_domain_name}",
            description="CloudFront distribution URL"
        )

        return distribution

    def _create_firehose_delivery_stream(self, suffix: str) -> firehose.CfnDeliveryStream:
        """Create Kinesis Data Firehose delivery stream"""
        
        # Create IAM role for Firehose
        firehose_role = iam.Role(
            self, "FirehoseRole",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            inline_policies={
                "FirehoseDeliveryPolicy": iam.PolicyDocument(
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
                                self.logs_bucket.bucket_arn,
                                f"{self.logs_bucket.bucket_arn}/*"
                            ]
                        ),
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
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["logs:PutLogEvents"],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Create delivery stream
        delivery_stream = firehose.CfnDeliveryStream(
            self, "FirehoseDeliveryStream",
            delivery_stream_name=f"cf-monitoring-{suffix}-logs-to-s3-opensearch",
            delivery_stream_type="KinesisStreamAsSource",
            kinesis_stream_source_configuration=firehose.CfnDeliveryStream.KinesisStreamSourceConfigurationProperty(
                kinesis_stream_arn=self.processed_stream.stream_arn,
                role_arn=firehose_role.role_arn
            ),
            extended_s3_destination_configuration=firehose.CfnDeliveryStream.ExtendedS3DestinationConfigurationProperty(
                role_arn=firehose_role.role_arn,
                bucket_arn=self.logs_bucket.bucket_arn,
                prefix="cloudfront-logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
                buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                    size_in_m_bs=5,
                    interval_in_seconds=60
                ),
                compression_format="GZIP",
                cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                    enabled=True,
                    log_group_name=f"/aws/kinesisfirehose/cf-monitoring-{suffix}",
                    log_stream_name="S3Delivery"
                )
            )
        )

        CfnOutput(
            self, "FirehoseDeliveryStreamName",
            value=delivery_stream.delivery_stream_name or "",
            description="Kinesis Data Firehose delivery stream name"
        )

        return delivery_stream

    def _create_cloudwatch_dashboard(self, suffix: str) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring"""
        
        dashboard = cloudwatch.Dashboard(
            self, "MonitoringDashboard",
            dashboard_name=f"CloudFront-RealTime-Analytics-{suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Real-time Traffic Volume",
                        left=[
                            cloudwatch.Metric(
                                namespace="CloudFront/RealTime",
                                metric_name="RequestCount",
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="CloudFront/RealTime",
                                metric_name="BytesDownloaded",
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    ),
                    cloudwatch.GraphWidget(
                        title="Real-time Error Rates",
                        left=[
                            cloudwatch.Metric(
                                namespace="CloudFront/RealTime",
                                metric_name="ErrorRate4xx",
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="CloudFront/RealTime",
                                metric_name="ErrorRate5xx",
                                statistic="Average"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Cache Performance",
                        left=[
                            cloudwatch.Metric(
                                namespace="CloudFront/RealTime",
                                metric_name="CacheMissRate",
                                statistic="Average"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    ),
                    cloudwatch.GraphWidget(
                        title="Log Processing Performance",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Duration",
                                dimensions_map={
                                    "FunctionName": self.log_processor.function_name
                                },
                                statistic="Average"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Invocations",
                                dimensions_map={
                                    "FunctionName": self.log_processor.function_name
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Lambda",
                                metric_name="Errors",
                                dimensions_map={
                                    "FunctionName": self.log_processor.function_name
                                },
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Kinesis Stream Activity",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Kinesis",
                                metric_name="IncomingRecords",
                                dimensions_map={
                                    "StreamName": self.raw_stream.stream_name
                                },
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/Kinesis",
                                metric_name="OutgoingRecords",
                                dimensions_map={
                                    "StreamName": self.raw_stream.stream_name
                                },
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    ),
                    cloudwatch.GraphWidget(
                        title="CloudFront Standard Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="Requests",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Sum",
                                region="us-east-1"  # CloudFront metrics are in us-east-1
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="BytesDownloaded",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Sum",
                                region="us-east-1"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    )
                ]
            ]
        )

        CfnOutput(
            self, "CloudWatchDashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={dashboard.dashboard_name}",
            description="CloudWatch dashboard URL for monitoring"
        )

        return dashboard

    def _deploy_sample_content(self) -> None:
        """Deploy sample content to S3 bucket"""
        
        # Create sample content files
        sample_content = {
            "index.html": '''<!DOCTYPE html>
<html>
<head>
    <title>CloudFront Monitoring Demo</title>
    <link rel="stylesheet" href="/css/style.css">
    <script src="/js/app.js"></script>
</head>
<body>
    <h1>Welcome to CloudFront Monitoring Demo</h1>
    <p>This page generates traffic for monitoring analysis.</p>
    <img src="/images/demo.jpg" alt="Demo Image" width="300">
    <div id="content"></div>
</body>
</html>''',
            "css/style.css": "body { font-family: Arial, sans-serif; margin: 40px; }",
            "js/app.js": '''console.log("Page loaded"); 
fetch("/api/data")
    .then(r => r.json())
    .then(d => document.getElementById("content").innerHTML = JSON.stringify(d));''',
            "api/data": '{"message": "Hello from API", "timestamp": "2025-01-12T00:00:00.000Z", "version": "1.0"}'
        }

        # Deploy content using S3 deployment
        s3_deployment.BucketDeployment(
            self, "DeployContent",
            sources=[s3_deployment.Source.data("index.html", sample_content["index.html"]),
                    s3_deployment.Source.data("css/style.css", sample_content["css/style.css"]),
                    s3_deployment.Source.data("js/app.js", sample_content["js/app.js"]),
                    s3_deployment.Source.data("api/data", sample_content["api/data"])],
            destination_bucket=self.content_bucket,
            cache_control=[
                s3_deployment.CacheControl.max_age(Duration.hours(1))
            ]
        )

    def _output_real_time_logging_instructions(self) -> None:
        """Output instructions for configuring real-time logging"""
        
        CfnOutput(
            self, "RealTimeLoggingInstructions",
            value=f"Manual Step: Configure real-time logging in CloudFront console for distribution {self.distribution.distribution_id} to stream {self.raw_stream.stream_name}",
            description="Instructions for enabling real-time logging"
        )

        CfnOutput(
            self, "KinesisStreamArn",
            value=self.raw_stream.stream_arn,
            description="Kinesis stream ARN for real-time logging configuration"
        )


def main():
    """Main CDK application entry point"""
    app = cdk.App()
    
    # Get stack name from context or use default
    stack_name = app.node.try_get_context("stack_name") or "CloudFrontMonitoringStack"
    
    # Create the stack
    CloudFrontMonitoringStack(
        app, 
        stack_name,
        description="CloudFront Real-time Monitoring and Analytics Stack",
        env=cdk.Environment(
            account=app.account,
            region=app.region
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()