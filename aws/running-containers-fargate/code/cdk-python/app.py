#!/usr/bin/env python3
"""
AWS CDK Python application for Running Containers with AWS Fargate.

This application creates:
- ECS Cluster with Fargate capacity providers
- ECR Repository with vulnerability scanning
- ECS Task Definition with health checks and logging
- ECS Service with auto-scaling
- IAM roles for task execution
- Security groups and networking configuration
- CloudWatch log groups for container logging
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    aws_ecs as ecs,
    aws_ecr as ecr,
    aws_iam as iam,
    aws_ec2 as ec2,
    aws_logs as logs,
    aws_applicationautoscaling as autoscaling,
)
from typing import Dict, Any
from constructs import Construct


class ServerlessContainerStack(Stack):
    """
    CDK Stack for Running Containers with AWS Fargate.
    
    This stack demonstrates best practices for:
    - Container orchestration with ECS and Fargate
    - Secure networking with VPC and security groups
    - Auto-scaling based on CPU utilization
    - Comprehensive logging and monitoring
    - Secure IAM role configuration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        container_image: str = "nginx:latest",
        container_port: int = 80,
        cpu: int = 256,
        memory: int = 512,
        desired_count: int = 2,
        min_capacity: int = 1,
        max_capacity: int = 10,
        target_cpu_utilization: float = 50.0,
        **kwargs: Any
    ) -> None:
        """
        Initialize the ServerlessContainerStack.

        Args:
            scope: The scope in which to define this stack
            construct_id: The scoped construct ID
            container_image: Container image to deploy (default: nginx:latest)
            container_port: Port exposed by the container (default: 80)
            cpu: CPU units for the task (default: 256)
            memory: Memory in MiB for the task (default: 512)
            desired_count: Initial number of tasks (default: 2)
            min_capacity: Minimum number of tasks for auto-scaling (default: 1)
            max_capacity: Maximum number of tasks for auto-scaling (default: 10)
            target_cpu_utilization: Target CPU utilization for scaling (default: 50.0)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Create ECR repository for container images
        self.repository = self._create_ecr_repository()

        # Get default VPC or create one
        self.vpc = self._get_or_create_vpc()

        # Create security group for Fargate tasks
        self.security_group = self._create_security_group(container_port)

        # Create IAM execution role for ECS tasks
        self.execution_role = self._create_execution_role()

        # Create CloudWatch log group
        self.log_group = self._create_log_group()

        # Create ECS cluster with Fargate capacity providers
        self.cluster = self._create_ecs_cluster()

        # Create ECS task definition
        self.task_definition = self._create_task_definition(
            container_image=container_image,
            container_port=container_port,
            cpu=cpu,
            memory=memory
        )

        # Create ECS service
        self.service = self._create_ecs_service(desired_count)

        # Configure auto-scaling
        self._configure_auto_scaling(
            min_capacity=min_capacity,
            max_capacity=max_capacity,
            target_cpu_utilization=target_cpu_utilization
        )

        # Create stack outputs
        self._create_outputs()

    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create ECR repository with vulnerability scanning enabled.

        Returns:
            ECR repository construct
        """
        repository = ecr.Repository(
            self,
            "ContainerRepository",
            repository_name=f"serverless-containers-{self.stack_name.lower()}",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only the latest 10 images",
                    max_image_count=10,
                    rule_priority=1
                )
            ],
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        return repository

    def _get_or_create_vpc(self) -> ec2.IVpc:
        """
        Get the default VPC or create a new one if needed.

        Returns:
            VPC construct
        """
        # Try to use the default VPC
        try:
            vpc = ec2.Vpc.from_lookup(
                self,
                "DefaultVpc",
                is_default=True
            )
        except Exception:
            # Create a new VPC if default doesn't exist
            vpc = ec2.Vpc(
                self,
                "FargateVpc",
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Public",
                        subnet_type=ec2.SubnetType.PUBLIC,
                        cidr_mask=24
                    ),
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                        cidr_mask=24
                    )
                ]
            )

        return vpc

    def _create_security_group(self, container_port: int) -> ec2.SecurityGroup:
        """
        Create security group for Fargate tasks.

        Args:
            container_port: Port to allow inbound traffic on

        Returns:
            Security group construct
        """
        security_group = ec2.SecurityGroup(
            self,
            "FargateSecurityGroup",
            vpc=self.vpc,
            description="Security group for Fargate tasks",
            allow_all_outbound=True
        )

        # Allow inbound traffic on the container port
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(container_port),
            description=f"Allow inbound traffic on port {container_port}"
        )

        return security_group

    def _create_execution_role(self) -> iam.Role:
        """
        Create IAM execution role for ECS tasks.

        Returns:
            IAM role construct
        """
        execution_role = iam.Role(
            self,
            "TaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="Execution role for ECS Fargate tasks",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ]
        )

        # Add permissions to pull from ECR repository
        self.repository.grant_pull(execution_role)

        return execution_role

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for container logs.

        Returns:
            CloudWatch log group construct
        """
        log_group = logs.LogGroup(
            self,
            "ContainerLogGroup",
            log_group_name=f"/ecs/serverless-containers-{self.stack_name.lower()}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        return log_group

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """
        Create ECS cluster with Fargate capacity providers.

        Returns:
            ECS cluster construct
        """
        cluster = ecs.Cluster(
            self,
            "FargateCluster",
            vpc=self.vpc,
            cluster_name=f"serverless-containers-{self.stack_name.lower()}",
            capacity_providers=["FARGATE", "FARGATE_SPOT"],
            default_capacity_provider_strategy=[
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE",
                    weight=1
                )
            ],
            enable_fargate_capacity_providers=True
        )

        return cluster

    def _create_task_definition(
        self,
        container_image: str,
        container_port: int,
        cpu: int,
        memory: int
    ) -> ecs.FargateTaskDefinition:
        """
        Create ECS task definition for Fargate.

        Args:
            container_image: Container image to use
            container_port: Port exposed by the container
            cpu: CPU units for the task
            memory: Memory in MiB for the task

        Returns:
            Fargate task definition construct
        """
        task_definition = ecs.FargateTaskDefinition(
            self,
            "TaskDefinition",
            family=f"serverless-containers-{self.stack_name.lower()}",
            cpu=cpu,
            memory_limit_mib=memory,
            execution_role=self.execution_role
        )

        # Add container to the task definition
        container = task_definition.add_container(
            "ApplicationContainer",
            image=ecs.ContainerImage.from_registry(container_image),
            port_mappings=[
                ecs.PortMapping(
                    container_port=container_port,
                    protocol=ecs.Protocol.TCP
                )
            ],
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_group
            ),
            health_check=ecs.HealthCheck(
                command=["CMD-SHELL", f"curl -f http://localhost:{container_port}/health || exit 1"],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60)
            ),
            essential=True
        )

        return task_definition

    def _create_ecs_service(self, desired_count: int) -> ecs.FargateService:
        """
        Create ECS service for running tasks.

        Args:
            desired_count: Initial number of tasks to run

        Returns:
            Fargate service construct
        """
        service = ecs.FargateService(
            self,
            "FargateService",
            cluster=self.cluster,
            task_definition=self.task_definition,
            service_name=f"serverless-containers-service-{self.stack_name.lower()}",
            desired_count=desired_count,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_groups=[self.security_group],
            assign_public_ip=True,
            enable_execute_command=True,
            health_check_grace_period=Duration.seconds(60)
        )

        return service

    def _configure_auto_scaling(
        self,
        min_capacity: int,
        max_capacity: int,
        target_cpu_utilization: float
    ) -> None:
        """
        Configure auto-scaling for the ECS service.

        Args:
            min_capacity: Minimum number of tasks
            max_capacity: Maximum number of tasks
            target_cpu_utilization: Target CPU utilization percentage
        """
        # Create scalable target
        scalable_target = self.service.auto_scale_task_count(
            min_capacity=min_capacity,
            max_capacity=max_capacity
        )

        # Add CPU-based scaling policy
        scalable_target.scale_on_cpu_utilization(
            "CpuScaling",
            target_utilization_percent=target_cpu_utilization,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300)
        )

        # Add memory-based scaling policy
        scalable_target.scale_on_memory_utilization(
            "MemoryScaling",
            target_utilization_percent=70.0,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="Name of the ECS cluster"
        )

        CfnOutput(
            self,
            "ServiceName",
            value=self.service.service_name,
            description="Name of the ECS service"
        )

        CfnOutput(
            self,
            "RepositoryUri",
            value=self.repository.repository_uri,
            description="URI of the ECR repository"
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group"
        )

        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="ID of the security group"
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Get configuration from context or use defaults
    env = Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )

    # Create the stack
    ServerlessContainerStack(
        app,
        "ServerlessContainerStack",
        env=env,
        description="CDK stack for Running Containers with AWS Fargate",
        # Customizable parameters
        container_image=app.node.try_get_context("containerImage") or "nginx:latest",
        container_port=int(app.node.try_get_context("containerPort") or "80"),
        cpu=int(app.node.try_get_context("cpu") or "256"),
        memory=int(app.node.try_get_context("memory") or "512"),
        desired_count=int(app.node.try_get_context("desiredCount") or "2"),
        min_capacity=int(app.node.try_get_context("minCapacity") or "1"),
        max_capacity=int(app.node.try_get_context("maxCapacity") or "10"),
        target_cpu_utilization=float(app.node.try_get_context("targetCpuUtilization") or "50.0")
    )

    app.synth()


if __name__ == "__main__":
    main()