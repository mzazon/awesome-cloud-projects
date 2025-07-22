#!/usr/bin/env python3
"""
AWS CDK Python application for building automated business file processing
with AWS Transfer Family and Step Functions.

This application creates a complete serverless file processing pipeline that:
- Provides secure SFTP endpoints via AWS Transfer Family
- Automatically processes files using Lambda functions
- Orchestrates workflows with Step Functions
- Stores files across multiple S3 buckets with lifecycle policies
- Monitors processing with CloudWatch and SNS notifications

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_stepfunctions as sfn,
    aws_stepfunctions_tasks as sfn_tasks,
    aws_iam as iam,
    aws_transfer as transfer,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
import json


class FileProcessingStack(Stack):
    """
    CDK Stack for automated business file processing with Transfer Family and Step Functions.
    
    This stack creates a complete serverless architecture for processing business files
    uploaded via SFTP, including validation, transformation, and routing capabilities.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Project configuration
        project_name = "file-processing"
        
        # Create S3 buckets for different stages of file processing
        self.landing_bucket = self._create_landing_bucket(project_name)
        self.processed_bucket = self._create_processed_bucket(project_name)
        self.archive_bucket = self._create_archive_bucket(project_name)
        
        # Create Lambda functions for file processing logic
        self.validator_function = self._create_validator_function(project_name)
        self.processor_function = self._create_processor_function(project_name)
        self.router_function = self._create_router_function(project_name)
        
        # Grant S3 permissions to Lambda functions
        self._grant_lambda_permissions()
        
        # Create Step Functions workflow
        self.state_machine = self._create_step_functions_workflow(project_name)
        
        # Create Transfer Family SFTP server
        self.transfer_server = self._create_transfer_family_server(project_name)
        
        # Create EventBridge rule for S3 events
        self._create_eventbridge_integration()
        
        # Create monitoring and alerting
        self.sns_topic = self._create_monitoring_and_alerts(project_name)
        
        # Create outputs
        self._create_outputs()

    def _create_landing_bucket(self, project_name: str) -> s3.Bucket:
        """
        Create S3 bucket for landing incoming files from SFTP uploads.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            S3 bucket configured for landing zone
        """
        bucket = s3.Bucket(
            self, "LandingBucket",
            bucket_name=f"{project_name}-landing-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            event_bridge_enabled=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )
        
        # Add tags for cost tracking and management
        cdk.Tags.of(bucket).add("Project", project_name)
        cdk.Tags.of(bucket).add("Environment", "development")
        cdk.Tags.of(bucket).add("Purpose", "file-landing")
        
        return bucket

    def _create_processed_bucket(self, project_name: str) -> s3.Bucket:
        """
        Create S3 bucket for storing processed files.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            S3 bucket configured for processed files
        """
        bucket = s3.Bucket(
            self, "ProcessedBucket",
            bucket_name=f"{project_name}-processed-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
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
        
        cdk.Tags.of(bucket).add("Project", project_name)
        cdk.Tags.of(bucket).add("Environment", "development")
        cdk.Tags.of(bucket).add("Purpose", "processed-files")
        
        return bucket

    def _create_archive_bucket(self, project_name: str) -> s3.Bucket:
        """
        Create S3 bucket for archiving final processed files.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            S3 bucket configured for archival storage
        """
        bucket = s3.Bucket(
            self, "ArchiveBucket",
            bucket_name=f"{project_name}-archive-{self.account}-{self.region}",
            versioned=False,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveTransition",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(1)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        cdk.Tags.of(bucket).add("Project", project_name)
        cdk.Tags.of(bucket).add("Environment", "development")
        cdk.Tags.of(bucket).add("Purpose", "archive-storage")
        
        return bucket

    def _create_validator_function(self, project_name: str) -> lambda_.Function:
        """
        Create Lambda function for file validation.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            Lambda function for file validation
        """
        function = lambda_.Function(
            self, "ValidatorFunction",
            function_name=f"{project_name}-validator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "LANDING_BUCKET": self.landing_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            code=lambda_.Code.from_inline("""
import json
import boto3
import csv
from io import StringIO
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    \"\"\"
    Validate incoming files for format compliance and data quality.
    
    Args:
        event: Lambda event containing file information
        context: Lambda context object
        
    Returns:
        Validation result with file metadata
    \"\"\"
    s3 = boto3.client('s3')
    
    try:
        # Extract S3 information from EventBridge or direct input
        if 'detail' in event:
            bucket = event['detail']['bucket']['name']
            key = event['detail']['object']['key']
        else:
            bucket = event['bucket']
            key = event['key']
        
        logger.info(f"Validating file: s3://{bucket}/{key}")
        
        # Download and validate file format
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Validate CSV format
        csv_reader = csv.reader(StringIO(content))
        rows = list(csv_reader)
        
        if len(rows) < 2:  # Header + at least one data row
            raise ValueError("File must contain header and data rows")
        
        # Additional validation rules
        header = rows[0]
        if len(header) < 2:
            raise ValueError("File must have at least 2 columns")
        
        # Check for empty rows
        empty_rows = sum(1 for row in rows[1:] if not any(cell.strip() for cell in row))
        if empty_rows > 0:
            logger.warning(f"Found {empty_rows} empty rows in file")
        
        result = {
            'statusCode': 200,
            'isValid': True,
            'rowCount': len(rows) - 1,
            'columnCount': len(header),
            'headers': header,
            'bucket': bucket,
            'key': key,
            'fileSize': response['ContentLength']
        }
        
        logger.info(f"File validation successful: {result}")
        return result
        
    except Exception as e:
        error_result = {
            'statusCode': 400,
            'isValid': False,
            'error': str(e),
            'bucket': bucket if 'bucket' in locals() else 'unknown',
            'key': key if 'key' in locals() else 'unknown'
        }
        
        logger.error(f"File validation failed: {error_result}")
        return error_result
""")
        )
        
        cdk.Tags.of(function).add("Project", project_name)
        cdk.Tags.of(function).add("Component", "file-validator")
        
        return function

    def _create_processor_function(self, project_name: str) -> lambda_.Function:
        """
        Create Lambda function for file processing and transformation.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            Lambda function for file processing
        """
        function = lambda_.Function(
            self, "ProcessorFunction",
            function_name=f"{project_name}-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "LANDING_BUCKET": self.landing_bucket.bucket_name,
                "PROCESSED_BUCKET": self.processed_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            code=lambda_.Code.from_inline("""
import json
import boto3
import csv
import io
from datetime import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    \"\"\"
    Process and transform file data according to business rules.
    
    Args:
        event: Lambda event containing file information
        context: Lambda context object
        
    Returns:
        Processing result with transformed file location
    \"\"\"
    s3 = boto3.client('s3')
    bucket = event['bucket']
    key = event['key']
    
    try:
        logger.info(f"Processing file: s3://{bucket}/{key}")
        
        # Download original file
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Process CSV data
        csv_reader = csv.DictReader(io.StringIO(content))
        processed_rows = []
        
        for row_num, row in enumerate(csv_reader, 1):
            # Add processing metadata
            row['processed_timestamp'] = datetime.utcnow().isoformat()
            row['processed_by'] = 'file-processing-pipeline'
            row['row_number'] = row_num
            
            # Apply business logic transformations
            if 'amount' in row:
                try:
                    # Normalize amount field
                    amount = float(row['amount'].replace(',', '').replace('$', ''))
                    row['amount_normalized'] = f"{amount:.2f}"
                except ValueError:
                    row['amount_normalized'] = '0.00'
                    row['validation_warning'] = 'Invalid amount format'
            
            # Add data quality indicators
            empty_fields = [k for k, v in row.items() if not str(v).strip()]
            if empty_fields:
                row['empty_fields'] = ','.join(empty_fields)
            
            processed_rows.append(row)
        
        # Convert back to CSV
        output = io.StringIO()
        if processed_rows:
            writer = csv.DictWriter(output, fieldnames=processed_rows[0].keys())
            writer.writeheader()
            writer.writerows(processed_rows)
        
        # Upload processed file
        processed_bucket = os.environ['PROCESSED_BUCKET']
        processed_key = f"processed/{key}"
        
        s3.put_object(
            Bucket=processed_bucket,
            Key=processed_key,
            Body=output.getvalue(),
            ContentType='text/csv',
            Metadata={
                'original-bucket': bucket,
                'original-key': key,
                'processed-timestamp': datetime.utcnow().isoformat(),
                'record-count': str(len(processed_rows))
            }
        )
        
        result = {
            'statusCode': 200,
            'processedKey': processed_key,
            'processedBucket': processed_bucket,
            'recordCount': len(processed_rows),
            'bucket': bucket,
            'originalKey': key
        }
        
        logger.info(f"File processing successful: {result}")
        return result
        
    except Exception as e:
        error_result = {
            'statusCode': 500,
            'error': str(e),
            'bucket': bucket,
            'key': key
        }
        
        logger.error(f"File processing failed: {error_result}")
        return error_result
""")
        )
        
        cdk.Tags.of(function).add("Project", project_name)
        cdk.Tags.of(function).add("Component", "file-processor")
        
        return function

    def _create_router_function(self, project_name: str) -> lambda_.Function:
        """
        Create Lambda function for intelligent file routing.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            Lambda function for file routing
        """
        function = lambda_.Function(
            self, "RouterFunction",
            function_name=f"{project_name}-router",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            timeout=Duration.minutes(3),
            memory_size=256,
            environment={
                "PROCESSED_BUCKET": self.processed_bucket.bucket_name,
                "ARCHIVE_BUCKET": self.archive_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
import os
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    \"\"\"
    Route processed files to appropriate destinations based on content analysis.
    
    Args:
        event: Lambda event containing processed file information
        context: Lambda context object
        
    Returns:
        Routing result with destination information
    \"\"\"
    s3 = boto3.client('s3')
    
    processed_bucket = event['processedBucket']
    processed_key = event['processedKey']
    record_count = event['recordCount']
    original_key = event['originalKey']
    
    try:
        logger.info(f"Routing file: s3://{processed_bucket}/{processed_key}")
        
        # Determine routing destination based on file content and metadata
        destination_path = _determine_destination(original_key, record_count)
        
        # Copy to archive with organized structure
        archive_bucket = os.environ['ARCHIVE_BUCKET']
        archive_key = f"{destination_path}{original_key}"
        
        # Add timestamp to archive path for versioning
        timestamp = datetime.utcnow().strftime('%Y/%m/%d')
        final_archive_key = f"{destination_path}{timestamp}/{original_key}"
        
        s3.copy_object(
            CopySource={'Bucket': processed_bucket, 'Key': processed_key},
            Bucket=archive_bucket,
            Key=final_archive_key,
            MetadataDirective='COPY'
        )
        
        # Add routing metadata
        s3.put_object_tagging(
            Bucket=archive_bucket,
            Key=final_archive_key,
            Tagging={
                'TagSet': [
                    {'Key': 'RoutingDestination', 'Value': destination_path.rstrip('/')},
                    {'Key': 'ProcessedDate', 'Value': timestamp},
                    {'Key': 'RecordCount', 'Value': str(record_count)},
                    {'Key': 'OriginalFile', 'Value': original_key}
                ]
            }
        )
        
        result = {
            'statusCode': 200,
            'destination': destination_path,
            'archiveKey': final_archive_key,
            'archiveBucket': archive_bucket,
            'recordCount': record_count,
            'routingRules': _get_routing_rules()
        }
        
        logger.info(f"File routing successful: {result}")
        return result
        
    except Exception as e:
        error_result = {
            'statusCode': 500,
            'error': str(e),
            'processedBucket': processed_bucket,
            'processedKey': processed_key
        }
        
        logger.error(f"File routing failed: {error_result}")
        return error_result

def _determine_destination(file_key: str, record_count: int) -> str:
    \"\"\"
    Determine the appropriate destination path based on file characteristics.
    
    Args:
        file_key: Original file key
        record_count: Number of records in the file
        
    Returns:
        Destination path for the file
    \"\"\"
    file_key_lower = file_key.lower()
    
    # Route based on file name patterns
    if 'financial' in file_key_lower or 'payment' in file_key_lower:
        return 'financial-data/'
    elif 'inventory' in file_key_lower or 'stock' in file_key_lower:
        return 'inventory-data/'
    elif 'customer' in file_key_lower or 'user' in file_key_lower:
        return 'customer-data/'
    elif 'order' in file_key_lower or 'transaction' in file_key_lower:
        return 'transaction-data/'
    
    # Route based on file size (record count)
    if record_count > 10000:
        return 'bulk-data/'
    elif record_count < 100:
        return 'small-files/'
    
    # Default destination
    return 'general-data/'

def _get_routing_rules() -> dict:
    \"\"\"
    Get the current routing rules for documentation.
    
    Returns:
        Dictionary of routing rules
    \"\"\"
    return {
        'patterns': {
            'financial': 'financial-data/',
            'inventory': 'inventory-data/',
            'customer': 'customer-data/',
            'transaction': 'transaction-data/'
        },
        'size_rules': {
            'bulk': '>10000 records',
            'small': '<100 records',
            'general': 'default'
        }
    }
""")
        )
        
        cdk.Tags.of(function).add("Project", project_name)
        cdk.Tags.of(function).add("Component", "file-router")
        
        return function

    def _grant_lambda_permissions(self) -> None:
        """Grant necessary S3 permissions to Lambda functions."""
        # Grant read/write permissions to all buckets for all functions
        for bucket in [self.landing_bucket, self.processed_bucket, self.archive_bucket]:
            bucket.grant_read_write(self.validator_function)
            bucket.grant_read_write(self.processor_function)
            bucket.grant_read_write(self.router_function)

    def _create_step_functions_workflow(self, project_name: str) -> sfn.StateMachine:
        """
        Create Step Functions state machine for workflow orchestration.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            Step Functions state machine
        """
        # Define Lambda tasks
        validate_task = sfn_tasks.LambdaInvoke(
            self, "ValidateFileTask",
            lambda_function=self.validator_function,
            comment="Validate incoming file format and content",
            retry_on_service_exceptions=True,
            output_path="$.Payload"
        )
        
        process_task = sfn_tasks.LambdaInvoke(
            self, "ProcessFileTask",
            lambda_function=self.processor_function,
            comment="Process and transform file data",
            retry_on_service_exceptions=True,
            output_path="$.Payload"
        )
        
        route_task = sfn_tasks.LambdaInvoke(
            self, "RouteFileTask",
            lambda_function=self.router_function,
            comment="Route processed file to appropriate destination",
            retry_on_service_exceptions=True,
            output_path="$.Payload"
        )
        
        # Define success and failure states
        success_state = sfn.Succeed(
            self, "ProcessingComplete",
            comment="File processing completed successfully"
        )
        
        validation_failed_state = sfn.Fail(
            self, "ValidationFailed",
            comment="File validation failed",
            cause="File does not meet validation requirements"
        )
        
        processing_failed_state = sfn.Fail(
            self, "ProcessingFailed",
            comment="File processing failed",
            cause="Error occurred during file processing"
        )
        
        # Define validation check
        validation_check = sfn.Choice(
            self, "CheckValidation",
            comment="Check if file validation passed"
        )
        
        validation_check.when(
            sfn.Condition.boolean_equals("$.isValid", True),
            process_task.next(route_task).next(success_state)
        ).otherwise(validation_failed_state)
        
        # Define the workflow
        definition = validate_task.next(validation_check)
        
        # Create state machine
        state_machine = sfn.StateMachine(
            self, "FileProcessingWorkflow",
            state_machine_name=f"{project_name}-workflow",
            definition=definition,
            timeout=Duration.minutes(15),
            logs=sfn.LogOptions(
                destination=logs.LogGroup(
                    self, "WorkflowLogGroup",
                    log_group_name=f"/aws/stepfunctions/{project_name}-workflow",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY
                ),
                level=sfn.LogLevel.ALL
            )
        )
        
        cdk.Tags.of(state_machine).add("Project", project_name)
        cdk.Tags.of(state_machine).add("Component", "workflow-orchestration")
        
        return state_machine

    def _create_transfer_family_server(self, project_name: str) -> transfer.CfnServer:
        """
        Create AWS Transfer Family SFTP server.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            Transfer Family server
        """
        # Create IAM role for Transfer Family
        transfer_role = iam.Role(
            self, "TransferFamilyRole",
            role_name=f"{project_name}-transfer-role",
            assumed_by=iam.ServicePrincipal("transfer.amazonaws.com"),
            inline_policies={
                "S3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                                "s3:DeleteObject",
                                "s3:DeleteObjectVersion"
                            ],
                            resources=[f"{self.landing_bucket.bucket_arn}/*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:ListBucket",
                                "s3:GetBucketLocation"
                            ],
                            resources=[self.landing_bucket.bucket_arn]
                        )
                    ]
                )
            }
        )
        
        # Create Transfer Family server
        server = transfer.CfnServer(
            self, "TransferServer",
            identity_provider_type="SERVICE_MANAGED",
            protocols=["SFTP"],
            endpoint_type="PUBLIC",
            logging_role=transfer_role.role_arn,
            tags=[
                cdk.CfnTag(key="Project", value=project_name),
                cdk.CfnTag(key="Component", value="sftp-server")
            ]
        )
        
        # Create SFTP user
        transfer.CfnUser(
            self, "TransferUser",
            server_id=server.attr_server_id,
            user_name="businesspartner",
            role=transfer_role.role_arn,
            home_directory=f"/{self.landing_bucket.bucket_name}",
            home_directory_type="PATH",
            tags=[
                cdk.CfnTag(key="UserType", value="BusinessPartner"),
                cdk.CfnTag(key="Project", value=project_name)
            ]
        )
        
        return server

    def _create_eventbridge_integration(self) -> None:
        """Create EventBridge rule to trigger Step Functions on S3 events."""
        # Create EventBridge rule for S3 object creation
        rule = events.Rule(
            self, "FileProcessingRule",
            rule_name=f"{self.stack_name}-file-processing",
            description="Trigger file processing workflow on S3 object creation",
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["Object Created"],
                detail={
                    "bucket": {
                        "name": [self.landing_bucket.bucket_name]
                    }
                }
            )
        )
        
        # Add Step Functions as target
        rule.add_target(
            events_targets.SfnStateMachine(
                self.state_machine,
                input=events.RuleTargetInput.from_event_path("$.detail")
            )
        )

    def _create_monitoring_and_alerts(self, project_name: str) -> sns.Topic:
        """
        Create monitoring and alerting infrastructure.
        
        Args:
            project_name: The project name for resource naming
            
        Returns:
            SNS topic for alerts
        """
        # Create SNS topic for alerts
        topic = sns.Topic(
            self, "AlertsTopic",
            topic_name=f"{project_name}-alerts",
            display_name="File Processing Alerts"
        )
        
        # Create CloudWatch alarm for failed Step Functions executions
        cloudwatch.Alarm(
            self, "FailedExecutionsAlarm",
            alarm_name=f"{project_name}-failed-executions",
            alarm_description="Alert on Step Functions execution failures",
            metric=self.state_machine.metric_failed(),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
        ).add_alarm_action(
            cloudwatch.SnsAction(topic)
        )
        
        # Create alarm for Lambda function errors
        for function in [self.validator_function, self.processor_function, self.router_function]:
            cloudwatch.Alarm(
                self, f"{function.function_name}ErrorsAlarm",
                alarm_name=f"{function.function_name}-errors",
                alarm_description=f"Alert on {function.function_name} errors",
                metric=function.metric_errors(),
                threshold=1,
                evaluation_periods=2,
                comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD
            ).add_alarm_action(
                cloudwatch.SnsAction(topic)
            )
        
        cdk.Tags.of(topic).add("Project", project_name)
        cdk.Tags.of(topic).add("Component", "monitoring")
        
        return topic

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "LandingBucketName",
            value=self.landing_bucket.bucket_name,
            description="Name of the S3 bucket for landing incoming files",
            export_name=f"{self.stack_name}-LandingBucket"
        )
        
        CfnOutput(
            self, "ProcessedBucketName",
            value=self.processed_bucket.bucket_name,
            description="Name of the S3 bucket for processed files",
            export_name=f"{self.stack_name}-ProcessedBucket"
        )
        
        CfnOutput(
            self, "ArchiveBucketName",
            value=self.archive_bucket.bucket_name,
            description="Name of the S3 bucket for archived files",
            export_name=f"{self.stack_name}-ArchiveBucket"
        )
        
        CfnOutput(
            self, "StateMachineArn",
            value=self.state_machine.state_machine_arn,
            description="ARN of the Step Functions state machine",
            export_name=f"{self.stack_name}-StateMachine"
        )
        
        CfnOutput(
            self, "TransferServerEndpoint",
            value=f"{self.transfer_server.attr_server_id}.server.transfer.{self.region}.amazonaws.com",
            description="SFTP endpoint for file uploads",
            export_name=f"{self.stack_name}-SFTPEndpoint"
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for alerts",
            export_name=f"{self.stack_name}-AlertsTopic"
        )


app = cdk.App()

# Create the main file processing stack
FileProcessingStack(
    app, "FileProcessingStack",
    description="Automated business file processing with AWS Transfer Family and Step Functions",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()