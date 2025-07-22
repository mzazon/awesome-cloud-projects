"""
Unit tests for the Real-time Anomaly Detection CDK application.

This module contains unit tests that verify the CDK stack configuration
and resource creation without actually deploying to AWS.
"""

import pytest
from aws_cdk import App, Environment
from aws_cdk.assertions import Template, Match
from app import AnomalyDetectionStack


class TestAnomalyDetectionStack:
    """Test cases for the AnomalyDetectionStack CDK stack."""

    @pytest.fixture
    def app(self) -> App:
        """Create a CDK app for testing."""
        return App()

    @pytest.fixture
    def stack(self, app: App) -> AnomalyDetectionStack:
        """Create an AnomalyDetectionStack for testing."""
        env = Environment(account="123456789012", region="us-east-1")
        return AnomalyDetectionStack(
            app,
            "TestAnomalyDetectionStack",
            env=env,
        )

    @pytest.fixture
    def template(self, stack: AnomalyDetectionStack) -> Template:
        """Generate CloudFormation template from the stack."""
        return Template.from_stack(stack)

    def test_kinesis_stream_created(self, template: Template) -> None:
        """Test that Kinesis Data Stream is created with correct configuration."""
        template.has_resource_properties(
            "AWS::Kinesis::Stream",
            {
                "ShardCount": 2,
                "RetentionPeriodHours": 24,
            }
        )

    def test_s3_bucket_created(self, template: Template) -> None:
        """Test that S3 bucket is created with proper security settings."""
        template.has_resource_properties(
            "AWS::S3::Bucket",
            {
                "VersioningConfiguration": {
                    "Status": "Enabled"
                },
                "PublicAccessBlockConfiguration": {
                    "BlockPublicAcls": True,
                    "BlockPublicPolicy": True,
                    "IgnorePublicAcls": True,
                    "RestrictPublicBuckets": True,
                },
            }
        )

    def test_sns_topic_created(self, template: Template) -> None:
        """Test that SNS topic is created for alerts."""
        template.has_resource_properties(
            "AWS::SNS::Topic",
            {
                "DisplayName": "Real-time Anomaly Detection Alerts"
            }
        )

    def test_lambda_function_created(self, template: Template) -> None:
        """Test that Lambda function is created with correct configuration."""
        template.has_resource_properties(
            "AWS::Lambda::Function",
            {
                "Runtime": "python3.9",
                "Handler": "index.lambda_handler",
                "Timeout": 60,
                "Environment": {
                    "Variables": {
                        "CLOUDWATCH_NAMESPACE": "AnomalyDetection"
                    }
                }
            }
        )

    def test_kinesis_analytics_application_created(self, template: Template) -> None:
        """Test that Kinesis Analytics application is created."""
        template.has_resource_properties(
            "AWS::KinesisAnalyticsV2::Application",
            {
                "RuntimeEnvironment": "FLINK-1_17",
                "ApplicationConfiguration": {
                    "FlinkApplicationConfiguration": {
                        "CheckpointConfiguration": {
                            "ConfigurationType": "CUSTOM",
                            "CheckpointingEnabled": True,
                            "CheckpointInterval": 60000,
                        },
                        "ParallelismConfiguration": {
                            "ConfigurationType": "CUSTOM",
                            "Parallelism": 2,
                            "ParallelismPerKPU": 1,
                        }
                    }
                }
            }
        )

    def test_cloudwatch_alarm_created(self, template: Template) -> None:
        """Test that CloudWatch alarm is created for anomaly detection."""
        template.has_resource_properties(
            "AWS::CloudWatch::Alarm",
            {
                "ComparisonOperator": "GreaterThanThreshold",
                "EvaluationPeriods": 1,
                "MetricName": "AnomalyCount",
                "Namespace": "AnomalyDetection",
                "Statistic": "Sum",
                "Threshold": 1,
            }
        )

    def test_iam_roles_created(self, template: Template) -> None:
        """Test that necessary IAM roles are created."""
        # Test Lambda execution role
        template.has_resource_properties(
            "AWS::IAM::Role",
            {
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
            }
        )

        # Test Flink execution role
        template.has_resource_properties(
            "AWS::IAM::Role",
            {
                "AssumeRolePolicyDocument": {
                    "Statement": [
                        {
                            "Effect": "Allow",
                            "Principal": {
                                "Service": "kinesisanalytics.amazonaws.com"
                            },
                            "Action": "sts:AssumeRole"
                        }
                    ]
                }
            }
        )

    def test_iam_policies_attached(self, template: Template) -> None:
        """Test that IAM policies are properly attached to roles."""
        # Check for Kinesis permissions in Flink role
        template.has_resource_properties(
            "AWS::IAM::Policy",
            {
                "PolicyDocument": {
                    "Statement": Match.array_with([
                        {
                            "Effect": "Allow",
                            "Action": [
                                "kinesis:DescribeStream",
                                "kinesis:GetShardIterator",
                                "kinesis:GetRecords",
                                "kinesis:ListShards"
                            ]
                        }
                    ])
                }
            }
        )

    def test_outputs_created(self, template: Template) -> None:
        """Test that CloudFormation outputs are created."""
        template.has_output("TransactionStreamName", {})
        template.has_output("TransactionStreamArn", {})
        template.has_output("FlinkApplicationName", {})
        template.has_output("AlertsTopicArn", {})
        template.has_output("ArtifactsBucketName", {})
        template.has_output("LambdaFunctionName", {})

    def test_resource_count(self, template: Template) -> None:
        """Test that the expected number of resources are created."""
        # This is a general sanity check to ensure we're creating the right number of resources
        template.resource_count_is("AWS::Kinesis::Stream", 1)
        template.resource_count_is("AWS::S3::Bucket", 1)
        template.resource_count_is("AWS::SNS::Topic", 1)
        template.resource_count_is("AWS::Lambda::Function", 1)
        template.resource_count_is("AWS::KinesisAnalyticsV2::Application", 1)
        template.resource_count_is("AWS::CloudWatch::Alarm", 1)
        template.resource_count_is("AWS::CloudWatch::Dashboard", 1)

    def test_stack_tags(self, stack: AnomalyDetectionStack) -> None:
        """Test that stack has appropriate tags."""
        template = Template.from_stack(stack)
        
        # Tags are applied at the stack level, so we check the stack metadata
        # In a real implementation, you might want to check specific resource tags
        assert stack.tags.tag_values().get("Project") == "AnomalyDetection"
        assert stack.tags.tag_values().get("Environment") == "Development"
        assert stack.tags.tag_values().get("Owner") == "DataEngineering"


class TestStackCreation:
    """Test cases for stack creation and basic validation."""

    def test_stack_creation_succeeds(self) -> None:
        """Test that the stack can be created without errors."""
        app = App()
        env = Environment(account="123456789012", region="us-east-1")
        
        # This should not raise any exceptions
        stack = AnomalyDetectionStack(
            app,
            "TestStack",
            env=env,
        )
        
        assert stack is not None
        assert stack.stack_name == "TestStack"

    def test_app_synthesis_succeeds(self) -> None:
        """Test that the CDK app can be synthesized to CloudFormation."""
        app = App()
        env = Environment(account="123456789012", region="us-east-1")
        
        AnomalyDetectionStack(
            app,
            "TestStack",
            env=env,
        )
        
        # This should not raise any exceptions
        cloud_assembly = app.synth()
        assert cloud_assembly is not None
        assert len(cloud_assembly.stacks) == 1


if __name__ == "__main__":
    # Run tests when script is executed directly
    pytest.main([__file__, "-v"])