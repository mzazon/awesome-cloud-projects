#!/usr/bin/env python3
"""
CDK Python Application for Custom CloudFormation Resources with Lambda-Backed Custom Resources

This application creates a complete solution for extending CloudFormation capabilities using
Lambda-backed custom resources. It demonstrates how to implement CREATE, UPDATE, and DELETE
operations for custom resource types while maintaining CloudFormation's declarative model.

Key Components:
- Lambda function with custom resource handling logic
- IAM role with least privilege permissions
- S3 bucket for custom resource data storage
- CloudWatch logs for monitoring and troubleshooting
- Custom resource demonstrating the complete lifecycle

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    CfnParameter,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lambda as lambda_
from aws_cdk import aws_logs as logs
from aws_cdk import aws_s3 as s3
from constructs import Construct


class CustomResourceDemoStack(Stack):
    """
    Stack that demonstrates Lambda-backed custom resources in CloudFormation.
    
    This stack creates:
    1. S3 bucket for custom resource data storage
    2. IAM role for Lambda execution with minimal required permissions
    3. Lambda function implementing custom resource logic
    4. CloudWatch log group for monitoring
    5. Custom resource demonstrating complete lifecycle management
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self._create_parameters()
        
        # Core infrastructure
        self._create_s3_bucket()
        self._create_iam_role()
        self._create_lambda_function()
        self._create_log_group()
        
        # Custom resource demonstration
        self._create_custom_resource()
        
        # Outputs for integration and verification
        self._create_outputs()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_parameters(self) -> None:
        """Create CloudFormation parameters for stack customization."""
        self.environment_param = CfnParameter(
            self,
            "Environment",
            type="String",
            default="development",
            allowed_values=["development", "staging", "production"],
            description="Environment name for resource naming and configuration",
        )

        self.data_retention_days_param = CfnParameter(
            self,
            "DataRetentionDays",
            type="Number",
            default=30,
            min_value=1,
            max_value=365,
            description="Number of days to retain custom resource data in S3",
        )

        self.log_retention_days_param = CfnParameter(
            self,
            "LogRetentionDays",
            type="Number",
            default=14,
            allowed_values=[1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1827, 3653],
            description="Number of days to retain CloudWatch logs",
        )

    def _create_s3_bucket(self) -> None:
        """
        Create S3 bucket for custom resource data storage.
        
        The bucket is configured with:
        - Server-side encryption using AES256
        - Public access blocked for security
        - Versioning enabled for data protection
        - Lifecycle policy for automatic cleanup
        """
        self.data_bucket = s3.Bucket(
            self,
            "CustomResourceDataBucket",
            bucket_name=f"custom-resource-data-{self.environment_param.value_as_string}-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(
                        self.data_retention_days_param.value_as_number
                    ),
                ),
                s3.LifecycleRule(
                    id="CleanupIncompleteUploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                ),
            ],
        )

    def _create_iam_role(self) -> None:
        """
        Create IAM role for Lambda function execution.
        
        The role follows the principle of least privilege, granting only:
        - Basic Lambda execution permissions (CloudWatch Logs)
        - Specific S3 permissions for the custom resource data bucket
        """
        # Custom policy for S3 access
        s3_policy_document = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                    ],
                    resources=[
                        self.data_bucket.bucket_arn,
                        f"{self.data_bucket.bucket_arn}/*",
                    ],
                ),
            ]
        )

        self.lambda_execution_role = iam.Role(
            self,
            "CustomResourceLambdaRole",
            role_name=f"CustomResourceLambdaRole-{self.environment_param.value_as_string}-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "CustomResourceS3Policy": s3_policy_document,
            },
            description="Execution role for custom resource Lambda function with S3 access",
        )

    def _create_lambda_function(self) -> None:
        """
        Create Lambda function for custom resource handling.
        
        The function implements:
        - CREATE: Creates new data objects in S3
        - UPDATE: Modifies existing data objects
        - DELETE: Removes data objects and cleans up resources
        - Comprehensive error handling and logging
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import cfnresponse
import logging
import traceback
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')


def lambda_handler(event: Dict[str, Any], context: Any) -> None:
    """
    Main handler for custom resource operations.
    
    Processes CloudFormation events for CREATE, UPDATE, and DELETE operations.
    Implements proper error handling and response mechanisms.
    """
    physical_resource_id = event.get('PhysicalResourceId', 'CustomResourceDemo')
    
    try:
        logger.info(f"Received event: {json.dumps(event, default=str)}")
        
        # Validate required properties
        resource_properties = event.get('ResourceProperties', {})
        if not validate_properties(resource_properties):
            raise ValueError("Invalid or missing required properties")
        
        # Extract event information
        request_type = event['RequestType']
        
        # Route to appropriate handler
        response_data = {}
        if request_type == 'Create':
            response_data = handle_create(resource_properties, physical_resource_id)
        elif request_type == 'Update':
            response_data = handle_update(resource_properties, physical_resource_id)
        elif request_type == 'Delete':
            response_data = handle_delete(resource_properties, physical_resource_id)
        else:
            raise ValueError(f"Unknown request type: {request_type}")
        
        # Add standard response metadata
        response_data.update({
            'PhysicalResourceId': physical_resource_id,
            'RequestId': event['RequestId'],
            'LogicalResourceId': event['LogicalResourceId'],
            'StackId': event['StackId'],
            'Timestamp': datetime.utcnow().isoformat()
        })
        
        logger.info(f"Operation completed successfully: {response_data}")
        cfnresponse.send(event, context, cfnresponse.SUCCESS, response_data, physical_resource_id)
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}")
        logger.error(f"Traceback: {traceback.format_exc()}")
        
        # Send failure response with error details
        error_data = {
            'Error': str(e),
            'RequestId': event.get('RequestId', 'unknown'),
            'LogicalResourceId': event.get('LogicalResourceId', 'unknown'),
            'StackId': event.get('StackId', 'unknown'),
            'Timestamp': datetime.utcnow().isoformat()
        }
        cfnresponse.send(event, context, cfnresponse.FAILED, error_data, physical_resource_id)


def validate_properties(properties: Dict[str, Any]) -> bool:
    """Validate required resource properties."""
    required_props = ['BucketName']
    return all(prop in properties for prop in required_props)


def handle_create(properties: Dict[str, Any], physical_resource_id: str) -> Dict[str, Any]:
    """
    Handle resource creation operations.
    
    Creates a new data object in S3 with metadata and configuration.
    """
    try:
        bucket_name = properties['BucketName']
        file_name = properties.get('FileName', 'custom-resource-data.json')
        data_content = parse_data_content(properties.get('DataContent', {}))
        environment = properties.get('Environment', 'unknown')
        
        # Validate bucket accessibility
        validate_bucket_access(bucket_name)
        
        # Create comprehensive data object
        data_object = {
            'metadata': {
                'created_at': datetime.utcnow().isoformat(),
                'resource_id': physical_resource_id,
                'operation': 'CREATE',
                'version': '1.0',
                'environment': environment
            },
            'configuration': data_content,
            'validation': {
                'bucket_accessible': True,
                'data_format': 'valid',
                'creation_successful': True
            }
        }
        
        # Upload to S3
        upload_to_s3(bucket_name, file_name, data_object, physical_resource_id, 'CREATE')
        
        logger.info(f"Successfully created resource {physical_resource_id} in {bucket_name}/{file_name}")
        
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
            'CreatedAt': data_object['metadata']['created_at'],
            'Status': 'SUCCESS',
            'Environment': environment
        }
        
    except Exception as e:
        logger.error(f"Error in handle_create: {str(e)}")
        raise


def handle_update(properties: Dict[str, Any], physical_resource_id: str) -> Dict[str, Any]:
    """
    Handle resource update operations.
    
    Updates existing data object while preserving creation metadata.
    """
    try:
        bucket_name = properties['BucketName']
        file_name = properties.get('FileName', 'custom-resource-data.json')
        data_content = parse_data_content(properties.get('DataContent', {}))
        environment = properties.get('Environment', 'unknown')
        
        # Get existing data if available
        existing_data = get_existing_data(bucket_name, file_name)
        
        # Update data object
        data_object = {
            'metadata': {
                'created_at': existing_data.get('metadata', {}).get('created_at', datetime.utcnow().isoformat()),
                'updated_at': datetime.utcnow().isoformat(),
                'resource_id': physical_resource_id,
                'operation': 'UPDATE',
                'version': '2.0',
                'environment': environment
            },
            'configuration': data_content,
            'validation': {
                'bucket_accessible': True,
                'data_format': 'valid',
                'update_successful': True
            },
            'history': existing_data.get('history', []) + [{
                'operation': 'UPDATE',
                'timestamp': datetime.utcnow().isoformat(),
                'changes': 'Configuration updated'
            }]
        }
        
        # Upload updated object
        upload_to_s3(bucket_name, file_name, data_object, physical_resource_id, 'UPDATE')
        
        logger.info(f"Successfully updated resource {physical_resource_id} in {bucket_name}/{file_name}")
        
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DataUrl': f"https://{bucket_name}.s3.amazonaws.com/{file_name}",
            'UpdatedAt': data_object['metadata']['updated_at'],
            'Status': 'SUCCESS',
            'Environment': environment
        }
        
    except Exception as e:
        logger.error(f"Error in handle_update: {str(e)}")
        raise


def handle_delete(properties: Dict[str, Any], physical_resource_id: str) -> Dict[str, Any]:
    """
    Handle resource deletion operations.
    
    Removes data object from S3 with verification.
    """
    try:
        bucket_name = properties['BucketName']
        file_name = properties.get('FileName', 'custom-resource-data.json')
        environment = properties.get('Environment', 'unknown')
        
        # Attempt to delete object
        try:
            s3.delete_object(Bucket=bucket_name, Key=file_name)
            logger.info(f"Deleted object {file_name} from bucket {bucket_name}")
            
            # Verify deletion
            verify_deletion(bucket_name, file_name)
            
        except s3.exceptions.NoSuchKey:
            logger.info(f"Object {file_name} does not exist, deletion not needed")
        except Exception as e:
            logger.warning(f"Error during deletion: {str(e)}")
            # Don't fail on cleanup errors during deletion
        
        logger.info(f"Successfully deleted resource {physical_resource_id}")
        
        return {
            'BucketName': bucket_name,
            'FileName': file_name,
            'DeletedAt': datetime.utcnow().isoformat(),
            'Status': 'SUCCESS',
            'Environment': environment
        }
        
    except Exception as e:
        logger.error(f"Error in handle_delete: {str(e)}")
        raise


def parse_data_content(data_content: Any) -> Dict[str, Any]:
    """Parse and validate data content from properties."""
    if isinstance(data_content, str):
        try:
            return json.loads(data_content)
        except json.JSONDecodeError as e:
            raise ValueError(f"Invalid JSON in DataContent: {str(e)}")
    elif isinstance(data_content, dict):
        return data_content
    else:
        return {'raw_data': str(data_content)}


def validate_bucket_access(bucket_name: str) -> None:
    """Validate that the S3 bucket exists and is accessible."""
    try:
        s3.head_bucket(Bucket=bucket_name)
    except Exception as e:
        raise ValueError(f"Cannot access bucket {bucket_name}: {str(e)}")


def get_existing_data(bucket_name: str, file_name: str) -> Dict[str, Any]:
    """Retrieve existing data object from S3."""
    try:
        response = s3.get_object(Bucket=bucket_name, Key=file_name)
        return json.loads(response['Body'].read())
    except s3.exceptions.NoSuchKey:
        logger.warning(f"Object {file_name} not found in bucket {bucket_name}")
        return {}
    except Exception as e:
        logger.warning(f"Could not retrieve existing data: {str(e)}")
        return {}


def upload_to_s3(bucket_name: str, file_name: str, data_object: Dict[str, Any], 
                 resource_id: str, operation: str) -> None:
    """Upload data object to S3 with metadata."""
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key=file_name,
            Body=json.dumps(data_object, indent=2),
            ContentType='application/json',
            Metadata={
                'resource-id': resource_id,
                'operation': operation,
                'created-by': 'custom-resource-handler'
            }
        )
    except Exception as e:
        raise RuntimeError(f"Failed to upload to S3: {str(e)}")


def verify_deletion(bucket_name: str, file_name: str) -> None:
    """Verify that object was successfully deleted."""
    try:
        s3.head_object(Bucket=bucket_name, Key=file_name)
        logger.warning(f"Object {file_name} still exists after deletion attempt")
    except s3.exceptions.NoSuchKey:
        logger.info(f"Confirmed: Object {file_name} successfully deleted")
'''

        self.custom_resource_function = lambda_.Function(
            self,
            "CustomResourceHandler",
            function_name=f"custom-resource-handler-{self.environment_param.value_as_string}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "ENVIRONMENT": self.environment_param.value_as_string,
                "LOG_LEVEL": "INFO",
                "AWS_REGION": self.region,
            },
            description="Lambda function for handling custom CloudFormation resources",
        )

    def _create_log_group(self) -> None:
        """Create CloudWatch log group for Lambda function monitoring."""
        self.log_group = logs.LogGroup(
            self,
            "CustomResourceLogGroup",
            log_group_name=f"/aws/lambda/{self.custom_resource_function.function_name}",
            retention=logs.RetentionDays(
                logs.RetentionDays(self.log_retention_days_param.value_as_number)
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_custom_resource(self) -> None:
        """
        Create custom resource to demonstrate the complete lifecycle.
        
        This custom resource uses the Lambda function to manage a data object in S3,
        demonstrating CREATE, UPDATE, and DELETE operations.
        """
        # Import the custom resource construct
        from aws_cdk.custom_resources import Provider
        
        # Create custom resource provider
        self.custom_resource_provider = Provider(
            self,
            "CustomResourceProvider",
            on_event_handler=self.custom_resource_function,
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )

        # Create the actual custom resource
        self.demo_custom_resource = cdk.CustomResource(
            self,
            "DemoCustomResource",
            service_token=self.custom_resource_provider.service_token,
            properties={
                "BucketName": self.data_bucket.bucket_name,
                "FileName": "demo-custom-resource.json",
                "DataContent": {
                    "environment": self.environment_param.value_as_string,
                    "version": "1.0",
                    "features": ["logging", "monitoring", "error-handling"],
                    "configuration": {
                        "retention_days": self.data_retention_days_param.value_as_number,
                        "log_retention_days": self.log_retention_days_param.value_as_number,
                    }
                },
                "Environment": self.environment_param.value_as_string,
            },
        )

        # Add dependency to ensure proper resource creation order
        self.demo_custom_resource.node.add_dependency(self.data_bucket)
        self.demo_custom_resource.node.add_dependency(self.custom_resource_function)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for integration and verification."""
        CfnOutput(
            self,
            "CustomResourceFunctionArn",
            description="ARN of the custom resource Lambda function",
            value=self.custom_resource_function.function_arn,
            export_name=f"{self.stack_name}-CustomResourceFunctionArn",
        )

        CfnOutput(
            self,
            "CustomResourceFunctionName",
            description="Name of the custom resource Lambda function",
            value=self.custom_resource_function.function_name,
            export_name=f"{self.stack_name}-CustomResourceFunctionName",
        )

        CfnOutput(
            self,
            "DataBucketName",
            description="Name of the S3 bucket for custom resource data",
            value=self.data_bucket.bucket_name,
            export_name=f"{self.stack_name}-DataBucketName",
        )

        CfnOutput(
            self,
            "DataBucketArn",
            description="ARN of the S3 bucket for custom resource data",
            value=self.data_bucket.bucket_arn,
            export_name=f"{self.stack_name}-DataBucketArn",
        )

        CfnOutput(
            self,
            "CustomResourceDataUrl",
            description="URL of the data file created by custom resource",
            value=self.demo_custom_resource.get_att_string("DataUrl"),
            export_name=f"{self.stack_name}-CustomResourceDataUrl",
        )

        CfnOutput(
            self,
            "CustomResourceStatus",
            description="Status of the custom resource operation",
            value=self.demo_custom_resource.get_att_string("Status"),
            export_name=f"{self.stack_name}-CustomResourceStatus",
        )

        CfnOutput(
            self,
            "LogGroupName",
            description="CloudWatch log group for custom resource monitoring",
            value=self.log_group.log_group_name,
            export_name=f"{self.stack_name}-LogGroupName",
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack."""
        Tags.of(self).add("Project", "CustomResourceDemo")
        Tags.of(self).add("Environment", self.environment_param.value_as_string)
        Tags.of(self).add("Purpose", "CloudFormation Custom Resource Demonstration")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "Engineering")


def main() -> None:
    """
    Main application entry point.
    
    Creates and deploys the CDK application with the custom resource demonstration stack.
    """
    app = App()
    
    # Get environment configuration
    env = cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT", "123456789012"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the main stack
    CustomResourceDemoStack(
        app,
        "CustomResourceDemoStack",
        env=env,
        description="Demonstration of Lambda-backed custom CloudFormation resources",
        tags={
            "Application": "CustomResourceDemo",
            "Framework": "CDK-Python",
            "Version": "1.0",
        },
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()