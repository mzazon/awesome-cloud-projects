#!/usr/bin/env python3
"""
AWS CDK Application for Infrastructure Automation with AWS Proton

This CDK application creates reusable infrastructure components that can be
integrated with AWS Proton templates for standardized, self-service infrastructure
deployment across development teams.
"""

import os
from typing import List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Environment,
    Tags,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_logs as logs,
    aws_iam as iam,
    aws_servicediscovery as servicediscovery,
    aws_codepipeline as codepipeline,
    aws_codepipeline_actions as codepipeline_actions,
    aws_codebuild as codebuild,
    aws_codecommit as codecommit,
    aws_s3 as s3,
    aws_ssm as ssm,
    aws_secretsmanager as secretsmanager,
    aws_sns as sns,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class VpcStack(Stack):
    """
    VPC Stack for AWS Proton Infrastructure
    
    Creates a production-ready VPC with public and private subnets,
    NAT gateways, and appropriate security configurations for use
    with AWS Proton templates.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        env_name: str,
        vpc_cidr: str = "10.0.0.0/16",
        max_azs: int = 2,
        **kwargs
    ) -> None:
        """
        Initialize the VPC Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            env_name: Environment name for resource naming
            vpc_cidr: CIDR block for the VPC
            max_azs: Maximum number of availability zones to use
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.env_name = env_name
        
        # Create VPC with public and private subnets
        self.vpc = ec2.Vpc(
            self,
            "ProtonVpc",
            vpc_name=f"{env_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr(vpc_cidr),
            max_azs=max_azs,
            nat_gateways=1,  # Cost optimization: single NAT gateway
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )
        
        # Create VPC Flow Logs for security monitoring
        flow_log_group = logs.LogGroup(
            self,
            "VpcFlowLogGroup",
            log_group_name=f"/aws/vpc/flowlogs/{env_name}",
            retention=logs.RetentionDays.ONE_MONTH,
        )
        
        self.vpc.add_flow_log(
            "FlowLogToCloudWatch",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(flow_log_group),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        # Create security groups
        self._create_security_groups()
        
        # Create outputs for Proton templates
        self._create_outputs()
        
        # Add tags
        self._add_tags()
    
    def _create_security_groups(self) -> None:
        """Create common security groups for use by Proton services."""
        
        # Application Load Balancer security group
        self.alb_security_group = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            security_group_name=f"{self.env_name}-alb-sg",
        )
        
        # Allow HTTP and HTTPS traffic from internet
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )
        
        # ECS service security group
        self.ecs_security_group = ec2.SecurityGroup(
            self,
            "EcsSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS services",
            security_group_name=f"{self.env_name}-ecs-sg",
        )
        
        # Allow traffic from ALB to ECS services
        self.ecs_security_group.add_ingress_rule(
            peer=self.alb_security_group,
            connection=ec2.Port.all_tcp(),
            description="Allow traffic from ALB to ECS services",
        )
        
        # Database security group
        self.db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for databases",
            security_group_name=f"{self.env_name}-db-sg",
        )
        
        # Allow traffic from ECS to database
        self.db_security_group.add_ingress_rule(
            peer=self.ecs_security_group,
            connection=ec2.Port.tcp(5432),  # PostgreSQL
            description="Allow PostgreSQL traffic from ECS",
        )
        
        self.db_security_group.add_ingress_rule(
            peer=self.ecs_security_group,
            connection=ec2.Port.tcp(3306),  # MySQL
            description="Allow MySQL traffic from ECS",
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for use by Proton templates."""
        
        # VPC outputs
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for Proton services",
            export_name=f"{self.env_name}-vpc-id",
        )
        
        CfnOutput(
            self,
            "VpcCidr",
            value=self.vpc.vpc_cidr_block,
            description="VPC CIDR block",
            export_name=f"{self.env_name}-vpc-cidr",
        )
        
        # Subnet outputs
        public_subnet_ids = [subnet.subnet_id for subnet in self.vpc.public_subnets]
        private_subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]
        
        CfnOutput(
            self,
            "PublicSubnetIds",
            value=",".join(public_subnet_ids),
            description="Public subnet IDs",
            export_name=f"{self.env_name}-public-subnet-ids",
        )
        
        CfnOutput(
            self,
            "PrivateSubnetIds",
            value=",".join(private_subnet_ids),
            description="Private subnet IDs",
            export_name=f"{self.env_name}-private-subnet-ids",
        )
        
        # Security group outputs
        CfnOutput(
            self,
            "AlbSecurityGroupId",
            value=self.alb_security_group.security_group_id,
            description="ALB security group ID",
            export_name=f"{self.env_name}-alb-sg-id",
        )
        
        CfnOutput(
            self,
            "EcsSecurityGroupId",
            value=self.ecs_security_group.security_group_id,
            description="ECS security group ID",
            export_name=f"{self.env_name}-ecs-sg-id",
        )
        
        CfnOutput(
            self,
            "DatabaseSecurityGroupId",
            value=self.db_security_group.security_group_id,
            description="Database security group ID",
            export_name=f"{self.env_name}-db-sg-id",
        )
    
    def _add_tags(self) -> None:
        """Add tags to VPC resources."""
        Tags.of(self.vpc).add("Name", f"{self.env_name}-vpc")
        Tags.of(self.vpc).add("Purpose", "ProtonEnvironment")
        Tags.of(self.vpc).add("Component", "Networking")


class EcsStack(Stack):
    """
    ECS Stack for AWS Proton Infrastructure
    
    Creates a production-ready ECS cluster with service discovery,
    logging, and monitoring capabilities for use with AWS Proton
    service templates.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: ec2.Vpc,
        env_name: str,
        enable_logging: bool = True,
        enable_service_discovery: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the ECS Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            vpc: The VPC where ECS cluster will be deployed
            env_name: Environment name for resource naming
            enable_logging: Whether to enable container insights
            enable_service_discovery: Whether to enable service discovery
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.vpc = vpc
        self.env_name = env_name
        
        # Create ECS cluster
        cluster_settings = []
        if enable_logging:
            cluster_settings.append(
                ecs.ClusterSetting(
                    name=ecs.ClusterSettingName.CONTAINER_INSIGHTS,
                    value="enabled"
                )
            )
        
        self.cluster = ecs.Cluster(
            self,
            "ProtonEcsCluster",
            cluster_name=f"{env_name}-cluster",
            vpc=vpc,
            cluster_settings=cluster_settings,
            enable_fargate_capacity_providers=True,
        )
        
        # Create service discovery namespace
        if enable_service_discovery:
            self.namespace = servicediscovery.PrivateDnsNamespace(
                self,
                "ServiceDiscoveryNamespace",
                name=f"{env_name}.local",
                vpc=vpc,
                description=f"Service discovery namespace for {env_name} environment",
            )
        
        # Create IAM roles
        self._create_iam_roles()
        
        # Create CloudWatch Log Group
        self.log_group = logs.LogGroup(
            self,
            "EcsLogGroup",
            log_group_name=f"/aws/ecs/{env_name}",
            retention=logs.RetentionDays.ONE_MONTH,
        )
        
        # Create outputs
        self._create_outputs()
        
        # Add tags
        self._add_tags()
    
    def _create_iam_roles(self) -> None:
        """Create IAM roles for ECS tasks and services."""
        
        # ECS Task Execution Role
        self.task_execution_role = iam.Role(
            self,
            "EcsTaskExecutionRole",
            role_name=f"{self.env_name}-ecs-task-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for ECS task execution",
        )
        
        # Attach AWS managed policy for ECS task execution
        self.task_execution_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonECSTaskExecutionRolePolicy"
            )
        )
        
        # Add permissions for ECR and CloudWatch Logs
        self.task_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )
        
        # ECS Task Role (for application permissions)
        self.task_role = iam.Role(
            self,
            "EcsTaskRole",
            role_name=f"{self.env_name}-ecs-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for ECS tasks (application permissions)",
        )
        
        # Add basic AWS SDK permissions
        self.task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "secretsmanager:GetSecretValue",
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath",
                ],
                resources=[
                    f"arn:aws:secretsmanager:{self.region}:{self.account}:secret:/apps/{self.env_name}/*",
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/apps/{self.env_name}/*",
                ],
            )
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for use by Proton templates."""
        
        # ECS Cluster outputs
        CfnOutput(
            self,
            "EcsClusterName",
            value=self.cluster.cluster_name,
            description="ECS cluster name",
            export_name=f"{self.env_name}-ecs-cluster-name",
        )
        
        CfnOutput(
            self,
            "EcsClusterArn",
            value=self.cluster.cluster_arn,
            description="ECS cluster ARN",
            export_name=f"{self.env_name}-ecs-cluster-arn",
        )
        
        # IAM Role outputs
        CfnOutput(
            self,
            "EcsTaskExecutionRoleArn",
            value=self.task_execution_role.role_arn,
            description="ECS task execution role ARN",
            export_name=f"{self.env_name}-ecs-task-execution-role-arn",
        )
        
        CfnOutput(
            self,
            "EcsTaskRoleArn",
            value=self.task_role.role_arn,
            description="ECS task role ARN",
            export_name=f"{self.env_name}-ecs-task-role-arn",
        )
        
        # Service Discovery outputs
        if hasattr(self, 'namespace'):
            CfnOutput(
                self,
                "ServiceDiscoveryNamespaceId",
                value=self.namespace.namespace_id,
                description="Service discovery namespace ID",
                export_name=f"{self.env_name}-service-discovery-namespace-id",
            )
        
        # Log Group outputs
        CfnOutput(
            self,
            "EcsLogGroupName",
            value=self.log_group.log_group_name,
            description="ECS log group name",
            export_name=f"{self.env_name}-ecs-log-group-name",
        )
    
    def _add_tags(self) -> None:
        """Add tags to ECS resources."""
        Tags.of(self.cluster).add("Name", f"{self.env_name}-ecs-cluster")
        Tags.of(self.cluster).add("Purpose", "ProtonEnvironment")
        Tags.of(self.cluster).add("Component", "Compute")


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
        self.artifacts_bucket = s3.Bucket(
            self,
            "ProtonArtifactsBucket",
            bucket_name=f"{env_name}-proton-artifacts-{self.account}",
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
            ],
        )
        
        # Create parameter store for configuration
        self.env_config_param = ssm.StringParameter(
            self,
            "EnvironmentConfigParameter",
            parameter_name=f"/apps/{env_name}/config/environment",
            string_value="production",
            description=f"Environment configuration for {env_name}",
        )
        
        # Create secrets manager for sensitive data
        self.db_secrets = secretsmanager.Secret(
            self,
            "DatabaseSecrets",
            secret_name=f"/apps/{env_name}/secrets/database",
            description=f"Database connection secrets for {env_name}",
            generate_secret_string=secretsmanager.SecretStringGenerator(
                secret_string_template='{"username": "admin"}',
                generate_string_key="password",
                exclude_characters='"@/\\',
            ),
        )
        
        # Create notification topic
        self.notification_topic = sns.Topic(
            self,
            "ProtonNotificationTopic",
            topic_name=f"{env_name}-proton-notifications",
            display_name=f"Proton Notifications - {env_name}",
        )
        
        # Create CI/CD pipeline if enabled
        if enable_cicd:
            self._create_cicd_pipeline()
        
        # Create monitoring resources if enabled
        if enable_monitoring:
            self._create_monitoring_resources()
        
        # Create outputs
        self._create_outputs()
    
    def _create_cicd_pipeline(self) -> None:
        """Create CI/CD pipeline for automated deployments."""
        
        # Create CodeCommit repository
        self.repository = codecommit.Repository(
            self,
            "ProtonRepository",
            repository_name=f"{self.env_name}-proton-apps",
            description=f"Source code repository for {self.env_name} applications",
        )
        
        # Create CodeBuild project
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
                privileged=True,
            ),
            artifacts=codebuild.Artifacts.s3(
                bucket=self.artifacts_bucket,
                include_build_id=True,
            ),
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
                ],
                width=12,
            ),
        )
        
        # Create alarms for critical metrics
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
        )
        
        cpu_alarm.add_alarm_action(
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


class ProtonCdkApp(cdk.App):
    """
    Main CDK Application for AWS Proton Infrastructure Automation
    
    This application creates standardized infrastructure components that can be
    used by AWS Proton templates to provide self-service infrastructure deployment
    capabilities for development teams.
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        aws_account = os.getenv('CDK_DEFAULT_ACCOUNT', os.getenv('AWS_ACCOUNT_ID'))
        aws_region = os.getenv('CDK_DEFAULT_REGION', os.getenv('AWS_REGION', 'us-east-1'))
        
        # Environment configuration
        env = Environment(
            account=aws_account,
            region=aws_region
        )
        
        # Environment name for resource naming
        env_name = os.getenv('ENVIRONMENT_NAME', 'proton-demo')
        
        # Create VPC stack for networking infrastructure
        vpc_stack = VpcStack(
            self,
            f"{env_name}-vpc-stack",
            env_name=env_name,
            env=env,
            description="VPC infrastructure for AWS Proton environments"
        )
        
        # Create ECS stack for container orchestration
        ecs_stack = EcsStack(
            self,
            f"{env_name}-ecs-stack",
            vpc=vpc_stack.vpc,
            env_name=env_name,
            env=env,
            description="ECS cluster infrastructure for AWS Proton services"
        )
        
        # Create main Proton infrastructure stack
        proton_stack = ProtonInfrastructureStack(
            self,
            f"{env_name}-proton-stack",
            vpc=vpc_stack.vpc,
            ecs_cluster=ecs_stack.cluster,
            env_name=env_name,
            env=env,
            description="AWS Proton infrastructure automation components"
        )
        
        # Stack dependencies
        ecs_stack.add_dependency(vpc_stack)
        proton_stack.add_dependency(vpc_stack)
        proton_stack.add_dependency(ecs_stack)
        
        # Add common tags to all resources
        Tags.of(self).add("Project", "ProtonInfrastructureAutomation")
        Tags.of(self).add("Environment", env_name)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "ProtonTemplateInfrastructure")


# Create and deploy the application
app = ProtonCdkApp()
app.synth()