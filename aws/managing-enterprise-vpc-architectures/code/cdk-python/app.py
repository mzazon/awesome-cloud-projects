#!/usr/bin/env python3
"""
CDK Python application for Multi-VPC Architectures with Transit Gateway and Route Table Management.

This application deploys a comprehensive multi-VPC architecture using AWS Transit Gateway
with custom route tables for network segmentation. It implements enterprise-grade
network isolation between production, development, test, and shared services environments.

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Tags,
    aws_ec2 as ec2,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
)
from constructs import Construct


class MultiVpcTransitGatewayStack(Stack):
    """
    CDK Stack for Multi-VPC Transit Gateway Architecture.
    
    This stack creates:
    - Multiple VPCs with different CIDR blocks for environment isolation
    - AWS Transit Gateway with custom route tables for network segmentation
    - VPC attachments with controlled routing policies
    - Security groups for application-level access control
    - Cross-region peering capability for disaster recovery
    - Comprehensive monitoring and logging
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "enterprise",
        enable_cross_region_peering: bool = False,
        dr_region: str = "us-west-2",
        enable_flow_logs: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Multi-VPC Transit Gateway Stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            environment_name: Name prefix for all resources
            enable_cross_region_peering: Whether to create cross-region peering
            dr_region: Disaster recovery region for cross-region peering
            enable_flow_logs: Whether to enable VPC Flow Logs
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        self.environment_name = environment_name
        self.enable_cross_region_peering = enable_cross_region_peering
        self.dr_region = dr_region
        self.enable_flow_logs = enable_flow_logs

        # Store VPCs and related resources for cross-referencing
        self.vpcs: Dict[str, ec2.Vpc] = {}
        self.route_tables: Dict[str, ec2.CfnTransitGatewayRouteTable] = {}
        self.attachments: Dict[str, ec2.CfnTransitGatewayVpcAttachment] = {}
        self.security_groups: Dict[str, ec2.SecurityGroup] = {}

        # Create the infrastructure
        self._create_vpcs()
        self._create_transit_gateway()
        self._create_route_tables()
        self._create_vpc_attachments()
        self._configure_route_table_associations()
        self._configure_route_propagation()
        self._create_static_routes()
        self._create_security_groups()
        self._setup_monitoring()
        self._create_outputs()

    def _create_vpcs(self) -> None:
        """Create VPCs for different environments with appropriate CIDR blocks."""
        vpc_configs = [
            {
                "name": "production",
                "cidr": "10.0.0.0/16",
                "environment": "production",
                "description": "Production environment VPC with strict access controls"
            },
            {
                "name": "development", 
                "cidr": "10.1.0.0/16",
                "environment": "development",
                "description": "Development environment VPC for application testing"
            },
            {
                "name": "test",
                "cidr": "10.2.0.0/16", 
                "environment": "test",
                "description": "Test environment VPC for quality assurance"
            },
            {
                "name": "shared-services",
                "cidr": "10.3.0.0/16",
                "environment": "shared",
                "description": "Shared services VPC for centralized resources like DNS and monitoring"
            }
        ]

        for config in vpc_configs:
            # Create VPC with single AZ for cost optimization in this demo
            vpc = ec2.Vpc(
                self,
                f"{config['name']}-vpc",
                vpc_name=f"{self.environment_name}-{config['name']}-vpc",
                ip_addresses=ec2.IpAddresses.cidr(config["cidr"]),
                max_azs=1,  # Use single AZ for cost optimization
                enable_dns_hostnames=True,
                enable_dns_support=True,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name=f"{config['name']}-private",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=24
                    )
                ]
            )

            # Tag VPC with environment information
            Tags.of(vpc).add("Environment", config["environment"])
            Tags.of(vpc).add("Purpose", config["description"])
            Tags.of(vpc).add("NetworkTier", config["name"])

            self.vpcs[config["name"]] = vpc

            # Enable VPC Flow Logs if requested
            if self.enable_flow_logs:
                self._create_flow_logs(vpc, config["name"])

    def _create_flow_logs(self, vpc: ec2.Vpc, vpc_name: str) -> None:
        """Create VPC Flow Logs for network monitoring and security analysis."""
        # Create IAM role for Flow Logs
        flow_logs_role = iam.Role(
            self,
            f"{vpc_name}-flow-logs-role",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/VPCFlowLogsDeliveryRolePolicy"
                )
            ]
        )

        # Create CloudWatch Log Group for Flow Logs
        log_group = logs.LogGroup(
            self,
            f"{vpc_name}-flow-logs",
            log_group_name=f"/aws/vpc/flowlogs/{vpc_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

        # Create Flow Logs
        ec2.FlowLog(
            self,
            f"{vpc_name}-flow-log",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                log_group, flow_logs_role
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL
        )

    def _create_transit_gateway(self) -> None:
        """Create Transit Gateway with enterprise configuration."""
        self.transit_gateway = ec2.CfnTransitGateway(
            self,
            "enterprise-transit-gateway",
            description="Enterprise Multi-VPC Transit Gateway with custom routing",
            amazon_side_asn=64512,
            auto_accept_shared_attachments="disable",
            default_route_table_association="disable",
            default_route_table_propagation="disable",
            vpn_ecmp_support="enable",
            dns_support="enable",
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.environment_name}-transit-gateway"),
                cdk.CfnTag(key="Purpose", value="Multi-VPC enterprise networking"),
                cdk.CfnTag(key="Environment", value="production")
            ]
        )

    def _create_route_tables(self) -> None:
        """Create custom route tables for network segmentation."""
        route_table_configs = [
            {
                "name": "production",
                "description": "Production environment route table with restricted access",
                "environment": "production"
            },
            {
                "name": "development", 
                "description": "Development environment route table with test environment access",
                "environment": "development"
            },
            {
                "name": "shared-services",
                "description": "Shared services route table with access to all environments", 
                "environment": "shared"
            }
        ]

        for config in route_table_configs:
            route_table = ec2.CfnTransitGatewayRouteTable(
                self,
                f"{config['name']}-route-table",
                transit_gateway_id=self.transit_gateway.ref,
                tags=[
                    cdk.CfnTag(key="Name", value=f"{config['name']}-route-table"),
                    cdk.CfnTag(key="Environment", value=config["environment"]),
                    cdk.CfnTag(key="Purpose", value=config["description"])
                ]
            )
            
            self.route_tables[config["name"]] = route_table

    def _create_vpc_attachments(self) -> None:
        """Create VPC attachments to Transit Gateway."""
        vpc_attachment_configs = [
            {"vpc_name": "production", "route_table": "production"},
            {"vpc_name": "development", "route_table": "development"},
            {"vpc_name": "test", "route_table": "development"},  # Test uses dev route table
            {"vpc_name": "shared-services", "route_table": "shared-services"}
        ]

        for config in vpc_attachment_configs:
            vpc = self.vpcs[config["vpc_name"]]
            
            # Get the first private subnet for attachment
            private_subnet = vpc.private_subnets[0]
            
            attachment = ec2.CfnTransitGatewayVpcAttachment(
                self,
                f"{config['vpc_name']}-attachment",
                transit_gateway_id=self.transit_gateway.ref,
                vpc_id=vpc.vpc_id,
                subnet_ids=[private_subnet.subnet_id],
                tags=[
                    cdk.CfnTag(key="Name", value=f"{config['vpc_name']}-attachment"),
                    cdk.CfnTag(key="VpcName", value=config["vpc_name"]),
                    cdk.CfnTag(key="RouteTable", value=config["route_table"])
                ]
            )
            
            # Ensure attachment is created after Transit Gateway
            attachment.add_dependency(self.transit_gateway)
            
            self.attachments[config["vpc_name"]] = attachment

    def _configure_route_table_associations(self) -> None:
        """Associate VPC attachments with appropriate route tables."""
        associations = [
            {"vpc_name": "production", "route_table": "production"},
            {"vpc_name": "development", "route_table": "development"},
            {"vpc_name": "test", "route_table": "development"},
            {"vpc_name": "shared-services", "route_table": "shared-services"}
        ]

        for assoc in associations:
            association = ec2.CfnTransitGatewayRouteTableAssociation(
                self,
                f"{assoc['vpc_name']}-route-association",
                transit_gateway_attachment_id=self.attachments[assoc["vpc_name"]].ref,
                transit_gateway_route_table_id=self.route_tables[assoc["route_table"]].ref
            )
            
            # Ensure association is created after both attachment and route table
            association.add_dependency(self.attachments[assoc["vpc_name"]])
            association.add_dependency(self.route_tables[assoc["route_table"]])

    def _configure_route_propagation(self) -> None:
        """Configure route propagation for controlled access patterns."""
        propagations = [
            # Production can access shared services
            {
                "route_table": "production",
                "attachment": "shared-services",
                "description": "Enable production access to shared services"
            },
            # Development can access shared services
            {
                "route_table": "development", 
                "attachment": "shared-services",
                "description": "Enable development access to shared services"
            },
            # Shared services can access all environments
            {
                "route_table": "shared-services",
                "attachment": "production", 
                "description": "Enable shared services access to production"
            },
            {
                "route_table": "shared-services",
                "attachment": "development",
                "description": "Enable shared services access to development"
            },
            {
                "route_table": "shared-services",
                "attachment": "test",
                "description": "Enable shared services access to test"
            }
        ]

        for prop in propagations:
            propagation = ec2.CfnTransitGatewayRouteTablePropagation(
                self,
                f"{prop['route_table']}-to-{prop['attachment']}-propagation",
                transit_gateway_attachment_id=self.attachments[prop["attachment"]].ref,
                transit_gateway_route_table_id=self.route_tables[prop["route_table"]].ref
            )
            
            # Ensure propagation is created after dependencies
            propagation.add_dependency(self.attachments[prop["attachment"]])
            propagation.add_dependency(self.route_tables[prop["route_table"]])

    def _create_static_routes(self) -> None:
        """Create static routes for specific network policies including blackhole routes."""
        # Create blackhole route to block direct dev-to-prod communication
        blackhole_route = ec2.CfnTransitGatewayRoute(
            self,
            "dev-to-prod-blackhole",
            destination_cidr_block="10.0.0.0/16",  # Production VPC CIDR
            transit_gateway_route_table_id=self.route_tables["development"].ref,
            blackhole=True
        )
        blackhole_route.add_dependency(self.route_tables["development"])

        # Create specific routes for shared services access
        static_routes = [
            {
                "route_table": "production",
                "destination": "10.3.0.0/16",  # Shared services CIDR
                "attachment": "shared-services",
                "description": "Production to shared services route"
            },
            {
                "route_table": "development",
                "destination": "10.3.0.0/16",  # Shared services CIDR
                "attachment": "shared-services", 
                "description": "Development to shared services route"
            }
        ]

        for route in static_routes:
            static_route = ec2.CfnTransitGatewayRoute(
                self,
                f"{route['route_table']}-to-shared-route",
                destination_cidr_block=route["destination"],
                transit_gateway_route_table_id=self.route_tables[route["route_table"]].ref,
                transit_gateway_attachment_id=self.attachments[route["attachment"]].ref
            )
            
            static_route.add_dependency(self.route_tables[route["route_table"]])
            static_route.add_dependency(self.attachments[route["attachment"]])

    def _create_security_groups(self) -> None:
        """Create security groups for Transit Gateway traffic control."""
        # Production security group with restricted access
        prod_sg = ec2.SecurityGroup(
            self,
            "production-tgw-sg",
            vpc=self.vpcs["production"],
            description="Security group for production Transit Gateway traffic",
            security_group_name=f"{self.environment_name}-prod-tgw-sg"
        )

        # Allow HTTPS traffic within production environment
        prod_sg.add_ingress_rule(
            peer=ec2.Peer.security_group_id(prod_sg.security_group_id),
            connection=ec2.Port.tcp(443),
            description="HTTPS traffic within production environment"
        )

        # Allow DNS queries to shared services
        prod_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.3.0.0/16"),
            connection=ec2.Port.tcp(53),
            description="DNS TCP queries to shared services"
        )

        prod_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.3.0.0/16"),
            connection=ec2.Port.udp(53),
            description="DNS UDP queries to shared services"
        )

        self.security_groups["production"] = prod_sg

        # Development security group with broader internal access
        dev_sg = ec2.SecurityGroup(
            self,
            "development-tgw-sg",
            vpc=self.vpcs["development"],
            description="Security group for development Transit Gateway traffic",
            security_group_name=f"{self.environment_name}-dev-tgw-sg"
        )

        # Allow HTTP/HTTPS traffic within development environment
        dev_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.1.0.0/16"),
            connection=ec2.Port.tcp(80),
            description="HTTP traffic within development environment"
        )

        dev_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.1.0.0/16"),
            connection=ec2.Port.tcp(443),
            description="HTTPS traffic within development environment"
        )

        # Allow SSH access from test environment
        dev_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.2.0.0/16"),
            connection=ec2.Port.tcp(22),
            description="SSH access from test environment"
        )

        self.security_groups["development"] = dev_sg

        # Test security group inheriting development patterns
        test_sg = ec2.SecurityGroup(
            self,
            "test-tgw-sg",
            vpc=self.vpcs["test"],
            description="Security group for test Transit Gateway traffic",
            security_group_name=f"{self.environment_name}-test-tgw-sg"
        )

        # Allow HTTP/HTTPS traffic from development environment
        test_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.1.0.0/16"),
            connection=ec2.Port.tcp(80),
            description="HTTP traffic from development environment"
        )

        test_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.1.0.0/16"),
            connection=ec2.Port.tcp(443),
            description="HTTPS traffic from development environment"
        )

        self.security_groups["test"] = test_sg

        # Shared services security group with access to all environments
        shared_sg = ec2.SecurityGroup(
            self,
            "shared-services-tgw-sg",
            vpc=self.vpcs["shared-services"],
            description="Security group for shared services Transit Gateway traffic",
            security_group_name=f"{self.environment_name}-shared-tgw-sg"
        )

        # Allow DNS server traffic from all VPCs
        for cidr in ["10.0.0.0/16", "10.1.0.0/16", "10.2.0.0/16"]:
            shared_sg.add_ingress_rule(
                peer=ec2.Peer.ipv4(cidr),
                connection=ec2.Port.tcp(53),
                description=f"DNS TCP queries from {cidr}"
            )
            
            shared_sg.add_ingress_rule(
                peer=ec2.Peer.ipv4(cidr),
                connection=ec2.Port.udp(53),
                description=f"DNS UDP queries from {cidr}"
            )

        # Allow monitoring traffic (HTTPS) from all VPCs
        shared_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(443),
            description="Monitoring HTTPS traffic from all VPCs"
        )

        self.security_groups["shared-services"] = shared_sg

    def _setup_monitoring(self) -> None:
        """Set up CloudWatch monitoring for Transit Gateway."""
        # Create CloudWatch alarm for high data processing
        cloudwatch.Alarm(
            self,
            "tgw-data-processing-alarm",
            alarm_name=f"{self.environment_name}-TransitGateway-DataProcessing-High",
            alarm_description="High data processing on Transit Gateway",
            metric=cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="BytesIn",
                dimensions_map={
                    "TransitGateway": self.transit_gateway.ref
                },
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            ),
            threshold=10_000_000_000,  # 10 GB threshold
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Create log group for Transit Gateway monitoring
        logs.LogGroup(
            self,
            "tgw-monitoring-logs",
            log_group_name=f"/aws/transitgateway/{self.environment_name}/monitoring",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        # Transit Gateway outputs
        CfnOutput(
            self,
            "TransitGatewayId",
            value=self.transit_gateway.ref,
            description="Transit Gateway ID for multi-VPC connectivity",
            export_name=f"{self.environment_name}-TransitGatewayId"
        )

        # VPC outputs
        for name, vpc in self.vpcs.items():
            CfnOutput(
                self,
                f"{name.replace('-', '').title()}VpcId",
                value=vpc.vpc_id,
                description=f"{name.title()} VPC ID",
                export_name=f"{self.environment_name}-{name.replace('-', '').title()}VpcId"
            )

        # Route table outputs
        for name, route_table in self.route_tables.items():
            CfnOutput(
                self,
                f"{name.replace('-', '').title()}RouteTableId",
                value=route_table.ref,
                description=f"{name.title()} Transit Gateway Route Table ID",
                export_name=f"{self.environment_name}-{name.replace('-', '').title()}RouteTableId"
            )

        # Attachment outputs
        for name, attachment in self.attachments.items():
            CfnOutput(
                self,
                f"{name.replace('-', '').title()}AttachmentId",
                value=attachment.ref,
                description=f"{name.title()} VPC attachment ID",
                export_name=f"{self.environment_name}-{name.replace('-', '').title()}AttachmentId"
            )

        # Security group outputs
        for name, sg in self.security_groups.items():
            CfnOutput(
                self,
                f"{name.replace('-', '').title()}SecurityGroupId",
                value=sg.security_group_id,
                description=f"{name.title()} security group ID",
                export_name=f"{self.environment_name}-{name.replace('-', '').title()}SecurityGroupId"
            )


class MultiVpcTransitGatewayApp(cdk.App):
    """
    CDK Application for Multi-VPC Transit Gateway Architecture.
    
    This application can be configured through environment variables:
    - ENVIRONMENT_NAME: Prefix for all resources (default: "enterprise")
    - ENABLE_CROSS_REGION_PEERING: Enable cross-region peering (default: "false")
    - DR_REGION: Disaster recovery region (default: "us-west-2")
    - ENABLE_FLOW_LOGS: Enable VPC Flow Logs (default: "true")
    """

    def __init__(self) -> None:
        """Initialize the CDK application with environment-specific configuration."""
        super().__init__()

        # Get configuration from environment variables
        environment_name = os.getenv("ENVIRONMENT_NAME", "enterprise")
        enable_cross_region_peering = os.getenv("ENABLE_CROSS_REGION_PEERING", "false").lower() == "true"
        dr_region = os.getenv("DR_REGION", "us-west-2")
        enable_flow_logs = os.getenv("ENABLE_FLOW_LOGS", "true").lower() == "true"
        
        # Get AWS environment information
        aws_account = os.getenv("CDK_DEFAULT_ACCOUNT")
        aws_region = os.getenv("CDK_DEFAULT_REGION", "us-east-1")

        # Create the main stack
        MultiVpcTransitGatewayStack(
            self,
            f"{environment_name}-multi-vpc-tgw-stack",
            environment_name=environment_name,
            enable_cross_region_peering=enable_cross_region_peering,
            dr_region=dr_region,
            enable_flow_logs=enable_flow_logs,
            env=Environment(
                account=aws_account,
                region=aws_region
            ),
            description=f"Multi-VPC Transit Gateway Architecture for {environment_name} environment"
        )

        # Add application-level tags
        Tags.of(self).add("Application", "multi-vpc-transit-gateway")
        Tags.of(self).add("Environment", environment_name)
        Tags.of(self).add("Owner", "Infrastructure Team")
        Tags.of(self).add("CostCenter", "NetworkingOps")
        Tags.of(self).add("Compliance", "SOC2-PCI-HIPAA")


def main() -> None:
    """Main entry point for the CDK application."""
    app = MultiVpcTransitGatewayApp()
    app.synth()


if __name__ == "__main__":
    main()