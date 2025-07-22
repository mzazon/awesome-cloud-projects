"""
Unit tests for Real-time Data Processing CDK Stack

This module contains unit tests for the CDK stack to ensure
proper resource creation and configuration.
"""

import aws_cdk as core
import aws_cdk.assertions as assertions
import pytest
from real_time_data_processing_stack import RealTimeDataProcessingStack


class TestRealTimeDataProcessingStack:
    """Test cases for the Real-time Data Processing Stack."""

    def setup_method(self):
        """Set up test fixtures before each test method."""
        self.app = core.App()
        self.stack = RealTimeDataProcessingStack(
            self.app, 
            "TestRealTimeDataProcessingStack"
        )
        self.template = assertions.Template.from_stack(self.stack)

    def test_kinesis_stream_created(self):
        """Test that Kinesis Data Stream is created with correct configuration."""
        self.template.has_resource_properties(
            "AWS::Kinesis::Stream",
            {
                "ShardCount": 3,
                "RetentionPeriodHours": 24,
                "StreamEncryption": {
                    "EncryptionType": "KMS"
                }
            }
        )

    def test_lambda_function_created(self):
        """Test that Lambda function is created with correct configuration."""
        self.template.has_resource_properties(
            "AWS::Lambda::Function",
            {
                "Runtime": "python3.9",
                "Handler": "index.lambda_handler",
                "Timeout": 60,
                "MemorySize": 256
            }
        )

    def test_s3_bucket_created(self):
        """Test that S3 bucket is created with proper configuration."""
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "VersioningConfiguration": {
                    "Status": "Enabled"
                },
                "BucketEncryption": {
                    "ServerSideEncryptionConfiguration": [
                        {
                            "ServerSideEncryptionByDefault": {
                                "SSEAlgorithm": "AES256"
                            }
                        }
                    ]
                },
                "PublicAccessBlockConfiguration": {
                    "BlockPublicAcls": True,
                    "BlockPublicPolicy": True,
                    "IgnorePublicAcls": True,
                    "RestrictPublicBuckets": True
                }
            }
        )

    def test_iam_role_created(self):
        """Test that IAM role is created with appropriate policies."""
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

    def test_event_source_mapping_created(self):
        """Test that event source mapping is created."""
        self.template.has_resource_properties(
            "AWS::Lambda::EventSourceMapping",
            {
                "BatchSize": 100,
                "MaximumBatchingWindowInSeconds": 5,
                "StartingPosition": "LATEST"
            }
        )

    def test_log_group_created(self):
        """Test that CloudWatch log group is created."""
        self.template.has_resource_properties(
            "AWS::Logs::LogGroup",
            {
                "RetentionInDays": 7
            }
        )

    def test_stack_outputs_created(self):
        """Test that all required stack outputs are created."""
        self.template.has_output("KinesisStreamName", {})
        self.template.has_output("KinesisStreamArn", {})
        self.template.has_output("LambdaFunctionName", {})
        self.template.has_output("LambdaFunctionArn", {})
        self.template.has_output("S3BucketName", {})
        self.template.has_output("S3BucketArn", {})

    def test_resource_count(self):
        """Test that the expected number of resources are created."""
        # Count major resource types
        self.template.resource_count_is("AWS::Kinesis::Stream", 1)
        self.template.resource_count_is("AWS::Lambda::Function", 1)
        self.template.resource_count_is("AWS::S3::Bucket", 1)
        self.template.resource_count_is("AWS::IAM::Role", 1)
        self.template.resource_count_is("AWS::Lambda::EventSourceMapping", 1)
        self.template.resource_count_is("AWS::Logs::LogGroup", 1)

    def test_lambda_environment_variables(self):
        """Test that Lambda function has correct environment variables."""
        self.template.has_resource_properties(
            "AWS::Lambda::Function",
            {
                "Environment": {
                    "Variables": {
                        "S3_BUCKET_NAME": assertions.Match.any_value()
                    }
                }
            }
        )

    def test_s3_lifecycle_policy(self):
        """Test that S3 bucket has lifecycle configuration."""
        self.template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "LifecycleConfiguration": {
                    "Rules": assertions.Match.any_value()
                }
            }
        )


def test_stack_synthesis():
    """Test that the stack can be synthesized without errors."""
    app = core.App()
    stack = RealTimeDataProcessingStack(app, "TestStack")
    
    # This should not raise any exceptions
    app.synth()
    
    # Basic assertions
    assert stack.kinesis_stream is not None
    assert stack.processor_function is not None
    assert stack.processed_data_bucket is not None
    assert stack.lambda_role is not None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])