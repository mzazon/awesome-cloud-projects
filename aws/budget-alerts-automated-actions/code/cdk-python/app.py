#!/usr/bin/env python3
"""
AWS CDK application for Budget Alerts and Automated Actions.

This application creates a comprehensive budget monitoring system with automated
cost control actions using AWS Budgets, SNS, Lambda, and IAM policies.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    aws_budgets as budgets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
import json
from typing import List, Dict, Any


class BudgetAlertsStack(Stack):
    """
    CDK Stack for Budget Alerts and Automated Actions.
    
    This stack creates:
    - AWS Budget with multiple alert thresholds
    - SNS topic for notifications
    - Lambda function for automated actions
    - IAM roles and policies for budget actions
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        budget_amount: float = 100.0,
        budget_email: str = "admin@example.com",
        **kwargs
    ) -> None:
        """
        Initialize the Budget Alerts Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            budget_amount: Monthly budget limit in USD
            budget_email: Email address for budget notifications
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store parameters
        self.budget_amount = budget_amount
        self.budget_email = budget_email

        # Create SNS topic for budget notifications
        self.sns_topic = self._create_sns_topic()

        # Create Lambda execution role
        self.lambda_role = self._create_lambda_execution_role()

        # Create Lambda function for automated actions
        self.lambda_function = self._create_budget_action_lambda()

        # Create Budget Actions IAM role and policy
        self.budget_action_role = self._create_budget_action_role()

        # Create the budget with notifications
        self.budget = self._create_budget()

        # Add Lambda subscription to SNS topic
        self._add_lambda_subscription()

        # Create outputs
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for budget notifications.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "BudgetAlertsTopic",
            topic_name=f"budget-alerts-{self.account}-{self.region}",
            display_name="Budget Alerts Topic",
            description="SNS topic for AWS Budget alerts and notifications"
        )

        # Add email subscription
        topic.add_subscription(
            subscriptions.EmailSubscription(self.budget_email)
        )

        # Add tags
        cdk.Tags.of(topic).add("Application", "BudgetMonitoring")
        cdk.Tags.of(topic).add("Environment", "Production")

        return topic

    def _create_lambda_execution_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function execution.
        
        Returns:
            iam.Role: The Lambda execution role
        """
        role = iam.Role(
            self,
            "BudgetLambdaExecutionRole",
            role_name=f"budget-lambda-role-{self.account}-{self.region}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for budget action Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add custom policy for budget actions
        policy_document = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "ec2:DescribeInstances",
                        "ec2:StopInstances",
                        "ec2:StartInstances",
                        "ec2:DescribeInstanceStatus"
                    ],
                    resources=["*"],
                    sid="EC2InstanceManagement"
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=["sns:Publish"],
                    resources=[self.sns_topic.topic_arn],
                    sid="SNSPublishPermissions"
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "budgets:ViewBudget",
                        "budgets:ModifyBudget"
                    ],
                    resources=["*"],
                    sid="BudgetManagement"
                )
            ]
        )

        iam.Policy(
            self,
            "BudgetActionPolicy",
            policy_name=f"budget-action-policy-{self.account}-{self.region}",
            policy_document=policy_document,
            roles=[role]
        )

        return role

    def _create_budget_action_lambda(self) -> lambda_.Function:
        """
        Create Lambda function for automated budget actions.
        
        Returns:
            lambda_.Function: The Lambda function
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Lambda handler for processing budget alert events.
    
    This function processes SNS messages from AWS Budgets and takes
    automated actions like stopping development EC2 instances.
    """
    try:
        # Parse the budget alert event
        for record in event.get('Records', []):
            if record.get('EventSource') == 'aws:sns':
                message = json.loads(record['Sns']['Message'])
                
                budget_name = message.get('BudgetName', 'Unknown')
                account_id = message.get('AccountId', 'Unknown')
                alert_type = message.get('AlertType', 'Unknown')
                
                logger.info(f"Budget alert triggered: {budget_name} in account {account_id} ({alert_type})")
                
                # Initialize AWS clients
                ec2 = boto3.client('ec2')
                sns = boto3.client('sns')
                
                # Get development instances (tagged as Environment=Development)
                response = ec2.describe_instances(
                    Filters=[
                        {'Name': 'tag:Environment', 'Values': ['Development', 'Dev', 'development']},
                        {'Name': 'instance-state-name', 'Values': ['running']}
                    ]
                )
                
                instances_to_stop = []
                for reservation in response['Reservations']:
                    for instance in reservation['Instances']:
                        instances_to_stop.append(instance['InstanceId'])
                
                # Stop development instances if any found
                if instances_to_stop:
                    ec2.stop_instances(InstanceIds=instances_to_stop)
                    logger.info(f"Stopped {len(instances_to_stop)} development instances")
                    
                    # Send notification about action taken
                    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
                    if sns_topic_arn:
                        sns.publish(
                            TopicArn=sns_topic_arn,
                            Subject=f'Budget Action Executed - {budget_name}',
                            Message=f'''Budget Alert Response Action Completed

Budget: {budget_name}
Account: {account_id}
Alert Type: {alert_type}

Automated Action: Stopped {len(instances_to_stop)} development instances to control costs.

Affected Instances:
{chr(10).join(f"- {instance_id}" for instance_id in instances_to_stop)}

This is an automated response to budget threshold violations.
Review your resource usage and adjust budgets as needed.
                            '''
                        )
                else:
                    logger.info("No development instances found to stop")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Budget action processing completed successfully',
                'instances_processed': len(instances_to_stop) if 'instances_to_stop' in locals() else 0
            })
        }
        
    except Exception as e:
        logger.error(f"Error executing budget action: {str(e)}")
        raise e
'''

        function = lambda_.Function(
            self,
            "BudgetActionFunction",
            function_name=f"budget-action-{self.account}-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(2),
            description="Automated budget action function for cost control",
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )

        # Add tags
        cdk.Tags.of(function).add("Application", "BudgetMonitoring")
        cdk.Tags.of(function).add("Environment", "Production")

        return function

    def _create_budget_action_role(self) -> iam.Role:
        """
        Create IAM role for AWS Budgets service to execute actions.
        
        Returns:
            iam.Role: The budget action role
        """
        role = iam.Role(
            self,
            "BudgetActionServiceRole",
            role_name=f"budget-action-service-role-{self.account}-{self.region}",
            assumed_by=iam.ServicePrincipal("budgets.amazonaws.com"),
            description="Service role for AWS Budgets to execute automated actions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/BudgetsActionsWithAWSResourceControlAccess"
                )
            ]
        )

        # Create restrictive policy for budget actions
        restrictive_policy = iam.Policy(
            self,
            "BudgetRestrictionPolicy",
            policy_name=f"budget-restriction-policy-{self.account}-{self.region}",
            policy_document=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.DENY,
                        actions=[
                            "ec2:RunInstances",
                            "ec2:StartInstances",
                            "rds:CreateDBInstance",
                            "rds:StartDBInstance"
                        ],
                        resources=["*"],
                        conditions={
                            "StringNotEquals": {
                                "ec2:InstanceType": [
                                    "t3.nano",
                                    "t3.micro",
                                    "t3.small"
                                ]
                            }
                        }
                    )
                ]
            )
        )

        return role

    def _create_budget(self) -> budgets.CfnBudget:
        """
        Create AWS Budget with multiple notification thresholds.
        
        Returns:
            budgets.CfnBudget: The created budget
        """
        # Define budget configuration
        budget_config = {
            "budget_name": f"cost-control-budget-{self.account}-{self.region}",
            "budget_limit": {
                "amount": str(self.budget_amount),
                "unit": "USD"
            },
            "budget_type": "COST",
            "cost_types": {
                "include_credit": False,
                "include_discount": True,
                "include_other_subscription": True,
                "include_recurring": True,
                "include_refund": True,
                "include_subscription": True,
                "include_support": True,
                "include_tax": True,
                "include_upfront": True,
                "use_blended": False,
                "use_amortized": False
            },
            "time_unit": "MONTHLY"
        }

        # Define notification configurations
        notifications = [
            {
                "notification": {
                    "notification_type": "ACTUAL",
                    "comparison_operator": "GREATER_THAN",
                    "threshold": 80,
                    "threshold_type": "PERCENTAGE"
                },
                "subscribers": [
                    {
                        "subscription_type": "EMAIL",
                        "address": self.budget_email
                    },
                    {
                        "subscription_type": "SNS",
                        "address": self.sns_topic.topic_arn
                    }
                ]
            },
            {
                "notification": {
                    "notification_type": "FORECASTED",
                    "comparison_operator": "GREATER_THAN",
                    "threshold": 90,
                    "threshold_type": "PERCENTAGE"
                },
                "subscribers": [
                    {
                        "subscription_type": "EMAIL",
                        "address": self.budget_email
                    },
                    {
                        "subscription_type": "SNS",
                        "address": self.sns_topic.topic_arn
                    }
                ]
            },
            {
                "notification": {
                    "notification_type": "ACTUAL",
                    "comparison_operator": "GREATER_THAN",
                    "threshold": 100,
                    "threshold_type": "PERCENTAGE"
                },
                "subscribers": [
                    {
                        "subscription_type": "EMAIL",
                        "address": self.budget_email
                    },
                    {
                        "subscription_type": "SNS",
                        "address": self.sns_topic.topic_arn
                    }
                ]
            }
        ]

        budget = budgets.CfnBudget(
            self,
            "CostControlBudget",
            budget=budget_config,
            notifications_with_subscribers=notifications
        )

        return budget

    def _add_lambda_subscription(self) -> None:
        """Add Lambda function as subscriber to SNS topic."""
        self.sns_topic.add_subscription(
            subscriptions.LambdaSubscription(self.lambda_function)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "BudgetName",
            value=f"cost-control-budget-{self.account}-{self.region}",
            description="Name of the created budget"
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for budget alerts"
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function for automated actions"
        )

        CfnOutput(
            self,
            "BudgetAmount",
            value=str(self.budget_amount),
            description="Monthly budget amount in USD"
        )

        CfnOutput(
            self,
            "NotificationEmail",
            value=self.budget_email,
            description="Email address receiving budget notifications"
        )


class BudgetAlertsApp(cdk.App):
    """CDK Application for Budget Alerts and Automated Actions."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get context values or use defaults
        budget_amount = float(self.node.try_get_context("budget_amount") or 100.0)
        budget_email = self.node.try_get_context("budget_email") or "admin@example.com"
        
        # Create the stack
        BudgetAlertsStack(
            self,
            "BudgetAlertsStack",
            budget_amount=budget_amount,
            budget_email=budget_email,
            description="AWS Budget alerts with automated cost control actions",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


# Create and run the app
app = BudgetAlertsApp()
app.synth()