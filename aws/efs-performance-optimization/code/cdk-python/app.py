#!/usr/bin/env python3
"""
CDK Application for EFS Performance Optimization and Monitoring

This CDK application deploys a complete Amazon EFS solution with performance
optimization and comprehensive CloudWatch monitoring. It creates:
- EFS file system with provisioned throughput for consistent performance
- Mount targets across multiple Availability Zones for high availability
- Security groups with proper NFS access controls
- CloudWatch dashboard for real-time performance monitoring
- CloudWatch alarms for proactive performance management
- IAM roles for EC2 instances to access EFS

Author: AWS Recipes Team
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_ec2 as ec2,
    aws_efs as efs,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags
)
from constructs import Construct
from typing import List, Optional


class EfsPerformanceOptimizationStack(Stack):
    """
    CDK Stack for EFS Performance Optimization and Monitoring
    
    This stack creates a performance-optimized EFS file system with:
    - General Purpose performance mode for low latency
    - Provisioned throughput for consistent performance
    - Encryption at rest for security compliance
    - Multi-AZ mount targets for high availability
    - Comprehensive CloudWatch monitoring and alerting
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        vpc: Optional[ec2.IVpc] = None,
        provisioned_throughput_mibps: int = 100,
        enable_backup: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the EFS Performance Optimization Stack
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            vpc: VPC to deploy resources (creates default if not provided)
            provisioned_throughput_mibps: Provisioned throughput in MiB/s
            enable_backup: Whether to enable EFS backup
            **kwargs: Additional keyword arguments for Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.provisioned_throughput = provisioned_throughput_mibps
        self.enable_backup = enable_backup

        # Use provided VPC or create a new one
        if vpc is None:
            self.vpc = self._create_vpc()
        else:
            self.vpc = vpc

        # Create security group for EFS
        self.security_group = self._create_security_group()

        # Create the EFS file system with performance optimization
        self.file_system = self._create_efs_file_system()

        # Create mount targets across multiple AZs
        self.mount_targets = self._create_mount_targets()

        # Create IAM role for EC2 instances
        self.ec2_role = self._create_ec2_role()

        # Create CloudWatch monitoring dashboard
        self.dashboard = self._create_cloudwatch_dashboard()

        # Create CloudWatch alarms for proactive monitoring
        self.alarms = self._create_cloudwatch_alarms()

        # Create outputs for reference
        self._create_outputs()

        # Apply tags to all resources
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with public and private subnets across multiple AZs
        
        Returns:
            VPC construct with proper subnet configuration
        """
        vpc = ec2.Vpc(
            self,
            "EfsVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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

        # Add VPC Flow Logs for network monitoring
        vpc.add_flow_log(
            "VpcFlowLogs",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self,
                    "VpcFlowLogsGroup",
                    retention=logs.RetentionDays.ONE_WEEK,
                    removal_policy=RemovalPolicy.DESTROY
                )
            )
        )

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for EFS mount targets with NFS access
        
        Returns:
            Security group configured for EFS access
        """
        sg = ec2.SecurityGroup(
            self,
            "EfsSecurityGroup",
            vpc=self.vpc,
            description="Security group for EFS mount targets with NFS access",
            allow_all_outbound=False
        )

        # Allow NFS traffic (port 2049) from within the security group
        sg.add_ingress_rule(
            peer=sg,
            connection=ec2.Port.tcp(2049),
            description="Allow NFS traffic from EFS clients"
        )

        # Allow NFS traffic from VPC CIDR for broader access
        sg.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(2049),
            description="Allow NFS traffic from VPC"
        )

        return sg

    def _create_efs_file_system(self) -> efs.FileSystem:
        """
        Create EFS file system with performance optimization
        
        Returns:
            EFS file system with provisioned throughput and encryption
        """
        file_system = efs.FileSystem(
            self,
            "PerformanceOptimizedEfs",
            vpc=self.vpc,
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            throughput_mode=efs.ThroughputMode.PROVISIONED,
            provisioned_throughput_per_second=cdk.Size.mebibytes(self.provisioned_throughput),
            encrypted=True,
            enable_backup_policy=self.enable_backup,
            lifecycle_policy=efs.LifecyclePolicy.AFTER_30_DAYS,
            removal_policy=RemovalPolicy.DESTROY,
            security_group=self.security_group,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            )
        )

        return file_system

    def _create_mount_targets(self) -> List[efs.MountTarget]:
        """
        Create mount targets in private subnets across multiple AZs
        
        Returns:
            List of mount target constructs
        """
        mount_targets = []
        
        # Get private subnets for mount targets
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        ).subnets

        # Create mount target in each private subnet
        for i, subnet in enumerate(private_subnets):
            mount_target = efs.MountTarget(
                self,
                f"MountTarget{i+1}",
                file_system=self.file_system,
                subnet=subnet,
                security_group=self.security_group
            )
            mount_targets.append(mount_target)

        return mount_targets

    def _create_ec2_role(self) -> iam.Role:
        """
        Create IAM role for EC2 instances to access EFS
        
        Returns:
            IAM role with EFS permissions
        """
        role = iam.Role(
            self,
            "EfsEc2Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 instances to access EFS",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonElasticFileSystemClientWrite"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
            ]
        )

        # Create instance profile for EC2
        iam.InstanceProfile(
            self,
            "EfsEc2InstanceProfile",
            role=role,
            instance_profile_name=f"{role.role_name}-profile"
        )

        return role

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for EFS performance monitoring
        
        Returns:
            CloudWatch dashboard with EFS metrics
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "EfsPerformanceDashboard",
            dashboard_name=f"EFS-Performance-{self.file_system.file_system_id}",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # Create widgets for different metrics
        throughput_widget = cloudwatch.GraphWidget(
            title="EFS IO Throughput",
            left=[
                self.file_system.metric_total_io_bytes(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                ),
                self.file_system.metric("ReadIOBytes",
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                ),
                self.file_system.metric("WriteIOBytes",
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        latency_widget = cloudwatch.GraphWidget(
            title="EFS IO Latency",
            left=[
                self.file_system.metric("TotalIOTime",
                    statistic=cloudwatch.Statistic.AVERAGE,
                    period=Duration.minutes(5)
                ),
                self.file_system.metric("ReadIOTime",
                    statistic=cloudwatch.Statistic.AVERAGE,
                    period=Duration.minutes(5)
                ),
                self.file_system.metric("WriteIOTime",
                    statistic=cloudwatch.Statistic.AVERAGE,
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        connections_widget = cloudwatch.GraphWidget(
            title="EFS Client Connections",
            left=[
                self.file_system.metric_client_connections(
                    statistic=cloudwatch.Statistic.SUM,
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        utilization_widget = cloudwatch.GraphWidget(
            title="EFS IO Limit Utilization",
            left=[
                self.file_system.metric_percent_io_limit(
                    statistic=cloudwatch.Statistic.AVERAGE,
                    period=Duration.minutes(5)
                )
            ],
            width=12,
            height=6
        )

        # Add widgets to dashboard in a 2x2 grid
        dashboard.add_widgets(
            throughput_widget,
            latency_widget
        )
        dashboard.add_widgets(
            connections_widget,
            utilization_widget
        )

        return dashboard

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for proactive performance monitoring
        
        Returns:
            List of CloudWatch alarm constructs
        """
        alarms = []

        # High throughput utilization alarm
        throughput_alarm = cloudwatch.Alarm(
            self,
            "EfsHighThroughputUtilization",
            alarm_name=f"EFS-High-Throughput-Utilization-{self.file_system.file_system_id}",
            alarm_description="EFS throughput utilization exceeds 80%",
            metric=self.file_system.metric_percent_io_limit(
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=80,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(throughput_alarm)

        # High client connections alarm
        connections_alarm = cloudwatch.Alarm(
            self,
            "EfsHighClientConnections",
            alarm_name=f"EFS-High-Client-Connections-{self.file_system.file_system_id}",
            alarm_description="EFS client connections exceed 500",
            metric=self.file_system.metric_client_connections(
                statistic=cloudwatch.Statistic.SUM,
                period=Duration.minutes(5)
            ),
            threshold=500,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(connections_alarm)

        # High IO latency alarm
        latency_alarm = cloudwatch.Alarm(
            self,
            "EfsHighIoLatency",
            alarm_name=f"EFS-High-IO-Latency-{self.file_system.file_system_id}",
            alarm_description="EFS average IO time exceeds 50ms",
            metric=self.file_system.metric("TotalIOTime",
                statistic=cloudwatch.Statistic.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=50,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=3,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(latency_alarm)

        return alarms

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        CfnOutput(
            self,
            "EfsFileSystemId",
            value=self.file_system.file_system_id,
            description="EFS File System ID for mounting"
        )

        CfnOutput(
            self,
            "EfsFileSystemArn",
            value=self.file_system.file_system_arn,
            description="EFS File System ARN"
        )

        CfnOutput(
            self,
            "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security Group ID for EFS access"
        )

        CfnOutput(
            self,
            "Ec2RoleArn",
            value=self.ec2_role.role_arn,
            description="IAM Role ARN for EC2 instances"
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL"
        )

        CfnOutput(
            self,
            "MountCommand",
            value=f"sudo mount -t efs -o tls {self.file_system.file_system_id}:/ /mnt/efs",
            description="Command to mount EFS on EC2 instances"
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack"""
        
        Tags.of(self).add("Project", "EFS-Performance-Optimization")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Purpose", "Performance-Optimized-Storage")
        Tags.of(self).add("ManagedBy", "CDK")


class EfsPerformanceApp(cdk.App):
    """
    CDK Application for EFS Performance Optimization
    
    This application creates the complete infrastructure for EFS performance
    optimization and monitoring across multiple environments.
    """

    def __init__(self) -> None:
        """Initialize the CDK application"""
        super().__init__()

        # Get configuration from context or use defaults
        env = cdk.Environment(
            account=self.node.try_get_context("account") or None,
            region=self.node.try_get_context("region") or "us-east-1"
        )

        # Create the main stack
        EfsPerformanceOptimizationStack(
            self,
            "EfsPerformanceOptimizationStack",
            env=env,
            provisioned_throughput_mibps=self.node.try_get_context("provisioned_throughput") or 100,
            enable_backup=self.node.try_get_context("enable_backup") or True,
            description="EFS Performance Optimization and Monitoring Solution"
        )


# Entry point for CDK application
if __name__ == "__main__":
    app = EfsPerformanceApp()
    app.synth()