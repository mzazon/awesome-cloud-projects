"""
CDK Stack for CodeCommit Git Workflows with Branch Policies and Triggers

This stack creates a comprehensive Git workflow automation system with:
- CodeCommit repository with initial structure
- Lambda functions for workflow automation
- SNS topics for notifications
- EventBridge rules for event processing
- CloudWatch dashboard for monitoring
- IAM roles with least privilege access
"""

from typing import List, Optional
import json
from constructs import Construct
from aws_cdk import (
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_codecommit as codecommit,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sns as sns,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)


class CodeCommitGitWorkflowsStack(Stack):
    """CDK Stack for CodeCommit Git Workflows automation."""

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        repository_name: str,
        repository_description: str,
        team_lead_user: str,
        senior_developers: List[str],
        environment_name: str = "development",
        notification_email: Optional[str] = None,
        enable_monitoring: bool = True,
        enable_email_notifications: bool = False,
        **kwargs,
    ) -> None:
        """
        Initialize the CodeCommit Git Workflows stack.

        Args:
            repository_name: Name of the CodeCommit repository
            repository_description: Description for the repository
            team_lead_user: Username of the team lead for approval rules
            senior_developers: List of senior developer usernames
            environment_name: Environment name (development, staging, production)
            notification_email: Email address for notifications (optional)
            enable_monitoring: Whether to create CloudWatch dashboard
            enable_email_notifications: Whether to set up email notifications
        """
        super().__init__(scope, construct_id, **kwargs)

        self.repository_name = repository_name
        self.repository_description = repository_description
        self.team_lead_user = team_lead_user
        self.senior_developers = senior_developers
        self.environment_name = environment_name
        self.notification_email = notification_email
        self.enable_monitoring = enable_monitoring
        self.enable_email_notifications = enable_email_notifications

        # Create all resources
        self._create_codecommit_repository()
        self._create_sns_topics()
        self._create_iam_roles()
        self._create_lambda_functions()
        self._create_eventbridge_rules()
        self._create_approval_rule_template()
        if self.enable_monitoring:
            self._create_monitoring_dashboard()
        self._create_outputs()

    def _create_codecommit_repository(self) -> None:
        """Create the CodeCommit repository with initial configuration."""
        self.repository = codecommit.Repository(
            self,
            "GitWorkflowRepository",
            repository_name=self.repository_name,
            description=self.repository_description,
            code=codecommit.Code.from_directory(
                directory_path="assets/repository-structure",
                branch="main",
            ) if hasattr(self, "assets") else None,
        )

        # Create initial repository structure using custom resource if needed
        # This would be implemented with a Lambda-backed custom resource
        # to create the initial files and directory structure

    def _create_sns_topics(self) -> None:
        """Create SNS topics for different notification types."""
        # Pull Request notifications
        self.pull_request_topic = sns.Topic(
            self,
            "PullRequestTopic",
            topic_name=f"{self.repository_name}-pull-requests",
            display_name="CodeCommit Pull Request Notifications",
        )

        # Merge notifications
        self.merge_topic = sns.Topic(
            self,
            "MergeTopic",
            topic_name=f"{self.repository_name}-merges",
            display_name="CodeCommit Merge Notifications",
        )

        # Quality gate notifications
        self.quality_gate_topic = sns.Topic(
            self,
            "QualityGateTopic",
            topic_name=f"{self.repository_name}-quality-gates",
            display_name="CodeCommit Quality Gate Notifications",
        )

        # Security alert notifications
        self.security_alert_topic = sns.Topic(
            self,
            "SecurityAlertTopic",
            topic_name=f"{self.repository_name}-security-alerts",
            display_name="CodeCommit Security Alert Notifications",
        )

        # Add email subscriptions if enabled
        if self.enable_email_notifications and self.notification_email:
            for topic, name in [
                (self.pull_request_topic, "PullRequest"),
                (self.merge_topic, "Merge"),
                (self.quality_gate_topic, "QualityGate"),
                (self.security_alert_topic, "SecurityAlert"),
            ]:
                sns.Subscription(
                    self,
                    f"{name}EmailSubscription",
                    topic=topic,
                    endpoint=self.notification_email,
                    protocol=sns.SubscriptionProtocol.EMAIL,
                )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Lambda functions with least privilege access."""
        # Create execution role for Lambda functions
        self.lambda_execution_role = iam.Role(
            self,
            "CodeCommitAutomationRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for CodeCommit automation Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add inline policy for CodeCommit, SNS, and CloudWatch access
        codecommit_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "codecommit:GetRepository",
                "codecommit:GetBranch",
                "codecommit:GetCommit",
                "codecommit:GetDifferences",
                "codecommit:GetPullRequest",
                "codecommit:ListPullRequests",
                "codecommit:GetMergeCommit",
                "codecommit:GetMergeConflicts",
                "codecommit:GetMergeOptions",
                "codecommit:PostCommentForPullRequest",
                "codecommit:UpdatePullRequestTitle",
                "codecommit:UpdatePullRequestDescription",
            ],
            resources=[self.repository.repository_arn],
        )

        sns_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["sns:Publish"],
            resources=[
                self.pull_request_topic.topic_arn,
                self.merge_topic.topic_arn,
                self.quality_gate_topic.topic_arn,
                self.security_alert_topic.topic_arn,
            ],
        )

        cloudwatch_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["cloudwatch:PutMetricData"],
            resources=["*"],
        )

        self.lambda_execution_role.add_to_policy(codecommit_policy)
        self.lambda_execution_role.add_to_policy(sns_policy)
        self.lambda_execution_role.add_to_policy(cloudwatch_policy)

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for workflow automation."""
        # Pull Request automation function
        self.pull_request_function = lambda_.Function(
            self,
            "PullRequestAutomationFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="pull_request_automation.lambda_handler",
            code=lambda_.Code.from_asset("lambda/pull_request_automation"),
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automation for CodeCommit pull request workflows",
            environment={
                "PULL_REQUEST_TOPIC_ARN": self.pull_request_topic.topic_arn,
                "MERGE_TOPIC_ARN": self.merge_topic.topic_arn,
                "QUALITY_GATE_TOPIC_ARN": self.quality_gate_topic.topic_arn,
                "REPOSITORY_NAME": self.repository_name,
            },
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )

        # Quality Gate automation function
        self.quality_gate_function = lambda_.Function(
            self,
            "QualityGateAutomationFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="quality_gate_automation.lambda_handler",
            code=lambda_.Code.from_asset("lambda/quality_gate_automation"),
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            description="Quality gate automation for CodeCommit repositories",
            environment={
                "QUALITY_GATE_TOPIC_ARN": self.quality_gate_topic.topic_arn,
                "SECURITY_ALERT_TOPIC_ARN": self.security_alert_topic.topic_arn,
                "REPOSITORY_NAME": self.repository_name,
            },
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )

        # Branch Protection automation function
        self.branch_protection_function = lambda_.Function(
            self,
            "BranchProtectionFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="branch_protection.lambda_handler",
            code=lambda_.Code.from_asset("lambda/branch_protection"),
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Automated branch protection enforcement",
            environment={
                "REPOSITORY_NAME": self.repository_name,
            },
            log_retention=logs.RetentionDays.TWO_WEEKS,
        )

        # Grant repository trigger permissions to quality gate function
        self.quality_gate_function.add_permission(
            "CodeCommitTriggerPermission",
            principal=iam.ServicePrincipal("codecommit.amazonaws.com"),
            source_arn=self.repository.repository_arn,
        )

    def _create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for pull request events."""
        # EventBridge rule for pull request events
        self.pull_request_rule = events.Rule(
            self,
            "PullRequestRule",
            rule_name=f"codecommit-pull-request-events-{self.repository_name}",
            description="Capture CodeCommit pull request events",
            event_pattern=events.EventPattern(
                source=["aws.codecommit"],
                detail_type=["CodeCommit Pull Request State Change"],
                detail={
                    "repositoryName": [self.repository_name],
                },
            ),
        )

        # Add Lambda target to EventBridge rule
        self.pull_request_rule.add_target(
            targets.LambdaFunction(
                self.pull_request_function,
                retry_attempts=2,
            )
        )

        # Grant EventBridge permission to invoke Lambda
        self.pull_request_function.add_permission(
            "EventBridgeInvokePermission",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            source_arn=self.pull_request_rule.rule_arn,
        )

    def _create_approval_rule_template(self) -> None:
        """Create approval rule template for pull requests."""
        # Create approval rule template content
        approval_rule_content = {
            "Version": "2018-11-08",
            "DestinationReferences": ["refs/heads/main", "refs/heads/master", "refs/heads/develop"],
            "Statements": [
                {
                    "Type": "Approvers",
                    "NumberOfApprovalsNeeded": 2,
                    "ApprovalPoolMembers": [
                        f"arn:aws:iam::{self.account}:user/{self.team_lead_user}"
                    ] + [
                        f"arn:aws:iam::{self.account}:user/{dev}"
                        for dev in self.senior_developers
                    ],
                }
            ],
        }

        # Create approval rule template using CloudFormation custom resource
        # This would be implemented with a Lambda-backed custom resource
        # to create and associate the approval rule template

    def _create_monitoring_dashboard(self) -> None:
        """Create CloudWatch dashboard for Git workflow monitoring."""
        self.dashboard = cloudwatch.Dashboard(
            self,
            "GitWorkflowDashboard",
            dashboard_name=f"Git-Workflow-{self.repository_name}",
        )

        # Pull Request activity widget
        pr_activity_widget = cloudwatch.GraphWidget(
            title="Pull Request Activity",
            left=[
                cloudwatch.Metric(
                    namespace="CodeCommit/PullRequests",
                    metric_name="PullRequestsCreated",
                    dimensions_map={"Repository": self.repository_name},
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="CodeCommit/PullRequests",
                    metric_name="PullRequestsMerged",
                    dimensions_map={"Repository": self.repository_name},
                    statistic="Sum",
                ),
                cloudwatch.Metric(
                    namespace="CodeCommit/PullRequests",
                    metric_name="PullRequestsClosed",
                    dimensions_map={"Repository": self.repository_name},
                    statistic="Sum",
                ),
            ],
            period=Duration.minutes(5),
            width=12,
            height=6,
        )

        # Quality Gate success rate widget
        quality_gate_widget = cloudwatch.GraphWidget(
            title="Quality Gate Success Rate",
            left=[
                cloudwatch.Metric(
                    namespace="CodeCommit/QualityGates",
                    metric_name="QualityChecksResult",
                    dimensions_map={"Repository": self.repository_name},
                    statistic="Average",
                )
            ],
            period=Duration.minutes(5),
            width=12,
            height=6,
            left_y_axis=cloudwatch.YAxisProps(min=0, max=1),
        )

        # Individual quality checks widget
        quality_checks_widget = cloudwatch.GraphWidget(
            title="Individual Quality Checks",
            left=[
                cloudwatch.Metric(
                    namespace="CodeCommit/QualityGates",
                    metric_name="QualityCheck_lint_check",
                    dimensions_map={
                        "Repository": self.repository_name,
                        "CheckType": "lint_check",
                    },
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="CodeCommit/QualityGates",
                    metric_name="QualityCheck_security_scan",
                    dimensions_map={
                        "Repository": self.repository_name,
                        "CheckType": "security_scan",
                    },
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="CodeCommit/QualityGates",
                    metric_name="QualityCheck_test_coverage",
                    dimensions_map={
                        "Repository": self.repository_name,
                        "CheckType": "test_coverage",
                    },
                    statistic="Average",
                ),
                cloudwatch.Metric(
                    namespace="CodeCommit/QualityGates",
                    metric_name="QualityCheck_dependency_check",
                    dimensions_map={
                        "Repository": self.repository_name,
                        "CheckType": "dependency_check",
                    },
                    statistic="Average",
                ),
            ],
            period=Duration.minutes(5),
            width=8,
            height=6,
        )

        # Recent pull request events log widget
        log_widget = cloudwatch.LogQueryWidget(
            title="Recent Pull Request Events",
            log_groups=[self.pull_request_function.log_group],
            query_lines=[
                "fields @timestamp, @message",
                "filter @message like /Pull request/",
                "sort @timestamp desc",
                "limit 20",
            ],
            width=16,
            height=6,
        )

        # Add widgets to dashboard
        self.dashboard.add_widgets(pr_activity_widget, quality_gate_widget)
        self.dashboard.add_widgets(quality_checks_widget, log_widget)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "RepositoryName",
            value=self.repository.repository_name,
            description="Name of the CodeCommit repository",
        )

        CfnOutput(
            self,
            "RepositoryCloneUrl",
            value=self.repository.repository_clone_url_http,
            description="HTTPS clone URL for the repository",
        )

        CfnOutput(
            self,
            "PullRequestTopicArn",
            value=self.pull_request_topic.topic_arn,
            description="ARN of the pull request notifications topic",
        )

        CfnOutput(
            self,
            "QualityGateTopicArn",
            value=self.quality_gate_topic.topic_arn,
            description="ARN of the quality gate notifications topic",
        )

        CfnOutput(
            self,
            "PullRequestFunctionName",
            value=self.pull_request_function.function_name,
            description="Name of the pull request automation Lambda function",
        )

        CfnOutput(
            self,
            "QualityGateFunctionName",
            value=self.quality_gate_function.function_name,
            description="Name of the quality gate automation Lambda function",
        )

        if self.enable_monitoring:
            CfnOutput(
                self,
                "DashboardUrl",
                value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
                description="URL to the CloudWatch dashboard",
            )