#!/usr/bin/env python3
"""
AWS CDK Python application for optimizing HPC workloads with AWS Batch and Spot Instances.

This application creates a cost-optimized HPC infrastructure using:
- AWS Batch with Spot instances for compute environments
- Amazon EFS for shared storage across compute instances
- CloudWatch monitoring for performance and cost tracking
- IAM roles with least privilege access
- Auto-scaling capabilities from zero to thousands of cores

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Size,
    aws_batch as batch,
    aws_ec2 as ec2,
    aws_ecs as ecs,
    aws_efs as efs,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class HpcBatchSpotStack(Stack):
    """
    CDK Stack for HPC workloads using AWS Batch with Spot Instances.
    
    This stack creates a complete HPC infrastructure with:
    - Spot-optimized compute environments
    - Shared EFS storage
    - CloudWatch monitoring
    - Cost optimization features
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        env: Environment,
        max_vcpus: int = 1000,
        spot_bid_percentage: int = 80,
        **kwargs
    ) -> None:
        """
        Initialize the HPC Batch Spot Stack.
        
        Args:
            scope: CDK app scope
            construct_id: Unique identifier for this stack
            env: AWS environment configuration
            max_vcpus: Maximum vCPUs for compute environment
            spot_bid_percentage: Spot instance bid percentage (0-100)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.max_vcpus = max_vcpus
        self.spot_bid_percentage = spot_bid_percentage

        # Create foundational infrastructure
        self.vpc = self._create_vpc()
        self.security_groups = self._create_security_groups()
        
        # Create storage infrastructure
        self.s3_bucket = self._create_s3_bucket()
        self.efs_filesystem = self._create_efs_storage()
        
        # Create IAM roles
        self.batch_service_role = self._create_batch_service_role()
        self.instance_profile = self._create_instance_profile()
        
        # Create compute infrastructure
        self.compute_environment = self._create_compute_environment()
        self.job_queue = self._create_job_queue()
        self.job_definition = self._create_job_definition()
        
        # Create monitoring
        self.monitoring = self._create_monitoring()
        
        # Create outputs
        self._create_outputs()

    def _create_vpc(self) -> ec2.IVpc:
        """
        Get the default VPC or create a new one if needed.
        
        Returns:
            VPC instance for the HPC infrastructure
        """
        # Use default VPC for simplicity, or create a new one
        return ec2.Vpc.from_lookup(
            self,
            "DefaultVpc",
            is_default=True
        )

    def _create_security_groups(self) -> Dict[str, ec2.SecurityGroup]:
        """
        Create security groups for Batch compute instances and EFS.
        
        Returns:
            Dictionary of security groups
        """
        # Security group for EFS
        efs_sg = ec2.SecurityGroup(
            self,
            "EfsSecurityGroup",
            vpc=self.vpc,
            description="Security group for EFS file system",
            allow_all_outbound=True
        )

        # Security group for Batch compute instances
        batch_sg = ec2.SecurityGroup(
            self,
            "BatchComputeSecurityGroup",
            vpc=self.vpc,
            description="Security group for AWS Batch compute environment",
            allow_all_outbound=True
        )

        # Allow NFS traffic between Batch instances and EFS
        efs_sg.add_ingress_rule(
            peer=batch_sg,
            connection=ec2.Port.tcp(2049),
            description="Allow NFS traffic from Batch compute instances"
        )

        batch_sg.add_egress_rule(
            peer=efs_sg,
            connection=ec2.Port.tcp(2049),
            description="Allow NFS traffic to EFS file system"
        )

        return {
            "efs": efs_sg,
            "batch": batch_sg
        }

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for HPC data storage.
        
        Returns:
            S3 bucket for input/output data
        """
        bucket = s3.Bucket(
            self,
            "HpcDataBucket",
            bucket_name=f"hpc-batch-data-{cdk.Aws.ACCOUNT_ID}-{cdk.Aws.REGION}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldData",
                    status=s3.LifecycleRuleStatus.ENABLED,
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

        cdk.Tags.of(bucket).add("Purpose", "HPC-Data-Storage")
        cdk.Tags.of(bucket).add("CostCenter", "Research")

        return bucket

    def _create_efs_storage(self) -> efs.FileSystem:
        """
        Create EFS file system for shared storage across compute instances.
        
        Returns:
            EFS file system for shared HPC data
        """
        filesystem = efs.FileSystem(
            self,
            "HpcSharedStorage",
            vpc=self.vpc,
            security_group=self.security_groups["efs"],
            performance_mode=efs.PerformanceMode.GENERAL_PURPOSE,
            throughput_mode=efs.ThroughputMode.PROVISIONED,
            provisioned_throughput_per_second=Size.mebibytes(100),
            removal_policy=RemovalPolicy.DESTROY,
            enable_backup_policy=True,
            lifecycle_policy=efs.LifecyclePolicy.TRANSITION_TO_IA_AFTER_30_DAYS
        )

        # Create mount targets in all subnets
        for i, subnet in enumerate(self.vpc.private_subnets):
            efs.MountTarget(
                self,
                f"EfsMountTarget{i}",
                file_system=filesystem,
                subnet=subnet,
                security_group=self.security_groups["efs"]
            )

        cdk.Tags.of(filesystem).add("Purpose", "HPC-Shared-Storage")
        cdk.Tags.of(filesystem).add("CostCenter", "Research")

        return filesystem

    def _create_batch_service_role(self) -> iam.Role:
        """
        Create IAM role for AWS Batch service.
        
        Returns:
            IAM role for Batch service operations
        """
        role = iam.Role(
            self,
            "BatchServiceRole",
            assumed_by=iam.ServicePrincipal("batch.amazonaws.com"),
            description="AWS Batch service role for HPC workloads",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBatchServiceRole"
                )
            ]
        )

        cdk.Tags.of(role).add("Purpose", "BatchService")
        return role

    def _create_instance_profile(self) -> iam.CfnInstanceProfile:
        """
        Create IAM instance profile for EC2 instances.
        
        Returns:
            IAM instance profile for Batch compute instances
        """
        # Create role for EC2 instances
        instance_role = iam.Role(
            self,
            "EcsInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for Batch compute instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2ContainerServiceforEC2Role"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "CloudWatchAgentServerPolicy"
                )
            ]
        )

        # Add S3 access for data operations
        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*"
                ]
            )
        )

        # Create instance profile
        instance_profile = iam.CfnInstanceProfile(
            self,
            "EcsInstanceProfile",
            roles=[instance_role.role_name],
            instance_profile_name=f"ecsInstanceProfile-{cdk.Aws.STACK_NAME}"
        )

        cdk.Tags.of(instance_role).add("Purpose", "BatchCompute")
        return instance_profile

    def _create_compute_environment(self) -> batch.CfnComputeEnvironment:
        """
        Create AWS Batch compute environment with Spot instances.
        
        Returns:
            Batch compute environment optimized for Spot instances
        """
        # Define instance types for diversified Spot allocation
        instance_types = [
            "c5.large", "c5.xlarge", "c5.2xlarge", "c5.4xlarge",
            "c4.large", "c4.xlarge", "c4.2xlarge",
            "m5.large", "m5.xlarge", "m5.2xlarge",
            "m4.large", "m4.xlarge", "m4.2xlarge"
        ]

        compute_environment = batch.CfnComputeEnvironment(
            self,
            "HpcSpotComputeEnvironment",
            type="MANAGED",
            state="ENABLED",
            service_role=self.batch_service_role.role_arn,
            compute_environment_name=f"hpc-spot-compute-{cdk.Aws.STACK_NAME}",
            compute_resources=batch.CfnComputeEnvironment.ComputeResourcesProperty(
                type="EC2",
                allocation_strategy="SPOT_CAPACITY_OPTIMIZED",
                min_vcpus=0,
                max_vcpus=self.max_vcpus,
                desired_vcpus=0,
                instance_types=instance_types,
                spot_iam_fleet_request_role=f"arn:aws:iam::{cdk.Aws.ACCOUNT_ID}:role/aws-ec2-spot-fleet-tagging-role",
                bid_percentage=self.spot_bid_percentage,
                ec2_configuration=[
                    batch.CfnComputeEnvironment.Ec2ConfigurationObjectProperty(
                        image_type="ECS_AL2"
                    )
                ],
                subnets=[subnet.subnet_id for subnet in self.vpc.private_subnets],
                security_group_ids=[self.security_groups["batch"].security_group_id],
                instance_role=self.instance_profile.attr_arn,
                tags={
                    "Name": f"HPC-Batch-Instance-{cdk.Aws.STACK_NAME}",
                    "Purpose": "HPC-Compute",
                    "CostCenter": "Research",
                    "Environment": "HPC"
                }
            )
        )

        return compute_environment

    def _create_job_queue(self) -> batch.CfnJobQueue:
        """
        Create AWS Batch job queue.
        
        Returns:
            Batch job queue for HPC workloads
        """
        job_queue = batch.CfnJobQueue(
            self,
            "HpcJobQueue",
            job_queue_name=f"hpc-job-queue-{cdk.Aws.STACK_NAME}",
            state="ENABLED",
            priority=1,
            compute_environment_order=[
                batch.CfnJobQueue.ComputeEnvironmentOrderProperty(
                    order=1,
                    compute_environment=self.compute_environment.ref
                )
            ]
        )

        # Ensure compute environment is created first
        job_queue.add_dependency(self.compute_environment)

        return job_queue

    def _create_job_definition(self) -> batch.CfnJobDefinition:
        """
        Create AWS Batch job definition for HPC workloads.
        
        Returns:
            Batch job definition with EFS mounting and fault tolerance
        """
        job_definition = batch.CfnJobDefinition(
            self,
            "HpcJobDefinition",
            job_definition_name=f"hpc-simulation-{cdk.Aws.STACK_NAME}",
            type="container",
            container_properties=batch.CfnJobDefinition.ContainerPropertiesProperty(
                image="public.ecr.aws/amazonlinux/amazonlinux:latest",
                vcpus=2,
                memory=4096,
                job_role_arn=self.instance_profile.attr_arn,
                command=[
                    "sh", "-c",
                    "echo 'Starting HPC simulation at' $(date); "
                    "echo 'Shared storage mounted at /shared'; "
                    "echo 'S3 bucket available at $S3_BUCKET'; "
                    "sleep 300; "
                    "echo 'Simulation completed at' $(date)"
                ],
                mount_points=[
                    batch.CfnJobDefinition.MountPointsProperty(
                        source_volume="efs-storage",
                        container_path="/shared",
                        read_only=False
                    )
                ],
                volumes=[
                    batch.CfnJobDefinition.VolumesProperty(
                        name="efs-storage",
                        efs_volume_configuration=batch.CfnJobDefinition.EfsVolumeConfigurationProperty(
                            file_system_id=self.efs_filesystem.file_system_id
                        )
                    )
                ],
                environment=[
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="S3_BUCKET",
                        value=self.s3_bucket.bucket_name
                    ),
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="AWS_DEFAULT_REGION",
                        value=cdk.Aws.REGION
                    ),
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="EFS_MOUNT_POINT",
                        value="/shared"
                    )
                ]
            ),
            retry_strategy=batch.CfnJobDefinition.RetryStrategyProperty(
                attempts=3
            ),
            timeout=batch.CfnJobDefinition.TimeoutProperty(
                attempt_duration_seconds=3600
            )
        )

        return job_definition

    def _create_monitoring(self) -> Dict[str, cloudwatch.Alarm]:
        """
        Create CloudWatch monitoring for the HPC infrastructure.
        
        Returns:
            Dictionary of CloudWatch alarms
        """
        # Create log group for Batch jobs
        log_group = logs.LogGroup(
            self,
            "BatchJobLogGroup",
            log_group_name="/aws/batch/job",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create alarm for failed jobs
        failed_jobs_alarm = cloudwatch.Alarm(
            self,
            "FailedJobsAlarm",
            alarm_name=f"HPC-Batch-FailedJobs-{cdk.Aws.STACK_NAME}",
            alarm_description="Alert when Batch jobs fail",
            metric=cloudwatch.Metric(
                namespace="AWS/Batch",
                metric_name="FailedJobs",
                dimensions_map={
                    "JobQueue": self.job_queue.job_queue_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1
        )

        # Create alarm for Spot interruptions
        spot_interruption_alarm = cloudwatch.Alarm(
            self,
            "SpotInterruptionAlarm",
            alarm_name=f"HPC-Spot-Interruptions-{cdk.Aws.STACK_NAME}",
            alarm_description="Alert when Spot instances are interrupted",
            metric=cloudwatch.Metric(
                namespace="AWS/EC2Spot",
                metric_name="InterruptionNotifications",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=3,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1
        )

        return {
            "failed_jobs": failed_jobs_alarm,
            "spot_interruptions": spot_interruption_alarm
        }

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "S3BucketName",
            description="S3 bucket for HPC data storage",
            value=self.s3_bucket.bucket_name
        )

        CfnOutput(
            self,
            "EfsFileSystemId",
            description="EFS file system ID for shared storage",
            value=self.efs_filesystem.file_system_id
        )

        CfnOutput(
            self,
            "ComputeEnvironmentName",
            description="AWS Batch compute environment name",
            value=self.compute_environment.compute_environment_name or ""
        )

        CfnOutput(
            self,
            "JobQueueName",
            description="AWS Batch job queue name",
            value=self.job_queue.job_queue_name or ""
        )

        CfnOutput(
            self,
            "JobDefinitionName",
            description="AWS Batch job definition name",
            value=self.job_definition.job_definition_name or ""
        )

        CfnOutput(
            self,
            "MaxVcpus",
            description="Maximum vCPUs configured for compute environment",
            value=str(self.max_vcpus)
        )

        CfnOutput(
            self,
            "SpotBidPercentage",
            description="Spot instance bid percentage",
            value=str(self.spot_bid_percentage)
        )


def main() -> None:
    """Main function to create and deploy the CDK app."""
    app = cdk.App()

    # Get configuration from context or environment variables
    max_vcpus = int(app.node.try_get_context("max_vcpus") or os.environ.get("MAX_VCPUS", "1000"))
    spot_bid_percentage = int(app.node.try_get_context("spot_bid_percentage") or os.environ.get("SPOT_BID_PERCENTAGE", "80"))
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )

    # Create the stack
    HpcBatchSpotStack(
        app,
        "HpcBatchSpotStack",
        env=env,
        max_vcpus=max_vcpus,
        spot_bid_percentage=spot_bid_percentage,
        description="HPC workloads optimization with AWS Batch and Spot Instances"
    )

    app.synth()


if __name__ == "__main__":
    main()