#!/usr/bin/env python3
"""
CDK Python application for AutoML Solutions with Amazon SageMaker Autopilot.

This application creates the infrastructure needed for automated machine learning
using SageMaker Autopilot, including S3 buckets, IAM roles, and optional endpoints.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_iam as iam,
    aws_sagemaker as sagemaker,
    aws_logs as logs,
)
from constructs import Construct


class AutoMLSageMakerAutopilotStack(Stack):
    """
    CDK Stack for AutoML Solutions with Amazon SageMaker Autopilot.
    
    This stack creates:
    - S3 bucket for input data and model artifacts
    - IAM role for SageMaker Autopilot with appropriate permissions
    - CloudWatch log group for monitoring
    - Optional: SageMaker model and endpoint for real-time inference
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        deploy_endpoint: bool = False,
        endpoint_instance_type: str = "ml.m5.large",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.addr[:8].lower()
        
        # Create S3 bucket for data and model artifacts
        self.data_bucket = s3.Bucket(
            self,
            "AutoMLDataBucket",
            bucket_name=f"sagemaker-autopilot-{self.account}-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    noncurrent_version_expiration=Duration.days(30),
                    abort_incomplete_multipart_uploads_after=Duration.days(7),
                )
            ],
        )

        # Create IAM role for SageMaker Autopilot
        self.autopilot_role = iam.Role(
            self,
            "AutopilotExecutionRole",
            role_name=f"SageMakerAutopilotRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="IAM role for SageMaker Autopilot to access required AWS services",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
            ],
        )

        # Add custom inline policy for S3 access
        self.autopilot_role.add_to_policy(
            iam.PolicyStatement(
                sid="S3BucketAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add CloudWatch Logs permissions
        self.autopilot_role.add_to_policy(
            iam.PolicyStatement(
                sid="CloudWatchLogsAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/sagemaker/*",
                ],
            )
        )

        # Create CloudWatch log group for AutoML jobs
        self.log_group = logs.LogGroup(
            self,
            "AutoMLLogGroup",
            log_group_name=f"/aws/sagemaker/autopilot/automl-{unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Conditional deployment of SageMaker model and endpoint
        if deploy_endpoint:
            self._create_inference_infrastructure(
                unique_suffix=unique_suffix,
                instance_type=endpoint_instance_type,
            )

        # Add tags to all resources
        Tags.of(self).add("Purpose", "AutoML-SageMaker-Autopilot")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("Recipe", "automl-solutions-amazon-sagemaker-autopilot")
        Tags.of(self).add("CostCenter", "ML-Engineering")

        # Create stack outputs
        self._create_outputs(unique_suffix)

    def _create_inference_infrastructure(
        self,
        unique_suffix: str,
        instance_type: str,
    ) -> None:
        """
        Create SageMaker model and endpoint for real-time inference.
        
        Args:
            unique_suffix: Unique identifier for resource naming
            instance_type: EC2 instance type for the endpoint
        """
        # Note: In a real scenario, you would need to provide the model artifact
        # and container image after the Autopilot job completes. This is a placeholder
        # structure that would be updated with actual model details.
        
        # Create endpoint configuration
        self.endpoint_config = sagemaker.CfnEndpointConfig(
            self,
            "AutoMLEndpointConfig",
            endpoint_config_name=f"autopilot-endpoint-config-{unique_suffix}",
            production_variants=[
                sagemaker.CfnEndpointConfig.ProductionVariantProperty(
                    variant_name="primary",
                    model_name=f"autopilot-model-{unique_suffix}",
                    initial_instance_count=1,
                    instance_type=instance_type,
                    initial_variant_weight=1.0,
                )
            ],
            tags=[
                cdk.CfnTag(key="Purpose", value="AutoML-Real-Time-Inference"),
                cdk.CfnTag(key="Environment", value="Development"),
            ],
        )

        # Create SageMaker endpoint
        self.endpoint = sagemaker.CfnEndpoint(
            self,
            "AutoMLEndpoint",
            endpoint_name=f"autopilot-endpoint-{unique_suffix}",
            endpoint_config_name=self.endpoint_config.endpoint_config_name,
            tags=[
                cdk.CfnTag(key="Purpose", value="AutoML-Real-Time-Inference"),
                cdk.CfnTag(key="Environment", value="Development"),
            ],
        )

        # Ensure endpoint depends on endpoint configuration
        self.endpoint.add_dependency(self.endpoint_config)

    def _create_outputs(self, unique_suffix: str) -> None:
        """
        Create CloudFormation stack outputs.
        
        Args:
            unique_suffix: Unique identifier for resource naming
        """
        # S3 bucket outputs
        cdk.CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for AutoML data and artifacts",
            export_name=f"AutoML-DataBucket-{unique_suffix}",
        )

        cdk.CfnOutput(
            self,
            "DataBucketArn",
            value=self.data_bucket.bucket_arn,
            description="ARN of the S3 bucket for AutoML data",
            export_name=f"AutoML-DataBucketArn-{unique_suffix}",
        )

        # IAM role outputs
        cdk.CfnOutput(
            self,
            "AutopilotRoleArn",
            value=self.autopilot_role.role_arn,
            description="ARN of the IAM role for SageMaker Autopilot",
            export_name=f"AutoML-AutopilotRole-{unique_suffix}",
        )

        cdk.CfnOutput(
            self,
            "AutopilotRoleName",
            value=self.autopilot_role.role_name,
            description="Name of the IAM role for SageMaker Autopilot",
            export_name=f"AutoML-AutopilotRoleName-{unique_suffix}",
        )

        # CloudWatch log group output
        cdk.CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for AutoML jobs",
            export_name=f"AutoML-LogGroup-{unique_suffix}",
        )

        # Conditional endpoint outputs
        if hasattr(self, 'endpoint'):
            cdk.CfnOutput(
                self,
                "EndpointName",
                value=self.endpoint.endpoint_name,
                description="Name of the SageMaker endpoint for real-time inference",
                export_name=f"AutoML-EndpointName-{unique_suffix}",
            )

        # Usage instructions output
        cdk.CfnOutput(
            self,
            "UsageInstructions",
            value=(
                f"Use 'aws sagemaker create-auto-ml-job-v2' with role ARN: "
                f"{self.autopilot_role.role_arn} and S3 bucket: {self.data_bucket.bucket_name}"
            ),
            description="Instructions for using the AutoML infrastructure",
        )


class AutoMLSageMakerAutopilotApp(cdk.App):
    """
    CDK Application for AutoML Solutions with Amazon SageMaker Autopilot.
    """

    def __init__(self):
        super().__init__()

        # Get configuration from environment variables or context
        deploy_endpoint = self.node.try_get_context("deploy_endpoint") or False
        endpoint_instance_type = self.node.try_get_context("endpoint_instance_type") or "ml.m5.large"
        
        # Get AWS environment from environment variables
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Create the stack
        AutoMLSageMakerAutopilotStack(
            self,
            "AutoMLSageMakerAutopilotStack",
            deploy_endpoint=deploy_endpoint,
            endpoint_instance_type=endpoint_instance_type,
            env=Environment(account=account, region=region),
            description="Infrastructure for AutoML Solutions with Amazon SageMaker Autopilot",
        )


# Create and run the CDK application
app = AutoMLSageMakerAutopilotApp()
app.synth()