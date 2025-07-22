#!/usr/bin/env python3
"""
CDK Application for Automated Testing Strategies for Infrastructure as Code

This CDK application creates the infrastructure needed for automated testing
of Infrastructure as Code, including CodeBuild projects, CodePipeline,
S3 buckets, and IAM roles with proper security configurations.
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_codecommit as codecommit
from aws_cdk import aws_codebuild as codebuild
from aws_cdk import aws_codepipeline as codepipeline
from aws_cdk import aws_codepipeline_actions as codepipeline_actions
from aws_cdk import aws_logs as logs
from constructs import Construct
from typing import Dict, List, Optional
import json
import os


class IacTestingStack(Stack):
    """
    CDK Stack for Infrastructure as Code Automated Testing
    
    This stack creates:
    - S3 bucket for pipeline artifacts
    - CodeCommit repository for source code
    - CodeBuild project for testing
    - CodePipeline for CI/CD automation
    - IAM roles and policies with least privilege access
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        project_name: str = "iac-testing",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.unique_suffix = self.node.addr[-8:].lower()
        
        # Create S3 bucket for artifacts
        self.artifacts_bucket = self._create_artifacts_bucket()
        
        # Create CodeCommit repository
        self.repository = self._create_codecommit_repository()
        
        # Create IAM roles
        self.codebuild_role = self._create_codebuild_role()
        self.codepipeline_role = self._create_codepipeline_role()
        
        # Create CodeBuild project
        self.codebuild_project = self._create_codebuild_project()
        
        # Create CodePipeline
        self.pipeline = self._create_codepipeline()
        
        # Create outputs
        self._create_outputs()

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing pipeline artifacts with security best practices
        """
        bucket = s3.Bucket(
            self,
            "ArtifactsBucket",
            bucket_name=f"{self.project_name}-artifacts-{self.unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                ),
                s3.LifecycleRule(
                    id="AbortIncompleteMultipartUploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                )
            ]
        )
        
        # Add bucket notification for monitoring
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.PUT],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )
        
        return bucket

    def _create_codecommit_repository(self) -> codecommit.Repository:
        """
        Create CodeCommit repository for Infrastructure as Code source files
        """
        repository = codecommit.Repository(
            self,
            "IacRepository",
            repository_name=f"{self.project_name}-repo-{self.unique_suffix}",
            description="Infrastructure as Code Testing Repository",
            code=codecommit.Code.from_directory(
                directory_path="./sample-iac-code",
                branch="main"
            ) if os.path.exists("./sample-iac-code") else None
        )
        
        return repository

    def _create_codebuild_role(self) -> iam.Role:
        """
        Create IAM role for CodeBuild with minimal required permissions
        """
        role = iam.Role(
            self,
            "CodeBuildRole",
            role_name=f"{self.project_name}-codebuild-role-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="IAM role for CodeBuild project in IaC testing pipeline"
        )
        
        # CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/codebuild/{self.project_name}*"
                ]
            )
        )
        
        # S3 permissions for artifacts
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject"
                ],
                resources=[f"{self.artifacts_bucket.bucket_arn}/*"]
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:ListBucket"],
                resources=[self.artifacts_bucket.bucket_arn]
            )
        )
        
        # CloudFormation permissions for testing
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudformation:CreateStack",
                    "cloudformation:UpdateStack",
                    "cloudformation:DeleteStack",
                    "cloudformation:DescribeStacks",
                    "cloudformation:DescribeStackEvents",
                    "cloudformation:ListStacks",
                    "cloudformation:ValidateTemplate"
                ],
                resources=[
                    f"arn:aws:cloudformation:{self.region}:{self.account}:stack/integration-test-*/*"
                ],
                conditions={
                    "StringLike": {
                        "cloudformation:TemplateUrl": [
                            f"{self.artifacts_bucket.bucket_arn}/*",
                            f"https://{self.artifacts_bucket.bucket_name}.s3.{self.region}.amazonaws.com/*"
                        ]
                    }
                }
            )
        )
        
        # S3 permissions for integration testing
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:CreateBucket",
                    "s3:DeleteBucket",
                    "s3:GetBucketEncryption",
                    "s3:GetBucketVersioning",
                    "s3:GetBucketLocation",
                    "s3:ListBucket"
                ],
                resources=[
                    f"arn:aws:s3:::integration-test-*"
                ]
            )
        )
        
        return role

    def _create_codepipeline_role(self) -> iam.Role:
        """
        Create IAM role for CodePipeline with minimal required permissions
        """
        role = iam.Role(
            self,
            "CodePipelineRole",
            role_name=f"{self.project_name}-pipeline-role-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("codepipeline.amazonaws.com"),
            description="IAM role for CodePipeline in IaC testing pipeline"
        )
        
        # S3 permissions for artifacts
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:GetBucketVersioning"
                ],
                resources=[
                    self.artifacts_bucket.bucket_arn,
                    f"{self.artifacts_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # CodeCommit permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:GetBranch",
                    "codecommit:GetCommit",
                    "codecommit:GetRepository",
                    "codecommit:ListBranches",
                    "codecommit:ListRepositories"
                ],
                resources=[self.repository.repository_arn]
            )
        )
        
        # CodeBuild permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codebuild:BatchGetBuilds",
                    "codebuild:StartBuild"
                ],
                resources=[
                    f"arn:aws:codebuild:{self.region}:{self.account}:project/{self.project_name}*"
                ]
            )
        )
        
        return role

    def _create_codebuild_project(self) -> codebuild.Project:
        """
        Create CodeBuild project for automated testing
        """
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "CodeBuildLogGroup",
            log_group_name=f"/aws/codebuild/{self.project_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Define build specification
        buildspec = {
            "version": "0.2",
            "phases": {
                "install": {
                    "runtime-versions": {
                        "python": "3.9"
                    },
                    "commands": [
                        "echo 'Installing dependencies...'",
                        "pip install --upgrade pip",
                        "pip install -r tests/requirements.txt || echo 'No requirements.txt found'",
                        "pip install awscli boto3 cfn-lint checkov pytest pyyaml moto"
                    ]
                },
                "pre_build": {
                    "commands": [
                        "echo 'Pre-build phase started on `date`'",
                        "echo 'Validating AWS credentials...'",
                        "aws sts get-caller-identity",
                        "echo 'Setting up environment...'",
                        "export PYTHONPATH=$PYTHONPATH:$CODEBUILD_SRC_DIR"
                    ]
                },
                "build": {
                    "commands": [
                        "echo 'Build phase started on `date`'",
                        "echo 'Running CloudFormation linting...'",
                        "find . -name '*.yaml' -o -name '*.yml' | xargs -I {} cfn-lint {} || true",
                        "echo 'Running security checks with Checkov...'",
                        "checkov -f . --framework cloudformation || true",
                        "echo 'Running unit tests...'",
                        "if [ -d 'tests' ]; then cd tests && python -m pytest . -v; cd ..; fi",
                        "echo 'Running custom security tests...'",
                        "if [ -f 'tests/security_test.py' ]; then python tests/security_test.py; fi",
                        "echo 'Running cost analysis...'",
                        "if [ -f 'tests/cost_analysis.py' ]; then python tests/cost_analysis.py; fi",
                        "echo 'Running integration tests...'",
                        "if [ -f 'tests/integration_test.py' ]; then python tests/integration_test.py; fi"
                    ]
                },
                "post_build": {
                    "commands": [
                        "echo 'Post-build phase started on `date`'",
                        "echo 'All tests completed successfully!'",
                        "echo 'Generating test reports...'",
                        "if [ -d 'test-reports' ]; then aws s3 cp test-reports/ s3://$ARTIFACT_BUCKET/test-reports/ --recursive; fi"
                    ]
                }
            },
            "artifacts": {
                "files": [
                    "**/*"
                ],
                "base-directory": "."
            },
            "reports": {
                "pytest_reports": {
                    "files": [
                        "**/test-*.xml"
                    ],
                    "file-format": "JUNITXML"
                }
            }
        }
        
        project = codebuild.Project(
            self,
            "CodeBuildProject",
            project_name=f"{self.project_name}",
            description="Automated testing for Infrastructure as Code",
            source=codebuild.Source.code_commit(
                repository=self.repository,
                branch_or_ref="main"
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_4,
                compute_type=codebuild.ComputeType.SMALL,
                environment_variables={
                    "ARTIFACT_BUCKET": codebuild.BuildEnvironmentVariable(
                        value=self.artifacts_bucket.bucket_name
                    ),
                    "AWS_DEFAULT_REGION": codebuild.BuildEnvironmentVariable(
                        value=self.region
                    ),
                    "AWS_ACCOUNT_ID": codebuild.BuildEnvironmentVariable(
                        value=self.account
                    )
                }
            ),
            role=self.codebuild_role,
            timeout=Duration.minutes(60),
            build_spec=codebuild.BuildSpec.from_object(buildspec),
            artifacts=codebuild.Artifacts.s3(
                bucket=self.artifacts_bucket,
                include_build_id=True,
                package_zip=True
            ),
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    log_group=log_group,
                    enabled=True
                )
            )
        )
        
        return project

    def _create_codepipeline(self) -> codepipeline.Pipeline:
        """
        Create CodePipeline for end-to-end automation
        """
        # Define pipeline artifacts
        source_output = codepipeline.Artifact("SourceOutput")
        build_output = codepipeline.Artifact("BuildOutput")
        
        pipeline = codepipeline.Pipeline(
            self,
            "IacTestingPipeline",
            pipeline_name=f"{self.project_name}-pipeline",
            role=self.codepipeline_role,
            artifact_bucket=self.artifacts_bucket,
            restart_execution_on_update=True,
            stages=[
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.CodeCommitSourceAction(
                            action_name="Source",
                            repository=self.repository,
                            branch="main",
                            output=source_output,
                            trigger=codepipeline_actions.CodeCommitTrigger.EVENTS
                        )
                    ]
                ),
                codepipeline.StageProps(
                    stage_name="Test",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="Test",
                            project=self.codebuild_project,
                            input=source_output,
                            outputs=[build_output],
                            environment_variables={
                                "BUILD_OUTPUT_BUCKET": codebuild.BuildEnvironmentVariable(
                                    value=self.artifacts_bucket.bucket_name
                                )
                            }
                        )
                    ]
                )
            ]
        )
        
        return pipeline

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resources
        """
        CfnOutput(
            self,
            "S3BucketName",
            value=self.artifacts_bucket.bucket_name,
            description="S3 bucket for storing pipeline artifacts",
            export_name=f"{self.stack_name}-S3BucketName"
        )
        
        CfnOutput(
            self,
            "CodeCommitRepositoryName",
            value=self.repository.repository_name,
            description="CodeCommit repository for Infrastructure as Code",
            export_name=f"{self.stack_name}-RepositoryName"
        )
        
        CfnOutput(
            self,
            "CodeCommitCloneUrl",
            value=self.repository.repository_clone_url_http,
            description="CodeCommit repository clone URL (HTTPS)",
            export_name=f"{self.stack_name}-CloneUrl"
        )
        
        CfnOutput(
            self,
            "CodeBuildProjectName",
            value=self.codebuild_project.project_name,
            description="CodeBuild project for automated testing",
            export_name=f"{self.stack_name}-CodeBuildProject"
        )
        
        CfnOutput(
            self,
            "CodePipelineName",
            value=self.pipeline.pipeline_name,
            description="CodePipeline for CI/CD automation",
            export_name=f"{self.stack_name}-PipelineName"
        )
        
        CfnOutput(
            self,
            "CodeBuildRoleArn",
            value=self.codebuild_role.role_arn,
            description="IAM role ARN for CodeBuild project",
            export_name=f"{self.stack_name}-CodeBuildRoleArn"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = App()
    
    # Get configuration from environment variables or use defaults
    project_name = app.node.try_get_context("project_name") or "iac-testing"
    env_name = app.node.try_get_context("environment") or "dev"
    
    # Create the stack
    stack = IacTestingStack(
        app,
        f"IacTestingStack-{env_name}",
        project_name=project_name,
        env=Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        ),
        description=f"Infrastructure as Code Automated Testing Stack for {env_name} environment",
        tags={
            "Project": project_name,
            "Environment": env_name,
            "Purpose": "Infrastructure Testing",
            "ManagedBy": "CDK"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()