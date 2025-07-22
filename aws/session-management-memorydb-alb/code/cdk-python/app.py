#!/usr/bin/env python3
"""
CDK Application for Distributed Session Management with MemoryDB

This CDK application creates a complete distributed session management solution using:
- Amazon MemoryDB for Redis as centralized session storage
- Application Load Balancer for traffic distribution
- ECS Fargate for stateless application containers
- Systems Manager Parameter Store for configuration management
- Auto Scaling for dynamic capacity management

Architecture provides high availability, horizontal scalability, and session persistence
across multiple application instances and availability zones.
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    Duration,
    RemovalPolicy,
    CfnOutput
)
from aws_cdk import aws_ec2 as ec2
from aws_cdk import aws_ecs as ecs
from aws_cdk import aws_elasticloadbalancingv2 as elbv2
from aws_cdk import aws_applicationautoscaling as autoscaling
from aws_cdk import aws_memorydb as memorydb
from aws_cdk import aws_ssm as ssm
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_s3 as s3
from constructs import Construct


class DistributedSessionManagementStack(Stack):
    """
    CDK Stack for Distributed Session Management Architecture
    
    This stack implements a production-ready session management solution with:
    - Multi-AZ MemoryDB cluster for session persistence
    - Application Load Balancer for traffic distribution
    - ECS Fargate service with auto scaling
    - Secure networking with VPC and security groups
    - Configuration management through Parameter Store
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        env_name: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the Distributed Session Management Stack
        
        Args:
            scope: CDK app or parent construct
            construct_id: Unique identifier for this stack
            env_name: Environment name (dev, staging, prod)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.env_name = env_name

        # Create VPC with public and private subnets
        self.vpc = self._create_vpc()

        # Create security groups
        self.security_groups = self._create_security_groups()

        # Create MemoryDB cluster for session storage
        self.memorydb_cluster = self._create_memorydb_cluster()

        # Create Parameter Store parameters for configuration
        self._create_ssm_parameters()

        # Create Application Load Balancer
        self.alb = self._create_application_load_balancer()

        # Create ECS cluster and service
        self.ecs_cluster = self._create_ecs_cluster()
        self.ecs_service = self._create_ecs_service()

        # Configure auto scaling for ECS service
        self._configure_auto_scaling()

        # Create S3 bucket for configuration files
        self.config_bucket = self._create_config_bucket()

        # Add stack outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets across multiple AZs
        
        Returns:
            ec2.Vpc: The created VPC with configured subnets
        """
        return ec2.Vpc(
            self,
            "SessionVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=2,
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
                ),
                ec2.SubnetConfiguration(
                    name="Database",
                    subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for ALB, ECS, and MemoryDB
        
        Returns:
            Dict[str, ec2.SecurityGroup]: Dictionary of security groups by name
        """
        # ALB Security Group - allows HTTPS/HTTP from internet
        alb_sg = ec2.SecurityGroup(
            self,
            "ALBSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=False
        )

        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from internet"
        )

        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from internet"
        )

        # ECS Security Group - allows traffic from ALB
        ecs_sg = ec2.SecurityGroup(
            self,
            "ECSSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS tasks",
            allow_all_outbound=True
        )

        ecs_sg.add_ingress_rule(
            peer=ec2.Peer.security_group_id(alb_sg.security_group_id),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from ALB"
        )

        # MemoryDB Security Group - allows Redis connections from ECS
        memorydb_sg = ec2.SecurityGroup(
            self,
            "MemoryDBSecurityGroup",
            vpc=self.vpc,
            description="Security group for MemoryDB cluster",
            allow_all_outbound=False
        )

        memorydb_sg.add_ingress_rule(
            peer=ec2.Peer.security_group_id(ecs_sg.security_group_id),
            connection=ec2.Port.tcp(6379),
            description="Allow Redis connections from ECS tasks"
        )

        # Add egress rule for ALB to ECS
        alb_sg.add_egress_rule(
            peer=ec2.Peer.security_group_id(ecs_sg.security_group_id),
            connection=ec2.Port.tcp(80),
            description="Allow traffic to ECS tasks"
        )

        return {
            "alb": alb_sg,
            "ecs": ecs_sg,
            "memorydb": memorydb_sg
        }

    def _create_memorydb_cluster(self) -> memorydb.CfnCluster:
        """
        Create MemoryDB for Redis cluster for session storage
        
        Returns:
            memorydb.CfnCluster: The created MemoryDB cluster
        """
        # Create subnet group for MemoryDB
        subnet_group = memorydb.CfnSubnetGroup(
            self,
            "SessionMemoryDBSubnetGroup",
            subnet_group_name=f"session-subnet-group-{self.env_name}",
            description="Subnet group for session management MemoryDB",
            subnet_ids=[
                subnet.subnet_id for subnet in self.vpc.isolated_subnets
            ]
        )

        # Create ACL for MemoryDB access control
        acl = memorydb.CfnACL(
            self,
            "SessionMemoryDBAcl",
            acl_name=f"session-acl-{self.env_name}",
            user_names=["default"]
        )

        # Create MemoryDB cluster
        cluster = memorydb.CfnCluster(
            self,
            "SessionMemoryDBCluster",
            cluster_name=f"session-cluster-{self.env_name}",
            description="MemoryDB cluster for distributed session management",
            node_type="db.r6g.large",
            acl_name=acl.acl_name,
            subnet_group_name=subnet_group.subnet_group_name,
            security_group_ids=[self.security_groups["memorydb"].security_group_id],
            num_shards=2,
            num_replicas_per_shard=1,
            auto_minor_version_upgrade=True,
            maintenance_window="sun:03:00-sun:04:00",
            snapshot_retention_limit=7,
            snapshot_window="02:00-03:00",
            parameter_group_name="default.memorydb-redis7"
        )

        cluster.add_dependency(subnet_group)
        cluster.add_dependency(acl)

        return cluster

    def _create_ssm_parameters(self) -> None:
        """
        Create Systems Manager Parameter Store parameters for application configuration
        """
        # MemoryDB endpoint parameter
        ssm.StringParameter(
            self,
            "MemoryDBEndpointParameter",
            parameter_name=f"/{self.env_name}/session-app/memorydb/endpoint",
            string_value=self.memorydb_cluster.attr_cluster_endpoint_address,
            description="MemoryDB cluster endpoint for session storage",
            tier=ssm.ParameterTier.STANDARD
        )

        # Redis port parameter
        ssm.StringParameter(
            self,
            "RedisPortParameter",
            parameter_name=f"/{self.env_name}/session-app/memorydb/port",
            string_value="6379",
            description="MemoryDB port for Redis connections",
            tier=ssm.ParameterTier.STANDARD
        )

        # Session timeout parameter
        ssm.StringParameter(
            self,
            "SessionTimeoutParameter",
            parameter_name=f"/{self.env_name}/session-app/config/session-timeout",
            string_value="1800",
            description="Session timeout in seconds (30 minutes)",
            tier=ssm.ParameterTier.STANDARD
        )

        # Redis database parameter
        ssm.StringParameter(
            self,
            "RedisDatabaseParameter",
            parameter_name=f"/{self.env_name}/session-app/config/redis-db",
            string_value="0",
            description="Redis database number for session storage",
            tier=ssm.ParameterTier.STANDARD
        )

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """
        Create Application Load Balancer with target group and listener
        
        Returns:
            elbv2.ApplicationLoadBalancer: The created ALB
        """
        # Create Application Load Balancer
        alb = elbv2.ApplicationLoadBalancer(
            self,
            "SessionALB",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.security_groups["alb"],
            load_balancer_name=f"session-alb-{self.env_name}",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            )
        )

        # Create target group for ECS service
        self.target_group = elbv2.ApplicationTargetGroup(
            self,
            "SessionTargetGroup",
            vpc=self.vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            target_group_name=f"session-tg-{self.env_name}",
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(5),
                interval=Duration.seconds(30),
                path="/health",
                protocol=elbv2.Protocol.HTTP,
                port="80"
            ),
            deregistration_delay=Duration.seconds(30)
        )

        # Create listener
        listener = alb.add_listener(
            "SessionListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self.target_group]
        )

        return alb

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """
        Create ECS cluster for running containerized applications
        
        Returns:
            ecs.Cluster: The created ECS cluster
        """
        cluster = ecs.Cluster(
            self,
            "SessionECSCluster",
            vpc=self.vpc,
            cluster_name=f"session-cluster-{self.env_name}",
            container_insights=True,
            enable_fargate_capacity_providers=True
        )

        return cluster

    def _create_ecs_service(self) -> ecs.FargateService:
        """
        Create ECS Fargate service with task definition
        
        Returns:
            ecs.FargateService: The created ECS service
        """
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "SessionAppLogGroup",
            log_group_name=f"/ecs/{self.env_name}/session-app",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create task execution role
        execution_role = iam.Role(
            self,
            "SessionTaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ]
        )

        # Create task role with SSM permissions
        task_role = iam.Role(
            self,
            "SessionTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com")
        )

        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath"
                ],
                resources=[
                    f"arn:aws:ssm:{self.region}:{self.account}:parameter/{self.env_name}/session-app/*"
                ]
            )
        )

        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.config_bucket.bucket_arn,
                    f"{self.config_bucket.bucket_arn}/*"
                ]
            )
        )

        # Create Fargate task definition
        task_definition = ecs.FargateTaskDefinition(
            self,
            "SessionTaskDefinition",
            memory_limit_mib=512,
            cpu=256,
            execution_role=execution_role,
            task_role=task_role,
            family=f"session-app-{self.env_name}"
        )

        # Add container to task definition
        container = task_definition.add_container(
            "session-app",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            memory_limit_mib=512,
            cpu=256,
            environment={
                "ENV": self.env_name,
                "AWS_DEFAULT_REGION": self.region
            },
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=log_group
            ),
            essential=True
        )

        container.add_port_mappings(
            ecs.PortMapping(
                container_port=80,
                protocol=ecs.Protocol.TCP
            )
        )

        # Create ECS service
        service = ecs.FargateService(
            self,
            "SessionECSService",
            cluster=self.ecs_cluster,
            task_definition=task_definition,
            service_name=f"session-app-service-{self.env_name}",
            desired_count=2,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self.security_groups["ecs"]],
            assign_public_ip=False,
            health_check_grace_period=Duration.seconds(300),
            enable_execute_command=True
        )

        # Associate service with target group
        service.attach_to_application_target_group(self.target_group)

        return service

    def _configure_auto_scaling(self) -> None:
        """
        Configure auto scaling for the ECS service based on CPU utilization
        """
        scaling_target = self.ecs_service.auto_scale_task_count(
            min_capacity=2,
            max_capacity=10
        )

        scaling_target.scale_on_cpu_utilization(
            "SessionCpuScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300)
        )

        scaling_target.scale_on_memory_utilization(
            "SessionMemoryScaling",
            target_utilization_percent=80,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300)
        )

    def _create_config_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing configuration files and scripts
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "SessionConfigBucket",
            bucket_name=f"session-config-{self.env_name}-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        return bucket

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information
        """
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for the session management infrastructure",
            export_name=f"{self.stack_name}-VpcId"
        )

        CfnOutput(
            self,
            "ALBDnsName",
            value=self.alb.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
            export_name=f"{self.stack_name}-ALBDnsName"
        )

        CfnOutput(
            self,
            "MemoryDBClusterEndpoint",
            value=self.memorydb_cluster.attr_cluster_endpoint_address,
            description="MemoryDB cluster endpoint address",
            export_name=f"{self.stack_name}-MemoryDBEndpoint"
        )

        CfnOutput(
            self,
            "ECSClusterName",
            value=self.ecs_cluster.cluster_name,
            description="ECS cluster name",
            export_name=f"{self.stack_name}-ECSClusterName"
        )

        CfnOutput(
            self,
            "ECSServiceName",
            value=self.ecs_service.service_name,
            description="ECS service name",
            export_name=f"{self.stack_name}-ECSServiceName"
        )

        CfnOutput(
            self,
            "ConfigBucketName",
            value=self.config_bucket.bucket_name,
            description="S3 bucket name for configuration files",
            export_name=f"{self.stack_name}-ConfigBucketName"
        )

    def _add_tags(self) -> None:
        """
        Add common tags to all resources in the stack
        """
        Tags.of(self).add("Project", "DistributedSessionManagement")
        Tags.of(self).add("Environment", self.env_name)
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("Recipe", "distributed-session-management-memorydb-application-load-balancer")


def main() -> None:
    """
    Main function to create and deploy the CDK application
    """
    app = cdk.App()

    # Get environment name from context or default to 'dev'
    env_name = app.node.try_get_context("env") or "dev"

    # Get AWS environment from context or use default
    aws_env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the stack
    DistributedSessionManagementStack(
        app,
        f"DistributedSessionManagementStack-{env_name}",
        env_name=env_name,
        env=aws_env,
        description=f"Distributed Session Management with MemoryDB and ALB ({env_name})",
        tags={
            "Project": "DistributedSessionManagement",
            "Environment": env_name
        }
    )

    app.synth()


if __name__ == "__main__":
    main()