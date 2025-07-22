#!/usr/bin/env python3
"""
CDK Python application for ECS Task Definitions with Environment Variable Management.

This application demonstrates comprehensive environment variable management for Amazon ECS
task definitions using AWS Systems Manager Parameter Store, AWS Secrets Manager, and 
environment files stored in S3.
"""

from aws_cdk import (
    App,
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_ecs as ecs,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    aws_ssm as ssm,
    aws_logs as logs,
    aws_s3_deployment as s3deploy,
)
from constructs import Construct
from typing import Dict, List, Optional
import os


class EcsEnvironmentVariableStack(Stack):
    """
    CDK Stack that implements ECS Task Definitions with comprehensive environment
    variable management using Parameter Store, Secrets Manager, and S3 environment files.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        app_name: str = "envvar-demo",
        environment: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the ECS Environment Variable Management stack.

        Args:
            scope: CDK scope
            construct_id: Stack identifier
            app_name: Application name for resource naming
            environment: Environment name (dev, staging, prod)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.app_name = app_name
        self.environment = environment

        # Create VPC for ECS cluster
        self.vpc = self._create_vpc()

        # Create S3 bucket for environment files
        self.config_bucket = self._create_config_bucket()

        # Create Systems Manager parameters
        self._create_ssm_parameters()

        # Create IAM roles for ECS tasks
        self.task_execution_role = self._create_task_execution_role()
        self.task_role = self._create_task_role()

        # Create ECS cluster
        self.cluster = self._create_ecs_cluster()

        # Create CloudWatch log groups
        self.log_group = self._create_log_group()

        # Create ECS task definitions with different environment variable approaches
        self.basic_task_definition = self._create_basic_task_definition()
        self.envfiles_task_definition = self._create_envfiles_task_definition()
        self.hybrid_task_definition = self._create_hybrid_task_definition()

        # Create ECS services
        self.basic_service = self._create_ecs_service(
            "basic-service", self.basic_task_definition
        )
        self.envfiles_service = self._create_ecs_service(
            "envfiles-service", self.envfiles_task_definition
        )

        # Upload environment files to S3
        self._deploy_environment_files()

        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC for ECS cluster with public and private subnets."""
        vpc = ec2.Vpc(
            self,
            "EcsVpc",
            vpc_name=f"{self.app_name}-vpc",
            max_azs=2,
            nat_gateways=1,
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

        return vpc

    def _create_config_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing environment configuration files."""
        bucket = s3.Bucket(
            self,
            "ConfigBucket",
            bucket_name=f"{self.app_name}-configs-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        return bucket

    def _create_ssm_parameters(self) -> None:
        """Create Systems Manager Parameter Store parameters for configuration management."""
        # Database configuration parameters
        ssm.StringParameter(
            self,
            "DatabaseHost",
            parameter_name=f"/myapp/{self.environment}/database/host",
            string_value=f"{self.environment}-database.internal.com",
            description=f"{self.environment.title()} database host",
        )

        ssm.StringParameter(
            self,
            "DatabasePort",
            parameter_name=f"/myapp/{self.environment}/database/port",
            string_value="5432",
            description=f"{self.environment.title()} database port",
        )

        # API configuration parameters
        ssm.StringParameter(
            self,
            "ApiDebug",
            parameter_name=f"/myapp/{self.environment}/api/debug",
            string_value="true" if self.environment == "dev" else "false",
            description=f"{self.environment.title()} API debug mode",
        )

        # Secure parameters for sensitive data
        ssm.StringParameter(
            self,
            "DatabasePassword",
            parameter_name=f"/myapp/{self.environment}/database/password",
            string_value=f"{self.environment}-secure-password-123",
            type=ssm.ParameterType.SECURE_STRING,
            description=f"{self.environment.title()} database password",
        )

        ssm.StringParameter(
            self,
            "ApiSecretKey",
            parameter_name=f"/myapp/{self.environment}/api/secret-key",
            string_value=f"{self.environment}-api-secret-key-456",
            type=ssm.ParameterType.SECURE_STRING,
            description=f"{self.environment.title()} API secret key",
        )

        # Shared parameters
        ssm.StringParameter(
            self,
            "SharedRegion",
            parameter_name="/myapp/shared/region",
            string_value=self.region,
            description="Shared region parameter",
        )

        ssm.StringParameter(
            self,
            "SharedAccountId",
            parameter_name="/myapp/shared/account-id",
            string_value=self.account,
            description="Shared account ID parameter",
        )

    def _create_task_execution_role(self) -> iam.Role:
        """Create IAM role for ECS task execution with Parameter Store and S3 access."""
        role = iam.Role(
            self,
            "EcsTaskExecutionRole",
            role_name=f"{self.app_name}-task-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="ECS Task Execution Role with Parameter Store and S3 access",
        )

        # Attach AWS managed policy for ECS task execution
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AmazonECSTaskExecutionRolePolicy"
            )
        )

        # Add custom policy for Systems Manager Parameter Store access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:GetParameters",
                    "ssm:GetParameter",
                    "ssm:GetParametersByPath",
                ],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/myapp/*"
                ],
            )
        )

        # Add policy for S3 environment files access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject"],
                resources=[f"{self.config_bucket.bucket_arn}/configs/*"],
            )
        )

        # Add policy for CloudWatch Logs
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[f"arn:aws:logs:{self.region}:{self.account}:*"],
            )
        )

        return role

    def _create_task_role(self) -> iam.Role:
        """Create IAM role for ECS tasks with application-specific permissions."""
        role = iam.Role(
            self,
            "EcsTaskRole",
            role_name=f"{self.app_name}-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="ECS Task Role for application runtime permissions",
        )

        # Add policies for application runtime access to AWS services
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                ],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/myapp/shared/*"
                ],
            )
        )

        return role

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """Create ECS cluster with Fargate capacity providers."""
        cluster = ecs.Cluster(
            self,
            "EcsCluster",
            cluster_name=f"{self.app_name}-cluster",
            vpc=self.vpc,
            container_insights=True,
        )

        # Add Fargate capacity providers
        cluster.add_capacity(
            "FargateCapacity",
            min_capacity=0,
            max_capacity=10,
            desired_capacity=1,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
        )

        return cluster

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for ECS tasks."""
        log_group = logs.LogGroup(
            self,
            "EcsLogGroup",
            log_group_name=f"/ecs/{self.app_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_basic_task_definition(self) -> ecs.FargateTaskDefinition:
        """Create basic task definition with direct environment variables and Parameter Store secrets."""
        task_definition = ecs.FargateTaskDefinition(
            self,
            "BasicTaskDefinition",
            family=f"{self.app_name}-basic",
            cpu=256,
            memory_limit_mib=512,
            execution_role=self.task_execution_role,
            task_role=self.task_role,
        )

        # Add container with mixed environment variable sources
        container = task_definition.add_container(
            "app-container",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            essential=True,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group,
            ),
            environment={
                "NODE_ENV": self.environment,
                "SERVICE_NAME": f"{self.app_name}-basic-service",
                "CLUSTER_NAME": self.cluster.cluster_name,
                "DEPLOYMENT_TYPE": "basic-envvars",
            },
            secrets={
                "DATABASE_HOST": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "DatabaseHostParam", f"/myapp/{self.environment}/database/host"
                    )
                ),
                "DATABASE_PORT": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "DatabasePortParam", f"/myapp/{self.environment}/database/port"
                    )
                ),
                "DATABASE_PASSWORD": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "DatabasePasswordParam", f"/myapp/{self.environment}/database/password"
                    )
                ),
                "API_SECRET_KEY": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "ApiSecretKeyParam", f"/myapp/{self.environment}/api/secret-key"
                    )
                ),
                "API_DEBUG": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "ApiDebugParam", f"/myapp/{self.environment}/api/debug"
                    )
                ),
            },
        )

        # Add port mapping
        container.add_port_mappings(
            ecs.PortMapping(container_port=80, protocol=ecs.Protocol.TCP)
        )

        return task_definition

    def _create_envfiles_task_definition(self) -> ecs.FargateTaskDefinition:
        """Create task definition focused on environment files from S3."""
        task_definition = ecs.FargateTaskDefinition(
            self,
            "EnvFilesTaskDefinition",
            family=f"{self.app_name}-envfiles",
            cpu=256,
            memory_limit_mib=512,
            execution_role=self.task_execution_role,
            task_role=self.task_role,
        )

        # Add container with environment files
        container = task_definition.add_container(
            "app-container",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            essential=True,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group,
            ),
            environment={
                "DEPLOYMENT_TYPE": "environment-files",
                "SERVICE_NAME": f"{self.app_name}-envfiles-service",
            },
            environment_files=[
                ecs.EnvironmentFile.from_s3(
                    self.config_bucket, "configs/app-config.env"
                ),
                ecs.EnvironmentFile.from_s3(
                    self.config_bucket, "configs/prod-config.env"
                ),
            ],
        )

        # Add port mapping
        container.add_port_mappings(
            ecs.PortMapping(container_port=80, protocol=ecs.Protocol.TCP)
        )

        return task_definition

    def _create_hybrid_task_definition(self) -> ecs.FargateTaskDefinition:
        """Create task definition combining all environment variable approaches."""
        task_definition = ecs.FargateTaskDefinition(
            self,
            "HybridTaskDefinition",
            family=f"{self.app_name}-hybrid",
            cpu=256,
            memory_limit_mib=512,
            execution_role=self.task_execution_role,
            task_role=self.task_role,
        )

        # Add container with hybrid approach
        container = task_definition.add_container(
            "app-container",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            essential=True,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group,
            ),
            environment={
                "NODE_ENV": self.environment,
                "SERVICE_NAME": f"{self.app_name}-hybrid-service",
                "DEPLOYMENT_TYPE": "hybrid-approach",
            },
            secrets={
                "DATABASE_PASSWORD": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "HybridDatabasePasswordParam", 
                        f"/myapp/{self.environment}/database/password"
                    )
                ),
                "API_SECRET_KEY": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "HybridApiSecretKeyParam", 
                        f"/myapp/{self.environment}/api/secret-key"
                    )
                ),
            },
            environment_files=[
                ecs.EnvironmentFile.from_s3(
                    self.config_bucket, "configs/app-config.env"
                ),
            ],
        )

        # Add port mapping
        container.add_port_mappings(
            ecs.PortMapping(container_port=80, protocol=ecs.Protocol.TCP)
        )

        return task_definition

    def _create_ecs_service(
        self, service_name: str, task_definition: ecs.FargateTaskDefinition
    ) -> ecs.FargateService:
        """Create ECS Fargate service."""
        service = ecs.FargateService(
            self,
            f"{service_name}-Service",
            service_name=f"{self.app_name}-{service_name}",
            cluster=self.cluster,
            task_definition=task_definition,
            desired_count=1,
            assign_public_ip=False,
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS),
            enable_logging=True,
        )

        return service

    def _deploy_environment_files(self) -> None:
        """Deploy environment configuration files to S3 bucket."""
        # Create app-config.env content
        app_config_content = """LOG_LEVEL=info
MAX_CONNECTIONS=100
TIMEOUT_SECONDS=30
FEATURE_FLAGS=auth,logging,metrics
APP_VERSION=1.2.3
"""

        # Create prod-config.env content
        prod_config_content = """LOG_LEVEL=warn
MAX_CONNECTIONS=500
TIMEOUT_SECONDS=60
FEATURE_FLAGS=auth,logging,metrics,cache
APP_VERSION=1.2.3
MONITORING_ENABLED=true
"""

        # Deploy environment files using S3 deployment
        s3deploy.BucketDeployment(
            self,
            "DeployEnvironmentFiles",
            sources=[
                s3deploy.Source.data("configs/app-config.env", app_config_content),
                s3deploy.Source.data("configs/prod-config.env", prod_config_content),
            ],
            destination_bucket=self.config_bucket,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="ECS Cluster name",
        )

        CfnOutput(
            self,
            "ConfigBucketName",
            value=self.config_bucket.bucket_name,
            description="S3 bucket for environment configuration files",
        )

        CfnOutput(
            self,
            "BasicTaskDefinitionArn",
            value=self.basic_task_definition.task_definition_arn,
            description="Basic task definition ARN",
        )

        CfnOutput(
            self,
            "EnvFilesTaskDefinitionArn",
            value=self.envfiles_task_definition.task_definition_arn,
            description="Environment files task definition ARN",
        )

        CfnOutput(
            self,
            "HybridTaskDefinitionArn",
            value=self.hybrid_task_definition.task_definition_arn,
            description="Hybrid approach task definition ARN",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group name",
        )

        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
        )


# CDK Application
app = App()

# Get environment parameters from context or use defaults
app_name = app.node.try_get_context("app_name") or "envvar-demo"
environment = app.node.try_get_context("environment") or "dev"

# Create the stack
EcsEnvironmentVariableStack(
    app,
    "EcsEnvironmentVariableStack",
    app_name=app_name,
    environment=environment,
    description="ECS Task Definitions with Environment Variable Management using Parameter Store, Secrets Manager, and S3",
)

app.synth()