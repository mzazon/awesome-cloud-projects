#!/usr/bin/env python3
"""
AWS CDK Application for Advanced Request Routing with VPC Lattice and ALB

This application demonstrates sophisticated layer 7 routing across multiple VPCs
using VPC Lattice service networks integrated with Application Load Balancers.
The architecture enables flexible request routing based on paths, headers, and
methods while maintaining centralized authentication and authorization policies.

Key Components:
- VPC Lattice Service Network for cross-VPC connectivity
- Internal Application Load Balancers as routing targets
- EC2 instances with different content for routing demonstration
- Advanced routing rules (path-based, header-based, method-based)
- IAM authentication policies for secure service-to-service communication

Author: AWS CDK Team
Version: 1.0
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_elasticloadbalancingv2 as elbv2,
    aws_vpclattice as lattice,
    aws_iam as iam,
    CfnOutput,
    Tags,
    RemovalPolicy
)
from typing import Dict, List, Optional
import json


class AdvancedRequestRoutingStack(Stack):
    """
    CDK Stack implementing advanced request routing with VPC Lattice and ALB.
    
    This stack creates a complete microservices communication fabric that
    demonstrates sophisticated routing capabilities across multiple VPCs
    using VPC Lattice service networks and Application Load Balancers.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.environment_name = "advanced-routing"
        self.service_name = "api-gateway-service"
        
        # Create networking infrastructure
        self._create_vpc_infrastructure()
        
        # Create VPC Lattice service network
        self._create_lattice_service_network()
        
        # Create and configure Application Load Balancers
        self._create_application_load_balancers()
        
        # Create EC2 instances for demonstration
        self._create_ec2_instances()
        
        # Configure ALB target groups and listeners
        self._configure_alb_targets()
        
        # Create VPC Lattice service and routing rules
        self._create_lattice_service()
        
        # Configure advanced routing rules
        self._configure_routing_rules()
        
        # Apply IAM authentication policies
        self._configure_authentication()
        
        # Create outputs for validation and testing
        self._create_outputs()

    def _create_vpc_infrastructure(self) -> None:
        """
        Create VPC infrastructure including primary and target VPCs.
        
        The primary VPC hosts the main application components while the
        target VPC demonstrates cross-VPC connectivity through VPC Lattice.
        """
        # Primary VPC for main application components
        self.primary_vpc = ec2.Vpc(
            self, "PrimaryVPC",
            vpc_name=f"{self.environment_name}-primary-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            nat_gateways=1,
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

        # Target VPC for cross-VPC connectivity demonstration
        self.target_vpc = ec2.Vpc(
            self, "TargetVPC",
            vpc_name=f"{self.environment_name}-target-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.1.0.0/16"),
            max_azs=2,
            nat_gateways=1,
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

        # Security group for ALB instances
        self.alb_security_group = ec2.SecurityGroup(
            self, "ALBSecurityGroup",
            vpc=self.primary_vpc,
            description="Security group for VPC Lattice ALB targets",
            allow_all_outbound=True
        )

        # Allow HTTP/HTTPS traffic from VPC Lattice managed prefix lists
        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from VPC Lattice"
        )

        self.alb_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from VPC Lattice"
        )

        # Security group for EC2 instances
        self.ec2_security_group = ec2.SecurityGroup(
            self, "EC2SecurityGroup",
            vpc=self.primary_vpc,
            description="Security group for EC2 web servers",
            allow_all_outbound=True
        )

        # Allow HTTP traffic from ALB security group
        self.ec2_security_group.add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.alb_security_group.security_group_id),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from ALB"
        )

        # Tag VPC resources
        Tags.of(self.primary_vpc).add("Environment", self.environment_name)
        Tags.of(self.target_vpc).add("Environment", self.environment_name)

    def _create_lattice_service_network(self) -> None:
        """
        Create VPC Lattice service network for application-layer networking.
        
        The service network provides a logical boundary for secure, scalable
        communication between microservices while abstracting network complexity.
        """
        # Create VPC Lattice service network
        self.service_network = lattice.CfnServiceNetwork(
            self, "ServiceNetwork",
            name=f"{self.environment_name}-network",
            auth_type="AWS_IAM"
        )

        # Associate primary VPC with service network
        self.primary_vpc_association = lattice.CfnServiceNetworkVpcAssociation(
            self, "PrimaryVPCAssociation",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=self.primary_vpc.vpc_id
        )

        # Associate target VPC with service network
        self.target_vpc_association = lattice.CfnServiceNetworkVpcAssociation(
            self, "TargetVPCAssociation",
            service_network_identifier=self.service_network.attr_id,
            vpc_identifier=self.target_vpc.vpc_id
        )

    def _create_application_load_balancers(self) -> None:
        """
        Create internal Application Load Balancers for sophisticated routing.
        
        Internal ALBs serve as layer 7 traffic distributors within VPC Lattice,
        providing advanced routing capabilities based on request characteristics.
        """
        # Create internal ALB for API services
        self.api_alb = elbv2.ApplicationLoadBalancer(
            self, "APIServiceALB",
            vpc=self.primary_vpc,
            internet_facing=False,
            load_balancer_name=f"{self.environment_name}-api-alb",
            security_group=self.alb_security_group,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )
        )

        # Create internal ALB for backend services
        self.backend_alb = elbv2.ApplicationLoadBalancer(
            self, "BackendServiceALB",
            vpc=self.primary_vpc,
            internet_facing=False,
            load_balancer_name=f"{self.environment_name}-backend-alb",
            security_group=self.alb_security_group,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )
        )

    def _create_ec2_instances(self) -> None:
        """
        Create EC2 instances running web servers for routing demonstration.
        
        These instances serve different content to demonstrate the effectiveness
        of various routing rules including path-based and header-based routing.
        """
        # User data script for web server configuration
        user_data_script = ec2.UserData.for_linux()
        user_data_script.add_commands(
            "dnf update -y",
            "dnf install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            "",
            "# Create different content for routing demonstration",
            "mkdir -p /var/www/html/api/v1",
            "echo '<h1>API V1 Service</h1><p>Path: /api/v1/</p>' > /var/www/html/api/v1/index.html",
            "echo '<h1>Default Service</h1><p>Default routing target</p>' > /var/www/html/index.html",
            "echo '<h1>Beta Service</h1><p>X-Service-Version: beta</p>' > /var/www/html/beta.html",
            "",
            "# Configure virtual hosts for header-based routing",
            "cat >> /etc/httpd/conf/httpd.conf << 'VHOST'",
            "<VirtualHost *:80>",
            "    DocumentRoot /var/www/html",
            "    RewriteEngine On",
            "    RewriteCond %{HTTP:X-Service-Version} beta",
            "    RewriteRule ^(.*)$ /beta.html [L]",
            "</VirtualHost>",
            "VHOST",
            "",
            "systemctl restart httpd"
        )

        # Launch EC2 instances for API services
        self.api_instance = ec2.Instance(
            self, "APIServiceInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2023(),
            vpc=self.primary_vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_group=self.ec2_security_group,
            user_data=user_data_script,
            instance_name=f"{self.environment_name}-api-instance"
        )

        # Launch EC2 instance for backend services
        self.backend_instance = ec2.Instance(
            self, "BackendServiceInstance",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            machine_image=ec2.MachineImage.latest_amazon_linux2023(),
            vpc=self.primary_vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            security_group=self.ec2_security_group,
            user_data=user_data_script,
            instance_name=f"{self.environment_name}-backend-instance"
        )

    def _configure_alb_targets(self) -> None:
        """
        Configure ALB target groups and register EC2 instances.
        
        Target groups define how ALBs distribute traffic to backend instances
        with health checks to ensure reliable traffic distribution.
        """
        # Create target group for API services
        self.api_target_group = elbv2.ApplicationTargetGroup(
            self, "APITargetGroup",
            vpc=self.primary_vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_group_name=f"{self.environment_name}-api-tg",
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=cdk.Duration.seconds(30),
                path="/",
                port="80",
                protocol=elbv2.Protocol.HTTP,
                timeout=cdk.Duration.seconds(10),
                unhealthy_threshold_count=3,
                healthy_threshold_count=2
            ),
            targets=[elbv2.InstanceTarget(self.api_instance, 80)]
        )

        # Create target group for backend services
        self.backend_target_group = elbv2.ApplicationTargetGroup(
            self, "BackendTargetGroup",
            vpc=self.primary_vpc,
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            target_group_name=f"{self.environment_name}-backend-tg",
            health_check=elbv2.HealthCheck(
                enabled=True,
                healthy_http_codes="200",
                interval=cdk.Duration.seconds(30),
                path="/",
                port="80",
                protocol=elbv2.Protocol.HTTP,
                timeout=cdk.Duration.seconds(10),
                unhealthy_threshold_count=3,
                healthy_threshold_count=2
            ),
            targets=[elbv2.InstanceTarget(self.backend_instance, 80)]
        )

        # Create ALB listeners
        self.api_listener = self.api_alb.add_listener(
            "APIListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward([self.api_target_group])
        )

        self.backend_listener = self.backend_alb.add_listener(
            "BackendListener",
            port=80,
            protocol=elbv2.ApplicationProtocol.HTTP,
            default_action=elbv2.ListenerAction.forward([self.backend_target_group])
        )

    def _create_lattice_service(self) -> None:
        """
        Create VPC Lattice service and configure target groups.
        
        The VPC Lattice service acts as the central routing hub, receiving
        client requests and applying routing rules to direct traffic to ALBs.
        """
        # Create VPC Lattice service
        self.lattice_service = lattice.CfnService(
            self, "LatticeService",
            name=self.service_name,
            auth_type="AWS_IAM"
        )

        # Associate service with service network
        self.service_association = lattice.CfnServiceNetworkServiceAssociation(
            self, "ServiceAssociation",
            service_network_identifier=self.service_network.attr_id,
            service_identifier=self.lattice_service.attr_id
        )

        # Create VPC Lattice target group for API ALB
        self.lattice_api_target_group = lattice.CfnTargetGroup(
            self, "LatticeAPITargetGroup",
            name=f"{self.environment_name}-api-alb-tg",
            type="ALB",
            config=lattice.CfnTargetGroup.TargetGroupConfigProperty(
                vpc_identifier=self.primary_vpc.vpc_id
            ),
            targets=[
                lattice.CfnTargetGroup.TargetProperty(
                    id=self.api_alb.load_balancer_arn
                )
            ]
        )

        # Create VPC Lattice target group for backend ALB
        self.lattice_backend_target_group = lattice.CfnTargetGroup(
            self, "LatticeBackendTargetGroup",
            name=f"{self.environment_name}-backend-alb-tg",
            type="ALB",
            config=lattice.CfnTargetGroup.TargetGroupConfigProperty(
                vpc_identifier=self.primary_vpc.vpc_id
            ),
            targets=[
                lattice.CfnTargetGroup.TargetProperty(
                    id=self.backend_alb.load_balancer_arn
                )
            ]
        )

        # Create HTTP listener for VPC Lattice service
        self.lattice_listener = lattice.CfnListener(
            self, "LatticeListener",
            service_identifier=self.lattice_service.attr_id,
            name="http-listener",
            protocol="HTTP",
            port=80,
            default_action=lattice.CfnListener.DefaultActionProperty(
                forward=lattice.CfnListener.ForwardProperty(
                    target_groups=[
                        lattice.CfnListener.WeightedTargetGroupProperty(
                            target_group_identifier=self.lattice_api_target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            )
        )

    def _configure_routing_rules(self) -> None:
        """
        Configure advanced routing rules for sophisticated traffic management.
        
        These rules demonstrate path-based, header-based, and method-based
        routing capabilities for microservices architectures.
        """
        # Path-based routing rule for API v1
        self.api_v1_rule = lattice.CfnRule(
            self, "APIv1Rule",
            service_identifier=self.lattice_service.attr_id,
            listener_identifier=self.lattice_listener.attr_id,
            name="api-v1-path-rule",
            priority=10,
            match=lattice.CfnRule.MatchProperty(
                http_match=lattice.CfnRule.HttpMatchProperty(
                    path_match=lattice.CfnRule.PathMatchProperty(
                        match=lattice.CfnRule.PathMatchTypeProperty(
                            prefix="/api/v1"
                        )
                    )
                )
            ),
            action=lattice.CfnRule.ActionProperty(
                forward=lattice.CfnRule.ForwardProperty(
                    target_groups=[
                        lattice.CfnRule.WeightedTargetGroupProperty(
                            target_group_identifier=self.lattice_api_target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            )
        )

        # Header-based routing rule for service versioning
        self.beta_header_rule = lattice.CfnRule(
            self, "BetaHeaderRule",
            service_identifier=self.lattice_service.attr_id,
            listener_identifier=self.lattice_listener.attr_id,
            name="beta-header-rule",
            priority=5,
            match=lattice.CfnRule.MatchProperty(
                http_match=lattice.CfnRule.HttpMatchProperty(
                    header_matches=[
                        lattice.CfnRule.HeaderMatchProperty(
                            name="X-Service-Version",
                            match=lattice.CfnRule.HeaderMatchTypeProperty(
                                exact="beta"
                            )
                        )
                    ]
                )
            ),
            action=lattice.CfnRule.ActionProperty(
                forward=lattice.CfnRule.ForwardProperty(
                    target_groups=[
                        lattice.CfnRule.WeightedTargetGroupProperty(
                            target_group_identifier=self.lattice_api_target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            )
        )

        # Method-based routing rule for POST requests
        self.post_method_rule = lattice.CfnRule(
            self, "PostMethodRule",
            service_identifier=self.lattice_service.attr_id,
            listener_identifier=self.lattice_listener.attr_id,
            name="post-method-rule",
            priority=15,
            match=lattice.CfnRule.MatchProperty(
                http_match=lattice.CfnRule.HttpMatchProperty(
                    method="POST"
                )
            ),
            action=lattice.CfnRule.ActionProperty(
                forward=lattice.CfnRule.ForwardProperty(
                    target_groups=[
                        lattice.CfnRule.WeightedTargetGroupProperty(
                            target_group_identifier=self.lattice_backend_target_group.attr_id,
                            weight=100
                        )
                    ]
                )
            )
        )

        # Security rule blocking admin endpoints
        self.admin_block_rule = lattice.CfnRule(
            self, "AdminBlockRule",
            service_identifier=self.lattice_service.attr_id,
            listener_identifier=self.lattice_listener.attr_id,
            name="admin-block-rule",
            priority=20,
            match=lattice.CfnRule.MatchProperty(
                http_match=lattice.CfnRule.HttpMatchProperty(
                    path_match=lattice.CfnRule.PathMatchProperty(
                        match=lattice.CfnRule.PathMatchTypeProperty(
                            exact="/admin"
                        )
                    )
                )
            ),
            action=lattice.CfnRule.ActionProperty(
                fixed_response=lattice.CfnRule.FixedResponseProperty(
                    status_code=403
                )
            )
        )

    def _configure_authentication(self) -> None:
        """
        Configure IAM authentication policies for secure service communication.
        
        Authentication policies provide fine-grained access control with
        identity-based authorization integrated with AWS security frameworks.
        """
        # Create IAM auth policy for VPC Lattice service
        auth_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:Invoke",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "aws:PrincipalAccount": self.account
                        }
                    }
                },
                {
                    "Effect": "Deny",
                    "Principal": "*",
                    "Action": "vpc-lattice-svcs:Invoke",
                    "Resource": "*",
                    "Condition": {
                        "StringEquals": {
                            "vpc-lattice-svcs:RequestPath": "/admin"
                        }
                    }
                }
            ]
        }

        # Apply auth policy to VPC Lattice service
        self.auth_policy = lattice.CfnAuthPolicy(
            self, "AuthPolicy",
            resource_identifier=self.lattice_service.attr_id,
            policy=auth_policy
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for validation and testing.
        
        These outputs provide essential information for testing the routing
        functionality and validating the deployment.
        """
        # Service network outputs
        CfnOutput(
            self, "ServiceNetworkId",
            value=self.service_network.attr_id,
            description="VPC Lattice Service Network ID",
            export_name=f"{self.stack_name}-ServiceNetworkId"
        )

        CfnOutput(
            self, "ServiceNetworkArn",
            value=self.service_network.attr_arn,
            description="VPC Lattice Service Network ARN",
            export_name=f"{self.stack_name}-ServiceNetworkArn"
        )

        # Service outputs
        CfnOutput(
            self, "LatticeServiceId",
            value=self.lattice_service.attr_id,
            description="VPC Lattice Service ID",
            export_name=f"{self.stack_name}-LatticeServiceId"
        )

        CfnOutput(
            self, "LatticeServiceArn",
            value=self.lattice_service.attr_arn,
            description="VPC Lattice Service ARN",
            export_name=f"{self.stack_name}-LatticeServiceArn"
        )

        CfnOutput(
            self, "ServiceDomainName",
            value=self.lattice_service.attr_dns_entry_domain_name,
            description="VPC Lattice Service Domain Name for testing",
            export_name=f"{self.stack_name}-ServiceDomainName"
        )

        # ALB outputs
        CfnOutput(
            self, "APIALBArn",
            value=self.api_alb.load_balancer_arn,
            description="API Service ALB ARN",
            export_name=f"{self.stack_name}-APIALBArn"
        )

        CfnOutput(
            self, "BackendALBArn",
            value=self.backend_alb.load_balancer_arn,
            description="Backend Service ALB ARN",
            export_name=f"{self.stack_name}-BackendALBArn"
        )

        # VPC outputs
        CfnOutput(
            self, "PrimaryVPCId",
            value=self.primary_vpc.vpc_id,
            description="Primary VPC ID",
            export_name=f"{self.stack_name}-PrimaryVPCId"
        )

        CfnOutput(
            self, "TargetVPCId",
            value=self.target_vpc.vpc_id,
            description="Target VPC ID",
            export_name=f"{self.stack_name}-TargetVPCId"
        )

        # Testing information
        CfnOutput(
            self, "TestingInstructions",
            value=f"Test routing with: curl http://{self.lattice_service.attr_dns_entry_domain_name}/api/v1/",
            description="Basic testing command for path-based routing",
            export_name=f"{self.stack_name}-TestingInstructions"
        )


class AdvancedRequestRoutingApp(cdk.App):
    """
    CDK Application for Advanced Request Routing with VPC Lattice and ALB.
    
    This application creates a complete demonstration of sophisticated
    microservices communication using VPC Lattice service networks.
    """

    def __init__(self):
        super().__init__()

        # Environment configuration
        env = cdk.Environment(
            account=self.node.try_get_context("account") or "123456789012",
            region=self.node.try_get_context("region") or "us-east-1"
        )

        # Create the main stack
        stack = AdvancedRequestRoutingStack(
            self, "AdvancedRequestRoutingStack",
            env=env,
            description="Advanced Request Routing with VPC Lattice and ALB demonstration"
        )

        # Apply tags to all resources
        Tags.of(stack).add("Project", "AdvancedRequestRouting")
        Tags.of(stack).add("Environment", "Demo")
        Tags.of(stack).add("CostCenter", "Engineering")
        Tags.of(stack).add("Owner", "Platform-Team")


# Application entry point
app = AdvancedRequestRoutingApp()
app.synth()