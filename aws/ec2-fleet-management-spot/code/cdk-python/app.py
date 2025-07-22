#!/usr/bin/env python3
"""
CDK Application for EC2 Fleet Management with Spot Instances

This application deploys a complete EC2 Fleet management solution that combines
Spot Fleet and On-Demand instances to achieve cost optimization while maintaining
high availability across multiple Availability Zones.

Key Features:
- Mixed instance types (t3.micro, t3.small, t3.nano)
- Intelligent allocation strategies (capacity-optimized for Spot, diversified for On-Demand)
- Automatic capacity rebalancing and health monitoring
- CloudWatch monitoring and alerting
- Cost optimization through Spot/On-Demand mix
"""

import os
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    Duration,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    Tags,
)
from constructs import Construct
from typing import List, Dict, Any


class EC2FleetManagementStack(Stack):
    """
    CDK Stack for EC2 Fleet Management with Spot Instances
    
    This stack creates:
    - VPC with public subnets across multiple AZs
    - Security groups for fleet instances
    - EC2 key pair for instance access
    - Launch template with mixed instance types
    - EC2 Fleet with Spot/On-Demand mix
    - Spot Fleet for comparison
    - IAM roles and policies
    - CloudWatch monitoring dashboard
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create VPC with public subnets in multiple AZs
        self.vpc = self._create_vpc()
        
        # Create security group for fleet instances
        self.security_group = self._create_security_group()
        
        # Create key pair for instance access
        self.key_pair = self._create_key_pair(unique_suffix)
        
        # Get latest Amazon Linux 2 AMI
        self.ami = self._get_latest_ami()
        
        # Create launch template for fleet instances
        self.launch_template = self._create_launch_template(unique_suffix)
        
        # Create IAM role for Spot Fleet
        self.spot_fleet_role = self._create_spot_fleet_role(unique_suffix)
        
        # Create EC2 Fleet with mixed instances
        self.ec2_fleet = self._create_ec2_fleet(unique_suffix)
        
        # Create Spot Fleet for comparison
        self.spot_fleet = self._create_spot_fleet(unique_suffix)
        
        # Create CloudWatch monitoring dashboard
        self.dashboard = self._create_monitoring_dashboard(unique_suffix)
        
        # Create outputs
        self._create_outputs()
        
        # Apply tags to all resources
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets across multiple AZs"""
        vpc = ec2.Vpc(
            self,
            "FleetVPC",
            vpc_name="ec2-fleet-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
            nat_gateways=0,  # Use public subnets only to minimize costs
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Tag subnets for better identification
        for i, subnet in enumerate(vpc.public_subnets):
            Tags.of(subnet).add("Name", f"Fleet-Public-Subnet-{i+1}")
        
        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for fleet instances"""
        sg = ec2.SecurityGroup(
            self,
            "FleetSecurityGroup",
            vpc=self.vpc,
            description="Security group for EC2 Fleet instances",
            security_group_name="ec2-fleet-sg",
            allow_all_outbound=True,
        )
        
        # Allow SSH access (consider restricting CIDR in production)
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access",
        )
        
        # Allow HTTP access
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP access",
        )
        
        # Allow HTTPS access
        sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS access",
        )
        
        return sg

    def _create_key_pair(self, suffix: str) -> ec2.KeyPair:
        """Create EC2 key pair for instance access"""
        key_pair = ec2.KeyPair(
            self,
            "FleetKeyPair",
            key_pair_name=f"fleet-keypair-{suffix}",
            type=ec2.KeyPairType.RSA,
            format=ec2.KeyPairFormat.PEM,
        )
        
        return key_pair

    def _get_latest_ami(self) -> ec2.IMachineImage:
        """Get latest Amazon Linux 2 AMI"""
        return ec2.MachineImage.latest_amazon_linux2(
            generation=ec2.AmazonLinuxGeneration.AMAZON_LINUX_2,
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )

    def _create_launch_template(self, suffix: str) -> ec2.LaunchTemplate:
        """Create launch template for fleet instances"""
        
        # User data script to set up web server
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "#!/bin/bash",
            "yum update -y",
            "yum install -y httpd",
            "systemctl start httpd",
            "systemctl enable httpd",
            "echo '<h1>EC2 Fleet Instance</h1>' > /var/www/html/index.html",
            "echo '<p>Instance ID: '$(curl -s http://169.254.169.254/latest/meta-data/instance-id)'</p>' >> /var/www/html/index.html",
            "echo '<p>Instance Type: '$(curl -s http://169.254.169.254/latest/meta-data/instance-type)'</p>' >> /var/www/html/index.html",
            "echo '<p>Availability Zone: '$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)'</p>' >> /var/www/html/index.html",
            "echo '<p>Lifecycle: '$(curl -s http://169.254.169.254/latest/meta-data/instance-life-cycle)'</p>' >> /var/www/html/index.html",
        )
        
        launch_template = ec2.LaunchTemplate(
            self,
            "FleetLaunchTemplate",
            launch_template_name=f"fleet-template-{suffix}",
            machine_image=self.ami,
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO
            ),
            key_pair=self.key_pair,
            security_group=self.security_group,
            user_data=user_data,
            detailed_monitoring=True,
            role=self._create_instance_role(),
        )
        
        return launch_template

    def _create_instance_role(self) -> iam.Role:
        """Create IAM role for EC2 instances"""
        role = iam.Role(
            self,
            "FleetInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 Fleet instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
            ],
        )
        
        return role

    def _create_spot_fleet_role(self, suffix: str) -> iam.Role:
        """Create IAM role for Spot Fleet"""
        role = iam.Role(
            self,
            "SpotFleetRole",
            role_name=f"aws-ec2-spot-fleet-role-{suffix}",
            assumed_by=iam.ServicePrincipal("spotfleet.amazonaws.com"),
            description="IAM role for EC2 Spot Fleet",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2SpotFleetRequestRole"
                ),
            ],
        )
        
        return role

    def _create_ec2_fleet(self, suffix: str) -> ec2.CfnEC2Fleet:
        """Create EC2 Fleet with mixed instances"""
        
        # Define instance type overrides for different AZs
        overrides = []
        instance_types = ["t3.micro", "t3.small", "t3.nano"]
        
        for i, subnet in enumerate(self.vpc.public_subnets[:3]):  # Use first 3 AZs
            for instance_type in instance_types:
                overrides.append(
                    ec2.CfnEC2Fleet.FleetLaunchTemplateOverridesRequestProperty(
                        availability_zone=subnet.availability_zone,
                        instance_type=instance_type,
                        subnet_id=subnet.subnet_id,
                    )
                )
        
        # Create EC2 Fleet
        fleet = ec2.CfnEC2Fleet(
            self,
            "EC2Fleet",
            launch_template_configs=[
                ec2.CfnEC2Fleet.FleetLaunchTemplateConfigRequestProperty(
                    launch_template_specification=ec2.CfnEC2Fleet.FleetLaunchTemplateSpecificationRequestProperty(
                        launch_template_id=self.launch_template.launch_template_id,
                        version="$Latest",
                    ),
                    overrides=overrides,
                )
            ],
            target_capacity_specification=ec2.CfnEC2Fleet.TargetCapacitySpecificationRequestProperty(
                total_target_capacity=6,
                on_demand_target_capacity=2,
                spot_target_capacity=4,
                default_target_capacity_type="spot",
            ),
            on_demand_options=ec2.CfnEC2Fleet.OnDemandOptionsRequestProperty(
                allocation_strategy="diversified",
            ),
            spot_options=ec2.CfnEC2Fleet.SpotOptionsRequestProperty(
                allocation_strategy="capacity-optimized",
                instance_interruption_behavior="terminate",
                replace_unhealthy_instances=True,
            ),
            type="maintain",
            excess_capacity_termination_policy="termination",
            replace_unhealthy_instances=True,
            tag_specifications=[
                ec2.CfnEC2Fleet.TagSpecificationProperty(
                    resource_type="fleet",
                    tags=[
                        {"key": "Name", "value": f"ec2-fleet-{suffix}"},
                        {"key": "Project", "value": "EC2-Fleet-Demo"},
                    ],
                ),
                ec2.CfnEC2Fleet.TagSpecificationProperty(
                    resource_type="instance",
                    tags=[
                        {"key": "Name", "value": "Fleet-Instance"},
                        {"key": "Project", "value": "EC2-Fleet-Demo"},
                    ],
                ),
            ],
        )
        
        return fleet

    def _create_spot_fleet(self, suffix: str) -> ec2.CfnSpotFleet:
        """Create Spot Fleet for comparison"""
        
        # Define launch specifications for different instance types
        launch_specs = []
        instance_types = ["t3.micro", "t3.small"]
        
        for instance_type in instance_types:
            for subnet in self.vpc.public_subnets[:2]:  # Use first 2 AZs
                launch_specs.append(
                    ec2.CfnSpotFleet.SpotFleetLaunchSpecificationProperty(
                        image_id=self.ami.get_image(self).image_id,
                        instance_type=instance_type,
                        key_name=self.key_pair.key_pair_name,
                        security_groups=[
                            ec2.CfnSpotFleet.GroupIdentifierProperty(
                                group_id=self.security_group.security_group_id
                            )
                        ],
                        subnet_id=subnet.subnet_id,
                        user_data=self.launch_template.user_data.render(),
                        tag_specifications=[
                            ec2.CfnSpotFleet.SpotFleetTagSpecificationProperty(
                                resource_type="instance",
                                tags=[
                                    {"key": "Name", "value": "SpotFleet-Instance"},
                                    {"key": "Project", "value": "EC2-Fleet-Demo"},
                                ],
                            )
                        ],
                    )
                )
        
        # Create Spot Fleet
        spot_fleet = ec2.CfnSpotFleet(
            self,
            "SpotFleet",
            spot_fleet_request_config=ec2.CfnSpotFleet.SpotFleetRequestConfigDataProperty(
                iam_fleet_role=self.spot_fleet_role.role_arn,
                allocation_strategy="capacity-optimized",
                target_capacity=3,
                spot_price="0.10",
                launch_specifications=launch_specs,
                type="maintain",
                replace_unhealthy_instances=True,
                terminate_instances_with_expiration=True,
            ),
        )
        
        return spot_fleet

    def _create_monitoring_dashboard(self, suffix: str) -> cloudwatch.Dashboard:
        """Create CloudWatch monitoring dashboard"""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "FleetMonitoringDashboard",
            dashboard_name=f"EC2-Fleet-Monitoring-{suffix}",
            start="-PT6H",  # Show last 6 hours
        )
        
        # Add CPU utilization widget
        cpu_widget = cloudwatch.GraphWidget(
            title="EC2 Fleet CPU Utilization",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="CPUUtilization",
                    dimensions_map={
                        "AutoScalingGroupName": f"ec2-fleet-{suffix}",
                    },
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            width=12,
            height=6,
        )
        
        # Add network utilization widget
        network_widget = cloudwatch.GraphWidget(
            title="Network Utilization",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkIn",
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="NetworkOut",
                    statistic="Sum",
                    period=Duration.minutes(5),
                ),
            ],
            width=12,
            height=6,
        )
        
        # Add instance count widget
        instance_widget = cloudwatch.SingleValueWidget(
            title="Fleet Instance Count",
            metrics=[
                cloudwatch.Metric(
                    namespace="AWS/EC2",
                    metric_name="GroupTotalInstances",
                    statistic="Average",
                    period=Duration.minutes(5),
                )
            ],
            width=6,
            height=6,
        )
        
        # Add Spot interruption widget
        spot_widget = cloudwatch.SingleValueWidget(
            title="Spot Interruptions (24h)",
            metrics=[
                cloudwatch.Metric(
                    namespace="AWS/EC2Spot",
                    metric_name="InterruptionNotifications",
                    statistic="Sum",
                    period=Duration.hours(24),
                )
            ],
            width=6,
            height=6,
        )
        
        # Add widgets to dashboard
        dashboard.add_widgets(cpu_widget)
        dashboard.add_widgets(network_widget)
        dashboard.add_widgets(instance_widget, spot_widget)
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="ID of the VPC",
        )
        
        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="ID of the security group",
        )
        
        CfnOutput(
            self,
            "KeyPairName",
            value=self.key_pair.key_pair_name,
            description="Name of the EC2 key pair",
        )
        
        CfnOutput(
            self,
            "LaunchTemplateId",
            value=self.launch_template.launch_template_id,
            description="ID of the launch template",
        )
        
        CfnOutput(
            self,
            "EC2FleetId",
            value=self.ec2_fleet.ref,
            description="ID of the EC2 Fleet",
        )
        
        CfnOutput(
            self,
            "SpotFleetId",
            value=self.spot_fleet.ref,
            description="ID of the Spot Fleet",
        )
        
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL of the CloudWatch dashboard",
        )

    def _apply_tags(self) -> None:
        """Apply tags to all resources in the stack"""
        Tags.of(self).add("Project", "EC2-Fleet-Management")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("Owner", "CDK-User")
        Tags.of(self).add("CostCenter", "Engineering")


def main():
    """Main application entry point"""
    app = App()
    
    # Get environment from context or use default
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the stack
    EC2FleetManagementStack(
        app,
        "EC2FleetManagementStack",
        env=env,
        description="EC2 Fleet Management with Spot Instances",
    )
    
    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()