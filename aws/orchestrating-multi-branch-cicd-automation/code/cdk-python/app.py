#!/usr/bin/env python3
"""
CDK Python application for Multi-Branch CI/CD Pipelines with CodePipeline

This application creates a complete multi-branch CI/CD system using AWS CodePipeline
with dynamic pipeline creation based on branch events. It includes:
- CodeCommit repository for source control
- Lambda function for pipeline automation
- EventBridge rules for branch event handling
- CodeBuild project for builds
- IAM roles and policies
- CloudWatch monitoring and alerts
"""

import os
from typing import Dict, Any, List

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_codecommit as codecommit,
    aws_codepipeline as codepipeline,
    aws_codepipeline_actions as codepipeline_actions,
    aws_codebuild as codebuild,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_iam as iam,
    aws_s3 as s3,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class MultiBranchCiCdStack(Stack):
    """
    CDK Stack for Multi-Branch CI/CD Pipelines
    
    This stack creates a complete multi-branch CI/CD system with:
    - CodeCommit repository
    - Lambda-based pipeline automation
    - EventBridge integration
    - CodeBuild projects
    - CloudWatch monitoring
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        repository_name: str = "multi-branch-app",
        environment_name: str = "dev",
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.repository_name = repository_name
        self.environment_name = environment_name

        # Create S3 bucket for pipeline artifacts
        self.artifact_bucket = self._create_artifact_bucket()

        # Create CodeCommit repository
        self.repository = self._create_codecommit_repository()

        # Create IAM roles
        self.pipeline_role = self._create_pipeline_role()
        self.codebuild_role = self._create_codebuild_role()
        self.lambda_role = self._create_lambda_role()

        # Create CodeBuild project
        self.codebuild_project = self._create_codebuild_project()

        # Create Lambda function for pipeline management
        self.pipeline_manager = self._create_pipeline_manager_lambda()

        # Create EventBridge rules
        self.event_rule = self._create_eventbridge_rule()

        # Create base pipelines for main branches
        self.main_pipeline = self._create_main_pipeline()
        self.develop_pipeline = self._create_develop_pipeline()

        # Create monitoring resources
        self.sns_topic = self._create_sns_topic()
        self.dashboard = self._create_cloudwatch_dashboard()
        self.alarms = self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_artifact_bucket(self) -> s3.Bucket:
        """Create S3 bucket for pipeline artifacts"""
        bucket = s3.Bucket(
            self,
            "ArtifactBucket",
            bucket_name=f"multi-branch-artifacts-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Add lifecycle policy to manage artifact retention
        bucket.add_lifecycle_rule(
            id="ArtifactCleanup",
            prefix="artifacts/",
            expiration=Duration.days(30),
            noncurrent_version_expiration=Duration.days(7),
        )

        return bucket

    def _create_codecommit_repository(self) -> codecommit.Repository:
        """Create CodeCommit repository"""
        repository = codecommit.Repository(
            self,
            "Repository",
            repository_name=self.repository_name,
            description="Multi-branch CI/CD demo application repository",
        )

        return repository

    def _create_pipeline_role(self) -> iam.Role:
        """Create IAM role for CodePipeline"""
        role = iam.Role(
            self,
            "CodePipelineRole",
            assumed_by=iam.ServicePrincipal("codepipeline.amazonaws.com"),
            description="Role for CodePipeline to access AWS services",
        )

        # Add necessary policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSCodePipelineFullAccess")
        )
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSCodeCommitFullAccess")
        )
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("AWSCodeBuildDeveloperAccess")
        )

        # Add S3 permissions for artifact bucket
        role.add_to_policy(
            iam.PolicyStatement(
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:GetBucketVersioning",
                ],
                resources=[
                    self.artifact_bucket.bucket_arn,
                    f"{self.artifact_bucket.bucket_arn}/*",
                ],
            )
        )

        return role

    def _create_codebuild_role(self) -> iam.Role:
        """Create IAM role for CodeBuild"""
        role = iam.Role(
            self,
            "CodeBuildRole",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="Role for CodeBuild to access AWS services",
        )

        # Add necessary policies
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchLogsFullAccess")
        )

        # Add S3 permissions for artifact bucket
        role.add_to_policy(
            iam.PolicyStatement(
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                ],
                resources=[
                    self.artifact_bucket.bucket_arn,
                    f"{self.artifact_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add ECR permissions for Docker builds
        role.add_to_policy(
            iam.PolicyStatement(
                actions=[
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:PutImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_lambda_role(self) -> iam.Role:
        """Create IAM role for Lambda pipeline manager"""
        role = iam.Role(
            self,
            "LambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for Lambda pipeline manager function",
        )

        # Add basic Lambda execution policy
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )

        # Add CodePipeline permissions
        role.add_to_policy(
            iam.PolicyStatement(
                actions=[
                    "codepipeline:CreatePipeline",
                    "codepipeline:DeletePipeline",
                    "codepipeline:GetPipeline",
                    "codepipeline:ListPipelines",
                    "codepipeline:UpdatePipeline",
                    "codepipeline:GetPipelineState",
                    "codepipeline:StartPipelineExecution",
                ],
                resources=["*"],
            )
        )

        # Add CodeCommit permissions
        role.add_to_policy(
            iam.PolicyStatement(
                actions=[
                    "codecommit:GetRepository",
                    "codecommit:ListRepositories",
                    "codecommit:GetBranch",
                    "codecommit:ListBranches",
                ],
                resources=["*"],
            )
        )

        # Add IAM permissions to pass roles
        role.add_to_policy(
            iam.PolicyStatement(
                actions=["iam:PassRole"],
                resources=[self.pipeline_role.role_arn],
            )
        )

        return role

    def _create_codebuild_project(self) -> codebuild.Project:
        """Create CodeBuild project for multi-branch builds"""
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "phases": {
                "pre_build": {
                    "commands": [
                        "echo Logging in to Amazon ECR...",
                        "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
                    ]
                },
                "build": {
                    "commands": [
                        "echo Build started on `date`",
                        "echo Building the Docker image...",
                        "docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .",
                        "docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG"
                    ]
                },
                "post_build": {
                    "commands": [
                        "echo Build completed on `date`",
                        "echo Pushing the Docker image...",
                        "docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG"
                    ]
                }
            },
            "artifacts": {
                "files": ["**/*"]
            }
        })

        project = codebuild.Project(
            self,
            "BuildProject",
            project_name=f"multi-branch-build-{self.environment_name}",
            description="Build project for multi-branch pipelines",
            role=self.codebuild_role,
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_3,
                compute_type=codebuild.ComputeType.SMALL,
                environment_variables={
                    "AWS_DEFAULT_REGION": codebuild.BuildEnvironmentVariable(
                        value=self.region
                    ),
                    "AWS_ACCOUNT_ID": codebuild.BuildEnvironmentVariable(
                        value=self.account
                    ),
                    "IMAGE_REPO_NAME": codebuild.BuildEnvironmentVariable(
                        value=self.repository_name
                    ),
                    "IMAGE_TAG": codebuild.BuildEnvironmentVariable(
                        value="latest"
                    ),
                },
            ),
            build_spec=buildspec,
            timeout=Duration.minutes(60),
        )

        return project

    def _create_pipeline_manager_lambda(self) -> lambda_.Function:
        """Create Lambda function for pipeline management"""
        lambda_code = """
import json
import boto3
import os
import logging
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

codepipeline = boto3.client('codepipeline')
codecommit = boto3.client('codecommit')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        detail = event.get('detail', {})
        event_name = detail.get('eventName', '')
        repository_name = detail.get('requestParameters', {}).get('repositoryName', '')
        
        if event_name == 'CreateBranch':
            return handle_branch_creation(detail, repository_name)
        elif event_name == 'DeleteBranch':
            return handle_branch_deletion(detail, repository_name)
        elif event_name == 'GitPush':
            return handle_git_push(detail, repository_name)
        
        return {'statusCode': 200, 'body': json.dumps('Event processed but no action taken')}
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {'statusCode': 500, 'body': json.dumps(f'Error: {str(e)}')}

def handle_branch_creation(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if not branch_name:
        return {'statusCode': 400, 'body': 'Branch name not found'}
    
    if branch_name.startswith('feature/'):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            create_branch_pipeline(repository_name, branch_name, pipeline_name)
            logger.info(f"Created pipeline {pipeline_name} for branch {branch_name}")
            return {'statusCode': 200, 'body': json.dumps(f'Pipeline {pipeline_name} created successfully')}
        except Exception as e:
            logger.error(f"Failed to create pipeline: {str(e)}")
            return {'statusCode': 500, 'body': json.dumps(f'Pipeline creation failed: {str(e)}')}
    
    return {'statusCode': 200, 'body': 'No pipeline created for this branch type'}

def handle_branch_deletion(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    
    if branch_name.startswith('feature/'):
        pipeline_name = f"{repository_name}-{branch_name.replace('/', '-')}"
        
        try:
            codepipeline.delete_pipeline(name=pipeline_name)
            logger.info(f"Deleted pipeline {pipeline_name}")
            return {'statusCode': 200, 'body': json.dumps(f'Pipeline {pipeline_name} deleted successfully')}
        except codepipeline.exceptions.PipelineNotFoundException:
            return {'statusCode': 404, 'body': json.dumps(f'Pipeline {pipeline_name} not found')}
        except Exception as e:
            logger.error(f"Failed to delete pipeline: {str(e)}")
            return {'statusCode': 500, 'body': json.dumps(f'Pipeline deletion failed: {str(e)}')}
    
    return {'statusCode': 200, 'body': 'No pipeline deleted for this branch type'}

def handle_git_push(detail: Dict[str, Any], repository_name: str) -> Dict[str, Any]:
    branch_name = detail.get('requestParameters', {}).get('branchName', '')
    logger.info(f"Git push detected on branch {branch_name} in repository {repository_name}")
    return {'statusCode': 200, 'body': json.dumps('Git push event processed')}

def create_branch_pipeline(repository_name: str, branch_name: str, pipeline_name: str) -> None:
    pipeline_definition = {
        "pipeline": {
            "name": pipeline_name,
            "roleArn": os.environ['PIPELINE_ROLE_ARN'],
            "artifactStore": {
                "type": "S3",
                "location": os.environ['ARTIFACT_BUCKET']
            },
            "stages": [
                {
                    "name": "Source",
                    "actions": [
                        {
                            "name": "SourceAction",
                            "actionTypeId": {
                                "category": "Source",
                                "owner": "AWS",
                                "provider": "CodeCommit",
                                "version": "1"
                            },
                            "configuration": {
                                "RepositoryName": repository_name,
                                "BranchName": branch_name
                            },
                            "outputArtifacts": [{"name": "SourceOutput"}]
                        }
                    ]
                },
                {
                    "name": "Build",
                    "actions": [
                        {
                            "name": "BuildAction",
                            "actionTypeId": {
                                "category": "Build",
                                "owner": "AWS",
                                "provider": "CodeBuild",
                                "version": "1"
                            },
                            "configuration": {
                                "ProjectName": os.environ['CODEBUILD_PROJECT_NAME']
                            },
                            "inputArtifacts": [{"name": "SourceOutput"}],
                            "outputArtifacts": [{"name": "BuildOutput"}]
                        }
                    ]
                }
            ]
        }
    }
    
    codepipeline.create_pipeline(**pipeline_definition)
        """

        function = lambda_.Function(
            self,
            "PipelineManagerFunction",
            function_name=f"pipeline-manager-{self.environment_name}",
            description="Multi-branch pipeline manager",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            environment={
                "PIPELINE_ROLE_ARN": self.pipeline_role.role_arn,
                "ARTIFACT_BUCKET": self.artifact_bucket.bucket_name,
                "CODEBUILD_PROJECT_NAME": self.codebuild_project.project_name,
            },
        )

        # Create log group with retention policy
        logs.LogGroup(
            self,
            "PipelineManagerLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return function

    def _create_eventbridge_rule(self) -> events.Rule:
        """Create EventBridge rule for CodeCommit events"""
        rule = events.Rule(
            self,
            "CodeCommitBranchEvents",
            description="Trigger pipeline management for branch events",
            event_pattern=events.EventPattern(
                source=["aws.codecommit"],
                detail_type=["CodeCommit Repository State Change"],
                detail={
                    "repositoryName": [self.repository.repository_name],
                    "eventName": ["CreateBranch", "DeleteBranch", "GitPush"],
                },
            ),
        )

        # Add Lambda function as target
        rule.add_target(events_targets.LambdaFunction(self.pipeline_manager))

        return rule

    def _create_main_pipeline(self) -> codepipeline.Pipeline:
        """Create main branch pipeline"""
        source_output = codepipeline.Artifact("SourceOutput")
        build_output = codepipeline.Artifact("BuildOutput")

        pipeline = codepipeline.Pipeline(
            self,
            "MainPipeline",
            pipeline_name=f"{self.repository_name}-main",
            role=self.pipeline_role,
            artifact_bucket=self.artifact_bucket,
            stages=[
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.CodeCommitSourceAction(
                            action_name="SourceAction",
                            repository=self.repository,
                            branch="main",
                            output=source_output,
                        )
                    ],
                ),
                codepipeline.StageProps(
                    stage_name="Build",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="BuildAction",
                            project=self.codebuild_project,
                            input=source_output,
                            outputs=[build_output],
                        )
                    ],
                ),
            ],
        )

        return pipeline

    def _create_develop_pipeline(self) -> codepipeline.Pipeline:
        """Create develop branch pipeline"""
        source_output = codepipeline.Artifact("SourceOutput")
        build_output = codepipeline.Artifact("BuildOutput")

        pipeline = codepipeline.Pipeline(
            self,
            "DevelopPipeline",
            pipeline_name=f"{self.repository_name}-develop",
            role=self.pipeline_role,
            artifact_bucket=self.artifact_bucket,
            stages=[
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.CodeCommitSourceAction(
                            action_name="SourceAction",
                            repository=self.repository,
                            branch="develop",
                            output=source_output,
                        )
                    ],
                ),
                codepipeline.StageProps(
                    stage_name="Build",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="BuildAction",
                            project=self.codebuild_project,
                            input=source_output,
                            outputs=[build_output],
                        )
                    ],
                ),
            ],
        )

        return pipeline

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for pipeline alerts"""
        topic = sns.Topic(
            self,
            "PipelineAlertsTopic",
            display_name="Pipeline Alerts",
            description="Notifications for pipeline failures and important events",
        )

        return topic

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for pipeline monitoring"""
        dashboard = cloudwatch.Dashboard(
            self,
            "PipelineDashboard",
            dashboard_name=f"MultiBranchPipelines-{self.environment_name}",
        )

        # Add pipeline success/failure metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Pipeline Execution Results",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/CodePipeline",
                        metric_name="PipelineExecutionSuccess",
                        dimensions_map={
                            "PipelineName": self.main_pipeline.pipeline_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/CodePipeline",
                        metric_name="PipelineExecutionFailure",
                        dimensions_map={
                            "PipelineName": self.main_pipeline.pipeline_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
            )
        )

        # Add build metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Build Performance",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/CodeBuild",
                        metric_name="Duration",
                        dimensions_map={
                            "ProjectName": self.codebuild_project.project_name
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/CodeBuild",
                        metric_name="SucceededBuilds",
                        dimensions_map={
                            "ProjectName": self.codebuild_project.project_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/CodeBuild",
                        metric_name="FailedBuilds",
                        dimensions_map={
                            "ProjectName": self.codebuild_project.project_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
            )
        )

        return dashboard

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """Create CloudWatch alarms for pipeline monitoring"""
        alarms = []

        # Pipeline failure alarm
        pipeline_failure_alarm = cloudwatch.Alarm(
            self,
            "PipelineFailureAlarm",
            alarm_name=f"PipelineFailure-{self.repository_name}",
            alarm_description="Alert when pipeline fails",
            metric=cloudwatch.Metric(
                namespace="AWS/CodePipeline",
                metric_name="PipelineExecutionFailure",
                dimensions_map={
                    "PipelineName": self.main_pipeline.pipeline_name
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        pipeline_failure_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )
        
        alarms.append(pipeline_failure_alarm)

        # Lambda function error alarm
        lambda_error_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorAlarm",
            alarm_name=f"LambdaErrors-{self.pipeline_manager.function_name}",
            alarm_description="Alert when Lambda function errors",
            metric=self.pipeline_manager.metric_errors(),
            threshold=1,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )
        
        lambda_error_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )
        
        alarms.append(lambda_error_alarm)

        return alarms

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        CfnOutput(
            self,
            "RepositoryName",
            value=self.repository.repository_name,
            description="CodeCommit repository name",
        )

        CfnOutput(
            self,
            "RepositoryCloneUrl",
            value=self.repository.repository_clone_url_http,
            description="CodeCommit repository clone URL",
        )

        CfnOutput(
            self,
            "ArtifactBucket",
            value=self.artifact_bucket.bucket_name,
            description="S3 bucket for pipeline artifacts",
        )

        CfnOutput(
            self,
            "CodeBuildProject",
            value=self.codebuild_project.project_name,
            description="CodeBuild project name",
        )

        CfnOutput(
            self,
            "PipelineManagerFunction",
            value=self.pipeline_manager.function_name,
            description="Lambda function for pipeline management",
        )

        CfnOutput(
            self,
            "MainPipeline",
            value=self.main_pipeline.pipeline_name,
            description="Main branch pipeline name",
        )

        CfnOutput(
            self,
            "DevelopPipeline",
            value=self.develop_pipeline.pipeline_name,
            description="Develop branch pipeline name",
        )

        CfnOutput(
            self,
            "SNSTopic",
            value=self.sns_topic.topic_arn,
            description="SNS topic ARN for pipeline alerts",
        )

        CfnOutput(
            self,
            "Dashboard",
            value=self.dashboard.dashboard_name,
            description="CloudWatch dashboard name",
        )


def main() -> None:
    """Main application entry point"""
    app = App()

    # Get environment variables or use defaults
    repository_name = app.node.try_get_context("repository_name") or "multi-branch-app"
    environment_name = app.node.try_get_context("environment_name") or "dev"
    
    # Get AWS account and region from environment or CDK context
    account = os.environ.get("CDK_DEFAULT_ACCOUNT") or app.node.try_get_context("account")
    region = os.environ.get("CDK_DEFAULT_REGION") or app.node.try_get_context("region")

    if not account or not region:
        raise ValueError("AWS account and region must be specified")

    env = Environment(account=account, region=region)

    # Create the stack
    MultiBranchCiCdStack(
        app,
        f"MultiBranchCiCd-{environment_name}",
        repository_name=repository_name,
        environment_name=environment_name,
        env=env,
        description="Multi-Branch CI/CD Pipelines with CodePipeline",
    )

    # Add stack tags
    cdk.Tags.of(app).add("Project", "MultiBranchCICD")
    cdk.Tags.of(app).add("Environment", environment_name)
    cdk.Tags.of(app).add("ManagedBy", "CDK")

    app.synth()


if __name__ == "__main__":
    main()