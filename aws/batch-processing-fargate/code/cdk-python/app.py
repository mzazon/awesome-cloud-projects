#!/usr/bin/env python3
"""
CDK Python application for AWS Batch with Fargate
This stack creates serverless batch processing infrastructure using AWS Batch and Fargate.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_batch as batch,
    aws_ec2 as ec2,
    aws_ecr as ecr,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags,
)
from constructs import Construct


class BatchFargateStack(Stack):
    """
    AWS CDK Stack for Batch Processing with Fargate
    
    This stack creates:
    - VPC with public subnets (or uses existing VPC)
    - ECR repository for container images
    - IAM roles for Batch execution
    - Batch compute environment with Fargate
    - Batch job queue
    - CloudWatch log group
    - Sample job definition
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        vpc_id: Optional[str] = None,
        subnet_ids: Optional[List[str]] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.project_name = "batch-fargate-demo"
        self.environment = "dev"
        
        # Create or use existing VPC
        if vpc_id:
            self.vpc = ec2.Vpc.from_lookup(self, "ExistingVPC", vpc_id=vpc_id)
        else:
            self.vpc = self._create_vpc()
        
        # Create ECR repository
        self.ecr_repository = self._create_ecr_repository()
        
        # Create IAM roles
        self.execution_role = self._create_execution_role()
        self.job_role = self._create_job_role()
        
        # Create CloudWatch log group
        self.log_group = self._create_log_group()
        
        # Create Batch compute environment
        self.compute_environment = self._create_compute_environment()
        
        # Create Batch job queue
        self.job_queue = self._create_job_queue()
        
        # Create sample job definition
        self.job_definition = self._create_job_definition()
        
        # Create outputs
        self._create_outputs()
        
        # Apply common tags
        self._apply_tags()

    def _create_vpc(self) -> ec2.Vpc:
        """Create VPC with public subnets for Fargate tasks"""
        vpc = ec2.Vpc(
            self,
            "BatchVPC",
            vpc_name=f"{self.project_name}-vpc",
            max_azs=2,
            nat_gateways=0,  # Use public subnets only for cost optimization
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="Public",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                )
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Add VPC endpoints for cost optimization (optional)
        vpc.add_gateway_endpoint(
            "S3Endpoint",
            service=ec2.GatewayVpcEndpointAwsService.S3,
            subnets=[ec2.SubnetSelection(subnet_type=ec2.SubnetType.PUBLIC)],
        )
        
        return vpc

    def _create_ecr_repository(self) -> ecr.Repository:
        """Create ECR repository for batch processing container images"""
        repository = ecr.Repository(
            self,
            "BatchRepository",
            repository_name=f"{self.project_name}-repository",
            image_scan_on_push=True,
            lifecycle_rules=[
                ecr.LifecycleRule(
                    description="Keep last 10 images",
                    max_image_count=10,
                    rule_priority=1,
                    tag_status=ecr.TagStatus.ANY,
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return repository

    def _create_execution_role(self) -> iam.Role:
        """Create IAM role for Fargate task execution"""
        execution_role = iam.Role(
            self,
            "BatchExecutionRole",
            role_name=f"{self.project_name}-execution-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for AWS Batch Fargate task execution",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonECSTaskExecutionRolePolicy"
                )
            ],
        )
        
        # Add additional permissions for ECR and CloudWatch
        execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=["*"],
            )
        )
        
        return execution_role

    def _create_job_role(self) -> iam.Role:
        """Create IAM role for batch job execution (application-level permissions)"""
        job_role = iam.Role(
            self,
            "BatchJobRole",
            role_name=f"{self.project_name}-job-role",
            assumed_by=iam.ServicePrincipal("ecs-tasks.amazonaws.com"),
            description="IAM role for AWS Batch job execution with application permissions",
        )
        
        # Add basic permissions for batch jobs
        job_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket",
                    "ssm:GetParameter",
                    "ssm:GetParameters",
                    "ssm:GetParametersByPath",
                ],
                resources=["*"],
            )
        )
        
        return job_role

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for batch jobs"""
        log_group = logs.LogGroup(
            self,
            "BatchLogGroup",
            log_group_name="/aws/batch/job",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _create_compute_environment(self) -> batch.CfnComputeEnvironment:
        """Create Fargate compute environment for AWS Batch"""
        
        # Get subnet IDs for the compute environment
        subnet_ids = [subnet.subnet_id for subnet in self.vpc.public_subnets]
        
        # Create security group for Fargate tasks
        security_group = ec2.SecurityGroup(
            self,
            "BatchSecurityGroup",
            vpc=self.vpc,
            description="Security group for AWS Batch Fargate tasks",
            allow_all_outbound=True,
        )
        
        # Create compute environment
        compute_environment = batch.CfnComputeEnvironment(
            self,
            "BatchComputeEnvironment",
            compute_environment_name=f"{self.project_name}-compute-env",
            type="MANAGED",
            state="ENABLED",
            compute_resources=batch.CfnComputeEnvironment.ComputeResourcesProperty(
                type="FARGATE",
                max_vcpus=256,
                subnets=subnet_ids,
                security_group_ids=[security_group.security_group_id],
            ),
            service_role=f"arn:aws:iam::{self.account}:role/aws-service-role/batch.amazonaws.com/AWSServiceRoleForBatch",
        )
        
        return compute_environment

    def _create_job_queue(self) -> batch.CfnJobQueue:
        """Create job queue for batch processing"""
        job_queue = batch.CfnJobQueue(
            self,
            "BatchJobQueue",
            job_queue_name=f"{self.project_name}-job-queue",
            state="ENABLED",
            priority=1,
            compute_environment_order=[
                batch.CfnJobQueue.ComputeEnvironmentOrderProperty(
                    order=1,
                    compute_environment=self.compute_environment.compute_environment_name,
                )
            ],
        )
        
        # Add dependency to ensure compute environment is created first
        job_queue.add_depends_on(self.compute_environment)
        
        return job_queue

    def _create_job_definition(self) -> batch.CfnJobDefinition:
        """Create sample job definition for Fargate"""
        
        # Create job definition
        job_definition = batch.CfnJobDefinition(
            self,
            "BatchJobDefinition",
            job_definition_name=f"{self.project_name}-job-definition",
            type="container",
            platform_capabilities=["FARGATE"],
            container_properties=batch.CfnJobDefinition.ContainerPropertiesProperty(
                image=f"{self.ecr_repository.repository_uri}:latest",
                resource_requirements=[
                    batch.CfnJobDefinition.ResourceRequirementProperty(
                        type="VCPU",
                        value="0.25"
                    ),
                    batch.CfnJobDefinition.ResourceRequirementProperty(
                        type="MEMORY",
                        value="512"
                    ),
                ],
                execution_role_arn=self.execution_role.role_arn,
                job_role_arn=self.job_role.role_arn,
                network_configuration=batch.CfnJobDefinition.NetworkConfigurationProperty(
                    assign_public_ip="ENABLED"
                ),
                log_configuration=batch.CfnJobDefinition.LogConfigurationProperty(
                    log_driver="awslogs",
                    options={
                        "awslogs-group": self.log_group.log_group_name,
                        "awslogs-region": self.region,
                        "awslogs-stream-prefix": "batch-fargate",
                    },
                ),
            ),
            timeout=batch.CfnJobDefinition.TimeoutProperty(
                attempt_duration_seconds=3600  # 1 hour timeout
            ),
        )
        
        return job_definition

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "ECRRepositoryURI",
            value=self.ecr_repository.repository_uri,
            description="ECR Repository URI for batch processing images",
            export_name=f"{self.stack_name}-ECRRepositoryURI",
        )
        
        CfnOutput(
            self,
            "ComputeEnvironmentName",
            value=self.compute_environment.compute_environment_name,
            description="AWS Batch Compute Environment Name",
            export_name=f"{self.stack_name}-ComputeEnvironmentName",
        )
        
        CfnOutput(
            self,
            "JobQueueName",
            value=self.job_queue.job_queue_name,
            description="AWS Batch Job Queue Name",
            export_name=f"{self.stack_name}-JobQueueName",
        )
        
        CfnOutput(
            self,
            "JobDefinitionName",
            value=self.job_definition.job_definition_name,
            description="AWS Batch Job Definition Name",
            export_name=f"{self.stack_name}-JobDefinitionName",
        )
        
        CfnOutput(
            self,
            "ExecutionRoleArn",
            value=self.execution_role.role_arn,
            description="IAM Role ARN for Fargate task execution",
            export_name=f"{self.stack_name}-ExecutionRoleArn",
        )
        
        CfnOutput(
            self,
            "JobRoleArn",
            value=self.job_role.role_arn,
            description="IAM Role ARN for batch job execution",
            export_name=f"{self.stack_name}-JobRoleArn",
        )
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for batch jobs",
            export_name=f"{self.stack_name}-LogGroupName",
        )
        
        CfnOutput(
            self,
            "VPCId",
            value=self.vpc.vpc_id,
            description="VPC ID for batch processing infrastructure",
            export_name=f"{self.stack_name}-VPCId",
        )

    def _apply_tags(self) -> None:
        """Apply common tags to all resources"""
        tags_dict = {
            "Project": self.project_name,
            "Environment": self.environment,
            "Purpose": "BatchProcessing",
            "ManagedBy": "CDK",
        }
        
        for key, value in tags_dict.items():
            Tags.of(self).add(key, value)


def main():
    """Main function to create and deploy the CDK application"""
    app = cdk.App()
    
    # Get configuration from CDK context or environment variables
    vpc_id = app.node.try_get_context("vpcId") or os.environ.get("VPC_ID")
    subnet_ids = app.node.try_get_context("subnetIds") or os.environ.get("SUBNET_IDS", "").split(",")
    
    # Create the stack
    BatchFargateStack(
        app,
        "BatchFargateStack",
        vpc_id=vpc_id if vpc_id else None,
        subnet_ids=subnet_ids if subnet_ids[0] else None,
        description="AWS Batch processing infrastructure with Fargate orchestration",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION"),
        ),
    )
    
    app.synth()


if __name__ == "__main__":
    main()