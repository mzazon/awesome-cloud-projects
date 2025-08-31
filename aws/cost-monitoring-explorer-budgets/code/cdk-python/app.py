#!/usr/bin/env python3
"""
AWS CDK Python application for Cost Monitoring with Cost Explorer and Budgets.

This application creates:
- SNS topic for budget notifications
- AWS Budget with multiple alert thresholds
- Email subscription for notifications

The budget monitors monthly spending with alerts at 50%, 75%, 90% actual spend
and 100% forecasted spend thresholds.
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    CfnParameter,
    aws_sns as sns,
    aws_budgets as budgets,
    RemovalPolicy,
)
from constructs import Construct


class CostMonitoringStack(Stack):
    """
    Stack for implementing comprehensive cost monitoring using AWS Budgets and SNS.
    
    This stack creates a complete cost monitoring solution with:
    - SNS topic for budget alert notifications
    - Monthly budget with configurable spending limit
    - Multiple notification thresholds (50%, 75%, 90% actual, 100% forecasted)
    - Email subscription for real-time alerts
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        budget_limit: float = 100.0,
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Cost Monitoring Stack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            budget_limit: Monthly budget limit in USD (default: 100.0)
            notification_email: Email address for budget notifications
            **kwargs: Additional keyword arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        email_param = CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address to receive budget notifications",
            default=notification_email or "your-email@example.com",
            constraint_description="Must be a valid email address"
        )

        budget_limit_param = CfnParameter(
            self,
            "BudgetLimit",
            type="Number",
            description="Monthly budget limit in USD",
            default=budget_limit,
            min_value=1,
            max_value=10000,
            constraint_description="Budget limit must be between $1 and $10,000"
        )

        # Create SNS topic for budget notifications
        self.notification_topic = self._create_notification_topic()

        # Create email subscription
        self.email_subscription = self._create_email_subscription(
            email_param.value_as_string
        )

        # Create budget with multiple alert thresholds
        self.budget = self._create_monthly_budget(
            budget_limit_param.value_as_number
        )

        # Create outputs
        self._create_outputs()

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for budget notifications.

        Returns:
            sns.Topic: The created SNS topic for budget alerts
        """
        topic = sns.Topic(
            self,
            "BudgetAlertsTopic",
            topic_name=f"budget-alerts-{self.stack_name.lower()}",
            display_name="AWS Budget Alerts",
            fifo=False
        )

        # Apply removal policy for cleanup
        topic.apply_removal_policy(RemovalPolicy.DESTROY)

        return topic

    def _create_email_subscription(self, email_address: str) -> sns.Subscription:
        """
        Create email subscription to the SNS topic.

        Args:
            email_address: Email address for notifications

        Returns:
            sns.Subscription: The email subscription
        """
        subscription = sns.Subscription(
            self,
            "EmailSubscription",
            topic=self.notification_topic,
            protocol=sns.SubscriptionProtocol.EMAIL,
            endpoint=email_address
        )

        return subscription

    def _create_monthly_budget(self, budget_limit: float) -> budgets.CfnBudget:
        """
        Create monthly cost budget with multiple notification thresholds.

        Args:
            budget_limit: Monthly budget limit in USD

        Returns:
            budgets.CfnBudget: The created budget resource
        """
        # Get current account ID for budget configuration
        account_id = self.account

        # Define budget configuration
        budget_config = budgets.CfnBudget.BudgetDataProperty(
            budget_name=f"monthly-cost-budget-{self.stack_name.lower()}",
            budget_limit=budgets.CfnBudget.SpendProperty(
                amount=budget_limit,
                unit="USD"
            ),
            time_unit="MONTHLY",
            time_period=budgets.CfnBudget.TimePeriodProperty(
                start="2024-01-01_00:00",
                end="2087-06-15_00:00"  # Far future end date
            ),
            budget_type="COST",
            cost_filters={},
            cost_types=budgets.CfnBudget.CostTypesProperty(
                include_tax=True,
                include_subscription=True,
                use_blended=False,
                include_refund=False,
                include_credit=False,
                include_upfront=True,
                include_recurring=True,
                include_other_subscription=True,
                include_support=True,
                include_discount=True,
                use_amortized=False
            )
        )

        # Create notification configurations for different thresholds
        notifications = self._create_budget_notifications()

        # Create the budget
        budget = budgets.CfnBudget(
            self,
            "MonthlyCostBudget",
            budget=budget_config,
            notifications_with_subscribers=notifications
        )

        return budget

    def _create_budget_notifications(self) -> list:
        """
        Create notification configurations for different budget thresholds.

        Returns:
            list: List of notification configurations with subscribers
        """
        # SNS topic ARN for notifications
        topic_arn = self.notification_topic.topic_arn

        # Define notification thresholds and types
        notification_configs = [
            {
                "threshold": 50.0,
                "notification_type": "ACTUAL",
                "description": "Early warning at 50% of budget"
            },
            {
                "threshold": 75.0,
                "notification_type": "ACTUAL",
                "description": "Serious concern at 75% of budget"
            },
            {
                "threshold": 90.0,
                "notification_type": "ACTUAL",
                "description": "Critical alert at 90% of budget"
            },
            {
                "threshold": 100.0,
                "notification_type": "FORECASTED",
                "description": "Forecasted overspend alert"
            }
        ]

        notifications = []
        for config in notification_configs:
            notification = budgets.CfnBudget.NotificationWithSubscribersProperty(
                notification=budgets.CfnBudget.NotificationProperty(
                    notification_type=config["notification_type"],
                    comparison_operator="GREATER_THAN",
                    threshold=config["threshold"],
                    threshold_type="PERCENTAGE",
                    notification_state="ALARM"
                ),
                subscribers=[
                    budgets.CfnBudget.SubscriberProperty(
                        subscription_type="SNS",
                        address=topic_arn
                    )
                ]
            )
            notifications.append(notification)

        return notifications

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for budget notifications",
            export_name=f"{self.stack_name}-SNSTopicArn"
        )

        CfnOutput(
            self,
            "SNSTopicName",
            value=self.notification_topic.topic_name,
            description="Name of the SNS topic for budget notifications",
            export_name=f"{self.stack_name}-SNSTopicName"
        )

        CfnOutput(
            self,
            "BudgetName",
            value=self.budget.budget.budget_name,
            description="Name of the created monthly cost budget",
            export_name=f"{self.stack_name}-BudgetName"
        )


class CostMonitoringApp(cdk.App):
    """
    CDK Application for Cost Monitoring infrastructure.
    
    This application creates the complete cost monitoring solution including
    SNS notifications and AWS Budgets with multiple alert thresholds.
    """

    def __init__(self):
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        budget_limit = float(os.getenv("BUDGET_LIMIT", "100.0"))
        notification_email = os.getenv("NOTIFICATION_EMAIL")
        
        # Create the cost monitoring stack
        CostMonitoringStack(
            self,
            "CostMonitoringStack",
            budget_limit=budget_limit,
            notification_email=notification_email,
            description="Cost monitoring solution with AWS Budgets and SNS notifications",
            env=cdk.Environment(
                account=os.getenv("CDK_DEFAULT_ACCOUNT"),
                region=os.getenv("CDK_DEFAULT_REGION", "us-east-1")
            )
        )


def main():
    """Main entry point for the CDK application."""
    app = CostMonitoringApp()
    app.synth()


if __name__ == "__main__":
    main()