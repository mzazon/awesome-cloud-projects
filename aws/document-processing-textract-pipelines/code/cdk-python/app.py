#!/usr/bin/env python3
"""
CDK Python Application for Document Processing Pipeline

This application deploys a complete document processing pipeline using:
- Amazon Textract for intelligent document analysis
- AWS Step Functions for workflow orchestration
- Amazon S3 for document storage
- AWS Lambda for event-driven processing
- Amazon DynamoDB for job tracking
- Amazon SNS for notifications

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_iam as iam,
    aws_logs as logs,
)


class DocumentProcessingPipelineStack(Stack):
    """
    CDK Stack for Document Processing Pipeline
    
    This stack creates a complete document processing pipeline that:
    1. Receives documents uploaded to S3
    2. Triggers Lambda function for workflow initiation
    3. Executes Step Functions workflow for document processing
    4. Uses Amazon Textract for intelligent document analysis
    5. Stores results and updates job tracking
    6. Sends notifications upon completion
    """

    def __init__(self, scope: App, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create S3 buckets for document storage
        self.document_bucket = self._create_document_bucket()
        self.results_bucket = self._create_results_bucket()

        # Create DynamoDB table for job tracking
        self.jobs_table = self._create_jobs_table()

        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()

        # Create IAM role for Step Functions
        self.step_functions_role = self._create_step_functions_role()

        # Create Step Functions state machine
        self.state_machine = self._create_state_machine()

        # Create Lambda function for workflow triggering
        self.trigger_function = self._create_trigger_function()

        # Configure S3 event notifications
        self._configure_s3_notifications()

        # Create stack outputs
        self._create_outputs()

    def _create_document_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for document uploads
        
        Returns:
            s3.Bucket: The created S3 bucket for document storage
        """
        bucket = s3.Bucket(
            self,
            "DocumentBucket",
            bucket_name=None,  # Auto-generated name
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    abort_incomplete_multipart_uploads_after=Duration.days(1),
                    noncurrent_version_expiration=Duration.days(30),
                    enabled=True,
                )
            ],
        )

        # Add bucket policy to deny insecure connections
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, f"{bucket.bucket_arn}/*"],
                conditions={
                    "Bool": {"aws:SecureTransport": "false"}
                },
            )
        )

        return bucket

    def _create_results_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for processing results
        
        Returns:
            s3.Bucket: The created S3 bucket for results storage
        """
        bucket = s3.Bucket(
            self,
            "ResultsBucket",
            bucket_name=None,  # Auto-generated name
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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
                    enabled=True,
                )
            ],
        )

        return bucket

    def _create_jobs_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for job tracking
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "JobsTable",
            table_name="DocumentProcessingJobs",
            partition_key=dynamodb.Attribute(
                name="JobId", type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            time_to_live_attribute="TTL",
        )

        # Add Global Secondary Index for status queries
        table.add_global_secondary_index(
            index_name="StatusIndex",
            partition_key=dynamodb.Attribute(
                name="Status", type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="ProcessedAt", type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )

        return table

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for notifications
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "NotificationTopic",
            topic_name="DocumentProcessingNotifications",
            display_name="Document Processing Notifications",
            fifo=False,
            content_based_deduplication=False,
        )

        # Add topic policy to allow Step Functions to publish
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowStepFunctionsPublish",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("states.amazonaws.com")],
                actions=["sns:Publish"],
                resources=[topic.topic_arn],
            )
        )

        return topic

    def _create_step_functions_role(self) -> iam.Role:
        """
        Create IAM role for Step Functions execution
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "StepFunctionsRole",
            role_name="DocumentProcessingStepFunctionsRole",
            assumed_by=iam.ServicePrincipal("states.amazonaws.com"),
            description="Role for Step Functions to execute document processing workflow",
        )

        # Add policies for Textract operations
        role.add_to_policy(
            iam.PolicyStatement(
                sid="TextractOperations",
                effect=iam.Effect.ALLOW,
                actions=[
                    "textract:AnalyzeDocument",
                    "textract:DetectDocumentText",
                    "textract:GetDocumentAnalysis",
                    "textract:GetDocumentTextDetection",
                    "textract:StartDocumentAnalysis",
                    "textract:StartDocumentTextDetection",
                ],
                resources=["*"],
            )
        )

        # Add policies for S3 operations
        role.add_to_policy(
            iam.PolicyStatement(
                sid="S3Operations",
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:PutObject"],
                resources=[
                    f"{self.document_bucket.bucket_arn}/*",
                    f"{self.results_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add policies for DynamoDB operations
        role.add_to_policy(
            iam.PolicyStatement(
                sid="DynamoDBOperations",
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:GetItem",
                ],
                resources=[self.jobs_table.table_arn],
            )
        )

        # Add policies for SNS operations
        role.add_to_policy(
            iam.PolicyStatement(
                sid="SNSOperations",
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.notification_topic.topic_arn],
            )
        )

        return role

    def _create_state_machine(self) -> sfn.StateMachine:
        """
        Create Step Functions state machine for document processing
        
        Returns:
            sfn.StateMachine: The created state machine
        """
        # Define the workflow definition
        process_document_choice = sfn.Choice(
            self, "ProcessDocumentChoice"
        ).when(
            sfn.Condition.boolean_equals("$.requiresAnalysis", True),
            self._create_analyze_document_task(),
        ).otherwise(
            self._create_detect_text_task()
        )

        # Define the complete workflow
        definition = process_document_choice

        # Create state machine
        state_machine = sfn.StateMachine(
            self,
            "DocumentProcessingStateMachine",
            state_machine_name="DocumentProcessingPipeline",
            definition=definition,
            role=self.step_functions_role,
            timeout=Duration.minutes(15),
            tracing_enabled=True,
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self,
                    "StateMachineLogGroup",
                    log_group_name="/aws/stepfunctions/DocumentProcessingPipeline",
                    removal_policy=RemovalPolicy.DESTROY,
                    retention=logs.RetentionDays.ONE_MONTH,
                ),
                level=sfn.LogLevel.ALL,
                include_execution_data=True,
            ),
        )

        return state_machine

    def _create_analyze_document_task(self) -> sfn.Chain:
        """
        Create Step Functions task for document analysis
        
        Returns:
            sfn.Chain: The analyze document task chain
        """
        analyze_task = sfn_tasks.CallAwsService(
            self,
            "AnalyzeDocument",
            service="textract",
            action="analyzeDocument",
            parameters={
                "Document": {
                    "S3Object": {
                        "Bucket": sfn.JsonPath.string_at("$.bucket"),
                        "Name": sfn.JsonPath.string_at("$.key"),
                    }
                },
                "FeatureTypes": ["TABLES", "FORMS", "SIGNATURES"],
            },
            result_path="$.textractResult",
            retry_on_service_exceptions=True,
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(5),
            max_attempts=3,
            backoff_rate=2.0,
        ).add_catch(
            handler=self._create_processing_failed_task(),
            errors=["States.ALL"],
            result_path="$.error",
        )

        return analyze_task.next(self._create_store_results_task())

    def _create_detect_text_task(self) -> sfn.Chain:
        """
        Create Step Functions task for text detection
        
        Returns:
            sfn.Chain: The detect text task chain
        """
        detect_task = sfn_tasks.CallAwsService(
            self,
            "DetectText",
            service="textract",
            action="detectDocumentText",
            parameters={
                "Document": {
                    "S3Object": {
                        "Bucket": sfn.JsonPath.string_at("$.bucket"),
                        "Name": sfn.JsonPath.string_at("$.key"),
                    }
                }
            },
            result_path="$.textractResult",
            retry_on_service_exceptions=True,
        ).add_retry(
            errors=["States.TaskFailed"],
            interval=Duration.seconds(5),
            max_attempts=3,
            backoff_rate=2.0,
        ).add_catch(
            handler=self._create_processing_failed_task(),
            errors=["States.ALL"],
            result_path="$.error",
        )

        return detect_task.next(self._create_store_results_task())

    def _create_store_results_task(self) -> sfn.Task:
        """
        Create Step Functions task for storing results
        
        Returns:
            sfn.Task: The store results task
        """
        store_task = sfn_tasks.CallAwsService(
            self,
            "StoreResults",
            service="s3",
            action="putObject",
            parameters={
                "Bucket": self.results_bucket.bucket_name,
                "Key": sfn.JsonPath.format("{}/results.json", sfn.JsonPath.string_at("$.jobId")),
                "Body": sfn.JsonPath.entire_payload,
            },
            result_path="$.storeResult",
        )

        return store_task.next(self._create_update_job_status_task())

    def _create_update_job_status_task(self) -> sfn.Task:
        """
        Create Step Functions task for updating job status
        
        Returns:
            sfn.Task: The update job status task
        """
        update_task = sfn_tasks.CallAwsService(
            self,
            "UpdateJobStatus",
            service="dynamodb",
            action="putItem",
            parameters={
                "TableName": self.jobs_table.table_name,
                "Item": {
                    "JobId": {"S": sfn.JsonPath.string_at("$.jobId")},
                    "Status": {"S": "COMPLETED"},
                    "ProcessedAt": {"S": sfn.JsonPath.string_at("$$.State.EnteredTime")},
                    "ResultsLocation": {
                        "S": sfn.JsonPath.format(
                            f"s3://{self.results_bucket.bucket_name}/{{0}}/results.json",
                            sfn.JsonPath.string_at("$.jobId")
                        )
                    },
                    "TTL": {"N": sfn.JsonPath.string_at("$$.Execution.StartTime")},
                },
            },
            result_path="$.updateResult",
        )

        return update_task.next(self._create_send_notification_task())

    def _create_send_notification_task(self) -> sfn.Task:
        """
        Create Step Functions task for sending notifications
        
        Returns:
            sfn.Task: The send notification task
        """
        notify_task = sfn_tasks.CallAwsService(
            self,
            "SendNotification",
            service="sns",
            action="publish",
            parameters={
                "TopicArn": self.notification_topic.topic_arn,
                "Message": sfn.JsonPath.format(
                    "Document processing completed for job {}", 
                    sfn.JsonPath.string_at("$.jobId")
                ),
                "Subject": "Document Processing Complete",
            },
        )

        return notify_task

    def _create_processing_failed_task(self) -> sfn.Task:
        """
        Create Step Functions task for handling processing failures
        
        Returns:
            sfn.Task: The processing failed task
        """
        failed_task = sfn_tasks.CallAwsService(
            self,
            "ProcessingFailed",
            service="dynamodb",
            action="putItem",
            parameters={
                "TableName": self.jobs_table.table_name,
                "Item": {
                    "JobId": {"S": sfn.JsonPath.string_at("$.jobId")},
                    "Status": {"S": "FAILED"},
                    "FailedAt": {"S": sfn.JsonPath.string_at("$$.State.EnteredTime")},
                    "Error": {"S": sfn.JsonPath.string_at("$.error.Error")},
                    "TTL": {"N": sfn.JsonPath.string_at("$$.Execution.StartTime")},
                },
            },
            result_path="$.updateResult",
        )

        notify_failure_task = sfn_tasks.CallAwsService(
            self,
            "NotifyFailure",
            service="sns",
            action="publish",
            parameters={
                "TopicArn": self.notification_topic.topic_arn,
                "Message": sfn.JsonPath.format(
                    "Document processing failed for job {}", 
                    sfn.JsonPath.string_at("$.jobId")
                ),
                "Subject": "Document Processing Failed",
            },
        )

        return failed_task.next(notify_failure_task)

    def _create_trigger_function(self) -> lambda_.Function:
        """
        Create Lambda function for triggering Step Functions workflow
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Lambda function code
        function_code = '''
import json
import boto3
import uuid
import os
from urllib.parse import unquote_plus

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Lambda handler for triggering Step Functions workflow
    
    Args:
        event: S3 event notification
        context: Lambda context
        
    Returns:
        dict: Response with status code
    """
    print(f"Received event: {json.dumps(event)}")
    
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        # Determine if document requires advanced analysis
        requires_analysis = (
            key.lower().endswith(('.pdf', '.tiff', '.tif')) or 
            'form' in key.lower() or 
            'table' in key.lower()
        )
        
        # Generate unique job ID
        job_id = str(uuid.uuid4())
        
        # Prepare input for Step Functions
        input_data = {
            'bucket': bucket,
            'key': key,
            'jobId': job_id,
            'requiresAnalysis': requires_analysis
        }
        
        try:
            # Start Step Functions execution
            response = stepfunctions.start_execution(
                stateMachineArn=os.environ['STATE_MACHINE_ARN'],
                name=f'doc-processing-{job_id}',
                input=json.dumps(input_data)
            )
            
            print(f'Started processing job {job_id} for document {key}')
            print(f'Execution ARN: {response["executionArn"]}')
            
        except Exception as e:
            print(f'Error starting execution for {key}: {str(e)}')
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Successfully triggered document processing')
    }
'''

        function = lambda_.Function(
            self,
            "TriggerFunction",
            function_name="DocumentProcessingTrigger",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            environment={
                "STATE_MACHINE_ARN": self.state_machine.state_machine_arn,
            },
            timeout=Duration.minutes(1),
            memory_size=256,
            retry_attempts=0,
            log_retention=logs.RetentionDays.ONE_MONTH,
            tracing=lambda_.Tracing.ACTIVE,
        )

        # Grant permissions to execute Step Functions
        self.state_machine.grant_start_execution(function)

        return function

    def _configure_s3_notifications(self) -> None:
        """
        Configure S3 bucket notifications to trigger Lambda function
        """
        self.document_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.trigger_function),
            s3.NotificationKeyFilter(
                suffix=".pdf"
            ),
        )

        # Add additional file type filters
        supported_extensions = [".png", ".jpg", ".jpeg", ".tiff", ".tif"]
        for ext in supported_extensions:
            self.document_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.trigger_function),
                s3.NotificationKeyFilter(suffix=ext),
            )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resources
        """
        CfnOutput(
            self,
            "DocumentBucketName",
            value=self.document_bucket.bucket_name,
            description="S3 bucket name for document uploads",
            export_name=f"{self.stack_name}-DocumentBucket",
        )

        CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 bucket name for processing results",
            export_name=f"{self.stack_name}-ResultsBucket",
        )

        CfnOutput(
            self,
            "JobsTableName",
            value=self.jobs_table.table_name,
            description="DynamoDB table name for job tracking",
            export_name=f"{self.stack_name}-JobsTable",
        )

        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
            export_name=f"{self.stack_name}-NotificationTopic",
        )

        CfnOutput(
            self,
            "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="Step Functions state machine ARN",
            export_name=f"{self.stack_name}-StateMachine",
        )

        CfnOutput(
            self,
            "TriggerFunctionName",
            value=self.trigger_function.function_name,
            description="Lambda function name for workflow triggering",
            export_name=f"{self.stack_name}-TriggerFunction",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = App()

    # Get environment from context or use default
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )

    # Create the main stack
    DocumentProcessingPipelineStack(
        app,
        "DocumentProcessingPipelineStack",
        env=env,
        description="Document Processing Pipeline with Amazon Textract and Step Functions",
        tags={
            "Project": "DocumentProcessing",
            "Environment": "Production",
            "ManagedBy": "CDK",
        },
    )

    app.synth()


if __name__ == "__main__":
    main()