"""
Unit tests for the AWS Batch processing CDK stack.

This module contains tests that validate the CDK stack creates the expected
AWS resources with proper configurations.
"""

import aws_cdk as cdk
from aws_cdk import assertions
import pytest
from app import BatchProcessingStack


class TestBatchProcessingStack:
    """Test cases for the BatchProcessingStack."""

    @pytest.fixture
    def stack(self) -> BatchProcessingStack:
        """Create a test stack instance."""
        app = cdk.App()
        return BatchProcessingStack(
            app, "TestBatchStack",
            env=cdk.Environment(account="123456789012", region="us-east-1")
        )

    def test_creates_ecr_repository(self, stack: BatchProcessingStack) -> None:
        """Test that ECR repository is created with proper configuration."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource("AWS::ECR::Repository", {
            "Properties": {
                "ImageScanningConfiguration": {
                    "ScanOnPush": True
                },
                "LifecyclePolicy": {
                    "LifecyclePolicyText": assertions.Match.string_like_regexp(
                        r".*maxImageCount.*10.*"
                    )
                }
            }
        })

    def test_creates_vpc_with_endpoints(self, stack: BatchProcessingStack) -> None:
        """Test that VPC is created with required VPC endpoints."""
        template = assertions.Template.from_stack(stack)
        
        # Check VPC exists
        template.has_resource("AWS::EC2::VPC", {
            "Properties": {
                "CidrBlock": "10.0.0.0/16",
                "EnableDnsHostnames": True,
                "EnableDnsSupport": True
            }
        })
        
        # Check VPC endpoints for ECR
        template.has_resource("AWS::EC2::VPCEndpoint", {
            "Properties": {
                "ServiceName": assertions.Match.string_like_regexp(
                    r".*\.ecr\.dkr\..*"
                )
            }
        })

    def test_creates_batch_compute_environment(self, stack: BatchProcessingStack) -> None:
        """Test that Batch compute environment is properly configured."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource("AWS::Batch::ComputeEnvironment", {
            "Properties": {
                "Type": "MANAGED",
                "State": "ENABLED",
                "ComputeResources": {
                    "Type": "EC2",
                    "MinvCpus": 0,
                    "MaxvCpus": 100,
                    "DesiredvCpus": 0,
                    "InstanceTypes": ["optimal"],
                    "BidPercentage": 50
                }
            }
        })

    def test_creates_job_queue(self, stack: BatchProcessingStack) -> None:
        """Test that job queue is created with proper configuration."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource("AWS::Batch::JobQueue", {
            "Properties": {
                "State": "ENABLED",
                "Priority": 1
            }
        })

    def test_creates_iam_roles(self, stack: BatchProcessingStack) -> None:
        """Test that required IAM roles are created."""
        template = assertions.Template.from_stack(stack)
        
        # Batch service role
        template.has_resource("AWS::IAM::Role", {
            "Properties": {
                "AssumeRolePolicyDocument": {
                    "Statement": [{
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "batch.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }]
                },
                "ManagedPolicyArns": [
                    "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
                ]
            }
        })
        
        # ECS instance role
        template.has_resource("AWS::IAM::Role", {
            "Properties": {
                "AssumeRolePolicyDocument": {
                    "Statement": [{
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "ec2.amazonaws.com"
                        },
                        "Action": "sts:AssumeRole"
                    }]
                },
                "ManagedPolicyArns": [
                    "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
                ]
            }
        })

    def test_creates_cloudwatch_log_group(self, stack: BatchProcessingStack) -> None:
        """Test that CloudWatch log group is created."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource("AWS::Logs::LogGroup", {
            "Properties": {
                "LogGroupName": "/aws/batch/job",
                "RetentionInDays": 30
            }
        })

    def test_creates_cloudwatch_alarms(self, stack: BatchProcessingStack) -> None:
        """Test that monitoring alarms are created."""
        template = assertions.Template.from_stack(stack)
        
        # Failed jobs alarm
        template.has_resource("AWS::CloudWatch::Alarm", {
            "Properties": {
                "MetricName": "FailedJobs",
                "Namespace": "AWS/Batch",
                "Statistic": "Sum",
                "Threshold": 1,
                "ComparisonOperator": "GreaterThanOrEqualToThreshold"
            }
        })

    def test_security_group_configuration(self, stack: BatchProcessingStack) -> None:
        """Test security group has proper configuration."""
        template = assertions.Template.from_stack(stack)
        
        # Should have security group with self-referencing rule
        template.has_resource("AWS::EC2::SecurityGroup", {
            "Properties": {
                "SecurityGroupIngress": [{
                    "IpProtocol": "-1",
                    "SourceSecurityGroupId": assertions.Match.any_value()
                }]
            }
        })

    def test_outputs_are_created(self, stack: BatchProcessingStack) -> None:
        """Test that stack outputs are properly defined."""
        template = assertions.Template.from_stack(stack)
        
        # Check for key outputs
        template.has_output("ECRRepositoryURI", {
            "Description": "ECR Repository URI for batch processing container images"
        })
        
        template.has_output("JobQueueName", {
            "Description": "Name of the Batch job queue"
        })
        
        template.has_output("ComputeEnvironmentName", {
            "Description": "Name of the Batch compute environment"
        })

    def test_resource_count(self, stack: BatchProcessingStack) -> None:
        """Test that expected number of resources are created."""
        template = assertions.Template.from_stack(stack)
        
        # Verify we're creating the expected number of key resources
        template.resource_count_is("AWS::Batch::ComputeEnvironment", 1)
        template.resource_count_is("AWS::Batch::JobQueue", 1) 
        template.resource_count_is("AWS::Batch::JobDefinition", 1)
        template.resource_count_is("AWS::ECR::Repository", 1)
        template.resource_count_is("AWS::Logs::LogGroup", 1)
        
        # Should have multiple IAM roles
        template.resource_count_is("AWS::IAM::Role", 2)


def test_app_synth_succeeds() -> None:
    """Test that the CDK app can be synthesized without errors."""
    app = cdk.App()
    BatchProcessingStack(
        app, "TestSynthStack",
        env=cdk.Environment(account="123456789012", region="us-east-1")
    )
    
    # This should not raise any exceptions
    template = app.synth()
    assert len(template.stacks) == 1
    assert template.stacks[0].stack_name == "TestSynthStack"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])