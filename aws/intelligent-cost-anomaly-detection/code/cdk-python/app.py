#!/usr/bin/env python3
"""
AWS CDK Python application for implementing automated cost anomaly detection
with CloudWatch and Lambda.

This application creates a complete cost monitoring solution that includes:
- Cost Anomaly Detection monitors and detectors
- Lambda function for enhanced anomaly processing
- SNS topic for notifications
- EventBridge rules for real-time event processing
- CloudWatch dashboard for operational visibility
- IAM roles and policies with least privilege access
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_lambda as _lambda,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_cloudwatch as cloudwatch,
    aws_ce as ce,
    aws_logs as logs,
)
from constructs import Construct
import json
from typing import Optional


class CostAnomalyDetectionStack(Stack):
    """
    CDK Stack for automated cost anomaly detection with CloudWatch and Lambda.
    
    This stack implements a comprehensive cost monitoring solution that leverages
    AWS Cost Anomaly Detection with intelligent Lambda processing and real-time
    notifications through SNS and EventBridge integration.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        email_address: Optional[str] = None,
        monitor_service: str = "Amazon Elastic Compute Cloud - Compute",
        anomaly_threshold: float = 10.0,
        **kwargs
    ) -> None:
        """
        Initialize the Cost Anomaly Detection Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            email_address: Email address for SNS notifications
            monitor_service: AWS service to monitor for cost anomalies
            anomaly_threshold: Dollar threshold for anomaly detection
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.email_address = email_address
        self.monitor_service = monitor_service
        self.anomaly_threshold = anomaly_threshold

        # Create core infrastructure components
        self.sns_topic = self._create_sns_topic()
        self.lambda_role = self._create_lambda_role()
        self.lambda_function = self._create_lambda_function()
        self.eventbridge_rule = self._create_eventbridge_rule()
        self.cost_monitor = self._create_cost_anomaly_monitor()
        self.cost_detector = self._create_cost_anomaly_detector()
        self.dashboard = self._create_cloudwatch_dashboard()

        # Create outputs for important resources
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for cost anomaly notifications.
        
        Returns:
            SNS Topic configured for cost anomaly alerts
        """
        topic = sns.Topic(
            self,
            "CostAnomalyAlertsTopic",
            topic_name=f"cost-anomaly-alerts-{self.stack_name.lower()}",
            display_name="Cost Anomaly Detection Alerts",
            description="SNS topic for AWS Cost Anomaly Detection notifications"
        )

        # Add email subscription if provided
        if self.email_address:
            topic.add_subscription(
                subs.EmailSubscription(self.email_address)
            )

        return topic

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with least privilege permissions.
        
        Returns:
            IAM Role configured for cost anomaly processing
        """
        # Create the role
        role = iam.Role(
            self,
            "CostAnomalyLambdaRole",
            role_name=f"CostAnomalyLambdaRole-{self.stack_name}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Cost Anomaly Detection Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add custom policy for cost operations
        cost_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ce:GetCostAndUsage",
                "ce:GetUsageReport", 
                "ce:GetDimensionValues",
                "ce:GetReservationCoverage",
                "ce:GetReservationPurchaseRecommendation",
                "ce:GetReservationUtilization"
            ],
            resources=["*"],
            sid="CostExplorerAccess"
        )

        # Add CloudWatch metrics policy
        cloudwatch_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "cloudwatch:PutMetricData",
                "cloudwatch:GetMetricStatistics"
            ],
            resources=["*"],
            sid="CloudWatchMetricsAccess"
        )

        # Add SNS publish policy
        sns_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["sns:Publish"],
            resources=[self.sns_topic.topic_arn],
            sid="SNSPublishAccess"
        )

        # Attach policies to role
        role.add_to_policy(cost_policy)
        role.add_to_policy(cloudwatch_policy)
        role.add_to_policy(sns_policy)

        return role

    def _create_lambda_function(self) -> _lambda.Function:
        """
        Create Lambda function for enhanced cost anomaly processing.
        
        Returns:
            Lambda Function configured for cost anomaly analysis
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
from datetime import datetime, timedelta
from decimal import Decimal
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process Cost Anomaly Detection events with enhanced analysis.
    
    Args:
        event: EventBridge event containing anomaly details
        context: Lambda context object
        
    Returns:
        Dict with processing status and metrics
    """
    logger.info(f"Received event: {json.dumps(event, indent=2)}")
    
    # Initialize AWS clients
    ce_client = boto3.client('ce')
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    try:
        # Extract anomaly details from EventBridge event
        detail = event['detail']
        anomaly_id = detail['anomalyId']
        total_impact = detail['impact']['totalImpact']
        account_name = detail['accountName']
        dimension_value = detail.get('dimensionValue', 'N/A')
        
        # Calculate percentage impact
        total_actual = detail['impact']['totalActualSpend']
        total_expected = detail['impact']['totalExpectedSpend']
        impact_percentage = detail['impact']['totalImpactPercentage']
        
        logger.info(f"Processing anomaly {anomaly_id} with impact ${total_impact}")
        
        # Get additional cost breakdown
        cost_breakdown = get_cost_breakdown(ce_client, detail)
        
        # Publish custom CloudWatch metrics
        publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage)
        
        # Send enhanced notification
        send_enhanced_notification(sns, detail, cost_breakdown)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed anomaly {anomaly_id}',
                'total_impact': float(total_impact),
                'impact_percentage': float(impact_percentage)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing anomaly: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_cost_breakdown(ce_client, detail):
    """Get detailed cost breakdown for the anomaly period."""
    try:
        end_date = detail['anomalyEndDate'][:10]  # YYYY-MM-DD
        start_date = detail['anomalyStartDate'][:10]
        
        # Get cost and usage data
        response = ce_client.get_cost_and_usage(
            TimePeriod={
                'Start': start_date,
                'End': end_date
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'}
            ]
        )
        
        return response.get('ResultsByTime', [])
        
    except Exception as e:
        logger.error(f"Error getting cost breakdown: {str(e)}")
        return []

def publish_metrics(cloudwatch, anomaly_id, total_impact, impact_percentage):
    """Publish custom CloudWatch metrics for anomaly tracking."""
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/CostAnomaly',
            MetricData=[
                {
                    'MetricName': 'AnomalyImpact',
                    'Value': float(total_impact),
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                },
                {
                    'MetricName': 'AnomalyPercentage',
                    'Value': float(impact_percentage),
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'AnomalyId',
                            'Value': anomaly_id
                        }
                    ]
                }
            ]
        )
        logger.info("Custom metrics published to CloudWatch")
        
    except Exception as e:
        logger.error(f"Error publishing metrics: {str(e)}")

def send_enhanced_notification(sns, detail, cost_breakdown):
    """Send enhanced notification with detailed analysis."""
    try:
        # Format the notification message
        message = format_notification_message(detail, cost_breakdown)
        
        # Publish to SNS
        response = sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Subject=f"🚨 AWS Cost Anomaly Detected - ${detail['impact']['totalImpact']:.2f}",
            Message=message
        )
        
        logger.info(f"Notification sent: {response['MessageId']}")
        
    except Exception as e:
        logger.error(f"Error sending notification: {str(e)}")

def format_notification_message(detail, cost_breakdown):
    """Format detailed notification message."""
    impact = detail['impact']
    
    message = f"""
AWS Cost Anomaly Detection Alert
================================

Anomaly ID: {detail['anomalyId']}
Account: {detail['accountName']}
Service: {detail.get('dimensionValue', 'Multiple Services')}

Cost Impact:
- Total Impact: ${impact['totalImpact']:.2f}
- Actual Spend: ${impact['totalActualSpend']:.2f}
- Expected Spend: ${impact['totalExpectedSpend']:.2f}
- Percentage Increase: {impact['totalImpactPercentage']:.1f}%

Period:
- Start: {detail['anomalyStartDate']}
- End: {detail['anomalyEndDate']}

Anomaly Score:
- Current: {detail['anomalyScore']['currentScore']:.3f}
- Maximum: {detail['anomalyScore']['maxScore']:.3f}

Root Causes:
"""
    
    # Add root cause analysis
    for cause in detail.get('rootCauses', []):
        message += f"""
- Account: {cause.get('linkedAccountName', 'N/A')}
  Service: {cause.get('service', 'N/A')}
  Region: {cause.get('region', 'N/A')}
  Usage Type: {cause.get('usageType', 'N/A')}
  Contribution: ${cause.get('impact', {}).get('contribution', 0):.2f}
"""
    
    message += f"""

Next Steps:
1. Review the affected services and usage patterns
2. Check for any unauthorized usage or misconfigurations
3. Consider implementing cost controls if needed
4. Monitor for additional anomalies

AWS Console Links:
- Cost Explorer: https://console.aws.amazon.com/billing/home#/costexplorer
- Cost Anomaly Detection: https://console.aws.amazon.com/billing/home#/anomaly-detection

Generated by: AWS Cost Anomaly Detection Lambda
Timestamp: {datetime.now().isoformat()}
    """
    
    return message
'''

        # Create Lambda function
        function = _lambda.Function(
            self,
            "CostAnomalyProcessor",
            function_name=f"cost-anomaly-processor-{self.stack_name.lower()}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=_lambda.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            description="Enhanced Cost Anomaly Detection processor with intelligent analysis",
            environment={
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn
            },
            log_retention=logs.RetentionDays.ONE_MONTH
        )

        return function

    def _create_eventbridge_rule(self) -> events.Rule:
        """
        Create EventBridge rule to trigger Lambda on cost anomalies.
        
        Returns:
            EventBridge Rule configured for cost anomaly events
        """
        # Create EventBridge rule
        rule = events.Rule(
            self,
            "CostAnomalyRule",
            rule_name=f"cost-anomaly-rule-{self.stack_name.lower()}",
            description="Rule to capture Cost Anomaly Detection events",
            event_pattern=events.EventPattern(
                source=["aws.ce"],
                detail_type=["Anomaly Detected"]
            )
        )

        # Add Lambda function as target
        rule.add_target(
            targets.LambdaFunction(
                handler=self.lambda_function,
                retry_attempts=3
            )
        )

        return rule

    def _create_cost_anomaly_monitor(self) -> ce.CfnAnomalyMonitor:
        """
        Create Cost Anomaly Detection monitor.
        
        Returns:
            CloudFormation-based Cost Anomaly Monitor
        """
        monitor = ce.CfnAnomalyMonitor(
            self,
            "CostAnomalyMonitor",
            monitor_name=f"cost-anomaly-monitor-{self.stack_name.lower()}",
            monitor_type="DIMENSIONAL",
            monitor_specification=json.dumps({
                "Dimension": "SERVICE",
                "MatchOptions": ["EQUALS"],
                "Values": [self.monitor_service]
            }),
            monitor_dimension="SERVICE"
        )

        return monitor

    def _create_cost_anomaly_detector(self) -> ce.CfnAnomalyDetector:
        """
        Create Cost Anomaly Detection detector.
        
        Returns:
            CloudFormation-based Cost Anomaly Detector
        """
        detector = ce.CfnAnomalyDetector(
            self,
            "CostAnomalyDetector",
            detector_name=f"cost-anomaly-detector-{self.stack_name.lower()}",
            monitor_arn_list=[self.cost_monitor.attr_monitor_arn],
            subscribers=[
                ce.CfnAnomalyDetector.SubscriberProperty(
                    address=self.sns_topic.topic_arn,
                    type="SNS",
                    status="CONFIRMED"
                )
            ],
            threshold=self.anomaly_threshold,
            frequency="IMMEDIATE"
        )

        # Add dependency on monitor
        detector.add_dependency(self.cost_monitor)

        return detector

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for cost monitoring.
        
        Returns:
            CloudWatch Dashboard with cost anomaly metrics
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "CostAnomalyDashboard",
            dashboard_name=f"CostAnomalyDetection-{self.stack_name}"
        )

        # Cost anomaly metrics widget
        anomaly_widget = cloudwatch.GraphWidget(
            title="Cost Anomaly Metrics",
            width=12,
            height=6,
            left=[
                cloudwatch.Metric(
                    namespace="AWS/CostAnomaly",
                    metric_name="AnomalyImpact",
                    statistic="Sum",
                    period=Duration.minutes(5)
                ),
                cloudwatch.Metric(
                    namespace="AWS/CostAnomaly", 
                    metric_name="AnomalyPercentage",
                    statistic="Sum",
                    period=Duration.minutes(5)
                )
            ]
        )

        # Lambda function metrics widget
        lambda_widget = cloudwatch.GraphWidget(
            title="Lambda Function Metrics",
            width=12,
            height=6,
            left=[
                self.lambda_function.metric_invocations(
                    period=Duration.minutes(5)
                ),
                self.lambda_function.metric_duration(
                    period=Duration.minutes(5)
                ),
                self.lambda_function.metric_errors(
                    period=Duration.minutes(5)
                )
            ]
        )

        # Add widgets to dashboard
        dashboard.add_widgets(anomaly_widget)
        dashboard.add_widgets(lambda_widget)

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for cost anomaly notifications"
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function processing cost anomalies"
        )

        cdk.CfnOutput(
            self,
            "CostMonitorArn",
            value=self.cost_monitor.attr_monitor_arn,
            description="ARN of the Cost Anomaly Detection monitor"
        )

        cdk.CfnOutput(
            self,
            "CostDetectorArn", 
            value=self.cost_detector.attr_detector_arn,
            description="ARN of the Cost Anomaly Detection detector"
        )

        cdk.CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard for cost monitoring"
        )


def main():
    """
    Main application entry point.
    
    Creates and deploys the Cost Anomaly Detection CDK application
    with configurable parameters for different environments.
    """
    app = cdk.App()

    # Get configuration from context or environment
    email_address = app.node.try_get_context("email_address")
    monitor_service = app.node.try_get_context("monitor_service") or "Amazon Elastic Compute Cloud - Compute"
    anomaly_threshold = float(app.node.try_get_context("anomaly_threshold") or 10.0)
    stack_name = app.node.try_get_context("stack_name") or "CostAnomalyDetectionStack"

    # Create the stack
    CostAnomalyDetectionStack(
        app,
        stack_name,
        email_address=email_address,
        monitor_service=monitor_service,
        anomaly_threshold=anomaly_threshold,
        description="Automated cost anomaly detection with CloudWatch and Lambda",
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        )
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()