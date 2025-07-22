#!/usr/bin/env python3
"""
AWS CDK Python Application for High Performance Computing Clusters with AWS ParallelCluster

This CDK application creates the foundational infrastructure required for AWS ParallelCluster HPC deployments,
including VPC, subnets, security groups, IAM roles, and S3 storage for data management.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_ec2 as ec2,
    aws_s3 as s3,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_fsx as fsx,
    aws_secretsmanager as secretsmanager,
)
from constructs import Construct
from typing import Dict, List, Optional
import json


class HpcParallelClusterStack(Stack):
    """
    CDK Stack for AWS ParallelCluster HPC Infrastructure
    
    This stack creates the foundational infrastructure required for AWS ParallelCluster
    deployments, including networking, storage, IAM roles, and monitoring resources.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        cluster_name: str,
        enable_fsx: bool = True,
        enable_monitoring: bool = True,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.cluster_name = cluster_name
        self.enable_fsx = enable_fsx
        self.enable_monitoring = enable_monitoring

        # Create VPC and networking infrastructure
        self.vpc = self._create_vpc()
        
        # Create security groups
        self.security_groups = self._create_security_groups()
        
        # Create S3 bucket for data storage
        self.s3_bucket = self._create_s3_bucket()
        
        # Create IAM roles and policies
        self.iam_roles = self._create_iam_roles()
        
        # Create FSx Lustre filesystem if enabled
        if self.enable_fsx:
            self.fsx_filesystem = self._create_fsx_filesystem()
        
        # Create monitoring resources if enabled
        if self.enable_monitoring:
            self.monitoring = self._create_monitoring_resources()
        
        # Create ParallelCluster configuration
        self.cluster_config = self._create_cluster_config()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC with public and private subnets for HPC cluster
        
        Returns:
            ec2.Vpc: The created VPC with configured subnets
        """
        vpc = ec2.Vpc(
            self,
            "HpcVpc",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC Flow Logs for monitoring
        vpc.add_flow_log(
            "VpcFlowLog",
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(
                logs.LogGroup(
                    self,
                    "VpcFlowLogGroup",
                    retention=logs.RetentionDays.ONE_MONTH,
                    removal_policy=RemovalPolicy.DESTROY,
                )
            ),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )
        
        # Tag VPC for ParallelCluster
        cdk.Tags.of(vpc).add("Name", f"{self.cluster_name}-vpc")
        cdk.Tags.of(vpc).add("Application", "ParallelCluster")
        
        return vpc

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for HPC cluster components
        
        Returns:
            Dict[str, ec2.SecurityGroup]: Dictionary of security groups
        """
        security_groups = {}
        
        # Head node security group
        head_node_sg = ec2.SecurityGroup(
            self,
            "HeadNodeSecurityGroup",
            vpc=self.vpc,
            description="Security group for ParallelCluster head node",
            allow_all_outbound=True,
        )
        
        # Allow SSH access from anywhere (restrict in production)
        head_node_sg.add_ingress_rule(
            ec2.Peer.any_ipv4(),
            ec2.Port.tcp(22),
            "SSH access for cluster management",
        )
        
        # Allow Slurm communication
        head_node_sg.add_ingress_rule(
            ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            ec2.Port.tcp_range(6817, 6818),
            "Slurm controller communication",
        )
        
        security_groups["head_node"] = head_node_sg
        
        # Compute node security group
        compute_node_sg = ec2.SecurityGroup(
            self,
            "ComputeNodeSecurityGroup",
            vpc=self.vpc,
            description="Security group for ParallelCluster compute nodes",
            allow_all_outbound=True,
        )
        
        # Allow communication between compute nodes
        compute_node_sg.add_ingress_rule(
            compute_node_sg,
            ec2.Port.all_traffic(),
            "Inter-compute node communication",
        )
        
        # Allow communication from head node
        compute_node_sg.add_ingress_rule(
            head_node_sg,
            ec2.Port.all_traffic(),
            "Head node to compute node communication",
        )
        
        # Allow SSH from head node
        compute_node_sg.add_ingress_rule(
            head_node_sg,
            ec2.Port.tcp(22),
            "SSH access from head node",
        )
        
        security_groups["compute_node"] = compute_node_sg
        
        # FSx security group
        fsx_sg = ec2.SecurityGroup(
            self,
            "FsxSecurityGroup",
            vpc=self.vpc,
            description="Security group for FSx Lustre filesystem",
            allow_all_outbound=True,
        )
        
        # Allow Lustre traffic from cluster nodes
        fsx_sg.add_ingress_rule(
            head_node_sg,
            ec2.Port.tcp_range(988, 988),
            "Lustre traffic from head node",
        )
        
        fsx_sg.add_ingress_rule(
            compute_node_sg,
            ec2.Port.tcp_range(988, 988),
            "Lustre traffic from compute nodes",
        )
        
        security_groups["fsx"] = fsx_sg
        
        return security_groups

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for HPC data storage and FSx integration
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self,
            "HpcDataBucket",
            bucket_name=f"{self.cluster_name}-data-{self.account}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    status=s3.LifecycleRuleStatus.ENABLED,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                ),
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Create folder structure for HPC workloads
        s3.BucketDeployment(
            self,
            "HpcDataStructure",
            sources=[s3.Source.data("input/.keep", "")],
            destination_bucket=bucket,
            destination_key_prefix="input/",
        )
        
        # Tag bucket for identification
        cdk.Tags.of(bucket).add("Application", "ParallelCluster")
        cdk.Tags.of(bucket).add("ClusterName", self.cluster_name)
        
        return bucket

    def _create_iam_roles(self) -> Dict[str, iam.Role]:
        """
        Create IAM roles and policies for ParallelCluster
        
        Returns:
            Dict[str, iam.Role]: Dictionary of IAM roles
        """
        roles = {}
        
        # ParallelCluster service role
        pc_service_role = iam.Role(
            self,
            "ParallelClusterServiceRole",
            assumed_by=iam.ServicePrincipal("parallelcluster.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSParallelClusterServiceRolePolicy"),
            ],
            inline_policies={
                "CustomClusterPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.s3_bucket.bucket_arn,
                                f"{self.s3_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "fsx:DescribeFileSystems",
                                "fsx:CreateFileSystem",
                                "fsx:DeleteFileSystem",
                                "fsx:DescribeBackups",
                                "fsx:CreateBackup",
                                "fsx:DeleteBackup",
                            ],
                            resources=["*"],
                        ),
                    ]
                ),
            },
        )
        
        roles["service"] = pc_service_role
        
        # Instance role for head node
        head_node_role = iam.Role(
            self,
            "HeadNodeRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
            inline_policies={
                "HeadNodePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.s3_bucket.bucket_arn,
                                f"{self.s3_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "ec2:DescribeInstances",
                                "ec2:DescribeInstanceAttribute",
                                "ec2:DescribeVolumes",
                                "ec2:DescribeSnapshots",
                            ],
                            resources=["*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                                "cloudwatch:GetMetricStatistics",
                                "cloudwatch:ListMetrics",
                            ],
                            resources=["*"],
                        ),
                    ]
                ),
            },
        )
        
        roles["head_node"] = head_node_role
        
        # Instance role for compute nodes
        compute_node_role = iam.Role(
            self,
            "ComputeNodeRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonSSMManagedInstanceCore"),
                iam.ManagedPolicy.from_aws_managed_policy_name("CloudWatchAgentServerPolicy"),
            ],
            inline_policies={
                "ComputeNodePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.s3_bucket.bucket_arn,
                                f"{self.s3_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cloudwatch:PutMetricData",
                            ],
                            resources=["*"],
                        ),
                    ]
                ),
            },
        )
        
        roles["compute_node"] = compute_node_role
        
        return roles

    def _create_fsx_filesystem(self) -> fsx.CfnFileSystem:
        """
        Create FSx Lustre filesystem for high-performance shared storage
        
        Returns:
            fsx.CfnFileSystem: The created FSx filesystem
        """
        # Create FSx subnet group
        fsx_subnet_group = fsx.CfnFileSystem(
            self,
            "HpcFsxFileSystem",
            file_system_type="LUSTRE",
            storage_capacity=1200,  # Minimum size for FSx Lustre
            subnet_ids=[self.vpc.private_subnets[0].subnet_id],
            security_group_ids=[self.security_groups["fsx"].security_group_id],
            lustre_configuration=fsx.CfnFileSystem.LustreConfigurationProperty(
                deployment_type="SCRATCH_2",
                import_path=f"s3://{self.s3_bucket.bucket_name}/input/",
                export_path=f"s3://{self.s3_bucket.bucket_name}/output/",
                imported_file_chunk_size=1024,
                auto_import_policy="NEW_CHANGED",
                copy_tags_to_backups=True,
            ),
            tags=[
                cdk.CfnTag(key="Name", value=f"{self.cluster_name}-fsx"),
                cdk.CfnTag(key="Application", value="ParallelCluster"),
            ],
        )
        
        return fsx_subnet_group

    def _create_monitoring_resources(self) -> Dict[str, any]:
        """
        Create CloudWatch monitoring resources for HPC cluster
        
        Returns:
            Dict[str, any]: Dictionary of monitoring resources
        """
        monitoring = {}
        
        # Create CloudWatch Log Group for cluster logs
        log_group = logs.LogGroup(
            self,
            "HpcClusterLogGroup",
            log_group_name=f"/aws/parallelcluster/{self.cluster_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        monitoring["log_group"] = log_group
        
        # Create CloudWatch Dashboard
        dashboard = cloudwatch.Dashboard(
            self,
            "HpcClusterDashboard",
            dashboard_name=f"{self.cluster_name}-performance",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="EC2 CPU Utilization",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/EC2",
                                metric_name="CPUUtilization",
                                dimensions_map={
                                    "AutoScalingGroupName": f"{self.cluster_name}-compute"
                                },
                                statistic="Average",
                                period=Duration.minutes(5),
                            )
                        ],
                        width=12,
                    ),
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Network Traffic",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/EC2",
                                metric_name="NetworkIn",
                                dimensions_map={
                                    "AutoScalingGroupName": f"{self.cluster_name}-compute"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/EC2",
                                metric_name="NetworkOut",
                                dimensions_map={
                                    "AutoScalingGroupName": f"{self.cluster_name}-compute"
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            )
                        ],
                        width=12,
                    ),
                ],
            ],
        )
        
        monitoring["dashboard"] = dashboard
        
        # Create CloudWatch Alarms
        cpu_alarm = cloudwatch.Alarm(
            self,
            "HighCpuAlarm",
            alarm_name=f"{self.cluster_name}-high-cpu",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2",
                metric_name="CPUUtilization",
                dimensions_map={
                    "AutoScalingGroupName": f"{self.cluster_name}-compute"
                },
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=80,
            evaluation_periods=2,
            alarm_description="High CPU utilization on HPC cluster",
        )
        
        monitoring["cpu_alarm"] = cpu_alarm
        
        return monitoring

    def _create_cluster_config(self) -> Dict[str, any]:
        """
        Create ParallelCluster configuration template
        
        Returns:
            Dict[str, any]: ParallelCluster configuration
        """
        config = {
            "Region": self.region,
            "Image": {
                "Os": "alinux2"
            },
            "HeadNode": {
                "InstanceType": "m5.large",
                "Networking": {
                    "SubnetId": self.vpc.public_subnets[0].subnet_id,
                    "SecurityGroups": [self.security_groups["head_node"].security_group_id],
                },
                "Iam": {
                    "InstanceRole": self.iam_roles["head_node"].role_arn,
                },
                "LocalStorage": {
                    "RootVolume": {
                        "Size": 50,
                        "VolumeType": "gp3",
                        "Encrypted": True,
                    }
                },
            },
            "Scheduling": {
                "Scheduler": "slurm",
                "SlurmSettings": {
                    "ScaledownIdletime": 5,
                    "QueueUpdateStrategy": "TERMINATE",
                },
                "SlurmQueues": [
                    {
                        "Name": "compute",
                        "ComputeResources": [
                            {
                                "Name": "compute-nodes",
                                "InstanceType": "c5n.large",
                                "MinCount": 0,
                                "MaxCount": 10,
                                "DisableSimultaneousMultithreading": True,
                                "Efa": {
                                    "Enabled": True
                                },
                            }
                        ],
                        "Networking": {
                            "SubnetIds": [subnet.subnet_id for subnet in self.vpc.private_subnets],
                            "SecurityGroups": [self.security_groups["compute_node"].security_group_id],
                        },
                        "Iam": {
                            "InstanceRole": self.iam_roles["compute_node"].role_arn,
                        },
                        "ComputeSettings": {
                            "LocalStorage": {
                                "RootVolume": {
                                    "Size": 50,
                                    "VolumeType": "gp3",
                                    "Encrypted": True,
                                }
                            }
                        },
                    }
                ],
            },
            "SharedStorage": [
                {
                    "MountDir": "/shared",
                    "Name": "shared-storage",
                    "StorageType": "Ebs",
                    "EbsSettings": {
                        "Size": 100,
                        "VolumeType": "gp3",
                        "Encrypted": True,
                    },
                }
            ],
            "Monitoring": {
                "CloudWatch": {
                    "Enabled": True,
                    "DashboardName": f"{self.cluster_name}-dashboard",
                },
                "Logs": {
                    "CloudWatch": {
                        "Enabled": True,
                        "LogGroupName": f"/aws/parallelcluster/{self.cluster_name}",
                    }
                },
            },
        }
        
        # Add FSx configuration if enabled
        if self.enable_fsx:
            config["SharedStorage"].append({
                "MountDir": "/fsx",
                "Name": "fsx-storage",
                "StorageType": "FsxLustre",
                "FsxLustreSettings": {
                    "FileSystemId": self.fsx_filesystem.ref,
                },
            })
        
        # Store configuration as a secret for secure access
        config_secret = secretsmanager.Secret(
            self,
            "ClusterConfigSecret",
            secret_name=f"{self.cluster_name}-config",
            description="ParallelCluster configuration",
            secret_string_value=cdk.SecretValue.unsafe_plain_text(json.dumps(config, indent=2)),
        )
        
        return {"config": config, "secret": config_secret}

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        CfnOutput(
            self,
            "VpcId",
            value=self.vpc.vpc_id,
            description="ID of the VPC created for the HPC cluster",
        )
        
        CfnOutput(
            self,
            "PublicSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.vpc.public_subnets]),
            description="IDs of the public subnets",
        )
        
        CfnOutput(
            self,
            "PrivateSubnetIds",
            value=",".join([subnet.subnet_id for subnet in self.vpc.private_subnets]),
            description="IDs of the private subnets",
        )
        
        CfnOutput(
            self,
            "HeadNodeSecurityGroupId",
            value=self.security_groups["head_node"].security_group_id,
            description="Security group ID for the head node",
        )
        
        CfnOutput(
            self,
            "ComputeNodeSecurityGroupId",
            value=self.security_groups["compute_node"].security_group_id,
            description="Security group ID for compute nodes",
        )
        
        CfnOutput(
            self,
            "S3BucketName",
            value=self.s3_bucket.bucket_name,
            description="Name of the S3 bucket for HPC data storage",
        )
        
        CfnOutput(
            self,
            "S3BucketArn",
            value=self.s3_bucket.bucket_arn,
            description="ARN of the S3 bucket for HPC data storage",
        )
        
        CfnOutput(
            self,
            "HeadNodeRoleArn",
            value=self.iam_roles["head_node"].role_arn,
            description="ARN of the IAM role for head node",
        )
        
        CfnOutput(
            self,
            "ComputeNodeRoleArn",
            value=self.iam_roles["compute_node"].role_arn,
            description="ARN of the IAM role for compute nodes",
        )
        
        if self.enable_fsx:
            CfnOutput(
                self,
                "FsxFileSystemId",
                value=self.fsx_filesystem.ref,
                description="ID of the FSx Lustre filesystem",
            )
        
        if self.enable_monitoring:
            CfnOutput(
                self,
                "CloudWatchLogGroupName",
                value=self.monitoring["log_group"].log_group_name,
                description="Name of the CloudWatch log group",
            )
            
            CfnOutput(
                self,
                "CloudWatchDashboardName",
                value=self.monitoring["dashboard"].dashboard_name,
                description="Name of the CloudWatch dashboard",
            )
        
        CfnOutput(
            self,
            "ClusterConfigSecretArn",
            value=self.cluster_config["secret"].secret_arn,
            description="ARN of the secret containing ParallelCluster configuration",
        )


# CDK App
app = cdk.App()

# Get context values with defaults
cluster_name = app.node.try_get_context("cluster_name") or "hpc-cluster"
enable_fsx = app.node.try_get_context("enable_fsx") != "false"
enable_monitoring = app.node.try_get_context("enable_monitoring") != "false"

# Create the stack
stack = HpcParallelClusterStack(
    app,
    "HpcParallelClusterStack",
    cluster_name=cluster_name,
    enable_fsx=enable_fsx,
    enable_monitoring=enable_monitoring,
    description="Infrastructure for AWS ParallelCluster HPC deployment",
)

# Tag all resources
cdk.Tags.of(app).add("Application", "ParallelCluster")
cdk.Tags.of(app).add("Environment", "HPC")
cdk.Tags.of(app).add("ManagedBy", "CDK")

app.synth()