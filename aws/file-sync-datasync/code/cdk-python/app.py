#!/usr/bin/env python3
"""
AWS CDK Python application for File System Synchronization with DataSync and EFS

This CDK application creates the infrastructure for automated file synchronization
between S3 and Amazon EFS using AWS DataSync service.

Author: AWS Recipe Generator
Version: 1.0
Recipe: file-system-synchronization-aws-datasync-efs
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_ec2 as ec2,
    aws_efs as efs,
    aws_s3 as s3,
    aws_datasync as datasync,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_cloudwatch_actions as cloudwatch_actions,
)
from constructs import Construct
import json
from typing import Optional


class DataSyncEfsStack(Stack):
    """
    CDK Stack for File System Sync with DataSync and EFS.
    
    This stack creates:
    - VPC with private subnets for EFS
    - Amazon EFS file system with encryption
    - S3 bucket for source data
    - DataSync task for automated synchronization
    - IAM roles and security groups
    - CloudWatch monitoring and SNS notifications
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        env: Environment,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.random_suffix = self.generate_random_suffix()
        
        # Create VPC for EFS resources
        self.vpc = self._create_vpc()
        
        # Create security group for EFS access
        self.efs_security_group = self._create_efs_security_group()
        
        # Create EFS file system
        self.efs_file_system = self._create_efs_file_system()
        
        # Create S3 bucket for source data
        self.source_bucket = self._create_source_bucket()
        
        # Create IAM role for DataSync
        self.datasync_role = self._create_datasync_iam_role()
        
        # Create DataSync locations and task
        self._create_datasync_resources()
        
        # Create monitoring resources
        self._create_monitoring_resources()
        
        # Create stack outputs
        self._create_outputs()

    def generate_random_suffix(self) -> str:
        """Generate a random suffix for resource names."""
        import random
        import string
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with private subnets for EFS access."""
        vpc = ec2.Vpc(
            self,
            "DataSyncVpc",
            vpc_name=f"datasync-vpc-{self.random_suffix}",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )
        
        # Add VPC endpoint for DataSync (if available in region)
        vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS)]
        )
        
        return vpc

    def _create_efs_security_group(self) -> ec2.SecurityGroup:
        """Create security group for EFS access."""
        security_group = ec2.SecurityGroup(
            self,
            "EfsSecurityGroup",
            vpc=self.vpc,
            description="Security group for EFS access from DataSync",
            security_group_name=f"datasync-efs-sg-{self.random_suffix}"
        )
        
        # Allow NFS traffic (port 2049) within VPC
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(2049),
            description="Allow NFS traffic within VPC"
        )
        
        # Allow HTTPS for DataSync communication
        security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(443),
            description="Allow HTTPS for DataSync communication"
        )
        
        return security_group

    def _create_efs_file_system(self) -> efs.FileSystem:
        """Create encrypted EFS file system with performance optimization."""
        file_system = efs.FileSystem(
            self,
            "DataSyncEfs",
            vpc=self.vpc,
            file_system_name=f"datasync-efs-{self.random_suffix}",
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            throughput_mode=efs.ThroughputMode.PROVISIONED,
            provisioned_throughput_per_second=cdk.Size.mebibytes(100),
            encrypted=True,
            lifecycle_policy=efs.LifecyclePolicy.AFTER_30_DAYS,
            out_of_infrequent_access_policy=efs.OutOfInfrequentAccessPolicy.AFTER_1_ACCESS,
            security_group=self.efs_security_group,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            removal_policy=RemovalPolicy.DESTROY,
            enable_backup_policy=True
        )
        
        # Add access point for application access
        access_point = file_system.add_access_point(
            "DataSyncAccessPoint",
            path="/datasync",
            creation_info=efs.AccessPointCreationInfo(
                owner_uid=1000,
                owner_gid=1000,
                permissions="0755"
            ),
            posix_user=efs.PosixUser(
                uid=1000,
                gid=1000
            )
        )
        
        return file_system

    def _create_source_bucket(self) -> s3.Bucket:
        """Create S3 bucket for source data with sample content."""
        bucket = s3.Bucket(
            self,
            "SourceBucket",
            bucket_name=f"datasync-source-{self.random_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
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
        
        # Add sample objects to the bucket
        self._add_sample_objects_to_bucket(bucket)
        
        return bucket

    def _add_sample_objects_to_bucket(self, bucket: s3.Bucket) -> None:
        """Add sample objects to S3 bucket for testing."""
        # Sample file 1
        s3.BucketDeployment(
            self,
            "SampleFiles",
            sources=[s3.Source.data("sample1.txt", "Sample file 1 content for DataSync testing")],
            destination_bucket=bucket,
            destination_key_prefix="samples/"
        )

    def _create_datasync_iam_role(self) -> iam.Role:
        """Create IAM role for DataSync service with required permissions."""
        role = iam.Role(
            self,
            "DataSyncServiceRole",
            role_name=f"DataSyncServiceRole-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("datasync.amazonaws.com"),
            description="Service role for DataSync operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonS3ReadOnlyAccess")
            ]
        )
        
        # Add custom policy for EFS access
        efs_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "elasticfilesystem:CreateFileSystem",
                "elasticfilesystem:DescribeFileSystems",
                "elasticfilesystem:DescribeMountTargets",
                "elasticfilesystem:DescribeAccessPoints",
                "elasticfilesystem:CreateAccessPoint",
                "elasticfilesystem:DeleteAccessPoint"
            ],
            resources=["*"]
        )
        
        # Add CloudWatch logging permissions
        logs_policy = iam.PolicyStatement(
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
        
        role.add_to_policy(efs_policy)
        role.add_to_policy(logs_policy)
        
        return role

    def _create_datasync_resources(self) -> None:
        """Create DataSync locations and synchronization task."""
        # Create CloudWatch log group for DataSync
        log_group = logs.LogGroup(
            self,
            "DataSyncLogGroup",
            log_group_name=f"/aws/datasync/task-{self.random_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create S3 location
        s3_location = datasync.CfnLocationS3(
            self,
            "DataSyncS3Location",
            s3_bucket_arn=self.source_bucket.bucket_arn,
            s3_config=datasync.CfnLocationS3.S3ConfigProperty(
                bucket_access_role_arn=self.datasync_role.role_arn
            ),
            s3_storage_class="STANDARD",
            subdirectory="/"
        )
        
        # Create EFS location
        efs_location = datasync.CfnLocationEFS(
            self,
            "DataSyncEfsLocation",
            efs_file_system_arn=self.efs_file_system.file_system_arn,
            ec2_config=datasync.CfnLocationEFS.Ec2ConfigProperty(
                subnet_arn=self.vpc.private_subnets[0].subnet_arn,
                security_group_arns=[self.efs_security_group.security_group_arn]
            ),
            subdirectory="/datasync"
        )
        
        # Create DataSync task
        self.datasync_task = datasync.CfnTask(
            self,
            "DataSyncTask",
            source_location_arn=s3_location.attr_location_arn,
            destination_location_arn=efs_location.attr_location_arn,
            name=f"file-sync-task-{self.random_suffix}",
            options=datasync.CfnTask.OptionsProperty(
                verify_mode="POINT_IN_TIME_CONSISTENT",
                overwrite_mode="ALWAYS",
                atime="BEST_EFFORT",
                mtime="PRESERVE",
                uid="INT_VALUE",
                gid="INT_VALUE",
                preserve_deleted_files="PRESERVE",
                preserve_devices="NONE",
                posix_permissions="PRESERVE",
                bytes_per_second=-1,
                task_queueing="ENABLED",
                log_level="TRANSFER"
            ),
            cloud_watch_log_group_arn=log_group.log_group_arn
        )
        
        # Store references for outputs
        self.s3_location = s3_location
        self.efs_location = efs_location

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring and SNS notifications."""
        # Create SNS topic for DataSync notifications
        self.notification_topic = sns.Topic(
            self,
            "DataSyncNotifications",
            topic_name=f"datasync-notifications-{self.random_suffix}",
            display_name="DataSync Task Notifications"
        )
        
        # Create CloudWatch dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "DataSyncDashboard",
            dashboard_name=f"DataSync-Monitoring-{self.random_suffix}"
        )
        
        # Add EFS metrics to dashboard
        efs_metrics_widget = cloudwatch.GraphWidget(
            title="EFS Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/EFS",
                    metric_name="DataReadIOBytes",
                    dimensions_map={
                        "FileSystemId": self.efs_file_system.file_system_id
                    }
                ),
                cloudwatch.Metric(
                    namespace="AWS/EFS",
                    metric_name="DataWriteIOBytes",
                    dimensions_map={
                        "FileSystemId": self.efs_file_system.file_system_id
                    }
                )
            ]
        )
        
        dashboard.add_widgets(efs_metrics_widget)
        
        # Create CloudWatch alarm for task failures
        task_failure_alarm = cloudwatch.Alarm(
            self,
            "DataSyncTaskFailureAlarm",
            alarm_name=f"DataSync-Task-Failure-{self.random_suffix}",
            alarm_description="Alert when DataSync task fails",
            metric=cloudwatch.Metric(
                namespace="AWS/DataSync",
                metric_name="TaskExecutionsFailedCount",
                statistic="Sum"
            ),
            threshold=1,
            evaluation_periods=1,
            datapoints_to_alarm=1
        )
        
        # Add SNS action to alarm
        task_failure_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.notification_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="ID of the VPC created for DataSync and EFS",
            export_name=f"DataSync-VPC-{self.random_suffix}"
        )
        
        CfnOutput(
            self,
            "EfsFileSystemId",
            value=self.efs_file_system.file_system_id,
            description="ID of the Amazon EFS file system",
            export_name=f"DataSync-EFS-{self.random_suffix}"
        )
        
        CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the S3 source bucket",
            export_name=f"DataSync-SourceBucket-{self.random_suffix}"
        )
        
        CfnOutput(
            self,
            "DataSyncTaskArn",
            value=self.datasync_task.attr_task_arn,
            description="ARN of the DataSync task",
            export_name=f"DataSync-TaskArn-{self.random_suffix}"
        )
        
        CfnOutput(
            self,
            "NotificationTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS notification topic",
            export_name=f"DataSync-Notifications-{self.random_suffix}"
        )
        
        CfnOutput(
            self,
            "EfsMountCommand",
            value=f"sudo mount -t efs -o tls {self.efs_file_system.file_system_id}:/ /mnt/efs",
            description="Command to mount EFS file system",
            export_name=f"DataSync-EfsMountCommand-{self.random_suffix}"
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()
    
    # Get deployment environment from context or use defaults
    account = app.node.try_get_context("account") or cdk.Aws.ACCOUNT_ID
    region = app.node.try_get_context("region") or cdk.Aws.REGION
    
    env = Environment(account=account, region=region)
    
    # Create the stack
    DataSyncEfsStack(
        app,
        "DataSyncEfsStack",
        env=env,
        description="File System Synchronization with AWS DataSync and EFS"
    )
    
    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()