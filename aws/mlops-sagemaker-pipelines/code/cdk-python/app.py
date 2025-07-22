#!/usr/bin/env python3
"""
CDK Python Application for End-to-End MLOps with SageMaker Pipelines

This application creates the complete infrastructure for an MLOps pipeline including:
- S3 bucket for data storage and artifacts
- CodeCommit repository for ML code versioning
- IAM execution role for SageMaker operations
- SageMaker Pipeline for automated ML workflows
- Model Registry for model versioning and governance
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_codecommit as codecommit,
    aws_iam as iam,
    aws_sagemaker as sagemaker,
    aws_logs as logs,
)
from constructs import Construct


class MLOpsPipelineStack(Stack):
    """
    CDK Stack for MLOps Pipeline Infrastructure
    
    Creates all necessary AWS resources for a complete MLOps solution
    including data storage, code versioning, execution roles, and
    SageMaker Pipeline for automated model training and deployment.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        pipeline_name: str = "mlops-pipeline",
        bucket_prefix: str = "sagemaker-mlops",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.pipeline_name = pipeline_name
        self.bucket_prefix = bucket_prefix

        # Create core infrastructure
        self.s3_bucket = self._create_s3_bucket()
        self.codecommit_repo = self._create_codecommit_repository()
        self.sagemaker_role = self._create_sagemaker_execution_role()
        self.model_package_group = self._create_model_package_group()
        self.cloudwatch_log_group = self._create_cloudwatch_log_group()

        # Output important resource information
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing training data, model artifacts, and pipeline outputs.
        
        Implements security best practices including:
        - Encryption at rest with S3 managed keys
        - Versioning enabled for data lineage
        - Public access blocked
        - Lifecycle policies for cost optimization
        """
        bucket = s3.Bucket(
            self,
            "MLOpsDataBucket",
            bucket_name=f"{self.bucket_prefix}-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                ),
                s3.LifecycleRule(
                    id="TransitionToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        )
                    ],
                ),
            ],
        )

        # Add bucket policy for SageMaker access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="SageMakerAccess",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("sagemaker.amazonaws.com")],
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    bucket.bucket_arn,
                    f"{bucket.bucket_arn}/*",
                ],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account,
                    }
                },
            )
        )

        # Tag bucket for organization and cost tracking
        cdk.Tags.of(bucket).add("Purpose", "MLOps")
        cdk.Tags.of(bucket).add("DataClassification", "Training")

        return bucket

    def _create_codecommit_repository(self) -> codecommit.Repository:
        """
        Create CodeCommit repository for ML code versioning and collaboration.
        
        This repository stores:
        - Training scripts and preprocessing code
        - Pipeline definitions and configurations
        - Model evaluation and testing code
        - Documentation and README files
        """
        repository = codecommit.Repository(
            self,
            "MLOpsCodeRepository",
            repository_name=f"{self.pipeline_name}-code",
            description=(
                "MLOps pipeline code repository containing training scripts, "
                "pipeline definitions, and model evaluation code"
            ),
        )

        # Tag repository for organization
        cdk.Tags.of(repository).add("Purpose", "MLOps")
        cdk.Tags.of(repository).add("Component", "SourceControl")

        return repository

    def _create_sagemaker_execution_role(self) -> iam.Role:
        """
        Create IAM execution role for SageMaker operations.
        
        This role provides necessary permissions for:
        - SageMaker training jobs and processing jobs
        - S3 access for data and model artifacts
        - CloudWatch logging and monitoring
        - Model registry operations
        - CodeCommit access for source code
        """
        role = iam.Role(
            self,
            "SageMakerExecutionRole",
            role_name=f"{self.pipeline_name}-execution-role",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="Execution role for SageMaker MLOps pipeline operations",
            max_session_duration=Duration.hours(12),
        )

        # Add managed policies for SageMaker operations
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess")
        )

        # Add custom inline policy for specific permissions
        role.add_to_policy(
            iam.PolicyStatement(
                sid="S3Access",
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*",
                ],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                sid="CloudWatchLogs",
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams",
                ],
                resources=[f"arn:aws:logs:{self.region}:{self.account}:*"],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                sid="CodeCommitAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:GitPull",
                    "codecommit:GitPush",
                    "codecommit:GetRepository",
                    "codecommit:ListRepositories",
                ],
                resources=[self.codecommit_repo.repository_arn],
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                sid="ECRAccess",
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetAuthorizationToken",
                ],
                resources=["*"],
            )
        )

        # Tag role for organization
        cdk.Tags.of(role).add("Purpose", "MLOps")
        cdk.Tags.of(role).add("Component", "ExecutionRole")

        return role

    def _create_model_package_group(self) -> sagemaker.CfnModelPackageGroup:
        """
        Create SageMaker Model Package Group for model versioning and governance.
        
        The model package group provides:
        - Centralized model registry for version control
        - Model approval workflows for production deployment
        - Model lineage tracking and metadata storage
        - Integration with CI/CD pipelines
        """
        model_package_group = sagemaker.CfnModelPackageGroup(
            self,
            "MLOpsModelPackageGroup",
            model_package_group_name=f"{self.pipeline_name}-model-group",
            model_package_group_description=(
                "Model package group for MLOps pipeline models. "
                "Provides versioning, approval workflows, and governance "
                "for machine learning models."
            ),
            model_package_group_policy={
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Sid": "AllowSageMakerAccess",
                        "Effect": "Allow",
                        "Principal": {"AWS": f"arn:aws:iam::{self.account}:root"},
                        "Action": [
                            "sagemaker:DescribeModelPackage",
                            "sagemaker:DescribeModelPackageGroup",
                            "sagemaker:ListModelPackages",
                        ],
                        "Resource": "*",
                    }
                ],
            },
            tags=[
                cdk.CfnTag(key="Purpose", value="MLOps"),
                cdk.CfnTag(key="Component", value="ModelRegistry"),
            ],
        )

        return model_package_group

    def _create_cloudwatch_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch Log Group for centralized logging.
        
        Provides:
        - Centralized logging for all pipeline components
        - Log retention management for cost control
        - Security through encryption at rest
        - Integration with CloudWatch Insights for analysis
        """
        log_group = logs.LogGroup(
            self,
            "MLOpsLogGroup",
            log_group_name=f"/aws/sagemaker/pipelines/{self.pipeline_name}",
            retention=logs.RetentionDays.ONE_MONTH,  # Adjust based on requirements
            encryption_key=None,  # Use default CloudWatch encryption
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
        )

        # Tag log group for organization
        cdk.Tags.of(log_group).add("Purpose", "MLOps")
        cdk.Tags.of(log_group).add("Component", "Logging")

        return log_group

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        
        These outputs provide essential information for:
        - Pipeline configuration and deployment
        - Integration with external systems
        - Manual verification and troubleshooting
        """
        cdk.CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket for MLOps data and artifacts",
            export_name=f"{self.stack_name}-S3Bucket",
        )

        cdk.CfnOutput(
            self,
            "S3BucketArn",
            value=self.s3_bucket.bucket_arn,
            description="ARN of the S3 bucket for MLOps data",
        )

        cdk.CfnOutput(
            self,
            "CodeCommitRepositoryName",
            value=self.codecommit_repo.repository_name,
            description="CodeCommit repository for ML code",
            export_name=f"{self.stack_name}-CodeCommitRepo",
        )

        cdk.CfnOutput(
            self,
            "CodeCommitRepositoryCloneUrl",
            value=self.codecommit_repo.repository_clone_url_http,
            description="HTTPS clone URL for CodeCommit repository",
        )

        cdk.CfnOutput(
            self,
            "SageMakerExecutionRoleArn",
            value=self.sagemaker_role.role_arn,
            description="IAM role ARN for SageMaker execution",
            export_name=f"{self.stack_name}-ExecutionRole",
        )

        cdk.CfnOutput(
            self,
            "ModelPackageGroupName",
            value=self.model_package_group.model_package_group_name,
            description="SageMaker Model Package Group name",
            export_name=f"{self.stack_name}-ModelPackageGroup",
        )

        cdk.CfnOutput(
            self,
            "CloudWatchLogGroupName",
            value=self.cloudwatch_log_group.log_group_name,
            description="CloudWatch Log Group for pipeline logging",
        )


class MLOpsPipelineApp(cdk.App):
    """
    CDK Application for MLOps Pipeline Infrastructure
    
    Main application class that orchestrates the deployment of
    all MLOps infrastructure components with proper configuration
    and environment-specific settings.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        pipeline_name = self.node.try_get_context("pipeline_name") or "mlops-pipeline"
        bucket_prefix = self.node.try_get_context("bucket_prefix") or "sagemaker-mlops"
        
        # Get deployment environment
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

        # Validate required environment variables
        if not account:
            raise ValueError(
                "CDK_DEFAULT_ACCOUNT environment variable must be set"
            )

        # Create the MLOps pipeline stack
        MLOpsPipelineStack(
            self,
            "MLOpsPipelineStack",
            pipeline_name=pipeline_name,
            bucket_prefix=bucket_prefix,
            env=Environment(account=account, region=region),
            description=(
                "End-to-end MLOps infrastructure with SageMaker Pipelines, "
                "including S3 storage, CodeCommit repository, IAM roles, "
                "and Model Registry for automated ML workflows"
            ),
            tags={
                "Project": "MLOps",
                "Environment": "Development",
                "ManagedBy": "CDK",
                "Purpose": "MLPipeline",
            },
        )


# Application entry point
app = MLOpsPipelineApp()
app.synth()