#!/usr/bin/env python3
"""
CDK Python application for deploying serverless containers with AWS Fargate and Application Load Balancer.

This application creates a complete serverless container infrastructure including:
- VPC with public and private subnets
- ECR repository for container images
- ECS cluster with Fargate capacity providers
- ECS service with auto-scaling
- Application Load Balancer with health checks
- CloudWatch logs and monitoring
- IAM roles and security groups
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_applicationautoscaling as autoscaling,
    aws_ec2 as ec2,
    aws_ecr as ecr,
    aws_ecs as ecs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class FargateContainerStack(Stack):
    """
    CDK Stack for deploying serverless containers with AWS Fargate and Application Load Balancer.
    
    This stack creates a complete serverless container infrastructure following AWS best practices
    for security, scalability, and cost optimization.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        container_image_tag: str = "latest",
        container_port: int = 3000,
        desired_count: int = 3,
        min_capacity: int = 2,
        max_capacity: int = 10,
        cpu: int = 256,
        memory_limit_mib: int = 512,
        enable_spot_capacity: bool = True,
        log_retention_days: int = 7,
        **kwargs
    ) -> None:
        """
        Initialize the Fargate Container Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            container_image_tag: Tag for the container image (default: "latest")
            container_port: Port on which the container listens (default: 3000)
            desired_count: Desired number of tasks (default: 3)
            min_capacity: Minimum number of tasks for auto-scaling (default: 2)
            max_capacity: Maximum number of tasks for auto-scaling (default: 10)
            cpu: CPU units for the task (default: 256)
            memory_limit_mib: Memory limit in MiB (default: 512)
            enable_spot_capacity: Enable Fargate Spot capacity (default: True)
            log_retention_days: CloudWatch log retention in days (default: 7)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.container_image_tag = container_image_tag
        self.container_port = container_port
        self.desired_count = desired_count
        self.min_capacity = min_capacity
        self.max_capacity = max_capacity
        self.cpu = cpu
        self.memory_limit_mib = memory_limit_mib
        self.enable_spot_capacity = enable_spot_capacity
        self.log_retention_days = log_retention_days

        # Create VPC and networking components
        self.vpc = self._create_vpc()
        
        # Create ECR repository
        self.ecr_repository = self._create_ecr_repository()
        
        # Create ECS cluster
        self.ecs_cluster = self._create_ecs_cluster()
        
        # Create IAM roles
        self.task_execution_role, self.task_role = self._create_iam_roles()
        
        # Create CloudWatch log group
        self.log_group = self._create_log_group()
        
        # Create task definition
        self.task_definition = self._create_task_definition()
        
        # Create Application Load Balancer
        self.alb, self.target_group = self._create_application_load_balancer()
        
        # Create ECS service
        self.ecs_service = self._create_ecs_service()
        
        # Configure auto-scaling
        self._configure_auto_scaling()
        
        # Create stack outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across multiple AZs.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self,
            "FargateVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Add tags for better resource management
        cdk.Tags.of(vpc).add("Name", "FargateVPC")
        cdk.Tags.of(vpc).add("Environment", "Production")

        return vpc

    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create ECR repository for container images with security scanning.
        
        Returns:
            ecr.Repository: The created ECR repository
        """
        repository = ecr.Repository(
            self,
            "FargateRepository",
            repository_name=f"fargate-demo-{self.node.addr[:8]}",
            image_scan_on_push=True,
            encryption=ecr.RepositoryEncryption.AES_256,
            removal_policy=RemovalPolicy.DESTROY,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only the latest 10 images",
                    max_image_count=10,
                    rule_priority=1,
                )
            ],
        )

        return repository

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """
        Create ECS cluster with Fargate capacity providers.
        
        Returns:
            ecs.Cluster: The created ECS cluster
        """
        cluster = ecs.Cluster(
            self,
            "FargateCluster",
            cluster_name=f"fargate-cluster-{self.node.addr[:8]}",
            vpc=self.vpc,
            container_insights=True,
            enable_fargate_capacity_providers=True,
        )

        # Configure capacity providers with cost optimization
        if self.enable_spot_capacity:
            cluster.add_default_capacity_provider_strategy([
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE",
                    weight=1,
                    base=1,
                ),
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE_SPOT",
                    weight=4,
                ),
            ])

        return cluster

    def _create_iam_roles(self) -> tuple[iam.Role, iam.Role]:
        """
        Create IAM roles for task execution and task permissions.
        
        Returns:
            tuple[iam.Role, iam.Role]: Task execution role and task role
        """
        # Task execution role (used by ECS to pull images and write logs)
        task_execution_role = iam.Role(
            self,
            "TaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )

        # Grant additional permissions for ECR access
        task_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                ],
                resources=["*"],
            )
        )

        # Task role (used by application code)
        task_role = iam.Role(
            self,
            "TaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )

        # Grant permissions for CloudWatch metrics and logs
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"],
            )
        )

        return task_execution_role, task_role

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for container logs.
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "FargateLogGroup",
            log_group_name=f"/ecs/fargate-task-{self.node.addr[:8]}",
            retention=logs.RetentionDays(self.log_retention_days),
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_task_definition(self) -> ecs.FargateTaskDefinition:
        """
        Create ECS task definition with container configuration.
        
        Returns:
            ecs.FargateTaskDefinition: The created task definition
        """
        task_definition = ecs.FargateTaskDefinition(
            self,
            "FargateTaskDefinition",
            family=f"fargate-task-{self.node.addr[:8]}",
            cpu=self.cpu,
            memory_limit_mib=self.memory_limit_mib,
            execution_role=self.task_execution_role,
            task_role=self.task_role,
        )

        # Add container to task definition
        container = task_definition.add_container(
            "FargateContainer",
            image=ecs.ContainerImage.from_ecr_repository(
                self.ecr_repository, self.container_image_tag
            ),
            port_mappings=[
                ecs.PortMapping(
                    container_port=self.container_port,
                    protocol=ecs.Protocol.TCP,
                )
            ],
            environment={
                "NODE_ENV": "production",
                "PORT": str(self.container_port),
            },
            logging=ecs.LogDriver.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group,
            ),
            health_check=ecs.HealthCheck(
                command=[
                    "CMD-SHELL",
                    f"curl -f http://localhost:{self.container_port}/health || exit 1",
                ],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )

        return task_definition

    def _create_application_load_balancer(self) -> tuple[elbv2.ApplicationLoadBalancer, elbv2.ApplicationTargetGroup]:
        """
        Create Application Load Balancer with target group and health checks.
        
        Returns:
            tuple[elbv2.ApplicationLoadBalancer, elbv2.ApplicationTargetGroup]: ALB and target group
        """
        # Create security group for ALB
        alb_security_group = ec2.SecurityGroup(
            self,
            "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=True,
        )

        # Allow HTTP and HTTPS traffic to ALB
        alb_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(80),
            "Allow HTTP traffic",
        )
        alb_security_group.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(443),
            "Allow HTTPS traffic",
        )

        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "FargateALB",
            load_balancer_name=f"fargate-alb-{self.node.addr[:8]}",
            vpc=self.vpc,
            internet_facing=True,
            security_group=alb_security_group,
        )

        # Create target group for Fargate service
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "FargateTargetGroup",
            target_group_name=f"fargate-tg-{self.node.addr[:8]}",
            port=self.container_port,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                enabled=True,
                path="/health",
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                healthy_http_codes="200",
            ),
        )

        # Add listener to ALB
        alb.add_listener(
            "ALBListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group],
        )

        return alb, target_group

    def _create_ecs_service(self) -> ecs.FargateService:
        """
        Create ECS service with Fargate launch type.
        
        Returns:
            ecs.FargateService: The created ECS service
        """
        # Create security group for Fargate tasks
        fargate_security_group = ec2.SecurityGroup(
            self,
            "FargateSecurityGroup",
            vpc=self.vpc,
            description="Security group for Fargate tasks",
            allow_all_outbound=True,
        )

        # Allow traffic from ALB to Fargate tasks
        fargate_security_group.add_ingress_rule(
            ec2.Peer.security_group_id(self.alb.connections.security_groups[0].security_group_id),
            ec2.Port.tcp(self.container_port),
            "Allow traffic from ALB",
        )

        # Create ECS service
        service = ecs.FargateService(
            self,
            "FargateService",
            service_name=f"fargate-service-{self.node.addr[:8]}",
            cluster=self.ecs_cluster,
            task_definition=self.task_definition,
            desired_count=self.desired_count,
            assign_public_ip=True,
            security_groups=[fargate_security_group],
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC,
            ),
            platform_version=ecs.FargatePlatformVersion.LATEST,
            deployment_configuration=ecs.DeploymentConfiguration(
                maximum_percent=200,
                minimum_healthy_percent=50,
                deployment_circuit_breaker=ecs.DeploymentCircuitBreaker(
                    enable=True,
                    rollback=True,
                ),
            ),
            health_check_grace_period=Duration.seconds(120),
            enable_execute_command=True,
        )

        # Attach service to target group
        service.attach_to_application_target_group(self.target_group)

        return service

    def _configure_auto_scaling(self) -> None:
        """Configure auto-scaling for the ECS service."""
        # Create scalable target
        scalable_target = self.ecs_service.auto_scale_task_count(
            min_capacity=self.min_capacity,
            max_capacity=self.max_capacity,
        )

        # Add CPU-based scaling policy
        scalable_target.scale_on_cpu_utilization(
            "CPUScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )

        # Add memory-based scaling policy
        scalable_target.scale_on_memory_utilization(
            "MemoryScaling",
            target_utilization_percent=80,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        # ALB DNS name
        cdk.CfnOutput(
            self,
            "ApplicationLoadBalancerDNS",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
        )

        # ALB URL
        cdk.CfnOutput(
            self,
            "ApplicationURL",
            value=f"http://{self.alb.load_balancer_dns_name}",
            description="URL of the deployed application",
        )

        # ECR repository URI
        cdk.CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository",
        )

        # ECS cluster name
        cdk.CfnOutput(
            self,
            "ECSClusterName",
            value=self.ecs_cluster.cluster_name,
            description="Name of the ECS cluster",
        )

        # ECS service name
        cdk.CfnOutput(
            self,
            "ECSServiceName",
            value=self.ecs_service.service_name,
            description="Name of the ECS service",
        )

        # CloudWatch log group
        cdk.CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group",
        )


# CDK App
app = cdk.App()

# Get configuration from context or environment variables
config = {
    "container_image_tag": app.node.try_get_context("container_image_tag") or "latest",
    "container_port": int(app.node.try_get_context("container_port") or "3000"),
    "desired_count": int(app.node.try_get_context("desired_count") or "3"),
    "min_capacity": int(app.node.try_get_context("min_capacity") or "2"),
    "max_capacity": int(app.node.try_get_context("max_capacity") or "10"),
    "cpu": int(app.node.try_get_context("cpu") or "256"),
    "memory_limit_mib": int(app.node.try_get_context("memory_limit_mib") or "512"),
    "enable_spot_capacity": app.node.try_get_context("enable_spot_capacity") != "false",
    "log_retention_days": int(app.node.try_get_context("log_retention_days") or "7"),
}

# Create the stack
FargateContainerStack(
    app,
    "FargateContainerStack",
    **config,
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    ),
    description="Serverless containers with AWS Fargate and Application Load Balancer",
)

app.synth()