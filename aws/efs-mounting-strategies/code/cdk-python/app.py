#!/usr/bin/env python3
"""
CDK Python Application for EFS Mounting Strategies

This application demonstrates comprehensive EFS mounting strategies including:
- EFS file system with general purpose performance mode
- Multi-AZ mount targets for high availability
- Security groups with proper NFS access controls
- EFS access points for multi-tenant access patterns
- IAM roles and policies for secure EC2-EFS integration
- EC2 instances with EFS utils for demonstration

Author: AWS Solutions Architecture
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_efs as efs,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
from typing import List, Dict, Any
import json


class EfsMountingStrategiesStack(Stack):
    """
    CDK Stack implementing EFS mounting strategies with comprehensive
    multi-AZ deployment, security controls, and access patterns.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.environment_name = self.node.try_get_context("environment") or "dev"
        self.instance_type = self.node.try_get_context("instance_type") or "t3.micro"
        self.provisioned_throughput = self.node.try_get_context("provisioned_throughput") or 100
        
        # Create VPC or use existing
        self.vpc = self._create_or_get_vpc()
        
        # Create EFS file system
        self.efs_filesystem = self._create_efs_filesystem()
        
        # Create security groups
        self.efs_security_group = self._create_efs_security_group()
        self.ec2_security_group = self._create_ec2_security_group()
        
        # Create mount targets
        self.mount_targets = self._create_mount_targets()
        
        # Create access points
        self.access_points = self._create_access_points()
        
        # Create IAM role for EC2
        self.ec2_role = self._create_ec2_iam_role()
        
        # Create EC2 instances for testing
        self.ec2_instances = self._create_ec2_instances()
        
        # Create CloudWatch log group for monitoring
        self.log_group = self._create_log_group()
        
        # Create outputs
        self._create_outputs()

    def _create_or_get_vpc(self) -> ec2.Vpc:
        """
        Create a new VPC or use existing VPC based on context.
        
        Returns:
            ec2.Vpc: The VPC to use for EFS deployment
        """
        existing_vpc_id = self.node.try_get_context("vpc_id")
        
        if existing_vpc_id:
            return ec2.Vpc.from_lookup(
                self, "ExistingVpc",
                vpc_id=existing_vpc_id
            )
        
        # Create new VPC with multiple AZs for EFS
        return ec2.Vpc(
            self, "EfsVpc",
            vpc_name=f"efs-vpc-{self.environment_name}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

    def _create_efs_filesystem(self) -> efs.FileSystem:
        """
        Create EFS file system with general purpose performance mode
        and provisioned throughput for predictable performance.
        
        Returns:
            efs.FileSystem: The created EFS file system
        """
        return efs.FileSystem(
            self, "EfsFileSystem",
            vpc=self.vpc,
            file_system_name=f"efs-mounting-strategies-{self.environment_name}",
            
            # Performance configuration
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            throughput_mode=efs.ThroughputMode.PROVISIONED,
            provisioned_throughput_per_second=cdk.Size.mebibytes(self.provisioned_throughput),
            
            # Security configuration
            encrypted=True,
            kms_key=None,  # Use AWS managed key
            
            # Lifecycle configuration for cost optimization
            lifecycle_policy=efs.LifecyclePolicy.AFTER_30_DAYS,
            transition_to_archive_policy=efs.LifecyclePolicy.AFTER_90_DAYS,
            
            # Backup configuration
            enable_backup_policy=True,
            
            # Removal policy
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_efs_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for EFS mount targets allowing NFS traffic.
        
        Returns:
            ec2.SecurityGroup: Security group for EFS mount targets
        """
        security_group = ec2.SecurityGroup(
            self, "EfsSecurityGroup",
            vpc=self.vpc,
            security_group_name=f"efs-mount-sg-{self.environment_name}",
            description="Security group for EFS mount targets - allows NFS traffic",
            allow_all_outbound=False,
        )
        
        # Allow NFS traffic from VPC CIDR
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(2049),
            description="NFS traffic from VPC",
        )
        
        return security_group

    def _create_ec2_security_group(self) -> ec2.SecurityGroup:
        """
        Create security group for EC2 instances with necessary outbound rules.
        
        Returns:
            ec2.SecurityGroup: Security group for EC2 instances
        """
        security_group = ec2.SecurityGroup(
            self, "Ec2SecurityGroup",
            vpc=self.vpc,
            security_group_name=f"efs-ec2-sg-{self.environment_name}",
            description="Security group for EC2 instances accessing EFS",
            allow_all_outbound=True,
        )
        
        # Optional: Add SSH access if needed
        if self.node.try_get_context("enable_ssh"):
            security_group.add_ingress_rule(
                peer=ec2.Peer.any_ipv4(),
                connection=ec2.Port.tcp(22),
                description="SSH access (configure source IP appropriately)",
            )
        
        return security_group

    def _create_mount_targets(self) -> List[efs.MountTarget]:
        """
        Create EFS mount targets in multiple availability zones for high availability.
        
        Returns:
            List[efs.MountTarget]: List of created mount targets
        """
        mount_targets = []
        
        # Create mount target in each private subnet
        for i, subnet in enumerate(self.vpc.private_subnets):
            mount_target = efs.MountTarget(
                self, f"EfsMountTarget{i}",
                file_system=self.efs_filesystem,
                subnet=subnet,
                security_group=self.efs_security_group,
            )
            mount_targets.append(mount_target)
        
        return mount_targets

    def _create_access_points(self) -> Dict[str, efs.AccessPoint]:
        """
        Create EFS access points for different use cases with enforced
        user identity and path restrictions.
        
        Returns:
            Dict[str, efs.AccessPoint]: Dictionary of access points by name
        """
        access_points = {}
        
        # Application data access point
        access_points["app_data"] = efs.AccessPoint(
            self, "AppDataAccessPoint",
            file_system=self.efs_filesystem,
            path="/app-data",
            posix_user=efs.PosixUser(
                uid=1000,
                gid=1000,
            ),
            creation_info=efs.CreationInfo(
                owner_uid=1000,
                owner_gid=1000,
                permissions="0755",
            ),
        )
        
        # User data access point
        access_points["user_data"] = efs.AccessPoint(
            self, "UserDataAccessPoint",
            file_system=self.efs_filesystem,
            path="/user-data",
            posix_user=efs.PosixUser(
                uid=2000,
                gid=2000,
            ),
            creation_info=efs.CreationInfo(
                owner_uid=2000,
                owner_gid=2000,
                permissions="0750",
            ),
        )
        
        # Logs access point
        access_points["logs"] = efs.AccessPoint(
            self, "LogsAccessPoint",
            file_system=self.efs_filesystem,
            path="/logs",
            posix_user=efs.PosixUser(
                uid=3000,
                gid=3000,
            ),
            creation_info=efs.CreationInfo(
                owner_uid=3000,
                owner_gid=3000,
                permissions="0755",
            ),
        )
        
        return access_points

    def _create_ec2_iam_role(self) -> iam.Role:
        """
        Create IAM role for EC2 instances with EFS access permissions.
        
        Returns:
            iam.Role: IAM role for EC2 instances
        """
        role = iam.Role(
            self, "Ec2EfsRole",
            role_name=f"EFS-EC2-Role-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for EC2 instances to access EFS",
        )
        
        # Add EFS access permissions
        efs_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "elasticfilesystem:ClientMount",
                "elasticfilesystem:ClientWrite",
                "elasticfilesystem:ClientRootAccess",
            ],
            resources=[self.efs_filesystem.file_system_arn],
        )
        
        role.add_to_policy(efs_policy)
        
        # Add CloudWatch logs permissions for monitoring
        logs_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams",
            ],
            resources=[
                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/ec2/efs-demo:*"
            ],
        )
        
        role.add_to_policy(logs_policy)
        
        # Add Systems Manager permissions for easier management
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AmazonSSMManagedInstanceCore"
            )
        )
        
        return role

    def _create_ec2_instances(self) -> List[ec2.Instance]:
        """
        Create EC2 instances with EFS utils for demonstrating mounting strategies.
        
        Returns:
            List[ec2.Instance]: List of created EC2 instances
        """
        instances = []
        
        # Get latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE,
        )
        
        # Create user data script for EFS utils installation
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-efs-utils",
            "mkdir -p /mnt/efs",
            "mkdir -p /mnt/efs-app",
            "mkdir -p /mnt/efs-user",
            "mkdir -p /mnt/efs-logs",
            "",
            "# Install CloudWatch agent",
            "yum install -y amazon-cloudwatch-agent",
            "",
            "# Create mount script for different strategies",
            "cat > /home/ec2-user/mount-efs.sh << 'EOF'",
            "#!/bin/bash",
            "# Standard NFS mount",
            f"sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 {self.efs_filesystem.file_system_id}.efs.{self.region}.amazonaws.com:/ /mnt/efs",
            "",
            "# EFS utils mounts with TLS encryption",
            f"sudo mount -t efs -o tls {self.efs_filesystem.file_system_id}:/ /mnt/efs",
            f"sudo mount -t efs -o tls,accesspoint={self.access_points['app_data'].access_point_id} {self.efs_filesystem.file_system_id}:/ /mnt/efs-app",
            f"sudo mount -t efs -o tls,accesspoint={self.access_points['user_data'].access_point_id} {self.efs_filesystem.file_system_id}:/ /mnt/efs-user",
            f"sudo mount -t efs -o tls,accesspoint={self.access_points['logs'].access_point_id} {self.efs_filesystem.file_system_id}:/ /mnt/efs-logs",
            "",
            "# Verify mounts",
            "df -h | grep efs",
            "EOF",
            "",
            "chmod +x /home/ec2-user/mount-efs.sh",
            "chown ec2-user:ec2-user /home/ec2-user/mount-efs.sh",
            "",
            "# Create performance test script",
            "cat > /home/ec2-user/test-efs-performance.sh << 'EOF'",
            "#!/bin/bash",
            "echo 'Testing EFS performance...'",
            "time dd if=/dev/zero of=/mnt/efs/test-file bs=1M count=100",
            "time dd if=/mnt/efs/test-file of=/dev/null bs=1M",
            "rm -f /mnt/efs/test-file",
            "echo 'Performance test completed'",
            "EOF",
            "",
            "chmod +x /home/ec2-user/test-efs-performance.sh",
            "chown ec2-user:ec2-user /home/ec2-user/test-efs-performance.sh",
        )
        
        # Create instances in different AZs for demonstration
        for i, subnet in enumerate(self.vpc.private_subnets[:2]):  # Create 2 instances
            instance = ec2.Instance(
                self, f"EfsTestInstance{i}",
                instance_name=f"efs-test-instance-{i}-{self.environment_name}",
                instance_type=ec2.InstanceType(self.instance_type),
                machine_image=amzn_linux,
                vpc=self.vpc,
                vpc_subnets=ec2.SubnetSelection(subnets=[subnet]),
                security_group=self.ec2_security_group,
                role=self.ec2_role,
                user_data=user_data,
                detailed_monitoring=True,
            )
            
            instances.append(instance)
        
        return instances

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for EFS monitoring and troubleshooting.
        
        Returns:
            logs.LogGroup: CloudWatch log group
        """
        return logs.LogGroup(
            self, "EfsLogGroup",
            log_group_name=f"/aws/ec2/efs-demo-{self.environment_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        # EFS File System outputs
        CfnOutput(
            self, "EfsFileSystemId",
            value=self.efs_filesystem.file_system_id,
            description="EFS File System ID",
            export_name=f"EfsFileSystemId-{self.environment_name}",
        )
        
        CfnOutput(
            self, "EfsFileSystemArn",
            value=self.efs_filesystem.file_system_arn,
            description="EFS File System ARN",
            export_name=f"EfsFileSystemArn-{self.environment_name}",
        )
        
        # Access Point outputs
        for name, access_point in self.access_points.items():
            CfnOutput(
                self, f"EfsAccessPoint{name.title().replace('_', '')}",
                value=access_point.access_point_id,
                description=f"EFS Access Point ID for {name.replace('_', ' ')}",
                export_name=f"EfsAccessPoint{name.title().replace('_', '')}-{self.environment_name}",
            )
        
        # Mount targets
        for i, mount_target in enumerate(self.mount_targets):
            CfnOutput(
                self, f"EfsMountTarget{i}",
                value=mount_target.mount_target_id,
                description=f"EFS Mount Target {i} ID",
                export_name=f"EfsMountTarget{i}-{self.environment_name}",
            )
        
        # EC2 instances
        for i, instance in enumerate(self.ec2_instances):
            CfnOutput(
                self, f"Ec2Instance{i}Id",
                value=instance.instance_id,
                description=f"EC2 Instance {i} ID",
                export_name=f"Ec2Instance{i}Id-{self.environment_name}",
            )
        
        # VPC information
        CfnOutput(
            self, "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
            export_name=f"VpcId-{self.environment_name}",
        )
        
        # Security Group IDs
        CfnOutput(
            self, "EfsSecurityGroupId",
            value=self.efs_security_group.security_group_id,
            description="EFS Security Group ID",
            export_name=f"EfsSecurityGroupId-{self.environment_name}",
        )
        
        CfnOutput(
            self, "Ec2SecurityGroupId",
            value=self.ec2_security_group.security_group_id,
            description="EC2 Security Group ID",
            export_name=f"Ec2SecurityGroupId-{self.environment_name}",
        )
        
        # IAM Role
        CfnOutput(
            self, "Ec2RoleArn",
            value=self.ec2_role.role_arn,
            description="EC2 IAM Role ARN",
            export_name=f"Ec2RoleArn-{self.environment_name}",
        )
        
        # Mount commands for reference
        CfnOutput(
            self, "StandardNfsMountCommand",
            value=f"sudo mount -t nfs4 -o nfsvers=4.1,rsize=1048576,wsize=1048576,hard,intr,timeo=600,retrans=2 {self.efs_filesystem.file_system_id}.efs.{self.region}.amazonaws.com:/ /mnt/efs",
            description="Standard NFS mount command",
        )
        
        CfnOutput(
            self, "EfsUtilsMountCommand",
            value=f"sudo mount -t efs -o tls {self.efs_filesystem.file_system_id}:/ /mnt/efs",
            description="EFS Utils mount command with TLS encryption",
        )


def main():
    """
    Main function to create and deploy the CDK app.
    """
    app = App()
    
    # Get environment configuration
    env_name = app.node.try_get_context("environment") or "dev"
    account = app.node.try_get_context("account")
    region = app.node.try_get_context("region")
    
    # Create the stack
    EfsMountingStrategiesStack(
        app, 
        f"EfsMountingStrategiesStack-{env_name}",
        env=Environment(
            account=account,
            region=region,
        ),
        description="EFS mounting strategies demonstration with multi-AZ deployment and access points",
    )
    
    app.synth()


if __name__ == "__main__":
    main()