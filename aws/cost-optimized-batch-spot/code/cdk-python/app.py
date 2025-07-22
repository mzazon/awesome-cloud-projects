#!/usr/bin/env python3
"""
Cost-Optimized Batch Processing with AWS Batch and Spot Instances

This CDK application creates a complete infrastructure for cost-optimized batch processing
using AWS Batch with EC2 Spot Instances. It includes:
- ECR repository for container images
- IAM roles with proper permissions
- VPC and networking components
- AWS Batch compute environment configured for Spot instances
- Job queue and job definition with retry strategies
- CloudWatch logging and monitoring
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    aws_batch as batch,
    aws_ec2 as ec2,
    aws_ecr as ecr,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
)
from constructs import Construct
from typing import Dict, List, Optional


class CostOptimizedBatchProcessingStack(Stack):
    """
    CDK Stack for cost-optimized batch processing with AWS Batch and Spot Instances.
    
    This stack implements a complete batch processing solution optimized for cost
    efficiency using EC2 Spot Instances while maintaining reliability through
    intelligent retry strategies and fault tolerance mechanisms.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc: Optional[ec2.Vpc] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.stack_name = construct_id
        self.region = self.region
        self.account = self.account

        # Create VPC or use existing one
        if vpc is None:
            self.vpc = self._create_vpc()
        else:
            self.vpc = vpc

        # Create ECR repository for batch applications
        self.ecr_repository = self._create_ecr_repository()

        # Create IAM roles
        self.batch_service_role = self._create_batch_service_role()
        self.instance_role = self._create_instance_role()
        self.instance_profile = self._create_instance_profile()
        self.job_execution_role = self._create_job_execution_role()

        # Create security group for batch instances
        self.security_group = self._create_security_group()

        # Create S3 bucket for job artifacts (optional)
        self.artifacts_bucket = self._create_artifacts_bucket()

        # Create CloudWatch log group
        self.log_group = self._create_log_group()

        # Create AWS Batch resources
        self.compute_environment = self._create_compute_environment()
        self.job_queue = self._create_job_queue()
        self.job_definition = self._create_job_definition()

        # Create outputs
        self._create_outputs()

        # Apply tags
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create a VPC with public and private subnets."""
        return ec2.Vpc(
            self,
            "BatchVPC",
            max_azs=2,
            cidr="10.0.0.0/16",
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

    def _create_ecr_repository(self) -> ecr.Repository:
        """Create ECR repository for batch application container images."""
        return ecr.Repository(
            self,
            "BatchRepository",
            repository_name=f"{self.stack_name}-batch-app",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    rule_priority=1,
                    description="Keep last 10 images",
                    max_image_count=10,
                ),
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_batch_service_role(self) -> iam.Role:
        """Create IAM role for AWS Batch service."""
        return iam.Role(
            self,
            "BatchServiceRole",
            role_name=f"{self.stack_name}-batch-service-role",
            assumed_by=iam.ServicePrincipal("batch.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBatchServiceRole"
                ),
            ],
        )

    def _create_instance_role(self) -> iam.Role:
        """Create IAM role for EC2 instances in the compute environment."""
        return iam.Role(
            self,
            "InstanceRole",
            role_name=f"{self.stack_name}-instance-role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2ContainerServiceforEC2Role"
                ),
            ],
        )

    def _create_instance_profile(self) -> iam.CfnInstanceProfile:
        """Create instance profile for EC2 instances."""
        return iam.CfnInstanceProfile(
            self,
            "InstanceProfile",
            instance_profile_name=f"{self.stack_name}-instance-profile",
            roles=[self.instance_role.role_name],
        )

    def _create_job_execution_role(self) -> iam.Role:
        """Create IAM role for job execution."""
        role = iam.Role(
            self,
            "JobExecutionRole",
            role_name=f"{self.stack_name}-job-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                ),
            ],
        )

        # Add permissions for S3 access (for job artifacts)
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                ],
                resources=[
                    f"{self.artifacts_bucket.bucket_arn}/*",
                ],
            )
        )

        return role

    def _create_security_group(self) -> ec2.SecurityGroup:
        """Create security group for batch instances."""
        return ec2.SecurityGroup(
            self,
            "BatchSecurityGroup",
            vpc=self.vpc,
            description="Security group for AWS Batch instances",
            security_group_name=f"{self.stack_name}-batch-sg",
            allow_all_outbound=True,
        )

    def _create_artifacts_bucket(self) -> s3.Bucket:
        """Create S3 bucket for job artifacts and logs."""
        return s3.Bucket(
            self,
            "ArtifactsBucket",
            bucket_name=f"{self.stack_name}-batch-artifacts-{self.account}-{self.region}",
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldVersions",
                    enabled=True,
                    noncurrent_version_expiration=Duration.days(30),
                ),
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
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

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for batch jobs."""
        return logs.LogGroup(
            self,
            "BatchLogGroup",
            log_group_name=f"/aws/batch/{self.stack_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _create_compute_environment(self) -> batch.CfnComputeEnvironment:
        """Create AWS Batch compute environment optimized for Spot instances."""
        return batch.CfnComputeEnvironment(
            self,
            "SpotComputeEnvironment",
            compute_environment_name=f"{self.stack_name}-spot-compute-env",
            type="MANAGED",
            state="ENABLED",
            service_role=self.batch_service_role.role_arn,
            compute_resources=batch.CfnComputeEnvironment.ComputeResourcesProperty(
                type="EC2",
                min_v_cpus=0,
                max_v_cpus=256,
                desired_v_cpus=0,
                instance_types=[
                    "c5.large",
                    "c5.xlarge",
                    "c5.2xlarge",
                    "c5.4xlarge",
                    "m5.large",
                    "m5.xlarge",
                    "m5.2xlarge",
                    "m5.4xlarge",
                    "r5.large",
                    "r5.xlarge",
                    "r5.2xlarge",
                ],
                allocation_strategy="SPOT_CAPACITY_OPTIMIZED",
                bid_percentage=80,  # Maximum 80% of On-Demand price
                ec2_configuration=[
                    batch.CfnComputeEnvironment.Ec2ConfigurationObjectProperty(
                        image_type="ECS_AL2",
                    )
                ],
                subnets=[subnet.subnet_id for subnet in self.vpc.private_subnets],
                security_group_ids=[self.security_group.security_group_id],
                instance_role=self.instance_profile.attr_arn,
                tags={
                    "Name": f"{self.stack_name}-batch-instance",
                    "Environment": "cost-optimized",
                    "BatchComputeEnvironment": f"{self.stack_name}-spot-compute-env",
                },
            ),
        )

    def _create_job_queue(self) -> batch.CfnJobQueue:
        """Create AWS Batch job queue."""
        return batch.CfnJobQueue(
            self,
            "BatchJobQueue",
            job_queue_name=f"{self.stack_name}-job-queue",
            state="ENABLED",
            priority=1,
            compute_environment_order=[
                batch.CfnJobQueue.ComputeEnvironmentOrderProperty(
                    order=1,
                    compute_environment=self.compute_environment.ref,
                )
            ],
        )

    def _create_job_definition(self) -> batch.CfnJobDefinition:
        """Create AWS Batch job definition with retry strategy for Spot instances."""
        return batch.CfnJobDefinition(
            self,
            "BatchJobDefinition",
            job_definition_name=f"{self.stack_name}-job-definition",
            type="container",
            container_properties=batch.CfnJobDefinition.ContainerPropertiesProperty(
                image=f"{self.ecr_repository.repository_uri}:latest",
                vcpus=1,
                memory=2048,
                job_role_arn=self.job_execution_role.role_arn,
                log_configuration=batch.CfnJobDefinition.LogConfigurationProperty(
                    log_driver="awslogs",
                    options={
                        "awslogs-group": self.log_group.log_group_name,
                        "awslogs-region": self.region,
                        "awslogs-stream-prefix": "batch",
                    },
                ),
                environment=[
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="AWS_DEFAULT_REGION",
                        value=self.region,
                    ),
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="ARTIFACTS_BUCKET",
                        value=self.artifacts_bucket.bucket_name,
                    ),
                ],
                mount_points=[],
                volumes=[],
                ulimits=[],
            ),
            retry_strategy=batch.CfnJobDefinition.RetryStrategyProperty(
                attempts=3,
                evaluate_on_exit=[
                    batch.CfnJobDefinition.EvaluateOnExitProperty(
                        action="RETRY",
                        on_status_reason="Host EC2*",  # Retry on Spot interruptions
                    ),
                    batch.CfnJobDefinition.EvaluateOnExitProperty(
                        action="EXIT",
                        on_reason="*",  # Exit on all other failures
                    ),
                ],
            ),
            timeout=batch.CfnJobDefinition.TimeoutProperty(
                attempt_duration_seconds=3600,  # 1 hour timeout
            ),
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="ECR Repository URI for batch application images",
        )

        CfnOutput(
            self,
            "JobQueueName",
            value=self.job_queue.job_queue_name,
            description="AWS Batch Job Queue Name",
        )

        CfnOutput(
            self,
            "JobDefinitionName",
            value=self.job_definition.job_definition_name,
            description="AWS Batch Job Definition Name",
        )

        CfnOutput(
            self,
            "ComputeEnvironmentName",
            value=self.compute_environment.compute_environment_name,
            description="AWS Batch Compute Environment Name",
        )

        CfnOutput(
            self,
            "ArtifactsBucketName",
            value=self.artifacts_bucket.bucket_name,
            description="S3 Bucket for job artifacts",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for batch jobs",
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all resources."""
        Tags.of(self).add("Project", "CostOptimizedBatchProcessing")
        Tags.of(self).add("Environment", "demo")
        Tags.of(self).add("CostCenter", "batch-processing")
        Tags.of(self).add("Owner", "aws-batch-demo")
        Tags.of(self).add("AutoDelete", "true")


def main() -> None:
    """Main application entry point."""
    app = App()

    # Get environment configuration
    env = Environment(
        account=app.node.try_get_context("account") or "123456789012",
        region=app.node.try_get_context("region") or "us-east-1",
    )

    # Create the stack
    stack = CostOptimizedBatchProcessingStack(
        app,
        "CostOptimizedBatchProcessingStack",
        env=env,
        description="Cost-optimized batch processing infrastructure with AWS Batch and Spot Instances",
    )

    # Add stack tags
    Tags.of(stack).add("StackName", "CostOptimizedBatchProcessingStack")
    Tags.of(stack).add("CDKVersion", cdk.__version__)

    app.synth()


if __name__ == "__main__":
    main()