#!/usr/bin/env python3
"""
AWS CDK Python Application for Cost Anomaly Detection

This CDK application implements a comprehensive cost anomaly detection solution using
AWS Cost Anomaly Detection, SNS notifications, EventBridge events, and Lambda processing.

Architecture:
- Cost Anomaly Detection monitors with ML-based anomaly detection
- SNS topic for email notifications
- EventBridge rule for event processing
- Lambda function for automated response and analysis
- CloudWatch dashboard for visualization
- IAM roles with least privilege permissions

Author: AWS CDK Team
Version: 2.0
"""

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    aws_ce as ce,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_events as events,
    aws_events_targets as targets,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    CfnOutput,
    RemovalPolicy,
    Tags
)
from constructs import Construct
from typing import Dict, List, Optional


class CostAnomalyDetectionStack(Stack):
    """
    CDK Stack for AWS Cost Anomaly Detection solution.
    
    This stack creates a complete cost anomaly detection infrastructure including:
    - Multiple anomaly monitors (service-based, account-based, tag-based)
    - Alert subscriptions with different frequencies and thresholds
    - SNS topic for notifications
    - EventBridge integration for event processing
    - Lambda function for automated response
    - CloudWatch dashboard for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get deployment parameters
        notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        environment_name = self.node.try_get_context("environment") or "production"
        
        # Create SNS topic for cost anomaly notifications
        self.sns_topic = self._create_sns_topic(notification_email)
        
        # Create Cost Anomaly Detection monitors
        self.monitors = self._create_anomaly_monitors()
        
        # Create alert subscriptions
        self.subscriptions = self._create_anomaly_subscriptions()
        
        # Create Lambda function for automated processing
        self.lambda_function = self._create_anomaly_processor()
        
        # Create EventBridge rule for cost anomaly events
        self.eventbridge_rule = self._create_eventbridge_rule()
        
        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()
        
        # Add tags to all resources
        self._add_common_tags(environment_name)
        
        # Create stack outputs
        self._create_outputs()

    def _create_sns_topic(self, email: str) -> sns.Topic:
        """
        Create SNS topic for cost anomaly notifications.
        
        Args:
            email: Email address for notifications
            
        Returns:
            SNS Topic construct
        """
        topic = sns.Topic(
            self, "CostAnomalyTopic",
            topic_name="cost-anomaly-alerts",
            display_name="AWS Cost Anomaly Detection Alerts",
            description="Notifications for AWS cost anomalies and unusual spending patterns"
        )
        
        # Add email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(email)
        )
        
        return topic

    def _create_anomaly_monitors(self) -> Dict[str, ce.CfnAnomalyMonitor]:
        """
        Create Cost Anomaly Detection monitors for different dimensions.
        
        Returns:
            Dictionary of monitor constructs
        """
        monitors = {}
        
        # AWS Services Monitor - tracks anomalies across individual AWS services
        monitors["services"] = ce.CfnAnomalyMonitor(
            self, "ServicesMonitor",
            monitor_name="AWS-Services-Monitor",
            monitor_type="DIMENSIONAL",
            monitor_dimension="SERVICE"
        )
        
        # Account-Based Monitor - tracks anomalies within specific linked accounts
        monitors["accounts"] = ce.CfnAnomalyMonitor(
            self, "AccountsMonitor",
            monitor_name="Account-Based-Monitor",
            monitor_type="DIMENSIONAL",
            monitor_dimension="LINKED_ACCOUNT"
        )
        
        # Tag-Based Monitor - tracks anomalies for resources with specific tags
        monitors["tags"] = ce.CfnAnomalyMonitor(
            self, "TagMonitor",
            monitor_name="Environment-Tag-Monitor",
            monitor_type="CUSTOM",
            monitor_specification={
                "Tags": {
                    "Key": "Environment",
                    "Values": ["Production", "Staging"],
                    "MatchOptions": ["EQUALS"]
                }
            }
        )
        
        return monitors

    def _create_anomaly_subscriptions(self) -> Dict[str, ce.CfnAnomalySubscription]:
        """
        Create Cost Anomaly Detection subscriptions with different configurations.
        
        Returns:
            Dictionary of subscription constructs
        """
        subscriptions = {}
        
        # Daily Summary Subscription - consolidated daily reports
        subscriptions["daily"] = ce.CfnAnomalySubscription(
            self, "DailySummarySubscription",
            subscription_name="Daily-Cost-Summary",
            frequency="DAILY",
            monitor_arn_list=[
                self.monitors["services"].attr_monitor_arn,
                self.monitors["accounts"].attr_monitor_arn
            ],
            subscribers=[
                {
                    "Address": self.node.try_get_context("notification_email") or "admin@example.com",
                    "Type": "EMAIL"
                }
            ],
            threshold_expression={
                "And": [
                    {
                        "Dimensions": {
                            "Key": "ANOMALY_TOTAL_IMPACT_ABSOLUTE",
                            "Values": ["100"]
                        }
                    }
                ]
            }
        )
        
        # Individual Alerts Subscription - immediate notifications via SNS
        subscriptions["individual"] = ce.CfnAnomalySubscription(
            self, "IndividualAlertsSubscription",
            subscription_name="Individual-Cost-Alerts",
            frequency="IMMEDIATE",
            monitor_arn_list=[
                self.monitors["tags"].attr_monitor_arn
            ],
            subscribers=[
                {
                    "Address": self.sns_topic.topic_arn,
                    "Type": "SNS"
                }
            ],
            threshold_expression={
                "And": [
                    {
                        "Dimensions": {
                            "Key": "ANOMALY_TOTAL_IMPACT_ABSOLUTE",
                            "Values": ["50"]
                        }
                    }
                ]
            }
        )
        
        return subscriptions

    def _create_anomaly_processor(self) -> lambda_.Function:
        """
        Create Lambda function for processing cost anomaly events.
        
        Returns:
            Lambda Function construct
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "AnomalyProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "CloudWatchLogsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/lambda/cost-anomaly-processor*"
                            ]
                        )
                    ]
                )
            }
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self, "AnomalyProcessor",
            function_name="cost-anomaly-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.seconds(60),
            description="Process cost anomaly detection events and take automated actions",
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn
            }
        )
        
        return function

    def _create_eventbridge_rule(self) -> events.Rule:
        """
        Create EventBridge rule to capture cost anomaly events.
        
        Returns:
            EventBridge Rule construct
        """
        rule = events.Rule(
            self, "CostAnomalyRule",
            rule_name="cost-anomaly-detection-rule",
            description="Capture AWS Cost Anomaly Detection events",
            event_pattern=events.EventPattern(
                source=["aws.ce"],
                detail_type=["Cost Anomaly Detection"]
            )
        )
        
        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.lambda_function))
        
        return rule

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for cost anomaly monitoring.
        
        Returns:
            CloudWatch Dashboard construct
        """
        dashboard = cloudwatch.Dashboard(
            self, "CostAnomalyDashboard",
            dashboard_name="Cost-Anomaly-Detection-Dashboard"
        )
        
        # Add log insights widgets for anomaly analysis
        dashboard.add_widgets(
            cloudwatch.LogQueryWidget(
                title="High Impact Cost Anomalies",
                log_groups=[
                    logs.LogGroup.from_log_group_name(
                        self, "ProcessorLogGroup",
                        "/aws/lambda/cost-anomaly-processor"
                    )
                ],
                query_lines=[
                    "SOURCE \"/aws/lambda/cost-anomaly-processor\"",
                    "| fields @timestamp, severity, total_impact, anomaly_score",
                    "| filter severity = \"HIGH\"",
                    "| sort @timestamp desc",
                    "| limit 20"
                ],
                width=12,
                height=6
            ),
            cloudwatch.LogQueryWidget(
                title="Anomaly Count by Severity",
                log_groups=[
                    logs.LogGroup.from_log_group_name(
                        self, "ProcessorLogGroupCount",
                        "/aws/lambda/cost-anomaly-processor"
                    )
                ],
                query_lines=[
                    "SOURCE \"/aws/lambda/cost-anomaly-processor\"",
                    "| fields @timestamp, severity, total_impact",
                    "| stats count() by severity",
                    "| sort severity desc"
                ],
                width=12,
                height=6
            )
        )
        
        return dashboard

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for processing cost anomaly events.
        
        Returns:
            Lambda function code as string
        """
        return '''
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """Process cost anomaly detection events and take automated actions"""
    
    try:
        # Log the incoming event
        logger.info(f"Received cost anomaly event: {json.dumps(event)}")
        
        # Extract anomaly details
        detail = event.get('detail', {})
        anomaly_score = detail.get('anomalyScore', 0)
        impact = detail.get('impact', {})
        total_impact = impact.get('totalImpact', 0)
        
        # Determine severity level
        if total_impact > 500:
            severity = "HIGH"
        elif total_impact > 100:
            severity = "MEDIUM"
        else:
            severity = "LOW"
        
        # Log anomaly details
        logger.info(f"Anomaly detected - Score: {anomaly_score}, Impact: ${total_impact}, Severity: {severity}")
        
        # Send to CloudWatch Logs for further analysis
        cloudwatch = boto3.client('logs')
        log_group = '/aws/lambda/cost-anomaly-processor'
        log_stream = f"anomaly-{datetime.now().strftime('%Y-%m-%d')}"
        
        try:
            cloudwatch.create_log_group(logGroupName=log_group)
        except cloudwatch.exceptions.ResourceAlreadyExistsException:
            pass
        
        try:
            cloudwatch.create_log_stream(
                logGroupName=log_group,
                logStreamName=log_stream
            )
        except cloudwatch.exceptions.ResourceAlreadyExistsException:
            pass
        
        # Log structured anomaly data
        structured_log = {
            "timestamp": datetime.now().isoformat(),
            "anomaly_score": anomaly_score,
            "total_impact": total_impact,
            "severity": severity,
            "event_detail": detail
        }
        
        cloudwatch.put_log_events(
            logGroupName=log_group,
            logStreamName=log_stream,
            logEvents=[
                {
                    'timestamp': int(datetime.now().timestamp() * 1000),
                    'message': json.dumps(structured_log)
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost anomaly processed successfully',
                'severity': severity,
                'impact': total_impact
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing cost anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing cost anomaly',
                'error': str(e)
            })
        }
'''

    def _add_common_tags(self, environment: str) -> None:
        """
        Add common tags to all resources in the stack.
        
        Args:
            environment: Environment name (e.g., production, staging)
        """
        Tags.of(self).add("Project", "CostAnomalyDetection")
        Tags.of(self).add("Environment", environment)
        Tags.of(self).add("ManagedBy", "CDK")
        Tags.of(self).add("Purpose", "CostGovernance")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for cost anomaly notifications",
            export_name="CostAnomalySNSTopicArn"
        )
        
        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function for processing cost anomaly events",
            export_name="CostAnomalyLambdaArn"
        )
        
        CfnOutput(
            self, "EventBridgeRuleArn",
            value=self.eventbridge_rule.rule_arn,
            description="ARN of the EventBridge rule for cost anomaly events",
            export_name="CostAnomalyEventBridgeRuleArn"
        )
        
        CfnOutput(
            self, "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard for cost anomaly monitoring",
            export_name="CostAnomalyDashboardURL"
        )
        
        # Output monitor ARNs
        for monitor_name, monitor in self.monitors.items():
            CfnOutput(
                self, f"{monitor_name.title()}MonitorArn",
                value=monitor.attr_monitor_arn,
                description=f"ARN of the {monitor_name} cost anomaly monitor",
                export_name=f"CostAnomaly{monitor_name.title()}MonitorArn"
            )


class CostAnomalyDetectionApp(cdk.App):
    """
    CDK Application for Cost Anomaly Detection.
    
    This application creates a comprehensive cost anomaly detection solution
    with multiple monitors, alert subscriptions, and automated response capabilities.
    """

    def __init__(self) -> None:
        super().__init__()
        
        # Create the main stack
        CostAnomalyDetectionStack(
            self, "CostAnomalyDetectionStack",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region") or "us-east-1"
            ),
            description="AWS Cost Anomaly Detection with ML-based monitoring and automated response"
        )


# Application entry point
if __name__ == "__main__":
    app = CostAnomalyDetectionApp()
    app.synth()