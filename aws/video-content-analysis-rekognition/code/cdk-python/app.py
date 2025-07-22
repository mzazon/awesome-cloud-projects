#!/usr/bin/env python3
"""
AWS CDK Python application for Video Content Analysis with AWS Elemental MediaAnalyzer

This application deploys a complete video content analysis pipeline using:
- Amazon Rekognition for video analysis (content moderation, segment detection)
- AWS Step Functions for workflow orchestration
- AWS Lambda for processing functions
- Amazon S3 for storage
- Amazon DynamoDB for metadata storage
- Amazon SNS/SQS for notifications
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_sns as sns,
    aws_sqs as sqs,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_s3_notifications as s3_notifications,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct


class VideoContentAnalysisStack(Stack):
    """
    CDK Stack for Video Content Analysis with AWS Elemental MediaAnalyzer
    
    This stack creates a serverless video analysis pipeline that automatically
    processes video content uploaded to S3 using Amazon Rekognition's video
    analysis capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        
        # Create S3 buckets for video processing
        self.source_bucket = self._create_source_bucket(unique_suffix)
        self.results_bucket = self._create_results_bucket(unique_suffix)
        self.temp_bucket = self._create_temp_bucket(unique_suffix)
        
        # Create DynamoDB table for analysis results
        self.analysis_table = self._create_analysis_table(unique_suffix)
        
        # Create SNS/SQS for notifications
        self.notification_topic, self.notification_queue = self._create_notification_resources(unique_suffix)
        
        # Create IAM roles
        self.lambda_role = self._create_lambda_role()
        self.stepfunctions_role = self._create_stepfunctions_role()
        
        # Create Lambda functions
        self.lambda_functions = self._create_lambda_functions()
        
        # Create Step Functions state machine
        self.state_machine = self._create_state_machine()
        
        # Create S3 event trigger
        self._create_s3_trigger()
        
        # Create monitoring resources
        self._create_monitoring_resources()
        
        # Create stack outputs
        self._create_outputs()

    def _create_source_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for source video files"""
        bucket = s3.Bucket(
            self,
            "VideoSourceBucket",
            bucket_name=f"video-source-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add bucket policy for secure transport
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, f"{bucket.bucket_arn}/*"],
                conditions={
                    "Bool": {
                        "aws:SecureTransport": "false"
                    }
                }
            )
        )
        
        return bucket

    def _create_results_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for analysis results"""
        return s3.Bucket(
            self,
            "VideoResultsBucket",
            bucket_name=f"video-results-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_temp_bucket(self, suffix: str) -> s3.Bucket:
        """Create S3 bucket for temporary processing files"""
        return s3.Bucket(
            self,
            "VideoTempBucket",
            bucket_name=f"video-temp-{suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteTempFilesAfter7Days",
                    expiration=Duration.days(7),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

    def _create_analysis_table(self, suffix: str) -> dynamodb.Table:
        """Create DynamoDB table for storing analysis results"""
        table = dynamodb.Table(
            self,
            "VideoAnalysisTable",
            table_name=f"video-analysis-results-{suffix}",
            partition_key=dynamodb.Attribute(
                name="VideoId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add Global Secondary Index for querying by job status
        table.add_global_secondary_index(
            index_name="JobStatusIndex",
            partition_key=dynamodb.Attribute(
                name="JobStatus",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )
        
        return table

    def _create_notification_resources(self, suffix: str) -> tuple[sns.Topic, sqs.Queue]:
        """Create SNS topic and SQS queue for notifications"""
        # Create SNS topic
        topic = sns.Topic(
            self,
            "VideoAnalysisNotificationTopic",
            topic_name=f"video-analysis-notifications-{suffix}",
            display_name="Video Analysis Notifications",
        )
        
        # Create SQS queue
        queue = sqs.Queue(
            self,
            "VideoAnalysisNotificationQueue",
            queue_name=f"video-analysis-queue-{suffix}",
            visibility_timeout=Duration.seconds(300),
            retention_period=Duration.days(14),
            encryption=sqs.QueueEncryption.SQS_MANAGED,
        )
        
        # Subscribe queue to topic
        topic.add_subscription(
            sns_subscriptions.SqsSubscription(queue)
        )
        
        return topic, queue

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda functions"""
        role = iam.Role(
            self,
            "VideoAnalysisLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )
        
        # Add custom policy for video analysis
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "rekognition:StartMediaAnalysisJob",
                    "rekognition:GetMediaAnalysisJob",
                    "rekognition:StartContentModeration",
                    "rekognition:GetContentModeration",
                    "rekognition:StartSegmentDetection",
                    "rekognition:GetSegmentDetection",
                    "rekognition:StartTextDetection",
                    "rekognition:GetTextDetection",
                ],
                resources=["*"],
            )
        )
        
        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                ],
                resources=[
                    f"{self.source_bucket.bucket_arn}/*",
                    f"{self.results_bucket.bucket_arn}/*",
                    f"{self.temp_bucket.bucket_arn}/*",
                ],
            )
        )
        
        # Add DynamoDB permissions
        self.analysis_table.grant_read_write_data(role)
        
        # Add SNS permissions
        self.notification_topic.grant_publish(role)
        
        return role

    def _create_stepfunctions_role(self) -> iam.Role:
        """Create IAM role for Step Functions"""
        role = iam.Role(
            self,
            "VideoAnalysisStepFunctionsRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
        )
        
        # Add Lambda invoke permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=[f"arn:aws:lambda:{self.region}:{self.account}:function:VideoAnalysis*"],
            )
        )
        
        # Add Rekognition permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "rekognition:StartMediaAnalysisJob",
                    "rekognition:GetMediaAnalysisJob",
                    "rekognition:StartContentModeration",
                    "rekognition:GetContentModeration",
                    "rekognition:StartSegmentDetection",
                    "rekognition:GetSegmentDetection",
                ],
                resources=["*"],
            )
        )
        
        # Add SNS permissions
        self.notification_topic.grant_publish(role)
        
        return role

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """Create all Lambda functions for the video analysis pipeline"""
        functions = {}
        
        # Common environment variables
        common_env = {
            "ANALYSIS_TABLE": self.analysis_table.table_name,
            "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
            "RESULTS_BUCKET": self.results_bucket.bucket_name,
        }
        
        # Initialize function
        functions["init"] = lambda_.Function(
            self,
            "VideoAnalysisInitFunction",
            function_name="VideoAnalysisInitFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_init_function_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment=common_env,
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )
        
        # Content moderation function
        functions["moderation"] = lambda_.Function(
            self,
            "VideoAnalysisModerationFunction",
            function_name="VideoAnalysisModerationFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_moderation_function_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                **common_env,
                "REKOGNITION_ROLE_ARN": self.lambda_role.role_arn,
            },
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )
        
        # Segment detection function
        functions["segment"] = lambda_.Function(
            self,
            "VideoAnalysisSegmentFunction",
            function_name="VideoAnalysisSegmentFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_segment_function_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                **common_env,
                "REKOGNITION_ROLE_ARN": self.lambda_role.role_arn,
            },
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )
        
        # Aggregation function
        functions["aggregation"] = lambda_.Function(
            self,
            "VideoAnalysisAggregationFunction",
            function_name="VideoAnalysisAggregationFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_aggregation_function_code()),
            timeout=Duration.seconds(300),
            memory_size=512,
            role=self.lambda_role,
            environment=common_env,
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )
        
        # Trigger function
        functions["trigger"] = lambda_.Function(
            self,
            "VideoAnalysisTriggerFunction",
            function_name="VideoAnalysisTriggerFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_trigger_function_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment=common_env,
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )
        
        return functions

    def _create_state_machine(self) -> sfn.StateMachine:
        """Create Step Functions state machine for workflow orchestration"""
        # Define state machine tasks
        init_task = sfn_tasks.LambdaInvoke(
            self,
            "InitializeAnalysis",
            lambda_function=self.lambda_functions["init"],
            retry_on_service_exceptions=True,
        )
        
        moderation_task = sfn_tasks.LambdaInvoke(
            self,
            "ContentModeration",
            lambda_function=self.lambda_functions["moderation"],
            input_path="$.Payload.body",
        )
        
        segment_task = sfn_tasks.LambdaInvoke(
            self,
            "SegmentDetection",
            lambda_function=self.lambda_functions["segment"],
            input_path="$.Payload.body",
        )
        
        # Parallel processing of moderation and segment detection
        parallel_analysis = sfn.Parallel(
            self,
            "ParallelAnalysis",
        ).branch(moderation_task).branch(segment_task)
        
        # Wait for processing to complete
        wait_task = sfn.Wait(
            self,
            "WaitForCompletion",
            time=sfn.WaitTime.duration(Duration.seconds(60)),
        )
        
        # Aggregate results
        aggregation_task = sfn_tasks.LambdaInvoke(
            self,
            "AggregateResults",
            lambda_function=self.lambda_functions["aggregation"],
            payload=sfn.TaskInput.from_object({
                "jobId": sfn.JsonPath.string_at("$[0].Payload.body.jobId"),
                "videoId": sfn.JsonPath.string_at("$[0].Payload.body.videoId"),
                "moderationJobId": sfn.JsonPath.string_at("$[0].Payload.body.moderationJobId"),
                "segmentJobId": sfn.JsonPath.string_at("$[1].Payload.body.segmentJobId"),
            }),
        )
        
        # Send notification
        notification_task = sfn_tasks.SnsPublish(
            self,
            "NotifyCompletion",
            topic=self.notification_topic,
            message=sfn.TaskInput.from_object({
                "jobId": sfn.JsonPath.string_at("$.Payload.body.jobId"),
                "videoId": sfn.JsonPath.string_at("$.Payload.body.videoId"),
                "status": sfn.JsonPath.string_at("$.Payload.body.status"),
                "resultsLocation": sfn.JsonPath.string_at("$.Payload.body.resultsLocation"),
            }),
        )
        
        # Define workflow
        definition = (
            init_task
            .next(parallel_analysis)
            .next(wait_task)
            .next(aggregation_task)
            .next(notification_task)
        )
        
        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "VideoAnalysisWorkflow",
            state_machine_name="VideoAnalysisWorkflow",
            definition=definition,
            role=self.stepfunctions_role,
            timeout=Duration.hours(2),
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "VideoAnalysisWorkflowLogs",
                    retention=logs.RetentionDays.TWO_WEEKS,
                ),
                level=sfn.LogLevel.ALL,
            ),
        )
        
        # Grant Step Functions permission to invoke Lambda functions
        for function in self.lambda_functions.values():
            function.grant_invoke(state_machine)
        
        return state_machine

    def _create_s3_trigger(self) -> None:
        """Create S3 event trigger for automatic processing"""
        # Update trigger function environment with state machine ARN
        self.lambda_functions["trigger"].add_environment(
            "STATE_MACHINE_ARN", self.state_machine.state_machine_arn
        )
        
        # Grant Step Functions execution permission to trigger function
        self.state_machine.grant_start_execution(self.lambda_functions["trigger"])
        
        # Configure S3 event notification
        self.source_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.lambda_functions["trigger"]),
            s3.NotificationKeyFilter(suffix=".mp4"),
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring resources"""
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "VideoAnalysisDashboard",
            dashboard_name="VideoAnalysisDashboard",
        )
        
        # Add Lambda function metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Duration",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Duration",
                        dimensions_map={"FunctionName": func.function_name},
                        statistic="Average",
                    )
                    for func in self.lambda_functions.values()
                ],
                period=Duration.minutes(5),
            )
        )
        
        # Add Step Functions metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Step Functions Executions",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/States",
                        metric_name="ExecutionsFailed",
                        dimensions_map={"StateMachineArn": self.state_machine.state_machine_arn},
                        statistic="Sum",
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/States",
                        metric_name="ExecutionsSucceeded",
                        dimensions_map={"StateMachineArn": self.state_machine.state_machine_arn},
                        statistic="Sum",
                    ),
                ],
                period=Duration.minutes(5),
            )
        )
        
        # Create alarm for failed executions
        cloudwatch.Alarm(
            self,
            "VideoAnalysisFailedExecutionsAlarm",
            alarm_name="VideoAnalysisFailedExecutions",
            alarm_description="Alert when Step Functions executions fail",
            metric=cloudwatch.Metric(
                namespace="AWS/States",
                metric_name="ExecutionsFailed",
                dimensions_map={"StateMachineArn": self.state_machine.state_machine_arn},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="S3 bucket name for source videos",
        )
        
        CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 bucket name for analysis results",
        )
        
        CfnOutput(
            self,
            "AnalysisTableName",
            value=self.analysis_table.table_name,
            description="DynamoDB table name for analysis results",
        )
        
        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN",
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
        )

    def _get_init_function_code(self) -> str:
        """Get the initialization function code"""
        return '''
import json
import boto3
import uuid
from datetime import datetime
import os

def lambda_handler(event, context):
    """Initialize video analysis job"""
    try:
        # Extract video information from S3 event
        s3_bucket = event['Records'][0]['s3']['bucket']['name']
        s3_key = event['Records'][0]['s3']['object']['key']
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Initialize DynamoDB record
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Store initial job information
        table.put_item(
            Item={
                'VideoId': f"{s3_bucket}/{s3_key}",
                'Timestamp': int(datetime.now().timestamp()),
                'JobId': job_id,
                'JobStatus': 'INITIATED',
                'S3Bucket': s3_bucket,
                'S3Key': s3_key,
                'CreatedAt': datetime.now().isoformat()
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'videoId': f"{s3_bucket}/{s3_key}",
                's3Bucket': s3_bucket,
                's3Key': s3_key,
                'status': 'INITIATED'
            }
        }
        
    except Exception as e:
        print(f"Error initializing video analysis: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
'''

    def _get_moderation_function_code(self) -> str:
        """Get the content moderation function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """Start content moderation analysis"""
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Extract job information
        job_id = event['jobId']
        s3_bucket = event['s3Bucket']
        s3_key = event['s3Key']
        video_id = event['videoId']
        
        # Start content moderation job
        response = rekognition.start_content_moderation(
            Video={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            MinConfidence=50.0,
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['REKOGNITION_ROLE_ARN']
            }
        )
        
        moderation_job_id = response['JobId']
        
        # Update DynamoDB with moderation job ID
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET ModerationJobId = :mjid, JobStatus = :status',
            ExpressionAttributeValues={
                ':mjid': moderation_job_id,
                ':status': 'MODERATION_IN_PROGRESS'
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'moderationJobId': moderation_job_id,
                'videoId': video_id,
                'status': 'MODERATION_IN_PROGRESS'
            }
        }
        
    except Exception as e:
        print(f"Error starting content moderation: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
'''

    def _get_segment_function_code(self) -> str:
        """Get the segment detection function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """Start segment detection analysis"""
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Extract job information
        job_id = event['jobId']
        s3_bucket = event['s3Bucket']
        s3_key = event['s3Key']
        video_id = event['videoId']
        
        # Start segment detection job
        response = rekognition.start_segment_detection(
            Video={
                'S3Object': {
                    'Bucket': s3_bucket,
                    'Name': s3_key
                }
            },
            SegmentTypes=['TECHNICAL_CUE', 'SHOT'],
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['REKOGNITION_ROLE_ARN']
            }
        )
        
        segment_job_id = response['JobId']
        
        # Update DynamoDB with segment job ID
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET SegmentJobId = :sjid, JobStatus = :status',
            ExpressionAttributeValues={
                ':sjid': segment_job_id,
                ':status': 'SEGMENT_DETECTION_IN_PROGRESS'
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'segmentJobId': segment_job_id,
                'videoId': video_id,
                'status': 'SEGMENT_DETECTION_IN_PROGRESS'
            }
        }
        
    except Exception as e:
        print(f"Error starting segment detection: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
'''

    def _get_aggregation_function_code(self) -> str:
        """Get the results aggregation function code"""
        return '''
import json
import boto3
import os
from datetime import datetime

def lambda_handler(event, context):
    """Aggregate and store analysis results"""
    try:
        rekognition = boto3.client('rekognition')
        dynamodb = boto3.resource('dynamodb')
        s3 = boto3.client('s3')
        
        table = dynamodb.Table(os.environ['ANALYSIS_TABLE'])
        
        # Extract job information
        job_id = event['jobId']
        video_id = event['videoId']
        moderation_job_id = event.get('moderationJobId')
        segment_job_id = event.get('segmentJobId')
        
        results = {
            'jobId': job_id,
            'videoId': video_id,
            'processedAt': datetime.now().isoformat(),
            'moderation': {},
            'segments': {},
            'summary': {}
        }
        
        # Get content moderation results
        if moderation_job_id:
            try:
                moderation_response = rekognition.get_content_moderation(
                    JobId=moderation_job_id
                )
                results['moderation'] = {
                    'jobStatus': moderation_response['JobStatus'],
                    'labels': moderation_response.get('ModerationLabels', [])
                }
            except Exception as e:
                print(f"Error getting moderation results: {str(e)}")
        
        # Get segment detection results
        if segment_job_id:
            try:
                segment_response = rekognition.get_segment_detection(
                    JobId=segment_job_id
                )
                results['segments'] = {
                    'jobStatus': segment_response['JobStatus'],
                    'technicalCues': segment_response.get('TechnicalCues', []),
                    'shotSegments': segment_response.get('Segments', [])
                }
            except Exception as e:
                print(f"Error getting segment results: {str(e)}")
        
        # Create summary
        moderation_labels = results['moderation'].get('labels', [])
        segment_count = len(results['segments'].get('shotSegments', []))
        
        results['summary'] = {
            'moderationLabelsCount': len(moderation_labels),
            'segmentCount': segment_count,
            'hasInappropriateContent': len(moderation_labels) > 0,
            'analysisComplete': True
        }
        
        # Store results in S3
        results_key = f"analysis-results/{job_id}/results.json"
        s3.put_object(
            Bucket=os.environ['RESULTS_BUCKET'],
            Key=results_key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        
        # Update DynamoDB with final results
        table.update_item(
            Key={
                'VideoId': video_id,
                'Timestamp': int(datetime.now().timestamp())
            },
            UpdateExpression='SET JobStatus = :status, ResultsS3Key = :s3key, Summary = :summary',
            ExpressionAttributeValues={
                ':status': 'COMPLETED',
                ':s3key': results_key,
                ':summary': results['summary']
            }
        )
        
        return {
            'statusCode': 200,
            'body': {
                'jobId': job_id,
                'videoId': video_id,
                'resultsLocation': f"s3://{os.environ['RESULTS_BUCKET']}/{results_key}",
                'summary': results['summary'],
                'status': 'COMPLETED'
            }
        }
        
    except Exception as e:
        print(f"Error aggregating results: {str(e)}")
        return {
            'statusCode': 500,
            'body': {
                'error': str(e)
            }
        }
'''

    def _get_trigger_function_code(self) -> str:
        """Get the S3 trigger function code"""
        return '''
import json
import boto3
import os

def lambda_handler(event, context):
    """Trigger video analysis workflow when new video is uploaded"""
    try:
        stepfunctions = boto3.client('stepfunctions')
        
        # Extract S3 event information
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Only process video files
            if not key.lower().endswith(('.mp4', '.avi', '.mov', '.mkv', '.wmv')):
                continue
            
            # Start Step Functions execution
            response = stepfunctions.start_execution(
                stateMachineArn=os.environ['STATE_MACHINE_ARN'],
                input=json.dumps({
                    'Records': [record]
                })
            )
            
            print(f"Started analysis for {bucket}/{key}: {response['executionArn']}")
        
        return {
            'statusCode': 200,
            'body': 'Video analysis workflow triggered successfully'
        }
        
    except Exception as e:
        print(f"Error triggering workflow: {str(e)}")
        return {
            'statusCode': 500,
            'body': str(e)
        }
'''


# Create the CDK app
app = cdk.App()

# Create the stack
VideoContentAnalysisStack(
    app,
    "VideoContentAnalysisStack",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    ),
    description="Video Content Analysis Pipeline with AWS Rekognition and Step Functions",
)

# Synthesize the CloudFormation template
app.synth()