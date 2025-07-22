#!/usr/bin/env python3
"""
CDK Python Application for Cost-Effective ECS Clusters with EC2 Spot Instances

This application creates an Amazon ECS cluster that leverages EC2 Spot Instances
through capacity providers to achieve 50-70% cost savings while maintaining
high availability and service reliability.

Architecture:
- ECS Cluster with Container Insights
- Auto Scaling Group with mixed instance types (Spot + On-Demand)
- ECS Capacity Provider with managed scaling
- Sample ECS Service with auto scaling
- CloudWatch monitoring and logging

Author: AWS CDK Team
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_autoscaling as autoscaling,
    aws_iam as iam,
    aws_logs as logs,
    aws_applicationautoscaling as appscaling,
    aws_elasticloadbalancingv2 as elbv2,
)
from constructs import Construct


class CostEffectiveEcsStack(Stack):
    """
    Stack for creating cost-effective ECS clusters with Spot Instances.
    
    This stack implements best practices for running containerized workloads
    on a mix of EC2 Spot and On-Demand instances to optimize costs while
    maintaining high availability.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: Optional[ec2.Vpc] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.cluster_name = "cost-optimized-cluster"
        self.service_name = "spot-resilient-service"
        self.capacity_provider_name = "spot-capacity-provider"
        
        # Create or use existing VPC
        self.vpc = vpc or self._create_vpc()
        
        # Create IAM roles
        self.ecs_task_execution_role = self._create_ecs_task_execution_role()
        self.ecs_instance_role = self._create_ecs_instance_role()
        self.ecs_instance_profile = self._create_instance_profile()
        
        # Create security groups
        self.ecs_security_group = self._create_ecs_security_group()
        self.alb_security_group = self._create_alb_security_group()
        
        # Create ECS cluster
        self.cluster = self._create_ecs_cluster()
        
        # Create launch template and Auto Scaling Group
        self.launch_template = self._create_launch_template()
        self.auto_scaling_group = self._create_auto_scaling_group()
        
        # Create capacity provider
        self.capacity_provider = self._create_capacity_provider()
        
        # Associate capacity provider with cluster
        self._associate_capacity_provider()
        
        # Create Application Load Balancer
        self.load_balancer = self._create_application_load_balancer()
        
        # Create task definition
        self.task_definition = self._create_task_definition()
        
        # Create ECS service
        self.service = self._create_ecs_service()
        
        # Set up service auto scaling
        self._setup_service_auto_scaling()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """Create a VPC with public and private subnets across 3 AZs."""
        return ec2.Vpc(
            self,
            "EcsVpc",
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

    def _create_ecs_task_execution_role(self) -> iam.Role:
        """Create IAM role for ECS task execution."""
        return iam.Role(
            self,
            "EcsTaskExecutionRole",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ],
            description="IAM role for ECS task execution with Spot instances",
        )

    def _create_ecs_instance_role(self) -> iam.Role:
        """Create IAM role for EC2 instances in ECS cluster."""
        return iam.Role(
            self,
            "EcsInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2ContainerServiceforEC2Role"
                ),
            ],
            description="IAM role for EC2 instances in ECS cluster",
        )

    def _create_instance_profile(self) -> iam.CfnInstanceProfile:
        """Create instance profile for EC2 instances."""
        return iam.CfnInstanceProfile(
            self,
            "EcsInstanceProfile",
            roles=[self.ecs_instance_role.role_name],
            instance_profile_name="ecsInstanceProfile",
        )

    def _create_ecs_security_group(self) -> ec2.SecurityGroup:
        """Create security group for ECS instances."""
        sg = ec2.SecurityGroup(
            self,
            "EcsSecurityGroup",
            vpc=self.vpc,
            description="Security group for ECS instances with Spot configuration",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from ALB
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp_range(32768, 65535),
            description="Allow dynamic port mapping from ALB",
        )
        
        return sg

    def _create_alb_security_group(self) -> ec2.SecurityGroup:
        """Create security group for Application Load Balancer."""
        sg = ec2.SecurityGroup(
            self,
            "AlbSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer",
            allow_all_outbound=True,
        )
        
        # Allow HTTP traffic from internet
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP traffic from internet",
        )
        
        # Allow HTTPS traffic from internet
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS traffic from internet",
        )
        
        return sg

    def _create_ecs_cluster(self) -> ecs.Cluster:
        """Create ECS cluster with Container Insights enabled."""
        return ecs.Cluster(
            self,
            "EcsCluster",
            cluster_name=self.cluster_name,
            vpc=self.vpc,
            container_insights=True,
            enable_fargate_capacity_providers=False,
        )

    def _create_launch_template(self) -> ec2.LaunchTemplate:
        """Create launch template for EC2 instances with ECS optimization."""
        # Get the latest ECS-optimized AMI
        ecs_ami = ecs.EcsOptimizedImage.amazon_linux2()
        
        # Create user data script for ECS configuration
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            f"echo ECS_CLUSTER={self.cluster_name} >> /etc/ecs/ecs.config",
            "echo ECS_ENABLE_SPOT_INSTANCE_DRAINING=true >> /etc/ecs/ecs.config",
            "echo ECS_CONTAINER_STOP_TIMEOUT=120s >> /etc/ecs/ecs.config",
            "echo ECS_CONTAINER_START_TIMEOUT=10m >> /etc/ecs/ecs.config",
            # Enable CloudWatch logs for ECS agent
            "echo ECS_AVAILABLE_LOGGING_DRIVERS='[\"json-file\",\"awslogs\"]' >> /etc/ecs/ecs.config",
        )
        
        return ec2.LaunchTemplate(
            self,
            "EcsLaunchTemplate",
            launch_template_name="ecs-spot-launch-template",
            machine_image=ecs_ami,
            instance_type=ec2.InstanceType("m5.large"),  # Default, will be overridden
            security_group=self.ecs_security_group,
            user_data=user_data,
            role=self.ecs_instance_role,
            block_devices=[
                ec2.BlockDevice(
                    device_name="/dev/xvda",
                    volume=ec2.BlockDeviceVolume.ebs(
                        volume_size=30,
                        volume_type=ec2.EbsDeviceVolumeType.GP3,
                        encrypted=True,
                        delete_on_termination=True,
                    ),
                ),
            ],
            require_imdsv2=True,
        )

    def _create_auto_scaling_group(self) -> autoscaling.AutoScalingGroup:
        """Create Auto Scaling Group with mixed instance policy."""
        # Define instance types for diversification
        instance_overrides = [
            {
                "instance_type": "m5.large",
                "weighted_capacity": 1,
            },
            {
                "instance_type": "m4.large", 
                "weighted_capacity": 1,
            },
            {
                "instance_type": "c5.large",
                "weighted_capacity": 1,
            },
            {
                "instance_type": "c4.large",
                "weighted_capacity": 1,
            },
            {
                "instance_type": "r5.large",
                "weighted_capacity": 1,
            },
        ]
        
        # Create ASG with mixed instances policy
        asg = autoscaling.AutoScalingGroup(
            self,
            "EcsAutoScalingGroup",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            launch_template=self.launch_template,
            min_capacity=1,
            max_capacity=10,
            desired_capacity=3,
            health_check=autoscaling.HealthCheck.ecs(
                grace=Duration.minutes(5)
            ),
            update_policy=autoscaling.UpdatePolicy.rolling_update(
                max_batch_size=1,
                min_instances_in_service=1,
                pause_time=Duration.minutes(5),
            ),
            termination_policies=[
                autoscaling.TerminationPolicy.OLDEST_INSTANCE,
                autoscaling.TerminationPolicy.DEFAULT,
            ],
            group_metrics=[
                autoscaling.GroupMetrics.all(),
            ],
        )
        
        # Configure mixed instances policy at the CloudFormation level
        asg_cfn = asg.node.default_child
        asg_cfn.mixed_instances_policy = {
            "launch_template": {
                "launch_template_specification": {
                    "launch_template_id": self.launch_template.launch_template_id,
                    "version": "$Latest",
                },
                "overrides": [
                    {
                        "instance_type": override["instance_type"],
                        "weighted_capacity": override["weighted_capacity"],
                    }
                    for override in instance_overrides
                ],
            },
            "instances_distribution": {
                "on_demand_allocation_strategy": "prioritized",
                "on_demand_base_capacity": 1,
                "on_demand_percentage_above_base_capacity": 20,
                "spot_allocation_strategy": "diversified",
                "spot_instance_pools": 4,
                "spot_max_price": "0.10",  # Maximum price per hour
            },
        }
        
        # Add tags
        cdk.Tags.of(asg).add("Name", "ECS-Spot-ASG")
        cdk.Tags.of(asg).add("Environment", "production")
        cdk.Tags.of(asg).add("CostOptimized", "true")
        
        return asg

    def _create_capacity_provider(self) -> ecs.CfnCapacityProvider:
        """Create ECS capacity provider for the Auto Scaling Group."""
        return ecs.CfnCapacityProvider(
            self,
            "SpotCapacityProvider",
            name=self.capacity_provider_name,
            auto_scaling_group_provider=ecs.CfnCapacityProvider.AutoScalingGroupProviderProperty(
                auto_scaling_group_arn=self.auto_scaling_group.auto_scaling_group_arn,
                managed_scaling=ecs.CfnCapacityProvider.ManagedScalingProperty(
                    status="ENABLED",
                    target_capacity=80,
                    minimum_scaling_step_size=1,
                    maximum_scaling_step_size=3,
                    instance_warmup_period=300,
                ),
                managed_termination_protection="ENABLED",
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="production"),
                cdk.CfnTag(key="CostOptimized", value="true"),
            ],
        )

    def _associate_capacity_provider(self) -> None:
        """Associate capacity provider with the ECS cluster."""
        ecs.CfnClusterCapacityProviderAssociations(
            self,
            "ClusterCapacityProviderAssociation",
            cluster=self.cluster.cluster_name,
            capacity_providers=[self.capacity_provider.name],
            default_capacity_provider_strategy=[
                ecs.CfnClusterCapacityProviderAssociations.CapacityProviderStrategyProperty(
                    capacity_provider=self.capacity_provider.name,
                    weight=1,
                    base=0,
                )
            ],
        )

    def _create_application_load_balancer(self) -> elbv2.ApplicationLoadBalancer:
        """Create Application Load Balancer for the ECS service."""
        return elbv2.ApplicationLoadBalancer(
            self,
            "EcsLoadBalancer",
            vpc=self.vpc,
            internet_facing=True,
            security_group=self.alb_security_group,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            load_balancer_name="ecs-spot-alb",
        )

    def _create_task_definition(self) -> ecs.Ec2TaskDefinition:
        """Create ECS task definition optimized for Spot instances."""
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "EcsTaskLogGroup",
            log_group_name=f"/ecs/{self.service_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create task definition
        task_definition = ecs.Ec2TaskDefinition(
            self,
            "SpotResilientTaskDefinition",
            family="spot-resilient-app",
            execution_role=self.ecs_task_execution_role,
            network_mode=ecs.NetworkMode.BRIDGE,
        )
        
        # Add container to task definition
        container = task_definition.add_container(
            "web-server",
            image=ecs.ContainerImage.from_registry("public.ecr.aws/docker/library/nginx:latest"),
            cpu=256,
            memory_limit_mib=512,
            essential=True,
            logging=ecs.LogDrivers.aws_logs(
                stream_prefix="ecs",
                log_group=log_group,
            ),
            health_check=ecs.HealthCheck(
                command=["CMD-SHELL", "curl -f http://localhost/ || exit 1"],
                interval=Duration.seconds(30),
                timeout=Duration.seconds(5),
                retries=3,
                start_period=Duration.seconds(60),
            ),
        )
        
        # Add port mapping with dynamic port allocation
        container.add_port_mappings(
            ecs.PortMapping(
                container_port=80,
                host_port=0,  # Dynamic port mapping
                protocol=ecs.Protocol.TCP,
            )
        )
        
        return task_definition

    def _create_ecs_service(self) -> ecs.Ec2Service:
        """Create ECS service with resilient configuration."""
        # Create target group for ALB
        target_group = elbv2.ApplicationTargetGroup(
            self,
            "EcsTargetGroup",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            vpc=self.vpc,
            target_type=elbv2.TargetType.INSTANCE,
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_threshold_count=2,
                unhealthy_threshold_count=3,
                timeout=Duration.seconds(5),
                interval=Duration.seconds(30),
                path="/",
                protocol=elbv2.Protocol.HTTP,
            ),
            deregistration_delay=Duration.seconds(30),
        )
        
        # Create listener for ALB
        listener = self.load_balancer.add_listener(
            "EcsListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_target_groups=[target_group],
        )
        
        # Create ECS service
        service = ecs.Ec2Service(
            self,
            "SpotResilientService",
            cluster=self.cluster,
            task_definition=self.task_definition,
            service_name=self.service_name,
            desired_count=6,
            capacity_provider_strategies=[
                ecs.CapacityProviderStrategy(
                    capacity_provider=self.capacity_provider.name,
                    weight=1,
                    base=2,
                )
            ],
            deployment_configuration=ecs.DeploymentConfiguration(
                maximum_percent=200,
                minimum_healthy_percent=50,
                deployment_circuit_breaker=ecs.DeploymentCircuitBreaker(
                    enable=True,
                    rollback=True,
                ),
            ),
            health_check_grace_period=Duration.seconds(300),
            enable_execute_command=True,
        )
        
        # Associate service with target group
        service.attach_to_application_target_group(target_group)
        
        # Add tags
        cdk.Tags.of(service).add("Environment", "production")
        cdk.Tags.of(service).add("CostOptimized", "true")
        
        return service

    def _setup_service_auto_scaling(self) -> None:
        """Configure auto scaling for the ECS service."""
        # Create scalable target
        scalable_target = self.service.auto_scale_task_count(
            min_capacity=2,
            max_capacity=20,
        )
        
        # Add CPU-based scaling policy
        scalable_target.scale_on_cpu_utilization(
            "CpuScaling",
            target_utilization_percent=60,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )
        
        # Add memory-based scaling policy
        scalable_target.scale_on_memory_utilization(
            "MemoryScaling",
            target_utilization_percent=70,
            scale_in_cooldown=Duration.seconds(300),
            scale_out_cooldown=Duration.seconds(300),
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "ClusterName",
            value=self.cluster.cluster_name,
            description="Name of the ECS cluster",
        )
        
        CfnOutput(
            self,
            "ServiceName",
            value=self.service.service_name,
            description="Name of the ECS service",
        )
        
        CfnOutput(
            self,
            "CapacityProviderName",
            value=self.capacity_provider.name,
            description="Name of the capacity provider",
        )
        
        CfnOutput(
            self,
            "LoadBalancerDNS",
            value=self.load_balancer.load_balancer_dns_name,
            description="DNS name of the Application Load Balancer",
        )
        
        CfnOutput(
            self,
            "LoadBalancerURL",
            value=f"http://{self.load_balancer.load_balancer_dns_name}",
            description="URL of the Application Load Balancer",
        )
        
        CfnOutput(
            self,
            "AutoScalingGroupName",
            value=self.auto_scaling_group.auto_scaling_group_name,
            description="Name of the Auto Scaling Group",
        )


class CostEffectiveEcsApp(cdk.App):
    """CDK Application for cost-effective ECS clusters."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )
        
        # Create the main stack
        CostEffectiveEcsStack(
            self,
            "CostEffectiveEcsStack",
            env=env,
            description="Cost-effective ECS cluster with EC2 Spot Instances",
        )


if __name__ == "__main__":
    app = CostEffectiveEcsApp()
    app.synth()