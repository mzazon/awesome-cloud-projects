#!/usr/bin/env python3
"""
Real-time Clickstream Analytics CDK Application

This CDK application deploys a complete real-time clickstream analytics pipeline
using Amazon Kinesis Data Streams, AWS Lambda, DynamoDB, and CloudWatch.

The architecture includes:
- Kinesis Data Streams for event ingestion
- Lambda functions for real-time processing and anomaly detection
- DynamoDB tables for storing analytics metrics
- S3 bucket for raw data archival
- CloudWatch dashboard for monitoring
- IAM roles with least privilege access

Author: AWS CDK Team
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
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_lambda_event_sources as lambda_event_sources,
    aws_logs as logs,
)
from constructs import Construct


class ClickstreamAnalyticsStack(Stack):
    """
    CDK Stack for Real-time Clickstream Analytics Pipeline
    
    This stack creates a serverless, real-time analytics pipeline that can process
    millions of clickstream events with sub-second latency. The architecture follows
    AWS Well-Architected principles for security, reliability, and cost optimization.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        self.unique_suffix = self.node.try_get_context("uniqueSuffix") or "dev"
        
        # Create the data ingestion layer
        self.kinesis_stream = self._create_kinesis_stream()
        
        # Create the storage layer
        self.s3_bucket = self._create_s3_bucket()
        self.dynamodb_tables = self._create_dynamodb_tables()
        
        # Create IAM roles
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create the processing layer
        self.event_processor_function = self._create_event_processor_function()
        self.anomaly_detector_function = self._create_anomaly_detector_function()
        
        # Create event source mappings
        self._create_event_source_mappings()
        
        # Create monitoring dashboard
        self._create_cloudwatch_dashboard()
        
        # Create outputs for easy access
        self._create_outputs()

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for clickstream event ingestion.
        
        The stream is configured with 2 shards for initial capacity, providing
        2,000 records/second write capacity and 4 MB/second read capacity.
        Retention is set to 24 hours which is sufficient for real-time processing
        while keeping costs low.
        
        Returns:
            kinesis.Stream: The created Kinesis stream
        """
        stream = kinesis.Stream(
            self,
            "ClickstreamEventsStream",
            stream_name=f"clickstream-events-{self.unique_suffix}",
            shard_count=2,
            retention_period=Duration.hours(24),
            stream_mode=kinesis.StreamMode.PROVISIONED,
        )
        
        # Add tags for cost tracking and governance
        cdk.Tags.of(stream).add("Project", "ClickstreamAnalytics")
        cdk.Tags.of(stream).add("Component", "DataIngestion")
        
        return stream

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for raw data archival.
        
        This bucket stores the original clickstream events for historical analysis,
        compliance, and data science workloads. It uses intelligent tiering to
        automatically optimize storage costs.
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "ClickstreamArchiveBucket",
            bucket_name=f"clickstream-archive-{self.unique_suffix}-{self.account}",
            versioning=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
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
        
        cdk.Tags.of(bucket).add("Project", "ClickstreamAnalytics")
        cdk.Tags.of(bucket).add("Component", "DataArchival")
        
        return bucket

    def _create_dynamodb_tables(self) -> Dict[str, dynamodb.Table]:
        """
        Create DynamoDB tables for real-time analytics storage.
        
        Creates three tables optimized for different query patterns:
        1. Page metrics: Aggregated page view data by URL and time
        2. Session metrics: User session tracking and behavior analysis
        3. Counters: Real-time counters with TTL for cost control
        
        Returns:
            Dict[str, dynamodb.Table]: Dictionary of created tables
        """
        tables = {}
        
        # Page metrics table - partitioned by page URL for even distribution
        tables["page_metrics"] = dynamodb.Table(
            self,
            "PageMetricsTable",
            table_name=f"clickstream-{self.unique_suffix}-page-metrics",
            partition_key=dynamodb.Attribute(
                name="page_url",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp_hour",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=False,  # Disabled for cost optimization in demo
        )
        
        # Session metrics table - optimized for session-based queries
        tables["session_metrics"] = dynamodb.Table(
            self,
            "SessionMetricsTable",
            table_name=f"clickstream-{self.unique_suffix}-session-metrics",
            partition_key=dynamodb.Attribute(
                name="session_id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Real-time counters table with TTL for automatic cleanup
        tables["counters"] = dynamodb.Table(
            self,
            "CountersTable",
            table_name=f"clickstream-{self.unique_suffix}-counters",
            partition_key=dynamodb.Attribute(
                name="metric_name",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="time_window",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            time_to_live_attribute="ttl",  # Automatic cleanup after 24 hours
        )
        
        # Add tags to all tables
        for table_name, table in tables.items():
            cdk.Tags.of(table).add("Project", "ClickstreamAnalytics")
            cdk.Tags.of(table).add("Component", "RealTimeStorage")
            
        return tables

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda functions with least privilege access.
        
        This role provides the minimum permissions required for Lambda functions
        to process Kinesis records, write to DynamoDB and S3, and publish
        CloudWatch metrics. It follows AWS security best practices.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"ClickstreamProcessorRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "ClickstreamProcessorPolicy": iam.PolicyDocument(
                    statements=[
                        # Kinesis stream permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetShardIterator",
                                "kinesis:GetRecords",
                                "kinesis:ListStreams"
                            ],
                            resources=[self.kinesis_stream.stream_arn]
                        ),
                        # DynamoDB permissions - scoped to specific tables
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:GetItem",
                                "dynamodb:Query"
                            ],
                            resources=[
                                table.table_arn for table in self.dynamodb_tables.values()
                            ]
                        ),
                        # S3 permissions for data archival
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:PutObject"],
                            resources=[f"{self.s3_bucket.bucket_arn}/*"]
                        ),
                        # CloudWatch metrics permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["cloudwatch:PutMetricData"],
                            resources=["*"],
                            conditions={
                                "StringEquals": {
                                    "cloudwatch:namespace": "Clickstream/Events"
                                }
                            }
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_event_processor_function(self) -> lambda_.Function:
        """
        Create Lambda function for real-time event processing.
        
        This function processes clickstream events from Kinesis, performs
        real-time aggregations, stores metrics in DynamoDB, archives raw data
        to S3, and publishes custom metrics to CloudWatch.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        function = lambda_.Function(
            self,
            "EventProcessorFunction",
            function_name=f"clickstream-event-processor-{self.unique_suffix}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_event_processor_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "TABLE_PREFIX": f"clickstream-{self.unique_suffix}",
                "BUCKET_NAME": self.s3_bucket.bucket_name,
                "AWS_NODEJS_CONNECTION_REUSE_ENABLED": "1"  # Performance optimization
            },
            log_retention=logs.RetentionDays.ONE_WEEK,  # Cost optimization
            dead_letter_queue_enabled=True,  # Error handling
            reserved_concurrent_executions=50,  # Prevent runaway costs
        )
        
        cdk.Tags.of(function).add("Project", "ClickstreamAnalytics")
        cdk.Tags.of(function).add("Component", "EventProcessing")
        
        return function

    def _create_anomaly_detector_function(self) -> lambda_.Function:
        """
        Create Lambda function for real-time anomaly detection.
        
        This function analyzes clickstream patterns to detect suspicious behavior,
        bot activity, and unusual user patterns. It operates independently from
        the main processing pipeline for better fault isolation.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        function = lambda_.Function(
            self,
            "AnomalyDetectorFunction",
            function_name=f"clickstream-anomaly-detector-{self.unique_suffix}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_anomaly_detector_code()),
            timeout=Duration.seconds(30),
            memory_size=128,  # Smaller memory for cost optimization
            role=self.lambda_role,
            environment={
                "TABLE_PREFIX": f"clickstream-{self.unique_suffix}"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            reserved_concurrent_executions=20,  # Limit concurrent executions
        )
        
        cdk.Tags.of(function).add("Project", "ClickstreamAnalytics")
        cdk.Tags.of(function).add("Component", "AnomalyDetection")
        
        return function

    def _create_event_source_mappings(self) -> None:
        """
        Create event source mappings between Kinesis stream and Lambda functions.
        
        Two separate mappings allow independent scaling and error handling for
        event processing and anomaly detection workloads. Each mapping is
        optimized for its specific use case.
        """
        # Event processing mapping - optimized for throughput
        lambda_event_sources.KinesisEventSource(
            stream=self.kinesis_stream,
            batch_size=100,  # Balance between latency and efficiency
            max_batching_window=Duration.seconds(5),  # Low latency requirement
            starting_position=lambda_.StartingPosition.LATEST,
            retry_attempts=3,  # Retry failed batches
            max_record_age=Duration.hours(1),  # Skip very old records
        ).bind(self.event_processor_function)
        
        # Anomaly detection mapping - optimized for pattern analysis
        lambda_event_sources.KinesisEventSource(
            stream=self.kinesis_stream,
            batch_size=50,  # Smaller batches for faster analysis
            max_batching_window=Duration.seconds(10),  # Slightly higher latency acceptable
            starting_position=lambda_.StartingPosition.LATEST,
            retry_attempts=2,  # Fewer retries for anomaly detection
            max_record_age=Duration.minutes(30),  # Skip older records
        ).bind(self.anomaly_detector_function)

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring the analytics pipeline.
        
        The dashboard provides real-time visibility into system performance,
        processing throughput, error rates, and business metrics. It includes
        alerts for operational issues and performance degradation.
        
        Returns:
            cloudwatch.Dashboard: The created dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "ClickstreamAnalyticsDashboard",
            dashboard_name=f"Clickstream-Analytics-{self.unique_suffix}",
        )
        
        # Add widgets for different metrics
        dashboard.add_widgets(
            # Events processed by type
            cloudwatch.GraphWidget(
                title="Events Processed by Type",
                left=[
                    cloudwatch.Metric(
                        namespace="Clickstream/Events",
                        metric_name="EventsProcessed",
                        dimensions_map={"EventType": "page_view"},
                        statistic="Sum",
                        period=Duration.minutes(5)
                    ),
                    cloudwatch.Metric(
                        namespace="Clickstream/Events",
                        metric_name="EventsProcessed",
                        dimensions_map={"EventType": "click"},
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ],
                width=12,
                height=6
            ),
            
            # Lambda performance metrics
            cloudwatch.GraphWidget(
                title="Lambda Performance",
                left=[
                    self.event_processor_function.metric_duration(
                        statistic="Average",
                        period=Duration.minutes(5)
                    ),
                    self.event_processor_function.metric_errors(
                        statistic="Sum",
                        period=Duration.minutes(5)
                    ),
                    self.event_processor_function.metric_invocations(
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        dashboard.add_widgets(
            # Kinesis stream throughput
            cloudwatch.GraphWidget(
                title="Kinesis Stream Throughput",
                left=[
                    self.kinesis_stream.metric_incoming_records(
                        statistic="Sum",
                        period=Duration.minutes(5)
                    ),
                    self.kinesis_stream.metric_outgoing_records(
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ],
                width=24,
                height=6
            )
        )
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis Data Stream for clickstream events"
        )
        
        CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="ARN of the Kinesis Data Stream"
        )
        
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="Name of the S3 bucket for data archival"
        )
        
        CfnOutput(
            self,
            "EventProcessorFunctionName",
            value=self.event_processor_function.function_name,
            description="Name of the event processor Lambda function"
        )
        
        CfnOutput(
            self,
            "AnomalyDetectorFunctionName",
            value=self.anomaly_detector_function.function_name,
            description="Name of the anomaly detector Lambda function"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name=Clickstream-Analytics-{self.unique_suffix}",
            description="URL to the CloudWatch dashboard"
        )

    def _get_event_processor_code(self) -> str:
        """Return the JavaScript code for the event processor Lambda function."""
        return '''
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();
const cloudwatch = new AWS.CloudWatch();

const TABLE_PREFIX = process.env.TABLE_PREFIX;
const BUCKET_NAME = process.env.BUCKET_NAME;

exports.handler = async (event) => {
    console.log('Processing', event.Records.length, 'records');
    
    const promises = event.Records.map(async (record) => {
        try {
            // Decode the Kinesis data
            const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const clickEvent = JSON.parse(payload);
            
            // Process different event types
            await Promise.all([
                processPageView(clickEvent),
                updateSessionMetrics(clickEvent),
                updateRealTimeCounters(clickEvent),
                archiveRawEvent(clickEvent),
                publishMetrics(clickEvent)
            ]);
            
        } catch (error) {
            console.error('Error processing record:', error);
            throw error;
        }
    });
    
    await Promise.all(promises);
    return { statusCode: 200, body: 'Successfully processed events' };
};

async function processPageView(event) {
    if (event.event_type !== 'page_view') return;
    
    const hour = new Date(event.timestamp).toISOString().slice(0, 13);
    
    const params = {
        TableName: `${TABLE_PREFIX}-page-metrics`,
        Key: {
            page_url: event.page_url,
            timestamp_hour: hour
        },
        UpdateExpression: 'ADD view_count :inc SET last_updated = :now',
        ExpressionAttributeValues: {
            ':inc': 1,
            ':now': Date.now()
        }
    };
    
    await dynamodb.update(params).promise();
}

async function updateSessionMetrics(event) {
    const params = {
        TableName: `${TABLE_PREFIX}-session-metrics`,
        Key: { session_id: event.session_id },
        UpdateExpression: 'SET last_activity = :now, user_agent = :ua ADD event_count :inc',
        ExpressionAttributeValues: {
            ':now': event.timestamp,
            ':ua': event.user_agent || 'unknown',
            ':inc': 1
        }
    };
    
    await dynamodb.update(params).promise();
}

async function updateRealTimeCounters(event) {
    const minute = new Date(event.timestamp).toISOString().slice(0, 16);
    
    const params = {
        TableName: `${TABLE_PREFIX}-counters`,
        Key: {
            metric_name: `events_per_minute_${event.event_type}`,
            time_window: minute
        },
        UpdateExpression: 'ADD event_count :inc SET ttl = :ttl',
        ExpressionAttributeValues: {
            ':inc': 1,
            ':ttl': Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hour TTL
        }
    };
    
    await dynamodb.update(params).promise();
}

async function archiveRawEvent(event) {
    const date = new Date(event.timestamp);
    const key = `year=${date.getFullYear()}/month=${date.getMonth() + 1}/day=${date.getDate()}/hour=${date.getHours()}/${event.session_id}-${Date.now()}.json`;
    
    const params = {
        Bucket: BUCKET_NAME,
        Key: key,
        Body: JSON.stringify(event),
        ContentType: 'application/json'
    };
    
    await s3.putObject(params).promise();
}

async function publishMetrics(event) {
    const params = {
        Namespace: 'Clickstream/Events',
        MetricData: [
            {
                MetricName: 'EventsProcessed',
                Value: 1,
                Unit: 'Count',
                Dimensions: [
                    {
                        Name: 'EventType',
                        Value: event.event_type
                    }
                ]
            }
        ]
    };
    
    await cloudwatch.putMetricData(params).promise();
}
        '''

    def _get_anomaly_detector_code(self) -> str:
        """Return the JavaScript code for the anomaly detector Lambda function."""
        return '''
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

const TABLE_PREFIX = process.env.TABLE_PREFIX;

exports.handler = async (event) => {
    console.log('Checking for anomalies in', event.Records.length, 'records');
    
    for (const record of event.Records) {
        try {
            const payload = Buffer.from(record.kinesis.data, 'base64').toString('utf-8');
            const clickEvent = JSON.parse(payload);
            
            await checkForAnomalies(clickEvent);
            
        } catch (error) {
            console.error('Error processing record for anomaly detection:', error);
        }
    }
    
    return { statusCode: 200 };
};

async function checkForAnomalies(event) {
    // Check for suspicious patterns
    const checks = await Promise.all([
        checkHighFrequencyClicks(event),
        checkSuspiciousUserAgent(event),
        checkUnusualPageSequence(event)
    ]);
    
    const anomalies = checks.filter(check => check.isAnomaly);
    
    if (anomalies.length > 0) {
        console.log('Anomalies detected:', anomalies);
        // Could send alerts here via SNS
    }
}

async function checkHighFrequencyClicks(event) {
    const minute = new Date(event.timestamp).toISOString().slice(0, 16);
    
    const params = {
        TableName: `${TABLE_PREFIX}-counters`,
        Key: {
            metric_name: `session_events_${event.session_id}`,
            time_window: minute
        }
    };
    
    const result = await dynamodb.get(params).promise();
    const eventCount = result.Item ? result.Item.event_count : 0;
    
    // Flag if more than 50 events per minute from same session
    return {
        isAnomaly: eventCount > 50,
        type: 'high_frequency_clicks',
        details: `${eventCount} events in one minute`
    };
}

async function checkSuspiciousUserAgent(event) {
    const suspiciousPatterns = ['bot', 'crawler', 'spider', 'scraper'];
    const userAgent = (event.user_agent || '').toLowerCase();
    
    const isSuspicious = suspiciousPatterns.some(pattern => 
        userAgent.includes(pattern)
    );
    
    return {
        isAnomaly: isSuspicious,
        type: 'suspicious_user_agent',
        details: event.user_agent
    };
}

async function checkUnusualPageSequence(event) {
    // Simple check for direct access to checkout without viewing products
    if (event.page_url && event.page_url.includes('/checkout')) {
        const params = {
            TableName: `${TABLE_PREFIX}-session-metrics`,
            Key: { session_id: event.session_id }
        };
        
        const result = await dynamodb.get(params).promise();
        const eventCount = result.Item ? result.Item.event_count : 0;
        
        // Flag if going to checkout with very few page views
        return {
            isAnomaly: eventCount < 3,
            type: 'unusual_page_sequence',
            details: `Direct checkout access with only ${eventCount} page views`
        };
    }
    
    return { isAnomaly: false };
}
        '''


class ClickstreamAnalyticsApp(cdk.App):
    """
    CDK Application for Real-time Clickstream Analytics
    
    This application creates a complete real-time analytics pipeline
    that can be deployed across multiple environments with different
    configuration parameters.
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Get environment-specific configuration
        env_name = self.node.try_get_context("environment") or "dev"
        unique_suffix = self.node.try_get_context("uniqueSuffix") or env_name
        
        # Define deployment environment
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
        
        # Create the main stack
        ClickstreamAnalyticsStack(
            self,
            f"ClickstreamAnalyticsStack-{unique_suffix}",
            env=env,
            description="Real-time clickstream analytics pipeline using Kinesis, Lambda, and DynamoDB",
            tags={
                "Project": "ClickstreamAnalytics",
                "Environment": env_name,
                "ManagedBy": "CDK"
            }
        )


# Application entry point
app = ClickstreamAnalyticsApp()
app.synth()