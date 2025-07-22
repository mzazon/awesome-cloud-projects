#!/usr/bin/env python3
"""
CDK Python application for automated document processing pipeline with Amazon Textract and Step Functions.

This application deploys a comprehensive document processing solution that:
- Automatically processes documents uploaded to S3
- Uses Amazon Textract for AI-powered text and data extraction
- Orchestrates workflows with AWS Step Functions
- Provides monitoring and alerting capabilities
- Implements security best practices

Author: AWS CDK Team
Version: 1.0.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_lambda as lambda_,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cw,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    CfnOutput,
    Tags,
)
from constructs import Construct


class DocumentProcessingPipelineStack(Stack):
    """
    CDK Stack for automated document processing pipeline.
    
    This stack creates:
    - S3 buckets for input, output, and archive storage
    - Lambda functions for document processing and result handling
    - Step Functions state machine for workflow orchestration
    - CloudWatch monitoring and alerting
    - SNS notifications for processing status
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        notification_email: str = "",
        **kwargs: Any,
    ) -> None:
        """
        Initialize the DocumentProcessingPipelineStack.
        
        Args:
            scope: The parent construct
            construct_id: The construct identifier
            project_name: Unique project name for resource naming
            notification_email: Email address for SNS notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.notification_email = notification_email

        # Create S3 buckets for document storage
        self._create_s3_buckets()

        # Create Lambda functions for document processing
        self._create_lambda_functions()

        # Create Step Functions state machine
        self._create_step_functions_state_machine()

        # Configure S3 event notifications
        self._configure_s3_notifications()

        # Create CloudWatch monitoring resources
        self._create_monitoring_resources()

        # Create SNS topic for notifications
        self._create_notification_resources()

        # Add stack outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_resource_tags()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for input, output, and archive storage."""
        # Input bucket for document uploads
        self.input_bucket = s3.Bucket(
            self,
            "InputBucket",
            bucket_name=f"{self.project_name}-input-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

        # Output bucket for processed results
        self.output_bucket = s3.Bucket(
            self,
            "OutputBucket",
            bucket_name=f"{self.project_name}-output-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                )
            ],
        )

        # Archive bucket for long-term storage
        self.archive_bucket = s3.Bucket(
            self,
            "ArchiveBucket",
            bucket_name=f"{self.project_name}-archive-{self.account}-{self.region}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveRule",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(1),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(90),
                        ),
                    ],
                )
            ],
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for document processing."""
        # Common Lambda execution role
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "TextractAndS3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "textract:StartDocumentAnalysis",
                                "textract:StartDocumentTextDetection",
                                "textract:GetDocumentAnalysis",
                                "textract:GetDocumentTextDetection",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                            ],
                            resources=[
                                f"{self.input_bucket.bucket_arn}/*",
                                f"{self.output_bucket.bucket_arn}/*",
                                f"{self.archive_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:ListBucket"],
                            resources=[
                                self.input_bucket.bucket_arn,
                                self.output_bucket.bucket_arn,
                                self.archive_bucket.bucket_arn,
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["states:StartExecution"],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

        # Document processor Lambda function
        self.document_processor_function = lambda_.Function(
            self,
            "DocumentProcessorFunction",
            function_name=f"{self.project_name}-document-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_document_processor_code()),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "INPUT_BUCKET": self.input_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "ARCHIVE_BUCKET": self.archive_bucket.bucket_name,
            },
            description="Initiates Textract document processing",
        )

        # Results processor Lambda function
        self.results_processor_function = lambda_.Function(
            self,
            "ResultsProcessorFunction",
            function_name=f"{self.project_name}-results-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_results_processor_code()),
            role=lambda_role,
            timeout=Duration.seconds(300),
            memory_size=512,
            environment={
                "INPUT_BUCKET": self.input_bucket.bucket_name,
                "OUTPUT_BUCKET": self.output_bucket.bucket_name,
                "ARCHIVE_BUCKET": self.archive_bucket.bucket_name,
            },
            description="Processes and formats Textract extraction results",
        )

        # S3 trigger Lambda function
        self.s3_trigger_function = lambda_.Function(
            self,
            "S3TriggerFunction",
            function_name=f"{self.project_name}-s3-trigger",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_s3_trigger_code()),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Triggers document processing pipeline from S3 events",
        )

    def _create_step_functions_state_machine(self) -> None:
        """Create Step Functions state machine for workflow orchestration."""
        # Step Functions execution role
        step_functions_role = iam.Role(
            self,
            "StepFunctionsExecutionRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            inline_policies={
                "StepFunctionsExecutionPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["lambda:InvokeFunction"],
                            resources=[
                                self.document_processor_function.function_arn,
                                self.results_processor_function.function_arn,
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

        # Define Step Functions tasks
        process_document_task = sfn_tasks.LambdaInvoke(
            self,
            "ProcessDocumentTask",
            lambda_function=self.document_processor_function,
            input_path="$",
            result_path="$.processResult",
            retry_on_service_exceptions=True,
        )

        wait_for_completion = sfn.Wait(
            self,
            "WaitForTextractCompletion",
            time=sfn.WaitTime.duration(Duration.seconds(30)),
        )

        check_status_task = sfn_tasks.LambdaInvoke(
            self,
            "CheckTextractStatusTask",
            lambda_function=self.results_processor_function,
            input_path="$",
            result_path="$.statusResult",
            retry_on_service_exceptions=True,
        )

        # Define Step Functions states
        processing_completed = sfn.Succeed(
            self,
            "ProcessingCompleted",
            comment="Document processing completed successfully",
        )

        processing_failed = sfn.Fail(
            self,
            "ProcessingFailed",
            cause="Document processing failed",
            error="ProcessingError",
        )

        # Define choice conditions
        status_choice = sfn.Choice(self, "EvaluateStatus")
        status_choice.when(
            sfn.Condition.string_equals("$.statusResult.Payload.status", "COMPLETED"),
            processing_completed,
        )
        status_choice.when(
            sfn.Condition.string_equals("$.statusResult.Payload.status", "IN_PROGRESS"),
            wait_for_completion,
        )
        status_choice.when(
            sfn.Condition.string_equals("$.statusResult.Payload.status", "FAILED"),
            processing_failed,
        )
        status_choice.otherwise(processing_failed)

        # Define workflow
        definition = (
            process_document_task
            .next(wait_for_completion)
            .next(check_status_task)
            .next(status_choice)
        )

        # Create state machine
        self.state_machine = sfn.StateMachine(
            self,
            "DocumentProcessingStateMachine",
            state_machine_name=f"{self.project_name}-document-pipeline",
            definition=definition,
            role=step_functions_role,
            timeout=Duration.minutes(30),
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "StateMachineLogGroup",
                    log_group_name=f"/aws/stepfunctions/{self.project_name}-document-pipeline",
                    retention=logs.RetentionDays.TWO_WEEKS,
                    removal_policy=RemovalPolicy.DESTROY,
                ),
                level=sfn.LogLevel.ALL,
            ),
        )

        # Update S3 trigger function with state machine ARN
        self.s3_trigger_function.add_environment(
            "STATE_MACHINE_ARN", self.state_machine.state_machine_arn
        )

        # Grant S3 trigger function permission to start executions
        self.state_machine.grant_start_execution(self.s3_trigger_function)

    def _configure_s3_notifications(self) -> None:
        """Configure S3 event notifications to trigger processing."""
        # Add S3 event notification for PDF files
        self.input_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.s3_trigger_function),
            s3.NotificationKeyFilter(suffix=".pdf"),
        )

        # Add notifications for other supported formats
        for file_extension in [".png", ".jpg", ".jpeg", ".tiff"]:
            self.input_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.s3_trigger_function),
                s3.NotificationKeyFilter(suffix=file_extension),
            )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring resources."""
        # Create CloudWatch dashboard
        self.dashboard = cw.Dashboard(
            self,
            "DocumentProcessingDashboard",
            dashboard_name=f"{self.project_name}-pipeline-monitoring",
            widgets=[
                [
                    cw.GraphWidget(
                        title="Lambda Function Metrics",
                        width=12,
                        height=6,
                        left=[
                            self.document_processor_function.metric_invocations(),
                            self.results_processor_function.metric_invocations(),
                            self.s3_trigger_function.metric_invocations(),
                        ],
                        right=[
                            self.document_processor_function.metric_errors(),
                            self.results_processor_function.metric_errors(),
                            self.s3_trigger_function.metric_errors(),
                        ],
                    ),
                    cw.GraphWidget(
                        title="Step Functions Metrics",
                        width=12,
                        height=6,
                        left=[
                            self.state_machine.metric_started(),
                            self.state_machine.metric_succeeded(),
                            self.state_machine.metric_failed(),
                        ],
                        right=[
                            self.state_machine.metric_time(),
                        ],
                    ),
                ],
                [
                    cw.GraphWidget(
                        title="S3 Storage Metrics",
                        width=24,
                        height=6,
                        left=[
                            self.input_bucket.metric_number_of_objects(),
                            self.output_bucket.metric_number_of_objects(),
                            self.archive_bucket.metric_number_of_objects(),
                        ],
                    ),
                ],
            ],
        )

        # Create CloudWatch alarms for critical failures
        self.state_machine_failures_alarm = cw.Alarm(
            self,
            "StateMachineFailuresAlarm",
            metric=self.state_machine.metric_failed(),
            threshold=1,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            alarm_description="Step Functions state machine execution failures",
            treat_missing_data=cw.TreatMissingData.NOT_BREACHING,
        )

        self.lambda_errors_alarm = cw.Alarm(
            self,
            "LambdaErrorsAlarm",
            metric=cw.MathExpression(
                expression="e1 + e2 + e3",
                using_metrics={
                    "e1": self.document_processor_function.metric_errors(),
                    "e2": self.results_processor_function.metric_errors(),
                    "e3": self.s3_trigger_function.metric_errors(),
                },
            ),
            threshold=3,
            evaluation_periods=2,
            datapoints_to_alarm=1,
            alarm_description="High Lambda function error rate",
            treat_missing_data=cw.TreatMissingData.NOT_BREACHING,
        )

    def _create_notification_resources(self) -> None:
        """Create SNS topic and subscriptions for notifications."""
        # Create SNS topic for notifications
        self.notification_topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name=f"{self.project_name}-notifications",
            display_name="Document Processing Pipeline Notifications",
        )

        # Add email subscription if provided
        if self.notification_email:
            self.notification_topic.add_subscription(
                subs.EmailSubscription(self.notification_email)
            )

        # Connect alarms to SNS topic
        self.state_machine_failures_alarm.add_alarm_action(
            cw.SnsAction(self.notification_topic)
        )
        self.lambda_errors_alarm.add_alarm_action(
            cw.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "InputBucketName",
            value=self.input_bucket.bucket_name,
            description="S3 bucket for document uploads",
        )

        CfnOutput(
            self,
            "OutputBucketName",
            value=self.output_bucket.bucket_name,
            description="S3 bucket for processed results",
        )

        CfnOutput(
            self,
            "ArchiveBucketName",
            value=self.archive_bucket.bucket_name,
            description="S3 bucket for document archive",
        )

        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-pipeline-monitoring",
            description="CloudWatch dashboard URL",
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
        )

    def _add_resource_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", "production")
        Tags.of(self).add("Application", "document-processing-pipeline")
        Tags.of(self).add("Owner", "engineering-team")
        Tags.of(self).add("CostCenter", "operations")

    def _get_document_processor_code(self) -> str:
        """Get the Lambda function code for document processing."""
        return """
import json
import boto3
import logging
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Extract S3 information from event
        bucket = event['bucket']
        key = unquote_plus(event['key'])
        
        logger.info(f"Processing document: s3://{bucket}/{key}")
        
        # Determine document type and processing method
        file_extension = key.lower().split('.')[-1]
        
        # Configure Textract parameters based on document type
        if file_extension in ['pdf', 'png', 'jpg', 'jpeg', 'tiff']:
            # Start document analysis for complex documents
            response = textract.start_document_analysis(
                DocumentLocation={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                FeatureTypes=['TABLES', 'FORMS', 'SIGNATURES']
            )
            
            job_id = response['JobId']
            
            return {
                'statusCode': 200,
                'jobId': job_id,
                'jobType': 'ANALYSIS',
                'bucket': bucket,
                'key': key,
                'documentType': file_extension
            }
        else:
            raise ValueError(f"Unsupported file type: {file_extension}")
            
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
"""

    def _get_results_processor_code(self) -> str:
        """Get the Lambda function code for results processing."""
        return """
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        job_id = event['jobId']
        job_type = event['jobType']
        bucket = event['bucket']
        key = event['key']
        
        logger.info(f"Processing results for job: {job_id}")
        
        # Get Textract results based on job type
        if job_type == 'ANALYSIS':
            response = textract.get_document_analysis(JobId=job_id)
        else:
            response = textract.get_document_text_detection(JobId=job_id)
        
        # Check job status
        job_status = response['JobStatus']
        
        if job_status == 'SUCCEEDED':
            # Process and structure the results
            processed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'sourceDocument': f"s3://{bucket}/{key}",
                'jobId': job_id,
                'jobType': job_type,
                'documentMetadata': response.get('DocumentMetadata', {}),
                'extractedData': {
                    'text': [],
                    'tables': [],
                    'forms': []
                }
            }
            
            # Parse blocks and extract meaningful data
            blocks = response.get('Blocks', [])
            
            for block in blocks:
                if block['BlockType'] == 'LINE':
                    processed_data['extractedData']['text'].append({
                        'text': block.get('Text', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {})
                    })
                elif block['BlockType'] == 'TABLE':
                    table_data = {
                        'id': block.get('Id', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {}),
                        'rowCount': block.get('RowCount', 0),
                        'columnCount': block.get('ColumnCount', 0)
                    }
                    processed_data['extractedData']['tables'].append(table_data)
                elif block['BlockType'] == 'KEY_VALUE_SET':
                    if block.get('EntityTypes') and 'KEY' in block['EntityTypes']:
                        form_data = {
                            'id': block.get('Id', ''),
                            'confidence': block.get('Confidence', 0),
                            'geometry': block.get('Geometry', {}),
                            'text': block.get('Text', '')
                        }
                        processed_data['extractedData']['forms'].append(form_data)
            
            # Save processed results to S3 output bucket
            output_bucket = os.environ.get('OUTPUT_BUCKET', bucket)
            output_key = f"processed/{key.replace('.', '_')}_results.json"
            
            s3.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=json.dumps(processed_data, indent=2),
                ContentType='application/json',
                Metadata={
                    'source-bucket': bucket,
                    'source-key': key,
                    'processing-timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Archive original document
            archive_bucket = os.environ.get('ARCHIVE_BUCKET')
            if archive_bucket:
                archive_key = f"archive/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"
                s3.copy_object(
                    CopySource={'Bucket': bucket, 'Key': key},
                    Bucket=archive_bucket,
                    Key=archive_key
                )
            
            return {
                'statusCode': 200,
                'status': 'COMPLETED',
                'outputLocation': f"s3://{output_bucket}/{output_key}",
                'extractedItems': {
                    'textLines': len(processed_data['extractedData']['text']),
                    'tables': len(processed_data['extractedData']['tables']),
                    'forms': len(processed_data['extractedData']['forms'])
                }
            }
            
        elif job_status == 'FAILED':
            logger.error(f"Textract job failed: {job_id}")
            return {
                'statusCode': 500,
                'status': 'FAILED',
                'error': 'Textract job failed'
            }
        else:
            # Job still in progress
            return {
                'statusCode': 202,
                'status': 'IN_PROGRESS',
                'message': f"Job status: {job_status}"
            }
            
    except Exception as e:
        logger.error(f"Error processing results: {str(e)}")
        return {
            'statusCode': 500,
            'status': 'ERROR',
            'error': str(e)
        }
"""

    def _get_s3_trigger_code(self) -> str:
        """Get the Lambda function code for S3 event handling."""
        return """
import json
import boto3
import logging
import os
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        state_machine_arn = os.environ['STATE_MACHINE_ARN']
        
        # Process S3 event records
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"New document uploaded: s3://{bucket}/{key}")
            
            # Start Step Functions execution
            execution_input = {
                'bucket': bucket,
                'key': key,
                'eventTime': record['eventTime']
            }
            
            execution_name = f"doc-processing-{key.replace('/', '-').replace('.', '-')}-{context.aws_request_id[:8]}"
            
            response = stepfunctions.start_execution(
                stateMachineArn=state_machine_arn,
                name=execution_name,
                input=json.dumps(execution_input)
            )
            
            logger.info(f"Started execution: {response['executionArn']}")
            
        return {
            'statusCode': 200,
            'message': f"Processed {len(event['Records'])} document(s)"
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
"""


def main() -> None:
    """Main application entry point."""
    app = cdk.App()

    # Get configuration from context or environment variables
    project_name = app.node.try_get_context("project_name") or os.environ.get(
        "PROJECT_NAME", "textract-pipeline"
    )
    notification_email = app.node.try_get_context("notification_email") or os.environ.get(
        "NOTIFICATION_EMAIL", ""
    )
    
    # Create the main stack
    DocumentProcessingPipelineStack(
        app,
        "DocumentProcessingPipelineStack",
        project_name=project_name,
        notification_email=notification_email,
        description="Automated document processing pipeline with Amazon Textract and Step Functions",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        ),
    )

    app.synth()


if __name__ == "__main__":
    main()