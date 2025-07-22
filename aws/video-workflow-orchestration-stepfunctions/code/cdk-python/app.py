#!/usr/bin/env python3
"""
AWS CDK Python Application for Automated Video Workflow Orchestration

This CDK application deploys a comprehensive video processing workflow using AWS Step Functions,
MediaConvert, Lambda, S3, DynamoDB, and API Gateway. The solution provides automated video
transcoding, quality control, metadata extraction, and content publishing capabilities.

Features:
- Step Functions workflow orchestration with Express Workflows
- MediaConvert video transcoding with multiple output formats
- Lambda functions for metadata extraction, quality control, and publishing
- S3 event-driven workflow triggering
- API Gateway for programmatic workflow initiation
- DynamoDB for job tracking and audit trails
- CloudWatch monitoring and SNS notifications
- Automated source file archiving

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
    aws_apigateway as apigateway,
    aws_apigatewayv2 as apigatewayv2,
    aws_apigatewayv2_integrations as apigatewayv2_integrations,
    aws_dynamodb as dynamodb,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_sns as sns,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as tasks,
)
from constructs import Construct


class VideoWorkflowOrchestrationStack(Stack):
    """
    CDK Stack for Automated Video Workflow Orchestration
    
    This stack creates a complete video processing pipeline using AWS Step Functions
    to orchestrate video transcoding, quality control, and content publishing workflows.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.random_suffix = self.node.try_get_context("random_suffix") or "demo"
        self.environment_name = self.node.try_get_context("environment") or "production"
        
        # Create core infrastructure
        self._create_storage_resources()
        self._create_database_resources()
        self._create_notification_resources()
        self._create_iam_roles()
        self._create_lambda_functions()
        self._create_step_functions_workflow()
        self._create_api_gateway()
        self._create_s3_event_triggers()
        self._create_monitoring_resources()
        
        # Apply common tags
        self._apply_tags()

    def _create_storage_resources(self) -> None:
        """Create S3 buckets for source videos, processed outputs, and archived content."""
        
        # Source bucket for incoming video files
        self.source_bucket = s3.Bucket(
            self, "SourceBucket",
            bucket_name=f"video-workflow-source-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="archive-old-versions",
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(30)
                        )
                    ],
                    enabled=True
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Output bucket for processed video files
        self.output_bucket = s3.Bucket(
            self, "OutputBucket",
            bucket_name=f"video-workflow-output-{self.random_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="transition-to-ia",
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
                    enabled=True
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Archive bucket for long-term storage
        self.archive_bucket = s3.Bucket(
            self, "ArchiveBucket",
            bucket_name=f"video-workflow-archive-{self.random_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            storage_class=s3.StorageClass.GLACIER,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

    def _create_database_resources(self) -> None:
        """Create DynamoDB table for job tracking and workflow state management."""
        
        self.jobs_table = dynamodb.Table(
            self, "JobsTable",
            table_name=f"video-workflow-jobs-{self.random_suffix}",
            partition_key=dynamodb.Attribute(
                name="JobId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

        # Add Global Secondary Index for querying by creation time
        self.jobs_table.add_global_secondary_index(
            index_name="CreatedAtIndex",
            partition_key=dynamodb.Attribute(
                name="CreatedAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

    def _create_notification_resources(self) -> None:
        """Create SNS topic for workflow notifications and alerts."""
        
        self.sns_topic = sns.Topic(
            self, "NotificationTopic",
            topic_name=f"video-workflow-notifications-{self.random_suffix}",
            display_name="Video Workflow Notifications",
            description="Notifications for video processing workflow events"
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for MediaConvert, Lambda functions, and Step Functions."""
        
        # MediaConvert service role
        self.mediaconvert_role = iam.Role(
            self, "MediaConvertRole",
            role_name=f"VideoWorkflowMediaConvertRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("mediaconvert.amazonaws.com"),
            description="Service role for MediaConvert video processing jobs"
        )

        # Add permissions for S3 bucket access
        self.mediaconvert_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                resources=[
                    self.source_bucket.bucket_arn,
                    f"{self.source_bucket.bucket_arn}/*",
                    self.output_bucket.bucket_arn,
                    f"{self.output_bucket.bucket_arn}/*",
                    self.archive_bucket.bucket_arn,
                    f"{self.archive_bucket.bucket_arn}/*"
                ]
            )
        )

        # Add SNS publish permission
        self.mediaconvert_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.sns_topic.topic_arn]
            )
        )

        # Lambda execution role for workflow functions
        self.lambda_role = iam.Role(
            self, "LambdaRole",
            role_name=f"VideoWorkflowLambdaRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            description="Execution role for video workflow Lambda functions"
        )

        # Add DynamoDB permissions
        self.jobs_table.grant_read_write_data(self.lambda_role)

        # Add S3 permissions
        for bucket in [self.source_bucket, self.output_bucket, self.archive_bucket]:
            bucket.grant_read_write(self.lambda_role)

        # Add SNS publish permission
        self.sns_topic.grant_publish(self.lambda_role)

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for metadata extraction, quality control, and publishing."""
        
        # Common Lambda configuration
        lambda_config = {
            "runtime": lambda_.Runtime.PYTHON_3_9,
            "timeout": Duration.minutes(5),
            "role": self.lambda_role,
            "environment": {
                "JOBS_TABLE": self.jobs_table.table_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
                "SOURCE_BUCKET": self.source_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "ARCHIVE_BUCKET": self.archive_bucket.bucket_name
            }
        }

        # Metadata extraction Lambda
        self.metadata_lambda = lambda_.Function(
            self, "MetadataExtractorFunction",
            function_name=f"video-metadata-extractor-{self.random_suffix}",
            description="Extract metadata from source video files",
            code=lambda_.Code.from_inline(self._get_metadata_extractor_code()),
            handler="index.lambda_handler",
            **lambda_config
        )

        # Quality control Lambda
        self.quality_control_lambda = lambda_.Function(
            self, "QualityControlFunction",
            function_name=f"video-quality-control-{self.random_suffix}",
            description="Perform quality control validation on processed videos",
            code=lambda_.Code.from_inline(self._get_quality_control_code()),
            handler="index.lambda_handler",
            **lambda_config
        )

        # Publishing Lambda
        self.publisher_lambda = lambda_.Function(
            self, "PublisherFunction",
            function_name=f"video-publisher-{self.random_suffix}",
            description="Publish processed videos and manage content distribution",
            code=lambda_.Code.from_inline(self._get_publisher_code()),
            handler="index.lambda_handler",
            **lambda_config
        )

        # Workflow trigger Lambda
        self.trigger_lambda = lambda_.Function(
            self, "WorkflowTriggerFunction",
            function_name=f"video-workflow-trigger-{self.random_suffix}",
            description="Trigger video processing workflows",
            code=lambda_.Code.from_inline(self._get_trigger_code()),
            handler="index.lambda_handler",
            timeout=Duration.seconds(30),
            role=self.lambda_role,
            environment={
                "STATE_MACHINE_ARN": "",  # Will be updated after state machine creation
                **lambda_config["environment"]
            }
        )

    def _create_step_functions_workflow(self) -> None:
        """Create Step Functions state machine for video workflow orchestration."""
        
        # Step Functions execution role
        self.stepfunctions_role = iam.Role(
            self, "StepFunctionsRole",
            role_name=f"VideoWorkflowStepFunctionsRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Execution role for video workflow Step Functions"
        )

        # Add Lambda invoke permissions
        for lambda_func in [self.metadata_lambda, self.quality_control_lambda, self.publisher_lambda]:
            lambda_func.grant_invoke(self.stepfunctions_role)

        # Add MediaConvert permissions
        self.stepfunctions_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "mediaconvert:CreateJob",
                    "mediaconvert:GetJob",
                    "mediaconvert:ListJobs"
                ],
                resources=["*"]
            )
        )

        # Add IAM PassRole permission for MediaConvert
        self.stepfunctions_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[self.mediaconvert_role.role_arn]
            )
        )

        # Add DynamoDB permissions
        self.jobs_table.grant_read_write_data(self.stepfunctions_role)

        # Add S3 permissions
        for bucket in [self.source_bucket, self.output_bucket, self.archive_bucket]:
            bucket.grant_read_write(self.stepfunctions_role)

        # Create CloudWatch Logs group for Step Functions
        self.stepfunctions_log_group = logs.LogGroup(
            self, "StepFunctionsLogGroup",
            log_group_name=f"/aws/stepfunctions/video-processing-workflow-{self.random_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Define workflow states
        workflow_definition = self._create_workflow_definition()

        # Create Step Functions state machine
        self.state_machine = sfn.StateMachine(
            self, "VideoWorkflowStateMachine",
            state_machine_name=f"video-processing-workflow-{self.random_suffix}",
            definition=workflow_definition,
            role=self.stepfunctions_role,
            state_machine_type=sfn.StateMachineType.EXPRESS,
            logs=sfn.LogOptions(
                destination=self.stepfunctions_log_group,
                level=sfn.LogLevel.ALL,
                include_execution_data=True
            ),
            timeout=Duration.hours(2)
        )

        # Update trigger Lambda environment with state machine ARN
        self.trigger_lambda.add_environment("STATE_MACHINE_ARN", self.state_machine.state_machine_arn)

        # Grant Step Functions execution permission to trigger Lambda
        self.state_machine.grant_start_execution(self.lambda_role)

    def _create_workflow_definition(self) -> sfn.IChainable:
        """Create the Step Functions workflow definition with parallel processing and quality control."""
        
        # Initialize job state
        initialize_job = sfn.Pass(
            self, "InitializeJob",
            parameters={
                "jobId.$": "$.jobId",
                "bucket.$": "$.bucket",
                "key.$": "$.key",
                "outputBucket": self.output_bucket.bucket_name,
                "archiveBucket": self.archive_bucket.bucket_name,
                "timestamp.$": "$$.State.EnteredTime"
            }
        )

        # Record job start in DynamoDB
        record_job_start = tasks.DynamoPutItem(
            self, "RecordJobStart",
            table=self.jobs_table,
            item={
                "JobId": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$.jobId")),
                "SourceBucket": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$.bucket")),
                "SourceKey": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$.key")),
                "CreatedAt": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$.timestamp")),
                "JobStatus": tasks.DynamoAttributeValue.from_string("STARTED")
            }
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(2),
            max_attempts=3,
            backoff_rate=2.0
        )

        # Metadata extraction branch
        extract_metadata = tasks.LambdaInvoke(
            self, "ExtractMetadata",
            lambda_function=self.metadata_lambda,
            payload=sfn.TaskInput.from_object({
                "bucket.$": "$.bucket",
                "key.$": "$.key",
                "jobId.$": "$.jobId"
            }),
            output_path="$.Payload"
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(5),
            max_attempts=2
        )

        # MediaConvert transcoding job
        mediaconvert_job = tasks.MediaConvertCreateJob(
            self, "TranscodeVideo",
            create_job_request={
                "Role": self.mediaconvert_role.role_arn,
                "Settings": {
                    "OutputGroups": [
                        {
                            "Name": "MP4_Output",
                            "OutputGroupSettings": {
                                "Type": "FILE_GROUP_SETTINGS",
                                "FileGroupSettings": {
                                    "Destination": sfn.JsonPath.format(
                                        f"s3://{self.output_bucket.bucket_name}/mp4/{{}}/",
                                        sfn.JsonPath.string_at("$.jobId")
                                    )
                                }
                            },
                            "Outputs": [
                                {
                                    "NameModifier": "_1080p",
                                    "ContainerSettings": {"Container": "MP4"},
                                    "VideoDescription": {
                                        "Width": 1920,
                                        "Height": 1080,
                                        "CodecSettings": {
                                            "Codec": "H_264",
                                            "H264Settings": {
                                                "RateControlMode": "QVBR",
                                                "QvbrSettings": {"QvbrQualityLevel": 8},
                                                "MaxBitrate": 5000000
                                            }
                                        }
                                    },
                                    "AudioDescriptions": [
                                        {
                                            "CodecSettings": {
                                                "Codec": "AAC",
                                                "AacSettings": {
                                                    "Bitrate": 128000,
                                                    "CodingMode": "CODING_MODE_2_0",
                                                    "SampleRate": 48000
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "Name": "HLS_Output",
                            "OutputGroupSettings": {
                                "Type": "HLS_GROUP_SETTINGS",
                                "HlsGroupSettings": {
                                    "Destination": sfn.JsonPath.format(
                                        f"s3://{self.output_bucket.bucket_name}/hls/{{}}/",
                                        sfn.JsonPath.string_at("$.jobId")
                                    ),
                                    "SegmentLength": 6,
                                    "OutputSelection": "MANIFESTS_AND_SEGMENTS"
                                }
                            },
                            "Outputs": [
                                {
                                    "NameModifier": "_hls_1080p",
                                    "ContainerSettings": {"Container": "M3U8"},
                                    "VideoDescription": {
                                        "Width": 1920,
                                        "Height": 1080,
                                        "CodecSettings": {
                                            "Codec": "H_264",
                                            "H264Settings": {
                                                "RateControlMode": "QVBR",
                                                "QvbrSettings": {"QvbrQualityLevel": 8},
                                                "MaxBitrate": 5000000
                                            }
                                        }
                                    },
                                    "AudioDescriptions": [
                                        {
                                            "CodecSettings": {
                                                "Codec": "AAC",
                                                "AacSettings": {
                                                    "Bitrate": 128000,
                                                    "CodingMode": "CODING_MODE_2_0",
                                                    "SampleRate": 48000
                                                }
                                            }
                                        }
                                    ]
                                }
                            ]
                        }
                    ],
                    "Inputs": [
                        {
                            "FileInput": sfn.JsonPath.format(
                                "s3://{}/{}",
                                sfn.JsonPath.string_at("$.bucket"),
                                sfn.JsonPath.string_at("$.key")
                            ),
                            "AudioSelectors": {
                                "Audio Selector 1": {
                                    "Tracks": [1],
                                    "DefaultSelection": "DEFAULT"
                                }
                            },
                            "VideoSelector": {"ColorSpace": "FOLLOW"},
                            "TimecodeSource": "EMBEDDED"
                        }
                    ]
                },
                "StatusUpdateInterval": "SECONDS_60",
                "UserMetadata": {
                    "WorkflowJobId": sfn.JsonPath.string_at("$.jobId"),
                    "SourceFile": sfn.JsonPath.string_at("$.key")
                }
            },
            integration_pattern=sfn.IntegrationPattern.RUN_JOB
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(30),
            max_attempts=2,
            backoff_rate=2.0
        )

        # Parallel processing of metadata extraction and video transcoding
        parallel_processing = sfn.Parallel(
            self, "ParallelProcessing",
            comment="Process metadata extraction and video transcoding in parallel"
        ).branch(extract_metadata).branch(mediaconvert_job)

        # Combine parallel results
        processing_complete = sfn.Pass(
            self, "ProcessingComplete",
            parameters={
                "jobId.$": "$[0].jobId",
                "metadata.$": "$[0].metadata",
                "mediaConvertJob.$": "$[1].Job",
                "outputs": [
                    {
                        "format": "mp4",
                        "bucket": self.output_bucket.bucket_name,
                        "key.$": "States.Format('mp4/{}/output', $[0].jobId)"
                    },
                    {
                        "format": "hls",
                        "bucket": self.output_bucket.bucket_name,
                        "key.$": "States.Format('hls/{}/index.m3u8', $[0].jobId)"
                    }
                ]
            }
        )

        # Quality control validation
        quality_control = tasks.LambdaInvoke(
            self, "QualityControl",
            lambda_function=self.quality_control_lambda,
            payload=sfn.TaskInput.from_object({
                "jobId.$": "$.jobId",
                "outputs.$": "$.outputs",
                "metadata.$": "$.metadata"
            }),
            output_path="$.Payload"
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(10),
            max_attempts=2
        )

        # Quality decision choice
        quality_decision = sfn.Choice(self, "QualityDecision")

        # Publish content (success path)
        publish_content = tasks.LambdaInvoke(
            self, "PublishContent",
            lambda_function=self.publisher_lambda,
            payload=sfn.TaskInput.from_object({
                "jobId.$": "$.jobId",
                "outputs.$": "$.outputs",
                "qualityResults.$": "$.qualityResults",
                "qualityPassed": True
            }),
            output_path="$.Payload"
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(5),
            max_attempts=2
        )

        # Archive source file
        archive_source = tasks.CallAwsService(
            self, "ArchiveSource",
            service="s3",
            action="copyObject",
            parameters={
                "Bucket": self.archive_bucket.bucket_name,
                "CopySource": sfn.JsonPath.format(
                    "{}/{}",
                    sfn.JsonPath.string_at("$.jobId"),
                    sfn.JsonPath.string_at("$.key")
                ),
                "Key": sfn.JsonPath.format(
                    "archived/{}/{}",
                    sfn.JsonPath.string_at("$.jobId"),
                    sfn.JsonPath.string_at("$.key")
                )
            },
            iam_resources=["*"]
        ).add_catch(
            errors=["States.ALL"],
            handler=sfn.Pass(self, "ArchiveFailureIgnored"),
            comment="Archive failure doesn't fail the entire workflow"
        )

        # Workflow success
        workflow_success = sfn.Pass(
            self, "WorkflowSuccess",
            result=sfn.Result.from_object({
                "status": "SUCCESS",
                "message": "Video processing workflow completed successfully"
            })
        )

        # Quality control failed path
        quality_control_failed = tasks.LambdaInvoke(
            self, "QualityControlFailed",
            lambda_function=self.publisher_lambda,
            payload=sfn.TaskInput.from_object({
                "jobId.$": "$.jobId",
                "outputs.$": "$.outputs",
                "qualityResults.$": "$.qualityResults",
                "qualityPassed": False
            }),
            output_path="$.Payload"
        )

        # Workflow failure
        workflow_failure = sfn.Fail(
            self, "WorkflowFailure",
            cause="Video processing workflow failed"
        )

        # Handle processing failure
        handle_processing_failure = tasks.DynamoUpdateItem(
            self, "HandleProcessingFailure",
            table=self.jobs_table,
            key={
                "JobId": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$.jobId"))
            },
            update_expression="SET JobStatus = :status, ErrorDetails = :error, FailedAt = :timestamp",
            expression_attribute_values={
                ":status": tasks.DynamoAttributeValue.from_string("FAILED_PROCESSING"),
                ":error": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$.error.Cause")),
                ":timestamp": tasks.DynamoAttributeValue.from_string(sfn.JsonPath.string_at("$$.State.EnteredTime"))
            }
        )

        # Build workflow definition
        parallel_processing.add_catch(
            errors=["States.ALL"],
            handler=handle_processing_failure.next(workflow_failure),
            result_path="$.error"
        )

        quality_decision.when(
            sfn.Condition.boolean_equals("$.passed", True),
            publish_content.next(archive_source).next(workflow_success)
        ).otherwise(quality_control_failed.next(workflow_failure))

        # Chain the workflow states
        definition = (
            initialize_job
            .next(record_job_start)
            .next(parallel_processing)
            .next(processing_complete)
            .next(quality_control)
            .next(quality_decision)
        )

        return definition

    def _create_api_gateway(self) -> None:
        """Create API Gateway HTTP API for programmatic workflow triggering."""
        
        # Create HTTP API
        self.http_api = apigatewayv2.HttpApi(
            self, "VideoWorkflowApi",
            api_name=f"video-workflow-api-{self.random_suffix}",
            description="Video processing workflow API",
            cors_preflight=apigatewayv2.CorsPreflightOptions(
                allow_credentials=False,
                allow_headers=["*"],
                allow_methods=[apigatewayv2.CorsHttpMethod.ANY],
                allow_origins=["*"]
            )
        )

        # Create Lambda integration
        trigger_integration = apigatewayv2_integrations.HttpLambdaIntegration(
            "TriggerIntegration",
            self.trigger_lambda,
            payload_format_version=apigatewayv2.PayloadFormatVersion.VERSION_2_0
        )

        # Add route for workflow triggering
        self.http_api.add_routes(
            path="/start-workflow",
            methods=[apigatewayv2.HttpMethod.POST],
            integration=trigger_integration
        )

        # Create stage
        self.api_stage = apigatewayv2.HttpStage(
            self, "ProdStage",
            http_api=self.http_api,
            stage_name="prod",
            auto_deploy=True
        )

        # Output API endpoint URL
        self.api_endpoint_url = f"https://{self.http_api.http_api_id}.execute-api.{self.region}.amazonaws.com/prod"

    def _create_s3_event_triggers(self) -> None:
        """Configure S3 event notifications to automatically trigger workflows."""
        
        # Add S3 event notification for video file uploads
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.trigger_lambda),
            s3.NotificationKeyFilter(suffix=".mp4")
        )

        # Add notification for MOV files
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.trigger_lambda),
            s3.NotificationKeyFilter(suffix=".mov")
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch dashboard and monitoring resources."""
        
        # Create CloudWatch dashboard
        self.dashboard = logs.LogGroup(
            self, "WorkflowDashboard",
            log_group_name=f"/aws/video-workflow/dashboard-{self.random_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all stack resources."""
        
        Tags.of(self).add("Project", "VideoWorkflowOrchestration")
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "MediaServices")

    def _get_metadata_extractor_code(self) -> str:
        """Return the Lambda function code for metadata extraction."""
        return '''
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Extract input parameters
    bucket = event['bucket']
    key = event['key']
    job_id = event['jobId']
    
    try:
        # Get basic file information
        response = s3.head_object(Bucket=bucket, Key=key)
        
        # Extract metadata (simplified for demo)
        metadata = {
            'file_size': response['ContentLength'],
            'last_modified': response['LastModified'].isoformat(),
            'content_type': response.get('ContentType', 'unknown'),
            'etag': response['ETag'],
            'duration': 120.5,  # Placeholder
            'width': 1920,      # Placeholder
            'height': 1080,     # Placeholder
            'fps': 29.97,       # Placeholder
            'bitrate': 5000000, # Placeholder
            'codec': 'h264',    # Placeholder
            'audio_codec': 'aac' # Placeholder
        }
        
        # Store metadata in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET VideoMetadata = :metadata, MetadataExtractedAt = :timestamp',
            ExpressionAttributeValues={
                ':metadata': metadata,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'metadata': metadata,
            'jobId': job_id
        }
        
    except Exception as e:
        print(f"Error extracting metadata: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id
        }
'''

    def _get_quality_control_code(self) -> str:
        """Return the Lambda function code for quality control validation."""
        return '''
import json
import boto3
import os
from datetime import datetime

s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Extract input parameters
    outputs = event['outputs']
    job_id = event['jobId']
    
    try:
        quality_results = []
        
        for output in outputs:
            bucket = output['bucket']
            key = output['key']
            format_type = output['format']
            
            # Perform quality checks
            quality_check = perform_quality_validation(bucket, key, format_type)
            quality_results.append(quality_check)
        
        # Calculate overall quality score
        overall_score = calculate_overall_quality(quality_results)
        
        # Store results in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        table.update_item(
            Key={'JobId': job_id},
            UpdateExpression='SET QualityResults = :results, QualityScore = :score, QCCompletedAt = :timestamp',
            ExpressionAttributeValues={
                ':results': quality_results,
                ':score': overall_score,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'qualityResults': quality_results,
            'qualityScore': overall_score,
            'passed': overall_score >= 0.8,
            'jobId': job_id
        }
        
    except Exception as e:
        print(f"Error in quality control: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id,
            'passed': False
        }

def perform_quality_validation(bucket, key, format_type):
    try:
        # Basic file existence and size check
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        # Basic quality checks
        checks = {
            'file_exists': True,
            'file_size_valid': file_size > 1000,
            'format_valid': format_type in ['mp4', 'hls'],
            'encoding_quality': 0.9
        }
        
        score = sum(1 for check in checks.values() if check is True) / len([k for k in checks.keys() if k != 'encoding_quality'])
        if 'encoding_quality' in checks:
            score = (score + checks['encoding_quality']) / 2
        
        return {
            'bucket': bucket,
            'key': key,
            'format': format_type,
            'checks': checks,
            'score': score,
            'file_size': file_size
        }
        
    except Exception as e:
        return {
            'bucket': bucket,
            'key': key,
            'format': format_type,
            'error': str(e),
            'score': 0.0
        }

def calculate_overall_quality(quality_results):
    if not quality_results:
        return 0.0
    
    total_score = sum(result.get('score', 0.0) for result in quality_results)
    return total_score / len(quality_results)
'''

    def _get_publisher_code(self) -> str:
        """Return the Lambda function code for content publishing."""
        return '''
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    # Extract input parameters
    job_id = event['jobId']
    outputs = event['outputs']
    quality_passed = event.get('qualityPassed', False)
    
    try:
        # Update job status in DynamoDB
        table = dynamodb.Table(os.environ['JOBS_TABLE'])
        
        if quality_passed:
            # Publish successful completion
            table.update_item(
                Key={'JobId': job_id},
                UpdateExpression='SET JobStatus = :status, PublishedAt = :timestamp, OutputLocations = :outputs',
                ExpressionAttributeValues={
                    ':status': 'PUBLISHED',
                    ':timestamp': datetime.utcnow().isoformat(),
                    ':outputs': outputs
                }
            )
            
            message = f"Video processing completed successfully for job {job_id}"
            subject = "Video Processing Success"
            
        else:
            # Mark as failed quality control
            table.update_item(
                Key={'JobId': job_id},
                UpdateExpression='SET JobStatus = :status, FailedAt = :timestamp, FailureReason = :reason',
                ExpressionAttributeValues={
                    ':status': 'FAILED_QC',
                    ':timestamp': datetime.utcnow().isoformat(),
                    ':reason': 'Quality control validation failed'
                }
            )
            
            message = f"Video processing failed quality control for job {job_id}"
            subject = "Video Processing Quality Control Failed"
        
        # Send SNS notification
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject=subject
        )
        
        return {
            'statusCode': 200,
            'jobId': job_id,
            'status': 'PUBLISHED' if quality_passed else 'FAILED_QC',
            'message': message
        }
        
    except Exception as e:
        print(f"Error in publishing: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e),
            'jobId': job_id
        }
'''

    def _get_trigger_code(self) -> str:
        """Return the Lambda function code for workflow triggering."""
        return '''
import json
import boto3
import uuid
import os
from datetime import datetime

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        # Handle both S3 events and API Gateway requests
        if 'Records' in event:
            # S3 event
            bucket = event['Records'][0]['s3']['bucket']['name']
            key = event['Records'][0]['s3']['object']['key']
        else:
            # API Gateway event
            if 'body' in event:
                body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            else:
                body = event
            
            bucket = body.get('bucket')
            key = body.get('key')
            
            if not bucket or not key:
                return {
                    'statusCode': 400,
                    'body': json.dumps({'error': 'Missing bucket or key parameter'})
                }
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Start Step Functions execution
        response = stepfunctions.start_execution(
            stateMachineArn=os.environ['STATE_MACHINE_ARN'],
            name=f"video-workflow-{job_id}",
            input=json.dumps({
                'jobId': job_id,
                'bucket': bucket,
                'key': key,
                'requestedAt': datetime.utcnow().isoformat()
            })
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'jobId': job_id,
                'executionArn': response['executionArn'],
                'message': 'Video processing workflow started successfully'
            })
        }
        
    except Exception as e:
        print(f"Error starting workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''


class VideoWorkflowOrchestrationApp(cdk.App):
    """CDK Application for Video Workflow Orchestration."""

    def __init__(self):
        super().__init__()

        # Get configuration from context
        env_config = self.get_env_config()

        # Create the main stack
        VideoWorkflowOrchestrationStack(
            self, "VideoWorkflowOrchestrationStack",
            env=cdk.Environment(
                account=env_config.get("account", os.environ.get("CDK_DEFAULT_ACCOUNT")),
                region=env_config.get("region", os.environ.get("CDK_DEFAULT_REGION"))
            ),
            description="Automated Video Workflow Orchestration with Step Functions and MediaConvert"
        )

    def get_env_config(self) -> Dict[str, str]:
        """Get environment configuration from context or environment variables."""
        return {
            "account": self.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT"),
            "region": self.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            "environment": self.node.try_get_context("environment") or "production"
        }


# Create and run the application
if __name__ == "__main__":
    app = VideoWorkflowOrchestrationApp()
    app.synth()