#!/usr/bin/env python3
"""
AWS CDK Python application for network micro-segmentation with NACLs and advanced security groups.

This application implements a comprehensive micro-segmentation strategy using Network Access Control Lists (NACLs)
for subnet-level enforcement and advanced security group configurations for instance-level controls.
The architecture creates multiple security zones with layered defenses, automated traffic monitoring,
and zero-trust networking principles.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Tags,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    RemovalPolicy,
)
from constructs import Construct
from typing import Dict, List, Tuple, Optional
import json


class NetworkMicroSegmentationStack(Stack):
    """
    CDK Stack for Securing Networks with Micro-Segmentation using NACLs and Security Groupsexisting_folder_name.
    
    This stack creates:
    - VPC with multiple subnets for different security zones
    - Custom NACLs with restrictive rules for each zone
    - Security groups with layered access controls
    - VPC Flow Logs for monitoring
    - CloudWatch alarms for security monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.vpc_cidr = "10.0.0.0/16"
        self.availability_zone = f"{self.region}a"
        
        # Subnet CIDR blocks for each security zone
        self.subnet_configs = {
            "dmz": {"cidr": "10.0.1.0/24", "name": "DMZ", "public": True},
            "web": {"cidr": "10.0.2.0/24", "name": "Web", "public": False},
            "app": {"cidr": "10.0.3.0/24", "name": "App", "public": False},
            "db": {"cidr": "10.0.4.0/24", "name": "Database", "public": False},
            "mgmt": {"cidr": "10.0.5.0/24", "name": "Management", "public": False},
            "mon": {"cidr": "10.0.6.0/24", "name": "Monitoring", "public": False},
        }

        # Create VPC infrastructure
        self.vpc = self._create_vpc()
        self.internet_gateway = self._create_internet_gateway()
        self.subnets = self._create_subnets()
        self.route_tables = self._create_route_tables()
        
        # Create NACLs for subnet-level security
        self.nacls = self._create_nacls()
        self._configure_nacl_rules()
        self._associate_nacls_with_subnets()
        
        # Create security groups for instance-level security
        self.security_groups = self._create_security_groups()
        self._configure_security_group_rules()
        
        # Set up monitoring and logging
        self.flow_logs = self._create_vpc_flow_logs()
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create the main VPC for micro-segmentation."""
        vpc = ec2.Vpc(
            self,
            "MicroSegmentationVPC",
            cidr=self.vpc_cidr,
            max_azs=1,  # Single AZ for simplicity
            enable_dns_hostnames=True,
            enable_dns_support=True,
            subnet_configuration=[],  # We'll create custom subnets
        )
        
        # Add VPC tags
        Tags.of(vpc).add("Name", "microseg-vpc")
        Tags.of(vpc).add("Environment", "production")
        Tags.of(vpc).add("Purpose", "network-micro-segmentation")
        
        return vpc

    def _create_internet_gateway(self) -> ec2.CfnInternetGateway:
        """Create and attach Internet Gateway."""
        igw = ec2.CfnInternetGateway(
            self,
            "MicroSegmentationIGW",
        )
        
        # Attach IGW to VPC
        ec2.CfnVPCGatewayAttachment(
            self,
            "IGWAttachment",
            vpc_id=self.vpc.vpc_id,
            internet_gateway_id=igw.ref,
        )
        
        Tags.of(igw).add("Name", "microseg-igw")
        return igw

    def _create_subnets(self) -> Dict[str, ec2.Subnet]:
        """Create subnets for each security zone."""
        subnets = {}
        
        for zone, config in self.subnet_configs.items():
            subnet = ec2.Subnet(
                self,
                f"{config['name']}Subnet",
                vpc=self.vpc,
                cidr_block=config["cidr"],
                availability_zone=self.availability_zone,
                map_public_ip_on_launch=config["public"],
            )
            
            Tags.of(subnet).add("Name", f"{zone}-subnet")
            Tags.of(subnet).add("Zone", zone)
            Tags.of(subnet).add("Tier", config["name"])
            
            subnets[zone] = subnet
            
        return subnets

    def _create_route_tables(self) -> Dict[str, ec2.CfnRouteTable]:
        """Create route tables for each subnet."""
        route_tables = {}
        
        for zone, subnet in self.subnets.items():
            # Create route table
            route_table = ec2.CfnRouteTable(
                self,
                f"{zone.title()}RouteTable",
                vpc_id=self.vpc.vpc_id,
            )
            
            # Associate with subnet
            ec2.CfnSubnetRouteTableAssociation(
                self,
                f"{zone.title()}RouteTableAssociation",
                subnet_id=subnet.subnet_id,
                route_table_id=route_table.ref,
            )
            
            # Add internet route for DMZ subnet
            if zone == "dmz":
                ec2.CfnRoute(
                    self,
                    f"{zone.title()}InternetRoute",
                    route_table_id=route_table.ref,
                    destination_cidr_block="0.0.0.0/0",
                    gateway_id=self.internet_gateway.ref,
                )
            
            Tags.of(route_table).add("Name", f"{zone}-route-table")
            route_tables[zone] = route_table
            
        return route_tables

    def _create_nacls(self) -> Dict[str, ec2.CfnNetworkAcl]:
        """Create custom NACLs for each security zone."""
        nacls = {}
        
        for zone, config in self.subnet_configs.items():
            nacl = ec2.CfnNetworkAcl(
                self,
                f"{config['name']}NACL",
                vpc_id=self.vpc.vpc_id,
            )
            
            Tags.of(nacl).add("Name", f"{zone}-nacl")
            Tags.of(nacl).add("Zone", zone)
            
            nacls[zone] = nacl
            
        return nacls

    def _configure_nacl_rules(self) -> None:
        """Configure NACL rules for each security zone."""
        
        # DMZ NACL Rules (Internet-facing)
        self._add_nacl_rules(
            nacl_id="dmz",
            inbound_rules=[
                # Allow HTTP/HTTPS from Internet
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 80, "to": 80}, "cidr": "0.0.0.0/0", "action": "allow"},
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "0.0.0.0/0", "action": "allow"},
                # Allow ephemeral ports for return traffic
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "0.0.0.0/0", "action": "allow"},
            ],
            outbound_rules=[
                # Allow to Web Tier
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 80, "to": 80}, "cidr": "10.0.2.0/24", "action": "allow"},
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "10.0.2.0/24", "action": "allow"},
                # Allow ephemeral ports to Internet
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "0.0.0.0/0", "action": "allow"},
            ]
        )
        
        # Web Tier NACL Rules
        self._add_nacl_rules(
            nacl_id="web",
            inbound_rules=[
                # Allow from DMZ only
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 80, "to": 80}, "cidr": "10.0.1.0/24", "action": "allow"},
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "10.0.1.0/24", "action": "allow"},
                # Allow SSH from Management
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 22, "to": 22}, "cidr": "10.0.5.0/24", "action": "allow"},
                # Allow monitoring
                {"rule_number": 130, "protocol": "tcp", "port_range": {"from": 161, "to": 161}, "cidr": "10.0.6.0/24", "action": "allow"},
            ],
            outbound_rules=[
                # Allow to App Tier
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 8080, "to": 8080}, "cidr": "10.0.3.0/24", "action": "allow"},
                # Allow return traffic to DMZ
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "10.0.1.0/24", "action": "allow"},
                # Allow HTTPS to Internet for updates
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "0.0.0.0/0", "action": "allow"},
            ]
        )
        
        # App Tier NACL Rules
        self._add_nacl_rules(
            nacl_id="app",
            inbound_rules=[
                # Allow from Web Tier only
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 8080, "to": 8080}, "cidr": "10.0.2.0/24", "action": "allow"},
                # Allow SSH from Management
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 22, "to": 22}, "cidr": "10.0.5.0/24", "action": "allow"},
                # Allow monitoring
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 161, "to": 161}, "cidr": "10.0.6.0/24", "action": "allow"},
            ],
            outbound_rules=[
                # Allow to Database
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 3306, "to": 3306}, "cidr": "10.0.4.0/24", "action": "allow"},
                # Allow return traffic to Web Tier
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "10.0.2.0/24", "action": "allow"},
                # Allow HTTPS for external APIs
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "0.0.0.0/0", "action": "allow"},
            ]
        )
        
        # Database Tier NACL Rules (Most Restrictive)
        self._add_nacl_rules(
            nacl_id="db",
            inbound_rules=[
                # Allow from App Tier only
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 3306, "to": 3306}, "cidr": "10.0.3.0/24", "action": "allow"},
                # Allow SSH from Management only
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 22, "to": 22}, "cidr": "10.0.5.0/24", "action": "allow"},
                # Allow monitoring
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 161, "to": 161}, "cidr": "10.0.6.0/24", "action": "allow"},
            ],
            outbound_rules=[
                # Allow return traffic to App Tier
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "10.0.3.0/24", "action": "allow"},
                # Allow HTTPS for patches (restricted)
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "0.0.0.0/0", "action": "allow"},
            ]
        )
        
        # Management NACL Rules
        self._add_nacl_rules(
            nacl_id="mgmt",
            inbound_rules=[
                # Allow SSH from VPN/Admin networks
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 22, "to": 22}, "cidr": "10.0.0.0/8", "action": "allow"},
                # Allow HTTPS management traffic
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "10.0.0.0/8", "action": "allow"},
            ],
            outbound_rules=[
                # Allow to all internal subnets for management
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 22, "to": 22}, "cidr": "10.0.0.0/16", "action": "allow"},
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "0.0.0.0/0", "action": "allow"},
                {"rule_number": 120, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "10.0.0.0/8", "action": "allow"},
            ]
        )
        
        # Monitoring NACL Rules
        self._add_nacl_rules(
            nacl_id="mon",
            inbound_rules=[
                # Allow monitoring traffic from all zones
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 1024, "to": 65535}, "cidr": "10.0.0.0/16", "action": "allow"},
            ],
            outbound_rules=[
                # Allow monitoring queries to all zones
                {"rule_number": 100, "protocol": "tcp", "port_range": {"from": 161, "to": 161}, "cidr": "10.0.0.0/16", "action": "allow"},
                {"rule_number": 110, "protocol": "tcp", "port_range": {"from": 443, "to": 443}, "cidr": "0.0.0.0/0", "action": "allow"},
            ]
        )

    def _add_nacl_rules(self, nacl_id: str, inbound_rules: List[Dict], outbound_rules: List[Dict]) -> None:
        """Add NACL rules for inbound and outbound traffic."""
        nacl = self.nacls[nacl_id]
        
        # Add inbound rules
        for rule in inbound_rules:
            ec2.CfnNetworkAclEntry(
                self,
                f"{nacl_id.title()}InboundRule{rule['rule_number']}",
                network_acl_id=nacl.ref,
                rule_number=rule["rule_number"],
                protocol=6 if rule["protocol"] == "tcp" else 17,  # TCP = 6, UDP = 17
                port_range=ec2.CfnNetworkAclEntry.PortRangeProperty(
                    from_=rule["port_range"]["from"],
                    to=rule["port_range"]["to"]
                ),
                cidr_block=rule["cidr"],
                rule_action=rule["action"],
                egress=False,
            )
        
        # Add outbound rules
        for rule in outbound_rules:
            ec2.CfnNetworkAclEntry(
                self,
                f"{nacl_id.title()}OutboundRule{rule['rule_number']}",
                network_acl_id=nacl.ref,
                rule_number=rule["rule_number"],
                protocol=6 if rule["protocol"] == "tcp" else 17,  # TCP = 6, UDP = 17
                port_range=ec2.CfnNetworkAclEntry.PortRangeProperty(
                    from_=rule["port_range"]["from"],
                    to=rule["port_range"]["to"]
                ),
                cidr_block=rule["cidr"],
                rule_action=rule["action"],
                egress=True,
            )

    def _associate_nacls_with_subnets(self) -> None:
        """Associate each NACL with its respective subnet."""
        for zone, nacl in self.nacls.items():
            subnet = self.subnets[zone]
            
            ec2.CfnSubnetNetworkAclAssociation(
                self,
                f"{zone.title()}NACLAssociation",
                subnet_id=subnet.subnet_id,
                network_acl_id=nacl.ref,
            )

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """Create security groups for each tier."""
        security_groups = {}
        
        # DMZ Security Group (Load Balancer)
        security_groups["dmz"] = ec2.SecurityGroup(
            self,
            "DMZSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Load Balancer in DMZ",
            allow_all_outbound=False,
        )
        
        # Web Tier Security Group
        security_groups["web"] = ec2.SecurityGroup(
            self,
            "WebSecurityGroup",
            vpc=self.vpc,
            description="Security group for Web Tier instances",
            allow_all_outbound=False,
        )
        
        # App Tier Security Group
        security_groups["app"] = ec2.SecurityGroup(
            self,
            "AppSecurityGroup",
            vpc=self.vpc,
            description="Security group for Application Tier instances",
            allow_all_outbound=False,
        )
        
        # Database Security Group
        security_groups["db"] = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for Database Tier",
            allow_all_outbound=False,
        )
        
        # Management Security Group
        security_groups["mgmt"] = ec2.SecurityGroup(
            self,
            "ManagementSecurityGroup",
            vpc=self.vpc,
            description="Security group for Management resources",
            allow_all_outbound=False,
        )
        
        # Add tags
        for zone, sg in security_groups.items():
            Tags.of(sg).add("Name", f"{zone}-sg")
            Tags.of(sg).add("Zone", zone)
            
        return security_groups

    def _configure_security_group_rules(self) -> None:
        """Configure security group rules with source group references."""
        
        # DMZ Security Group Rules (ALB)
        self.security_groups["dmz"].add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from Internet"
        )
        self.security_groups["dmz"].add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from Internet"
        )
        
        # Web Tier Security Group Rules
        self.security_groups["web"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["dmz"].security_group_id),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP from DMZ"
        )
        self.security_groups["web"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["dmz"].security_group_id),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS from DMZ"
        )
        self.security_groups["web"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["mgmt"].security_group_id),
            connection=ec2.Port.tcp(22),
            description="Allow SSH from Management"
        )
        
        # Web Tier Outbound Rules
        self.security_groups["web"].add_egress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["app"].security_group_id),
            connection=ec2.Port.tcp(8080),
            description="Allow to App Tier"
        )
        self.security_groups["web"].add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS to Internet for updates"
        )
        
        # App Tier Security Group Rules
        self.security_groups["app"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["web"].security_group_id),
            connection=ec2.Port.tcp(8080),
            description="Allow from Web Tier"
        )
        self.security_groups["app"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["mgmt"].security_group_id),
            connection=ec2.Port.tcp(22),
            description="Allow SSH from Management"
        )
        
        # App Tier Outbound Rules
        self.security_groups["app"].add_egress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["db"].security_group_id),
            connection=ec2.Port.tcp(3306),
            description="Allow to Database"
        )
        self.security_groups["app"].add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS for external APIs"
        )
        
        # Database Security Group Rules (most restrictive)
        self.security_groups["db"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["app"].security_group_id),
            connection=ec2.Port.tcp(3306),
            description="Allow from App Tier only"
        )
        self.security_groups["db"].add_ingress_rule(
            peer=ec2.Peer.security_group_id(self.security_groups["mgmt"].security_group_id),
            connection=ec2.Port.tcp(22),
            description="Allow SSH from Management only"
        )
        
        # Database Outbound Rules
        self.security_groups["db"].add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS for patches"
        )
        
        # Management Security Group Rules
        self.security_groups["mgmt"].add_ingress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/8"),
            connection=ec2.Port.tcp(22),
            description="Allow SSH from VPN/Admin networks"
        )
        
        # Management Outbound Rules
        self.security_groups["mgmt"].add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS management traffic"
        )
        self.security_groups["mgmt"].add_egress_rule(
            peer=ec2.Peer.ipv4("10.0.0.0/16"),
            connection=ec2.Port.tcp(22),
            description="Allow SSH to all internal subnets"
        )

    def _create_vpc_flow_logs(self) -> logs.LogGroup:
        """Create VPC Flow Logs for traffic monitoring."""
        # Create CloudWatch Log Group for Flow Logs
        log_group = logs.LogGroup(
            self,
            "VPCFlowLogsGroup",
            log_group_name="/aws/vpc/microsegmentation/flowlogs",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create IAM role for VPC Flow Logs
        flow_logs_role = iam.Role(
            self,
            "VPCFlowLogsRole",
            assumed_by=iam.ServicePrincipal("vpc-flow-logs.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/VPCFlowLogsDeliveryRolePolicy"
                )
            ],
        )
        
        # Create VPC Flow Logs
        flow_logs = ec2.CfnFlowLog(
            self,
            "VPCFlowLogs",
            resource_type="VPC",
            resource_id=self.vpc.vpc_id,
            traffic_type="ALL",
            log_destination_type="cloud-watch-logs",
            log_group_name=log_group.log_group_name,
            deliver_logs_permission_arn=flow_logs_role.role_arn,
        )
        
        Tags.of(log_group).add("Name", "vpc-flow-logs")
        Tags.of(flow_logs_role).add("Name", "vpc-flow-logs-role")
        
        return log_group

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """Create CloudWatch alarms for suspicious traffic patterns."""
        alarms = []
        
        # Alarm for high number of rejected packets
        rejected_traffic_alarm = cloudwatch.Alarm(
            self,
            "VPCRejectedTrafficAlarm",
            alarm_name="VPC-Rejected-Traffic-High",
            alarm_description="High number of rejected packets in VPC",
            metric=cloudwatch.Metric(
                namespace="AWS/VPC",
                metric_name="PacketsDropped",
                dimensions_map={"VpcId": self.vpc.vpc_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=1000,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        alarms.append(rejected_traffic_alarm)
        
        # Alarm for unusual inbound traffic patterns
        inbound_traffic_alarm = cloudwatch.Alarm(
            self,
            "VPCInboundTrafficAlarm",
            alarm_name="VPC-Inbound-Traffic-Unusual",
            alarm_description="Unusual inbound traffic patterns detected",
            metric=cloudwatch.Metric(
                namespace="AWS/VPC",
                metric_name="PacketsReceived",
                dimensions_map={"VpcId": self.vpc.vpc_id},
                statistic="Sum",
                period=cdk.Duration.minutes(5),
            ),
            threshold=10000,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        alarms.append(inbound_traffic_alarm)
        
        return alarms

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        # VPC Output
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for micro-segmentation",
            export_name=f"{self.stack_name}-VPCId",
        )
        
        # Subnet Outputs
        for zone, subnet in self.subnets.items():
            CfnOutput(
                self,
                f"{zone.title()}SubnetId",
                value=subnet.subnet_id,
                description=f"Subnet ID for {zone} zone",
                export_name=f"{self.stack_name}-{zone.title()}SubnetId",
            )
        
        # Security Group Outputs
        for zone, sg in self.security_groups.items():
            CfnOutput(
                self,
                f"{zone.title()}SecurityGroupId",
                value=sg.security_group_id,
                description=f"Security Group ID for {zone} zone",
                export_name=f"{self.stack_name}-{zone.title()}SecurityGroupId",
            )
        
        # NACL Outputs
        for zone, nacl in self.nacls.items():
            CfnOutput(
                self,
                f"{zone.title()}NACLId",
                value=nacl.ref,
                description=f"NACL ID for {zone} zone",
                export_name=f"{self.stack_name}-{zone.title()}NACLId",
            )

    def _add_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "NetworkMicroSegmentation")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "SecurityTeam")
        Tags.of(self).add("CostCenter", "Security")
        Tags.of(self).add("Compliance", "SOC2-HIPAA-PCI")


class NetworkMicroSegmentationApp(cdk.App):
    """CDK Application for network micro-segmentation."""

    def __init__(self):
        super().__init__()
        
        # Create the main stack
        NetworkMicroSegmentationStack(
            self,
            "NetworkMicroSegmentationStack",
            description="Network micro-segmentation with NACLs and advanced security groups",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region") or "us-east-1",
            ),
        )


# Entry point for the CDK application
if __name__ == "__main__":
    app = NetworkMicroSegmentationApp()
    app.synth()