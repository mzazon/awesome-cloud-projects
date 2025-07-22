#!/usr/bin/env python3
"""
AWS App2Container Modernization CDK Application

This CDK application provisions the complete infrastructure needed for application
modernization using AWS App2Container, including ECS cluster, ECR repository,
CI/CD pipeline, and supporting services.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ecs as ecs,
    aws_ecr as ecr,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_s3 as s3,
    aws_codecommit as codecommit,
    aws_codebuild as codebuild,
    aws_codepipeline as codepipeline,
    aws_codepipeline_actions as codepipeline_actions,
    aws_elbv2 as elbv2,
    aws_logs as logs,
    aws_secretsmanager as secretsmanager,
    aws_applicationautoscaling as appautoscaling,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class App2ContainerStack(Stack):
    """
    CDK Stack for AWS App2Container modernization infrastructure.
    
    This stack creates all the necessary AWS resources for containerizing
    and deploying legacy applications using App2Container.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        self.unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create VPC for container infrastructure
        self.vpc = self._create_vpc()
        
        # Create S3 bucket for App2Container artifacts
        self.artifacts_bucket = self._create_artifacts_bucket()
        
        # Create ECR repository for container images
        self.ecr_repository = self._create_ecr_repository()
        
        # Create ECS cluster
        self.ecs_cluster = self._create_ecs_cluster()
        
        # Create CodeCommit repository
        self.code_repository = self._create_code_repository()
        
        # Create IAM roles for App2Container and services
        self.app2container_role = self._create_app2container_role()
        self.ecs_task_role = self._create_ecs_task_role()
        self.ecs_execution_role = self._create_ecs_execution_role()
        
        # Create Application Load Balancer
        self.load_balancer = self._create_load_balancer()
        
        # Create target group (will be used by ECS service)
        self.target_group = self._create_target_group()
        
        # Create CI/CD pipeline
        self.pipeline = self._create_cicd_pipeline()
        
        # Create CloudWatch Log Group
        self.log_group = self._create_log_group()
        
        # Create CloudWatch Dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Output important resource information
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public and private subnets."""
        return ec2.Vpc(
            self, "App2ContainerVpc",
            vpc_name=f"app2container-vpc-{self.unique_suffix}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """Create S3 bucket for App2Container artifacts storage."""
        return s3.Bucket(
            self, "ArtifactsBucket",
            bucket_name=f"app2container-artifacts-{self.unique_suffix}-{self.account}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30)
                )
            ]
        )

    def _create_ecr_repository(self) -> ecr.Repository:
        """Create ECR repository for container images."""
        return ecr.Repository(
            self, "ContainerRepository",
            repository_name=f"modernized-app-{self.unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only 10 latest images",
                    max_image_count=10
                )
            ]
        )

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """Create ECS cluster with Fargate capacity providers."""
        cluster = ecs.Cluster(
            self, "EcsCluster",
            cluster_name=f"app2container-cluster-{self.unique_suffix}",
            vpc=self.vpc,
            container_insights=True
        )
        
        # Add Fargate capacity providers
        cluster.add_default_capacity_provider("FARGATE")
        cluster.add_default_capacity_provider("FARGATE_SPOT")
        
        return cluster

    def _create_code_repository(self) -> codecommit.Repository:
        """Create CodeCommit repository for CI/CD pipeline."""
        return codecommit.Repository(
            self, "CodeRepository",
            repository_name=f"app2container-pipeline-{self.unique_suffix}",
            description="Repository for App2Container modernization pipeline"
        )

    def _create_app2container_role(self) -> iam.Role:
        """Create IAM role for App2Container operations."""
        role = iam.Role(
            self, "App2ContainerRole",
            role_name=f"App2ContainerRole-{self.unique_suffix}",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("ec2.amazonaws.com"),
                iam.AccountRootPrincipal()
            ),
            description="IAM role for App2Container operations"
        )
        
        # Add necessary permissions for App2Container
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket"
            ],
            resources=[
                self.artifacts_bucket.bucket_arn,
                f"{self.artifacts_bucket.bucket_arn}/*"
            ]
        ))
        
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload",
                "ecr:PutImage"
            ],
            resources=["*"]
        ))
        
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ecs:CreateCluster",
                "ecs:CreateService",
                "ecs:CreateTaskDefinition",
                "ecs:DescribeClusters",
                "ecs:DescribeServices",
                "ecs:DescribeTaskDefinition",
                "ecs:DescribeTasks",
                "ecs:ListClusters",
                "ecs:ListServices",
                "ecs:ListTaskDefinitions",
                "ecs:ListTasks",
                "ecs:RegisterTaskDefinition",
                "ecs:UpdateService"
            ],
            resources=["*"]
        ))
        
        return role

    def _create_ecs_task_role(self) -> iam.Role:
        """Create IAM role for ECS tasks."""
        role = iam.Role(
            self, "EcsTaskRole",
            role_name=f"EcsTaskRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for ECS tasks"
        )
        
        # Add necessary permissions for containerized applications
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret"
            ],
            resources=["*"]
        ))
        
        return role

    def _create_ecs_execution_role(self) -> iam.Role:
        """Create IAM execution role for ECS tasks."""
        role = iam.Role(
            self, "EcsExecutionRole",
            role_name=f"EcsExecutionRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM execution role for ECS tasks",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ]
        )
        
        # Add additional permissions for ECR and CloudWatch
        role.add_to_policy(iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ecr:GetAuthorizationToken",
                "ecr:BatchCheckLayerAvailability",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage"
            ],
            resources=["*"]
        ))
        
        return role

    def _create_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """Create Application Load Balancer for container services."""
        security_group = ec2.SecurityGroup(
            self, "LoadBalancerSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=True
        )
        
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic"
        )
        
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic"
        )
        
        return elbv2.ApplicationLoadBalancer(
            self, "LoadBalancer",
            vpc=self.vpc,
            internet_facing=True,
            security_group=security_group,
            load_balancer_name=f"app2container-alb-{self.unique_suffix}"
        )

    def _create_target_group(self) -> elbv2.ApplicationTargetGroup:
        """Create target group for load balancer."""
        return elbv2.ApplicationTargetGroup(
            self, "TargetGroup",
            vpc=self.vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(30),
                interval=Duration.seconds(60),
                path="/health"
            ),
            target_group_name=f"app2container-tg-{self.unique_suffix}"
        )

    def _create_cicd_pipeline(self) -> codepipeline.Pipeline:
        """Create CI/CD pipeline for automated deployments."""
        # Create CodeBuild project
        build_project = codebuild.Project(
            self, "BuildProject",
            project_name=f"app2container-build-{self.unique_suffix}",
            source=codebuild.Source.code_commit(
                repository=self.code_repository
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.STANDARD_7_0,
                privileged=True,
                compute_type=codebuild.ComputeType.SMALL,
                environment_variables={
                    "AWS_DEFAULT_REGION": codebuild.BuildEnvironmentVariable(
                        value=self.region
                    ),
                    "AWS_ACCOUNT_ID": codebuild.BuildEnvironmentVariable(
                        value=self.account
                    ),
                    "IMAGE_REPO_NAME": codebuild.BuildEnvironmentVariable(
                        value=self.ecr_repository.repository_name
                    ),
                    "IMAGE_TAG": codebuild.BuildEnvironmentVariable(
                        value="latest"
                    )
                }
            ),
            build_spec=codebuild.BuildSpec.from_object({
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
                }
            })
        )
        
        # Grant permissions to CodeBuild
        self.ecr_repository.grant_pull_push(build_project.role)
        
        # Create pipeline artifacts
        source_output = codepipeline.Artifact("SourceOutput")
        build_output = codepipeline.Artifact("BuildOutput")
        
        # Create pipeline
        pipeline = codepipeline.Pipeline(
            self, "Pipeline",
            pipeline_name=f"app2container-pipeline-{self.unique_suffix}",
            stages=[
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.CodeCommitSourceAction(
                            action_name="CodeCommit",
                            repository=self.code_repository,
                            output=source_output,
                            branch="main"
                        )
                    ]
                ),
                codepipeline.StageProps(
                    stage_name="Build",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="Build",
                            project=build_project,
                            input=source_output,
                            outputs=[build_output]
                        )
                    ]
                )
            ]
        )
        
        return pipeline

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for ECS tasks."""
        return logs.LogGroup(
            self, "LogGroup",
            log_group_name=f"/aws/ecs/app2container-{self.unique_suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring."""
        dashboard = cloudwatch.Dashboard(
            self, "Dashboard",
            dashboard_name=f"App2Container-{self.unique_suffix}"
        )
        
        # Add ECS cluster metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="ECS Cluster CPU Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ECS",
                        metric_name="CPUUtilization",
                        dimensions_map={
                            "ClusterName": self.ecs_cluster.cluster_name
                        },
                        statistic="Average",
                        period=Duration.minutes(5)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        # Add ALB metrics widget
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Application Load Balancer Request Count",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ApplicationELB",
                        metric_name="RequestCount",
                        dimensions_map={
                            "LoadBalancer": self.load_balancer.load_balancer_full_name
                        },
                        statistic="Sum",
                        period=Duration.minutes(5)
                    )
                ],
                width=12,
                height=6
            )
        )
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the App2Container infrastructure",
            export_name=f"App2Container-VpcId-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "EcsClusterName",
            value=self.ecs_cluster.cluster_name,
            description="ECS Cluster name for containerized applications",
            export_name=f"App2Container-EcsCluster-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "EcrRepositoryUri",
            value=self.ecr_repository.repository_uri,
            description="ECR Repository URI for container images",
            export_name=f"App2Container-EcrRepository-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "S3BucketName",
            value=self.artifacts_bucket.bucket_name,
            description="S3 Bucket for App2Container artifacts",
            export_name=f"App2Container-S3Bucket-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "CodeCommitRepositoryCloneUrl",
            value=self.code_repository.repository_clone_url_ssh,
            description="CodeCommit repository clone URL",
            export_name=f"App2Container-CodeCommitRepo-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "LoadBalancerDnsName",
            value=self.load_balancer.load_balancer_dns_name,
            description="Application Load Balancer DNS name",
            export_name=f"App2Container-LoadBalancer-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "App2ContainerRoleArn",
            value=self.app2container_role.role_arn,
            description="IAM Role ARN for App2Container operations",
            export_name=f"App2Container-Role-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "EcsTaskRoleArn",
            value=self.ecs_task_role.role_arn,
            description="IAM Role ARN for ECS tasks",
            export_name=f"App2Container-EcsTaskRole-{self.unique_suffix}"
        )
        
        CfnOutput(
            self, "EcsExecutionRoleArn",
            value=self.ecs_execution_role.role_arn,
            description="IAM Execution Role ARN for ECS tasks",
            export_name=f"App2Container-EcsExecutionRole-{self.unique_suffix}"
        )


# CDK Application
app = cdk.App()

# Get deployment environment from context or use default
env = Environment(
    account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
    region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
)

# Create the stack
App2ContainerStack(
    app, "App2ContainerStack",
    env=env,
    description="AWS App2Container modernization infrastructure stack"
)

# Add stack tags
cdk.Tags.of(app).add("Project", "App2Container")
cdk.Tags.of(app).add("Environment", "Development")
cdk.Tags.of(app).add("Owner", "DevOps")

app.synth()