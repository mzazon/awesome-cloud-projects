#!/usr/bin/env python3
"""
CDK Python application for ECS Service Discovery with Route 53 and Application Load Balancer.

This application creates a complete microservices architecture with:
- ECS Fargate cluster with service discovery
- AWS Cloud Map private DNS namespace
- Application Load Balancer with path-based routing
- Security groups and networking configuration
- IAM roles and policies
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_elasticloadbalancingv2 as elbv2,
    aws_servicediscovery as servicediscovery,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, List, Optional


class EcsServiceDiscoveryStack(Stack):
    """
    Main CDK stack for ECS Service Discovery with Route 53 and ALB.
    
    This stack creates a complete microservices infrastructure with automatic
    service discovery using AWS Cloud Map and Route 53 private hosted zones,
    combined with Application Load Balancer for external access.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: Optional[ec2.IVpc] = None,
        namespace_name: str = "internal.local",
        cluster_name: str = "microservices-cluster",
        **kwargs
    ) -> None:
        """
        Initialize the ECS Service Discovery stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            vpc: Existing VPC to use, or None to create a new one
            namespace_name: DNS namespace for service discovery
            cluster_name: Name for the ECS cluster
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self._namespace_name = namespace_name
        self._cluster_name = cluster_name

        # Create or use existing VPC
        self._vpc = vpc or self._create_vpc()

        # Create ECS cluster
        self._cluster = self._create_ecs_cluster()

        # Create service discovery namespace
        self._namespace = self._create_service_discovery_namespace()

        # Create security groups
        self._security_groups = self._create_security_groups()

        # Create Application Load Balancer
        self._alb = self._create_application_load_balancer()

        # Create target groups
        self._target_groups = self._create_target_groups()

        # Configure ALB listeners and routing
        self._configure_alb_routing()

        # Create IAM roles
        self._task_role, self._execution_role = self._create_iam_roles()

        # Create service discovery services
        self._discovery_services = self._create_discovery_services()

        # Create task definitions
        self._task_definitions = self._create_task_definitions()

        # Create ECS services
        self._ecs_services = self._create_ecs_services()

        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a new VPC with public and private subnets across multiple AZs.

        Returns:
            The created VPC
        """
        return ec2.Vpc(
            self,
            "MicroservicesVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=2,
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

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """
        Create ECS cluster with Fargate capacity providers.

        Returns:
            The created ECS cluster
        """
        cluster = ecs.Cluster(
            self,
            "MicroservicesCluster",
            cluster_name=self._cluster_name,
            vpc=self._vpc,
            container_insights=True,
        )

        # Add Fargate capacity providers
        cluster.add_capacity_provider("FARGATE")
        cluster.add_capacity_provider("FARGATE_SPOT")

        return cluster

    def _create_service_discovery_namespace(self) -> servicediscovery.PrivateDnsNamespace:
        """
        Create AWS Cloud Map private DNS namespace for service discovery.

        Returns:
            The created private DNS namespace
        """
        return servicediscovery.PrivateDnsNamespace(
            self,
            "ServiceDiscoveryNamespace",
            name=self._namespace_name,
            vpc=self._vpc,
            description="Private DNS namespace for microservices discovery",
        )

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for ALB and ECS tasks.

        Returns:
            Dictionary containing security groups
        """
        # ALB security group
        alb_sg = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=self._vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=True,
        )

        # Allow HTTP and HTTPS traffic to ALB
        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic",
        )
        alb_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic",
        )

        # ECS tasks security group
        ecs_sg = ec2.SecurityGroup(
            self,
            "EcsTasksSecurityGroup",
            vpc=self._vpc,
            description="Security group for ECS tasks",
            allow_all_outbound=True,
        )

        # Allow traffic from ALB to ECS tasks
        ecs_sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(3000),
            description="Allow ALB traffic to web service",
        )
        ecs_sg.add_ingress_rule(
            peer=alb_sg,
            connection=ec2.Port.tcp(8080),
            description="Allow ALB traffic to API service",
        )

        # Allow internal communication between services
        ecs_sg.add_ingress_rule(
            peer=ecs_sg,
            connection=ec2.Port.all_traffic(),
            description="Allow internal service communication",
        )

        return {
            "alb": alb_sg,
            "ecs": ecs_sg,
        }

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """
        Create Application Load Balancer in public subnets.

        Returns:
            The created Application Load Balancer
        """
        return elbv2.ApplicationLoadBalancer(
            self,
            "MicroservicesAlb",
            vpc=self._vpc,
            internet_facing=True,
            security_group=self._security_groups["alb"],
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            deletion_protection=False,
        )

    def _create_target_groups(self) -> Dict[str, elbv2.ApplicationTargetGroup]:
        """
        Create target groups for different services.

        Returns:
            Dictionary containing target groups
        """
        # Web service target group
        web_tg = elbv2.ApplicationTargetGroup(
            self,
            "WebTargetGroup",
            vpc=self._vpc,
            port=3000,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
            ),
        )

        # API service target group
        api_tg = elbv2.ApplicationTargetGroup(
            self,
            "ApiTargetGroup",
            vpc=self._vpc,
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_type=elbv2.TargetType.IP,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
                timeout=Duration.seconds(5),
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
            ),
        )

        return {
            "web": web_tg,
            "api": api_tg,
        }

    def _configure_alb_routing(self) -> None:
        """Configure ALB listeners and routing rules."""
        # Create default listener for web service
        listener = self._alb.add_listener(
            "WebListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[self._target_groups["web"]],
        )

        # Add routing rule for API service
        listener.add_targets(
            "ApiTargets",
            port=8080,
            protocol=elbv2.ApplicationProtocol.HTTP,
            targets=[self._target_groups["api"]],
            conditions=[elbv2.ListenerCondition.path_patterns(["/api/*"])],
            priority=100,
        )

    def _create_iam_roles(self) -> tuple[iam.Role, iam.Role]:
        """
        Create IAM roles for ECS tasks.

        Returns:
            Tuple containing task role and execution role
        """
        # Task execution role
        execution_role = iam.Role(
            self,
            "EcsTaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )

        # Task role (for application permissions)
        task_role = iam.Role(
            self,
            "EcsTaskRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )

        # Add permissions for service discovery
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "servicediscovery:DeregisterInstance",
                    "servicediscovery:GetInstance",
                    "servicediscovery:GetInstancesHealthStatus",
                    "servicediscovery:GetNamespace",
                    "servicediscovery:GetOperation",
                    "servicediscovery:GetService",
                    "servicediscovery:ListInstances",
                    "servicediscovery:ListNamespaces",
                    "servicediscovery:ListOperations",
                    "servicediscovery:ListServices",
                    "servicediscovery:RegisterInstance",
                    "servicediscovery:UpdateInstanceCustomHealthStatus",
                ],
                resources=["*"],
            )
        )

        return task_role, execution_role

    def _create_discovery_services(self) -> Dict[str, servicediscovery.Service]:
        """
        Create service discovery services for different microservices.

        Returns:
            Dictionary containing service discovery services
        """
        services = {}

        service_names = ["web", "api", "database"]
        for service_name in service_names:
            service = servicediscovery.Service(
                self,
                f"{service_name.title()}DiscoveryService",
                namespace=self._namespace,
                name=service_name,
                dns_record_type=servicediscovery.DnsRecordType.A,
                dns_ttl=Duration.seconds(300),
                custom_health_check=servicediscovery.HealthCheckCustomConfig(
                    failure_threshold=3
                ),
                description=f"Service discovery for {service_name} service",
            )
            services[service_name] = service

        return services

    def _create_task_definitions(self) -> Dict[str, ecs.FargateTaskDefinition]:
        """
        Create ECS task definitions for different services.

        Returns:
            Dictionary containing task definitions
        """
        task_definitions = {}

        # Web service task definition
        web_task_def = ecs.FargateTaskDefinition(
            self,
            "WebTaskDefinition",
            memory_limit_mib=512,
            cpu=256,
            task_role=self._task_role,
            execution_role=self._execution_role,
        )

        web_container = web_task_def.add_container(
            "WebContainer",
            image=ecs.ContainerImage.from_registry("nginx:alpine"),
            port_mappings=[
                ecs.PortMapping(
                    container_port=80,
                    host_port=3000,
                    protocol=ecs.Protocol.TCP,
                )
            ],
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="web-service",
                log_group=logs.LogGroup(
                    self,
                    "WebServiceLogGroup",
                    log_group_name="/ecs/web-service",
                    removal_policy=RemovalPolicy.DESTROY,
                    retention=logs.RetentionDays.ONE_WEEK,
                ),
            ),
        )

        task_definitions["web"] = web_task_def

        # API service task definition
        api_task_def = ecs.FargateTaskDefinition(
            self,
            "ApiTaskDefinition",
            memory_limit_mib=512,
            cpu=256,
            task_role=self._task_role,
            execution_role=self._execution_role,
        )

        api_container = api_task_def.add_container(
            "ApiContainer",
            image=ecs.ContainerImage.from_registry("httpd:alpine"),
            port_mappings=[
                ecs.PortMapping(
                    container_port=80,
                    host_port=8080,
                    protocol=ecs.Protocol.TCP,
                )
            ],
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="api-service",
                log_group=logs.LogGroup(
                    self,
                    "ApiServiceLogGroup",
                    log_group_name="/ecs/api-service",
                    removal_policy=RemovalPolicy.DESTROY,
                    retention=logs.RetentionDays.ONE_WEEK,
                ),
            ),
        )

        task_definitions["api"] = api_task_def

        return task_definitions

    def _create_ecs_services(self) -> Dict[str, ecs.FargateService]:
        """
        Create ECS Fargate services with service discovery and load balancer integration.

        Returns:
            Dictionary containing ECS services
        """
        services = {}

        # Web service
        web_service = ecs.FargateService(
            self,
            "WebService",
            cluster=self._cluster,
            task_definition=self._task_definitions["web"],
            desired_count=2,
            service_name="web-service",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self._security_groups["ecs"]],
            assign_public_ip=False,
            cloud_map_options=ecs.CloudMapOptions(
                cloud_map_service=self._discovery_services["web"],
                name="web",
            ),
            capacity_provider_strategies=[
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE",
                    weight=1,
                )
            ],
        )

        # Add load balancer target
        web_service.attach_to_application_target_group(self._target_groups["web"])
        services["web"] = web_service

        # API service
        api_service = ecs.FargateService(
            self,
            "ApiService",
            cluster=self._cluster,
            task_definition=self._task_definitions["api"],
            desired_count=2,
            service_name="api-service",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_groups=[self._security_groups["ecs"]],
            assign_public_ip=False,
            cloud_map_options=ecs.CloudMapOptions(
                cloud_map_service=self._discovery_services["api"],
                name="api",
            ),
            capacity_provider_strategies=[
                ecs.CapacityProviderStrategy(
                    capacity_provider="FARGATE",
                    weight=1,
                )
            ],
        )

        # Add load balancer target
        api_service.attach_to_application_target_group(self._target_groups["api"])
        services["api"] = api_service

        return services

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "VpcId",
            value=self._vpc.vpc_id,
            description="VPC ID for the microservices infrastructure",
        )

        CfnOutput(
            self,
            "ClusterName",
            value=self._cluster.cluster_name,
            description="ECS cluster name",
        )

        CfnOutput(
            self,
            "LoadBalancerDns",
            value=self._alb.load_balancer_dns_name,
            description="Application Load Balancer DNS name",
        )

        CfnOutput(
            self,
            "LoadBalancerArn",
            value=self._alb.load_balancer_arn,
            description="Application Load Balancer ARN",
        )

        CfnOutput(
            self,
            "ServiceDiscoveryNamespace",
            value=self._namespace.namespace_name,
            description="Service discovery namespace name",
        )

        CfnOutput(
            self,
            "ServiceDiscoveryNamespaceId",
            value=self._namespace.namespace_id,
            description="Service discovery namespace ID",
        )

        # Output service URLs
        CfnOutput(
            self,
            "WebServiceUrl",
            value=f"http://{self._alb.load_balancer_dns_name}",
            description="Web service URL",
        )

        CfnOutput(
            self,
            "ApiServiceUrl",
            value=f"http://{self._alb.load_balancer_dns_name}/api",
            description="API service URL",
        )


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = cdk.App()

    # Get configuration from context or use defaults
    env_config = app.node.try_get_context("env") or {}
    
    # Default environment
    env = Environment(
        account=env_config.get("account"),
        region=env_config.get("region"),
    )

    # Stack configuration
    stack_config = app.node.try_get_context("stack") or {}
    
    EcsServiceDiscoveryStack(
        app,
        "EcsServiceDiscoveryStack",
        env=env,
        namespace_name=stack_config.get("namespace_name", "internal.local"),
        cluster_name=stack_config.get("cluster_name", "microservices-cluster"),
        description="ECS Service Discovery with Route 53 and Application Load Balancer",
    )

    app.synth()


if __name__ == "__main__":
    main()