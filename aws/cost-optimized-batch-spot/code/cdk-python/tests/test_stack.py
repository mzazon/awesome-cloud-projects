"""
Unit tests for the Cost-Optimized Batch Processing CDK Stack.

These tests verify that the CDK stack creates the expected resources
with the correct configurations for cost optimization and fault tolerance.
"""

import aws_cdk as cdk
import pytest
from aws_cdk import assertions

from app import CostOptimizedBatchProcessingStack


class TestCostOptimizedBatchProcessingStack:
    """Test suite for the Cost-Optimized Batch Processing Stack."""

    @pytest.fixture
    def stack(self) -> CostOptimizedBatchProcessingStack:
        """Create a test stack instance."""
        app = cdk.App()
        return CostOptimizedBatchProcessingStack(
            app,
            "TestStack",
            env=cdk.Environment(account="123456789012", region="us-east-1"),
        )

    def test_vpc_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that VPC is created with correct configuration."""
        template = assertions.Template.from_stack(stack)
        
        # Check VPC exists
        template.has_resource_properties("AWS::EC2::VPC", {
            "CidrBlock": "10.0.0.0/16",
            "EnableDnsHostnames": True,
            "EnableDnsSupport": True,
        })
        
        # Check public subnets exist
        template.has_resource_properties("AWS::EC2::Subnet", {
            "MapPublicIpOnLaunch": True,
        })
        
        # Check private subnets exist
        template.has_resource_properties("AWS::EC2::Subnet", {
            "MapPublicIpOnLaunch": False,
        })

    def test_ecr_repository_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that ECR repository is created with correct configuration."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::ECR::Repository", {
            "ImageScanningConfiguration": {
                "ScanOnPush": True,
            },
            "LifecyclePolicy": {
                "LifecyclePolicyText": assertions.Match.string_like_regexp(
                    r".*imageCountMoreThan.*10.*"
                ),
            },
        })

    def test_iam_roles_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that IAM roles are created with correct policies."""
        template = assertions.Template.from_stack(stack)
        
        # Check Batch service role
        template.has_resource_properties("AWS::IAM::Role", {
            "AssumeRolePolicyDocument": {
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "batch.amazonaws.com",
                        },
                        "Action": "sts:AssumeRole",
                    }
                ],
            },
            "ManagedPolicyArns": [
                {
                    "Fn::Join": [
                        "",
                        [
                            "arn:",
                            {"Ref": "AWS::Partition"},
                            ":iam::aws:policy/service-role/AWSBatchServiceRole",
                        ],
                    ],
                }
            ],
        })
        
        # Check instance role
        template.has_resource_properties("AWS::IAM::Role", {
            "AssumeRolePolicyDocument": {
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "Service": "ec2.amazonaws.com",
                        },
                        "Action": "sts:AssumeRole",
                    }
                ],
            },
            "ManagedPolicyArns": [
                {
                    "Fn::Join": [
                        "",
                        [
                            "arn:",
                            {"Ref": "AWS::Partition"},
                            ":iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role",
                        ],
                    ],
                }
            ],
        })

    def test_compute_environment_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that compute environment is created with Spot configuration."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::Batch::ComputeEnvironment", {
            "Type": "MANAGED",
            "State": "ENABLED",
            "ComputeResources": {
                "Type": "EC2",
                "MinvCpus": 0,
                "MaxvCpus": 256,
                "DesiredvCpus": 0,
                "InstanceTypes": [
                    "c5.large",
                    "c5.xlarge",
                    "c5.2xlarge",
                    "c5.4xlarge",
                    "m5.large",
                    "m5.xlarge",
                    "m5.2xlarge",
                    "m5.4xlarge",
                    "r5.large",
                    "r5.xlarge",
                    "r5.2xlarge",
                ],
                "AllocationStrategy": "SPOT_CAPACITY_OPTIMIZED",
                "BidPercentage": 80,
                "Ec2Configuration": [
                    {
                        "ImageType": "ECS_AL2",
                    }
                ],
            },
        })

    def test_job_queue_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that job queue is created with correct configuration."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::Batch::JobQueue", {
            "State": "ENABLED",
            "Priority": 1,
            "ComputeEnvironmentOrder": [
                {
                    "Order": 1,
                    "ComputeEnvironment": assertions.Match.any_value(),
                }
            ],
        })

    def test_job_definition_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that job definition is created with retry strategy."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::Batch::JobDefinition", {
            "Type": "container",
            "ContainerProperties": {
                "Vcpus": 1,
                "Memory": 2048,
                "LogConfiguration": {
                    "LogDriver": "awslogs",
                    "Options": {
                        "awslogs-region": "us-east-1",
                        "awslogs-stream-prefix": "batch",
                    },
                },
            },
            "RetryStrategy": {
                "Attempts": 3,
                "EvaluateOnExit": [
                    {
                        "Action": "RETRY",
                        "OnStatusReason": "Host EC2*",
                    },
                    {
                        "Action": "EXIT",
                        "OnReason": "*",
                    },
                ],
            },
            "Timeout": {
                "AttemptDurationSeconds": 3600,
            },
        })

    def test_s3_bucket_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that S3 bucket is created with lifecycle policies."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::S3::Bucket", {
            "VersioningConfiguration": {
                "Status": "Enabled",
            },
            "PublicAccessBlockConfiguration": {
                "BlockPublicAcls": True,
                "BlockPublicPolicy": True,
                "IgnorePublicAcls": True,
                "RestrictPublicBuckets": True,
            },
            "LifecycleConfiguration": {
                "Rules": assertions.Match.array_with([
                    {
                        "Status": "Enabled",
                        "NoncurrentVersionExpirationInDays": 30,
                    },
                    {
                        "Status": "Enabled",
                        "Transitions": assertions.Match.array_with([
                            {
                                "StorageClass": "STANDARD_IA",
                                "TransitionInDays": 30,
                            },
                            {
                                "StorageClass": "GLACIER",
                                "TransitionInDays": 90,
                            },
                        ]),
                    },
                ]),
            },
        })

    def test_cloudwatch_log_group_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that CloudWatch log group is created."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::Logs::LogGroup", {
            "RetentionInDays": 30,
        })

    def test_security_group_creation(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that security group is created with correct configuration."""
        template = assertions.Template.from_stack(stack)
        
        template.has_resource_properties("AWS::EC2::SecurityGroup", {
            "GroupDescription": "Security group for AWS Batch instances",
            "SecurityGroupEgress": [
                {
                    "CidrIp": "0.0.0.0/0",
                    "Description": "Allow all outbound traffic by default",
                    "IpProtocol": "-1",
                }
            ],
        })

    def test_stack_outputs(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that stack creates the expected outputs."""
        template = assertions.Template.from_stack(stack)
        
        # Check that outputs exist
        template.has_output("ECRRepositoryURI", {})
        template.has_output("JobQueueName", {})
        template.has_output("JobDefinitionName", {})
        template.has_output("ComputeEnvironmentName", {})
        template.has_output("ArtifactsBucketName", {})
        template.has_output("LogGroupName", {})

    def test_resource_count(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that the expected number of resources are created."""
        template = assertions.Template.from_stack(stack)
        
        # Check key resource counts
        template.resource_count_is("AWS::EC2::VPC", 1)
        template.resource_count_is("AWS::ECR::Repository", 1)
        template.resource_count_is("AWS::Batch::ComputeEnvironment", 1)
        template.resource_count_is("AWS::Batch::JobQueue", 1)
        template.resource_count_is("AWS::Batch::JobDefinition", 1)
        template.resource_count_is("AWS::S3::Bucket", 1)
        template.resource_count_is("AWS::Logs::LogGroup", 1)

    def test_tags_applied(self, stack: CostOptimizedBatchProcessingStack) -> None:
        """Test that common tags are applied to resources."""
        template = assertions.Template.from_stack(stack)
        
        # Check that resources have expected tags
        template.has_resource_properties("AWS::EC2::VPC", {
            "Tags": assertions.Match.array_with([
                {
                    "Key": "Project",
                    "Value": "CostOptimizedBatchProcessing",
                },
                {
                    "Key": "Environment",
                    "Value": "demo",
                },
            ]),
        })


if __name__ == "__main__":
    pytest.main([__file__])