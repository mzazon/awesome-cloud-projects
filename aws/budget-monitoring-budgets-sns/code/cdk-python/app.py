#!/usr/bin/env python3
"""
CDK Python Application for Budget Monitoring with AWS Budgets and SNS

This application creates:
- An SNS topic for budget notifications
- An email subscription to the SNS topic
- A monthly budget with multiple notification thresholds
- IAM service-linked role for budgets (if needed)

The budget monitors overall AWS account spending with alerts at 80% and 100%
thresholds for both actual and forecasted costs.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    CfnParameter,
    Duration,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_budgets as budgets,
    aws_iam as iam,
)
from constructs import Construct


class BudgetMonitoringStack(Stack):
    """
    Stack for implementing budget monitoring with AWS Budgets and SNS notifications.
    
    Creates a comprehensive budget monitoring solution with:
    - SNS topic for reliable notification delivery
    - Email subscription with confirmation requirement
    - Monthly budget with $100 default limit
    - Multiple alert thresholds (80% and 100%)
    - Both actual and forecasted cost notifications
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.notification_email = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address to receive budget notifications",
            constraint_description="Must be a valid email address",
            allowed_pattern=r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
        )

        self.budget_amount = CfnParameter(
            self,
            "BudgetAmount",
            type="Number",
            description="Monthly budget amount in USD",
            default=100,
            min_value=1,
            max_value=1000000
        )

        self.budget_name_prefix = CfnParameter(
            self,
            "BudgetNamePrefix",
            type="String",
            description="Prefix for budget name (will be suffixed with account ID)",
            default="monthly-cost-budget",
            allowed_pattern=r"^[a-zA-Z0-9\-_]+$",
            constraint_description="Must contain only alphanumeric characters, hyphens, and underscores"
        )

        # Create SNS topic for budget notifications
        self.notification_topic = self._create_notification_topic()
        
        # Create email subscription
        self._create_email_subscription()
        
        # Create budget with notifications
        self._create_budget_with_notifications()
        
        # Create outputs
        self._create_outputs()

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for budget notifications with appropriate configuration.
        
        Returns:
            sns.Topic: The created SNS topic for budget alerts
        """
        topic = sns.Topic(
            self,
            "BudgetNotificationTopic",
            display_name="Budget Alerts",
            topic_name=f"budget-alerts-{self.account}",
            enforce_ssl=True,  # Security best practice
        )

        # Add topic policy for AWS Budgets service
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                sid="AllowBudgetsServiceToPublish",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("budgets.amazonaws.com")],
                actions=["sns:Publish"],
                resources=[topic.topic_arn],
                conditions={
                    "StringEquals": {
                        "aws:SourceAccount": self.account
                    }
                }
            )
        )

        return topic

    def _create_email_subscription(self) -> None:
        """
        Create email subscription to the SNS topic.
        
        Note: The subscription will require email confirmation after deployment.
        """
        subscription = subscriptions.EmailSubscription(
            self.notification_email.value_as_string
        )
        
        self.notification_topic.add_subscription(subscription)

    def _create_budget_with_notifications(self) -> None:
        """
        Create AWS Budget with comprehensive notification configuration.
        
        Creates a monthly cost budget with multiple notification thresholds:
        - 80% actual spend threshold
        - 100% actual spend threshold  
        - 80% forecasted spend threshold
        """
        # Generate unique budget name using account ID
        budget_name = f"{self.budget_name_prefix.value_as_string}-{self.account}"

        # Create notification configurations
        notifications_with_subscribers = [
            # 80% actual spend notification
            budgets.CfnBudget.NotificationWithSubscribersProperty(
                notification=budgets.CfnBudget.NotificationProperty(
                    comparison_operator="GREATER_THAN",
                    notification_type="ACTUAL",
                    threshold=80,
                    threshold_type="PERCENTAGE"
                ),
                subscribers=[
                    budgets.CfnBudget.SubscriberProperty(
                        address=self.notification_topic.topic_arn,
                        subscription_type="SNS"
                    )
                ]
            ),
            # 100% actual spend notification
            budgets.CfnBudget.NotificationWithSubscribersProperty(
                notification=budgets.CfnBudget.NotificationProperty(
                    comparison_operator="GREATER_THAN",
                    notification_type="ACTUAL",
                    threshold=100,
                    threshold_type="PERCENTAGE"
                ),
                subscribers=[
                    budgets.CfnBudget.SubscriberProperty(
                        address=self.notification_topic.topic_arn,
                        subscription_type="SNS"
                    )
                ]
            ),
            # 80% forecasted spend notification
            budgets.CfnBudget.NotificationWithSubscribersProperty(
                notification=budgets.CfnBudget.NotificationProperty(
                    comparison_operator="GREATER_THAN",
                    notification_type="FORECASTED",
                    threshold=80,
                    threshold_type="PERCENTAGE"
                ),
                subscribers=[
                    budgets.CfnBudget.SubscriberProperty(
                        address=self.notification_topic.topic_arn,
                        subscription_type="SNS"
                    )
                ]
            )
        ]

        # Create the budget
        self.budget = budgets.CfnBudget(
            self,
            "MonthlyBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=budget_name,
                budget_type="COST",
                time_unit="MONTHLY",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=self.budget_amount.value_as_number,
                    unit="USD"
                ),
                cost_types=budgets.CfnBudget.CostTypesProperty(
                    include_credit=True,
                    include_discount=True,
                    include_other_subscription=True,
                    include_recurring=True,
                    include_refund=True,
                    include_subscription=True,
                    include_support=True,
                    include_tax=True,
                    include_upfront=True,
                    use_blended=False
                ),
                # Time period starts from current month and extends to far future
                time_period=budgets.CfnBudget.TimePeriodProperty(
                    start="2025-01-01T00:00:00Z",
                    end="2087-06-15T00:00:00Z"  # AWS Budgets maximum end date
                )
            ),
            notifications_with_subscribers=notifications_with_subscribers
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "SNSTopicArn",
            description="ARN of the SNS topic for budget notifications",
            value=self.notification_topic.topic_arn,
            export_name=f"{self.stack_name}-SNSTopicArn"
        )

        CfnOutput(
            self,
            "BudgetName",
            description="Name of the created budget",
            value=self.budget.budget.budget_name,
            export_name=f"{self.stack_name}-BudgetName"
        )

        CfnOutput(
            self,
            "NotificationEmail",
            description="Email address configured for budget notifications",
            value=self.notification_email.value_as_string,
            export_name=f"{self.stack_name}-NotificationEmail"
        )

        CfnOutput(
            self,
            "BudgetAmount",
            description="Monthly budget amount in USD",
            value=str(self.budget_amount.value_as_number),
            export_name=f"{self.stack_name}-BudgetAmount"
        )


class BudgetMonitoringApp(cdk.App):
    """
    CDK Application for Budget Monitoring.
    
    This application creates all the necessary infrastructure for comprehensive
    budget monitoring using AWS Budgets and SNS notifications.
    """

    def __init__(self):
        super().__init__()

        # Environment configuration
        env = cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
        )

        # Create the main stack
        BudgetMonitoringStack(
            self,
            "BudgetMonitoringStack",
            env=env,
            description="Budget monitoring solution with AWS Budgets and SNS notifications",
            tags={
                "Project": "BudgetMonitoring",
                "Environment": "Production",
                "Purpose": "CostManagement",
                "Recipe": "budget-monitoring-budgets-sns"
            }
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = BudgetMonitoringApp()
    app.synth()


if __name__ == "__main__":
    main()