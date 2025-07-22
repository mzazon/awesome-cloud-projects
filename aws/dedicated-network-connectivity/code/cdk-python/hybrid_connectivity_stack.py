"""
Hybrid Cloud Connectivity Stack

This stack implements a complete hybrid cloud connectivity solution using:
- Multiple VPCs (Production, Development, Shared Services)
- Transit Gateway with VPC attachments
- Direct Connect Gateway
- Route 53 Resolver endpoints
- CloudWatch monitoring and alerting
- Security controls and VPC Flow Logs

Author: Recipe Generator
Version: 1.0
"""

from typing import Dict, List, Optional
from constructs import Construct
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_directconnect as directconnect,
    aws_route53resolver as route53resolver,
    aws_logs as logs,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)


class HybridConnectivityStack(Stack):
    """
    AWS CDK Stack for Hybrid Cloud Connectivity with Direct Connect
    
    This stack creates a comprehensive hybrid cloud connectivity solution
    with multiple VPCs, Transit Gateway, Direct Connect Gateway, and
    supporting infrastructure for DNS resolution and monitoring.
    """
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_id: str,
        environment_name: str,
        on_premises_asn: int,
        aws_asn: int,
        on_premises_cidr: str,
        **kwargs
    ) -> None:
        """
        Initialize the Hybrid Connectivity Stack.
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            project_id: Project identifier for resource naming
            environment_name: Environment name (production, staging, etc.)
            on_premises_asn: BGP ASN for on-premises network
            aws_asn: BGP ASN for AWS side
            on_premises_cidr: CIDR block for on-premises network
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_id = project_id
        self.environment_name = environment_name
        self.on_premises_asn = on_premises_asn
        self.aws_asn = aws_asn
        self.on_premises_cidr = on_premises_cidr
        
        # Create VPC infrastructure
        self.vpcs = self._create_vpcs()
        
        # Create Transit Gateway
        self.transit_gateway = self._create_transit_gateway()
        
        # Create VPC attachments to Transit Gateway
        self.vpc_attachments = self._create_vpc_attachments()
        
        # Create Direct Connect Gateway
        self.dx_gateway = self._create_direct_connect_gateway()
        
        # Create Transit Gateway Direct Connect attachment
        self.dx_attachment = self._create_dx_attachment()
        
        # Set up routing
        self._configure_routing()
        
        # Create Route 53 Resolver endpoints
        self.resolver_endpoints = self._create_resolver_endpoints()
        
        # Create VPC Flow Logs
        self._create_vpc_flow_logs()
        
        # Create CloudWatch monitoring
        self._create_monitoring()
        
        # Create stack outputs
        self._create_outputs()
    
    def _create_vpcs(self) -> Dict[str, ec2.Vpc]:
        """
        Create multiple VPCs for the hybrid connectivity solution.
        
        Returns:
            Dictionary of VPC names to VPC constructs
        """
        vpcs = {}
        
        # VPC configurations
        vpc_configs = {
            'production': {
                'cidr': '10.1.0.0/16',
                'description': 'Production VPC for hybrid connectivity'
            },
            'development': {
                'cidr': '10.2.0.0/16',
                'description': 'Development VPC for hybrid connectivity'
            },
            'shared-services': {
                'cidr': '10.3.0.0/16',
                'description': 'Shared Services VPC for hybrid connectivity'
            }
        }
        
        for vpc_name, config in vpc_configs.items():
            vpc = ec2.Vpc(
                self,
                f"{vpc_name.title().replace('-', '')}Vpc",
                vpc_name=f"{vpc_name}-vpc-{self.project_id}",
                ip_addresses=ec2.IpAddresses.cidr(config['cidr']),
                max_azs=2,
                subnet_configuration=[
                    ec2.SubnetConfiguration(
                        subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                        name=f"{vpc_name}-private",
                        cidr_mask=24
                    ),
                    ec2.SubnetConfiguration(
                        subnet_type=ec2.SubnetType.PUBLIC,
                        name=f"{vpc_name}-public",
                        cidr_mask=24
                    )
                ],
                enable_dns_hostnames=True,
                enable_dns_support=True,
            )
            
            # Add tags
            cdk.Tags.of(vpc).add("Name", f"{vpc_name.title()}-VPC-{self.project_id}")
            cdk.Tags.of(vpc).add("VpcType", vpc_name)
            cdk.Tags.of(vpc).add("Description", config['description'])
            
            vpcs[vpc_name] = vpc
        
        return vpcs
    
    def _create_transit_gateway(self) -> ec2.CfnTransitGateway:
        """
        Create Transit Gateway for centralized routing.
        
        Returns:
            Transit Gateway construct
        """
        transit_gateway = ec2.CfnTransitGateway(
            self,
            "TransitGateway",
            amazon_side_asn=self.aws_asn,
            description=f"Corporate hybrid connectivity gateway - {self.project_id}",
            default_route_table_association="enable",
            default_route_table_propagation="enable",
            dns_support="enable",
            vpn_ecmp_support="enable",
            multicast_support="disable",
            tags=[
                cdk.CfnTag(key="Name", value=f"corporate-tgw-{self.project_id}")
            ]
        )
        
        return transit_gateway
    
    def _create_vpc_attachments(self) -> Dict[str, ec2.CfnTransitGatewayVpcAttachment]:
        """
        Create VPC attachments to Transit Gateway.
        
        Returns:
            Dictionary of VPC attachment constructs
        """
        attachments = {}
        
        for vpc_name, vpc in self.vpcs.items():
            # Get private subnets for attachment
            private_subnets = [
                subnet for subnet in vpc.private_subnets[:1]  # Use first private subnet
            ]
            
            attachment = ec2.CfnTransitGatewayVpcAttachment(
                self,
                f"{vpc_name.title().replace('-', '')}Attachment",
                transit_gateway_id=self.transit_gateway.ref,
                vpc_id=vpc.vpc_id,
                subnet_ids=[subnet.subnet_id for subnet in private_subnets],
                tags=[
                    cdk.CfnTag(key="Name", value=f"{vpc_name.title()}-TGW-Attachment")
                ]
            )
            
            attachments[vpc_name] = attachment
        
        return attachments
    
    def _create_direct_connect_gateway(self) -> directconnect.CfnDirectConnectGateway:
        """
        Create Direct Connect Gateway.
        
        Returns:
            Direct Connect Gateway construct
        """
        dx_gateway = directconnect.CfnDirectConnectGateway(
            self,
            "DirectConnectGateway",
            name=f"corporate-dx-gateway-{self.project_id}",
            amazon_side_asn=self.aws_asn
        )
        
        return dx_gateway
    
    def _create_dx_attachment(self) -> ec2.CfnTransitGatewayDirectConnectGatewayAttachment:
        """
        Create Transit Gateway Direct Connect Gateway attachment.
        
        Returns:
            Transit Gateway Direct Connect Gateway attachment
        """
        dx_attachment = ec2.CfnTransitGatewayDirectConnectGatewayAttachment(
            self,
            "DxTgwAttachment",
            transit_gateway_id=self.transit_gateway.ref,
            direct_connect_gateway_id=self.dx_gateway.ref,
            tags=[
                cdk.CfnTag(key="Name", value=f"DX-TGW-Attachment-{self.project_id}")
            ]
        )
        
        return dx_attachment
    
    def _configure_routing(self) -> None:
        """
        Configure routing between VPCs and on-premises networks.
        """
        # Add routes to on-premises networks in each VPC
        for vpc_name, vpc in self.vpcs.items():
            # Add route to on-premises CIDR via Transit Gateway
            for subnet in vpc.private_subnets:
                ec2.CfnRoute(
                    self,
                    f"{vpc_name.title().replace('-', '')}OnPremRoute{subnet.node.id}",
                    route_table_id=subnet.route_table.route_table_id,
                    destination_cidr_block=self.on_premises_cidr,
                    transit_gateway_id=self.transit_gateway.ref
                )
    
    def _create_resolver_endpoints(self) -> Dict[str, route53resolver.CfnResolverEndpoint]:
        """
        Create Route 53 Resolver endpoints for DNS resolution.
        
        Returns:
            Dictionary of resolver endpoint constructs
        """
        endpoints = {}
        
        # Create security group for resolver endpoints
        resolver_sg = ec2.SecurityGroup(
            self,
            "ResolverSecurityGroup",
            vpc=self.vpcs['shared-services'],
            description="Security group for Route 53 Resolver endpoints",
            allow_all_outbound=True
        )
        
        # Allow DNS traffic from on-premises
        resolver_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.on_premises_cidr),
            connection=ec2.Port.udp(53),
            description="Allow DNS UDP from on-premises"
        )
        
        resolver_sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.on_premises_cidr),
            connection=ec2.Port.tcp(53),
            description="Allow DNS TCP from on-premises"
        )
        
        # Allow DNS traffic from VPCs
        for vpc_name, vpc in self.vpcs.items():
            resolver_sg.add_ingress_rule(
                peer=ec2.Peer.ipv4(vpc.vpc_cidr_block),
                connection=ec2.Port.udp(53),
                description=f"Allow DNS UDP from {vpc_name} VPC"
            )
        
        # Create inbound resolver endpoint
        shared_vpc = self.vpcs['shared-services']
        private_subnet = shared_vpc.private_subnets[0]
        
        inbound_endpoint = route53resolver.CfnResolverEndpoint(
            self,
            "InboundResolverEndpoint",
            direction="INBOUND",
            ip_addresses=[
                route53resolver.CfnResolverEndpoint.IpAddressRequestProperty(
                    subnet_id=private_subnet.subnet_id,
                    ip="10.3.1.100"
                )
            ],
            security_group_ids=[resolver_sg.security_group_id],
            name=f"Inbound-Resolver-{self.project_id}"
        )
        
        # Create outbound resolver endpoint
        outbound_endpoint = route53resolver.CfnResolverEndpoint(
            self,
            "OutboundResolverEndpoint",
            direction="OUTBOUND",
            ip_addresses=[
                route53resolver.CfnResolverEndpoint.IpAddressRequestProperty(
                    subnet_id=private_subnet.subnet_id,
                    ip="10.3.1.101"
                )
            ],
            security_group_ids=[resolver_sg.security_group_id],
            name=f"Outbound-Resolver-{self.project_id}"
        )
        
        endpoints['inbound'] = inbound_endpoint
        endpoints['outbound'] = outbound_endpoint
        
        return endpoints
    
    def _create_vpc_flow_logs(self) -> None:
        """
        Create VPC Flow Logs for all VPCs.
        """
        # Create CloudWatch log group for VPC Flow Logs
        flow_log_group = logs.LogGroup(
            self,
            "VpcFlowLogsGroup",
            log_group_name=f"/aws/vpc/flowlogs-{self.project_id}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY
        )
        
        # Create IAM role for VPC Flow Logs
        flow_logs_role = iam.Role(
            self,
            "VpcFlowLogsRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            inline_policies={
                "FlowLogsDeliveryRolePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        # Create VPC Flow Logs for each VPC
        for vpc_name, vpc in self.vpcs.items():
            ec2.CfnFlowLog(
                self,
                f"{vpc_name.title().replace('-', '')}FlowLog",
                resource_type="VPC",
                resource_id=vpc.vpc_id,
                traffic_type="ALL",
                log_destination_type="cloud-watch-logs",
                log_group_name=flow_log_group.log_group_name,
                deliver_logs_permission_arn=flow_logs_role.role_arn
            )
    
    def _create_monitoring(self) -> None:
        """
        Create CloudWatch monitoring and alerting.
        """
        # Create SNS topic for alerts
        alert_topic = sns.Topic(
            self,
            "DirectConnectAlerts",
            display_name=f"Direct Connect Alerts - {self.project_id}",
            topic_name=f"dx-alerts-{self.project_id}"
        )
        
        # Create CloudWatch Dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "DirectConnectDashboard",
            dashboard_name=f"DirectConnect-{self.project_id}",
            period_override=cloudwatch.PeriodOverride.INHERIT,
            start="P1D",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Direct Connect Connection State",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/DX",
                                metric_name="ConnectionState",
                                dimensions_map={
                                    "ConnectionId": "CONNECTION_ID_PLACEHOLDER"
                                },
                                statistic="Maximum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Direct Connect Bandwidth",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/DX",
                                metric_name="ConnectionBpsEgress",
                                dimensions_map={
                                    "ConnectionId": "CONNECTION_ID_PLACEHOLDER"
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/DX",
                                metric_name="ConnectionBpsIngress",
                                dimensions_map={
                                    "ConnectionId": "CONNECTION_ID_PLACEHOLDER"
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )
        
        # Create CloudWatch Alarm for connection state
        # Note: This alarm would need to be configured with actual connection ID
        # after the physical Direct Connect connection is established
        
    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resources.
        """
        # VPC outputs
        for vpc_name, vpc in self.vpcs.items():
            CfnOutput(
                self,
                f"{vpc_name.title().replace('-', '')}VpcId",
                value=vpc.vpc_id,
                description=f"ID of the {vpc_name} VPC",
                export_name=f"{self.stack_name}-{vpc_name.replace('-', '')}-vpc-id"
            )
        
        # Transit Gateway outputs
        CfnOutput(
            self,
            "TransitGatewayId",
            value=self.transit_gateway.ref,
            description="ID of the Transit Gateway",
            export_name=f"{self.stack_name}-transit-gateway-id"
        )
        
        # Direct Connect Gateway outputs
        CfnOutput(
            self,
            "DirectConnectGatewayId",
            value=self.dx_gateway.ref,
            description="ID of the Direct Connect Gateway",
            export_name=f"{self.stack_name}-dx-gateway-id"
        )
        
        # Resolver endpoints outputs
        CfnOutput(
            self,
            "InboundResolverEndpointId",
            value=self.resolver_endpoints['inbound'].ref,
            description="ID of the inbound Route 53 Resolver endpoint",
            export_name=f"{self.stack_name}-inbound-resolver-id"
        )
        
        CfnOutput(
            self,
            "OutboundResolverEndpointId",
            value=self.resolver_endpoints['outbound'].ref,
            description="ID of the outbound Route 53 Resolver endpoint",
            export_name=f"{self.stack_name}-outbound-resolver-id"
        )
        
        # Configuration outputs
        CfnOutput(
            self,
            "OnPremisesCidr",
            value=self.on_premises_cidr,
            description="CIDR block for on-premises network"
        )
        
        CfnOutput(
            self,
            "OnPremisesAsn",
            value=str(self.on_premises_asn),
            description="BGP ASN for on-premises network"
        )
        
        CfnOutput(
            self,
            "AwsAsn",
            value=str(self.aws_asn),
            description="BGP ASN for AWS side"
        )
        
        # DNS server IP addresses
        CfnOutput(
            self,
            "InboundDnsServerIp",
            value="10.3.1.100",
            description="IP address of inbound DNS resolver endpoint"
        )
        
        CfnOutput(
            self,
            "OutboundDnsServerIp",
            value="10.3.1.101",
            description="IP address of outbound DNS resolver endpoint"
        )
        
        # BGP configuration template
        CfnOutput(
            self,
            "BgpConfigurationNote",
            value="See README.md for BGP configuration template and virtual interface setup instructions",
            description="BGP configuration instructions"
        )