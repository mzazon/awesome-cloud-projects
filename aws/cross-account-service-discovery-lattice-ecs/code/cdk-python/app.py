#!/usr/bin/env python3
"""
Cross-Account Service Discovery with VPC Lattice and ECS
CDK Python Application

This CDK application deploys the infrastructure for cross-account service discovery
using Amazon VPC Lattice, ECS Fargate, EventBridge, and CloudWatch.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_vpclattice as vpclattice,
    aws_iam as iam,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_ram as ram,
)
from constructs import Construct


class CrossAccountServiceDiscoveryStack(Stack):
    """
    Main CDK Stack for Cross-Account Service Discovery with VPC Lattice and ECS.
    
    This stack creates:
    - VPC Lattice Service Network for cross-account service discovery
    - ECS Fargate cluster and service with automatic registration
    - VPC Lattice service, target group, and listener
    - EventBridge rules for service discovery event monitoring
    - CloudWatch dashboard for observability
    - AWS RAM resource share for cross-account access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters and configuration
        self.random_suffix = self.node.try_get_context("random_suffix") or "demo"
        self.account_b_id = self.node.try_get_context("account_b_id") or "123456789012"
        
        # Create VPC (use default VPC or create new one)
        self.vpc = self._create_or_get_vpc()
        
        # Create CloudWatch log groups
        self.log_groups = self._create_log_groups()
        
        # Create VPC Lattice Service Network
        self.service_network = self._create_service_network()
        
        # Create ECS cluster and task definition
        self.ecs_cluster = self._create_ecs_cluster()
        self.task_definition = self._create_task_definition()
        
        # Create VPC Lattice components
        self.target_group = self._create_target_group()
        self.lattice_service = self._create_lattice_service()
        self.listener = self._create_listener()
        
        # Associate service with service network
        self._create_service_associations()
        
        # Create ECS service with VPC Lattice integration
        self.ecs_service = self._create_ecs_service()
        
        # Create AWS RAM resource share
        self.resource_share = self._create_resource_share()
        
        # Create EventBridge monitoring
        self._create_eventbridge_monitoring()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_or_get_vpc(self) -> ec2.IVpc:
        """Create a new VPC or use the default VPC."""
        # For this example, we'll create a simple VPC
        # In production, you might want to use an existing VPC
        vpc = ec2.Vpc(
            self,
            "ServiceDiscoveryVpc",
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
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        cdk.Tags.of(vpc).add("Name", f"vpc-lattice-demo-{self.random_suffix}")
        return vpc

    def _create_log_groups(self) -> Dict[str, logs.LogGroup]:
        """Create CloudWatch log groups for ECS and EventBridge."""
        log_groups = {}
        
        # ECS log group
        log_groups["ecs"] = logs.LogGroup(
            self,
            "EcsLogGroup",
            log_group_name="/ecs/producer",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # EventBridge log group
        log_groups["events"] = logs.LogGroup(
            self,
            "EventsLogGroup",
            log_group_name="/aws/events/vpc-lattice",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_groups

    def _create_service_network(self) -> vpclattice.CfnServiceNetwork:
        """Create VPC Lattice Service Network."""
        service_network = vpclattice.CfnServiceNetwork(
            self,
            "ServiceNetwork",
            name=f"cross-account-network-{self.random_suffix}",
            auth_type="AWS_IAM",
        )
        
        cdk.Tags.of(service_network).add("Name", f"cross-account-network-{self.random_suffix}")
        return service_network

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """Create ECS Fargate cluster."""
        cluster = ecs.Cluster(
            self,
            "ProducerCluster",
            cluster_name=f"producer-cluster-{self.random_suffix}",
            vpc=self.vpc,
            enable_fargate_capacity_providers=True,
        )
        
        cdk.Tags.of(cluster).add("Name", f"producer-cluster-{self.random_suffix}")
        return cluster

    def _create_task_definition(self) -> ecs.FargateTaskDefinition:
        """Create ECS Fargate task definition."""
        # Create task execution role
        execution_role = iam.Role(
            self,
            "TaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )
        
        # Create task definition
        task_definition = ecs.FargateTaskDefinition(
            self,
            "ProducerTaskDefinition",
            family="producer-task",
            cpu=256,
            memory_limit_mib=512,
            execution_role=execution_role,
        )
        
        # Add container
        container = task_definition.add_container(
            "producer-container",
            image=ecs.ContainerImage.from_registry("nginx:latest"),
            port_mappings=[
                ecs.PortMapping(
                    container_port=80,
                    protocol=ecs.Protocol.TCP,
                )
            ],
            essential=True,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=self.log_groups["ecs"],
            ),
        )
        
        return task_definition

    def _create_target_group(self) -> vpclattice.CfnTargetGroup:
        """Create VPC Lattice target group."""
        target_group = vpclattice.CfnTargetGroup(
            self,
            "ProducerTargetGroup",
            name=f"producer-targets-{self.random_suffix}",
            type="IP",
            protocol="HTTP",
            port=80,
            vpc_identifier=self.vpc.vpc_id,
            health_check_config=vpclattice.CfnTargetGroup.HealthCheckConfigProperty(
                enabled=True,
                protocol="HTTP",
                path="/",
                timeout_seconds=5,
                interval_seconds=30,
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
            ),
        )
        
        cdk.Tags.of(target_group).add("Name", f"producer-targets-{self.random_suffix}")
        return target_group

    def _create_lattice_service(self) -> vpclattice.CfnService:
        """Create VPC Lattice service."""
        lattice_service = vpclattice.CfnService(
            self,
            "LatticeService",
            name=f"lattice-producer-{self.random_suffix}",
            auth_type="AWS_IAM",
        )
        
        cdk.Tags.of(lattice_service).add("Name", f"lattice-producer-{self.random_suffix}")
        return lattice_service

    def _create_listener(self) -> vpclattice.CfnListener:
        """Create VPC Lattice listener."""
        listener = vpclattice.CfnListener(
            self,
            "HttpListener",
            service_identifier=self.lattice_service.attr_arn,
            name="http-listener",
            protocol="HTTP",
            port=80,
            default_action=vpclattice.CfnListener.DefaultActionProperty(
                forward=vpclattice.CfnListener.ForwardProperty(
                    target_groups=[
                        vpclattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.target_group.attr_arn,
                            weight=100,
                        )
                    ]
                )
            ),
        )
        
        return listener

    def _create_service_associations(self) -> None:
        """Create VPC Lattice service and VPC associations."""
        # Associate service with service network
        vpclattice.CfnServiceNetworkServiceAssociation(
            self,
            "ServiceNetworkServiceAssociation",
            service_network_identifier=self.service_network.attr_arn,
            service_identifier=self.lattice_service.attr_arn,
        )
        
        # Associate VPC with service network
        vpclattice.CfnServiceNetworkVpcAssociation(
            self,
            "ServiceNetworkVpcAssociation",
            service_network_identifier=self.service_network.attr_arn,
            vpc_identifier=self.vpc.vpc_id,
        )

    def _create_ecs_service(self) -> ecs.FargateService:
        """Create ECS Fargate service with VPC Lattice integration."""
        # Create security group for ECS tasks
        security_group = ec2.SecurityGroup(
            self,
            "EcsTaskSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS tasks",
            allow_all_outbound=True,
        )
        
        security_group.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP traffic from VPC Lattice",
        )
        
        # Create ECS service
        service = ecs.FargateService(
            self,
            "ProducerService",
            service_name=f"producer-service-{self.random_suffix}",
            cluster=self.ecs_cluster,
            task_definition=self.task_definition,
            desired_count=2,
            assign_public_ip=True,  # Required for public subnets
            vpc_subnets=ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC),
            security_groups=[security_group],
            enable_logging=True,
        )
        
        # Note: VPC Lattice target group registration is handled through ECS service
        # integration, which would typically be configured through additional CDK constructs
        # or AWS CLI commands post-deployment
        
        return service

    def _create_resource_share(self) -> ram.CfnResourceShare:
        """Create AWS RAM resource share for cross-account access."""
        resource_share = ram.CfnResourceShare(
            self,
            "LatticeNetworkShare",
            name=f"lattice-network-share-{self.random_suffix}",
            resource_arns=[self.service_network.attr_arn],
            principals=[self.account_b_id],
            allow_external_principals=True,
        )
        
        return resource_share

    def _create_eventbridge_monitoring(self) -> None:
        """Create EventBridge rules for VPC Lattice event monitoring."""
        # Create IAM role for EventBridge to write to CloudWatch Logs
        eventbridge_role = iam.Role(
            self,
            "EventBridgeLogsRole",
            role_name="EventBridgeLogsRole",
            assumed_by=iam.ServicePrincipal("events.amazonaws.com"),
            inline_policies={
                "EventBridgeLogsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/events/vpc-lattice:*"
                            ],
                        )
                    ]
                )
            },
        )
        
        # Create EventBridge rule for VPC Lattice events
        rule = events.Rule(
            self,
            "VpcLatticeEventsRule",
            rule_name="vpc-lattice-events",
            description="Capture VPC Lattice service discovery events",
            event_pattern=events.EventPattern(
                source=["aws.vpc-lattice"],
                detail_type=[
                    "VPC Lattice Service Network State Change",
                    "VPC Lattice Service State Change",
                ],
            ),
        )
        
        # Add CloudWatch Logs target
        rule.add_target(
            targets.CloudWatchLogGroup(
                log_group=self.log_groups["events"],
                event=events.RuleTargetInput.from_object({
                    "timestamp": events.EventField.from_path("$.time"),
                    "source": events.EventField.from_path("$.source"),
                    "detail-type": events.EventField.from_path("$.detail-type"),
                    "detail": events.EventField.from_path("$.detail"),
                }),
            )
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "ServiceDiscoveryDashboard",
            dashboard_name="cross-account-service-discovery",
        )
        
        # Add VPC Lattice metrics widget
        lattice_metrics_widget = cloudwatch.GraphWidget(
            title="VPC Lattice Service Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="ActiveConnectionCount",
                    dimensions_map={
                        "ServiceName": f"lattice-producer-{self.random_suffix}"
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="NewConnectionCount",
                    dimensions_map={
                        "ServiceName": f"lattice-producer-{self.random_suffix}"
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/VpcLattice",
                    metric_name="ProcessedBytes",
                    dimensions_map={
                        "ServiceName": f"lattice-producer-{self.random_suffix}"
                    },
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )
        
        # Add ECS service metrics widget
        ecs_metrics_widget = cloudwatch.GraphWidget(
            title="ECS Service Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "ServiceName": f"producer-service-{self.random_suffix}",
                        "ClusterName": f"producer-cluster-{self.random_suffix}",
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/ECS",
                    metric_name="MemoryUtilization",
                    dimensions_map={
                        "ServiceName": f"producer-service-{self.random_suffix}",
                        "ClusterName": f"producer-cluster-{self.random_suffix}",
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )
        
        # Add log insights widget for VPC Lattice events
        log_widget = cloudwatch.LogQueryWidget(
            title="VPC Lattice Events",
            log_groups=[self.log_groups["events"]],
            query_lines=[
                "fields @timestamp, source, detail-type, detail",
                "sort @timestamp desc",
                "limit 100",
            ],
            width=24,
            height=6,
        )
        
        dashboard.add_widgets(lattice_metrics_widget, ecs_metrics_widget)
        dashboard.add_widgets(log_widget)
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
            export_name=f"{self.stack_name}-ServiceNetworkId",
        )
        
        CfnOutput(
            self,
            "ServiceNetworkArn",
            value=self.service_network.attr_arn,
            description="VPC Lattice Service Network ARN",
            export_name=f"{self.stack_name}-ServiceNetworkArn",
        )
        
        CfnOutput(
            self,
            "LatticeServiceArn",
            value=self.lattice_service.attr_arn,
            description="VPC Lattice Service ARN",
            export_name=f"{self.stack_name}-LatticeServiceArn",
        )
        
        CfnOutput(
            self,
            "EcsClusterName",
            value=self.ecs_cluster.cluster_name,
            description="ECS Cluster Name",
            export_name=f"{self.stack_name}-EcsClusterName",
        )
        
        CfnOutput(
            self,
            "ResourceShareArn",
            value=self.resource_share.attr_arn,
            description="AWS RAM Resource Share ARN",
            export_name=f"{self.stack_name}-ResourceShareArn",
        )
        
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
            export_name=f"{self.stack_name}-VpcId",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get context values or use defaults
    env = cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION"),
    )
    
    # Create the stack
    CrossAccountServiceDiscoveryStack(
        app,
        "CrossAccountServiceDiscoveryStack",
        env=env,
        description="Cross-Account Service Discovery with VPC Lattice and ECS",
    )
    
    app.synth()


if __name__ == "__main__":
    main()