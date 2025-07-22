#!/usr/bin/env python3
"""
CDK Python application for Real-Time Data Transformation with Kinesis Data Firehose.

This application deploys a complete streaming data processing pipeline using:
- Amazon Kinesis Data Firehose for data ingestion and delivery
- AWS Lambda for real-time data transformation
- Amazon S3 for data storage (processed, raw backup, and error handling)
- Amazon CloudWatch for monitoring and alerting
- Amazon SNS for notifications

The pipeline processes JSON log data, performs filtering and transformation,
and delivers it to multiple S3 destinations with comprehensive monitoring.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_kinesisfirehose as firehose,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from constructs import Construct
import json


class RealTimeDataTransformationStack(Stack):
    """
    CDK Stack for Real-Time Data Transformation with Kinesis Data Firehose.
    
    This stack creates a complete serverless data processing pipeline that:
    1. Ingests streaming data through Kinesis Data Firehose
    2. Transforms data using Lambda functions
    3. Stores processed data in S3 with partitioning
    4. Provides monitoring and alerting capabilities
    5. Handles errors gracefully with backup and dead-letter queues
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 buckets for data storage
        self._create_s3_buckets()
        
        # Create Lambda function for data transformation
        self._create_lambda_function()
        
        # Create IAM role for Kinesis Data Firehose
        self._create_firehose_role()
        
        # Create Kinesis Data Firehose delivery stream
        self._create_firehose_delivery_stream()
        
        # Create monitoring and alerting resources
        self._create_monitoring_resources()
        
        # Create stack outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for processed data, raw backup, and error handling."""
        
        # Processed data bucket - stores transformed data
        self.processed_bucket = s3.Bucket(
            self, "ProcessedDataBucket",
            bucket_name=f"firehose-processed-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
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
        
        # Raw data backup bucket - stores original data before transformation
        self.raw_bucket = s3.Bucket(
            self, "RawDataBucket",
            bucket_name=f"firehose-raw-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ]
        )
        
        # Error data bucket - stores failed transformation records
        self.error_bucket = s3.Bucket(
            self, "ErrorDataBucket",
            bucket_name=f"firehose-error-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for data transformation."""
        
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "FirehoseTransformPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "firehose:DescribeDeliveryStream",
                                "firehose:ListDeliveryStreams",
                                "firehose:ListTagsForDeliveryStream"
                            ],
                            resources=["*"]
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
                            resources=[
                                self.error_bucket.bucket_arn,
                                f"{self.error_bucket.bucket_arn}/*",
                                self.processed_bucket.bucket_arn,
                                f"{self.processed_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                )
            }
        )
        
        # Lambda function code for data transformation
        lambda_code = """
/**
 * Kinesis Firehose Data Transformation Lambda
 * - Processes incoming log records
 * - Filters out records that don't match criteria
 * - Transforms and enriches valid records
 * - Returns both processed records and failed records
 */

// Configuration options
const config = {
    // Minimum log level to process (logs below this level will be filtered out)
    // Values: DEBUG, INFO, WARN, ERROR
    minLogLevel: 'INFO',
    
    // Whether to include timestamp in transformed data
    addProcessingTimestamp: true,
    
    // Fields to remove from logs for privacy/compliance (PII, etc.)
    fieldsToRedact: ['password', 'creditCard', 'ssn']
};

/**
 * Event structure expected in records:
 * {
 *   "timestamp": "2023-04-10T12:34:56Z",
 *   "level": "INFO|DEBUG|WARN|ERROR",
 *   "service": "service-name",
 *   "message": "Log message",
 *   // Additional fields...
 * }
 */
exports.handler = async (event, context) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const output = {
        records: []
    };
    
    // Process each record in the batch
    for (const record of event.records) {
        console.log('Processing record:', record.recordId);
        
        try {
            // Decode and parse the record data
            const buffer = Buffer.from(record.data, 'base64');
            const decodedData = buffer.toString('utf8');
            
            // Try to parse as JSON, fail gracefully if not valid JSON
            let parsedData;
            try {
                parsedData = JSON.parse(decodedData);
            } catch (e) {
                console.error('Invalid JSON in record:', decodedData);
                
                // Mark record as processing failed
                output.records.push({
                    recordId: record.recordId,
                    result: 'ProcessingFailed',
                    data: record.data
                });
                continue;
            }
            
            // Apply filtering logic - skip records with log level below minimum
            if (parsedData.level && 
                ['DEBUG', 'INFO', 'WARN', 'ERROR'].indexOf(parsedData.level) < 
                ['DEBUG', 'INFO', 'WARN', 'ERROR'].indexOf(config.minLogLevel)) {
                
                console.log(`Filtering out record with level ${parsedData.level}`);
                
                // Mark record as dropped
                output.records.push({
                    recordId: record.recordId,
                    result: 'Dropped', 
                    data: record.data
                });
                continue;
            }
            
            // Apply transformations
            
            // Add processing metadata
            if (config.addProcessingTimestamp) {
                parsedData.processedAt = new Date().toISOString();
            }
            
            // Add AWS request ID for traceability
            parsedData.lambdaRequestId = context.awsRequestId;
            
            // Redact any sensitive fields
            for (const field of config.fieldsToRedact) {
                if (parsedData[field]) {
                    parsedData[field] = '********';
                }
            }
            
            // Convert transformed data back to string and encode as base64
            const transformedData = JSON.stringify(parsedData) + '\\n';
            const encodedData = Buffer.from(transformedData).toString('base64');
            
            // Add transformed record to output
            output.records.push({
                recordId: record.recordId,
                result: 'Ok',
                data: encodedData
            });
            
        } catch (error) {
            console.error('Error processing record:', error);
            
            // Mark record as processing failed
            output.records.push({
                recordId: record.recordId,
                result: 'ProcessingFailed',
                data: record.data
            });
        }
    }
    
    console.log('Processing complete, returning', output.records.length, 'records');
    return output;
};
"""
        
        # Create Lambda function
        self.transform_lambda = lambda_.Function(
            self, "TransformFunction",
            function_name=f"firehose-transform-{self.account}-{self.region}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Transform function for Kinesis Data Firehose",
            environment={
                "MIN_LOG_LEVEL": "INFO",
                "ADD_PROCESSING_TIMESTAMP": "true"
            },
            retry_attempts=2,
            log_retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_firehose_role(self) -> None:
        """Create IAM role for Kinesis Data Firehose."""
        
        self.firehose_role = iam.Role(
            self, "FirehoseDeliveryRole",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            inline_policies={
                "FirehoseDeliveryPolicy": iam.PolicyDocument(
                    statements=[
                        # S3 permissions for all buckets
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
                                self.raw_bucket.bucket_arn,
                                f"{self.raw_bucket.bucket_arn}/*",
                                self.processed_bucket.bucket_arn,
                                f"{self.processed_bucket.bucket_arn}/*",
                                self.error_bucket.bucket_arn,
                                f"{self.error_bucket.bucket_arn}/*"
                            ]
                        ),
                        # Lambda permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "lambda:InvokeFunction",
                                "lambda:GetFunctionConfiguration"
                            ],
                            resources=[f"{self.transform_lambda.function_arn}:$LATEST"]
                        ),
                        # CloudWatch Logs permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:PutLogEvents",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream"
                            ],
                            resources=["arn:aws:logs:*:*:*"]
                        ),
                        # Kinesis permissions (for future stream integration)
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetShardIterator",
                                "kinesis:GetRecords",
                                "kinesis:ListShards"
                            ],
                            resources=["arn:aws:kinesis:*:*:stream/*"]
                        )
                    ]
                )
            }
        )

    def _create_firehose_delivery_stream(self) -> None:
        """Create Kinesis Data Firehose delivery stream."""
        
        # Create CloudWatch log group for Firehose
        log_group = logs.LogGroup(
            self, "FirehoseLogGroup",
            log_group_name=f"/aws/kinesisfirehose/log-processing-stream-{self.account}-{self.region}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create Firehose delivery stream
        self.delivery_stream = firehose.CfnDeliveryStream(
            self, "LogProcessingStream",
            delivery_stream_name=f"log-processing-stream-{self.account}-{self.region}",
            delivery_stream_type="DirectPut",
            extended_s3_destination_configuration=firehose.CfnDeliveryStream.ExtendedS3DestinationConfigurationProperty(
                bucket_arn=self.processed_bucket.bucket_arn,
                role_arn=self.firehose_role.role_arn,
                prefix="logs/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
                error_output_prefix="errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/!{firehose:error-output-type}/",
                buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                    size_in_m_bs=5,
                    interval_in_seconds=60
                ),
                compression_format="GZIP",
                s3_backup_mode="Enabled",
                s3_backup_configuration=firehose.CfnDeliveryStream.S3DestinationConfigurationProperty(
                    bucket_arn=self.raw_bucket.bucket_arn,
                    role_arn=self.firehose_role.role_arn,
                    prefix="raw/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/",
                    buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                        size_in_m_bs=5,
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
                                    parameter_value=f"{self.transform_lambda.function_arn}:$LATEST"
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
                ),
                cloud_watch_logging_options=firehose.CfnDeliveryStream.CloudWatchLoggingOptionsProperty(
                    enabled=True,
                    log_group_name=log_group.log_group_name,
                    log_stream_name="S3Delivery"
                )
            )
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and SNS alerting resources."""
        
        # Create SNS topic for alerts
        self.alert_topic = sns.Topic(
            self, "FirehoseAlertTopic",
            topic_name=f"firehose-alerts-{self.account}-{self.region}",
            display_name="Firehose Pipeline Alerts"
        )
        
        # Create CloudWatch alarm for delivery failures
        self.delivery_alarm = cloudwatch.Alarm(
            self, "DeliveryFailureAlarm",
            alarm_name=f"FirehoseDeliveryFailure-{self.delivery_stream.delivery_stream_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/Kinesis/Firehose",
                metric_name="DeliveryToS3.DataFreshness",
                dimensions_map={
                    "DeliveryStreamName": self.delivery_stream.delivery_stream_name or ""
                },
                statistic="Maximum",
                period=Duration.minutes(5)
            ),
            threshold=900,  # 15 minutes
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Alarm when Firehose records are not delivered to S3 within 15 minutes"
        )
        
        # Add SNS action to alarm
        self.delivery_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )
        self.delivery_alarm.add_ok_action(
            cloudwatch.SnsAction(self.alert_topic)
        )
        
        # Create CloudWatch alarm for transformation errors
        self.transformation_error_alarm = cloudwatch.Alarm(
            self, "TransformationErrorAlarm",
            alarm_name=f"FirehoseTransformationErrors-{self.delivery_stream.delivery_stream_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/Kinesis/Firehose",
                metric_name="ExecuteProcessing.Duration",
                dimensions_map={
                    "DeliveryStreamName": self.delivery_stream.delivery_stream_name or ""
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=30000,  # 30 seconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Alarm when Lambda transformation takes longer than 30 seconds"
        )
        
        # Add SNS action to transformation error alarm
        self.transformation_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self, "DeliveryStreamName",
            value=self.delivery_stream.delivery_stream_name or "",
            description="Name of the Kinesis Data Firehose delivery stream",
            export_name=f"{self.stack_name}-DeliveryStreamName"
        )
        
        CfnOutput(
            self, "DeliveryStreamArn",
            value=self.delivery_stream.attr_arn,
            description="ARN of the Kinesis Data Firehose delivery stream",
            export_name=f"{self.stack_name}-DeliveryStreamArn"
        )
        
        CfnOutput(
            self, "ProcessedDataBucket",
            value=self.processed_bucket.bucket_name,
            description="S3 bucket containing processed data",
            export_name=f"{self.stack_name}-ProcessedDataBucket"
        )
        
        CfnOutput(
            self, "RawDataBucket",
            value=self.raw_bucket.bucket_name,
            description="S3 bucket containing raw backup data",
            export_name=f"{self.stack_name}-RawDataBucket"
        )
        
        CfnOutput(
            self, "ErrorDataBucket",
            value=self.error_bucket.bucket_name,
            description="S3 bucket containing error/failed records",
            export_name=f"{self.stack_name}-ErrorDataBucket"
        )
        
        CfnOutput(
            self, "TransformLambdaArn",
            value=self.transform_lambda.function_arn,
            description="ARN of the Lambda transformation function",
            export_name=f"{self.stack_name}-TransformLambdaArn"
        )
        
        CfnOutput(
            self, "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS topic for alerts",
            export_name=f"{self.stack_name}-AlertTopicArn"
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        
        Tags.of(self).add("Recipe", "real-time-data-transformation-with-kinesis-firehose")
        Tags.of(self).add("Environment", "production")
        Tags.of(self).add("Application", "LogProcessingPipeline")
        Tags.of(self).add("Owner", "DataEngineering")
        Tags.of(self).add("CostCenter", "DataAnalytics")


def main():
    """Main function to create and deploy the CDK application."""
    
    # Create CDK app
    app = cdk.App()
    
    # Get configuration from context or environment
    env = cdk.Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or None
    )
    
    # Create the stack
    stack = RealTimeDataTransformationStack(
        app, 
        "RealTimeDataTransformationStack",
        env=env,
        description="Real-Time Data Transformation with Kinesis Data Firehose - CDK Python Stack"
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()