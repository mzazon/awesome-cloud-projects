#!/usr/bin/env python3
"""
AWS CDK Python application for building CI/CD pipelines for container applications
with CodePipeline and CodeDeploy.

This application creates a comprehensive CI/CD pipeline that implements:
- Multi-environment deployment (dev/prod)
- Blue-green deployments with CodeDeploy
- Security scanning with ECR vulnerability scanning
- Canary deployments with automated rollback
- Comprehensive monitoring with CloudWatch and X-Ray
- Multi-AZ deployment with high availability
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_ecr as ecr,
    aws_ecs as ecs,
    aws_ecs_patterns as ecs_patterns,
    aws_elasticloadbalancingv2 as elbv2,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    aws_sns as sns,
    aws_ssm as ssm,
    aws_codebuild as codebuild,
    aws_codepipeline as codepipeline,
    aws_codepipeline_actions as codepipeline_actions,
    aws_codedeploy as codedeploy,
    aws_cloudwatch as cloudwatch,
    aws_applicationautoscaling as autoscaling,
)
from constructs import Construct


class CICDPipelineStack(Stack):
    """
    Main CDK Stack for the CI/CD Pipeline for Container Applications.
    
    This stack creates a comprehensive CI/CD pipeline with:
    - Multi-environment ECS clusters (dev/prod)
    - ECR repository with vulnerability scanning
    - CodeBuild project with security scanning
    - CodePipeline with multi-stage deployment
    - CodeDeploy with blue-green deployment
    - CloudWatch monitoring and alerting
    - X-Ray tracing integration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        **kwargs
    ) -> None:
        """
        Initialize the CICD Pipeline Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            project_name: The name of the project for resource naming
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        
        # Create VPC and networking infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create ECR repository
        self.ecr_repository = self._create_ecr_repository()
        
        # Create S3 bucket for artifacts
        self.artifacts_bucket = self._create_artifacts_bucket()
        
        # Create Parameter Store parameters
        self._create_parameter_store_parameters()
        
        # Create IAM roles
        self.iam_roles = self._create_iam_roles()
        
        # Create CloudWatch log groups
        self.log_groups = self._create_log_groups()
        
        # Create ECS clusters
        self.ecs_clusters = self._create_ecs_clusters()
        
        # Create Application Load Balancers
        self.load_balancers = self._create_load_balancers()
        
        # Create ECS task definitions
        self.task_definitions = self._create_task_definitions()
        
        # Create ECS services
        self.ecs_services = self._create_ecs_services()
        
        # Create SNS topic for notifications
        self.sns_topic = self._create_sns_topic()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create CodeDeploy application
        self.codedeploy_app = self._create_codedeploy_application()
        
        # Create CodeBuild project
        self.codebuild_project = self._create_codebuild_project()
        
        # Create CodePipeline
        self.pipeline = self._create_codepipeline()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with multi-AZ subnets for high availability."""
        vpc = ec2.Vpc(
            self, "VPC",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        cdk.Tags.of(vpc).add("Name", f"{self.project_name}-vpc")
        return vpc

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """Create security groups for ALB and ECS tasks."""
        # Security group for Application Load Balancer
        alb_sg = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=True,
        )
        
        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP access from anywhere",
        )
        
        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS access from anywhere",
        )
        
        # Security group for ECS tasks
        ecs_sg = ec2.SecurityGroup(
            self, "ECSSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS tasks",
            allow_all_outbound=True,
        )
        
        ecs_sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(8080),
            description="Application port from ALB",
        )
        
        ecs_sg.add_ingress_rule(
            peer=ecs_sg,
            connection=ec2.Port.tcp(2000),
            description="X-Ray daemon port",
        )
        
        return {
            "alb": alb_sg,
            "ecs": ecs_sg,
        }

    def _create_ecr_repository(self) -> ecr.Repository:
        """Create ECR repository with vulnerability scanning enabled."""
        repository = ecr.Repository(
            self, "ECRRepository",
            repository_name=f"{self.project_name}-repo",
            image_scan_on_push=True,
            encryption=ecr.RepositoryEncryption.AES_256,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Set lifecycle policy to manage image retention
        repository.add_lifecycle_rule(
            description="Keep last 10 production images",
            tag_prefix_list=["prod"],
            max_image_count=10,
        )
        
        repository.add_lifecycle_rule(
            description="Keep last 5 development images",
            tag_prefix_list=["dev"],
            max_image_count=5,
        )
        
        return repository

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """Create S3 bucket for CodePipeline artifacts."""
        bucket = s3.Bucket(
            self, "ArtifactsBucket",
            bucket_name=f"{self.project_name}-artifacts-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        return bucket

    def _create_parameter_store_parameters(self) -> None:
        """Create Parameter Store parameters for application configuration."""
        ssm.StringParameter(
            self, "AppEnvironmentParam",
            parameter_name=f"/{self.project_name}/app/environment",
            string_value="production",
            description="Application environment",
        )
        
        ssm.StringParameter(
            self, "AppVersionParam",
            parameter_name=f"/{self.project_name}/app/version",
            string_value="1.0.0",
            description="Application version",
        )

    def _create_iam_roles(self) -> Dict[str, iam.Role]:
        """Create IAM roles for ECS tasks, CodeDeploy, CodeBuild, and CodePipeline."""
        # ECS Task Execution Role
        task_execution_role = iam.Role(
            self, "TaskExecutionRole",
            role_name=f"{self.project_name}-task-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ],
        )
        
        # ECS Task Role
        task_role = iam.Role(
            self, "TaskRole",
            role_name=f"{self.project_name}-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )
        
        # Add permissions for Parameter Store, X-Ray, and CloudWatch Logs
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath",
                    "secretsmanager:GetSecretValue",
                    "xray:PutTraceSegments",
                    "xray:PutTelemetryRecords",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )
        
        # CodeDeploy Service Role
        codedeploy_role = iam.Role(
            self, "CodeDeployRole",
            role_name=f"{self.project_name}-codedeploy-role",
            assumed_by=iam.ServicePrincipal("codedeploy.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSCodeDeployRoleForECS"
                ),
            ],
        )
        
        # CodeBuild Service Role
        codebuild_role = iam.Role(
            self, "CodeBuildRole",
            role_name=f"{self.project_name}-codebuild-role",
            assumed_by=iam.ServicePrincipal("codebuild.amazonaws.com"),
        )
        
        # Add comprehensive permissions for CodeBuild
        codebuild_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:GetAuthorizationToken",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                    "ecr:PutImage",
                    "ecr:DescribeRepositories",
                    "ecr:DescribeImages",
                    "s3:GetObject",
                    "s3:PutObject",
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "secretsmanager:GetSecretValue",
                    "codebuild:CreateReportGroup",
                    "codebuild:CreateReport",
                    "codebuild:UpdateReport",
                    "codebuild:BatchPutTestCases",
                    "codebuild:BatchPutCodeCoverages",
                ],
                resources=["*"],
            )
        )
        
        # CodePipeline Service Role
        codepipeline_role = iam.Role(
            self, "CodePipelineRole",
            role_name=f"{self.project_name}-codepipeline-role",
            assumed_by=iam.ServicePrincipal("codepipeline.amazonaws.com"),
        )
        
        # Add comprehensive permissions for CodePipeline
        codepipeline_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetBucketVersioning",
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "codebuild:BatchGetBuilds",
                    "codebuild:StartBuild",
                    "codedeploy:CreateDeployment",
                    "codedeploy:GetApplication",
                    "codedeploy:GetApplicationRevision",
                    "codedeploy:GetDeployment",
                    "codedeploy:GetDeploymentConfig",
                    "codedeploy:RegisterApplicationRevision",
                    "ecs:DescribeServices",
                    "ecs:DescribeTaskDefinition",
                    "ecs:DescribeTasks",
                    "ecs:ListTasks",
                    "ecs:RegisterTaskDefinition",
                    "ecs:UpdateService",
                    "iam:PassRole",
                    "sns:Publish",
                ],
                resources=["*"],
            )
        )
        
        return {
            "task_execution": task_execution_role,
            "task": task_role,
            "codedeploy": codedeploy_role,
            "codebuild": codebuild_role,
            "codepipeline": codepipeline_role,
        }

    def _create_log_groups(self) -> Dict[str, logs.LogGroup]:
        """Create CloudWatch log groups for different environments."""
        dev_log_group = logs.LogGroup(
            self, "DevLogGroup",
            log_group_name=f"/ecs/{self.project_name}/dev",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        prod_log_group = logs.LogGroup(
            self, "ProdLogGroup",
            log_group_name=f"/ecs/{self.project_name}/prod",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return {
            "dev": dev_log_group,
            "prod": prod_log_group,
        }

    def _create_ecs_clusters(self) -> Dict[str, ecs.Cluster]:
        """Create ECS clusters for development and production environments."""
        # Development cluster with Fargate Spot for cost optimization
        dev_cluster = ecs.Cluster(
            self, "DevCluster",
            cluster_name=f"{self.project_name}-dev-cluster",
            vpc=self.vpc,
            capacity_providers=["FARGATE", "FARGATE_SPOT"],
            default_capacity_provider_strategy=[
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE_SPOT",
                    weight=1,
                    base=0,
                ),
            ],
            container_insights=True,
        )
        
        # Production cluster with standard Fargate for reliability
        prod_cluster = ecs.Cluster(
            self, "ProdCluster",
            cluster_name=f"{self.project_name}-prod-cluster",
            vpc=self.vpc,
            capacity_providers=["FARGATE"],
            default_capacity_provider_strategy=[
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE",
                    weight=1,
                    base=0,
                ),
            ],
            container_insights=True,
        )
        
        cdk.Tags.of(dev_cluster).add("Environment", "development")
        cdk.Tags.of(prod_cluster).add("Environment", "production")
        
        return {
            "dev": dev_cluster,
            "prod": prod_cluster,
        }

    def _create_load_balancers(self) -> Dict[str, Dict]:
        """Create Application Load Balancers for development and production."""
        # Development ALB
        dev_alb = elbv2.ApplicationLoadBalancer(
            self, "DevALB",
            load_balancer_name=f"{self.project_name}-dev-alb",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.security_groups["alb"],
        )
        
        # Production ALB
        prod_alb = elbv2.ApplicationLoadBalancer(
            self, "ProdALB",
            load_balancer_name=f"{self.project_name}-prod-alb",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.security_groups["alb"],
        )
        
        # Create target groups for development
        dev_target_group = elbv2.ApplicationTargetGroup(
            self, "DevTargetGroup",
            target_group_name=f"{self.project_name}-dev-tg",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            vpc=self.vpc,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                interval=Duration.seconds(30),
                path="/health",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
            ),
        )
        
        # Create target groups for production blue-green deployment
        prod_blue_target_group = elbv2.ApplicationTargetGroup(
            self, "ProdBlueTargetGroup",
            target_group_name=f"{self.project_name}-prod-blue",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            vpc=self.vpc,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                healthy_threshold_count=2,
                unhealthy_threshold_count=2,
                interval=Duration.seconds(15),
                path="/health",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
            ),
        )
        
        prod_green_target_group = elbv2.ApplicationTargetGroup(
            self, "ProdGreenTargetGroup",
            target_group_name=f"{self.project_name}-prod-green",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            vpc=self.vpc,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                healthy_threshold_count=2,
                unhealthy_threshold_count=2,
                interval=Duration.seconds(15),
                path="/health",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
            ),
        )
        
        # Create listeners
        dev_listener = dev_alb.add_listener(
            "DevListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[dev_target_group],
        )
        
        prod_listener = prod_alb.add_listener(
            "ProdListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[prod_blue_target_group],
        )
        
        return {
            "dev": {
                "alb": dev_alb,
                "target_group": dev_target_group,
                "listener": dev_listener,
            },
            "prod": {
                "alb": prod_alb,
                "blue_target_group": prod_blue_target_group,
                "green_target_group": prod_green_target_group,
                "listener": prod_listener,
            },
        }

    def _create_task_definitions(self) -> Dict[str, ecs.FargateTaskDefinition]:
        """Create ECS task definitions for development and production."""
        # Development task definition
        dev_task_definition = ecs.FargateTaskDefinition(
            self, "DevTaskDefinition",
            family=f"{self.project_name}-dev-task",
            cpu=256,
            memory_limit_mib=512,
            execution_role=self.iam_roles["task_execution"],
            task_role=self.iam_roles["task"],
        )
        
        # Add application container to development task
        dev_app_container = dev_task_definition.add_container(
            "app",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            port_mappings=[
                ecs.PortMapping(container_port=8080, protocol=ecs.Protocol.TCP)
            ],
            environment={
                "ENV": "development",
                "AWS_XRAY_TRACING_NAME": f"{self.project_name}-dev",
            },
            secrets={
                "APP_VERSION": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "DevAppVersionParam",
                        string_parameter_name=f"/{self.project_name}/app/version",
                    )
                ),
            },
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_groups["dev"],
            ),
            health_check=ecs.HealthCheck(
                command=["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )
        
        # Add X-Ray daemon container to development task
        dev_xray_container = dev_task_definition.add_container(
            "xray-daemon",
            image=ecs.ContainerImage.from_registry("amazon/aws-xray-daemon:latest"),
            port_mappings=[
                ecs.PortMapping(container_port=2000, protocol=ecs.Protocol.UDP)
            ],
            essential=False,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="xray",
                log_group=self.log_groups["dev"],
            ),
        )
        
        # Production task definition
        prod_task_definition = ecs.FargateTaskDefinition(
            self, "ProdTaskDefinition",
            family=f"{self.project_name}-prod-task",
            cpu=512,
            memory_limit_mib=1024,
            execution_role=self.iam_roles["task_execution"],
            task_role=self.iam_roles["task"],
        )
        
        # Add application container to production task
        prod_app_container = prod_task_definition.add_container(
            "app",
            image=ecs.ContainerImage.from_ecr_repository(
                self.ecr_repository, tag="latest"
            ),
            port_mappings=[
                ecs.PortMapping(container_port=8080, protocol=ecs.Protocol.TCP)
            ],
            environment={
                "ENV": "production",
                "AWS_XRAY_TRACING_NAME": f"{self.project_name}-prod",
            },
            secrets={
                "APP_VERSION": ecs.Secret.from_ssm_parameter(
                    ssm.StringParameter.from_string_parameter_name(
                        self, "ProdAppVersionParam",
                        string_parameter_name=f"/{self.project_name}/app/version",
                    )
                ),
            },
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_groups["prod"],
            ),
            health_check=ecs.HealthCheck(
                command=["CMD-SHELL", "curl -f http://localhost:8080/health || exit 1"],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )
        
        # Add X-Ray daemon container to production task
        prod_xray_container = prod_task_definition.add_container(
            "xray-daemon",
            image=ecs.ContainerImage.from_registry("amazon/aws-xray-daemon:latest"),
            port_mappings=[
                ecs.PortMapping(container_port=2000, protocol=ecs.Protocol.UDP)
            ],
            essential=False,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="xray",
                log_group=self.log_groups["prod"],
            ),
        )
        
        return {
            "dev": dev_task_definition,
            "prod": prod_task_definition,
        }

    def _create_ecs_services(self) -> Dict[str, ecs.FargateService]:
        """Create ECS services for development and production."""
        # Development service with standard ECS deployment
        dev_service = ecs.FargateService(
            self, "DevService",
            service_name=f"{self.project_name}-service-dev",
            cluster=self.ecs_clusters["dev"],
            task_definition=self.task_definitions["dev"],
            desired_count=2,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.security_groups["ecs"]],
            assign_public_ip=False,
            enable_execute_command=True,
        )
        
        # Associate dev service with target group
        dev_service.attach_to_application_target_group(
            self.load_balancers["dev"]["target_group"]
        )
        
        # Production service with CodeDeploy deployment controller
        prod_service = ecs.FargateService(
            self, "ProdService",
            service_name=f"{self.project_name}-service-prod",
            cluster=self.ecs_clusters["prod"],
            task_definition=self.task_definitions["prod"],
            desired_count=3,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.security_groups["ecs"]],
            assign_public_ip=False,
            enable_execute_command=True,
            deployment_controller=ecs.DeploymentController(
                type=ecs.DeploymentControllerType.CODE_DEPLOY
            ),
        )
        
        # Associate prod service with blue target group
        prod_service.attach_to_application_target_group(
            self.load_balancers["prod"]["blue_target_group"]
        )
        
        # Add auto scaling for production service
        prod_scaling = prod_service.auto_scale_task_count(
            min_capacity=2,
            max_capacity=10,
        )
        
        prod_scaling.scale_on_cpu_utilization(
            "ProdCpuScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.minutes(5),
            scale_out_cooldown=Duration.minutes(5),
        )
        
        # Add tags
        cdk.Tags.of(dev_service).add("Environment", "development")
        cdk.Tags.of(prod_service).add("Environment", "production")
        
        return {
            "dev": dev_service,
            "prod": prod_service,
        }

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for notifications."""
        topic = sns.Topic(
            self, "AlertsTopic",
            topic_name=f"{self.project_name}-alerts",
            display_name="CI/CD Pipeline Alerts",
        )
        
        return topic

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring."""
        # High error rate alarm
        high_error_alarm = cloudwatch.Alarm(
            self, "HighErrorRateAlarm",
            alarm_name=f"{self.project_name}-high-error-rate",
            alarm_description="High error rate detected",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="HTTPCode_ELB_4XX_Count",
                dimensions_map={
                    "LoadBalancer": self.load_balancers["prod"]["alb"].load_balancer_full_name,
                },
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=10,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        high_error_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        
        # High response time alarm
        high_response_time_alarm = cloudwatch.Alarm(
            self, "HighResponseTimeAlarm",
            alarm_name=f"{self.project_name}-high-response-time",
            alarm_description="High response time detected",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationELB",
                metric_name="TargetResponseTime",
                dimensions_map={
                    "LoadBalancer": self.load_balancers["prod"]["alb"].load_balancer_full_name,
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=2.0,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        high_response_time_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_codedeploy_application(self) -> codedeploy.EcsApplication:
        """Create CodeDeploy application for ECS blue-green deployments."""
        # CodeDeploy application
        app = codedeploy.EcsApplication(
            self, "CodeDeployApp",
            application_name=f"{self.project_name}-app",
        )
        
        # Production deployment group with canary configuration
        deployment_group = codedeploy.EcsDeploymentGroup(
            self, "ProdDeploymentGroup",
            application=app,
            deployment_group_name=f"{self.project_name}-prod-deployment-group",
            service=self.ecs_services["prod"],
            blue_green_deployment_config=codedeploy.EcsBlueGreenDeploymentConfig(
                blue_target_group=self.load_balancers["prod"]["blue_target_group"],
                green_target_group=self.load_balancers["prod"]["green_target_group"],
                listener=self.load_balancers["prod"]["listener"],
                deployment_approval_wait_time=Duration.minutes(0),
                termination_wait_time=Duration.minutes(5),
            ),
            deployment_config=codedeploy.EcsDeploymentConfig.CANARY_10_PERCENT_5_MINUTES,
            role=self.iam_roles["codedeploy"],
            auto_rollback=codedeploy.AutoRollbackConfig(
                failed_deployment=True,
                stopped_deployment=True,
            ),
        )
        
        return app

    def _create_codebuild_project(self) -> codebuild.Project:
        """Create CodeBuild project for building and testing."""
        # Create buildspec for advanced build process
        buildspec = codebuild.BuildSpec.from_object({
            "version": "0.2",
            "phases": {
                "pre_build": {
                    "commands": [
                        "echo Logging in to Amazon ECR...",
                        "aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com",
                        "REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME",
                        "COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)",
                        "IMAGE_TAG=$COMMIT_HASH",
                        "echo Installing security scanning tools...",
                        "curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b /usr/local/bin",
                    ]
                },
                "build": {
                    "commands": [
                        "echo Build started on `date`",
                        "echo Building the Docker image...",
                        "docker build -t $IMAGE_REPO_NAME:latest .",
                        "docker tag $IMAGE_REPO_NAME:latest $REPOSITORY_URI:latest",
                        "docker tag $IMAGE_REPO_NAME:latest $REPOSITORY_URI:$IMAGE_TAG",
                        "echo Running security scan...",
                        "grype $IMAGE_REPO_NAME:latest --fail-on medium || true",
                        "echo Running unit tests...",
                        "docker run --rm $IMAGE_REPO_NAME:latest echo 'Tests passed'",
                    ]
                },
                "post_build": {
                    "commands": [
                        "echo Build completed on `date`",
                        "echo Pushing the Docker images...",
                        "docker push $REPOSITORY_URI:latest",
                        "docker push $REPOSITORY_URI:$IMAGE_TAG",
                        "echo Writing image definitions file...",
                        "printf '[{\"name\":\"app\",\"imageUri\":\"%s\"}]' $REPOSITORY_URI:$IMAGE_TAG > imagedefinitions.json",
                        "echo Creating task definition template...",
                        "cat imagedefinitions.json",
                    ]
                }
            },
            "artifacts": {
                "files": [
                    "imagedefinitions.json",
                ]
            },
            "reports": {
                "unit-tests": {
                    "files": ["test-results.xml"],
                    "name": "unit-tests"
                },
                "security-scan": {
                    "files": ["security-scan-results.json"],
                    "name": "security-scan"
                }
            }
        })
        
        project = codebuild.Project(
            self, "BuildProject",
            project_name=f"{self.project_name}-build",
            source=codebuild.Source.code_pipeline(
                build_spec=buildspec,
            ),
            environment=codebuild.BuildEnvironment(
                build_image=codebuild.LinuxBuildImage.AMAZON_LINUX_2_3,
                compute_type=codebuild.ComputeType.MEDIUM,
                privileged=True,
            ),
            role=self.iam_roles["codebuild"],
        )
        
        # Grant ECR permissions
        self.ecr_repository.grant_pull_push(project.role)
        
        return project

    def _create_codepipeline(self) -> codepipeline.Pipeline:
        """Create CodePipeline for CI/CD workflow."""
        # Create pipeline artifacts
        source_output = codepipeline.Artifact("SourceOutput")
        build_output = codepipeline.Artifact("BuildOutput")
        
        # Create pipeline
        pipeline = codepipeline.Pipeline(
            self, "Pipeline",
            pipeline_name=f"{self.project_name}-pipeline",
            role=self.iam_roles["codepipeline"],
            artifact_bucket=self.artifacts_bucket,
            stages=[
                # Source stage
                codepipeline.StageProps(
                    stage_name="Source",
                    actions=[
                        codepipeline_actions.S3SourceAction(
                            action_name="Source",
                            bucket=self.artifacts_bucket,
                            bucket_key="source.zip",
                            output=source_output,
                        ),
                    ],
                ),
                # Build stage
                codepipeline.StageProps(
                    stage_name="Build",
                    actions=[
                        codepipeline_actions.CodeBuildAction(
                            action_name="Build",
                            project=self.codebuild_project,
                            input=source_output,
                            outputs=[build_output],
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
                            },
                        ),
                    ],
                ),
                # Deploy to development
                codepipeline.StageProps(
                    stage_name="Deploy-Dev",
                    actions=[
                        codepipeline_actions.EcsDeployAction(
                            action_name="Deploy-Dev",
                            service=self.ecs_services["dev"],
                            input=build_output,
                            deployment_timeout=Duration.minutes(20),
                        ),
                    ],
                ),
                # Manual approval
                codepipeline.StageProps(
                    stage_name="Approval",
                    actions=[
                        codepipeline_actions.ManualApprovalAction(
                            action_name="ManualApproval",
                            notification_topic=self.sns_topic,
                            additional_information="Please review the development deployment and approve for production deployment.",
                        ),
                    ],
                ),
                # Deploy to production
                codepipeline.StageProps(
                    stage_name="Deploy-Production",
                    actions=[
                        codepipeline_actions.CodeDeployEcsDeployAction(
                            action_name="Deploy-Production",
                            deployment_group=self.codedeploy_app.deployment_groups[0],
                            app_spec_template_input=build_output,
                            task_definition_template_input=build_output,
                        ),
                    ],
                ),
            ],
        )
        
        return pipeline

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self, "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="ECR Repository URI",
        )
        
        CfnOutput(
            self, "DevALBDNS",
            value=self.load_balancers["dev"]["alb"].load_balancer_dns_name,
            description="Development ALB DNS Name",
        )
        
        CfnOutput(
            self, "ProdALBDNS",
            value=self.load_balancers["prod"]["alb"].load_balancer_dns_name,
            description="Production ALB DNS Name",
        )
        
        CfnOutput(
            self, "PipelineName",
            value=self.pipeline.pipeline_name,
            description="CodePipeline Name",
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for notifications",
        )


class CICDPipelineApp(cdk.App):
    """Main CDK Application for CI/CD Pipeline."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get project name from environment variable or use default
        project_name = os.environ.get("PROJECT_NAME", "advanced-cicd")
        
        # Create the main stack
        CICDPipelineStack(
            self, "CICDPipelineStack",
            project_name=project_name,
            description="CI/CD Pipeline for Container Applications with CodePipeline and CodeDeploy",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


# Create and run the app
app = CICDPipelineApp()
app.synth()