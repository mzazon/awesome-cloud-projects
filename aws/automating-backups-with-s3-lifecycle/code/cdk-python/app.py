#!/usr/bin/env python3
"""
Scheduled Backups with Amazon S3 - CDK Python Application

This AWS CDK application creates automated, scheduled backups using Amazon S3,
EventBridge, and Lambda. It demonstrates a complete backup solution with
primary and backup S3 buckets, lifecycle policies, and scheduled execution.

Author: AWS CDK Python Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct
import os
from typing import Dict, Any


class ScheduledBackupsStack(Stack):
    """
    CDK Stack for Scheduled Backups with Amazon S3
    
    This stack creates:
    - Primary S3 bucket for working data
    - Backup S3 bucket with versioning and lifecycle policies
    - Lambda function for backup operations
    - EventBridge rule for scheduled execution
    - Required IAM roles and policies
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create primary S3 bucket
        self.primary_bucket = self._create_primary_bucket(unique_suffix)
        
        # Create backup S3 bucket with versioning and lifecycle policies
        self.backup_bucket = self._create_backup_bucket(unique_suffix)
        
        # Create Lambda execution role
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda function for backup operations
        self.backup_function = self._create_backup_function(unique_suffix)
        
        # Create EventBridge rule for scheduled execution
        self.schedule_rule = self._create_schedule_rule(unique_suffix)
        
        # Create CloudWatch log group for Lambda function
        self.log_group = self._create_log_group(unique_suffix)
        
        # Create outputs for important resource identifiers
        self._create_outputs()

    def _create_primary_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create the primary S3 bucket for working data
        
        Args:
            suffix: Unique suffix for bucket naming
            
        Returns:
            s3.Bucket: The created primary bucket
        """
        return s3.Bucket(
            self,
            "PrimaryBucket",
            bucket_name=f"primary-data-{suffix}",
            versioning=s3.BucketVersioning.DISABLED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
        )

    def _create_backup_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create the backup S3 bucket with versioning and lifecycle policies
        
        Args:
            suffix: Unique suffix for bucket naming
            
        Returns:
            s3.Bucket: The created backup bucket
        """
        backup_bucket = s3.Bucket(
            self,
            "BackupBucket",
            bucket_name=f"backup-data-{suffix}",
            versioning=s3.BucketVersioning.ENABLED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
        )
        
        # Add lifecycle rules for cost optimization
        backup_bucket.add_lifecycle_rule(
            id="BackupRetentionRule",
            enabled=True,
            transitions=[
                s3.Transition(
                    storage_class=s3.StorageClass.STANDARD_IA,
                    transition_after=Duration.days(30)
                ),
                s3.Transition(
                    storage_class=s3.StorageClass.GLACIER,
                    transition_after=Duration.days(90)
                ),
            ],
            expiration=Duration.days(365),
        )
        
        return backup_bucket

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with required permissions
        
        Returns:
            iam.Role: The created Lambda execution role
        """
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add S3 permissions for the Lambda function
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.primary_bucket.bucket_arn,
                    f"{self.primary_bucket.bucket_arn}/*",
                ],
            )
        )
        
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:PutObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.backup_bucket.bucket_arn,
                    f"{self.backup_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return lambda_role

    def _create_backup_function(self, suffix: str) -> _lambda.Function:
        """
        Create Lambda function for backup operations
        
        Args:
            suffix: Unique suffix for function naming
            
        Returns:
            _lambda.Function: The created Lambda function
        """
        return _lambda.Function(
            self,
            "BackupFunction",
            function_name=f"s3-backup-function-{suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            timeout=Duration.minutes(1),
            memory_size=128,
            role=self.lambda_role,
            environment={
                "SOURCE_BUCKET": self.primary_bucket.bucket_name,
                "DESTINATION_BUCKET": self.backup_bucket.bucket_name,
            },
            code=_lambda.Code.from_inline(self._get_lambda_code()),
        )

    def _create_schedule_rule(self, suffix: str) -> events.Rule:
        """
        Create EventBridge rule for scheduled execution
        
        Args:
            suffix: Unique suffix for rule naming
            
        Returns:
            events.Rule: The created EventBridge rule
        """
        rule = events.Rule(
            self,
            "DailyBackupRule",
            rule_name=f"DailyS3BackupRule-{suffix}",
            description="Trigger S3 backup function daily at 1:00 AM UTC",
            schedule=events.Schedule.cron(
                minute="0",
                hour="1",
                day="*",
                month="*",
                year="*",
            ),
        )
        
        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.backup_function))
        
        return rule

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch log group for Lambda function
        
        Args:
            suffix: Unique suffix for log group naming
            
        Returns:
            logs.LogGroup: The created log group
        """
        return logs.LogGroup(
            self,
            "BackupFunctionLogGroup",
            log_group_name=f"/aws/lambda/s3-backup-function-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers"""
        
        CfnOutput(
            self,
            "PrimaryBucketName",
            value=self.primary_bucket.bucket_name,
            description="Name of the primary S3 bucket",
        )
        
        CfnOutput(
            self,
            "BackupBucketName",
            value=self.backup_bucket.bucket_name,
            description="Name of the backup S3 bucket",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.backup_function.function_name,
            description="Name of the Lambda backup function",
        )
        
        CfnOutput(
            self,
            "EventRuleName",
            value=self.schedule_rule.rule_name,
            description="Name of the EventBridge schedule rule",
        )
        
        CfnOutput(
            self,
            "PrimaryBucketArn",
            value=self.primary_bucket.bucket_arn,
            description="ARN of the primary S3 bucket",
        )
        
        CfnOutput(
            self,
            "BackupBucketArn",
            value=self.backup_bucket.bucket_arn,
            description="ARN of the backup S3 bucket",
        )

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for backup operations
        
        Returns:
            str: The Lambda function code
        """
        return '''
import boto3
import os
import time
import json
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for S3 backup operations
    
    Args:
        event: Lambda event data
        context: Lambda context object
        
    Returns:
        Dict[str, Any]: Response with status and message
    """
    # Get bucket names from environment variables
    source_bucket = os.environ['SOURCE_BUCKET']
    destination_bucket = os.environ['DESTINATION_BUCKET']
    
    # Initialize S3 client
    s3 = boto3.client('s3')
    
    # Get current timestamp for logging
    timestamp = time.strftime("%Y-%m-%d-%H-%M-%S")
    print(f"Starting backup process at {timestamp}")
    
    try:
        # List objects in source bucket
        objects = []
        paginator = s3.get_paginator('list_objects_v2')
        for page in paginator.paginate(Bucket=source_bucket):
            if 'Contents' in page:
                objects.extend(page['Contents'])
        
        # Copy each object to the destination bucket
        copied_count = 0
        for obj in objects:
            key = obj['Key']
            copy_source = {'Bucket': source_bucket, 'Key': key}
            
            print(f"Copying {key} to backup bucket")
            s3.copy_object(
                CopySource=copy_source,
                Bucket=destination_bucket,
                Key=key
            )
            copied_count += 1
        
        print(f"Backup completed successfully. Copied {copied_count} objects.")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully backed up {copied_count} objects',
                'timestamp': timestamp,
                'source_bucket': source_bucket,
                'destination_bucket': destination_bucket
            })
        }
        
    except Exception as e:
        print(f"Error during backup process: {str(e)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': timestamp,
                'source_bucket': source_bucket,
                'destination_bucket': destination_bucket
            })
        }
'''


class ScheduledBackupsApp(cdk.App):
    """Main CDK application for Scheduled Backups"""
    
    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        
        # Create the main stack
        ScheduledBackupsStack(
            self,
            "ScheduledBackupsStack",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
            description="Scheduled Backups with Amazon S3 - CDK Python Stack",
        )


# Create and synthesize the CDK app
app = ScheduledBackupsApp()
app.synth()