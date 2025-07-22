#!/usr/bin/env python3
"""
CDK Python application for building distributed file systems with Amazon EFS.

This application creates a complete EFS setup with:
- VPC with multiple subnets across AZs
- EFS file system with encryption
- Mount targets in multiple AZs
- EC2 instances for testing
- Security groups for secure NFS access
- EFS access points for fine-grained control
- CloudWatch monitoring and logging
- AWS Backup configuration
- Performance optimization settings
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_ec2 as ec2,
    aws_efs as efs,
    aws_iam as iam,
    aws_logs as logs,
    aws_backup as backup,
    aws_cloudwatch as cloudwatch,
    aws_ssm as ssm,
)
from constructs import Construct


class DistributedEfsStack(Stack):
    """Stack for creating a distributed file system with Amazon EFS."""
    
    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        environment_name: str = "dev",
        **kwargs
    ) -> None:
        """
        Initialize the Distributed EFS Stack.
        
        Args:
            scope: The CDK app scope
            construct_id: The construct identifier
            environment_name: Environment name for resource naming
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.environment_name = environment_name
        
        # Create VPC with multiple AZs
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create EFS file system
        self.file_system = self._create_efs_file_system()
        
        # Create mount targets
        self.mount_targets = self._create_mount_targets()
        
        # Create access points
        self.access_points = self._create_access_points()
        
        # Create EC2 instances for testing
        self.ec2_instances = self._create_ec2_instances()
        
        # Create CloudWatch monitoring
        self._create_monitoring()
        
        # Create backup configuration
        self._create_backup_configuration()
        
        # Create outputs
        self._create_outputs()
    
    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with multiple availability zones."""
        return ec2.Vpc(
            self,
            "DistributedEfsVpc",
            vpc_name=f"distributed-efs-vpc-{self.environment_name}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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
    
    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """Create security groups for EFS and EC2 instances."""
        security_groups = {}
        
        # Security group for EFS mount targets
        efs_sg = ec2.SecurityGroup(
            self,
            "EfsSecurityGroup",
            vpc=self.vpc,
            description="Security group for EFS mount targets",
            security_group_name=f"efs-sg-{self.environment_name}",
            allow_all_outbound=False,
        )
        
        # Security group for EC2 instances
        ec2_sg = ec2.SecurityGroup(
            self,
            "Ec2SecurityGroup",
            vpc=self.vpc,
            description="Security group for EFS client instances",
            security_group_name=f"efs-client-sg-{self.environment_name}",
            allow_all_outbound=True,
        )
        
        # Allow SSH access to EC2 instances
        ec2_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(22),
            description="Allow SSH access",
        )
        
        # Allow HTTP access to EC2 instances
        ec2_sg.add_ingress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="Allow HTTP access",
        )
        
        # Allow NFS access from EC2 security group to EFS
        efs_sg.add_ingress_rule(
            peer=ec2_sg,
            connection=ec2.Port.tcp(2049),
            description="Allow NFS access from EC2 instances",
        )
        
        security_groups["efs"] = efs_sg
        security_groups["ec2"] = ec2_sg
        
        return security_groups
    
    def _create_efs_file_system(self) -> efs.FileSystem:
        """Create EFS file system with optimal settings."""
        # Create KMS key for EFS encryption
        kms_key = cdk.aws_kms.Key(
            self,
            "EfsKmsKey",
            description="KMS key for EFS encryption",
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create EFS file system
        file_system = efs.FileSystem(
            self,
            "DistributedEfsFileSystem",
            vpc=self.vpc,
            file_system_name=f"distributed-efs-{self.environment_name}",
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            throughput_mode=efs.ThroughputMode.ELASTIC,
            encrypted=True,
            kms_key=kms_key,
            lifecycle_policy=efs.LifecyclePolicy.AFTER_30_DAYS,
            out_of_infrequent_access_policy=efs.OutOfInfrequentAccessPolicy.AFTER_1_ACCESS,
            removal_policy=RemovalPolicy.DESTROY,
            security_groups=[self.security_groups["efs"]],
            enable_backup_policy=True,
        )
        
        # Create file system policy for enhanced security
        file_system_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[iam.AccountRootPrincipal()],
                    actions=[
                        "elasticfilesystem:ClientMount",
                        "elasticfilesystem:ClientWrite",
                        "elasticfilesystem:ClientRootAccess",
                    ],
                    resources=["*"],
                    conditions={
                        "Bool": {
                            "aws:SecureTransport": "true"
                        }
                    },
                )
            ]
        )
        
        # Apply the policy to the file system
        efs.CfnFileSystemPolicy(
            self,
            "EfsFileSystemPolicy",
            file_system_id=file_system.file_system_id,
            policy_document=file_system_policy,
        )
        
        return file_system
    
    def _create_mount_targets(self) -> List[efs.MountTarget]:
        """Create mount targets in multiple availability zones."""
        mount_targets = []
        
        # Create mount targets in private subnets
        for i, subnet in enumerate(self.vpc.private_subnets):
            mount_target = efs.MountTarget(
                self,
                f"EfsMountTarget{i + 1}",
                file_system=self.file_system,
                subnet=subnet,
                security_groups=[self.security_groups["efs"]],
            )
            mount_targets.append(mount_target)
        
        return mount_targets
    
    def _create_access_points(self) -> Dict[str, efs.AccessPoint]:
        """Create EFS access points for fine-grained access control."""
        access_points = {}
        
        # Access point for web content
        web_access_point = efs.AccessPoint(
            self,
            "WebContentAccessPoint",
            file_system=self.file_system,
            path="/web-content",
            posix_user=efs.PosixUser(uid=1000, gid=1000),
            creation_info=efs.CreationInfo(
                owner_uid=1000,
                owner_gid=1000,
                permissions="755",
            ),
        )
        
        # Access point for shared data
        shared_data_access_point = efs.AccessPoint(
            self,
            "SharedDataAccessPoint",
            file_system=self.file_system,
            path="/shared-data",
            posix_user=efs.PosixUser(uid=1001, gid=1001),
            creation_info=efs.CreationInfo(
                owner_uid=1001,
                owner_gid=1001,
                permissions="750",
            ),
        )
        
        access_points["web"] = web_access_point
        access_points["shared"] = shared_data_access_point
        
        return access_points
    
    def _create_ec2_instances(self) -> List[ec2.Instance]:
        """Create EC2 instances for testing EFS functionality."""
        # Create IAM role for EC2 instances
        ec2_role = iam.Role(
            self,
            "Ec2EfsRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonElasticFileSystemClientFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
        )
        
        # Create user data script for EFS client setup
        user_data = ec2.UserData.for_linux()
        user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-efs-utils",
            "mkdir -p /mnt/efs",
            "mkdir -p /mnt/web-content",
            "mkdir -p /mnt/shared-data",
            "",
            "# Install CloudWatch agent",
            "yum install -y amazon-cloudwatch-agent",
            "",
            "# Configure CloudWatch agent",
            "cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'EOF'",
            "{",
            '    "logs": {',
            '        "logs_collected": {',
            '            "files": {',
            '                "collect_list": [',
            '                    {',
            '                        "file_path": "/var/log/messages",',
            '                        "log_group_name": "/aws/ec2/efs-demo",',
            '                        "log_stream_name": "{instance_id}/var/log/messages"',
            '                    }',
            '                ]',
            '            }',
            '        }',
            '    }',
            "}",
            "EOF",
            "",
            "# Start CloudWatch agent",
            "/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \\",
            "    -a fetch-config -m ec2 -s \\",
            "    -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json",
            "",
            f"# Mount EFS file system",
            f"mount -t efs -o tls,iam {self.file_system.file_system_id}:/ /mnt/efs",
            "",
            f"# Mount access points",
            f"mount -t efs -o tls,iam,accesspoint={self.access_points['web'].access_point_id} {self.file_system.file_system_id}:/ /mnt/web-content",
            f"mount -t efs -o tls,iam,accesspoint={self.access_points['shared'].access_point_id} {self.file_system.file_system_id}:/ /mnt/shared-data",
            "",
            "# Add to fstab for persistent mounting",
            f"echo '{self.file_system.file_system_id}:/ /mnt/efs efs defaults,_netdev,tls,iam' >> /etc/fstab",
            f"echo '{self.file_system.file_system_id}:/ /mnt/web-content efs defaults,_netdev,tls,iam,accesspoint={self.access_points['web'].access_point_id}' >> /etc/fstab",
            f"echo '{self.file_system.file_system_id}:/ /mnt/shared-data efs defaults,_netdev,tls,iam,accesspoint={self.access_points['shared'].access_point_id}' >> /etc/fstab",
        )
        
        # Get latest Amazon Linux 2 AMI
        ami = ec2.MachineImage.latest_amazon_linux2()
        
        instances = []
        
        # Create instances in different AZs
        for i, subnet in enumerate(self.vpc.private_subnets[:2]):  # Create 2 instances
            instance = ec2.Instance(
                self,
                f"EfsTestInstance{i + 1}",
                instance_type=ec2.InstanceType.of(
                    ec2.InstanceClass.T3,
                    ec2.InstanceSize.MICRO,
                ),
                machine_image=ami,
                vpc=self.vpc,
                vpc_subnets=ec2.SubnetSelection(subnets=[subnet]),
                security_group=self.security_groups["ec2"],
                role=ec2_role,
                user_data=user_data,
                key_name=None,  # You can set a key pair name here if needed
            )
            
            # Add name tag
            cdk.Tags.of(instance).add("Name", f"efs-test-instance-{i + 1}-{self.environment_name}")
            
            instances.append(instance)
        
        return instances
    
    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring for EFS."""
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "EfsLogGroup",
            log_group_name=f"/aws/efs/distributed-efs-{self.environment_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "EfsDashboard",
            dashboard_name=f"EFS-{self.environment_name}-Dashboard",
        )
        
        # Add EFS metrics widgets
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="EFS Data Transfer",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/EFS",
                        metric_name="TotalIOBytes",
                        dimensions_map={
                            "FileSystemId": self.file_system.file_system_id,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/EFS",
                        metric_name="DataReadIOBytes",
                        dimensions_map={
                            "FileSystemId": self.file_system.file_system_id,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/EFS",
                        metric_name="DataWriteIOBytes",
                        dimensions_map={
                            "FileSystemId": self.file_system.file_system_id,
                        },
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
            ),
            cloudwatch.GraphWidget(
                title="EFS Performance",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/EFS",
                        metric_name="ClientConnections",
                        dimensions_map={
                            "FileSystemId": self.file_system.file_system_id,
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/EFS",
                        metric_name="TotalIOTime",
                        dimensions_map={
                            "FileSystemId": self.file_system.file_system_id,
                        },
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
            ),
        )
    
    def _create_backup_configuration(self) -> None:
        """Create AWS Backup configuration for EFS."""
        # Create backup vault
        backup_vault = backup.BackupVault(
            self,
            "EfsBackupVault",
            backup_vault_name=f"efs-backup-vault-{self.environment_name}",
            encryption_key=cdk.aws_kms.Key(
                self,
                "BackupVaultKmsKey",
                description="KMS key for backup vault encryption",
                removal_policy=RemovalPolicy.DESTROY,
            ),
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create backup plan
        backup_plan = backup.BackupPlan(
            self,
            "EfsBackupPlan",
            backup_plan_name=f"efs-daily-backup-{self.environment_name}",
            backup_plan_rules=[
                backup.BackupPlanRule(
                    rule_name="DailyBackup",
                    backup_vault=backup_vault,
                    schedule_expression=cdk.aws_events.ScheduleExpression.cron(
                        minute="0",
                        hour="2",
                        day="*",
                        month="*",
                        year="*",
                    ),
                    start_window=Duration.hours(1),
                    delete_after=Duration.days(30),
                    recovery_point_tags={
                        "EFS": f"distributed-efs-{self.environment_name}",
                    },
                )
            ],
        )
        
        # Create backup selection
        backup.BackupSelection(
            self,
            "EfsBackupSelection",
            backup_plan=backup_plan,
            backup_selection_name=f"efs-selection-{self.environment_name}",
            resources=[
                backup.BackupResource.from_efs_file_system(self.file_system)
            ],
        )
    
    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="VPC ID",
        )
        
        CfnOutput(
            self,
            "EfsFileSystemId",
            value=self.file_system.file_system_id,
            description="EFS File System ID",
        )
        
        CfnOutput(
            self,
            "EfsFileSystemArn",
            value=self.file_system.file_system_arn,
            description="EFS File System ARN",
        )
        
        CfnOutput(
            self,
            "WebAccessPointId",
            value=self.access_points["web"].access_point_id,
            description="Web Content Access Point ID",
        )
        
        CfnOutput(
            self,
            "SharedDataAccessPointId",
            value=self.access_points["shared"].access_point_id,
            description="Shared Data Access Point ID",
        )
        
        CfnOutput(
            self,
            "EfsSecurityGroupId",
            value=self.security_groups["efs"].security_group_id,
            description="EFS Security Group ID",
        )
        
        CfnOutput(
            self,
            "Ec2SecurityGroupId",
            value=self.security_groups["ec2"].security_group_id,
            description="EC2 Security Group ID",
        )
        
        # Output instance IDs
        for i, instance in enumerate(self.ec2_instances):
            CfnOutput(
                self,
                f"Ec2Instance{i + 1}Id",
                value=instance.instance_id,
                description=f"EC2 Instance {i + 1} ID",
            )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment configuration
    account = os.getenv("CDK_DEFAULT_ACCOUNT")
    region = os.getenv("CDK_DEFAULT_REGION")
    environment_name = os.getenv("ENVIRONMENT_NAME", "dev")
    
    # Create the stack
    DistributedEfsStack(
        app,
        "DistributedEfsStack",
        environment_name=environment_name,
        env=Environment(account=account, region=region),
        description="Distributed File System with Amazon EFS - CDK Python Application",
    )
    
    app.synth()


if __name__ == "__main__":
    main()