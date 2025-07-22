#!/usr/bin/env python3
"""
CDK Python application for GitOps Workflows with AWS CodeCommit and CodeBuild.

This application creates a complete GitOps workflow infrastructure including:
- CodeCommit repository for source control
- ECR repository for container images
- CodeBuild project for automated builds
- ECS cluster and task definition for container deployment
- IAM roles and policies with least privilege access
- CloudWatch log groups for monitoring

Author: AWS CDK Generator
Version: 1.0.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from aws_cdk import aws_codecommit as codecommit
from aws_cdk import aws_codebuild as codebuild
from aws_cdk import aws_ecr as ecr
from aws_cdk import aws_ecs as ecs
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_ec2 as ec2
from constructs import Construct


class GitOpsWorkflowStack(Stack):
    """
    CDK Stack for GitOps Workflows with AWS CodeCommit and CodeBuild.
    
    This stack creates a complete GitOps infrastructure that enables automated
    CI/CD workflows triggered by Git operations. The architecture follows
    GitOps best practices with declarative deployments and audit trails.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        environment_name: str = "dev",
        **kwargs: Any
    ) -> None:
        """
        Initialize the GitOps Workflow Stack.
        
        Args:
            scope: The CDK construct scope
            construct_id: The CDK construct ID
            project_name: Name of the project (used for resource naming)
            environment_name: Environment name (dev, staging, prod)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.environment_name = environment_name

        # Create core infrastructure components
        self.repository = self._create_codecommit_repository()
        self.ecr_repository = self._create_ecr_repository()
        self.ecs_cluster = self._create_ecs_cluster()
        self.vpc = self._create_vpc()
        self.log_group = self._create_log_group()
        
        # Create IAM roles
        self.codebuild_role = self._create_codebuild_role()
        self.ecs_task_role = self._create_ecs_task_role()
        self.ecs_execution_role = self._create_ecs_execution_role()
        
        # Create build project
        self.build_project = self._create_codebuild_project()
        
        # Create ECS task definition
        self.task_definition = self._create_ecs_task_definition()
        
        # Create ECS service
        self.ecs_service = self._create_ecs_service()

        # Add tags to all resources
        self._add_tags()

        # Create outputs
        self._create_outputs()

    def _create_codecommit_repository(self) -> codecommit.Repository:
        """
        Create CodeCommit repository for GitOps source control.
        
        Returns:
            CodeCommit repository construct
        """
        repository = codecommit.Repository(
            self,
            "GitOpsRepository",
            repository_name=f"{self.project_name}-gitops-repo",
            description=f"GitOps repository for {self.project_name} automated deployments",
        )
        
        # Enable repository events for trigger automation
        repository.on_commit(
            "OnCommitTrigger",
            description="Trigger builds on commit to main branch",
            branches=["main"]
        )
        
        return repository

    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create ECR repository for container images.
        
        Returns:
            ECR repository construct
        """
        repository = ecr.Repository(
            self,
            "ContainerRepository",
            repository_name=f"{self.project_name}-app",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep last 10 images",
                    max_image_count=10,
                    tag_status=ecr.TagStatus.ANY,
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return repository

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC for ECS cluster.
        
        Returns:
            VPC construct
        """
        vpc = ec2.Vpc(
            self,
            "GitOpsVPC",
            vpc_name=f"{self.project_name}-vpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
        )
        
        return vpc

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """
        Create ECS cluster for container deployment.
        
        Returns:
            ECS cluster construct
        """
        cluster = ecs.Cluster(
            self,
            "GitOpsCluster",
            cluster_name=f"{self.project_name}-cluster",
            vpc=self.vpc,
            container_insights=True,
        )
        
        return cluster

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for application logs.
        
        Returns:
            CloudWatch log group construct
        """
        log_group = logs.LogGroup(
            self,
            "ApplicationLogGroup",
            log_group_name=f"/ecs/{self.project_name}-app",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_codebuild_role(self) -> iam.Role:
        """
        Create IAM role for CodeBuild with necessary permissions.
        
        Returns:
            IAM role construct
        """
        role = iam.Role(
            self,
            "CodeBuildRole",
            role_name=f"{self.project_name}-codebuild-role",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
            description="Role for CodeBuild to perform GitOps operations",
        )
        
        # Add necessary permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/codebuild/{self.project_name}*",
                ],
            )
        )
        
        # ECR permissions for pushing images
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:GetAuthorizationToken",
                ],
                resources=["*"],
            )
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:PutImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                ],
                resources=[self.ecr_repository.repository_arn],
            )
        )
        
        # ECS permissions for deployment
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecs:UpdateService",
                    "ecs:DescribeServices",
                    "ecs:DescribeTaskDefinition",
                    "ecs:RegisterTaskDefinition",
                ],
                resources=["*"],
            )
        )
        
        return role

    def _create_ecs_task_role(self) -> iam.Role:
        """
        Create IAM role for ECS tasks.
        
        Returns:
            IAM role construct
        """
        role = iam.Role(
            self,
            "ECSTaskRole",
            role_name=f"{self.project_name}-ecs-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="Role for ECS tasks to access AWS services",
        )
        
        # Add basic permissions for application
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[self.log_group.log_group_arn],
            )
        )
        
        return role

    def _create_ecs_execution_role(self) -> iam.Role:
        """
        Create IAM execution role for ECS tasks.
        
        Returns:
            IAM role construct
        """
        role = iam.Role(
            self,
            "ECSExecutionRole",
            role_name=f"{self.project_name}-ecs-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
            description="Execution role for ECS tasks",
        )
        
        return role

    def _create_codebuild_project(self) -> codebuild.Project:
        """
        Create CodeBuild project for automated builds.
        
        Returns:
            CodeBuild project construct
        """
        # Create buildspec configuration
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "phases": {
                "pre_build": {
                    "commands": [
                        "echo Logging in to Amazon ECR...",
                        "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REPOSITORY_URI",
                        "COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)",
                        "IMAGE_TAG=$COMMIT_HASH",
                        "echo Build started on `date`",
                    ]
                },
                "build": {
                    "commands": [
                        "echo Build started on `date`",
                        "echo Building the Docker image...",
                        "cd app",
                        "docker build -t $ECR_REPOSITORY_URI:latest .",
                        "docker tag $ECR_REPOSITORY_URI:latest $ECR_REPOSITORY_URI:$IMAGE_TAG",
                    ]
                },
                "post_build": {
                    "commands": [
                        "echo Build completed on `date`",
                        "echo Pushing the Docker images...",
                        "docker push $ECR_REPOSITORY_URI:latest",
                        "docker push $ECR_REPOSITORY_URI:$IMAGE_TAG",
                        "echo Writing image definitions file...",
                        "printf '[{\"name\":\"gitops-app\",\"imageUri\":\"%s\"}]' $ECR_REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json",
                    ]
                }
            },
            "artifacts": {
                "files": [
                    "imagedefinitions.json",
                    "infrastructure/**/*"
                ],
                "name": "GitOpsArtifacts"
            }
        })
        
        project = codebuild.Project(
            self,
            "GitOpsBuildProject",
            project_name=f"{self.project_name}-build",
            description="GitOps build project for automated deployments",
            source=codebuild.Source.code_commit(
                repository=self.repository,
                branch_or_ref="main",
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_5,
                compute_type=codebuild.ComputeType.SMALL,
                privileged=True,  # Required for Docker builds
            ),
            environment_variables={
                "ECR_REPOSITORY_URI": codebuild.BuildEnvironmentVariable(
                    value=self.ecr_repository.repository_uri
                ),
                "AWS_DEFAULT_REGION": codebuild.BuildEnvironmentVariable(
                    value=self.region
                ),
                "AWS_ACCOUNT_ID": codebuild.BuildEnvironmentVariable(
                    value=self.account
                ),
            },
            role=self.codebuild_role,
            build_spec=buildspec,
            timeout=Duration.minutes(60),
        )
        
        return project

    def _create_ecs_task_definition(self) -> ecs.FargateTaskDefinition:
        """
        Create ECS task definition for the application.
        
        Returns:
            ECS task definition construct
        """
        task_definition = ecs.FargateTaskDefinition(
            self,
            "GitOpsTaskDefinition",
            family=f"{self.project_name}-app-task",
            cpu=256,
            memory_limit_mib=512,
            task_role=self.ecs_task_role,
            execution_role=self.ecs_execution_role,
        )
        
        # Add container to task definition
        container = task_definition.add_container(
            "GitOpsAppContainer",
            image=ecs.ContainerImage.from_ecr_repository(
                self.ecr_repository,
                tag="latest"
            ),
            environment={
                "ENVIRONMENT": self.environment_name,
                "APP_VERSION": "1.0.0",
                "NODE_ENV": "production",
            },
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group,
            ),
            health_check=ecs.HealthCheck(
                command=["CMD-SHELL", "curl -f http://localhost:3000/health || exit 1"],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )
        
        # Add port mapping
        container.add_port_mappings(
            ecs.PortMapping(
                container_port=3000,
                protocol=ecs.Protocol.TCP,
            )
        )
        
        return task_definition

    def _create_ecs_service(self) -> ecs.FargateService:
        """
        Create ECS service for running the application.
        
        Returns:
            ECS service construct
        """
        service = ecs.FargateService(
            self,
            "GitOpsService",
            service_name=f"{self.project_name}-service",
            cluster=self.ecs_cluster,
            task_definition=self.task_definition,
            desired_count=1,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            platform_version=ecs.FargatePlatformVersion.LATEST,
            health_check_grace_period=Duration.seconds(300),
            enable_logging=True,
        )
        
        return service

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", self.environment_name)
        Tags.of(self).add("GitOps", "true")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Owner", "GitOps-Team")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "RepositoryName",
            value=self.repository.repository_name,
            description="Name of the CodeCommit repository",
        )
        
        CfnOutput(
            self,
            "RepositoryCloneUrl",
            value=self.repository.repository_clone_url_http,
            description="HTTPS clone URL for the repository",
        )
        
        CfnOutput(
            self,
            "ECRRepositoryUri",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository",
        )
        
        CfnOutput(
            self,
            "BuildProjectName",
            value=self.build_project.project_name,
            description="Name of the CodeBuild project",
        )
        
        CfnOutput(
            self,
            "ECSClusterName",
            value=self.ecs_cluster.cluster_name,
            description="Name of the ECS cluster",
        )
        
        CfnOutput(
            self,
            "ECSServiceName",
            value=self.ecs_service.service_name,
            description="Name of the ECS service",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()
    
    # Get configuration from context or environment variables
    project_name = app.node.try_get_context("project_name") or os.getenv("PROJECT_NAME", "gitops-demo")
    environment_name = app.node.try_get_context("environment") or os.getenv("ENVIRONMENT", "dev")
    aws_account = app.node.try_get_context("aws_account") or os.getenv("CDK_DEFAULT_ACCOUNT")
    aws_region = app.node.try_get_context("aws_region") or os.getenv("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create the stack
    GitOpsWorkflowStack(
        app,
        f"GitOpsWorkflowStack-{environment_name}",
        project_name=project_name,
        environment_name=environment_name,
        env=Environment(
            account=aws_account,
            region=aws_region,
        ),
        description=f"GitOps workflow infrastructure for {project_name} ({environment_name})",
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()