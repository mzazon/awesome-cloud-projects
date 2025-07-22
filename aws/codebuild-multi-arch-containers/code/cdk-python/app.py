#!/usr/bin/env python3
"""
CDK Python application for multi-architecture container image builds with CodeBuild and ECR.

This application deploys infrastructure to support building multi-architecture container images
that run on both ARM64 and x86_64 architectures using AWS CodeBuild and Amazon ECR.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_codebuild as codebuild,
    aws_ecr as ecr,
    aws_iam as iam,
    aws_s3 as s3,
    RemovalPolicy,
    CfnOutput,
    Duration,
)
from constructs import Construct
from typing import Dict, List, Optional


class MultiArchContainerStack(Stack):
    """
    Stack for deploying multi-architecture container build infrastructure.
    
    This stack creates:
    - Amazon ECR repository for storing multi-architecture images
    - IAM role for CodeBuild with necessary permissions
    - S3 bucket for storing source code
    - CodeBuild project configured for multi-architecture builds
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        project_name: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the multi-architecture container stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            project_name: Optional custom project name
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        self.project_name = project_name or f"multi-arch-build-{unique_suffix}"
        
        # Create ECR repository
        self.ecr_repository = self._create_ecr_repository()
        
        # Create S3 bucket for source code
        self.source_bucket = self._create_source_bucket()
        
        # Create IAM role for CodeBuild
        self.codebuild_role = self._create_codebuild_role()
        
        # Create CodeBuild project
        self.codebuild_project = self._create_codebuild_project()
        
        # Create outputs
        self._create_outputs()

    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create ECR repository for storing multi-architecture container images.
        
        Returns:
            ECR repository instance
        """
        repository = ecr.Repository(
            self,
            "ECRRepository",
            repository_name=f"sample-app-{self.project_name.split('-')[-1]}",
            image_scan_on_push=True,
            encryption=ecr.RepositoryEncryption.AES_256,
            removal_policy=RemovalPolicy.DESTROY,
            empty_on_delete=True,
        )
        
        # Add lifecycle policy to manage image retention
        repository.add_lifecycle_rule(
            description="Keep last 10 images",
            max_image_count=10,
            rule_priority=1,
        )
        
        return repository

    def _create_source_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing source code archives.
        
        Returns:
            S3 bucket instance
        """
        bucket = s3.Bucket(
            self,
            "SourceBucket",
            bucket_name=f"{self.project_name}-source-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
        )
        
        # Add lifecycle policy to manage object retention
        bucket.add_lifecycle_rule(
            id="DeleteOldVersions",
            expiration=Duration.days(30),
            noncurrent_version_expiration=Duration.days(7),
        )
        
        return bucket

    def _create_codebuild_role(self) -> iam.Role:
        """
        Create IAM role for CodeBuild with necessary permissions.
        
        Returns:
            IAM role instance
        """
        role = iam.Role(
            self,
            "CodeBuildRole",
            role_name=f"CodeBuildMultiArchRole-{self.project_name.split('-')[-1]}",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="IAM role for CodeBuild multi-architecture builds",
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/codebuild/*"
                ],
            )
        )
        
        # Add ECR permissions
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
                resources=["*"],
            )
        )
        
        # Add S3 permissions for source bucket
        self.source_bucket.grant_read(role)
        
        return role

    def _create_codebuild_project(self) -> codebuild.Project:
        """
        Create CodeBuild project for multi-architecture builds.
        
        Returns:
            CodeBuild project instance
        """
        # Define build environment variables
        environment_variables: Dict[str, codebuild.BuildEnvironmentVariable] = {
            "AWS_DEFAULT_REGION": codebuild.BuildEnvironmentVariable(
                value=self.region
            ),
            "AWS_ACCOUNT_ID": codebuild.BuildEnvironmentVariable(
                value=self.account
            ),
            "IMAGE_REPO_NAME": codebuild.BuildEnvironmentVariable(
                value=self.ecr_repository.repository_name
            ),
        }
        
        # Create buildspec for multi-architecture builds
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "phases": {
                "pre_build": {
                    "commands": [
                        "echo Logging in to Amazon ECR...",
                        "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com",
                        "REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME",
                        "COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)",
                        "IMAGE_TAG=${COMMIT_HASH:=latest}",
                        "echo Repository URI is $REPOSITORY_URI",
                        "echo Image tag is $IMAGE_TAG",
                    ]
                },
                "build": {
                    "commands": [
                        "echo Build started on $(date)",
                        "echo Building multi-architecture Docker image...",
                        "",
                        "# Create and use buildx builder",
                        "docker buildx create --name multiarch-builder --use --bootstrap",
                        "docker buildx inspect --bootstrap",
                        "",
                        "# Build and push multi-architecture image",
                        "docker buildx build --platform linux/amd64,linux/arm64 --tag $REPOSITORY_URI:latest --tag $REPOSITORY_URI:$IMAGE_TAG --push --cache-from type=local,src=/tmp/.buildx-cache --cache-to type=local,dest=/tmp/.buildx-cache-new,mode=max .",
                        "",
                        "# Move cache to prevent unbounded growth",
                        "rm -rf /tmp/.buildx-cache",
                        "mv /tmp/.buildx-cache-new /tmp/.buildx-cache",
                    ]
                },
                "post_build": {
                    "commands": [
                        "echo Build completed on $(date)",
                        "echo Pushing the Docker images...",
                        "docker buildx imagetools inspect $REPOSITORY_URI:latest",
                        "printf '{\"ImageURI\":\"%s\"}' $REPOSITORY_URI:latest > imageDetail.json",
                    ]
                },
            },
            "artifacts": {
                "files": ["imageDetail.json"]
            },
            "cache": {
                "paths": ["/tmp/.buildx-cache/**/*"]
            },
        })
        
        project = codebuild.Project(
            self,
            "CodeBuildProject",
            project_name=self.project_name,
            description="Multi-architecture container image build project",
            source=codebuild.Source.s3(
                bucket=self.source_bucket,
                path="source.zip",
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                compute_type=codebuild.ComputeType.MEDIUM,
                privileged=True,  # Required for Docker Buildx
                environment_variables=environment_variables,
            ),
            role=self.codebuild_role,
            timeout=Duration.minutes(60),
            cache=codebuild.Cache.local(
                codebuild.LocalCacheMode.DOCKER_LAYER,
                codebuild.LocalCacheMode.CUSTOM,
            ),
            build_spec=buildspec,
            artifacts=codebuild.Artifacts.no_artifacts(),
        )
        
        return project

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository for multi-architecture images",
            export_name=f"{self.stack_name}-ECRRepositoryURI",
        )
        
        CfnOutput(
            self,
            "CodeBuildProjectName",
            value=self.codebuild_project.project_name,
            description="Name of the CodeBuild project",
            export_name=f"{self.stack_name}-CodeBuildProjectName",
        )
        
        CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the S3 bucket for source code",
            export_name=f"{self.stack_name}-SourceBucketName",
        )
        
        CfnOutput(
            self,
            "CodeBuildRoleArn",
            value=self.codebuild_role.role_arn,
            description="ARN of the CodeBuild IAM role",
            export_name=f"{self.stack_name}-CodeBuildRoleArn",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get context values for customization
    project_name = app.node.try_get_context("project_name")
    
    # Create the stack
    MultiArchContainerStack(
        app,
        "MultiArchContainerStack",
        project_name=project_name,
        description="Multi-architecture container build infrastructure with CodeBuild and ECR",
        # Add tags for resource management
        tags={
            "Project": "MultiArchContainerBuild",
            "Environment": "Development",
            "Owner": "DevOps",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()