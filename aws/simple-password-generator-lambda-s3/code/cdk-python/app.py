#!/usr/bin/env python3
"""
AWS CDK Python application for Simple Password Generator with Lambda and S3

This CDK application deploys:
- S3 bucket with encryption and versioning for secure password storage
- Lambda function for password generation using Python's secrets module
- IAM role with least privilege permissions
- CloudWatch log group for Lambda function logs

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct


class PasswordGeneratorStack(Stack):
    """
    AWS CDK Stack for Simple Password Generator with Lambda and S3
    
    This stack creates a serverless password generator that uses:
    - AWS Lambda for secure password generation
    - Amazon S3 for encrypted storage with versioning
    - IAM roles with least privilege access
    - CloudWatch Logs for monitoring and debugging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters for customization
        self.stack_name_lower = construct_id.lower().replace('_', '-')
        
        # Create S3 bucket for password storage
        self.password_bucket = self._create_password_bucket()
        
        # Create Lambda execution role
        self.lambda_role = self._create_lambda_role()
        
        # Create Lambda function
        self.lambda_function = self._create_lambda_function()
        
        # Create CloudWatch log group
        self.log_group = self._create_log_group()
        
        # Create stack outputs
        self._create_outputs()

    def _create_password_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for secure password storage with encryption and versioning.
        
        Returns:
            s3.Bucket: The created S3 bucket with security configurations
        """
        bucket = s3.Bucket(
            self,
            "PasswordBucket",
            bucket_name=f"password-generator-{self.stack_name_lower}-{self.account}",
            # Enable encryption at rest using S3 managed keys
            encryption=s3.BucketEncryption.S3_MANAGED,
            # Enable versioning for password history
            versioned=True,
            # Block all public access for security
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Set lifecycle policy for cost optimization (optional)
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="PasswordCleanup",
                    enabled=True,
                    # Transition to IA after 30 days
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
                    # Delete non-current versions after 30 days
                    noncurrent_version_expiration=Duration.days(30)
                )
            ],
            # Enable server access logging (optional)
            server_access_logs_prefix="access-logs/",
            # Use DESTROY removal policy for development (change to RETAIN for production)
            removal_policy=RemovalPolicy.DESTROY,
            # Auto-delete objects when stack is destroyed (development only)
            auto_delete_objects=True
        )

        # Add tags for resource management
        cdk.Tags.of(bucket).add("Project", "PasswordGenerator")
        cdk.Tags.of(bucket).add("Environment", "Development")
        cdk.Tags.of(bucket).add("Purpose", "SecurePasswordStorage")

        return bucket

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege permissions.
        
        Returns:
            iam.Role: The IAM role with necessary permissions for Lambda execution
        """
        # Create the Lambda execution role
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"PasswordGenerator-Lambda-Role-{self.stack_name_lower}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Password Generator Lambda function with least privilege access",
            # Attach basic Lambda execution role for CloudWatch Logs
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add custom policy for S3 access to the specific bucket
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObjectAcl"
            ],
            resources=[
                self.password_bucket.bucket_arn,
                f"{self.password_bucket.bucket_arn}/*"
            ]
        )

        role.add_to_policy(s3_policy)

        # Add tags for resource management
        cdk.Tags.of(role).add("Project", "PasswordGenerator")
        cdk.Tags.of(role).add("Environment", "Development")

        return role

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for password generation.
        
        Returns:
            lambda_.Function: The Lambda function for password generation
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import secrets
import string
from datetime import datetime
import logging
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    """
    AWS Lambda handler for secure password generation.
    
    Args:
        event: Lambda event containing password parameters
        context: Lambda context object
        
    Returns:
        dict: Response with password generation status and metadata
    """
    try:
        # Parse request parameters
        body = json.loads(event.get('body', '{}')) if event.get('body') else event
        
        # Default password parameters
        length = body.get('length', 16)
        include_uppercase = body.get('include_uppercase', True)
        include_lowercase = body.get('include_lowercase', True)
        include_numbers = body.get('include_numbers', True)
        include_symbols = body.get('include_symbols', True)
        password_name = body.get('name', f'password_{datetime.now().strftime("%Y%m%d_%H%M%S")}')
        
        # Validate parameters
        if length < 8 or length > 128:
            raise ValueError("Password length must be between 8 and 128 characters")
        
        # Build character set
        charset = ""
        if include_lowercase:
            charset += string.ascii_lowercase
        if include_uppercase:
            charset += string.ascii_uppercase
        if include_numbers:
            charset += string.digits
        if include_symbols:
            charset += "!@#$%^&*()_+-=[]{}|;:,.<>?"
        
        if not charset:
            raise ValueError("At least one character type must be selected")
        
        # Generate secure password using cryptographically secure random
        password = ''.join(secrets.choice(charset) for _ in range(length))
        
        # Create password metadata
        password_data = {
            'password': password,
            'length': length,
            'created_at': datetime.now().isoformat(),
            'parameters': {
                'include_uppercase': include_uppercase,
                'include_lowercase': include_lowercase,
                'include_numbers': include_numbers,
                'include_symbols': include_symbols
            }
        }
        
        # Store password in S3 with server-side encryption
        s3_key = f'passwords/{password_name}.json'
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=s3_key,
            Body=json.dumps(password_data, indent=2),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        
        logger.info(f"Password generated and stored: {s3_key}")
        
        # Return response (without actual password for security)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Password generated successfully',
                'password_name': password_name,
                's3_key': s3_key,
                'length': length,
                'created_at': password_data['created_at']
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating password: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Failed to generate password',
                'message': str(e)
            })
        }
'''

        # Create Lambda function
        function = lambda_.Function(
            self,
            "PasswordGeneratorFunction",
            function_name=f"password-generator-{self.stack_name_lower}",
            runtime=lambda_.Runtime.PYTHON_3_12,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=128,
            description="Secure password generator with S3 storage - CDK deployed",
            environment={
                "BUCKET_NAME": self.password_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            # Enable tracing for debugging
            tracing=lambda_.Tracing.ACTIVE,
            # Set retry configuration
            retry_attempts=0,
            # Enable insights for monitoring
            insights_version=lambda_.LambdaInsightsVersion.VERSION_1_0_229_0
        )

        # Add tags for resource management
        cdk.Tags.of(function).add("Project", "PasswordGenerator")
        cdk.Tags.of(function).add("Environment", "Development")

        return function

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for Lambda function.
        
        Returns:
            logs.LogGroup: The CloudWatch log group for Lambda logs
        """
        log_group = logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/{self.lambda_function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,  # Adjust retention as needed
            removal_policy=RemovalPolicy.DESTROY
        )

        # Add tags for resource management
        cdk.Tags.of(log_group).add("Project", "PasswordGenerator")
        cdk.Tags.of(log_group).add("Environment", "Development")

        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "S3BucketName",
            value=self.password_bucket.bucket_name,
            description="Name of the S3 bucket for password storage",
            export_name=f"{self.stack_name}-S3-Bucket-Name"
        )

        CfnOutput(
            self,
            "S3BucketArn",
            value=self.password_bucket.bucket_arn,
            description="ARN of the S3 bucket for password storage",
            export_name=f"{self.stack_name}-S3-Bucket-Arn"
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for password generation",
            export_name=f"{self.stack_name}-Lambda-Function-Name"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function for password generation",
            export_name=f"{self.stack_name}-Lambda-Function-Arn"
        )

        CfnOutput(
            self,
            "IAMRoleName",
            value=self.lambda_role.role_name,
            description="Name of the IAM role for Lambda execution",
            export_name=f"{self.stack_name}-IAM-Role-Name"
        )

        CfnOutput(
            self,
            "IAMRoleArn",
            value=self.lambda_role.role_arn,
            description="ARN of the IAM role for Lambda execution",
            export_name=f"{self.stack_name}-IAM-Role-Arn"
        )


class PasswordGeneratorApp(cdk.App):
    """
    CDK Application for Password Generator infrastructure.
    """

    def __init__(self) -> None:
        super().__init__()

        # Environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )

        # Create the stack
        PasswordGeneratorStack(
            self,
            "PasswordGeneratorStack",
            env=env,
            description="Simple Password Generator with Lambda and S3 - CDK Python",
            # Add stack tags
            tags={
                "Project": "PasswordGenerator",
                "Environment": "Development",
                "ManagedBy": "CDK",
                "CostCenter": "Engineering"
            }
        )


# Application entry point
if __name__ == "__main__":
    app = PasswordGeneratorApp()
    app.synth()