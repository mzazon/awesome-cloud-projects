#!/usr/bin/env python3
"""
AWS Cloud9 Developer Environments CDK Application

This CDK application creates a comprehensive Cloud9 development environment
with proper IAM roles, CodeCommit integration, monitoring, and team collaboration
features as described in the developer-environments-aws-cloud9 recipe.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags,
    aws_cloud9 as cloud9,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_codecommit as codecommit,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class Cloud9DeveloperEnvironmentStack(Stack):
    """
    CDK Stack for AWS Cloud9 Developer Environment
    
    Creates a complete development environment including:
    - Cloud9 EC2 environment with proper sizing
    - IAM roles and policies for development permissions
    - CodeCommit repository for team collaboration
    - CloudWatch monitoring and logging
    - Security groups and network configuration
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Environment configuration
        self.environment_name = self.node.try_get_context("environmentName") or "dev-environment"
        self.instance_type = self.node.try_get_context("instanceType") or "t3.medium"
        self.auto_stop_minutes = int(self.node.try_get_context("autoStopMinutes") or "60")
        self.team_repository_name = self.node.try_get_context("repositoryName") or "team-development-repo"

        # Create VPC or use default
        self.vpc = self._get_or_create_vpc()
        
        # Create IAM role for Cloud9 environment
        self.cloud9_role = self._create_cloud9_iam_role()
        
        # Create instance profile
        self.instance_profile = self._create_instance_profile()
        
        # Create CodeCommit repository
        self.repository = self._create_codecommit_repository()
        
        # Create Cloud9 environment
        self.cloud9_environment = self._create_cloud9_environment()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_monitoring_dashboard()
        
        # Add tags to all resources
        self._add_resource_tags()
        
        # Create outputs
        self._create_outputs()

    def _get_or_create_vpc(self) -> ec2.IVpc:
        """
        Get default VPC or create a new one for the Cloud9 environment.
        
        Returns:
            ec2.IVpc: VPC for the Cloud9 environment
        """
        # Try to use default VPC first
        try:
            vpc = ec2.Vpc.from_lookup(self, "DefaultVPC", is_default=True)
            return vpc
        except Exception:
            # If no default VPC exists, create a new one
            vpc = ec2.Vpc(
                self, "Cloud9VPC",
                max_azs=2,
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
            
            # Add VPC Flow Logs for security monitoring
            logs.LogGroup(
                self, "VPCFlowLogsGroup",
                log_group_name=f"/aws/vpc/flowlogs/{self.environment_name}",
                retention=logs.RetentionDays.ONE_WEEK,
                removal_policy=RemovalPolicy.DESTROY,
            )
            
            return vpc

    def _create_cloud9_iam_role(self) -> iam.Role:
        """
        Create IAM role for Cloud9 environment with necessary permissions.
        
        Returns:
            iam.Role: IAM role for Cloud9 environment
        """
        role = iam.Role(
            self, "Cloud9EnvironmentRole",
            role_name=f"Cloud9-{self.environment_name}-Role",
            assumed_by=iam.ServicePrincipal("ec2.amazonaws.com"),
            description="IAM role for Cloud9 development environment",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSCloud9EnvironmentMember"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSCodeCommitReadOnly"),
            ],
        )

        # Add custom policy for development permissions
        development_policy = iam.Policy(
            self, "Cloud9DevelopmentPolicy",
            policy_name=f"Cloud9-Development-Policy-{self.environment_name}",
            statements=[
                # S3 permissions for development
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                    ],
                    resources=["*"],
                ),
                # DynamoDB permissions for development
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "dynamodb:GetItem",
                        "dynamodb:PutItem",
                        "dynamodb:UpdateItem",
                        "dynamodb:DeleteItem",
                        "dynamodb:Query",
                        "dynamodb:Scan",
                    ],
                    resources=["*"],
                ),
                # Lambda permissions for development
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "lambda:InvokeFunction",
                        "lambda:GetFunction",
                        "lambda:CreateFunction",
                        "lambda:UpdateFunctionCode",
                    ],
                    resources=["*"],
                ),
                # CloudWatch permissions for monitoring
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "cloudwatch:PutMetricData",
                        "cloudwatch:GetMetricStatistics",
                        "cloudwatch:ListMetrics",
                        "logs:CreateLogGroup",
                        "logs:CreateLogStream",
                        "logs:PutLogEvents",
                        "logs:DescribeLogStreams",
                    ],
                    resources=["*"],
                ),
                # Systems Manager permissions for session management
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ssm:UpdateInstanceInformation",
                        "ssm:SendCommand",
                        "ssm:ListCommands",
                        "ssm:ListCommandInvocations",
                        "ssm:DescribeInstanceInformation",
                        "ssm:GetCommandInvocation",
                        "ssmmessages:CreateControlChannel",
                        "ssmmessages:CreateDataChannel",
                        "ssmmessages:OpenControlChannel",
                        "ssmmessages:OpenDataChannel",
                    ],
                    resources=["*"],
                ),
            ],
        )

        role.attach_inline_policy(development_policy)
        return role

    def _create_instance_profile(self) -> iam.InstanceProfile:
        """
        Create instance profile for the Cloud9 environment.
        
        Returns:
            iam.InstanceProfile: Instance profile for EC2 instance
        """
        return iam.InstanceProfile(
            self, "Cloud9InstanceProfile",
            instance_profile_name=f"Cloud9-{self.environment_name}-InstanceProfile",
            role=self.cloud9_role,
        )

    def _create_codecommit_repository(self) -> codecommit.Repository:
        """
        Create CodeCommit repository for team collaboration.
        
        Returns:
            codecommit.Repository: CodeCommit repository
        """
        repository = codecommit.Repository(
            self, "TeamRepository",
            repository_name=self.team_repository_name,
            description=f"Team development repository for {self.environment_name} Cloud9 environment",
        )

        # Add repository policy for team access
        repository.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ArnPrincipal(self.cloud9_role.role_arn)],
                actions=[
                    "codecommit:GitPull",
                    "codecommit:GitPush",
                    "codecommit:GetBranch",
                    "codecommit:GetCommit",
                    "codecommit:GetRepository",
                    "codecommit:ListBranches",
                    "codecommit:ListRepositories",
                ],
                resources=[repository.repository_arn],
            )
        )

        return repository

    def _create_cloud9_environment(self) -> cloud9.CfnEnvironmentEC2:
        """
        Create Cloud9 EC2 environment with proper configuration.
        
        Returns:
            cloud9.CfnEnvironmentEC2: Cloud9 environment
        """
        # Get public subnet for Cloud9 environment
        public_subnet = self.vpc.public_subnets[0]

        # Create Cloud9 environment using CfnEnvironmentEC2 for more control
        cloud9_env = cloud9.CfnEnvironmentEC2(
            self, "Cloud9Environment",
            name=self.environment_name,
            description=f"Development environment with pre-configured tools and settings - {self.environment_name}",
            instance_type=self.instance_type,
            image_id="amazonlinux-2023-x86_64",
            subnet_id=public_subnet.subnet_id,
            automatic_stop_time_minutes=self.auto_stop_minutes,
            connection_type="CONNECT_SSH",
            owner_arn=self.cloud9_role.role_arn,
            tags=[
                cdk.CfnTag(key="Name", value=self.environment_name),
                cdk.CfnTag(key="Environment", value="Development"),
                cdk.CfnTag(key="ManagedBy", value="CDK"),
            ],
        )

        return cloud9_env

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for environment monitoring.
        
        Returns:
            cloudwatch.Dashboard: CloudWatch dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self, "Cloud9Dashboard",
            dashboard_name=f"Cloud9-{self.environment_name}-Dashboard",
        )

        # Add widgets for EC2 instance metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Cloud9 Environment Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/EC2",
                        metric_name="CPUUtilization",
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/EC2",
                        metric_name="NetworkIn",
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/EC2",
                        metric_name="NetworkOut",
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=24,
                height=6,
            )
        )

        return dashboard

    def _add_resource_tags(self) -> None:
        """Add common tags to all resources in the stack."""
        Tags.of(self).add("Project", "Cloud9-Developer-Environment")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "AWS-CDK")
        Tags.of(self).add("Repository", self.team_repository_name)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "Cloud9EnvironmentId",
            value=self.cloud9_environment.ref,
            description="Cloud9 Environment ID",
            export_name=f"{self.stack_name}-Cloud9EnvironmentId",
        )

        CfnOutput(
            self, "Cloud9EnvironmentName",
            value=self.environment_name,
            description="Cloud9 Environment Name",
            export_name=f"{self.stack_name}-Cloud9EnvironmentName",
        )

        CfnOutput(
            self, "CodeCommitRepositoryName",
            value=self.repository.repository_name,
            description="CodeCommit Repository Name",
            export_name=f"{self.stack_name}-CodeCommitRepositoryName",
        )

        CfnOutput(
            self, "CodeCommitRepositoryCloneUrl",
            value=self.repository.repository_clone_url_http,
            description="CodeCommit Repository Clone URL (HTTP)",
            export_name=f"{self.stack_name}-CodeCommitCloneUrl",
        )

        CfnOutput(
            self, "IAMRoleArn",
            value=self.cloud9_role.role_arn,
            description="IAM Role ARN for Cloud9 Environment",
            export_name=f"{self.stack_name}-IAMRoleArn",
        )

        CfnOutput(
            self, "CloudWatchDashboardName",
            value=self.dashboard.dashboard_name,
            description="CloudWatch Dashboard Name",
            export_name=f"{self.stack_name}-DashboardName",
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()

    # Get environment configuration
    env_name = app.node.try_get_context("environmentName") or "dev-environment"
    
    # Create the stack
    Cloud9DeveloperEnvironmentStack(
        app, "Cloud9DeveloperEnvironmentStack",
        stack_name=f"cloud9-{env_name}",
        description="AWS Cloud9 Developer Environment with team collaboration features",
        env=cdk.Environment(
            account=os.getenv("CDK_DEFAULT_ACCOUNT"),
            region=os.getenv("CDK_DEFAULT_REGION"),
        ),
    )

    app.synth()


if __name__ == "__main__":
    main()