#!/usr/bin/env python3
"""
AWS CDK application for batch processing workloads using AWS Batch.

This CDK application creates a complete AWS Batch infrastructure including:
- ECR repository for container images
- Managed compute environment with spot and on-demand instances
- Job queue for batch job orchestration
- IAM roles and policies for Batch service
- CloudWatch log groups and alarms for monitoring
- Security groups for network access control

The infrastructure supports cost-effective batch processing workloads
with automatic scaling and comprehensive monitoring capabilities.

Author: AWS CDK Generator  
Version: 1.2
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_batch as batch,
    aws_ecr as ecr,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
    Duration,
    RemovalPolicy
)
from constructs import Construct
import os


class BatchProcessingStack(Stack):
    """
    AWS CDK Stack for Batch Processing Workloads
    
    This stack creates a comprehensive AWS Batch infrastructure for running
    containerized batch jobs with automatic scaling and cost optimization.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.max_vcpus = 100
        self.desired_vcpus = 0
        self.min_vcpus = 0
        self.spot_bid_percentage = 50
        self.job_timeout_seconds = 3600
        self.log_retention_days = 30

        # Create ECR Repository
        self.ecr_repository = self._create_ecr_repository()

        # Create VPC and networking components
        self.vpc = self._create_vpc()
        self.security_group = self._create_security_group()

        # Create IAM roles
        self.batch_service_role = self._create_batch_service_role()
        self.batch_instance_role = self._create_batch_instance_role()
        self.batch_instance_profile = self._create_batch_instance_profile()

        # Create CloudWatch Log Group
        self.log_group = self._create_log_group()

        # Create Batch Compute Environment
        self.compute_environment = self._create_compute_environment()

        # Create Job Queue
        self.job_queue = self._create_job_queue()

        # Create Job Definition
        self.job_definition = self._create_job_definition()

        # Create CloudWatch Alarms
        self._create_cloudwatch_alarms()

        # Create outputs
        self._create_outputs()

    def _create_ecr_repository(self) -> ecr.Repository:
        """
        Create an ECR repository for storing container images.
        
        Returns:
            ecr.Repository: The created ECR repository
        """
        repository = ecr.Repository(
            self, "BatchProcessingRepository",
            repository_name=f"batch-processing-{self.node.addr.lower()}",
            image_scan_on_push=True,
            removal_policy=RemovalPolicy.DESTROY,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep only the latest 10 images",
                    max_image_count=10,
                    rule_priority=1
                )
            ]
        )

        # Grant permissions for pushing images
        repository.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.AccountRootPrincipal()],
                actions=[
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:PutImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload"
                ]
            )
        )

        return repository

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create a VPC with public and private subnets for the Batch environment.
        
        Returns:
            ec2.Vpc: The created VPC
        """
        vpc = ec2.Vpc(
            self, "BatchVPC",
            ip_addresses=ec2.IpAddresses.cidr("10.0.0.0/16"),
            max_azs=2,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PUBLIC,
                    name="PublicSubnet",
                    cidr_mask=24
                ),
                ec2.SubnetConfiguration(
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    name="PrivateSubnet",
                    cidr_mask=24
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True
        )

        # Add VPC endpoint for ECR to reduce NAT gateway costs
        vpc.add_interface_endpoint(
            "ECREndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECR
        )

        vpc.add_interface_endpoint(
            "ECRDockerEndpoint",
            service=ec2.InterfaceVpcEndpointAwsService.ECR_DOCKER
        )

        # Add S3 gateway endpoint for ECR layer downloads
        vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3
        )

        return vpc

    def _create_security_group(self) -> ec2.SecurityGroup:
        """
        Create a security group for the Batch compute environment.
        
        Returns:
            ec2.SecurityGroup: The created security group
        """
        security_group = ec2.SecurityGroup(
            self, "BatchSecurityGroup",
            vpc=self.vpc,
            description="Security group for AWS Batch compute environment",
            allow_all_outbound=True
        )

        # Allow communication between batch instances
        security_group.add_ingress_rule(
            peer=security_group,
            connection=ec2.Port.all_traffic(),
            description="Allow communication between batch instances"
        )

        return security_group

    def _create_batch_service_role(self) -> iam.Role:
        """
        Create an IAM role for the AWS Batch service.
        
        Returns:
            iam.Role: The created service role
        """
        service_role = iam.Role(
            self, "BatchServiceRole",
            assumed_by=iam.ServicePrincipal("batch.amazonaws.com"),
            description="Service role for AWS Batch",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSBatchServiceRole"
                )
            ]
        )

        return service_role

    def _create_batch_instance_role(self) -> iam.Role:
        """
        Create an IAM role for Batch compute instances.
        
        Returns:
            iam.Role: The created instance role
        """
        instance_role = iam.Role(
            self, "BatchInstanceRole",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="Instance role for AWS Batch compute instances",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonEC2ContainerServiceforEC2Role"
                )
            ]
        )

        # Add additional permissions for CloudWatch logging
        instance_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogStreams"
                ],
                resources=["*"]
            )
        )

        return instance_role

    def _create_batch_instance_profile(self) -> iam.CfnInstanceProfile:
        """
        Create an instance profile for Batch compute instances.
        
        Returns:
            iam.CfnInstanceProfile: The created instance profile
        """
        instance_profile = iam.CfnInstanceProfile(
            self, "BatchInstanceProfile",
            roles=[self.batch_instance_role.role_name],
            instance_profile_name=f"BatchInstanceProfile-{self.node.addr}"
        )

        return instance_profile

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create a CloudWatch log group for Batch job logs.
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self, "BatchLogGroup",
            log_group_name="/aws/batch/job",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        return log_group

    def _create_compute_environment(self) -> batch.CfnComputeEnvironment:
        """
        Create a managed Batch compute environment with EC2 and Spot instances.
        
        Returns:
            batch.CfnComputeEnvironment: The created compute environment
        """
        compute_environment = batch.CfnComputeEnvironment(
            self, "BatchComputeEnvironment",
            type="MANAGED",
            state="ENABLED",
            service_role=self.batch_service_role.role_arn,
            compute_environment_name=f"BatchComputeEnv-{self.node.addr}",
            compute_resources=batch.CfnComputeEnvironment.ComputeResourcesProperty(
                type="EC2",
                min_vcpus=self.min_vcpus,
                max_vcpus=self.max_vcpus,
                desired_vcpus=self.desired_vcpus,
                instance_types=["optimal"],
                subnets=[subnet.subnet_id for subnet in self.vpc.private_subnets],
                security_group_ids=[self.security_group.security_group_id],
                instance_role=self.batch_instance_profile.attr_arn,
                bid_percentage=self.spot_bid_percentage,
                ec2_configuration=[
                    batch.CfnComputeEnvironment.Ec2ConfigurationObjectProperty(
                        image_type="ECS_AL2"
                    )
                ],
                tags={
                    "Name": "BatchComputeInstance",
                    "Environment": "BatchProcessing",
                    "ManagedBy": "CDK"
                }
            )
        )

        return compute_environment

    def _create_job_queue(self) -> batch.CfnJobQueue:
        """
        Create a Batch job queue.
        
        Returns:
            batch.CfnJobQueue: The created job queue
        """
        job_queue = batch.CfnJobQueue(
            self, "BatchJobQueue",
            job_queue_name=f"BatchJobQueue-{self.node.addr}",
            state="ENABLED",
            priority=1,
            compute_environment_order=[
                batch.CfnJobQueue.ComputeEnvironmentOrderProperty(
                    order=1,
                    compute_environment=self.compute_environment.ref
                )
            ]
        )

        # Add dependency to ensure compute environment is created first
        job_queue.add_dependency(self.compute_environment)

        return job_queue

    def _create_job_definition(self) -> batch.CfnJobDefinition:
        """
        Create a Batch job definition for containerized workloads.
        
        Returns:
            batch.CfnJobDefinition: The created job definition
        """
        job_definition = batch.CfnJobDefinition(
            self, "BatchJobDefinition",
            job_definition_name=f"BatchJobDef-{self.node.addr}",
            type="container",
            timeout=batch.CfnJobDefinition.TimeoutProperty(
                attempt_duration_seconds=self.job_timeout_seconds
            ),
            container_properties=batch.CfnJobDefinition.ContainerPropertiesProperty(
                image=f"{self.ecr_repository.repository_uri}:latest",
                vcpus=1,
                memory=512,
                environment=[
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="DATA_SIZE",
                        value="5000"
                    ),
                    batch.CfnJobDefinition.EnvironmentProperty(
                        name="PROCESSING_TIME",
                        value="120"
                    )
                ],
                log_configuration=batch.CfnJobDefinition.LogConfigurationProperty(
                    log_driver="awslogs",
                    options={
                        "awslogs-group": self.log_group.log_group_name,
                        "awslogs-region": self.region
                    }
                )
            )
        )

        return job_definition

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring Batch jobs.
        """
        # Alarm for failed jobs
        failed_jobs_alarm = cloudwatch.Alarm(
            self, "BatchFailedJobsAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/Batch",
                metric_name="FailedJobs",
                dimensions_map={
                    "JobQueue": self.job_queue.job_queue_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            alarm_description="Alert when batch jobs fail"
        )

        # Alarm for high queue utilization
        queue_utilization_alarm = cloudwatch.Alarm(
            self, "BatchQueueUtilizationAlarm",
            metric=cloudwatch.Metric(
                namespace="AWS/Batch",
                metric_name="SubmittedJobs",
                dimensions_map={
                    "JobQueue": self.job_queue.job_queue_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=50,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            alarm_description="Alert when job queue has high utilization"
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource information.
        """
        CfnOutput(
            self, "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="ECR Repository URI for batch processing container images"
        )

        CfnOutput(
            self, "ComputeEnvironmentName",
            value=self.compute_environment.compute_environment_name,
            description="Name of the Batch compute environment"
        )

        CfnOutput(
            self, "JobQueueName",
            value=self.job_queue.job_queue_name,
            description="Name of the Batch job queue"
        )

        CfnOutput(
            self, "JobDefinitionArn",
            value=self.job_definition.ref,
            description="ARN of the Batch job definition"
        )

        CfnOutput(
            self, "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for batch job logs"
        )

        CfnOutput(
            self, "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for the Batch infrastructure"
        )

        CfnOutput(
            self, "SecurityGroupId",
            value=self.security_group.security_group_id,
            description="Security group ID for Batch compute instances"
        )


def main():
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Get environment variables for account and region
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")

    # Create the stack
    BatchProcessingStack(
        app, "BatchProcessingStack",
        env=Environment(account=account, region=region),
        description="AWS Batch infrastructure for processing large-scale batch workloads with CDK v2",
        tags={
            "Project": "BatchProcessing",
            "ManagedBy": "CDK",
            "Purpose": "BatchProcessingWorkloads"
        }
    )

    # Apply CDK Nag for security best practices
    try:
        from cdk_nag import AwsSolutionsChecks, NagSuppressions
        
        # Apply AWS Solutions Pack for security validation
        AwsSolutionsChecks.check(app, verbose=True)
        
        # Add necessary suppressions for AWS Batch architecture
        NagSuppressions.add_stack_suppressions(
            app.node.find_child("BatchProcessingStack"),
            [
                {
                    "id": "AwsSolutions-IAM4",
                    "reason": "AWS managed policies are acceptable for Batch service roles as they provide least privilege for AWS services"
                },
                {
                    "id": "AwsSolutions-IAM5", 
                    "reason": "Wildcard permissions required for ECR access and CloudWatch Logs in batch processing scenarios"
                },
                {
                    "id": "AwsSolutions-EC23",
                    "reason": "Security group allows outbound traffic for package downloads and AWS service communication"
                },
                {
                    "id": "AwsSolutions-VPC7",
                    "reason": "VPC Flow Logs not required for this batch processing use case"
                }
            ]
        )
    except ImportError:
        print("Warning: cdk-nag not installed. Consider installing for security best practices validation.")

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()