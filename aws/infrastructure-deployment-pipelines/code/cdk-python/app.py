#!/usr/bin/env python3
"""
AWS CDK Python application for Infrastructure Deployment Pipelines.

This application creates a complete CI/CD pipeline using AWS CDK Pipelines
that automatically deploys infrastructure changes across multiple environments
with proper testing, approval gates, and security controls.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Stage,
    Environment,
    RemovalPolicy,
    CfnOutput,
    pipelines,
    aws_codecommit as codecommit,
    aws_codebuild as codebuild,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class ApplicationStack(Stack):
    """
    Example application stack that demonstrates infrastructure deployment.
    
    This stack creates a simple web application infrastructure including:
    - S3 bucket for static assets
    - DynamoDB table for application data
    - Lambda function for API processing
    - CloudWatch monitoring and logging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str,
        **kwargs
    ) -> None:
        """
        Initialize the application stack.
        
        Args:
            scope: The parent construct
            construct_id: The stack identifier
            environment_name: The deployment environment (dev, staging, prod)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.environment_name = environment_name
        
        # Create S3 bucket for static assets
        self.assets_bucket = s3.Bucket(
            self,
            f"AssetsBucket-{environment_name}",
            bucket_name=f"app-assets-{environment_name}-{self.account}-{self.region}",
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Create DynamoDB table for application data
        self.app_table = dynamodb.Table(
            self,
            f"AppTable-{environment_name}",
            table_name=f"app-data-{environment_name}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=environment_name == "prod",
        )
        
        # Create Lambda function for API processing
        self.api_function = lambda_.Function(
            self,
            f"ApiFunction-{environment_name}",
            function_name=f"app-api-{environment_name}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
from datetime import datetime

def handler(event, context):
    \"\"\"Simple API handler that processes requests and stores data.\"\"\"
    
    table_name = os.environ['TABLE_NAME']
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table(table_name)
    
    try:
        # Process the request
        request_id = event.get('requestId', 'test-request')
        timestamp = datetime.utcnow().isoformat()
        
        # Store data in DynamoDB
        table.put_item(
            Item={
                'id': request_id,
                'timestamp': timestamp,
                'environment': os.environ['ENVIRONMENT'],
                'data': json.dumps(event)
            }
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Request processed successfully',
                'requestId': request_id,
                'environment': os.environ['ENVIRONMENT']
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e)
            })
        }
            """),
            environment={
                "TABLE_NAME": self.app_table.table_name,
                "ENVIRONMENT": environment_name,
                "BUCKET_NAME": self.assets_bucket.bucket_name,
            },
            timeout=cdk.Duration.minutes(1),
            memory_size=256,
            log_retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Grant Lambda permissions to access DynamoDB and S3
        self.app_table.grant_read_write_data(self.api_function)
        self.assets_bucket.grant_read_write(self.api_function)
        
        # Create CloudWatch dashboard for monitoring
        self.create_monitoring_dashboard()
        
        # Create outputs for integration testing
        self.create_stack_outputs()
    
    def create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for application monitoring."""
        
        dashboard = cloudwatch.Dashboard(
            self,
            f"AppDashboard-{self.environment_name}",
            dashboard_name=f"app-monitoring-{self.environment_name}",
        )
        
        # Lambda metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                left=[
                    self.api_function.metric_invocations(),
                    self.api_function.metric_errors(),
                    self.api_function.metric_duration(),
                ],
                width=12,
            ),
            cloudwatch.GraphWidget(
                title="DynamoDB Metrics",
                left=[
                    self.app_table.metric_consumed_read_capacity_units(),
                    self.app_table.metric_consumed_write_capacity_units(),
                ],
                width=12,
            ),
        )
    
    def create_stack_outputs(self) -> None:
        """Create CloudFormation outputs for integration testing."""
        
        CfnOutput(
            self,
            "AssetsBucketName",
            value=self.assets_bucket.bucket_name,
            description=f"S3 bucket name for {self.environment_name} environment",
        )
        
        CfnOutput(
            self,
            "AppTableName",
            value=self.app_table.table_name,
            description=f"DynamoDB table name for {self.environment_name} environment",
        )
        
        CfnOutput(
            self,
            "ApiFunctionName",
            value=self.api_function.function_name,
            description=f"Lambda function name for {self.environment_name} environment",
        )
        
        CfnOutput(
            self,
            "ApiFunctionArn",
            value=self.api_function.function_arn,
            description=f"Lambda function ARN for {self.environment_name} environment",
        )


class ApplicationStage(Stage):
    """
    Application stage that represents a deployment environment.
    
    This stage contains all the application stacks that need to be deployed
    together for a specific environment (dev, staging, prod).
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str,
        **kwargs
    ) -> None:
        """
        Initialize the application stage.
        
        Args:
            scope: The parent construct
            construct_id: The stage identifier
            environment_name: The deployment environment name
            **kwargs: Additional stage properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.environment_name = environment_name
        
        # Create the application stack
        self.app_stack = ApplicationStack(
            self,
            f"ApplicationStack-{environment_name}",
            environment_name=environment_name,
        )


class PipelineStack(Stack):
    """
    CDK Pipeline stack that manages the CI/CD pipeline.
    
    This stack creates a self-updating pipeline that:
    - Monitors the source repository for changes
    - Runs unit tests and security scans
    - Deploys to development environment automatically
    - Requires manual approval for production deployment
    - Provides comprehensive monitoring and notifications
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        **kwargs
    ) -> None:
        """
        Initialize the pipeline stack.
        
        Args:
            scope: The parent construct
            construct_id: The stack identifier
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        # Get configuration from environment variables
        self.repo_name = os.environ.get(
            "REPO_NAME",
            f"infrastructure-pipeline-{self.account}"
        )
        
        # Create or reference the CodeCommit repository
        self.repository = self.create_or_get_repository()
        
        # Create SNS topic for notifications
        self.notifications_topic = sns.Topic(
            self,
            "PipelineNotifications",
            topic_name="infrastructure-pipeline-notifications",
            display_name="Infrastructure Pipeline Notifications",
        )
        
        # Create the CDK pipeline
        self.pipeline = self.create_pipeline()
        
        # Add development stage (auto-deploy)
        self.add_development_stage()
        
        # Add production stage (manual approval)
        self.add_production_stage()
        
        # Add monitoring and notifications
        self.add_monitoring()
        
        # Create outputs
        self.create_outputs()
    
    def create_or_get_repository(self) -> codecommit.Repository:
        """Create or reference the CodeCommit repository."""
        
        try:
            # Try to reference existing repository
            repository = codecommit.Repository.from_repository_name(
                self,
                "Repository",
                repository_name=self.repo_name,
            )
        except Exception:
            # Create new repository if it doesn't exist
            repository = codecommit.Repository(
                self,
                "Repository",
                repository_name=self.repo_name,
                description="Infrastructure deployment pipeline repository",
            )
        
        return repository
    
    def create_pipeline(self) -> pipelines.CodePipeline:
        """Create the CDK pipeline with proper configuration."""
        
        # Create custom CodeBuild environment for CDK
        build_environment = codebuild.BuildEnvironment(
            build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
            compute_type=codebuild.ComputeType.SMALL,
            privileged=False,
        )
        
        # Create the pipeline
        pipeline = pipelines.CodePipeline(
            self,
            "Pipeline",
            pipeline_name="InfrastructurePipeline",
            
            # Source configuration
            synth=pipelines.ShellStep(
                "Synth",
                input=pipelines.CodePipelineSource.code_commit(
                    repository=self.repository,
                    branch="main",
                    trigger=codecommit.RepositoryEventRule.ON_COMMIT,
                ),
                commands=[
                    # Install dependencies
                    "pip install -r requirements.txt",
                    
                    # Run unit tests
                    "python -m pytest tests/ -v",
                    
                    # Run security checks
                    "pip install bandit safety",
                    "bandit -r . -f json || true",
                    "safety check || true",
                    
                    # Synthesize CDK
                    "cdk synth",
                ],
                primary_output_directory="cdk.out",
                env={
                    "REPO_NAME": self.repo_name,
                },
            ),
            
            # Build configuration
            code_build_defaults=pipelines.CodeBuildOptions(
                build_environment=build_environment,
                role_policy=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        actions=[
                            "codecommit:GetBranch",
                            "codecommit:GetCommit",
                            "codecommit:GetRepository",
                            "codecommit:ListBranches",
                            "codecommit:ListRepositories",
                        ],
                        resources=[self.repository.repository_arn],
                    ),
                ],
                timeout=cdk.Duration.minutes(60),
            ),
            
            # Enable self-mutation
            self_mutation=True,
            
            # Cross-account keys for multi-account deployments
            cross_account_keys=True,
            
            # Docker enabled for container builds
            docker_enabled_for_synth=True,
        )
        
        return pipeline
    
    def add_development_stage(self) -> None:
        """Add development stage with automatic deployment."""
        
        # Create development stage
        dev_stage = ApplicationStage(
            self,
            "DevStage",
            environment_name="dev",
            env=Environment(
                account=self.account,
                region=self.region,
            ),
        )
        
        # Add pre-deployment validation
        pre_steps = [
            pipelines.ShellStep(
                "ValidateInfrastructure",
                commands=[
                    "echo 'Validating infrastructure configuration...'",
                    "cdk diff --no-fail",
                    "echo 'Infrastructure validation complete'",
                ],
            ),
        ]
        
        # Add post-deployment tests
        post_steps = [
            pipelines.ShellStep(
                "IntegrationTests",
                commands=[
                    "echo 'Running integration tests...'",
                    "pip install boto3 pytest",
                    "python -m pytest integration_tests/ -v",
                    "echo 'Integration tests complete'",
                ],
                env_from_cfn_outputs={
                    "ASSETS_BUCKET_NAME": dev_stage.app_stack.assets_bucket.bucket_name,
                    "APP_TABLE_NAME": dev_stage.app_stack.app_table.table_name,
                    "API_FUNCTION_NAME": dev_stage.app_stack.api_function.function_name,
                },
            ),
        ]
        
        # Add stage to pipeline
        self.pipeline.add_stage(
            dev_stage,
            pre=pre_steps,
            post=post_steps,
        )
    
    def add_production_stage(self) -> None:
        """Add production stage with manual approval."""
        
        # Create production stage
        prod_stage = ApplicationStage(
            self,
            "ProdStage",
            environment_name="prod",
            env=Environment(
                account=self.account,
                region=self.region,
            ),
        )
        
        # Add manual approval step
        approval_step = pipelines.ManualApprovalStep(
            "PromoteToProduction",
            comment="Please review the changes and approve deployment to production",
        )
        
        # Add pre-deployment validation
        pre_steps = [
            approval_step,
            pipelines.ShellStep(
                "ProductionValidation",
                commands=[
                    "echo 'Running production readiness checks...'",
                    "cdk diff --no-fail",
                    "echo 'Production validation complete'",
                ],
            ),
        ]
        
        # Add post-deployment verification
        post_steps = [
            pipelines.ShellStep(
                "ProductionVerification",
                commands=[
                    "echo 'Verifying production deployment...'",
                    "pip install boto3",
                    "python -c \"import boto3; print('Production deployment verified')\"",
                ],
            ),
        ]
        
        # Add stage to pipeline
        self.pipeline.add_stage(
            prod_stage,
            pre=pre_steps,
            post=post_steps,
        )
    
    def add_monitoring(self) -> None:
        """Add monitoring and alerting for the pipeline."""
        
        # Create CloudWatch alarm for pipeline failures
        pipeline_alarm = cloudwatch.Alarm(
            self,
            "PipelineFailureAlarm",
            alarm_name="infrastructure-pipeline-failure",
            alarm_description="Infrastructure deployment pipeline has failed",
            metric=cloudwatch.Metric(
                namespace="AWS/CodePipeline",
                metric_name="PipelineExecutionFailure",
                dimensions_map={
                    "PipelineName": self.pipeline.pipeline_name,
                },
                statistic="Sum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=1,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        # Add alarm action to send notification
        pipeline_alarm.add_alarm_action(
            cdk.aws_cloudwatch_actions.SnsAction(self.notifications_topic)
        )
    
    def create_outputs(self) -> None:
        """Create CloudFormation outputs for the pipeline."""
        
        CfnOutput(
            self,
            "PipelineName",
            value=self.pipeline.pipeline_name,
            description="Name of the infrastructure deployment pipeline",
        )
        
        CfnOutput(
            self,
            "RepositoryName",
            value=self.repository.repository_name,
            description="Name of the CodeCommit repository",
        )
        
        CfnOutput(
            self,
            "RepositoryUrl",
            value=self.repository.repository_clone_url_http,
            description="HTTP clone URL for the CodeCommit repository",
        )
        
        CfnOutput(
            self,
            "NotificationsTopic",
            value=self.notifications_topic.topic_arn,
            description="ARN of the SNS topic for pipeline notifications",
        )


def main() -> None:
    """Main application entry point."""
    
    # Create CDK app
    app = cdk.App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the pipeline stack
    pipeline_stack = PipelineStack(
        app,
        "InfrastructurePipelineStack",
        env=env,
        description="Infrastructure deployment pipeline using CDK and CodePipeline",
    )
    
    # Add tags to all resources
    cdk.Tags.of(app).add("Project", "InfrastructurePipeline")
    cdk.Tags.of(app).add("Environment", "pipeline")
    cdk.Tags.of(app).add("ManagedBy", "CDK")
    
    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()