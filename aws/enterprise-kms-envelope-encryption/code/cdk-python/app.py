#!/usr/bin/env python3
"""
Enterprise KMS Envelope Encryption with Automated Key Rotation
AWS CDK Python Application

This CDK application implements enterprise-grade envelope encryption using AWS KMS
with automated key rotation monitoring and S3 integration.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_kms as kms,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class EnterpriseKmsEncryptionStack(Stack):
    """
    CDK Stack Enterprise KMS Envelope Encryption.
    
    This stack creates:
    - Customer Master Key (CMK) with automatic rotation enabled
    - S3 bucket with KMS encryption
    - Lambda function for key rotation monitoring
    - CloudWatch Events rule for automated monitoring
    - IAM roles and policies with least privilege access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.addr[:8].lower()

        # Create Customer Master Key with automatic rotation
        self.cmk = kms.Key(
            self,
            "EnterpriseCMK",
            description="Enterprise envelope encryption master key",
            enable_key_rotation=True,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            alias=f"enterprise-encryption-{unique_suffix}",
        )

        # Create S3 bucket with KMS encryption
        self.encrypted_bucket = s3.Bucket(
            self,
            "EncryptedDataBucket",
            bucket_name=f"enterprise-encrypted-data-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.KMS,
            encryption_key=self.cmk,
            bucket_key_enabled=True,  # Optimize KMS costs
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            auto_delete_objects=True,  # Only for demo purposes
        )

        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "KeyRotationMonitorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add custom KMS permissions to Lambda role
        kms_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "kms:DescribeKey",
                "kms:GetKeyRotationStatus",
                "kms:EnableKeyRotation",
                "kms:ListKeys",
                "kms:ListAliases",
            ],
            resources=["*"],  # KMS operations require wildcard for list operations
        )

        lambda_role.add_to_policy(kms_policy)

        # Create Lambda function for key rotation monitoring
        self.rotation_monitor = lambda_.Function(
            self,
            "KeyRotationMonitor",
            function_name=f"kms-key-rotator-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            memory_size=128,
            description="Monitors and manages KMS key rotation for enterprise encryption",
            environment={
                "CMK_ALIAS": f"alias/enterprise-encryption-{unique_suffix}",
                "LOG_LEVEL": "INFO",
            },
        )

        # Create CloudWatch log group with retention policy
        log_group = logs.LogGroup(
            self,
            "KeyRotationMonitorLogs",
            log_group_name=f"/aws/lambda/{self.rotation_monitor.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudWatch Events rule for weekly monitoring
        schedule_rule = events.Rule(
            self,
            "KeyRotationSchedule",
            description="Weekly KMS key rotation monitoring",
            schedule=events.Schedule.rate(Duration.days(7)),
        )

        # Add Lambda function as target for the schedule
        schedule_rule.add_target(targets.LambdaFunction(self.rotation_monitor))

        # Add outputs for important resource information
        cdk.CfnOutput(
            self,
            "CMKKeyId",
            value=self.cmk.key_id,
            description="Customer Master Key ID for envelope encryption",
        )

        cdk.CfnOutput(
            self,
            "CMKAlias",
            value=f"alias/enterprise-encryption-{unique_suffix}",
            description="Customer Master Key alias for easy reference",
        )

        cdk.CfnOutput(
            self,
            "EncryptedBucketName",
            value=self.encrypted_bucket.bucket_name,
            description="S3 bucket with KMS encryption enabled",
        )

        cdk.CfnOutput(
            self,
            "RotationMonitorFunction",
            value=self.rotation_monitor.function_name,
            description="Lambda function for key rotation monitoring",
        )

        cdk.CfnOutput(
            self,
            "ScheduleRuleName",
            value=schedule_rule.rule_name,
            description="CloudWatch Events rule for automated monitoring",
        )

    def _get_lambda_code(self) -> str:
        """
        Returns the Lambda function code for key rotation monitoring.
        
        Returns:
            str: Python code for the Lambda function
        """
        return '''
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for monitoring KMS key rotation status.
    
    This function:
    1. Lists all customer-managed KMS keys
    2. Checks rotation status for each key
    3. Enables rotation for keys that don't have it enabled
    4. Logs comprehensive audit information
    
    Args:
        event: Lambda event data
        context: Lambda runtime context
        
    Returns:
        Dictionary with execution results and metrics
    """
    kms_client = boto3.client('kms')
    
    try:
        # Initialize metrics
        keys_checked = 0
        rotation_enabled_count = 0
        rotation_disabled_count = 0
        errors = []
        
        # List all customer-managed keys
        paginator = kms_client.get_paginator('list_keys')
        
        logger.info("Starting KMS key rotation monitoring")
        
        for page in paginator.paginate():
            for key in page['Keys']:
                key_id = key['KeyId']
                
                try:
                    # Get key details
                    key_details = kms_client.describe_key(KeyId=key_id)
                    key_metadata = key_details['KeyMetadata']
                    
                    # Skip AWS-managed keys
                    if key_metadata['KeyManager'] == 'AWS':
                        continue
                    
                    # Skip keys that are not in enabled state
                    if key_metadata['KeyState'] != 'Enabled':
                        logger.info(f"Skipping key {key_id} with state: {key_metadata['KeyState']}")
                        continue
                    
                    keys_checked += 1
                    
                    # Check rotation status
                    rotation_status = kms_client.get_key_rotation_status(KeyId=key_id)
                    rotation_enabled = rotation_status['KeyRotationEnabled']
                    
                    if rotation_enabled:
                        rotation_enabled_count += 1
                        logger.info(f"Key {key_id}: Rotation enabled ✓")
                    else:
                        rotation_disabled_count += 1
                        logger.warning(f"Key {key_id}: Rotation disabled - enabling now")
                        
                        # Enable rotation for keys that don't have it
                        try:
                            kms_client.enable_key_rotation(KeyId=key_id)
                            logger.info(f"Successfully enabled rotation for key {key_id}")
                            rotation_enabled_count += 1
                            rotation_disabled_count -= 1
                        except Exception as e:
                            error_msg = f"Failed to enable rotation for key {key_id}: {str(e)}"
                            logger.error(error_msg)
                            errors.append(error_msg)
                    
                    # Log key information for audit trail
                    logger.info(f"Key audit: ID={key_id[:8]}..., "
                              f"State={key_metadata['KeyState']}, "
                              f"Rotation={'Enabled' if rotation_enabled else 'Disabled'}, "
                              f"Created={key_metadata['CreationDate'].isoformat()}")
                              
                except Exception as e:
                    error_msg = f"Error processing key {key_id}: {str(e)}"
                    logger.error(error_msg)
                    errors.append(error_msg)
        
        # Prepare response
        result = {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Key rotation monitoring completed successfully',
                'metrics': {
                    'keysChecked': keys_checked,
                    'rotationEnabled': rotation_enabled_count,
                    'rotationDisabled': rotation_disabled_count,
                    'errors': len(errors)
                },
                'timestamp': datetime.now().isoformat(),
                'errors': errors if errors else None
            })
        }
        
        logger.info(f"Monitoring completed: {keys_checked} keys checked, "
                   f"{rotation_enabled_count} with rotation enabled, "
                   f"{len(errors)} errors")
        
        return result
        
    except Exception as e:
        error_msg = f"Fatal error in key rotation monitoring: {str(e)}"
        logger.error(error_msg)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': error_msg,
                'timestamp': datetime.now().isoformat()
            })
        }
'''


app = cdk.App()

# Create the main stack
EnterpriseKmsEncryptionStack(
    app,
    "EnterpriseKmsEncryptionStack",
    description="Enterprise KMS envelope encryption with automated key rotation",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region"),
    ),
)

app.synth()