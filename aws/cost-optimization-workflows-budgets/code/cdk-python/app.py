#!/usr/bin/env python3
"""
CDK Python Application for Automated Cost Optimization Workflows
with AWS Cost Optimization Hub and AWS Budgets

This application creates a comprehensive cost optimization workflow that combines
AWS Cost Optimization Hub for centralized recommendation management with AWS Budgets
for proactive spending controls and SNS notifications for real-time alerts.
"""

import os
from typing import Dict, Any, List
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_budgets as budgets,
    aws_sns as sns,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_ce as ce,
    aws_sns_subscriptions as sns_subscriptions,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct


class CostOptimizationStack(Stack):
    """
    Stack for deploying automated cost optimization workflows with Cost Optimization Hub
    and AWS Budgets integration.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        monthly_budget_limit: int = 1000,
        ec2_usage_limit: int = 2000,
        ri_utilization_threshold: int = 80,
        **kwargs
    ) -> None:
        """
        Initialize the Cost Optimization Stack.

        Args:
            scope: The CDK app scope
            construct_id: Unique identifier for this stack
            notification_email: Email address for budget notifications
            monthly_budget_limit: Monthly cost budget limit in USD
            ec2_usage_limit: EC2 usage budget limit in hours
            ri_utilization_threshold: Reserved Instance utilization threshold percentage
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.notification_email = notification_email
        self.monthly_budget_limit = monthly_budget_limit
        self.ec2_usage_limit = ec2_usage_limit
        self.ri_utilization_threshold = ri_utilization_threshold
        self.account_id = Stack.of(self).account

        # Create SNS topic for notifications
        self.notification_topic = self._create_notification_topic()

        # Create Lambda function for cost optimization automation
        self.cost_optimization_function = self._create_lambda_function()

        # Create IAM role for budget actions
        self.budget_actions_role = self._create_budget_actions_role()

        # Create budgets with notifications
        self.monthly_cost_budget = self._create_monthly_cost_budget()
        self.ec2_usage_budget = self._create_ec2_usage_budget()
        self.ri_utilization_budget = self._create_ri_utilization_budget()

        # Create cost anomaly detection
        self.anomaly_detector = self._create_anomaly_detector()
        self.anomaly_subscription = self._create_anomaly_subscription()

        # Create outputs
        self._create_outputs()

    def _create_notification_topic(self) -> sns.Topic:
        """
        Create SNS topic for budget and cost optimization notifications.

        Returns:
            SNS Topic for notifications
        """
        topic = sns.Topic(
            self,
            "CostOptimizationAlerts",
            topic_name=f"cost-optimization-alerts-{self.node.addr[:8]}",
            display_name="Cost Optimization Alerts",
            description="SNS topic for AWS cost optimization and budget alerts",
        )

        # Subscribe email address to topic
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )

        # Add policy to allow AWS Budgets service to publish
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("budgets.amazonaws.com")],
                actions=["SNS:Publish"],
                resources=[topic.topic_arn],
            )
        )

        # Add policy to allow Cost Anomaly Detection to publish
        topic.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("costalerts.amazonaws.com")],
                actions=["SNS:Publish"],
                resources=[topic.topic_arn],
            )
        )

        return topic

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for cost optimization automation.

        Returns:
            Lambda function for processing cost optimization events
        """
        # Create execution role
        lambda_role = iam.Role(
            self,
            "CostOptimizationLambdaRole",
            role_name=f"CostOptimizationLambdaRole-{self.node.addr[:8]}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "CostOptimizationPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "cost-optimization-hub:GetPreferences",
                                "cost-optimization-hub:ListRecommendations",
                                "cost-optimization-hub:GetRecommendation",
                                "ce:GetCostAndUsage",
                                "ce:GetDimensionValues",
                                "ce:GetAnomalyDetectors",
                                "ce:GetAnomalies",
                                "sns:Publish",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

        # Create Lambda function
        function = lambda_.Function(
            self,
            "CostOptimizationHandler",
            function_name=f"cost-optimization-handler-{self.node.addr[:8]}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=lambda_role,
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Process Cost Optimization Hub recommendations and budget alerts",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
            },
        )

        # Allow SNS to invoke Lambda
        function.add_permission(
            "AllowSNSInvoke",
            principal=iam.ServicePrincipal("sns.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=self.notification_topic.topic_arn,
        )

        return function

    def _create_budget_actions_role(self) -> iam.Role:
        """
        Create IAM role for budget actions with restrictive policies.

        Returns:
            IAM role for budget actions
        """
        # Create restrictive policy for budget actions
        restriction_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.DENY,
                    actions=[
                        "ec2:RunInstances",
                        "ec2:StartInstances",
                        "rds:CreateDBInstance",
                        "rds:CreateDBCluster",
                        "redshift:CreateCluster",
                        "elasticache:CreateCacheCluster",
                    ],
                    resources=["*"],
                    conditions={
                        "StringEquals": {
                            "aws:RequestedRegion": Stack.of(self).region
                        }
                    },
                )
            ]
        )

        # Create role
        role = iam.Role(
            self,
            "BudgetActionsRole",
            role_name=f"BudgetActionsRole-{self.node.addr[:8]}",
            assumed_by=iam.ServicePrincipal("budgets.amazonaws.com"),
            inline_policies={"BudgetRestrictionPolicy": restriction_policy},
            description="IAM role for AWS Budget actions with restrictive policies",
        )

        return role

    def _create_monthly_cost_budget(self) -> budgets.CfnBudget:
        """
        Create monthly cost budget with notifications.

        Returns:
            Monthly cost budget
        """
        budget = budgets.CfnBudget(
            self,
            "MonthlyCostBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"monthly-cost-budget-{self.node.addr[:8]}",
                budget_type="COST",
                time_unit="MONTHLY",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=self.monthly_budget_limit,
                    unit="USD",
                ),
                cost_filters={},
                time_period=budgets.CfnBudget.TimePeriodProperty(
                    start="2025-01-01_00:00",
                    end="2087-06-15_00:00",  # AWS Budgets requires end date
                ),
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="ACTUAL",
                        comparison_operator="GREATER_THAN",
                        threshold=80,
                        threshold_type="PERCENTAGE",
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.notification_topic.topic_arn,
                        )
                    ],
                ),
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="FORECASTED",
                        comparison_operator="GREATER_THAN",
                        threshold=95,
                        threshold_type="PERCENTAGE",
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.notification_topic.topic_arn,
                        )
                    ],
                ),
            ],
        )

        return budget

    def _create_ec2_usage_budget(self) -> budgets.CfnBudget:
        """
        Create EC2 usage budget with forecasted notifications.

        Returns:
            EC2 usage budget
        """
        budget = budgets.CfnBudget(
            self,
            "EC2UsageBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"ec2-usage-budget-{self.node.addr[:8]}",
                budget_type="USAGE",
                time_unit="MONTHLY",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=self.ec2_usage_limit,
                    unit="HOURS",
                ),
                cost_filters={
                    "Service": ["Amazon Elastic Compute Cloud - Compute"]
                },
                time_period=budgets.CfnBudget.TimePeriodProperty(
                    start="2025-01-01_00:00",
                    end="2087-06-15_00:00",
                ),
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="FORECASTED",
                        comparison_operator="GREATER_THAN",
                        threshold=90,
                        threshold_type="PERCENTAGE",
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.notification_topic.topic_arn,
                        )
                    ],
                )
            ],
        )

        return budget

    def _create_ri_utilization_budget(self) -> budgets.CfnBudget:
        """
        Create Reserved Instance utilization budget.

        Returns:
            RI utilization budget
        """
        budget = budgets.CfnBudget(
            self,
            "RIUtilizationBudget",
            budget=budgets.CfnBudget.BudgetDataProperty(
                budget_name=f"ri-utilization-budget-{self.node.addr[:8]}",
                budget_type="RI_UTILIZATION",
                time_unit="MONTHLY",
                budget_limit=budgets.CfnBudget.SpendProperty(
                    amount=self.ri_utilization_threshold,
                    unit="PERCENT",
                ),
                cost_filters={
                    "Service": ["Amazon Elastic Compute Cloud - Compute"]
                },
                time_period=budgets.CfnBudget.TimePeriodProperty(
                    start="2025-01-01_00:00",
                    end="2087-06-15_00:00",
                ),
            ),
            notifications_with_subscribers=[
                budgets.CfnBudget.NotificationWithSubscribersProperty(
                    notification=budgets.CfnBudget.NotificationProperty(
                        notification_type="ACTUAL",
                        comparison_operator="LESS_THAN",
                        threshold=self.ri_utilization_threshold,
                        threshold_type="PERCENTAGE",
                    ),
                    subscribers=[
                        budgets.CfnBudget.SubscriberProperty(
                            subscription_type="SNS",
                            address=self.notification_topic.topic_arn,
                        )
                    ],
                )
            ],
        )

        return budget

    def _create_anomaly_detector(self) -> ce.CfnAnomalyDetector:
        """
        Create cost anomaly detector for key services.

        Returns:
            Cost anomaly detector
        """
        detector = ce.CfnAnomalyDetector(
            self,
            "CostAnomalyDetector",
            detector_name=f"cost-anomaly-detector-{self.node.addr[:8]}",
            monitor_type="DIMENSIONAL",
            monitor_specification={
                "DimensionKey": "SERVICE",
                "Values": ["Amazon Elastic Compute Cloud - Compute", "Amazon Relational Database Service", "Amazon Simple Storage Service"],
                "MatchOptions": ["EQUALS"],
            },
        )

        return detector

    def _create_anomaly_subscription(self) -> ce.CfnAnomalySubscription:
        """
        Create anomaly subscription for notifications.

        Returns:
            Cost anomaly subscription
        """
        subscription = ce.CfnAnomalySubscription(
            self,
            "CostAnomalySubscription",
            subscription_name=f"cost-anomaly-subscription-{self.node.addr[:8]}",
            frequency="DAILY",
            monitor_arn_list=[self.anomaly_detector.attr_detector_arn],
            subscribers=[
                ce.CfnAnomalySubscription.SubscriberProperty(
                    type="SNS",
                    address=self.notification_topic.topic_arn,
                )
            ],
            threshold_expression=100,  # Alert for anomalies over $100
        )

        subscription.add_dependency(self.anomaly_detector)

        return subscription

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for cost optimization processing.

        Returns:
            Lambda function code as string
        """
        return """
import json
import boto3
import logging
import os
from typing import Dict, Any, List

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    '''
    Process Cost Optimization Hub recommendations and budget alerts.
    
    Args:
        event: Lambda event data
        context: Lambda context
        
    Returns:
        Response dictionary with status and processing results
    '''
    try:
        # Initialize AWS clients
        coh_client = boto3.client('cost-optimization-hub')
        ce_client = boto3.client('ce')
        sns_client = boto3.client('sns')
        
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        logger.info(f"Processing cost optimization event: {json.dumps(event, default=str)}")
        
        # Process SNS messages from budget alerts or anomaly detection
        if 'Records' in event:
            for record in event['Records']:
                if record.get('EventSource') == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    logger.info(f"Processing budget/anomaly alert: {message}")
                    
                    # Get cost optimization recommendations
                    try:
                        recommendations_response = coh_client.list_recommendations(
                            includeAllRecommendations=True,
                            maxResults=50
                        )
                        
                        recommendations = recommendations_response.get('items', [])
                        logger.info(f"Retrieved {len(recommendations)} cost optimization recommendations")
                        
                        # Process and categorize recommendations
                        high_impact_recommendations = []
                        total_potential_savings = 0
                        
                        for rec in recommendations:
                            action_type = rec.get('actionType', 'Unknown')
                            estimated_savings = float(rec.get('estimatedMonthlySavings', {}).get('value', 0))
                            resource_id = rec.get('resourceId', 'N/A')
                            
                            logger.info(
                                f"Recommendation: {rec.get('recommendationId')} - "
                                f"Action: {action_type} - "
                                f"Resource: {resource_id} - "
                                f"Potential Savings: ${estimated_savings:.2f}/month"
                            )
                            
                            total_potential_savings += estimated_savings
                            
                            # Identify high-impact recommendations (>$50/month savings)
                            if estimated_savings > 50:
                                high_impact_recommendations.append({
                                    'id': rec.get('recommendationId'),
                                    'action': action_type,
                                    'resource': resource_id,
                                    'savings': estimated_savings
                                })
                        
                        # Send summary notification if there are significant recommendations
                        if high_impact_recommendations:
                            summary_message = {
                                'alert_type': 'Cost Optimization Recommendations',
                                'total_recommendations': len(recommendations),
                                'high_impact_count': len(high_impact_recommendations),
                                'total_potential_savings': total_potential_savings,
                                'high_impact_recommendations': high_impact_recommendations[:5]  # Top 5
                            }
                            
                            sns_client.publish(
                                TopicArn=sns_topic_arn,
                                Subject='Cost Optimization Recommendations Available',
                                Message=json.dumps(summary_message, indent=2)
                            )
                            
                            logger.info(f"Published recommendation summary with ${total_potential_savings:.2f} potential monthly savings")
                    
                    except Exception as coh_error:
                        logger.warning(f"Could not retrieve Cost Optimization Hub recommendations: {str(coh_error)}")
                        
        # Handle direct invocations for testing
        elif event.get('source') == 'test':
            logger.info("Processing test invocation")
            
            # Test Cost Optimization Hub connectivity
            try:
                preferences = coh_client.get_preferences()
                logger.info(f"Cost Optimization Hub preferences: {preferences}")
                
                return {
                    'statusCode': 200,
                    'body': json.dumps({
                        'message': 'Cost Optimization Hub test successful',
                        'preferences': preferences
                    })
                }
            except Exception as test_error:
                logger.error(f"Cost Optimization Hub test failed: {str(test_error)}")
                return {
                    'statusCode': 500,
                    'body': json.dumps({
                        'error': 'Cost Optimization Hub test failed',
                        'details': str(test_error)
                    })
                }
        
        return {
            'statusCode': 200,
            'body': json.dumps('Cost optimization processing completed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing cost optimization event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
"""

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="SNS Topic ARN for cost optimization notifications",
            export_name=f"{Stack.of(self).stack_name}-SNSTopicArn",
        )

        CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.cost_optimization_function.function_arn,
            description="Lambda function ARN for cost optimization processing",
            export_name=f"{Stack.of(self).stack_name}-LambdaFunctionArn",
        )

        CfnOutput(
            self,
            "MonthlyCostBudgetName",
            value=self.monthly_cost_budget.ref,
            description="Monthly cost budget name",
            export_name=f"{Stack.of(self).stack_name}-MonthlyCostBudget",
        )

        CfnOutput(
            self,
            "AnomalyDetectorArn",
            value=self.anomaly_detector.attr_detector_arn,
            description="Cost anomaly detector ARN",
            export_name=f"{Stack.of(self).stack_name}-AnomalyDetector",
        )


class CostOptimizationApp(cdk.App):
    """CDK Application for Cost Optimization Workflows."""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or context
        notification_email = self.node.try_get_context("notification_email") or os.environ.get(
            "NOTIFICATION_EMAIL", "your-email@example.com"
        )
        
        monthly_budget_limit = int(
            self.node.try_get_context("monthly_budget_limit") or os.environ.get("MONTHLY_BUDGET_LIMIT", "1000")
        )
        
        ec2_usage_limit = int(
            self.node.try_get_context("ec2_usage_limit") or os.environ.get("EC2_USAGE_LIMIT", "2000")
        )
        
        ri_utilization_threshold = int(
            self.node.try_get_context("ri_utilization_threshold") or os.environ.get("RI_UTILIZATION_THRESHOLD", "80")
        )

        # Create the main stack
        CostOptimizationStack(
            self,
            "CostOptimizationStack",
            notification_email=notification_email,
            monthly_budget_limit=monthly_budget_limit,
            ec2_usage_limit=ec2_usage_limit,
            ri_utilization_threshold=ri_utilization_threshold,
            description="Automated Cost Optimization Workflows with Cost Optimization Hub and AWS Budgets",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


# Create the CDK application
app = CostOptimizationApp()

# Add tagging to all resources
cdk.Tags.of(app).add("Project", "CostOptimization")
cdk.Tags.of(app).add("Environment", "Production")
cdk.Tags.of(app).add("Owner", "FinOps")
cdk.Tags.of(app).add("ManagedBy", "CDK")

# Synthesize the CloudFormation template
app.synth()