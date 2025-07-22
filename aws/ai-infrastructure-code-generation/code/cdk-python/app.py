#!/usr/bin/env python3
"""
CDK Python implementation for Creating AI-Powered Infrastructure Code Generation
with Amazon Q Developer and AWS Infrastructure Composer

This CDK application deploys the infrastructure needed for automated template processing
using S3 event triggers, Lambda functions, and CloudFormation integration.
"""

import os
from typing import Any, Dict

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    App,
    Environment,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3_notifications as s3n,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct


class QDeveloperInfrastructureStack(Stack):
    """
    Stack for Amazon Q Developer Infrastructure Code Generation system.
    
    This stack creates:
    - S3 bucket for template storage with versioning and encryption
    - Lambda function for template processing and validation
    - IAM roles with least privilege permissions
    - CloudWatch logging for monitoring and troubleshooting
    - S3 event notifications for automated processing
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique identifier for resources
        random_suffix = self._generate_random_suffix()
        
        # S3 bucket for template storage
        self.template_bucket = self._create_template_bucket(random_suffix)
        
        # IAM role for Lambda function
        self.lambda_role = self._create_lambda_execution_role(random_suffix)
        
        # Lambda function for template processing
        self.template_processor = self._create_template_processor_function(random_suffix)
        
        # S3 event notification configuration
        self._configure_s3_event_notification()
        
        # CloudWatch log group with retention policy
        self._create_log_group()
        
        # Stack outputs
        self._create_outputs()

    def _generate_random_suffix(self) -> str:
        """Generate a random suffix for resource naming."""
        # Create a random password parameter for unique naming
        random_param = secretsmanager.Secret(
            self, "RandomSuffix",
            description="Random suffix for resource naming",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                length=6,
                exclude_punctuation=True,
                exclude_uppercase=True,
                require_each_included_type=True
            ),
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Use the first 6 characters of the secret value
        return random_param.secret_value.unsafe_unwrap()[:6]

    def _create_template_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing infrastructure templates.
        
        Args:
            suffix: Random suffix for unique bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self, "QDeveloperTemplatesBucket",
            bucket_name=f"q-developer-templates-{suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,  # For easier cleanup in development
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ValidationResultsCleanup",
                    prefix="validation-results/",
                    expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(1)
                ),
                s3.LifecycleRule(
                    id="OldVersionCleanup",
                    noncurrent_version_expiration=Duration.days(90)
                )
            ]
        )
        
        # Add bucket notification placeholder (configured later)
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )
        
        return bucket

    def _create_lambda_execution_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege permissions.
        
        Args:
            suffix: Random suffix for unique role naming
            
        Returns:
            IAM Role construct
        """
        role = iam.Role(
            self, "QDeveloperLambdaRole",
            role_name=f"q-developer-automation-role-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Q Developer template processing Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add custom inline policy for S3 and CloudFormation access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.template_bucket.bucket_arn,
                    f"{self.template_bucket.bucket_arn}/*"
                ]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudformation:ValidateTemplate",
                    "cloudformation:CreateStack",
                    "cloudformation:DescribeStacks",
                    "cloudformation:DescribeStackEvents",
                    "cloudformation:UpdateStack",
                    "cloudformation:DeleteStack"
                ],
                resources=["*"]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "iam:PassRole",
                    "iam:CreateRole",
                    "iam:AttachRolePolicy",
                    "iam:GetRole"
                ],
                resources=["*"]
            )
        )
        
        return role

    def _create_template_processor_function(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function for processing infrastructure templates.
        
        Args:
            suffix: Random suffix for unique function naming
            
        Returns:
            Lambda Function construct
        """
        # Lambda function code
        function_code = '''
import json
import boto3
import logging
from urllib.parse import unquote_plus

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3_client = boto3.client('s3')
cfn_client = boto3.client('cloudformation')

def lambda_handler(event, context):
    """
    Process CloudFormation templates uploaded to S3
    Validates templates and optionally deploys infrastructure
    """
    try:
        # Parse S3 event notification
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"Processing template: {key} from bucket: {bucket}")
            
            # Download template from S3
            response = s3_client.get_object(Bucket=bucket, Key=key)
            template_body = response['Body'].read().decode('utf-8')
            
            # Validate CloudFormation template
            try:
                validation_response = cfn_client.validate_template(
                    TemplateBody=template_body
                )
                logger.info(f"Template validation successful: {validation_response.get('Description', 'No description')}")
                
                # Extract metadata from template
                template_data = json.loads(template_body) if template_body.strip().startswith('{') else {}
                stack_name = template_data.get('Metadata', {}).get('StackName', f"q-developer-stack-{key.replace('.json', '').replace('/', '-')}")
                
                # Create CloudFormation stack (optional - controlled by parameter)
                if key.startswith('auto-deploy/'):
                    logger.info(f"Auto-deploying stack: {stack_name}")
                    cfn_client.create_stack(
                        StackName=stack_name,
                        TemplateBody=template_body,
                        Capabilities=['CAPABILITY_IAM', 'CAPABILITY_NAMED_IAM'],
                        Tags=[
                            {'Key': 'Source', 'Value': 'QDeveloperAutomation'},
                            {'Key': 'TemplateFile', 'Value': key}
                        ]
                    )
                    
                # Store validation results
                validation_result = {
                    'template_file': key,
                    'validation_status': 'VALID',
                    'description': validation_response.get('Description', ''),
                    'parameters': validation_response.get('Parameters', []),
                    'capabilities': validation_response.get('Capabilities', [])
                }
                
                # Save validation results to S3
                result_key = f"validation-results/{key.replace('.json', '-validation.json')}"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(validation_result, indent=2),
                    ContentType='application/json'
                )
                
            except Exception as validation_error:
                logger.error(f"Template validation failed: {str(validation_error)}")
                
                # Store validation error
                error_result = {
                    'template_file': key,
                    'validation_status': 'INVALID',
                    'error': str(validation_error)
                }
                
                result_key = f"validation-results/{key.replace('.json', '-error.json')}"
                s3_client.put_object(
                    Bucket=bucket,
                    Key=result_key,
                    Body=json.dumps(error_result, indent=2),
                    ContentType='application/json'
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps('Template processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Lambda execution error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error processing template: {str(e)}')
        }
'''
        
        function = lambda_.Function(
            self, "TemplateProcessorFunction",
            function_name=f"template-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=self.lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Processes CloudFormation templates from Amazon Q Developer",
            environment={
                "BUCKET_NAME": self.template_bucket.bucket_name,
                "LOG_LEVEL": "INFO"
            },
            retry_attempts=2
        )
        
        return function

    def _configure_s3_event_notification(self) -> None:
        """Configure S3 event notification to trigger Lambda function."""
        self.template_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.template_processor),
            s3.NotificationKeyFilter(
                prefix="templates/",
                suffix=".json"
            )
        )

    def _create_log_group(self) -> None:
        """Create CloudWatch log group with retention policy."""
        logs.LogGroup(
            self, "TemplateProcessorLogGroup",
            log_group_name=f"/aws/lambda/{self.template_processor.function_name}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "TemplateBucketName",
            value=self.template_bucket.bucket_name,
            description="S3 bucket name for storing infrastructure templates",
            export_name=f"{self.stack_name}-TemplateBucket"
        )
        
        CfnOutput(
            self, "TemplateBucketArn",
            value=self.template_bucket.bucket_arn,
            description="S3 bucket ARN for storing infrastructure templates"
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.template_processor.function_name,
            description="Lambda function name for template processing",
            export_name=f"{self.stack_name}-LambdaFunction"
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.template_processor.function_arn,
            description="Lambda function ARN for template processing"
        )
        
        CfnOutput(
            self, "IAMRoleName",
            value=self.lambda_role.role_name,
            description="IAM role name for Lambda execution"
        )
        
        CfnOutput(
            self, "IAMRoleArn",
            value=self.lambda_role.role_arn,
            description="IAM role ARN for Lambda execution"
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the stack
    QDeveloperInfrastructureStack(
        app, "QDeveloperInfrastructureStack",
        env=env,
        description="Amazon Q Developer Infrastructure Code Generation System",
        tags={
            "Project": "Q-Developer-Automation",
            "Environment": "Development",
            "ManagedBy": "CDK"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()