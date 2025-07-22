#!/usr/bin/env python3
"""
AWS CDK Python application for Workforce Productivity Solutions with WorkSpaces.

This application creates a complete virtual desktop infrastructure using:
- AWS WorkSpaces for virtual desktops
- AWS Directory Service (Simple AD) for user management
- VPC with proper networking configuration
- Security groups and access controls
- CloudWatch monitoring
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_directoryservice as ds,
    aws_workspaces as workspaces,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_iam as iam,
)
from constructs import Construct
from typing import Dict, List, Optional


class WorkSpacesInfrastructureStack(Stack):
    """
    CDK Stack for AWS WorkSpaces infrastructure.
    
    Creates a complete virtual desktop infrastructure including:
    - VPC with public and private subnets across multiple AZs
    - NAT Gateway for secure internet access
    - Simple AD directory for user management
    - WorkSpaces configuration and registration
    - CloudWatch monitoring and logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Define parameters
        self.vpc_cidr = "10.0.0.0/16"
        self.directory_name = "workspaces-corp"
        self.workspace_bundle_id = self._get_standard_bundle_id()

        # Create VPC infrastructure
        self.vpc = self._create_vpc()
        
        # Create Simple AD directory
        self.directory = self._create_directory()
        
        # Register directory with WorkSpaces
        self._register_directory_with_workspaces()
        
        # Create IP access control group
        self.ip_group = self._create_ip_access_control_group()
        
        # Set up CloudWatch monitoring
        self._setup_monitoring()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for WorkSpaces.
        
        Returns:
            ec2.Vpc: The created VPC with proper subnet configuration
        """
        # Create VPC with public and private subnets
        vpc = ec2.Vpc(
            self,
            "WorkSpacesVPC",
            ip_addresses=ec2.IpAddresses.cidr(self.vpc_cidr),
            max_azs=2,
            nat_gateways=1,
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

        # Add tags to VPC
        cdk.Tags.of(vpc).add("Name", "WorkSpaces-VPC")
        cdk.Tags.of(vpc).add("Purpose", "WorkSpaces Infrastructure")

        return vpc

    def _create_directory(self) -> ds.CfnSimpleAD:
        """
        Create Simple AD directory for WorkSpaces authentication.
        
        Returns:
            ds.CfnSimpleAD: The created Simple AD directory
        """
        # Get private subnet IDs for directory
        private_subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]

        # Create Simple AD directory
        directory = ds.CfnSimpleAD(
            self,
            "WorkSpacesDirectory",
            name=f"{self.directory_name}.local",
            password="TempPassword123!",  # In production, use Secrets Manager
            size="Small",
            description="Simple AD directory for WorkSpaces",
            vpc_settings=ds.CfnSimpleAD.VpcSettingsProperty(
                vpc_id=self.vpc.vpc_id,
                subnet_ids=private_subnet_ids,
            ),
            enable_sso=False,
        )

        # Add tags to directory
        cdk.Tags.of(directory).add("Name", "WorkSpaces-Directory")
        cdk.Tags.of(directory).add("Purpose", "WorkSpaces Authentication")

        return directory

    def _register_directory_with_workspaces(self) -> workspaces.CfnWorkspaceDirectory:
        """
        Register the Simple AD directory with WorkSpaces service.
        
        Returns:
            workspaces.CfnWorkspaceDirectory: The registered directory
        """
        # Get private subnet IDs for WorkSpaces
        private_subnet_ids = [subnet.subnet_id for subnet in self.vpc.private_subnets]

        # Register directory with WorkSpaces
        workspace_directory = workspaces.CfnWorkspaceDirectory(
            self,
            "WorkSpacesDirectoryRegistration",
            directory_id=self.directory.ref,
            subnet_ids=private_subnet_ids,
            enable_work_docs=True,
            enable_self_service=True,
            tenancy="SHARED",  # Can be changed to DEDICATED for compliance requirements
        )

        # Add dependency on directory
        workspace_directory.add_dependency(self.directory)

        return workspace_directory

    def _create_ip_access_control_group(self) -> workspaces.CfnIpGroup:
        """
        Create IP access control group for WorkSpaces security.
        
        Returns:
            workspaces.CfnIpGroup: The created IP access control group
        """
        # Create IP access control group
        ip_group = workspaces.CfnIpGroup(
            self,
            "WorkSpacesIpGroup",
            group_name="WorkSpaces-IP-Group",
            group_desc="IP access control for WorkSpaces",
            user_rules=[
                workspaces.CfnIpGroup.IpRuleItemProperty(
                    ip_rule="0.0.0.0/0",  # In production, restrict to specific IP ranges
                    rule_desc="Allow access from all IPs - restrict in production",
                )
            ],
        )

        # Associate IP group with directory
        workspaces.CfnIpGroupAssociation(
            self,
            "WorkSpacesIpGroupAssociation",
            group_id=ip_group.ref,
            directory_id=self.directory.ref,
        )

        return ip_group

    def _setup_monitoring(self) -> None:
        """Set up CloudWatch monitoring for WorkSpaces."""
        # Create log group for WorkSpaces
        log_group = logs.LogGroup(
            self,
            "WorkSpacesLogGroup",
            log_group_name=f"/aws/workspaces/{self.directory.ref}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudWatch alarm for connection failures
        connection_alarm = cloudwatch.Alarm(
            self,
            "WorkSpacesConnectionFailures",
            alarm_name="WorkSpaces-Connection-Failures",
            alarm_description="Monitor WorkSpace connection failures",
            metric=cloudwatch.Metric(
                namespace="AWS/WorkSpaces",
                metric_name="ConnectionAttempt",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

    def _get_standard_bundle_id(self) -> str:
        """
        Get the bundle ID for standard Windows WorkSpace.
        
        Note: Bundle IDs vary by region. This is a placeholder that should be
        replaced with actual bundle lookup logic.
        
        Returns:
            str: The bundle ID for standard Windows WorkSpace
        """
        # This would typically be looked up via describe-workspace-bundles
        # For now, using a placeholder that needs to be replaced
        return "wsb-bh8rsxt14"  # Standard Windows bundle (example)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID for WorkSpaces infrastructure",
        )

        CfnOutput(
            self,
            "DirectoryId",
            value=self.directory.ref,
            description="Simple AD Directory ID",
        )

        CfnOutput(
            self,
            "DirectoryDnsName",
            value=f"{self.directory_name}.local",
            description="Directory DNS name for WorkSpaces",
        )

        CfnOutput(
            self,
            "PrivateSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.vpc.private_subnets]),
            description="Private subnet IDs where WorkSpaces are deployed",
        )

        CfnOutput(
            self,
            "IpGroupId",
            value=self.ip_group.ref,
            description="IP access control group ID",
        )


class WorkSpaceStack(Stack):
    """
    CDK Stack for creating individual WorkSpaces.
    
    This stack depends on the WorkSpacesInfrastructureStack and creates
    individual WorkSpace instances for users.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        directory_id: str,
        bundle_id: str,
        user_name: str,
        **kwargs,
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create WorkSpace
        workspace = workspaces.CfnWorkspace(
            self,
            f"WorkSpace-{user_name}",
            directory_id=directory_id,
            user_name=user_name,
            bundle_id=bundle_id,
            user_volume_encryption_enabled=True,
            root_volume_encryption_enabled=True,
            workspace_properties=workspaces.CfnWorkspace.WorkspacePropertiesProperty(
                running_mode="AUTO_STOP",
                running_mode_auto_stop_timeout_in_minutes=60,
                root_volume_size_gib=80,
                user_volume_size_gib=50,
                compute_type_name="STANDARD",
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"WorkSpace-{user_name}"),
                cdk.CfnTag(key="User", value=user_name),
                cdk.CfnTag(key="Purpose", value="Virtual Desktop"),
            ],
        )

        # Output WorkSpace information
        CfnOutput(
            self,
            "WorkSpaceId",
            value=workspace.ref,
            description=f"WorkSpace ID for user {user_name}",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()

    # Get configuration from context or environment
    env = cdk.Environment(
        account=app.node.try_get_context("account") or "123456789012",
        region=app.node.try_get_context("region") or "us-east-1",
    )

    # Create infrastructure stack
    infrastructure_stack = WorkSpacesInfrastructureStack(
        app,
        "WorkSpacesInfrastructureStack",
        env=env,
        description="AWS CDK stack for WorkSpaces infrastructure including VPC, Directory Service, and monitoring",
    )

    # Example WorkSpace creation (commented out - create as needed)
    # workspace_stack = WorkSpaceStack(
    #     app,
    #     "WorkSpaceStack-TestUser",
    #     directory_id=infrastructure_stack.directory.ref,
    #     bundle_id=infrastructure_stack.workspace_bundle_id,
    #     user_name="testuser",
    #     env=env,
    #     description="AWS CDK stack for individual WorkSpace creation",
    # )
    # workspace_stack.add_dependency(infrastructure_stack)

    # Add common tags to all resources
    cdk.Tags.of(app).add("Project", "WorkSpaces-VDI")
    cdk.Tags.of(app).add("Environment", "Development")
    cdk.Tags.of(app).add("Owner", "IT-Team")

    app.synth()


if __name__ == "__main__":
    main()