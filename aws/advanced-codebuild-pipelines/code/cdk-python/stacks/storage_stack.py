"""
Storage Stack for Advanced CodeBuild Pipeline

This stack creates the storage infrastructure required for the pipeline:
- S3 buckets for caching and artifacts
- ECR repository for container images
- Lifecycle policies for cost optimization
- Security configurations
"""

from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    aws_ecr as ecr,
    aws_s3 as s3,
    aws_iam as iam,
)
from constructs import Construct


class StorageStack(Stack):
    """
    Stack containing storage infrastructure for the advanced CodeBuild pipeline
    
    This stack creates:
    - S3 bucket for build caching with lifecycle policies
    - S3 bucket for build artifacts with encryption
    - ECR repository for container images with vulnerability scanning
    - IAM policies for secure access
    """
    
    def __init__(
        self, 
        scope: Construct, 
        construct_id: str,
        project_name: str,
        environment: str,
        cache_retention_days: int = 30,
        artifact_retention_days: int = 90,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        self.environment = environment
        
        # Create S3 bucket for build caching
        self.cache_bucket = self._create_cache_bucket(cache_retention_days)
        
        # Create S3 bucket for build artifacts
        self.artifact_bucket = self._create_artifact_bucket(artifact_retention_days)
        
        # Create ECR repository for container images
        self.ecr_repository = self._create_ecr_repository()
        
        # Create IAM role for CodeBuild projects
        self.codebuild_role = self._create_codebuild_role()
        
        # Output important values
        self._create_outputs()
    
    def _create_cache_bucket(self, retention_days: int) -> s3.Bucket:
        """
        Create S3 bucket for build caching with optimized lifecycle policies
        
        Args:
            retention_days: Number of days to retain cache objects
            
        Returns:
            S3 Bucket for caching
        """
        bucket = s3.Bucket(
            self,
            "CacheBucket",
            bucket_name=f"{self.project_name}-cache-{self.environment}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                # Cache cleanup rule
                s3.LifecycleRule(
                    id="CacheCleanup",
                    enabled=True,
                    prefix="cache/",
                    expiration=Duration.days(retention_days),
                    noncurrent_version_expiration=Duration.days(7),
                ),
                # Dependency cache rule (longer retention)
                s3.LifecycleRule(
                    id="DependencyCache",
                    enabled=True,
                    prefix="deps/",
                    expiration=Duration.days(retention_days * 3),  # 90 days default
                    noncurrent_version_expiration=Duration.days(14),
                ),
                # Transition to IA after 30 days
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ]
        )
        
        # Add CORS configuration for web access
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )
        
        return bucket
    
    def _create_artifact_bucket(self, retention_days: int) -> s3.Bucket:
        """
        Create S3 bucket for build artifacts with encryption and lifecycle management
        
        Args:
            retention_days: Number of days to retain artifact objects
            
        Returns:
            S3 Bucket for artifacts
        """
        bucket = s3.Bucket(
            self,
            "ArtifactBucket",
            bucket_name=f"{self.project_name}-artifacts-{self.environment}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                # Artifact cleanup rule
                s3.LifecycleRule(
                    id="ArtifactCleanup",
                    enabled=True,
                    expiration=Duration.days(retention_days),
                    noncurrent_version_expiration=Duration.days(30),
                ),
                # Reports have shorter retention
                s3.LifecycleRule(
                    id="ReportsCleanup",
                    enabled=True,
                    prefix="reports/",
                    expiration=Duration.days(retention_days // 2),  # Half the artifact retention
                ),
                # Transition strategy for cost optimization
                s3.LifecycleRule(
                    id="CostOptimization",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        # Add notification configuration for artifact uploads
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            destinations=[]  # Can be extended with SNS/SQS/Lambda destinations
        )
        
        return bucket
    
    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create ECR repository for container images with security scanning
        
        Returns:
            ECR Repository for container images
        """
        repository = ecr.Repository(
            self,
            "ContainerRepository",
            repository_name=f"{self.project_name}-{self.environment}",
            image_scan_on_push=True,
            encryption=ecr.RepositoryEncryption.AES_256,
            removal_policy=RemovalPolicy.DESTROY,
            lifecycle_rules=[
                # Keep last 10 tagged images
                ecr.LifecycleRule(
                    description="Keep last 10 tagged images",
                    rule_priority=1,
                    selection=ecr.TagStatus.TAGGED,
                    max_image_count=10,
                ),
                # Keep untagged images for 1 day
                ecr.LifecycleRule(
                    description="Keep untagged images for 1 day",
                    rule_priority=2,
                    selection=ecr.TagStatus.UNTAGGED,
                    max_image_age=Duration.days(1),
                )
            ]
        )
        
        return repository
    
    def _create_codebuild_role(self) -> iam.Role:
        """
        Create IAM role for CodeBuild projects with comprehensive permissions
        
        Returns:
            IAM Role for CodeBuild projects
        """
        role = iam.Role(
            self,
            "CodeBuildRole",
            role_name=f"{self.project_name}-codebuild-role-{self.environment}",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="IAM role for advanced CodeBuild pipeline projects",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess"),
            ]
        )
        
        # S3 permissions for cache and artifacts
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation",
                ],
                resources=[
                    self.cache_bucket.bucket_arn,
                    f"{self.cache_bucket.bucket_arn}/*",
                    self.artifact_bucket.bucket_arn,
                    f"{self.artifact_bucket.bucket_arn}/*",
                ]
            )
        )
        
        # ECR permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:GetAuthorizationToken",
                    "ecr:PutImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                ],
                resources=["*"]
            )
        )
        
        # CodeBuild permissions for reports and metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codebuild:CreateReportGroup",
                    "codebuild:CreateReport",
                    "codebuild:UpdateReport",
                    "codebuild:BatchPutTestCases",
                    "codebuild:BatchPutCodeCoverages",
                    "codebuild:StartBuild",
                    "codebuild:BatchGetBuilds",
                ],
                resources=["*"]
            )
        )
        
        # CloudWatch permissions for custom metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"]
            )
        )
        
        return role
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        cdk.CfnOutput(
            self,
            "CacheBucketName",
            value=self.cache_bucket.bucket_name,
            description="Name of the S3 bucket for build caching",
            export_name=f"{self.stack_name}-CacheBucketName"
        )
        
        cdk.CfnOutput(
            self,
            "ArtifactBucketName",
            value=self.artifact_bucket.bucket_name,
            description="Name of the S3 bucket for build artifacts",
            export_name=f"{self.stack_name}-ArtifactBucketName"
        )
        
        cdk.CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository for container images",
            export_name=f"{self.stack_name}-ECRRepositoryURI"
        )
        
        cdk.CfnOutput(
            self,
            "CodeBuildRoleArn",
            value=self.codebuild_role.role_arn,
            description="ARN of the IAM role for CodeBuild projects",
            export_name=f"{self.stack_name}-CodeBuildRoleArn"
        )