#!/usr/bin/env python3
"""
CDK Python Application for High-Performance File Systems with Amazon FSx

This application creates a comprehensive FSx deployment including:
- FSx for Lustre with S3 integration for HPC workloads
- FSx for Windows File Server for Windows applications
- FSx for NetApp ONTAP with multi-protocol support
- Supporting infrastructure (VPC, Security Groups, EC2 instances)
- CloudWatch monitoring and alarms
- Automated backup policies
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Environment,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_fsx as fsx,
    aws_s3 as s3,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from typing import List, Dict, Optional
import json


class HighPerformanceFSxStack(Stack):
    """
    CDK Stack for deploying high-performance file systems using Amazon FSx.
    
    This stack creates multiple FSx file systems optimized for different workloads:
    - Lustre for high-performance computing
    - Windows File Server for SMB-based applications
    - NetApp ONTAP for multi-protocol enterprise workloads
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.project_name = "fsx-demo"
        self.environment_name = "production"
        
        # Create VPC and networking components
        self._create_vpc_infrastructure()
        
        # Create S3 bucket for Lustre data repository
        self._create_s3_data_repository()
        
        # Create security groups
        self._create_security_groups()
        
        # Create IAM roles for FSx services
        self._create_iam_roles()
        
        # Create FSx file systems
        self._create_lustre_file_system()
        self._create_windows_file_system()
        self._create_ontap_file_system()
        
        # Create ONTAP Storage Virtual Machine and volumes
        self._create_ontap_svm_and_volumes()
        
        # Create test EC2 instances
        self._create_test_instances()
        
        # Set up CloudWatch monitoring
        self._create_cloudwatch_monitoring()
        
        # Apply tags to all resources
        self._apply_tags()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc_infrastructure(self) -> None:
        """Create VPC with public and private subnets across multiple AZs."""
        self.vpc = ec2.Vpc(
            self, "FSxVPC",
            vpc_name=f"{self.project_name}-vpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,
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

    def _create_s3_data_repository(self) -> None:
        """Create S3 bucket for FSx Lustre data repository integration."""
        self.s3_bucket = s3.Bucket(
            self, "LustreDataRepository",
            bucket_name=f"{self.project_name}-lustre-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Create folders in S3 bucket for Lustre integration
        s3.BucketDeployment(
            self, "LustreDataFolders",
            sources=[s3.Source.data("input/", "")],
            destination_bucket=self.s3_bucket,
            destination_key_prefix="input/"
        )

    def _create_security_groups(self) -> None:
        """Create security groups for FSx file systems and clients."""
        # Security group for FSx file systems
        self.fsx_security_group = ec2.SecurityGroup(
            self, "FSxSecurityGroup",
            vpc=self.vpc,
            description="Security group for FSx file systems",
            security_group_name=f"{self.project_name}-fsx-sg"
        )

        # FSx Lustre traffic (TCP 988)
        self.fsx_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(988),
            description="FSx Lustre traffic"
        )

        # SMB traffic for Windows File Server (TCP 445)
        self.fsx_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(445),
            description="SMB traffic for Windows File Server"
        )

        # NFS traffic for ONTAP (TCP 111, 2049)
        self.fsx_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(111),
            description="NFS portmapper traffic"
        )

        self.fsx_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(2049),
            description="NFS traffic for ONTAP"
        )

        # iSCSI traffic for ONTAP (TCP 3260)
        self.fsx_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3260),
            description="iSCSI traffic for ONTAP"
        )

        # Security group for client instances
        self.client_security_group = ec2.SecurityGroup(
            self, "ClientSecurityGroup",
            vpc=self.vpc,
            description="Security group for FSx client instances",
            security_group_name=f"{self.project_name}-client-sg"
        )

        # SSH access for management
        self.client_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(22),
            description="SSH access"
        )

        # RDP access for Windows clients
        self.client_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3389),
            description="RDP access"
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for FSx services."""
        # Service role for FSx Lustre S3 integration
        self.fsx_service_role = iam.Role(
            self, "FSxServiceRole",
            role_name=f"{self.project_name}-fsx-service-role",
            assumed_by=iam.ServicePrincipal("fsx.amazonaws.com"),
            description="Service role for FSx to access S3 and other AWS services",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess")
            ]
        )

        # Add custom policy for S3 write access to specific bucket
        s3_write_policy = iam.Policy(
            self, "FSxS3WritePolicy",
            policy_name=f"{self.project_name}-fsx-s3-write",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:PutObject",
                        "s3:PutObjectAcl",
                        "s3:DeleteObject"
                    ],
                    resources=[
                        f"{self.s3_bucket.bucket_arn}/*"
                    ]
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:ListBucket"
                    ],
                    resources=[
                        self.s3_bucket.bucket_arn
                    ]
                )
            ]
        )
        
        self.fsx_service_role.attach_inline_policy(s3_write_policy)

    def _create_lustre_file_system(self) -> None:
        """Create FSx for Lustre file system optimized for HPC workloads."""
        # Get private subnets for FSx deployment
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        ).subnets

        self.lustre_file_system = fsx.CfnFileSystem(
            self, "LustreFileSystem",
            file_system_type="LUSTRE",
            storage_capacity=1200,  # Minimum 1.2 TiB for SCRATCH_2
            subnet_ids=[private_subnets[0].subnet_id],
            security_group_ids=[self.fsx_security_group.security_group_id],
            lustre_configuration=fsx.CfnFileSystem.LustreConfigurationProperty(
                deployment_type="SCRATCH_2",
                per_unit_storage_throughput=250,  # MB/s per TiB
                data_repository_configuration=fsx.CfnFileSystem.DataRepositoryConfigurationProperty(
                    bucket=self.s3_bucket.bucket_name,
                    import_path=f"s3://{self.s3_bucket.bucket_name}/input/",
                    export_path=f"s3://{self.s3_bucket.bucket_name}/output/",
                    auto_import_policy="NEW_CHANGED_DELETED"
                ),
                data_compression_type="LZ4"
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-lustre"),
                cdk.CfnTag(key="Purpose", value="HPC-Workloads")
            ]
        )

    def _create_windows_file_system(self) -> None:
        """Create FSx for Windows File Server."""
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        ).subnets

        self.windows_file_system = fsx.CfnFileSystem(
            self, "WindowsFileSystem",
            file_system_type="WINDOWS",
            storage_capacity=32,  # Minimum 32 GiB
            subnet_ids=[private_subnets[0].subnet_id],
            security_group_ids=[self.fsx_security_group.security_group_id],
            windows_configuration=fsx.CfnFileSystem.WindowsConfigurationProperty(
                throughput_capacity=16,  # MB/s
                deployment_type="SINGLE_AZ_1",
                preferred_subnet_id=private_subnets[0].subnet_id,
                automatic_backup_retention_days=7,
                copy_tags_to_backups=True,
                daily_automatic_backup_start_time="01:00"
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-windows"),
                cdk.CfnTag(key="Purpose", value="Windows-Applications")
            ]
        )

    def _create_ontap_file_system(self) -> None:
        """Create FSx for NetApp ONTAP file system with multi-AZ deployment."""
        private_subnets = self.vpc.select_subnets(
            subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
        ).subnets

        # Ensure we have at least 2 subnets for multi-AZ deployment
        if len(private_subnets) < 2:
            raise ValueError("At least 2 private subnets required for ONTAP multi-AZ deployment")

        self.ontap_file_system = fsx.CfnFileSystem(
            self, "ONTAPFileSystem",
            file_system_type="ONTAP",
            storage_capacity=1024,  # Minimum 1024 GiB
            subnet_ids=[private_subnets[0].subnet_id, private_subnets[1].subnet_id],
            security_group_ids=[self.fsx_security_group.security_group_id],
            ontap_configuration=fsx.CfnFileSystem.OntapConfigurationProperty(
                deployment_type="MULTI_AZ_1",
                throughput_capacity=256,  # MB/s
                preferred_subnet_id=private_subnets[0].subnet_id,
                fsx_admin_password="TempPassword123!",  # Change in production
                automatic_backup_retention_days=14,
                daily_automatic_backup_start_time="02:00"
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-ontap"),
                cdk.CfnTag(key="Purpose", value="Multi-Protocol-Access")
            ]
        )

    def _create_ontap_svm_and_volumes(self) -> None:
        """Create Storage Virtual Machine and volumes for ONTAP."""
        # Create Storage Virtual Machine
        self.ontap_svm = fsx.CfnStorageVirtualMachine(
            self, "ONTAPStorageVirtualMachine",
            file_system_id=self.ontap_file_system.ref,
            name="demo-svm",
            svm_admin_password="TempPassword123!",  # Change in production
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-svm")
            ]
        )

        # Create NFS volume with UNIX security style
        self.nfs_volume = fsx.CfnVolume(
            self, "NFSVolume",
            volume_type="ONTAP",
            name="nfs-volume",
            ontap_configuration=fsx.CfnVolume.OntapConfigurationProperty(
                storage_virtual_machine_id=self.ontap_svm.ref,
                junction_path="/nfs",
                security_style="UNIX",
                size_in_megabytes=102400,  # 100 GiB
                storage_efficiency_enabled=True
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-nfs-volume")
            ]
        )

        # Create SMB volume with NTFS security style
        self.smb_volume = fsx.CfnVolume(
            self, "SMBVolume",
            volume_type="ONTAP",
            name="smb-volume",
            ontap_configuration=fsx.CfnVolume.OntapConfigurationProperty(
                storage_virtual_machine_id=self.ontap_svm.ref,
                junction_path="/smb",
                security_style="NTFS",
                size_in_megabytes=51200,  # 50 GiB
                storage_efficiency_enabled=True
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.project_name}-smb-volume")
            ]
        )

    def _create_test_instances(self) -> None:
        """Create EC2 instances for testing FSx file systems."""
        # Get the latest Amazon Linux 2 AMI
        amzn_linux = ec2.MachineImage.latest_amazon_linux2(
            edition=ec2.AmazonLinuxEdition.STANDARD,
            virtualization=ec2.AmazonLinuxVirt.HVM,
            storage=ec2.AmazonLinuxStorage.GENERAL_PURPOSE
        )

        # Create user data for Linux instance with Lustre client
        linux_user_data = ec2.UserData.for_linux()
        linux_user_data.add_commands(
            "yum update -y",
            "yum install -y amazon-efs-utils",
            "yum install -y lustre-client",
            "mkdir -p /mnt/fsx-lustre",
            "mkdir -p /mnt/fsx-nfs",
            "echo '# FSx mount points' >> /etc/fstab"
        )

        # Linux client instance for Lustre and NFS testing
        self.linux_client = ec2.Instance(
            self, "LinuxClient",
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.C5,
                ec2.InstanceSize.LARGE
            ),
            machine_image=amzn_linux,
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PUBLIC
            ),
            security_group=self.client_security_group,
            user_data=linux_user_data,
            role=iam.Role(
                self, "LinuxClientRole",
                assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
                managed_policies=[
                    iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore")
                ]
            )
        )

        # Add tags
        Tags.of(self.linux_client).add("Name", f"{self.project_name}-linux-client")
        Tags.of(self.linux_client).add("Purpose", "FSx-Testing")

    def _create_cloudwatch_monitoring(self) -> None:
        """Create CloudWatch alarms for monitoring FSx performance."""
        # Lustre throughput utilization alarm
        self.lustre_throughput_alarm = cloudwatch.Alarm(
            self, "LustreThroughputAlarm",
            alarm_name=f"{self.project_name}-lustre-throughput",
            alarm_description="Monitor Lustre throughput utilization",
            metric=cloudwatch.Metric(
                namespace="AWS/FSx",
                metric_name="ThroughputUtilization",
                dimensions_map={
                    "FileSystemId": self.lustre_file_system.ref
                },
                statistic=cloudwatch.Stats.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=80,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Windows CPU utilization alarm
        self.windows_cpu_alarm = cloudwatch.Alarm(
            self, "WindowsCPUAlarm",
            alarm_name=f"{self.project_name}-windows-cpu",
            alarm_description="Monitor Windows file system CPU utilization",
            metric=cloudwatch.Metric(
                namespace="AWS/FSx",
                metric_name="CPUUtilization",
                dimensions_map={
                    "FileSystemId": self.windows_file_system.ref
                },
                statistic=cloudwatch.Stats.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=85,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # ONTAP storage utilization alarm
        self.ontap_storage_alarm = cloudwatch.Alarm(
            self, "ONTAPStorageAlarm",
            alarm_name=f"{self.project_name}-ontap-storage",
            alarm_description="Monitor ONTAP storage utilization",
            metric=cloudwatch.Metric(
                namespace="AWS/FSx",
                metric_name="StorageUtilization",
                dimensions_map={
                    "FileSystemId": self.ontap_file_system.ref
                },
                statistic=cloudwatch.Stats.AVERAGE,
                period=Duration.minutes(5)
            ),
            threshold=90,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "FSxDashboard",
            dashboard_name=f"{self.project_name}-fsx-performance"
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lustre Throughput Utilization",
                left=[self.lustre_throughput_alarm.metric],
                width=12
            ),
            cloudwatch.GraphWidget(
                title="Windows File System CPU",
                left=[self.windows_cpu_alarm.metric],
                width=12
            ),
            cloudwatch.GraphWidget(
                title="ONTAP Storage Utilization",
                left=[self.ontap_storage_alarm.metric],
                width=12
            )
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack."""
        common_tags = {
            "Project": self.project_name,
            "Environment": self.environment_name,
            "ManagedBy": "AWS-CDK",
            "Purpose": "High-Performance-File-Systems"
        }

        for key, value in common_tags.items():
            Tags.of(self).add(key, value)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        # VPC and networking outputs
        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the FSx deployment"
        )

        # S3 bucket output
        CfnOutput(
            self, "S3DataRepository",
            value=self.s3_bucket.bucket_name,
            description="S3 bucket for Lustre data repository"
        )

        # FSx file system outputs
        CfnOutput(
            self, "LustreFileSystemId",
            value=self.lustre_file_system.ref,
            description="FSx for Lustre file system ID"
        )

        CfnOutput(
            self, "LustreFileSystemDNS",
            value=self.lustre_file_system.attr_dns_name,
            description="DNS name for FSx Lustre file system"
        )

        CfnOutput(
            self, "WindowsFileSystemId",
            value=self.windows_file_system.ref,
            description="FSx for Windows file system ID"
        )

        CfnOutput(
            self, "WindowsFileSystemDNS",
            value=self.windows_file_system.attr_dns_name,
            description="DNS name for FSx Windows file system"
        )

        CfnOutput(
            self, "ONTAPFileSystemId",
            value=self.ontap_file_system.ref,
            description="FSx for NetApp ONTAP file system ID"
        )

        # ONTAP SVM and volume outputs
        CfnOutput(
            self, "ONTAPStorageVirtualMachineId",
            value=self.ontap_svm.ref,
            description="ONTAP Storage Virtual Machine ID"
        )

        CfnOutput(
            self, "NFSVolumeId",
            value=self.nfs_volume.ref,
            description="ONTAP NFS volume ID"
        )

        CfnOutput(
            self, "SMBVolumeId",
            value=self.smb_volume.ref,
            description="ONTAP SMB volume ID"
        )

        # Client instance outputs
        CfnOutput(
            self, "LinuxClientInstanceId",
            value=self.linux_client.instance_id,
            description="Linux client instance ID for testing"
        )

        CfnOutput(
            self, "LinuxClientPublicIP",
            value=self.linux_client.instance_public_ip,
            description="Public IP of Linux client instance"
        )

        # Monitoring outputs
        CfnOutput(
            self, "CloudWatchDashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name}-fsx-performance",
            description="CloudWatch Dashboard URL for FSx monitoring"
        )

        # Mount command examples
        CfnOutput(
            self, "LustreMountCommand",
            value=f"sudo mount -t lustre {self.lustre_file_system.attr_dns_name}@tcp:/{self.lustre_file_system.attr_lustre_mount_name} /mnt/fsx-lustre",
            description="Command to mount Lustre file system"
        )

        CfnOutput(
            self, "WindowsSMBShare",
            value=f"\\\\{self.windows_file_system.attr_dns_name}\\share",
            description="Windows SMB share path"
        )


def main():
    """Main application entry point."""
    app = cdk.App()
    
    # Get environment from context or use defaults
    env = Environment(
        account=app.node.try_get_context("account") or "123456789012",
        region=app.node.try_get_context("region") or "us-east-1"
    )
    
    # Create the FSx stack
    fsx_stack = HighPerformanceFSxStack(
        app, "HighPerformanceFSxStack",
        env=env,
        description="High-Performance File Systems with Amazon FSx - Lustre, Windows, and NetApp ONTAP"
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()