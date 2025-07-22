"""
Main Proton Infrastructure Stack for AWS Proton Infrastructure Automation

This stack creates the core infrastructure components that integrate with
AWS Proton templates, including CodePipeline for continuous deployment,
parameter stores for configuration management, and supporting services.
"""

from typing import Optional, List
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_codepipeline as codepipeline,
    aws_codepipeline_actions as codepipeline_actions,
    aws_codebuild as codebuild,
    aws_codecommit as codecommit,
    aws_s3 as s3,
    aws_iam as iam,
    aws_ssm as ssm,
    aws_secretsmanager as secretsmanager,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    RemovalPolicy,
    Tags,
)
from constructs import Construct


class ProtonInfrastructureStack(Stack):
    """
    Main Proton Infrastructure Stack
    
    Creates the core infrastructure components that enable AWS Proton
    template automation, including CI/CD pipelines, parameter management,
    and monitoring capabilities.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        ecs_cluster: ecs.Cluster,
        env_name: str,
        enable_cicd: bool = True,
        enable_monitoring: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Proton Infrastructure Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            vpc: The VPC for networking
            ecs_cluster: The ECS cluster for containerized services
            env_name: Environment name for resource naming
            enable_cicd: Whether to create CI/CD pipeline
            enable_monitoring: Whether to create monitoring resources
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.vpc = vpc
        self.ecs_cluster = ecs_cluster
        self.env_name = env_name
        
        # Create S3 bucket for artifacts
        self.artifacts_bucket = self._create_artifacts_bucket()
        
        # Create parameter store for configuration
        self._create_parameter_store()
        
        # Create secrets manager for sensitive data
        self._create_secrets_manager()
        
        # Create notification topic
        self.notification_topic = self._create_notification_topic()
        
        # Create CI/CD pipeline if enabled
        if enable_cicd:
            self._create_cicd_pipeline()
        
        # Create monitoring resources if enabled
        if enable_monitoring:
            self._create_monitoring_resources()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags
        self._add_tags()
    
    def _create_artifacts_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing build artifacts and templates."""
        
        bucket = s3.Bucket(
            self,
            "ProtonArtifactsBucket",
            bucket_name=f"{self.env_name}-proton-artifacts-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.RETAIN,
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
                ),
            ],
        )
        
        return bucket
    
    def _create_parameter_store(self) -> None:
        """Create SSM Parameter Store parameters for configuration management."""
        
        # Environment configuration parameters
        self.env_config_param = ssm.StringParameter(
            self,
            "EnvironmentConfigParameter",
            parameter_name=f"/apps/{self.env_name}/config/environment",
            string_value="production",
            description=f"Environment configuration for {self.env_name}",
            tier=ssm.ParameterTier.STANDARD,
        )
        
        # VPC configuration parameters
        self.vpc_config_param = ssm.StringParameter(
            self,
            "VpcConfigParameter",
            parameter_name=f"/apps/{self.env_name}/config/vpc-id",
            string_value=self.vpc.vpc_id,
            description=f"VPC ID for {self.env_name} environment",
            tier=ssm.ParameterTier.STANDARD,
        )
        
        # ECS cluster configuration parameters
        self.ecs_config_param = ssm.StringParameter(
            self,
            "EcsConfigParameter",
            parameter_name=f"/apps/{self.env_name}/config/ecs-cluster",
            string_value=self.ecs_cluster.cluster_name,
            description=f"ECS cluster name for {self.env_name} environment",
            tier=ssm.ParameterTier.STANDARD,
        )
    
    def _create_secrets_manager(self) -> None:
        """Create AWS Secrets Manager secrets for sensitive configuration."""
        
        # Database connection secrets template
        self.db_secrets = secretsmanager.Secret(
            self,
            "DatabaseSecrets",
            secret_name=f"/apps/{self.env_name}/secrets/database",
            description=f"Database connection secrets for {self.env_name}",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "admin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
            ),
        )
        
        # API keys and external service secrets
        self.api_secrets = secretsmanager.Secret(
            self,
            "ApiSecrets",
            secret_name=f"/apps/{self.env_name}/secrets/api-keys",
            description=f"API keys and external service secrets for {self.env_name}",
            secret_string_value=secretsmanager.SecretStringValueBeta1.from_token(
                '{"placeholder": "replace-with-actual-api-keys"}'
            ),
        )
    
    def _create_notification_topic(self) -> sns.Topic:
        """Create SNS topic for notifications."""
        
        topic = sns.Topic(
            self,
            "ProtonNotificationTopic",
            topic_name=f"{self.env_name}-proton-notifications",
            display_name=f"Proton Notifications - {self.env_name}",
        )
        
        return topic
    
    def _create_cicd_pipeline(self) -> None:
        """Create CI/CD pipeline for automated deployments."""
        
        # Create CodeCommit repository for source code
        self.repository = codecommit.Repository(
            self,
            "ProtonRepository",
            repository_name=f"{self.env_name}-proton-apps",
            description=f"Source code repository for {self.env_name} applications",
        )
        
        # Create CodeBuild project for building and testing
        self.build_project = codebuild.Project(
            self,
            "ProtonBuildProject",
            project_name=f"{self.env_name}-proton-build",
            description=f"Build project for {self.env_name} applications",
            source=codebuild.Source.code_commit(
                repository=self.repository,
                branch_or_ref="main",
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                compute_type=codebuild.ComputeType.SMALL,
                privileged=True,  # Required for Docker builds
            ),
            build_spec=codebuild.BuildSpec.from_object({
                "version": "0.2",
                "phases": {
                    "pre_build": {
                        "commands": [
                            "echo Logging in to Amazon ECR...",
                            "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com",
                        ]
                    },
                    "build": {
                        "commands": [
                            "echo Build started on `date`",
                            "echo Building the Docker image...",
                            "docker build -t $IMAGE_REPO_NAME:$IMAGE_TAG .",
                            "docker tag $IMAGE_REPO_NAME:$IMAGE_TAG $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG",
                        ]
                    },
                    "post_build": {
                        "commands": [
                            "echo Build completed on `date`",
                            "echo Pushing the Docker image...",
                            "docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME:$IMAGE_TAG",
                        ]
                    }
                }
            }),
            artifacts=codebuild.Artifacts.s3(
                bucket=self.artifacts_bucket,
                include_build_id=True,
                name="build-artifacts",
            ),
            logging=codebuild.LoggingOptions(
                cloud_watch=codebuild.CloudWatchLoggingOptions(
                    enabled=True,
                    log_group=logs.LogGroup(
                        self,
                        "BuildLogGroup",
                        log_group_name=f"/aws/codebuild/{self.env_name}-proton-build",
                        retention=logs.RetentionDays.ONE_MONTH,
                    ),
                ),
            ),
        )
        
        # Add permissions for ECR operations
        self.build_project.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
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
        
        # Create CodePipeline
        self.pipeline = codepipeline.Pipeline(
            self,
            "ProtonPipeline",
            pipeline_name=f"{self.env_name}-proton-pipeline",
            artifact_bucket=self.artifacts_bucket,
            stages=[
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.CodeCommitSourceAction(
                            action_name="SourceAction",
                            repository=self.repository,
                            branch="main",
                            output=codepipeline.Artifact("source-output"),
                        ),
                    ],
                ),
                codepipeline.StageProps(
                    stage_name="Build",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="BuildAction",
                            project=self.build_project,
                            input=codepipeline.Artifact("source-output"),
                            outputs=[codepipeline.Artifact("build-output")],
                        ),
                    ],
                ),
            ],
        )
        
        # Add notification to pipeline
        self.pipeline.on_state_change(
            "PipelineStateChange",
            target=None,  # Add SNS target if needed
        )
    
    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring resources."""
        
        # CloudWatch Dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "ProtonDashboard",
            dashboard_name=f"{self.env_name}-proton-dashboard",
        )
        
        # Add ECS cluster metrics
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="ECS Cluster CPU and Memory Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ECS",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "ClusterName": self.ecs_cluster.cluster_name,
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/ECS",
                        metric_name="MemoryUtilization",
                        dimensions_map={
                            "ClusterName": self.ecs_cluster.cluster_name,
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
            ),
        )
        
        # Add pipeline metrics if pipeline exists
        if hasattr(self, 'pipeline'):
            self.dashboard.add_widgets(
                cloudwatch.GraphWidget(
                    title="Pipeline Execution State",
                    left=[
                        cloudwatch.Metric(
                            namespace="AWS/CodePipeline",
                            metric_name="PipelineExecutionSuccess",
                            dimensions_map={
                                "PipelineName": self.pipeline.pipeline_name,
                            },
                            statistic="Sum",
                            period=Duration.hours(1),
                        ),
                    ],
                    width=12,
                ),
            )
        
        # Create alarms for critical metrics
        self._create_alarms()
    
    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        
        # ECS Cluster CPU alarm
        cpu_alarm = cloudwatch.Alarm(
            self,
            "EcsClusterCpuAlarm",
            alarm_name=f"{self.env_name}-ecs-cluster-cpu-high",
            alarm_description="ECS Cluster CPU utilization is high",
            metric=cloudwatch.Metric(
                namespace="AWS/ECS",
                metric_name="CPUUtilization",
                dimensions_map={
                    "ClusterName": self.ecs_cluster.cluster_name,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            datapoints_to_alarm=2,
        )
        
        # Add SNS notification to alarm
        cpu_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
        
        # ECS Cluster Memory alarm
        memory_alarm = cloudwatch.Alarm(
            self,
            "EcsClusterMemoryAlarm",
            alarm_name=f"{self.env_name}-ecs-cluster-memory-high",
            alarm_description="ECS Cluster memory utilization is high",
            metric=cloudwatch.Metric(
                namespace="AWS/ECS",
                metric_name="MemoryUtilization",
                dimensions_map={
                    "ClusterName": self.ecs_cluster.cluster_name,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            datapoints_to_alarm=2,
        )
        
        # Add SNS notification to alarm
        memory_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.notification_topic)
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the stack."""
        
        # S3 Bucket outputs
        CfnOutput(
            self,
            "ArtifactsBucketName",
            value=self.artifacts_bucket.bucket_name,
            description="S3 bucket for storing artifacts",
            export_name=f"{self.env_name}-artifacts-bucket-name",
        )
        
        # Parameter Store outputs
        CfnOutput(
            self,
            "EnvironmentConfigParameter",
            value=self.env_config_param.parameter_name,
            description="SSM parameter for environment configuration",
            export_name=f"{self.env_name}-env-config-parameter",
        )
        
        # Secrets Manager outputs
        CfnOutput(
            self,
            "DatabaseSecretsArn",
            value=self.db_secrets.secret_arn,
            description="Secrets Manager ARN for database secrets",
            export_name=f"{self.env_name}-db-secrets-arn",
        )
        
        # SNS Topic outputs
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS topic ARN for notifications",
            export_name=f"{self.env_name}-notification-topic-arn",
        )
        
        # CI/CD outputs
        if hasattr(self, 'repository'):
            CfnOutput(
                self,
                "CodeCommitRepositoryName",
                value=self.repository.repository_name,
                description="CodeCommit repository name",
                export_name=f"{self.env_name}-repository-name",
            )
        
        if hasattr(self, 'pipeline'):
            CfnOutput(
                self,
                "CodePipelineName",
                value=self.pipeline.pipeline_name,
                description="CodePipeline name",
                export_name=f"{self.env_name}-pipeline-name",
            )
        
        # Dashboard outputs
        if hasattr(self, 'dashboard'):
            CfnOutput(
                self,
                "CloudWatchDashboardName",
                value=self.dashboard.dashboard_name,
                description="CloudWatch dashboard name",
                export_name=f"{self.env_name}-dashboard-name",
            )
    
    def _add_tags(self) -> None:
        """Add tags to all resources."""
        Tags.of(self.artifacts_bucket).add("Name", f"{self.env_name}-artifacts")
        Tags.of(self.artifacts_bucket).add("Purpose", "ProtonArtifacts")
        
        Tags.of(self.notification_topic).add("Name", f"{self.env_name}-notifications")
        Tags.of(self.notification_topic).add("Purpose", "ProtonNotifications")
        
        if hasattr(self, 'repository'):
            Tags.of(self.repository).add("Name", f"{self.env_name}-repository")
            Tags.of(self.repository).add("Purpose", "ProtonSource")
        
        if hasattr(self, 'pipeline'):
            Tags.of(self.pipeline).add("Name", f"{self.env_name}-pipeline")
            Tags.of(self.pipeline).add("Purpose", "ProtonCICD")