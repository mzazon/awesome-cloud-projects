#!/usr/bin/env python3
"""
AWS CDK Application for Scientific Computing with Batch Multi-Node

This CDK application deploys a complete infrastructure for running distributed scientific
computing workloads using AWS Batch multi-node parallel jobs with MPI support.

The architecture includes:
- VPC with enhanced networking for MPI communication
- AWS Batch compute environment optimized for multi-node parallel jobs
- ECR repository for containerized MPI applications
- EFS shared filesystem for distributed data access
- IAM roles and security groups with least privilege access
- CloudWatch monitoring and logging

Author: AWS CDK Python Generator
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Tags,
    Duration,
    Size,
    RemovalPolicy,
    CfnOutput,
    aws_batch as batch,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_ecr as ecr,
    aws_efs as efs,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class DistributedScientificComputingStack(Stack):
    """
    AWS CDK Stack for Distributed Scientific Computing with Batch Multi-Node Jobs
    
    This stack creates all the necessary AWS resources for running distributed
    scientific computing workloads using AWS Batch multi-node parallel jobs.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        cluster_name: Optional[str] = None,
        enable_spot_instances: bool = True,
        max_vcpus: int = 256,
        efs_throughput_mibps: int = 100,
        **kwargs
    ) -> None:
        """
        Initialize the Distributed Scientific Computing Stack
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            cluster_name: Optional name for the computing cluster
            enable_spot_instances: Whether to enable spot instances for cost optimization
            max_vcpus: Maximum number of vCPUs for the compute environment
            efs_throughput_mibps: EFS provisioned throughput in MiB/s
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Set default cluster name if not provided
        self.cluster_name = cluster_name or f"sci-computing-{construct_id.lower()}"
        self.enable_spot_instances = enable_spot_instances
        self.max_vcpus = max_vcpus
        self.efs_throughput_mibps = efs_throughput_mibps

        # Create networking infrastructure
        self.vpc = self._create_vpc()
        self.security_groups = self._create_security_groups()

        # Create shared storage
        self.efs_filesystem = self._create_efs_filesystem()

        # Create container registry
        self.ecr_repository = self._create_ecr_repository()

        # Create IAM roles
        self.iam_roles = self._create_iam_roles()

        # Create Batch infrastructure
        self.compute_environment = self._create_batch_compute_environment()
        self.job_queue = self._create_batch_job_queue()
        self.job_definitions = self._create_batch_job_definitions()

        # Create monitoring and logging
        self._create_monitoring()

        # Apply tags to all resources
        self._apply_tags()

        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with enhanced networking capabilities for MPI communication
        
        Returns:
            ec2.Vpc: The created VPC with public and private subnets
        """
        vpc = ec2.Vpc(
            self,
            "BatchVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=3,  # Multi-AZ for high availability
            nat_gateways=2,  # HA NAT gateways for redundancy
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="Private",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=22,  # Larger subnets for compute resources
                ),
            ],
            # Enable DNS hostnames and resolution for MPI communication
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )

        # Enable VPC Flow Logs for security monitoring
        flow_log_group = logs.LogGroup(
            self,
            "VPCFlowLogGroup",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        ec2.FlowLog(
            self,
            "VPCFlowLogs",
            resource_type=ec2.FlowLogResourceType.from_vpc(vpc),
            destination=ec2.FlowLogDestination.to_cloud_watch_logs(flow_log_group),
            traffic_type=ec2.FlowLogTrafficType.ALL,
        )

        return vpc

    def _create_security_groups(self) -> dict:
        """
        Create security groups for Batch compute instances and EFS
        
        Returns:
            dict: Dictionary containing the created security groups
        """
        # Security group for Batch compute instances
        batch_sg = ec2.SecurityGroup(
            self,
            "BatchComputeSecurityGroup",
            vpc=self.vpc,
            description="Security group for Batch compute instances",
            allow_all_outbound=False,  # Explicitly define outbound rules
        )

        # Allow outbound HTTPS for package downloads and ECR access
        batch_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(443),
            description="HTTPS outbound for package downloads",
        )

        # Allow outbound HTTP for package repositories
        batch_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(80),
            description="HTTP outbound for package repositories",
        )

        # Allow outbound DNS
        batch_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.tcp(53),
            description="DNS TCP",
        )
        batch_sg.add_egress_rule(
            peer=ec2.Peer.any_ipv4(),
            connection=ec2.Port.udp(53),
            description="DNS UDP",
        )

        # Allow all communication within the security group for MPI
        batch_sg.add_ingress_rule(
            peer=batch_sg,
            connection=ec2.Port.all_traffic(),
            description="MPI inter-node communication",
        )

        # Security group for EFS
        efs_sg = ec2.SecurityGroup(
            self,
            "EFSSecurityGroup",
            vpc=self.vpc,
            description="Security group for EFS access",
            allow_all_outbound=False,
        )

        # Allow NFS traffic from Batch compute instances
        efs_sg.add_ingress_rule(
            peer=batch_sg,
            connection=ec2.Port.tcp(2049),
            description="NFS access from Batch compute instances",
        )

        # Allow EFS outbound to Batch security group
        batch_sg.add_egress_rule(
            peer=efs_sg,
            connection=ec2.Port.tcp(2049),
            description="NFS access to EFS",
        )

        return {
            "batch": batch_sg,
            "efs": efs_sg,
        }

    def _create_efs_filesystem(self) -> efs.FileSystem:
        """
        Create an EFS filesystem for shared data storage across compute nodes
        
        Returns:
            efs.FileSystem: The created EFS filesystem
        """
        filesystem = efs.FileSystem(
            self,
            "SharedFileSystem",
            vpc=self.vpc,
            # Enable encryption at rest and in transit
            encrypted=True,
            # Use provisioned throughput for predictable performance
            throughput_mode=efs.ThroughputMode.PROVISIONED,
            provisioned_throughput_per_second=Size.mebibytes(self.efs_throughput_mibps),
            # Use General Purpose for most scientific workloads
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            # Enable backup policy
            enable_backup_policy=True,
            # Configure lifecycle policies for cost optimization
            lifecycle_policy=efs.LifecyclePolicy.AFTER_30_DAYS,
            transition_to_archive_policy=efs.LifecyclePolicy.AFTER_90_DAYS,
            # Use the EFS security group
            security_group=self.security_groups["efs"],
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create access point for controlled access
        efs.AccessPoint(
            self,
            "BatchAccessPoint",
            file_system=filesystem,
            path="/batch-data",
            creation_info=efs.CreationInfo(
                owner_uid=1001,
                owner_gid=1001,
                permissions="755",
            ),
            posix_user=efs.PosixUser(uid=1001, gid=1001),
        )

        return filesystem

    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create an ECR repository for storing MPI container images
        
        Returns:
            ecr.Repository: The created ECR repository
        """
        repository = ecr.Repository(
            self,
            "BatchMPIRepository",
            repository_name=f"{self.cluster_name}-mpi-workloads",
            # Enable image scanning for security
            image_scan_on_push=True,
            # Enable immutable tags for security
            image_tag_mutability=ecr.TagMutability.IMMUTABLE,
            # Set lifecycle policy for cost management
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only 10 latest images",
                    max_image_count=10,
                    rule_priority=1,
                ),
                ecr.LifecycleRule(
                    description="Delete untagged images after 1 day",
                    max_image_age=Duration.days(1),
                    rule_priority=2,
                    tag_status=ecr.TagStatus.UNTAGGED,
                ),
            ],
            # Enable encryption
            encryption=ecr.RepositoryEncryption.AES_256,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Add repository policy for secure access
        repository.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[
                    iam.ServicePrincipal("batch.amazonaws.com"),
                    iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
                ],
                actions=[
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:BatchCheckLayerAvailability",
                ],
            )
        )

        return repository

    def _create_iam_roles(self) -> dict:
        """
        Create IAM roles for Batch service and compute instances
        
        Returns:
            dict: Dictionary containing the created IAM roles
        """
        # Batch service role
        batch_service_role = iam.Role(
            self,
            "BatchServiceRole",
            role_name=f"{self.cluster_name}-batch-service-role",
            assumed_by=iam.ServicePrincipal("batch.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBatchServiceRole"
                )
            ],
        )

        # EC2 instance role for Batch compute instances
        batch_instance_role = iam.Role(
            self,
            "BatchInstanceRole",
            role_name=f"{self.cluster_name}-batch-instance-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2ContainerServiceforEC2Role"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonSSMManagedInstanceCore"
                ),
            ],
        )

        # Add EFS access permissions to instance role
        batch_instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "elasticfilesystem:ClientMount",
                    "elasticfilesystem:ClientWrite",
                    "elasticfilesystem:ClientRootAccess",
                ],
                resources=[self.efs_filesystem.file_system_arn],
            )
        )

        # Instance profile for EC2 instances
        batch_instance_profile = iam.CfnInstanceProfile(
            self,
            "BatchInstanceProfile",
            instance_profile_name=f"{self.cluster_name}-batch-instance-profile",
            roles=[batch_instance_role.role_name],
        )

        # Task execution role for ECS tasks
        task_execution_role = iam.Role(
            self,
            "TaskExecutionRole",
            role_name=f"{self.cluster_name}-task-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )

        # Task role for runtime permissions
        task_role = iam.Role(
            self,
            "TaskRole",
            role_name=f"{self.cluster_name}-task-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
        )

        # Add EFS access permissions to task role
        task_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "elasticfilesystem:ClientMount",
                    "elasticfilesystem:ClientWrite",
                    "elasticfilesystem:ClientRootAccess",
                ],
                resources=[self.efs_filesystem.file_system_arn],
            )
        )

        return {
            "service": batch_service_role,
            "instance": batch_instance_role,
            "instance_profile": batch_instance_profile,
            "task_execution": task_execution_role,
            "task": task_role,
        }

    def _create_batch_compute_environment(self) -> batch.ManagedEc2EcsComputeEnvironment:
        """
        Create a Batch compute environment optimized for multi-node parallel jobs
        
        Returns:
            batch.ManagedEc2EcsComputeEnvironment: The created compute environment
        """
        # Choose instance types optimized for networking and MPI workloads
        instance_types = [
            ec2.InstanceType.of(ec2.InstanceClass.C5N, ec2.InstanceSize.LARGE),
            ec2.InstanceType.of(ec2.InstanceClass.C5N, ec2.InstanceSize.XLARGE),
            ec2.InstanceType.of(ec2.InstanceClass.C5N, ec2.InstanceSize.XLARGE2),
            ec2.InstanceType.of(ec2.InstanceClass.R5N, ec2.InstanceSize.LARGE),
            ec2.InstanceType.of(ec2.InstanceClass.R5N, ec2.InstanceSize.XLARGE),
        ]

        compute_env = batch.ManagedEc2EcsComputeEnvironment(
            self,
            "MPIComputeEnvironment",
            compute_environment_name=f"{self.cluster_name}-compute-env",
            vpc=self.vpc,
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
            instance_types=instance_types,
            security_groups=[self.security_groups["batch"]],
            service_role=self.iam_roles["service"],
            instance_profile=self.iam_roles["instance_profile"],
            # Configure scaling
            min_v_cpus=0,
            max_v_cpus=self.max_vcpus,
            desired_v_cpus=0,
            # Use spot instances for cost optimization if enabled
            spot=self.enable_spot_instances,
            spot_bid_percentage=80 if self.enable_spot_instances else None,
            # Use BEST_FIT_PROGRESSIVE for optimal resource allocation
            allocation_strategy=batch.AllocationStrategy.BEST_FIT_PROGRESSIVE,
            # Enable managed instance termination for automatic cleanup
            managed=True,
        )

        return compute_env

    def _create_batch_job_queue(self) -> batch.JobQueue:
        """
        Create a Batch job queue for submitting multi-node parallel jobs
        
        Returns:
            batch.JobQueue: The created job queue
        """
        job_queue = batch.JobQueue(
            self,
            "ScientificJobQueue",
            job_queue_name=f"{self.cluster_name}-job-queue",
            compute_environments=[
                batch.OrderedComputeEnvironment(
                    compute_environment=self.compute_environment,
                    order=1,
                )
            ],
            priority=1,
            enabled=True,
        )

        return job_queue

    def _create_batch_job_definitions(self) -> dict:
        """
        Create Batch job definitions for multi-node parallel jobs
        
        Returns:
            dict: Dictionary containing the created job definitions
        """
        # Basic multi-node job definition
        basic_job_def = batch.EcsJobDefinition(
            self,
            "BasicMPIJobDefinition",
            job_definition_name=f"{self.cluster_name}-basic-mpi-job",
            container=batch.EcsEc2ContainerDefinition(
                self,
                "BasicMPIContainer",
                image=ecs.ContainerImage.from_ecr_repository(
                    self.ecr_repository, tag="latest"
                ),
                cpu=2,
                memory=Size.mebibytes(4096),
                privileged=True,  # Required for MPI communication
                execution_role=self.iam_roles["task_execution"],
                job_role=self.iam_roles["task"],
                environment={
                    "EFS_DNS_NAME": f"{self.efs_filesystem.file_system_id}.efs.{self.region}.amazonaws.com",
                    "EFS_MOUNT_POINT": "/mnt/efs",
                    "OMPI_ALLOW_RUN_AS_ROOT": "1",
                    "OMPI_ALLOW_RUN_AS_ROOT_CONFIRM": "1",
                },
                logging=ecs.LogDriver.aws_logs(
                    stream_prefix="batch-mpi",
                    log_retention=logs.RetentionDays.ONE_WEEK,
                ),
            ),
            timeout=Duration.hours(2),
            retry_attempts=1,
        )

        # Multi-node parallel job definition
        multi_node_job_def = batch.MultiNodeJobDefinition(
            self,
            "MultiNodeMPIJobDefinition",
            job_definition_name=f"{self.cluster_name}-multi-node-mpi",
            main_node=0,
            node_properties=batch.NodeProperties(
                main_node=0,
                num_nodes=2,
                node_range_properties=[
                    batch.NodeRangeProperty(
                        target_nodes="0:",
                        container=batch.EcsEc2ContainerDefinition(
                            self,
                            "MultiNodeMPIContainer",
                            image=ecs.ContainerImage.from_ecr_repository(
                                self.ecr_repository, tag="latest"
                            ),
                            cpu=4,
                            memory=Size.mebibytes(8192),
                            privileged=True,
                            execution_role=self.iam_roles["task_execution"],
                            job_role=self.iam_roles["task"],
                            environment={
                                "EFS_DNS_NAME": f"{self.efs_filesystem.file_system_id}.efs.{self.region}.amazonaws.com",
                                "EFS_MOUNT_POINT": "/mnt/efs",
                                "OMPI_ALLOW_RUN_AS_ROOT": "1",
                                "OMPI_ALLOW_RUN_AS_ROOT_CONFIRM": "1",
                            },
                            logging=ecs.LogDriver.aws_logs(
                                stream_prefix="batch-multi-node-mpi",
                                log_retention=logs.RetentionDays.ONE_WEEK,
                            ),
                        ),
                    )
                ],
            ),
            timeout=Duration.hours(4),
            retry_attempts=1,
        )

        return {
            "basic": basic_job_def,
            "multi_node": multi_node_job_def,
        }

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms for the Batch infrastructure"""
        # CloudWatch dashboard for monitoring
        dashboard = cloudwatch.Dashboard(
            self,
            "BatchMonitoringDashboard",
            dashboard_name=f"{self.cluster_name}-monitoring",
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Batch Job Status",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Batch",
                        metric_name="SubmittedJobs",
                        dimensions_map={"JobQueue": self.job_queue.job_queue_name},
                        statistic="Sum",
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Batch",
                        metric_name="RunnableJobs",
                        dimensions_map={"JobQueue": self.job_queue.job_queue_name},
                        statistic="Sum",
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Batch",
                        metric_name="RunningJobs",
                        dimensions_map={"JobQueue": self.job_queue.job_queue_name},
                        statistic="Sum",
                    ),
                ],
                period=Duration.minutes(5),
            ),
            cloudwatch.GraphWidget(
                title="Compute Environment Utilization",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Batch",
                        metric_name="DesiredvCpus",
                        dimensions_map={
                            "ComputeEnvironment": self.compute_environment.compute_environment_name
                        },
                        statistic="Average",
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Batch",
                        metric_name="RunnablevCpus",
                        dimensions_map={
                            "ComputeEnvironment": self.compute_environment.compute_environment_name
                        },
                        statistic="Average",
                    ),
                ],
                period=Duration.minutes(5),
            ),
        )

        # CloudWatch alarm for failed jobs
        cloudwatch.Alarm(
            self,
            "FailedJobsAlarm",
            alarm_name=f"{self.cluster_name}-failed-jobs",
            alarm_description="Alert when Batch jobs fail",
            metric=cloudwatch.Metric(
                namespace="AWS/Batch",
                metric_name="FailedJobs",
                dimensions_map={"JobQueue": self.job_queue.job_queue_name},
                statistic="Sum",
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack"""
        Tags.of(self).add("Project", "distributed-scientific-computing")
        Tags.of(self).add("Environment", "development")
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("ClusterName", self.cluster_name)
        Tags.of(self).add("Purpose", "multi-node-parallel-computing")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the distributed computing environment",
        )

        CfnOutput(
            self,
            "ComputeEnvironmentName",
            value=self.compute_environment.compute_environment_name,
            description="Name of the Batch compute environment",
        )

        CfnOutput(
            self,
            "JobQueueName",
            value=self.job_queue.job_queue_name,
            description="Name of the Batch job queue",
        )

        CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="URI of the ECR repository for MPI container images",
        )

        CfnOutput(
            self,
            "EFSFileSystemId",
            value=self.efs_filesystem.file_system_id,
            description="ID of the EFS filesystem for shared data storage",
        )

        CfnOutput(
            self,
            "BasicJobDefinitionArn",
            value=self.job_definitions["basic"].job_definition_arn,
            description="ARN of the basic MPI job definition",
        )

        CfnOutput(
            self,
            "MultiNodeJobDefinitionArn",
            value=self.job_definitions["multi_node"].job_definition_arn,
            description="ARN of the multi-node MPI job definition",
        )


def main() -> None:
    """Main function to create and deploy the CDK application"""
    app = cdk.App()

    # Create the stack with environment configuration
    DistributedScientificComputingStack(
        app,
        "DistributedScientificComputingStack",
        env=cdk.Environment(
            account=os.getenv("CDK_DEFAULT_ACCOUNT"),
            region=os.getenv("CDK_DEFAULT_REGION"),
        ),
        # Customizable parameters
        cluster_name="scientific-computing-cluster",
        enable_spot_instances=True,
        max_vcpus=256,
        efs_throughput_mibps=100,
    )

    app.synth()


if __name__ == "__main__":
    main()