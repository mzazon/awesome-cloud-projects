#!/usr/bin/env python3
"""
CDK Python Application for CloudFront Cache Invalidation Strategies

This application deploys a comprehensive CloudFront cache invalidation system
that automatically detects content changes, applies selective invalidation patterns,
optimizes costs through batch processing, and provides comprehensive monitoring.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_cloudfront as cloudfront,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_sqs as sqs,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_s3_notifications as s3_notifications,
    aws_cloudfront_origins as origins,
    aws_apigateway as apigateway,
    CfnOutput,
    Fn,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct
import json


class CloudFrontInvalidationStack(Stack):
    """
    CDK Stack for CloudFront Cache Invalidation Strategies
    
    This stack creates:
    - S3 bucket for content origin
    - CloudFront distribution with optimized cache behaviors
    - Lambda function for intelligent invalidation processing
    - DynamoDB table for invalidation logging
    - SQS queues for batch processing
    - EventBridge custom bus and rules
    - CloudWatch dashboard for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        random_suffix = secretsmanager.Secret.from_secret_name_v2(
            self, "RandomSuffix",
            secret_name="cloudfront-invalidation-suffix"
        ).secret_value.unsafe_unwrap()

        # Create S3 bucket for content origin
        self.content_bucket = s3.Bucket(
            self, "ContentBucket",
            bucket_name=f"cf-origin-content-{random_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            event_bridge_enabled=True,
            cors=[
                s3.CorsRule(
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
                    allowed_origins=["*"],
                    allowed_headers=["*"],
                    max_age=3600,
                )
            ],
        )

        # Create DynamoDB table for invalidation logging
        self.invalidation_table = dynamodb.Table(
            self, "InvalidationTable",
            table_name=f"cf-invalidation-log-{random_suffix}",
            partition_key=dynamodb.Attribute(
                name="InvalidationId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            time_to_live_attribute="TTL",
            point_in_time_recovery=True,
        )

        # Create SQS queues for batch processing
        self.dead_letter_queue = sqs.Queue(
            self, "DeadLetterQueue",
            queue_name=f"cf-invalidation-dlq-{random_suffix}",
            retention_period=Duration.days(14),
            removal_policy=RemovalPolicy.DESTROY,
        )

        self.batch_queue = sqs.Queue(
            self, "BatchQueue",
            queue_name=f"cf-invalidation-batch-{random_suffix}",
            visibility_timeout=Duration.minutes(5),
            retention_period=Duration.days(14),
            receive_message_wait_time=Duration.seconds(20),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=self.dead_letter_queue
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create custom EventBridge bus
        self.event_bus = events.EventBus(
            self, "EventBus",
            event_bus_name=f"cf-invalidation-events-{random_suffix}",
        )

        # Create Origin Access Control for CloudFront
        self.origin_access_control = cloudfront.CfnOriginAccessControl(
            self, "OriginAccessControl",
            origin_access_control_config=cloudfront.CfnOriginAccessControl.OriginAccessControlConfigProperty(
                name=f"cf-invalidation-oac-{random_suffix}",
                origin_access_control_origin_type="s3",
                signing_behavior="always",
                signing_protocol="sigv4",
                description="Origin Access Control for CloudFront invalidation demo",
            )
        )

        # Create CloudFront distribution
        self.distribution = cloudfront.Distribution(
            self, "Distribution",
            comment="CloudFront distribution for invalidation strategies",
            default_behavior=cloudfront.BehaviorOptions(
                origin=origins.S3Origin(
                    bucket=self.content_bucket,
                    origin_access_identity=None,  # Using OAC instead
                ),
                viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
                cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                compress=True,
            ),
            additional_behaviors={
                "/api/*": cloudfront.BehaviorOptions(
                    origin=origins.S3Origin(
                        bucket=self.content_bucket,
                        origin_access_identity=None,
                    ),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    compress=True,
                ),
                "/css/*": cloudfront.BehaviorOptions(
                    origin=origins.S3Origin(
                        bucket=self.content_bucket,
                        origin_access_identity=None,
                    ),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    compress=True,
                ),
                "/js/*": cloudfront.BehaviorOptions(
                    origin=origins.S3Origin(
                        bucket=self.content_bucket,
                        origin_access_identity=None,
                    ),
                    viewer_protocol_policy=cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
                    cache_policy=cloudfront.CachePolicy.CACHING_OPTIMIZED_FOR_UNCOMPRESSED_OBJECTS,
                    allowed_methods=cloudfront.AllowedMethods.ALLOW_GET_HEAD,
                    compress=True,
                ),
            },
            default_root_object="index.html",
            price_class=cloudfront.PriceClass.PRICE_CLASS_100,
            enabled=True,
            http_version=cloudfront.HttpVersion.HTTP2,
            enable_ipv6=True,
            minimum_protocol_version=cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
        )

        # Update the distribution to use OAC
        cfn_distribution = self.distribution.node.default_child
        cfn_distribution.add_property_override(
            "DistributionConfig.Origins.0.OriginAccessControlId",
            self.origin_access_control.attr_id
        )
        cfn_distribution.add_property_override(
            "DistributionConfig.Origins.0.S3OriginConfig.OriginAccessIdentity",
            ""
        )

        # Grant CloudFront access to S3 bucket
        self.content_bucket.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("cloudfront.amazonaws.com")],
                actions=["s3:GetObject"],
                resources=[self.content_bucket.arn_for_objects("*")],
                conditions={
                    "StringEquals": {
                        "AWS:SourceArn": f"arn:aws:cloudfront::{self.account}:distribution/{self.distribution.distribution_id}"
                    }
                },
            )
        )

        # Create Lambda function for intelligent invalidation
        self.invalidation_function = lambda_.Function(
            self, "InvalidationFunction",
            function_name=f"cf-invalidation-processor-{random_suffix}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "DDB_TABLE_NAME": self.invalidation_table.table_name,
                "QUEUE_URL": self.batch_queue.queue_url,
                "DISTRIBUTION_ID": self.distribution.distribution_id,
                "BATCH_SIZE": "10",
            },
            dead_letter_queue=self.dead_letter_queue,
            retry_attempts=2,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
        )

        # Grant Lambda permissions
        self.invalidation_table.grant_read_write_data(self.invalidation_function)
        self.batch_queue.grant_send_messages(self.invalidation_function)
        self.batch_queue.grant_consume_messages(self.invalidation_function)
        self.dead_letter_queue.grant_send_messages(self.invalidation_function)

        # Grant CloudFront invalidation permissions
        self.invalidation_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudfront:CreateInvalidation",
                    "cloudfront:GetInvalidation",
                    "cloudfront:ListInvalidations",
                ],
                resources=["*"],
            )
        )

        # Create EventBridge rules
        self.s3_rule = events.Rule(
            self, "S3Rule",
            rule_name=f"cf-invalidation-s3-rule-{random_suffix}",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["Object Created", "Object Deleted"],
                detail={
                    "bucket": {
                        "name": [self.content_bucket.bucket_name]
                    }
                },
            ),
            targets=[events_targets.LambdaFunction(self.invalidation_function)],
        )

        self.deploy_rule = events.Rule(
            self, "DeployRule",
            rule_name=f"cf-invalidation-deploy-rule-{random_suffix}",
            event_bus=self.event_bus,
            event_pattern=events.EventPattern(
                source=["aws.codedeploy", "custom.app"],
                detail_type=["Deployment State-change Notification", "Application Deployment"],
            ),
            targets=[events_targets.LambdaFunction(self.invalidation_function)],
        )

        # Create SQS event source mapping
        self.invalidation_function.add_event_source(
            lambda_.SqsEventSource(
                queue=self.batch_queue,
                batch_size=5,
                max_batching_window=Duration.seconds(30),
                report_batch_item_failures=True,
            )
        )

        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "Dashboard",
            dashboard_name=f"CloudFront-Invalidation-{random_suffix}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="CloudFront Performance",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="Requests",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/CloudFront",
                                metric_name="CacheHitRate",
                                dimensions_map={
                                    "DistributionId": self.distribution.distribution_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                    cloudwatch.GraphWidget(
                        title="Invalidation Function Performance",
                        left=[
                            self.invalidation_function.metric_duration(
                                statistic="Average",
                                period=Duration.minutes(5)
                            ),
                            self.invalidation_function.metric_invocations(
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                            self.invalidation_function.metric_errors(
                                statistic="Sum",
                                period=Duration.minutes(5)
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Event Processing Volume",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Events",
                                metric_name="MatchedEvents",
                                dimensions_map={
                                    "EventBusName": self.event_bus.event_bus_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SQS",
                                metric_name="NumberOfMessagesSent",
                                dimensions_map={
                                    "QueueName": self.batch_queue.queue_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/SQS",
                                metric_name="NumberOfMessagesReceived",
                                dimensions_map={
                                    "QueueName": self.batch_queue.queue_name
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            ),
                        ],
                        width=24,
                        height=6,
                    ),
                ],
            ],
        )

        # Create CloudWatch alarms
        self.high_error_rate_alarm = cloudwatch.Alarm(
            self, "HighErrorRateAlarm",
            alarm_name=f"cf-invalidation-high-error-rate-{random_suffix}",
            alarm_description="High error rate in invalidation function",
            metric=self.invalidation_function.metric_errors(
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        self.low_cache_hit_rate_alarm = cloudwatch.Alarm(
            self, "LowCacheHitRateAlarm",
            alarm_name=f"cf-invalidation-low-cache-hit-rate-{random_suffix}",
            alarm_description="Low CloudFront cache hit rate",
            metric=cloudwatch.Metric(
                namespace="AWS/CloudFront",
                metric_name="CacheHitRate",
                dimensions_map={
                    "DistributionId": self.distribution.distribution_id
                },
                statistic="Average",
                period=Duration.minutes(15),
            ),
            threshold=70,
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Outputs
        CfnOutput(
            self, "ContentBucketName",
            description="S3 bucket for content origin",
            value=self.content_bucket.bucket_name,
        )

        CfnOutput(
            self, "DistributionId",
            description="CloudFront distribution ID",
            value=self.distribution.distribution_id,
        )

        CfnOutput(
            self, "DistributionDomainName",
            description="CloudFront distribution domain name",
            value=self.distribution.distribution_domain_name,
        )

        CfnOutput(
            self, "InvalidationTableName",
            description="DynamoDB table for invalidation logging",
            value=self.invalidation_table.table_name,
        )

        CfnOutput(
            self, "EventBusName",
            description="EventBridge custom bus name",
            value=self.event_bus.event_bus_name,
        )

        CfnOutput(
            self, "LambdaFunctionName",
            description="Lambda function for invalidation processing",
            value=self.invalidation_function.function_name,
        )

        CfnOutput(
            self, "DashboardUrl",
            description="CloudWatch dashboard URL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for intelligent invalidation processing.
        This function implements sophisticated business logic for analyzing content
        changes and determining optimal invalidation strategies.
        """
        return """
const AWS = require('aws-sdk');
const cloudfront = new AWS.CloudFront();
const dynamodb = new AWS.DynamoDB.DocumentClient();
const sqs = new AWS.SQS();

const TABLE_NAME = process.env.DDB_TABLE_NAME;
const QUEUE_URL = process.env.QUEUE_URL;
const DISTRIBUTION_ID = process.env.DISTRIBUTION_ID;
const BATCH_SIZE = parseInt(process.env.BATCH_SIZE || '10');

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        let invalidationPaths = [];
        
        // Process different event sources
        if (event.source === 'aws.s3') {
            invalidationPaths = await processS3Event(event);
        } else if (event.source === 'aws.codedeploy' || event.source === 'custom.app') {
            invalidationPaths = await processDeploymentEvent(event);
        } else if (event.Records) {
            // SQS batch processing
            invalidationPaths = await processSQSBatch(event);
        }
        
        if (invalidationPaths.length === 0) {
            console.log('No invalidation paths to process');
            return { statusCode: 200, body: 'No invalidation needed' };
        }
        
        // Optimize paths using intelligent grouping
        const optimizedPaths = optimizeInvalidationPaths(invalidationPaths);
        
        // Create invalidation batches
        const batches = createBatches(optimizedPaths, BATCH_SIZE);
        
        const results = [];
        for (const batch of batches) {
            const result = await createInvalidation(batch);
            results.push(result);
            
            // Log invalidation to DynamoDB
            await logInvalidation(result.Invalidation.Id, batch, event);
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                message: 'Invalidations created successfully',
                invalidations: results.length,
                paths: optimizedPaths.length
            })
        };
        
    } catch (error) {
        console.error('Error processing invalidation:', error);
        
        // Send failed paths to DLQ for retry
        if (event.source && invalidationPaths.length > 0) {
            await sendToDeadLetterQueue(invalidationPaths, error);
        }
        
        throw error;
    }
};

async function processS3Event(event) {
    const paths = [];
    
    if (event.detail && event.detail.object) {
        const objectKey = event.detail.object.key;
        const eventName = event['detail-type'];
        
        // Smart path invalidation based on content type
        if (objectKey.endsWith('.html')) {
            paths.push(`/${objectKey}`);
            // Also invalidate directory index
            if (objectKey.includes('/')) {
                const dir = objectKey.substring(0, objectKey.lastIndexOf('/'));
                paths.push(`/${dir}/`);
            }
        } else if (objectKey.match(/\\.(css|js|json)$/)) {
            // Invalidate specific asset
            paths.push(`/${objectKey}`);
            
            // For CSS/JS changes, also invalidate HTML pages that might reference them
            if (objectKey.includes('css/') || objectKey.includes('js/')) {
                paths.push('/index.html');
                paths.push('/');
            }
        } else if (objectKey.match(/\\.(jpg|jpeg|png|gif|webp|svg)$/)) {
            // Image invalidation
            paths.push(`/${objectKey}`);
        }
    }
    
    return [...new Set(paths)]; // Remove duplicates
}

async function processDeploymentEvent(event) {
    // For deployment events, invalidate common paths
    const deploymentPaths = [
        '/',
        '/index.html',
        '/css/*',
        '/js/*',
        '/api/*'
    ];
    
    // If deployment includes specific file changes, add them
    if (event.detail && event.detail.changedFiles) {
        event.detail.changedFiles.forEach(file => {
            deploymentPaths.push(`/${file}`);
        });
    }
    
    return deploymentPaths;
}

async function processSQSBatch(event) {
    const paths = [];
    
    for (const record of event.Records) {
        try {
            const body = JSON.parse(record.body);
            if (body.paths && Array.isArray(body.paths)) {
                paths.push(...body.paths);
            }
        } catch (error) {
            console.error('Error parsing SQS message:', error);
        }
    }
    
    return [...new Set(paths)];
}

function optimizeInvalidationPaths(paths) {
    // Remove redundant paths and optimize patterns
    const optimized = new Set();
    const sorted = paths.sort();
    
    for (const path of sorted) {
        let isRedundant = false;
        
        // Check if this path is covered by an existing wildcard
        for (const existing of optimized) {
            if (existing.endsWith('/*') && path.startsWith(existing.slice(0, -1))) {
                isRedundant = true;
                break;
            }
        }
        
        if (!isRedundant) {
            optimized.add(path);
        }
    }
    
    return Array.from(optimized);
}

function createBatches(paths, batchSize) {
    const batches = [];
    for (let i = 0; i < paths.length; i += batchSize) {
        batches.push(paths.slice(i, i + batchSize));
    }
    return batches;
}

async function createInvalidation(paths) {
    const params = {
        DistributionId: DISTRIBUTION_ID,
        InvalidationBatch: {
            Paths: {
                Quantity: paths.length,
                Items: paths
            },
            CallerReference: `invalidation-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`
        }
    };
    
    console.log('Creating invalidation for paths:', paths);
    return await cloudfront.createInvalidation(params).promise();
}

async function logInvalidation(invalidationId, paths, originalEvent) {
    const params = {
        TableName: TABLE_NAME,
        Item: {
            InvalidationId: invalidationId,
            Timestamp: new Date().toISOString(),
            Paths: paths,
            PathCount: paths.length,
            Source: originalEvent.source || 'unknown',
            EventType: originalEvent['detail-type'] || 'unknown',
            Status: 'InProgress',
            TTL: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days
        }
    };
    
    await dynamodb.put(params).promise();
}

async function sendToDeadLetterQueue(paths, error) {
    const message = {
        paths: paths,
        error: error.message,
        timestamp: new Date().toISOString()
    };
    
    const dlqUrl = QUEUE_URL.replace('batch-queue', 'dlq');
    const params = {
        QueueUrl: dlqUrl,
        MessageBody: JSON.stringify(message)
    };
    
    await sqs.sendMessage(params).promise();
}
"""


# Create the CDK app
app = cdk.App()

# Create the stack
CloudFrontInvalidationStack(
    app, 
    "CloudFrontInvalidationStack",
    description="Intelligent CloudFront cache invalidation system with automated event processing and cost optimization",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region") or "us-east-1",
    ),
)

# Synthesize the CloudFormation template
app.synth()