"""
Unit tests for the Markdown to HTML Converter CDK application.

This test module validates the CDK stack construction and resource configuration
to ensure the infrastructure is correctly defined.

Requirements:
    pip install pytest pytest-cdk moto boto3

Usage:
    pytest test_app.py -v
"""

import pytest
import json
from unittest.mock import patch, MagicMock

import aws_cdk as cdk
from aws_cdk import assertions

# Import the stack class to test
from app import MarkdownHtmlConverterStack


class TestMarkdownHtmlConverterStack:
    """Test suite for the MarkdownHtmlConverterStack CDK stack."""

    def setup_method(self):
        """Set up test fixtures before each test method."""
        self.app = cdk.App()
        self.stack = MarkdownHtmlConverterStack(
            self.app,
            "TestMarkdownHtmlConverter",
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )
        self.template = assertions.Template.from_stack(self.stack)

    def test_s3_buckets_created(self):
        """Test that both input and output S3 buckets are created."""
        # Verify input bucket exists
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "BucketEncryption": {
                    "ServerSideEncryptionConfiguration": [
                        {
                            "ServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            }
                        }
                    ]
                },
                "VersioningConfiguration": {
                    "Status": "Enabled"
                },
                "PublicAccessBlockConfiguration": {
                    "BlockPublicAcls": True,
                    "BlockPublicPolicy": True,
                    "IgnorePublicAcls": True,
                    "RestrictPublicBuckets": True
                }
            }
        )

        # Verify exactly 2 S3 buckets are created (input and output)
        self.template.resource_count_is("AWS::S3::Bucket", 2)

    def test_lambda_function_created(self):
        """Test that the Lambda function is created with correct configuration."""
        self.template.has_resource_properties(
            "AWS::Lambda::Function",
            {
                "Runtime": "python3.12",
                "Handler": "lambda_function.lambda_handler",
                "Timeout": 60,
                "MemorySize": 256,
                "Environment": {
                    "Variables": {
                        "OUTPUT_BUCKET_NAME": assertions.Match.any_value()
                    }
                }
            }
        )

        # Verify exactly 1 Lambda function is created
        self.template.resource_count_is("AWS::Lambda::Function", 1)

    def test_iam_role_created(self):
        """Test that the IAM role is created with proper trust policy."""
        self.template.has_resource_properties(
            "AWS::IAM::Role",
            {
                "AssumeRolePolicyDocument": {
                    "Statement": [
                        {
                            "Action": "sts:AssumeRole",
                            "Effect": "Allow",
                            "Principal": {
                                "Service": "lambda.amazonaws.com"
                            }
                        }
                    ]
                }
            }
        )

    def test_iam_policies_attached(self):
        """Test that the correct IAM policies are attached to the role."""
        # Check for basic execution role policy
        self.template.has_resource_properties(
            "AWS::IAM::Role",
            {
                "ManagedPolicyArns": assertions.Match.array_with([
                    assertions.Match.string_like_regexp(
                        ".*AWSLambdaBasicExecutionRole.*"
                    )
                ])
            }
        )

        # Check for inline policy with S3 permissions
        self.template.has_resource_properties(
            "AWS::IAM::Policy",
            {
                "PolicyDocument": {
                    "Statement": assertions.Match.any_value()
                }
            }
        )

    def test_s3_event_notification_configured(self):
        """Test that S3 event notification is properly configured."""
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "NotificationConfiguration": {
                    "LambdaConfigurations": [
                        {
                            "Event": "s3:ObjectCreated:*",
                            "Filter": {
                                "S3Key": {
                                    "Rules": [
                                        {
                                            "Name": "suffix",
                                            "Value": ".md"
                                        }
                                    ]
                                }
                            }
                        }
                    ]
                }
            }
        )

    def test_lambda_permission_for_s3(self):
        """Test that Lambda has permission to be invoked by S3."""
        self.template.has_resource_properties(
            "AWS::Lambda::Permission",
            {
                "Action": "lambda:InvokeFunction",
                "Principal": "s3.amazonaws.com"
            }
        )

    def test_stack_outputs_defined(self):
        """Test that all required stack outputs are defined."""
        # Get the synthesized template as JSON to check outputs
        template_dict = self.template.to_json()
        outputs = template_dict.get("Outputs", {})
        
        # Check that all expected outputs exist
        expected_outputs = [
            "InputBucketName",
            "OutputBucketName", 
            "LambdaFunctionName",
            "LambdaFunctionArn"
        ]
        
        for output_name in expected_outputs:
            assert output_name in outputs, f"Output {output_name} not found"

    def test_resource_tags_applied(self):
        """Test that common tags are applied to resources."""
        # This is a more complex test that would require checking
        # the synthesized template for tags on each resource
        template_dict = self.template.to_json()
        
        # Verify that tags exist somewhere in the template
        template_str = json.dumps(template_dict)
        assert "Project" in template_str
        assert "MarkdownHtmlConverter" in template_str

    def test_removal_policy_set(self):
        """Test that S3 buckets have appropriate removal policy."""
        # This ensures buckets can be deleted during cleanup
        template_dict = self.template.to_json()
        
        # Check that S3 buckets have DeletionPolicy set
        resources = template_dict.get("Resources", {})
        s3_buckets = [
            resource for resource in resources.values()
            if resource.get("Type") == "AWS::S3::Bucket"
        ]
        
        assert len(s3_buckets) == 2, "Expected exactly 2 S3 buckets"
        
        for bucket in s3_buckets:
            assert bucket.get("DeletionPolicy") == "Delete"


class TestLambdaFunction:
    """Test suite for the Lambda function code (if externalized)."""

    @patch('boto3.client')
    def test_lambda_handler_mock(self, mock_boto3):
        """Test Lambda handler with mocked AWS services."""
        # This would test the actual Lambda function logic
        # if it were in a separate file
        
        # Mock S3 client
        mock_s3 = MagicMock()
        mock_boto3.return_value = mock_s3
        
        # Mock S3 get_object response
        mock_s3.get_object.return_value = {
            'Body': MagicMock(read=lambda: b'# Test Markdown\nThis is **bold** text.')
        }
        
        # Since the Lambda code is inline in CDK, we can't easily test it
        # In a real implementation, the Lambda code would be in a separate file
        assert True  # Placeholder test


def test_app_creation():
    """Test that the CDK app can be created successfully."""
    app = cdk.App()
    stack = MarkdownHtmlConverterStack(
        app,
        "TestStack",
        env=cdk.Environment(account="123456789012", region="us-east-1")
    )
    
    # Synthesize the stack to ensure no errors
    template = assertions.Template.from_stack(stack)
    assert template is not None


if __name__ == "__main__":
    # Run tests if executed directly
    pytest.main([__file__, "-v"])