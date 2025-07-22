#!/usr/bin/env python3
"""
AWS CDK Python application for Multi-Region VPC Connectivity with Transit Gateway.

This application creates a multi-region network architecture using AWS Transit Gateway
with cross-region peering to establish scalable hub-and-spoke connectivity.

Features:
- Transit Gateways in multiple regions (us-east-1 and us-west-2)
- VPCs with non-overlapping CIDR blocks
- Cross-region peering attachments
- Custom route tables for controlled routing
- Security groups for cross-region access
- CloudWatch monitoring dashboard
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    aws_ec2 as ec2,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam
)
from constructs import Construct
from typing import Dict, List, Optional


class MultiRegionVpcConnectivityStack(Stack):
    """
    Main stack for multi-region VPC connectivity using Transit Gateway.
    
    This stack creates the complete infrastructure for establishing secure,
    scalable connectivity between VPCs across multiple AWS regions.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        region_config: Dict[str, str],
        vpc_cidrs: Dict[str, str],
        **kwargs
    ) -> None:
        """
        Initialize the multi-region VPC connectivity stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            region_config: Dictionary containing region configuration
            vpc_cidrs: Dictionary containing VPC CIDR blocks
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.region_config = region_config
        self.vpc_cidrs = vpc_cidrs
        self.current_region = self.region
        
        # Create VPCs
        self.vpcs = self._create_vpcs()
        
        # Create Transit Gateway
        self.transit_gateway = self._create_transit_gateway()
        
        # Create VPC attachments
        self.vpc_attachments = self._create_vpc_attachments()
        
        # Create custom route table
        self.route_table = self._create_custom_route_table()
        
        # Associate attachments with route table
        self._create_route_table_associations()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create outputs
        self._create_outputs()

    def _create_vpcs(self) -> Dict[str, ec2.Vpc]:
        """
        Create VPCs in the current region with appropriate CIDR blocks.
        
        Returns:
            Dictionary of VPC constructs keyed by VPC name
        """
        vpcs = {}
        
        if self.current_region == self.region_config['primary']:
            # Create VPCs in primary region
            vpcs['primary_a'] = ec2.Vpc(
                self, "PrimaryVpcA",
                ip_addresses=ec2.IpAddresses.cidr(self.vpc_cidrs['primary_a']),
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=24
                    )
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True
            )
            
            vpcs['primary_b'] = ec2.Vpc(
                self, "PrimaryVpcB",
                ip_addresses=ec2.IpAddresses.cidr(self.vpc_cidrs['primary_b']),
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=24
                    )
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True
            )
            
        elif self.current_region == self.region_config['secondary']:
            # Create VPCs in secondary region
            vpcs['secondary_a'] = ec2.Vpc(
                self, "SecondaryVpcA",
                ip_addresses=ec2.IpAddresses.cidr(self.vpc_cidrs['secondary_a']),
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=24
                    )
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True
            )
            
            vpcs['secondary_b'] = ec2.Vpc(
                self, "SecondaryVpcB",
                ip_addresses=ec2.IpAddresses.cidr(self.vpc_cidrs['secondary_b']),
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        name="Private",
                        subnet_type=ec2.SubnetType.PRIVATE_ISOLATED,
                        cidr_mask=24
                    )
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True
            )
        
        # Tag VPCs for identification
        for vpc_name, vpc in vpcs.items():
            cdk.Tags.of(vpc).add("Name", f"multi-region-tgw-{vpc_name}")
            cdk.Tags.of(vpc).add("Purpose", "TransitGatewayConnectivity")
        
        return vpcs

    def _create_transit_gateway(self) -> ec2.CfnTransitGateway:
        """
        Create Transit Gateway with appropriate configuration.
        
        Returns:
            Transit Gateway construct
        """
        # Set ASN based on region
        asn = 64512 if self.current_region == self.region_config['primary'] else 64513
        
        transit_gateway = ec2.CfnTransitGateway(
            self, "TransitGateway",
            amazon_side_asn=asn,
            description=f"Transit Gateway for multi-region connectivity in {self.current_region}",
            default_route_table_association="enable",
            default_route_table_propagation="enable",
            tags=[
                cdk.CfnTag(key="Name", value=f"multi-region-tgw-{self.current_region}"),
                cdk.CfnTag(key="Purpose", value="MultiRegionConnectivity")
            ]
        )
        
        return transit_gateway

    def _create_vpc_attachments(self) -> Dict[str, ec2.CfnTransitGatewayAttachment]:
        """
        Create VPC attachments to Transit Gateway.
        
        Returns:
            Dictionary of VPC attachment constructs
        """
        attachments = {}
        
        for vpc_name, vpc in self.vpcs.items():
            # Get first private subnet for attachment
            subnet_id = vpc.isolated_subnets[0].subnet_id
            
            attachment = ec2.CfnTransitGatewayAttachment(
                self, f"TgwAttachment{vpc_name.title()}",
                transit_gateway_id=self.transit_gateway.ref,
                vpc_id=vpc.vpc_id,
                subnet_ids=[subnet_id],
                tags=[
                    cdk.CfnTag(key="Name", value=f"attachment-{vpc_name}"),
                    cdk.CfnTag(key="Purpose", value="VpcConnectivity")
                ]
            )
            
            attachments[vpc_name] = attachment
        
        return attachments

    def _create_custom_route_table(self) -> ec2.CfnTransitGatewayRouteTable:
        """
        Create custom route table for controlled routing.
        
        Returns:
            Transit Gateway route table construct
        """
        route_table = ec2.CfnTransitGatewayRouteTable(
            self, "CustomRouteTable",
            transit_gateway_id=self.transit_gateway.ref,
            tags=[
                cdk.CfnTag(key="Name", value=f"custom-rt-{self.current_region}"),
                cdk.CfnTag(key="Purpose", value="CustomRouting")
            ]
        )
        
        return route_table

    def _create_route_table_associations(self) -> None:
        """
        Associate VPC attachments with custom route table.
        """
        for vpc_name, attachment in self.vpc_attachments.items():
            ec2.CfnTransitGatewayRouteTableAssociation(
                self, f"RouteTableAssociation{vpc_name.title()}",
                transit_gateway_attachment_id=attachment.ref,
                transit_gateway_route_table_id=self.route_table.ref
            )

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for cross-region access testing.
        
        Returns:
            Dictionary of security group constructs
        """
        security_groups = {}
        
        for vpc_name, vpc in self.vpcs.items():
            sg = ec2.SecurityGroup(
                self, f"SecurityGroup{vpc_name.title()}",
                vpc=vpc,
                description=f"Security group for cross-region connectivity testing in {vpc_name}",
                allow_all_outbound=True
            )
            
            # Add ICMP ingress rules for testing (restrictive for demo purposes)
            if self.current_region == self.region_config['primary']:
                # Allow ICMP from secondary region VPCs
                sg.add_ingress_rule(
                    peer=ec2.Peer.ipv4(self.vpc_cidrs['secondary_a']),
                    connection=ec2.Port.all_icmp(),
                    description="Allow ICMP from secondary region VPC A"
                )
                sg.add_ingress_rule(
                    peer=ec2.Peer.ipv4(self.vpc_cidrs['secondary_b']),
                    connection=ec2.Port.all_icmp(),
                    description="Allow ICMP from secondary region VPC B"
                )
            
            elif self.current_region == self.region_config['secondary']:
                # Allow ICMP from primary region VPCs
                sg.add_ingress_rule(
                    peer=ec2.Peer.ipv4(self.vpc_cidrs['primary_a']),
                    connection=ec2.Port.all_icmp(),
                    description="Allow ICMP from primary region VPC A"
                )
                sg.add_ingress_rule(
                    peer=ec2.Peer.ipv4(self.vpc_cidrs['primary_b']),
                    connection=ec2.Port.all_icmp(),
                    description="Allow ICMP from primary region VPC B"
                )
            
            cdk.Tags.of(sg).add("Name", f"sg-{vpc_name}-cross-region")
            security_groups[vpc_name] = sg
        
        return security_groups

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        # Transit Gateway outputs
        CfnOutput(
            self, "TransitGatewayId",
            value=self.transit_gateway.ref,
            description=f"Transit Gateway ID in {self.current_region}"
        )
        
        # Route table outputs
        CfnOutput(
            self, "CustomRouteTableId",
            value=self.route_table.ref,
            description=f"Custom route table ID in {self.current_region}"
        )
        
        # VPC outputs
        for vpc_name, vpc in self.vpcs.items():
            CfnOutput(
                self, f"VpcId{vpc_name.title()}",
                value=vpc.vpc_id,
                description=f"VPC ID for {vpc_name}"
            )
        
        # Attachment outputs
        for vpc_name, attachment in self.vpc_attachments.items():
            CfnOutput(
                self, f"AttachmentId{vpc_name.title()}",
                value=attachment.ref,
                description=f"Transit Gateway attachment ID for {vpc_name}"
            )


class CrossRegionPeeringStack(Stack):
    """
    Stack for creating cross-region Transit Gateway peering.
    
    This stack should be deployed after both regional stacks to establish
    the peering connection between Transit Gateways.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        primary_tgw_id: str,
        secondary_tgw_id: str,
        region_config: Dict[str, str],
        vpc_cidrs: Dict[str, str],
        **kwargs
    ) -> None:
        """
        Initialize the cross-region peering stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            primary_tgw_id: Transit Gateway ID in primary region
            secondary_tgw_id: Transit Gateway ID in secondary region
            region_config: Dictionary containing region configuration
            vpc_cidrs: Dictionary containing VPC CIDR blocks
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.primary_tgw_id = primary_tgw_id
        self.secondary_tgw_id = secondary_tgw_id
        self.region_config = region_config
        self.vpc_cidrs = vpc_cidrs
        
        # Create peering attachment
        self.peering_attachment = self._create_peering_attachment()
        
        # Create outputs
        self._create_outputs()

    def _create_peering_attachment(self) -> ec2.CfnTransitGatewayPeeringAttachment:
        """
        Create Transit Gateway peering attachment between regions.
        
        Returns:
            Transit Gateway peering attachment construct
        """
        # Get account ID from context
        account_id = self.account
        
        peering_attachment = ec2.CfnTransitGatewayPeeringAttachment(
            self, "CrossRegionPeering",
            transit_gateway_id=self.primary_tgw_id,
            peer_transit_gateway_id=self.secondary_tgw_id,
            peer_account_id=account_id,
            peer_region=self.region_config['secondary'],
            tags=[
                cdk.CfnTag(key="Name", value="cross-region-peering"),
                cdk.CfnTag(key="Purpose", value="CrossRegionConnectivity")
            ]
        )
        
        return peering_attachment

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for peering attachment information.
        """
        CfnOutput(
            self, "PeeringAttachmentId",
            value=self.peering_attachment.ref,
            description="Cross-region Transit Gateway peering attachment ID"
        )


class MonitoringStack(Stack):
    """
    Stack for creating CloudWatch monitoring dashboard.
    
    This stack creates monitoring and observability resources for
    the multi-region Transit Gateway infrastructure.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        primary_tgw_id: str,
        secondary_tgw_id: str,
        region_config: Dict[str, str],
        **kwargs
    ) -> None:
        """
        Initialize the monitoring stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            primary_tgw_id: Transit Gateway ID in primary region
            secondary_tgw_id: Transit Gateway ID in secondary region
            region_config: Dictionary containing region configuration
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.primary_tgw_id = primary_tgw_id
        self.secondary_tgw_id = secondary_tgw_id
        self.region_config = region_config
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_dashboard()

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for Transit Gateway monitoring.
        
        Returns:
            CloudWatch dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self, "TransitGatewayDashboard",
            dashboard_name="multi-region-tgw-monitoring"
        )
        
        # Primary Transit Gateway metrics
        primary_metrics = [
            cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="BytesIn",
                dimensions_map={"TransitGateway": self.primary_tgw_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            ),
            cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="BytesOut",
                dimensions_map={"TransitGateway": self.primary_tgw_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            ),
            cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="PacketDropCount",
                dimensions_map={"TransitGateway": self.primary_tgw_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            )
        ]
        
        # Secondary Transit Gateway metrics
        secondary_metrics = [
            cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="BytesIn",
                dimensions_map={"TransitGateway": self.secondary_tgw_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            ),
            cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="BytesOut",
                dimensions_map={"TransitGateway": self.secondary_tgw_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            ),
            cloudwatch.Metric(
                namespace="AWS/TransitGateway",
                metric_name="PacketDropCount",
                dimensions_map={"TransitGateway": self.secondary_tgw_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5)
            )
        ]
        
        # Add widgets to dashboard
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Primary Transit Gateway Metrics",
                left=primary_metrics,
                width=12,
                height=6
            ),
            cloudwatch.GraphWidget(
                title="Secondary Transit Gateway Metrics",
                left=secondary_metrics,
                width=12,
                height=6
            )
        )
        
        return dashboard


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    
    This function defines the application configuration and creates
    all necessary stacks for the multi-region VPC connectivity solution.
    """
    app = cdk.App()
    
    # Configuration
    region_config = {
        'primary': 'us-east-1',
        'secondary': 'us-west-2'
    }
    
    vpc_cidrs = {
        'primary_a': '10.1.0.0/16',
        'primary_b': '10.2.0.0/16',
        'secondary_a': '10.3.0.0/16',
        'secondary_b': '10.4.0.0/16'
    }
    
    # Get account ID from context
    account_id = app.node.try_get_context("account_id") or "123456789012"
    
    # Primary region stack
    primary_stack = MultiRegionVpcConnectivityStack(
        app, "MultiRegionVpcConnectivityPrimary",
        region_config=region_config,
        vpc_cidrs=vpc_cidrs,
        env=Environment(
            account=account_id,
            region=region_config['primary']
        )
    )
    
    # Secondary region stack
    secondary_stack = MultiRegionVpcConnectivityStack(
        app, "MultiRegionVpcConnectivitySecondary",
        region_config=region_config,
        vpc_cidrs=vpc_cidrs,
        env=Environment(
            account=account_id,
            region=region_config['secondary']
        )
    )
    
    # Note: Cross-region peering and monitoring stacks would need to be deployed
    # separately after the regional stacks, or use cross-stack references
    # with explicit dependencies
    
    # Add stack dependencies
    secondary_stack.add_dependency(primary_stack)
    
    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()