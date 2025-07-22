#!/usr/bin/env python3
"""
AWS CDK application for cloud-based development workflows with CloudShell and CodeCommit.

This application creates the infrastructure needed for cloud-based development workflows
using AWS CloudShell and CodeCommit, including:
- CodeCommit repository for source code storage
- IAM roles and policies for secure CloudShell access
- CloudWatch monitoring and logging
- Security best practices implementation

Note: AWS CodeCommit is no longer available to new customers as of July 2024.
Existing customers can continue using the service. Consider alternatives like
GitHub, GitLab, or AWS CodeStar Connections for new implementations.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    StackProps,
    CfnOutput,
    RemovalPolicy,
    Duration,
    Tags,
)
from aws_cdk import aws_codecommit as codecommit
from aws_cdk import aws_iam as iam
from aws_cdk import aws_logs as logs
from aws_cdk import aws_sns as sns
from aws_cdk import aws_events as events
from aws_cdk import aws_events_targets as targets
from constructs import Construct


class CloudBasedDevelopmentWorkflowsStack(Stack):
    """
    CDK Stack for cloud-based development workflows with CloudShell and CodeCommit.
    
    This stack creates the necessary infrastructure for teams to implement
    cloud-based development workflows using AWS CloudShell and CodeCommit.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        repository_name: Optional[str] = None,
        enable_notifications: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the CloudBasedDevelopmentWorkflowsStack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            repository_name: Optional custom repository name
            enable_notifications: Whether to enable SNS notifications for repository events
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique repository name if not provided
        if repository_name is None:
            repository_name = f"dev-workflow-demo-{self.node.addr[-8:].lower()}"

        # Create CodeCommit repository
        self.repository = self._create_codecommit_repository(repository_name)

        # Create IAM role and policies for CloudShell access
        self.cloudshell_role = self._create_cloudshell_iam_role()
        self.codecommit_policy = self._create_codecommit_policy()

        # Attach policy to role
        self.cloudshell_role.attach_inline_policy(self.codecommit_policy)

        # Create CloudWatch log group for monitoring
        self.log_group = self._create_log_group()

        # Create SNS topic for notifications if enabled
        self.sns_topic = None
        if enable_notifications:
            self.sns_topic = self._create_sns_topic()
            self._create_repository_event_rules()

        # Create stack outputs
        self._create_outputs()

        # Add tags to all resources
        self._add_tags()

    def _create_codecommit_repository(self, repository_name: str) -> codecommit.Repository:
        """
        Create a CodeCommit repository for the development workflow.

        Args:
            repository_name: The name of the repository to create

        Returns:
            The created CodeCommit repository
        """
        repository = codecommit.Repository(
            self,
            "DevWorkflowRepository",
            repository_name=repository_name,
            description=(
                "Demo repository for cloud-based development workflow using "
                "AWS CloudShell and CodeCommit. This repository supports "
                "browser-based development with integrated Git version control."
            ),
            code=codecommit.Code.from_directory(
                directory_path=os.path.join(
                    os.path.dirname(__file__), 
                    "sample_code"
                ),
                branch_name="main"
            ) if os.path.exists(
                os.path.join(os.path.dirname(__file__), "sample_code")
            ) else None,
        )

        # Apply removal policy for cleanup
        repository.apply_removal_policy(RemovalPolicy.DESTROY)

        return repository

    def _create_cloudshell_iam_role(self) -> iam.Role:
        """
        Create an IAM role for CloudShell to access CodeCommit.

        Returns:
            The created IAM role
        """
        # Create assume role policy for CloudShell and EC2 (CloudShell runs on EC2)
        assume_role_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ServicePrincipal("ec2.amazonaws.com"),
                        iam.ServicePrincipal("cloudshell.amazonaws.com"),
                    ],
                    actions=["sts:AssumeRole"],
                    conditions={
                        "StringEquals": {
                            "aws:RequestedRegion": self.region
                        }
                    }
                )
            ]
        )

        role = iam.Role(
            self,
            "CloudShellCodeCommitRole",
            role_name=f"CloudShellCodeCommitRole-{self.stack_name}",
            description=(
                "IAM role for AWS CloudShell to access CodeCommit repositories "
                "with secure, temporary credentials"
            ),
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("ec2.amazonaws.com"),
                iam.ServicePrincipal("cloudshell.amazonaws.com"),
            ),
            max_session_duration=Duration.hours(12),
        )

        # Add basic CloudShell permissions
        role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "AWSCloudShellFullAccess"
            )
        )

        return role

    def _create_codecommit_policy(self) -> iam.Policy:
        """
        Create an IAM policy with minimal permissions for CodeCommit access.

        Returns:
            The created IAM policy
        """
        policy_statements = [
            # Core CodeCommit permissions for Git operations
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:GitPull",
                    "codecommit:GitPush",
                    "codecommit:GetRepository",
                    "codecommit:ListRepositories",
                    "codecommit:ListBranches",
                    "codecommit:ListTagsForResource",
                    "codecommit:TagResource",
                    "codecommit:UntagResource",
                ],
                resources=[self.repository.repository_arn],
            ),
            # Branch-level permissions for feature branch workflows
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:CreateBranch",
                    "codecommit:DeleteBranch",
                    "codecommit:GetBranch",
                    "codecommit:MergeBranchesByFastForward",
                    "codecommit:MergeBranchesBySquash",
                    "codecommit:MergeBranchesByThreeWay",
                ],
                resources=[self.repository.repository_arn],
            ),
            # Commit-level permissions for detailed Git operations
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:GetCommit",
                    "codecommit:GetCommitHistory",
                    "codecommit:GetDifferences",
                    "codecommit:GetReferences",
                    "codecommit:GetObjectIdentifier",
                    "codecommit:BatchGetCommits",
                ],
                resources=[self.repository.repository_arn],
            ),
            # Pull request permissions for code review workflows
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "codecommit:CreatePullRequest",
                    "codecommit:GetPullRequest",
                    "codecommit:ListPullRequests",
                    "codecommit:MergePullRequestByFastForward",
                    "codecommit:UpdatePullRequestDescription",
                    "codecommit:UpdatePullRequestStatus",
                    "codecommit:UpdatePullRequestTitle",
                ],
                resources=[self.repository.repository_arn],
            ),
        ]

        policy = iam.Policy(
            self,
            "CodeCommitAccessPolicy",
            policy_name=f"CodeCommitAccess-{self.stack_name}",
            description=(
                "Policy granting minimal required permissions for CodeCommit "
                "access from AWS CloudShell following least privilege principle"
            ),
            statements=policy_statements,
        )

        return policy

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create a CloudWatch log group for monitoring repository activities.

        Returns:
            The created CloudWatch log group
        """
        log_group = logs.LogGroup(
            self,
            "DevWorkflowLogGroup",
            log_group_name=f"/aws/codecommit/dev-workflow/{self.stack_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        return log_group

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create an SNS topic for repository event notifications.

        Returns:
            The created SNS topic
        """
        topic = sns.Topic(
            self,
            "DevWorkflowNotifications",
            topic_name=f"dev-workflow-notifications-{self.stack_name}",
            description=(
                "SNS topic for CodeCommit repository event notifications "
                "including commits, branch changes, and pull requests"
            ),
            display_name="Development Workflow Notifications",
        )

        return topic

    def _create_repository_event_rules(self) -> None:
        """
        Create EventBridge rules to capture CodeCommit events and send notifications.
        """
        if not self.sns_topic:
            return

        # Rule for repository state changes (commits, pushes)
        commit_rule = events.Rule(
            self,
            "CommitEventRule",
            description="Capture CodeCommit repository state changes",
            event_pattern=events.EventPattern(
                source=["aws.codecommit"],
                detail_type=["CodeCommit Repository State Change"],
                detail={
                    "repositoryName": [self.repository.repository_name],
                    "referenceType": ["branch"],
                }
            ),
        )

        commit_rule.add_target(
            targets.SnsTopic(
                self.sns_topic,
                message=events.RuleTargetInput.from_text(
                    "CodeCommit Repository Update: "
                    "Repository '$.detail.repositoryName' "
                    "received changes on branch '$.detail.referenceName'"
                ),
            )
        )

        # Rule for pull request events
        pr_rule = events.Rule(
            self,
            "PullRequestEventRule",
            description="Capture CodeCommit pull request events",
            event_pattern=events.EventPattern(
                source=["aws.codecommit"],
                detail_type=["CodeCommit Pull Request State Change"],
                detail={
                    "repositoryName": [self.repository.repository_name],
                }
            ),
        )

        pr_rule.add_target(
            targets.SnsTopic(
                self.sns_topic,
                message=events.RuleTargetInput.from_text(
                    "CodeCommit Pull Request: "
                    "Pull request '$.detail.pullRequestId' "
                    "in repository '$.detail.repositoryName' "
                    "changed to status '$.detail.pullRequestStatus'"
                ),
            )
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for key resource information.
        """
        # Repository information outputs
        CfnOutput(
            self,
            "RepositoryName",
            value=self.repository.repository_name,
            description="Name of the CodeCommit repository for the development workflow",
            export_name=f"{self.stack_name}-RepositoryName",
        )

        CfnOutput(
            self,
            "RepositoryCloneUrlHttp",
            value=self.repository.repository_clone_url_http,
            description="HTTPS clone URL for the CodeCommit repository",
            export_name=f"{self.stack_name}-CloneUrl",
        )

        CfnOutput(
            self,
            "RepositoryArn",
            value=self.repository.repository_arn,
            description="ARN of the CodeCommit repository",
            export_name=f"{self.stack_name}-RepositoryArn",
        )

        # IAM role and policy outputs
        CfnOutput(
            self,
            "CloudShellRoleArn",
            value=self.cloudshell_role.role_arn,
            description="ARN of the IAM role for CloudShell CodeCommit access",
            export_name=f"{self.stack_name}-CloudShellRoleArn",
        )

        CfnOutput(
            self,
            "CodeCommitPolicyArn",
            value=self.codecommit_policy.policy_arn,
            description="ARN of the CodeCommit access policy",
            export_name=f"{self.stack_name}-PolicyArn",
        )

        # Monitoring outputs
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch log group for monitoring repository activities",
            export_name=f"{self.stack_name}-LogGroup",
        )

        if self.sns_topic:
            CfnOutput(
                self,
                "NotificationTopicArn",
                value=self.sns_topic.topic_arn,
                description="SNS topic ARN for repository event notifications",
                export_name=f"{self.stack_name}-NotificationTopic",
            )

        # Git configuration commands
        git_config_commands = (
            f"git config --global credential.helper '!aws codecommit credential-helper $@'\n"
            f"git config --global credential.UseHttpPath true\n"
            f"git clone {self.repository.repository_clone_url_http}"
        )

        CfnOutput(
            self,
            "GitConfigurationCommands",
            value=git_config_commands,
            description="Commands to configure Git for CodeCommit access in CloudShell",
        )

        # Repository console URL
        repository_console_url = (
            f"https://{self.region}.console.aws.amazon.com/codesuite/codecommit/"
            f"repositories/{self.repository.repository_name}/browse"
        )

        CfnOutput(
            self,
            "RepositoryConsoleUrl",
            value=repository_console_url,
            description="AWS Console URL for the CodeCommit repository",
        )

    def _add_tags(self) -> None:
        """
        Add consistent tags to all resources in the stack.
        """
        Tags.of(self).add("Project", "CloudBasedDevelopmentWorkflows")
        Tags.of(self).add("Purpose", "DemoInfrastructure")
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("CostCenter", "Engineering")


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = App()

    # Get environment configuration
    account = os.getenv("CDK_DEFAULT_ACCOUNT")
    region = os.getenv("CDK_DEFAULT_REGION", "us-east-1")

    # Create the stack
    CloudBasedDevelopmentWorkflowsStack(
        app,
        "CloudBasedDevelopmentWorkflowsStack",
        env=Environment(account=account, region=region),
        description=(
            "Infrastructure for cloud-based development workflows using "
            "AWS CloudShell and CodeCommit - includes repository, IAM roles, "
            "and monitoring setup"
        ),
        repository_name=os.getenv("REPOSITORY_NAME"),
        enable_notifications=os.getenv("ENABLE_NOTIFICATIONS", "true").lower() == "true",
    )

    app.synth()


if __name__ == "__main__":
    main()