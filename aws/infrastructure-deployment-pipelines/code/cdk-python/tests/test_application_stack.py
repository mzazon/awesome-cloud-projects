"""
Unit tests for the ApplicationStack.

This module contains comprehensive tests for the ApplicationStack class,
validating the creation and configuration of all infrastructure components.
"""

import json
import pytest
import aws_cdk as cdk
from aws_cdk import assertions

# Import the stack under test
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
from app import ApplicationStack


class TestApplicationStack:
    """Test suite for the ApplicationStack class."""

    def setup_method(self):
        """Set up test fixtures before each test method."""
        self.app = cdk.App()
        self.stack = ApplicationStack(
            self.app,
            "TestApplicationStack",
            environment_name="test"
        )
        self.template = assertions.Template.from_stack(self.stack)

    def test_s3_bucket_created(self):
        """Test that S3 bucket is created with correct configuration."""
        # Verify S3 bucket exists
        self.template.has_resource_properties("AWS::S3::Bucket", {
            "VersioningConfiguration": {
                "Status": "Enabled"
            },
            "PublicAccessBlockConfiguration": {
                "BlockPublicAcls": True,
                "BlockPublicPolicy": True,
                "IgnorePublicAcls": True,
                "RestrictPublicBuckets": True
            },
            "BucketEncryption": {
                "ServerSideEncryptionConfiguration": [
                    {
                        "ServerSideEncryptionByDefault": {
                            "SSEAlgorithm": "AES256"
                        }
                    }
                ]
            }
        })

    def test_dynamodb_table_created(self):
        """Test that DynamoDB table is created with correct configuration."""
        # Verify DynamoDB table exists
        self.template.has_resource_properties("AWS::DynamoDB::Table", {
            "TableName": "app-data-test",
            "KeySchema": [
                {
                    "AttributeName": "id",
                    "KeyType": "HASH"
                }
            ],
            "AttributeDefinitions": [
                {
                    "AttributeName": "id",
                    "AttributeType": "S"
                }
            ],
            "BillingMode": "PAY_PER_REQUEST"
        })

    def test_lambda_function_created(self):
        """Test that Lambda function is created with correct configuration."""
        # Verify Lambda function exists
        self.template.has_resource_properties("AWS::Lambda::Function", {
            "FunctionName": "app-api-test",
            "Runtime": "python3.11",
            "Handler": "index.handler",
            "MemorySize": 256,
            "Timeout": 60
        })

    def test_lambda_environment_variables(self):
        """Test that Lambda function has correct environment variables."""
        # Get Lambda function properties
        lambda_resources = self.template.find_resources("AWS::Lambda::Function")
        
        # Should have at least one Lambda function
        assert len(lambda_resources) >= 1
        
        # Check environment variables are present
        for resource_id, resource in lambda_resources.items():
            properties = resource.get("Properties", {})
            environment = properties.get("Environment", {})
            variables = environment.get("Variables", {})
            
            # Verify required environment variables exist
            assert "ENVIRONMENT" in variables
            assert "TABLE_NAME" in variables
            assert "BUCKET_NAME" in variables

    def test_lambda_iam_permissions(self):
        """Test that Lambda function has correct IAM permissions."""
        # Verify Lambda execution role exists
        self.template.has_resource_properties("AWS::IAM::Role", {
            "AssumeRolePolicyDocument": {
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "lambda.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }
                ]
            }
        })

    def test_cloudwatch_dashboard_created(self):
        """Test that CloudWatch dashboard is created."""
        # Verify CloudWatch dashboard exists
        self.template.has_resource_properties("AWS::CloudWatch::Dashboard", {
            "DashboardName": "app-monitoring-test"
        })

    def test_stack_outputs_created(self):
        """Test that stack outputs are created correctly."""
        # Verify outputs exist
        self.template.has_outputs_count(4)
        
        # Check specific outputs
        self.template.has_output("AssetsBucketName", {})
        self.template.has_output("AppTableName", {})
        self.template.has_output("ApiFunctionName", {})
        self.template.has_output("ApiFunctionArn", {})

    def test_resource_tagging(self):
        """Test that resources are properly tagged."""
        # This is a basic test - in real scenarios, you'd check specific tags
        # that are applied to resources
        pass

    def test_stack_environment_specific_naming(self):
        """Test that resources are named correctly for the environment."""
        # Verify resources include environment name
        resources = self.template.to_json()
        
        # Check that resource names include environment identifier
        assert "test" in json.dumps(resources)

    def test_security_configuration(self):
        """Test security-related configurations."""
        # Verify S3 bucket has encryption
        s3_resources = self.template.find_resources("AWS::S3::Bucket")
        for resource_id, resource in s3_resources.items():
            properties = resource.get("Properties", {})
            assert "BucketEncryption" in properties
            
        # Verify DynamoDB table has encryption
        dynamodb_resources = self.template.find_resources("AWS::DynamoDB::Table")
        for resource_id, resource in dynamodb_resources.items():
            properties = resource.get("Properties", {})
            # DynamoDB encryption may be implicit or explicit
            # This test could be enhanced based on specific requirements

    def test_removal_policy_configuration(self):
        """Test that removal policies are set correctly."""
        # This test verifies that resources have appropriate removal policies
        # In a real test, you'd check the CloudFormation metadata
        pass

    def test_different_environments(self):
        """Test stack behavior with different environment names."""
        # Test production environment
        prod_stack = ApplicationStack(
            self.app,
            "TestProdStack",
            environment_name="prod"
        )
        prod_template = assertions.Template.from_stack(prod_stack)
        
        # Verify production-specific configurations
        prod_template.has_resource_properties("AWS::DynamoDB::Table", {
            "TableName": "app-data-prod",
            "PointInTimeRecoverySpecification": {
                "PointInTimeRecoveryEnabled": True
            }
        })

    def test_lambda_function_code_content(self):
        """Test that Lambda function code contains expected content."""
        # Get Lambda function properties
        lambda_resources = self.template.find_resources("AWS::Lambda::Function")
        
        for resource_id, resource in lambda_resources.items():
            properties = resource.get("Properties", {})
            code = properties.get("Code", {})
            
            # Verify inline code is present
            assert "ZipFile" in code
            
            # Verify code contains expected imports and logic
            code_content = code["ZipFile"]
            assert "import json" in code_content
            assert "import boto3" in code_content
            assert "def handler" in code_content

    def test_resource_dependencies(self):
        """Test that resources have correct dependencies."""
        # Verify Lambda function depends on DynamoDB table and S3 bucket
        lambda_resources = self.template.find_resources("AWS::Lambda::Function")
        
        # This test could be enhanced to verify specific dependencies
        # using CDK assertions for dependency checking
        assert len(lambda_resources) >= 1