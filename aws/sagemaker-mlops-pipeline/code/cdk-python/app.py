#!/usr/bin/env python3
"""
AWS CDK Python application for Machine Learning Model Deployment Pipelines
with SageMaker and CodePipeline.

This application creates a comprehensive MLOps pipeline that automates
model training, validation, and deployment using Amazon SageMaker and
AWS CodePipeline. The solution provides continuous integration and
deployment for machine learning models while maintaining governance,
reproducibility, and monitoring throughout the model lifecycle.
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_codebuild as codebuild,
    aws_codepipeline as codepipeline,
    aws_codepipeline_actions as codepipeline_actions,
    aws_lambda as aws_lambda,
    aws_sagemaker as sagemaker,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct


class MLOpsPipelineStack(Stack):
    """
    Stack for MLOps Pipeline with SageMaker and CodePipeline.
    
    This stack creates:
    - S3 bucket for artifacts and training data
    - SageMaker Model Package Group for model registry
    - IAM roles for SageMaker, CodeBuild, CodePipeline, and Lambda
    - CodeBuild projects for training and testing
    - Lambda function for deployment
    - CodePipeline for orchestrating the ML workflow
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        project_name: str = "mlops-pipeline",
        model_package_group_name: str = "fraud-detection-models",
        **kwargs: Any
    ) -> None:
        """
        Initialize the MLOps Pipeline Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            project_name: Name prefix for project resources
            model_package_group_name: Name for SageMaker model package group
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.model_package_group_name = model_package_group_name

        # Create S3 bucket for artifacts
        self.artifacts_bucket = self._create_artifacts_bucket()

        # Create IAM roles
        self.sagemaker_role = self._create_sagemaker_execution_role()
        self.codebuild_role = self._create_codebuild_service_role()
        self.codepipeline_role = self._create_codepipeline_service_role()
        self.lambda_role = self._create_lambda_execution_role()

        # Create SageMaker Model Package Group
        self.model_package_group = self._create_model_package_group()

        # Create CodeBuild projects
        self.training_project = self._create_training_project()
        self.testing_project = self._create_testing_project()

        # Create Lambda deployment function
        self.deployment_function = self._create_deployment_function()

        # Create CodePipeline
        self.pipeline = self._create_ml_pipeline()

        # Create outputs
        self._create_outputs()

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing ML artifacts and training data."""
        bucket = s3.Bucket(
            self,
            "MLArtifactsBucket",
            bucket_name=f"sagemaker-mlops-{self.region}-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                ),
                s3.LifecycleRule(
                    id="DeleteIncompleteUploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                ),
            ],
        )

        # Add bucket policy for secure access
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="DenyInsecureConnections",
                effect=iam.Effect.DENY,
                principals=[iam.AnyPrincipal()],
                actions=["s3:*"],
                resources=[bucket.bucket_arn, bucket.arn_for_objects("*")],
                conditions={
                    "Bool": {"aws:SecureTransport": "false"}
                },
            )
        )

        return bucket

    def _create_sagemaker_execution_role(self) -> iam.Role:
        """Create IAM role for SageMaker training jobs and endpoints."""
        role = iam.Role(
            self,
            "SageMakerExecutionRole",
            role_name=f"SageMakerExecutionRole-{self.project_name}",
            assumed_by=iam.ServicePrincipal("sagemaker.amazonaws.com"),
            description="Execution role for SageMaker training jobs and endpoints",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
            ],
        )

        # Add custom policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.artifacts_bucket.bucket_arn,
                    self.artifacts_bucket.arn_for_objects("*"),
                ],
            )
        )

        # Add policy for CloudWatch logging
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_codebuild_service_role(self) -> iam.Role:
        """Create IAM role for CodeBuild projects."""
        role = iam.Role(
            self,
            "CodeBuildServiceRole",
            role_name=f"CodeBuildServiceRole-{self.project_name}",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="Service role for CodeBuild projects in ML pipeline",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
            ],
        )

        # Add S3 access policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.artifacts_bucket.bucket_arn,
                    self.artifacts_bucket.arn_for_objects("*"),
                ],
            )
        )

        # Add CloudWatch logs policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )

        # Add IAM pass role policy for SageMaker
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[self.sagemaker_role.role_arn],
            )
        )

        return role

    def _create_codepipeline_service_role(self) -> iam.Role:
        """Create IAM role for CodePipeline."""
        role = iam.Role(
            self,
            "CodePipelineServiceRole",
            role_name=f"CodePipelineServiceRole-{self.project_name}",
            assumed_by=iam.ServicePrincipal("codepipeline.amazonaws.com"),
            description="Service role for CodePipeline ML workflow orchestration",
        )

        # Add S3 access policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.artifacts_bucket.bucket_arn,
                    self.artifacts_bucket.arn_for_objects("*"),
                ],
            )
        )

        # Add CodeBuild access policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codebuild:BatchGetBuilds",
                    "codebuild:StartBuild",
                ],
                resources=["*"],
            )
        )

        # Add Lambda invoke policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["lambda:InvokeFunction"],
                resources=["*"],
            )
        )

        # Add SageMaker access policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sagemaker:DescribeModelPackage",
                    "sagemaker:ListModelPackages",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda deployment function."""
        role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"LambdaExecutionRole-{self.project_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for Lambda deployment function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSageMakerFullAccess"),
            ],
        )

        # Add CodePipeline access policy
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codepipeline:PutJobSuccessResult",
                    "codepipeline:PutJobFailureResult",
                ],
                resources=["*"],
            )
        )

        # Add IAM pass role policy for SageMaker
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["iam:PassRole"],
                resources=[self.sagemaker_role.role_arn],
            )
        )

        return role

    def _create_model_package_group(self) -> sagemaker.CfnModelPackageGroup:
        """Create SageMaker Model Package Group for model registry."""
        model_package_group = sagemaker.CfnModelPackageGroup(
            self,
            "ModelPackageGroup",
            model_package_group_name=self.model_package_group_name,
            model_package_group_description="Fraud detection model packages for MLOps pipeline",
            tags=[
                cdk.CfnTag(key="Project", value=self.project_name),
                cdk.CfnTag(key="Environment", value="Production"),
                cdk.CfnTag(key="ManagedBy", value="CDK"),
            ],
        )

        return model_package_group

    def _create_training_project(self) -> codebuild.Project:
        """Create CodeBuild project for model training."""
        # Create buildspec for training
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "phases": {
                "install": {
                    "runtime-versions": {"python": "3.9"},
                    "commands": [
                        "pip install boto3 scikit-learn pandas numpy sagemaker"
                    ]
                },
                "build": {
                    "commands": [
                        "echo 'Starting model training...'",
                        "python train.py"
                    ]
                }
            },
            "artifacts": {
                "files": ["model_package_arn.txt"]
            }
        })

        project = codebuild.Project(
            self,
            "TrainingProject",
            project_name=f"{self.project_name}-train",
            description="ML model training project",
            source=codebuild.Source.code_pipeline(build_spec=buildspec),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_5_0,
                compute_type=codebuild.ComputeType.MEDIUM,
                environment_variables={
                    "SAGEMAKER_ROLE_ARN": codebuild.BuildEnvironmentVariable(
                        value=self.sagemaker_role.role_arn
                    ),
                    "BUCKET_NAME": codebuild.BuildEnvironmentVariable(
                        value=self.artifacts_bucket.bucket_name
                    ),
                    "MODEL_PACKAGE_GROUP_NAME": codebuild.BuildEnvironmentVariable(
                        value=self.model_package_group_name
                    ),
                },
            ),
            role=self.codebuild_role,
            timeout=Duration.hours(2),
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    log_group=logs.LogGroup(
                        self,
                        "TrainingLogGroup",
                        log_group_name=f"/aws/codebuild/{self.project_name}-train",
                        retention=logs.RetentionDays.ONE_MONTH,
                        removal_policy=RemovalPolicy.DESTROY,
                    )
                )
            ),
        )

        return project

    def _create_testing_project(self) -> codebuild.Project:
        """Create CodeBuild project for model testing."""
        # Create buildspec for testing
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "phases": {
                "install": {
                    "runtime-versions": {"python": "3.9"},
                    "commands": [
                        "pip install boto3 sagemaker pandas numpy scikit-learn"
                    ]
                },
                "build": {
                    "commands": [
                        "echo 'Starting model testing...'",
                        "python test_model.py"
                    ]
                }
            },
            "artifacts": {
                "files": ["test_results.json", "model_package_arn.txt"]
            }
        })

        project = codebuild.Project(
            self,
            "TestingProject",
            project_name=f"{self.project_name}-test",
            description="ML model testing project",
            source=codebuild.Source.code_pipeline(build_spec=buildspec),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_5_0,
                compute_type=codebuild.ComputeType.MEDIUM,
            ),
            role=self.codebuild_role,
            timeout=Duration.hours(1),
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    log_group=logs.LogGroup(
                        self,
                        "TestingLogGroup",
                        log_group_name=f"/aws/codebuild/{self.project_name}-test",
                        retention=logs.RetentionDays.ONE_MONTH,
                        removal_policy=RemovalPolicy.DESTROY,
                    )
                )
            ),
        )

        return project

    def _create_deployment_function(self) -> aws_lambda.Function:
        """Create Lambda function for model deployment."""
        deployment_code = '''
import json
import boto3
import os
import time
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda function to deploy ML models to SageMaker endpoints.
    
    This function is triggered by CodePipeline and handles the deployment
    of approved model packages to production endpoints.
    """
    codepipeline = boto3.client('codepipeline')
    sagemaker = boto3.client('sagemaker')
    
    # Get job details from CodePipeline
    job_id = event['CodePipeline.job']['id']
    
    try:
        print(f"Starting deployment for job: {job_id}")
        
        # In a real implementation, you would:
        # 1. Extract model package ARN from input artifacts
        # 2. Create endpoint configuration
        # 3. Deploy model to endpoint
        # 4. Validate deployment
        
        # For this example, we'll simulate successful deployment
        print("Model deployment simulation completed successfully")
        
        # Signal success to CodePipeline
        codepipeline.put_job_success_result(jobId=job_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Deployment successful')
        }
        
    except Exception as e:
        print(f"Deployment failed: {str(e)}")
        
        # Signal failure to CodePipeline
        codepipeline.put_job_failure_result(
            jobId=job_id,
            failureDetails={'message': str(e)}
        )
        
        raise e
        '''

        function = aws_lambda.Function(
            self,
            "DeploymentFunction",
            function_name=f"{self.project_name}-deploy",
            description="Deploy ML model to production endpoint",
            runtime=aws_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=aws_lambda.Code.from_inline(deployment_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            environment={
                "SAGEMAKER_ROLE_ARN": self.sagemaker_role.role_arn,
                "MODEL_PACKAGE_GROUP_NAME": self.model_package_group_name,
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
        )

        return function

    def _create_ml_pipeline(self) -> codepipeline.Pipeline:
        """Create CodePipeline for ML workflow orchestration."""
        # Define pipeline artifacts
        source_output = codepipeline.Artifact("SourceOutput")
        build_output = codepipeline.Artifact("BuildOutput")
        test_output = codepipeline.Artifact("TestOutput")

        # Create pipeline
        pipeline = codepipeline.Pipeline(
            self,
            "MLPipeline",
            pipeline_name=f"ml-deployment-pipeline-{self.project_name}",
            role=self.codepipeline_role,
            artifact_bucket=self.artifacts_bucket,
            stages=[
                # Source stage
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.S3SourceAction(
                            action_name="SourceAction",
                            bucket=self.artifacts_bucket,
                            bucket_key="source/ml-source-code.zip",
                            output=source_output,
                        )
                    ],
                ),
                # Build stage (model training)
                codepipeline.StageProps(
                    stage_name="Build",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="TrainModel",
                            project=self.training_project,
                            input=source_output,
                            outputs=[build_output],
                        )
                    ],
                ),
                # Test stage (model validation)
                codepipeline.StageProps(
                    stage_name="Test",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="TestModel",
                            project=self.testing_project,
                            input=build_output,
                            outputs=[test_output],
                        )
                    ],
                ),
                # Deploy stage (production deployment)
                codepipeline.StageProps(
                    stage_name="Deploy",
                    actions=[
                        codepipeline_actions.LambdaInvokeAction(
                            action_name="DeployModel",
                            lambda_=self.deployment_function,
                            inputs=[test_output],
                        )
                    ],
                ),
            ],
        )

        return pipeline

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "ArtifactsBucketName",
            value=self.artifacts_bucket.bucket_name,
            description="S3 bucket for ML artifacts and training data",
            export_name=f"{self.stack_name}-ArtifactsBucket",
        )

        CfnOutput(
            self,
            "ModelPackageGroupName",
            value=self.model_package_group_name,
            description="SageMaker Model Package Group for model registry",
            export_name=f"{self.stack_name}-ModelPackageGroup",
        )

        CfnOutput(
            self,
            "PipelineName",
            value=self.pipeline.pipeline_name,
            description="CodePipeline for ML workflow orchestration",
            export_name=f"{self.stack_name}-Pipeline",
        )

        CfnOutput(
            self,
            "SageMakerExecutionRoleArn",
            value=self.sagemaker_role.role_arn,
            description="IAM role for SageMaker training jobs and endpoints",
            export_name=f"{self.stack_name}-SageMakerRole",
        )

        CfnOutput(
            self,
            "PipelineConsoleUrl",
            value=f"https://console.aws.amazon.com/codesuite/codepipeline/pipelines/{self.pipeline.pipeline_name}/view",
            description="URL to view the pipeline in AWS Console",
        )


class MLOpsPipelineApp(cdk.App):
    """CDK Application for MLOps Pipeline."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get environment configuration
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )

        # Get configuration from environment variables or use defaults
        project_name = os.environ.get("PROJECT_NAME", "mlops-pipeline")
        model_package_group_name = os.environ.get(
            "MODEL_PACKAGE_GROUP_NAME", "fraud-detection-models"
        )

        # Create the MLOps pipeline stack
        MLOpsPipelineStack(
            self,
            "MLOpsPipelineStack",
            env=env,
            project_name=project_name,
            model_package_group_name=model_package_group_name,
            description="MLOps Pipeline with SageMaker and CodePipeline for automated model deployment",
            tags={
                "Project": project_name,
                "Environment": "Production",
                "ManagedBy": "CDK",
                "Purpose": "MLOps",
            },
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = MLOpsPipelineApp()
    app.synth()


if __name__ == "__main__":
    main()