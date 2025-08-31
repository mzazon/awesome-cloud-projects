#!/usr/bin/env python3
"""
AWS CDK Python application for Basic Secret Management with Secrets Manager and Lambda.

This CDK application deploys:
- AWS Secrets Manager secret with sample database credentials
- AWS Lambda function that retrieves secrets using the AWS Parameters and Secrets Extension
- IAM role with least privilege permissions for secret access
- CloudWatch log group for Lambda function logging

The solution demonstrates secure secret management practices by:
- Using AWS Secrets Manager for centralized secret storage
- Implementing least privilege IAM permissions
- Leveraging the AWS Parameters and Secrets Lambda Extension for optimized performance
- Following AWS Well-Architected Framework security principles
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    RemovalPolicy,
    aws_secretsmanager as secretsmanager,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class BasicSecretManagementStack(Stack):
    """
    CDK Stack for Basic Secret Management with Secrets Manager and Lambda.
    
    This stack creates the complete infrastructure for secure secret management
    including a sample secret, Lambda function with the Secrets Extension layer,
    and proper IAM permissions following security best practices.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names to avoid conflicts
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create sample database secret with JSON structure
        self.database_secret = self._create_database_secret(unique_suffix)
        
        # Create IAM role for Lambda function with least privilege permissions  
        self.lambda_role = self._create_lambda_execution_role(unique_suffix)
        
        # Create CloudWatch log group for Lambda function
        self.log_group = self._create_log_group(unique_suffix)
        
        # Create Lambda function with Secrets Extension layer
        self.lambda_function = self._create_lambda_function(unique_suffix)
        
        # Grant secret access permissions to Lambda role
        self._grant_secret_permissions()
        
        # Create stack outputs for validation and testing
        self._create_outputs()

    def _create_database_secret(self, suffix: str) -> secretsmanager.Secret:
        """
        Create a Secrets Manager secret containing sample database credentials.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            secretsmanager.Secret: The created secret resource
        """
        # Sample database credentials as JSON structure
        secret_value = {
            "database_host": "mydb.cluster-xyz.us-east-1.rds.amazonaws.com",
            "database_port": "5432", 
            "database_name": "production",
            "username": "appuser",
            "password": "secure-random-password-123"
        }
        
        secret = secretsmanager.Secret(
            self,
            "DatabaseSecret",
            secret_name=f"my-app-secrets-{suffix}",
            description="Sample application secrets for Lambda demo - Created by CDK",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template=cdk.to_json_string(secret_value),
                generate_string_key="",  # Don't generate a random key
                exclude_characters=" %+~`#$&*()|[]{}:;<>?!'/\"\\",
            ),
            removal_policy=RemovalPolicy.DESTROY,  # Allow deletion for demo purposes
        )
        
        # Add tags for resource management
        cdk.Tags.of(secret).add("Project", "BasicSecretManagement")
        cdk.Tags.of(secret).add("Environment", "Demo")
        cdk.Tags.of(secret).add("ManagedBy", "CDK")
        
        return secret

    def _create_lambda_execution_role(self, suffix: str) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege permissions.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"lambda-secrets-role-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Lambda function to access Secrets Manager - Created by CDK",
            managed_policies=[
                # Basic Lambda execution permissions for CloudWatch logs
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add tags for resource management
        cdk.Tags.of(role).add("Project", "BasicSecretManagement")
        cdk.Tags.of(role).add("Environment", "Demo")
        cdk.Tags.of(role).add("ManagedBy", "CDK")
        
        return role

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """
        Create CloudWatch log group for Lambda function with retention policy.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/secret-demo-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,  # 7 days retention for demo
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add tags for resource management
        cdk.Tags.of(log_group).add("Project", "BasicSecretManagement")
        cdk.Tags.of(log_group).add("Environment", "Demo")
        cdk.Tags.of(log_group).add("ManagedBy", "CDK")
        
        return log_group

    def _create_lambda_function(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function with Secrets Extension layer and proper configuration.
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        # AWS Parameters and Secrets Lambda Extension layer ARN
        # Version 18 is the latest as of 2024 - check AWS documentation for updates
        extension_layer_arn = f"arn:aws:lambda:{self.region}:177933569100:layer:AWS-Parameters-and-Secrets-Lambda-Extension:18"
        
        function = lambda_.Function(
            self,
            "SecretDemoFunction",
            function_name=f"secret-demo-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=self.lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            log_group=self.log_group,
            environment={
                "SECRET_NAME": self.database_secret.secret_name,
                # Extension configuration for optimal performance
                "PARAMETERS_SECRETS_EXTENSION_CACHE_ENABLED": "true",
                "PARAMETERS_SECRETS_EXTENSION_CACHE_SIZE": "1000",
                "PARAMETERS_SECRETS_EXTENSION_MAX_CONNECTIONS": "3",
                "PARAMETERS_SECRETS_EXTENSION_HTTP_PORT": "2773",
            },
            layers=[
                # Add AWS Parameters and Secrets Extension layer
                lambda_.LayerVersion.from_layer_version_arn(
                    self,
                    "SecretsExtensionLayer",
                    extension_layer_arn
                )
            ],
            description="Lambda function that retrieves secrets using AWS Parameters and Secrets Extension - Created by CDK",
        )
        
        # Add tags for resource management
        cdk.Tags.of(function).add("Project", "BasicSecretManagement")
        cdk.Tags.of(function).add("Environment", "Demo")
        cdk.Tags.of(function).add("ManagedBy", "CDK")
        
        return function

    def _grant_secret_permissions(self) -> None:
        """
        Grant the Lambda function's IAM role permission to read the specific secret.
        
        This implements least privilege by granting access only to the specific
        secret created in this stack, not all secrets in the account.
        """
        # Grant read access to the specific secret only
        self.database_secret.grant_read(self.lambda_role)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for stack validation and testing."""
        CfnOutput(
            self,
            "SecretName",
            value=self.database_secret.secret_name,
            description="Name of the created Secrets Manager secret",
        )
        
        CfnOutput(
            self,
            "SecretArn", 
            value=self.database_secret.secret_arn,
            description="ARN of the created Secrets Manager secret",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for testing",
        )
        
        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function",
        )
        
        CfnOutput(
            self,
            "IAMRoleName",
            value=self.lambda_role.role_name,
            description="Name of the Lambda execution IAM role",
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group name for Lambda function",
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code as an inline string.
        
        This function demonstrates the recommended approach for retrieving secrets
        using the AWS Parameters and Secrets Lambda Extension with proper error
        handling and security practices.
        
        Returns:
            str: The complete Lambda function code
        """
        return '''
import json
import urllib.request
import urllib.error
import os

# AWS Parameters and Secrets Lambda Extension HTTP endpoint
SECRETS_EXTENSION_HTTP_PORT = "2773"
SECRETS_EXTENSION_SERVER_PORT = os.environ.get(
    'PARAMETERS_SECRETS_EXTENSION_HTTP_PORT', 
    SECRETS_EXTENSION_HTTP_PORT
)

def get_secret(secret_name):
    """Retrieve secret using AWS Parameters and Secrets Lambda Extension"""
    secrets_extension_endpoint = (
        f"http://localhost:{SECRETS_EXTENSION_SERVER_PORT}"
        f"/secretsmanager/get?secretId={secret_name}"
    )
    
    # Add authentication header for the extension
    headers = {
        'X-Aws-Parameters-Secrets-Token': os.environ.get('AWS_SESSION_TOKEN', '')
    }
    
    try:
        req = urllib.request.Request(
            secrets_extension_endpoint, 
            headers=headers
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            secret_data = response.read().decode('utf-8')
            return json.loads(secret_data)
    except urllib.error.URLError as e:
        print(f"Error retrieving secret from extension: {e}")
        raise
    except json.JSONDecodeError as e:
        print(f"Error parsing secret JSON: {e}")
        raise
    except Exception as e:
        print(f"Unexpected error in get_secret: {e}")
        raise

def lambda_handler(event, context):
    """Main Lambda function handler"""
    secret_name = os.environ.get('SECRET_NAME')
    
    if not secret_name:
        return {
            'statusCode': 400,
            'body': json.dumps({
                'error': 'SECRET_NAME environment variable not set'
            })
        }
    
    try:
        # Retrieve secret using the extension
        print(f"Attempting to retrieve secret: {secret_name}")
        secret_response = get_secret(secret_name)
        secret_value = json.loads(secret_response['SecretString'])
        
        # Use secret values (example: database connection info)
        db_host = secret_value.get('database_host', 'Not found')
        db_name = secret_value.get('database_name', 'Not found')
        username = secret_value.get('username', 'Not found')
        
        print(f"Successfully retrieved secret for database: {db_name}")
        
        # In a real application, you would use these values to connect
        # to your database or external service
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Secret retrieved successfully',
                'database_host': db_host,
                'database_name': db_name,
                'username': username,
                'extension_cache': 'Enabled with 300s TTL',
                'note': 'Password retrieved but not displayed for security'
            })
        }
        
    except Exception as e:
        print(f"Error in lambda_handler: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'details': str(e)
            })
        }
'''


# CDK App initialization and stack instantiation
app = cdk.App()

# Create the main stack
BasicSecretManagementStack(
    app, 
    "BasicSecretManagementStack",
    description="CDK Stack for Basic Secret Management with Secrets Manager and Lambda",
    # Enable termination protection for production deployments
    termination_protection=False,  # Set to True for production
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    ),
)

# Apply tags to all resources in the app
cdk.Tags.of(app).add("Project", "BasicSecretManagement")
cdk.Tags.of(app).add("CreatedBy", "CDK")
cdk.Tags.of(app).add("Environment", "Demo")

app.synth()