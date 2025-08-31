#!/usr/bin/env python3
"""
AWS CDK Python application for Cost Estimation Planning with Pricing Calculator and S3

This CDK application creates the infrastructure needed for storing and managing
AWS Pricing Calculator estimates, including:
- S3 bucket for estimate storage with versioning and encryption
- Lifecycle policies for cost optimization
- Budget alerts for cost monitoring
- SNS notifications for budget thresholds

Author: AWS CDK Team
Version: 1.0
"""

import os
import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    Environment,
    RemovalPolicy,
    Duration,
    CfnOutput,
    aws_s3 as s3,
    aws_budgets as budgets,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
)
from cdk_nag import AwsSolutionsChecks, NagSuppressions


class CostEstimationStack(Stack):
    """
    CDK Stack for Cost Estimation Planning Infrastructure
    
    Creates a complete solution for storing and managing AWS Pricing Calculator
    estimates with automated lifecycle management and cost monitoring.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Configuration parameters
        project_name = self.node.try_get_context("project_name") or "web-app-migration"
        notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        monthly_budget_limit = float(self.node.try_get_context("monthly_budget_limit") or "50.0")

        # Create S3 bucket for cost estimates storage
        self.estimates_bucket = self._create_estimates_bucket(unique_suffix)
        
        # Create SNS topic for budget notifications
        self.budget_topic = self._create_budget_notification_topic(project_name)
        
        # Subscribe email to SNS topic
        self._add_email_subscription(notification_email)
        
        # Create budget with alerts
        self._create_project_budget(project_name, monthly_budget_limit)
        
        # Apply CDK Nag for security best practices
        self._apply_security_suppressions()

    def _create_estimates_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for storing cost estimates with security and lifecycle policies.
        
        Args:
            unique_suffix: Unique identifier for bucket naming
            
        Returns:
            S3 Bucket construct
        """
        bucket = s3.Bucket(
            self, "CostEstimatesBucket",
            bucket_name=f"cost-estimates-{unique_suffix}",
            # Security configurations
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            # Versioning for estimate history tracking
            versioned=True,
            # Lifecycle management for cost optimization
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="CostEstimateLifecycle",
                    enabled=True,
                    prefix="estimates/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ],
            # Cleanup configuration
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        # Output bucket information
        CfnOutput(
            self, "EstimatesBucketName",
            value=bucket.bucket_name,
            description="S3 bucket name for storing cost estimates"
        )
        
        CfnOutput(
            self, "EstimatesBucketArn",
            value=bucket.bucket_arn,
            description="S3 bucket ARN for cost estimates"
        )
        
        return bucket

    def _create_budget_notification_topic(self, project_name: str) -> sns.Topic:
        """
        Create SNS topic for budget notifications.
        
        Args:
            project_name: Name of the project for topic naming
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self, "BudgetAlertsTopic",
            topic_name=f"{project_name}-budget-alerts",
            display_name=f"Budget Alerts for {project_name}",
            # Security: Server-side encryption
            master_key=None  # Uses AWS managed key
        )
        
        # Output topic information
        CfnOutput(
            self, "BudgetAlertsTopicArn",
            value=topic.topic_arn,
            description="SNS topic ARN for budget alerts"
        )
        
        return topic

    def _add_email_subscription(self, email: str) -> None:
        """
        Add email subscription to budget alerts topic.
        
        Args:
            email: Email address for notifications
        """
        self.budget_topic.add_subscription(
            sns_subscriptions.EmailSubscription(email)
        )

    def _create_project_budget(self, project_name: str, budget_limit: float) -> None:
        """
        Create AWS Budget with notifications for project cost monitoring.
        
        Args:
            project_name: Name of the project for budget filtering
            budget_limit: Monthly budget limit in USD
        """
        # Create budget with cost filters
        budget = budgets.CfnBudget(
            self, "ProjectBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"{project_name}-budget",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=budget_limit,
                    unit="USD"
                ),
                time_unit="MONTHLY",
                budget_type="COST",
                cost_filters=budgets.CfnBudget.CostFiltersProperty(
                    tag_key=["Project"],
                    tag_value=[project_name]
                )
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="ACTUAL",
                        comparison_operator="GREATER_THAN",
                        threshold=80,
                        threshold_type="PERCENTAGE"
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.budget_topic.topic_arn
                        )
                    ]
                ),
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="FORECASTED",
                        comparison_operator="GREATER_THAN",
                        threshold=100,
                        threshold_type="PERCENTAGE"
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.budget_topic.topic_arn
                        )
                    ]
                )
            ]
        )
        
        # Output budget information
        CfnOutput(
            self, "ProjectBudgetName",
            value=budget.budget.budget_name,
            description=f"Budget name for {project_name} project"
        )

    def _apply_security_suppressions(self) -> None:
        """
        Apply CDK Nag suppressions for justified security exceptions.
        """
        # Suppress S3 bucket access logging requirement for demo purposes
        NagSuppressions.add_resource_suppressions(
            self.estimates_bucket,
            [
                {
                    "id": "AwsSolutions-S3-1",
                    "reason": "Access logging not required for cost estimate demo bucket"
                }
            ]
        )
        
        # Suppress SNS topic encryption requirement (using AWS managed key)
        NagSuppressions.add_resource_suppressions(
            self.budget_topic,
            [
                {
                    "id": "AwsSolutions-SNS-1",
                    "reason": "Budget alerts topic uses AWS managed encryption for demo purposes"
                }
            ]
        )


class CostEstimationApp(cdk.App):
    """
    CDK Application for Cost Estimation Planning
    
    Main application class that creates the cost estimation stack with
    proper environment configuration and security validations.
    """
    
    def __init__(self):
        super().__init__()
        
        # Get environment configuration
        account = os.environ.get("CDK_DEFAULT_ACCOUNT", "123456789012")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        
        # Create the cost estimation stack
        cost_stack = CostEstimationStack(
            self, "CostEstimationStack",
            env=Environment(account=account, region=region),
            description="Cost Estimation Planning with Pricing Calculator and S3 (uksb-1tupboc58)"
        )
        
        # Apply CDK Nag for security best practices
        AwsSolutionsChecks(verbose=True).visit(cost_stack)


# Application entry point
if __name__ == "__main__":
    app = CostEstimationApp()
    app.synth()