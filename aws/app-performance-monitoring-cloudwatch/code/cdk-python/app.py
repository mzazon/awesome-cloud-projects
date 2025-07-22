#!/usr/bin/env python3
"""
AWS CDK Python application for Automated Application Performance Monitoring
with CloudWatch Application Signals and EventBridge.

This application creates a comprehensive monitoring system that:
- Enables CloudWatch Application Signals for application-level metrics
- Creates CloudWatch alarms for performance monitoring
- Uses EventBridge to route alarm state changes
- Implements Lambda functions for automated response
- Provides SNS notifications for alerts
- Creates a CloudWatch dashboard for visualization

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    Stack,
    StackProps,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_events as events,
    aws_events_targets as targets,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct


class ApplicationPerformanceMonitoringStack(Stack):
    """
    CDK Stack for automated application performance monitoring system.
    
    This stack creates:
    - SNS topic for notifications
    - Lambda function for event processing
    - CloudWatch alarms for Application Signals metrics
    - EventBridge rules for alarm processing
    - CloudWatch dashboard for visualization
    - IAM roles and policies with least privilege
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        application_name: str = "MyApplication",
        notification_email: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Application Performance Monitoring Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this stack
            application_name: Name of the application to monitor
            notification_email: Email address for alert notifications
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.application_name = application_name
        self.notification_email = notification_email

        # Create SNS topic for notifications
        self.notification_topic = self._create_sns_topic()

        # Create Lambda function for event processing
        self.event_processor = self._create_lambda_function()

        # Create CloudWatch alarms for Application Signals
        self.alarms = self._create_cloudwatch_alarms()

        # Create EventBridge rule for alarm processing
        self.event_rule = self._create_eventbridge_rule()

        # Create CloudWatch dashboard
        self.dashboard = self._create_cloudwatch_dashboard()

        # Create CloudWatch log group for Application Signals
        self.app_signals_log_group = self._create_app_signals_log_group()

        # Output important resource information
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for performance alert notifications.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "PerformanceAlertsTopic",
            display_name="Application Performance Alerts",
            topic_name=f"performance-alerts-{self.application_name.lower()}",
        )

        # Add email subscription if provided
        if self.notification_email:
            topic.add_subscription(
                subscriptions.EmailSubscription(self.notification_email)
            )

        cdk.Tags.of(topic).add("Purpose", "ApplicationMonitoring")
        cdk.Tags.of(topic).add("Application", self.application_name)

        return topic

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for processing CloudWatch alarm events.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "EventProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "PerformanceMonitoringPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sns:Publish",
                                "cloudwatch:DescribeAlarms",
                                "cloudwatch:GetMetricStatistics",
                                "autoscaling:DescribeAutoScalingGroups",
                                "autoscaling:UpdateAutoScalingGroup",
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["*"],
                        )
                    ]
                )
            },
        )

        # Lambda function code
        function_code = '''
import json
import boto3
import logging
from datetime import datetime
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Process CloudWatch alarm state changes and trigger appropriate actions.
    
    Args:
        event: EventBridge event containing alarm state change
        context: Lambda context object
        
    Returns:
        dict: Response indicating success or failure
    """
    try:
        # Parse EventBridge event
        detail = event.get('detail', {})
        alarm_name = detail.get('alarmName', '')
        new_state = detail.get('newState', {})
        state_value = new_state.get('value', '')
        state_reason = new_state.get('reason', '')
        timestamp = detail.get('timestamp', datetime.now().isoformat())
        
        logger.info(f"Processing alarm: {alarm_name}, State: {state_value}")
        
        # Initialize AWS clients
        sns_client = boto3.client('sns')
        cloudwatch_client = boto3.client('cloudwatch')
        
        # Get SNS topic ARN from environment
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        if not sns_topic_arn:
            logger.error("SNS_TOPIC_ARN environment variable not set")
            raise ValueError("Missing SNS topic ARN configuration")
        
        # Define response actions based on alarm state
        if state_value == 'ALARM':
            # Send immediate notification for alarm state
            message = f"""🚨 PERFORMANCE ALERT 🚨

Alarm: {alarm_name}
State: {state_value}
Reason: {state_reason}
Time: {timestamp}
Application: {os.environ.get('APPLICATION_NAME', 'Unknown')}

Automatic monitoring system has detected a performance issue.
Please check the CloudWatch dashboard for detailed metrics.

This is an automated alert from AWS CloudWatch Application Signals.
"""
            
            subject = f"Performance Alert: {alarm_name}"
            
        elif state_value == 'OK':
            # Send resolution notification
            message = f"""✅ ALERT RESOLVED ✅

Alarm: {alarm_name}
State: {state_value}
Time: {timestamp}
Application: {os.environ.get('APPLICATION_NAME', 'Unknown')}

Performance metrics have returned to normal levels.
The application is now operating within acceptable parameters.

This is an automated resolution notice from AWS CloudWatch Application Signals.
"""
            
            subject = f"Alert Resolved: {alarm_name}"
            
        else:
            # Handle INSUFFICIENT_DATA or other states
            logger.info(f"Alarm {alarm_name} in state {state_value} - no action required")
            return {
                'statusCode': 200,
                'body': json.dumps(f'No action required for alarm state: {state_value}')
            }
        
        # Publish notification to SNS topic
        response = sns_client.publish(
            TopicArn=sns_topic_arn,
            Message=message,
            Subject=subject
        )
        
        logger.info(f"Successfully published notification. MessageId: {response.get('MessageId')}")
        
        # Log performance metrics for monitoring the monitoring system
        cloudwatch_client.put_metric_data(
            Namespace='ApplicationMonitoring/System',
            MetricData=[
                {
                    'MetricName': 'AlarmsProcessed',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'AlarmState',
                            'Value': state_value
                        },
                        {
                            'Name': 'Application',
                            'Value': os.environ.get('APPLICATION_NAME', 'Unknown')
                        }
                    ]
                }
            ]
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed alarm: {alarm_name}',
                'state': state_value,
                'messageId': response.get('MessageId')
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        logger.error(f"Event details: {json.dumps(event, default=str)}")
        
        # Send error notification if possible
        try:
            sns_client = boto3.client('sns')
            sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if sns_topic_arn:
                error_message = f"""❌ MONITORING SYSTEM ERROR ❌

Error processing performance alert: {str(e)}
Time: {datetime.now().isoformat()}
Application: {os.environ.get('APPLICATION_NAME', 'Unknown')}

Please check CloudWatch Logs for detailed error information.
"""
                sns_client.publish(
                    TopicArn=sns_topic_arn,
                    Message=error_message,
                    Subject="Monitoring System Error"
                )
        except Exception as notification_error:
            logger.error(f"Failed to send error notification: {str(notification_error)}")
        
        raise e
'''

        # Create Lambda function
        function = lambda_.Function(
            self,
            "EventProcessor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Process CloudWatch alarm state changes for application performance monitoring",
            environment={
                "SNS_TOPIC_ARN": self.notification_topic.topic_arn,
                "APPLICATION_NAME": self.application_name,
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
        )

        # Grant permission to publish to SNS topic
        self.notification_topic.grant_publish(function)

        cdk.Tags.of(function).add("Purpose", "ApplicationMonitoring")
        cdk.Tags.of(function).add("Application", self.application_name)

        return function

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """
        Create CloudWatch alarms for Application Signals metrics.
        
        Returns:
            List[cloudwatch.Alarm]: List of created CloudWatch alarms
        """
        alarms = []

        # High Latency Alarm
        latency_alarm = cloudwatch.Alarm(
            self,
            "HighLatencyAlarm",
            alarm_name=f"AppSignals-HighLatency-{self.application_name}",
            alarm_description=f"Monitor application latency from Application Signals for {self.application_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationSignals",
                metric_name="Latency",
                dimensions_map={
                    "Service": self.application_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=2000,  # 2 seconds in milliseconds
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        latency_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )
        latency_alarm.add_ok_action(
            cw_actions.SnsAction(self.notification_topic)
        )

        alarms.append(latency_alarm)

        # High Error Rate Alarm
        error_alarm = cloudwatch.Alarm(
            self,
            "HighErrorRateAlarm",
            alarm_name=f"AppSignals-HighErrorRate-{self.application_name}",
            alarm_description=f"Monitor application error rate from Application Signals for {self.application_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationSignals",
                metric_name="ErrorRate",
                dimensions_map={
                    "Service": self.application_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5,  # 5% error rate
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        error_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )
        error_alarm.add_ok_action(
            cw_actions.SnsAction(self.notification_topic)
        )

        alarms.append(error_alarm)

        # Low Throughput Alarm
        throughput_alarm = cloudwatch.Alarm(
            self,
            "LowThroughputAlarm",
            alarm_name=f"AppSignals-LowThroughput-{self.application_name}",
            alarm_description=f"Monitor application throughput from Application Signals for {self.application_name}",
            metric=cloudwatch.Metric(
                namespace="AWS/ApplicationSignals",
                metric_name="CallCount",
                dimensions_map={
                    "Service": self.application_name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=10,  # Minimum 10 calls per 5-minute period
            evaluation_periods=3,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to alarm
        throughput_alarm.add_alarm_action(
            cw_actions.SnsAction(self.notification_topic)
        )
        throughput_alarm.add_ok_action(
            cw_actions.SnsAction(self.notification_topic)
        )

        alarms.append(throughput_alarm)

        # Add tags to all alarms
        for alarm in alarms:
            cdk.Tags.of(alarm).add("Purpose", "ApplicationMonitoring")
            cdk.Tags.of(alarm).add("Application", self.application_name)

        return alarms

    def _create_eventbridge_rule(self) -> events.Rule:
        """
        Create EventBridge rule to route CloudWatch alarm state changes to Lambda.
        
        Returns:
            events.Rule: The created EventBridge rule
        """
        rule = events.Rule(
            self,
            "AlarmStateChangeRule",
            rule_name=f"performance-anomaly-rule-{self.application_name.lower()}",
            description="Route CloudWatch alarm state changes to Lambda processor",
            event_pattern=events.EventPattern(
                source=["aws.cloudwatch"],
                detail_type=["CloudWatch Alarm State Change"],
                detail={
                    "state": {
                        "value": ["ALARM", "OK"]
                    }
                }
            ),
            enabled=True,
        )

        # Add Lambda function as target
        rule.add_target(targets.LambdaFunction(self.event_processor))

        cdk.Tags.of(rule).add("Purpose", "ApplicationMonitoring")
        cdk.Tags.of(rule).add("Application", self.application_name)

        return rule

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for performance monitoring visualization.
        
        Returns:
            cloudwatch.Dashboard: The created CloudWatch dashboard
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "PerformanceDashboard",
            dashboard_name=f"ApplicationPerformanceMonitoring-{self.application_name}",
        )

        # Application performance metrics widget
        app_metrics_widget = cloudwatch.GraphWidget(
            title="Application Performance Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/ApplicationSignals",
                    metric_name="Latency",
                    dimensions_map={"Service": self.application_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                    label="Average Latency (ms)"
                ),
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/ApplicationSignals",
                    metric_name="ErrorRate",
                    dimensions_map={"Service": self.application_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                    label="Error Rate (%)"
                ),
                cloudwatch.Metric(
                    namespace="AWS/ApplicationSignals",
                    metric_name="CallCount",
                    dimensions_map={"Service": self.application_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="Request Count"
                ),
            ],
            width=12,
            height=6,
        )

        # Event processing metrics widget
        event_metrics_widget = cloudwatch.GraphWidget(
            title="Event Processing Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/Events",
                    metric_name="InvocationsCount",
                    dimensions_map={"RuleName": self.event_rule.rule_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="EventBridge Invocations"
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Invocations",
                    dimensions_map={"FunctionName": self.event_processor.function_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="Lambda Invocations"
                ),
            ],
            right=[
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Errors",
                    dimensions_map={"FunctionName": self.event_processor.function_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="Lambda Errors"
                ),
                cloudwatch.Metric(
                    namespace="AWS/Lambda",
                    metric_name="Duration",
                    dimensions_map={"FunctionName": self.event_processor.function_name},
                    statistic="Average",
                    period=Duration.minutes(5),
                    label="Lambda Duration (ms)"
                ),
            ],
            width=12,
            height=6,
        )

        # System health metrics widget
        system_health_widget = cloudwatch.GraphWidget(
            title="Monitoring System Health",
            left=[
                cloudwatch.Metric(
                    namespace="ApplicationMonitoring/System",
                    metric_name="AlarmsProcessed",
                    dimensions_map={"Application": self.application_name},
                    statistic="Sum",
                    period=Duration.minutes(5),
                    label="Alarms Processed"
                ),
            ],
            width=12,
            height=4,
        )

        # Add widgets to dashboard
        dashboard.add_widgets(app_metrics_widget)
        dashboard.add_widgets(event_metrics_widget)
        dashboard.add_widgets(system_health_widget)

        cdk.Tags.of(dashboard).add("Purpose", "ApplicationMonitoring")
        cdk.Tags.of(dashboard).add("Application", self.application_name)

        return dashboard

    def _create_app_signals_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for Application Signals data collection.
        
        Returns:
            logs.LogGroup: The created CloudWatch log group
        """
        log_group = logs.LogGroup(
            self,
            "ApplicationSignalsLogGroup",
            log_group_name="/aws/application-signals/data",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=cdk.RemovalPolicy.DESTROY,
        )

        cdk.Tags.of(log_group).add("Purpose", "ApplicationMonitoring")
        cdk.Tags.of(log_group).add("Application", self.application_name)

        return log_group

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.notification_topic.topic_arn,
            description="ARN of the SNS topic for performance alerts",
            export_name=f"{self.stack_name}-SNSTopicArn",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.event_processor.function_arn,
            description="ARN of the Lambda function for event processing",
            export_name=f"{self.stack_name}-LambdaFunctionArn",
        )

        cdk.CfnOutput(
            self,
            "EventBridgeRuleArn",
            value=self.event_rule.rule_arn,
            description="ARN of the EventBridge rule for alarm processing",
            export_name=f"{self.stack_name}-EventBridgeRuleArn",
        )

        cdk.CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard for performance monitoring",
            export_name=f"{self.stack_name}-DashboardUrl",
        )

        cdk.CfnOutput(
            self,
            "ApplicationName",
            value=self.application_name,
            description="Name of the monitored application",
            export_name=f"{self.stack_name}-ApplicationName",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    """
    app = cdk.App()

    # Get configuration from context or environment variables
    application_name = app.node.try_get_context("applicationName") or os.environ.get("APPLICATION_NAME", "MyApplication")
    notification_email = app.node.try_get_context("notificationEmail") or os.environ.get("NOTIFICATION_EMAIL")

    # Create the monitoring stack
    ApplicationPerformanceMonitoringStack(
        app,
        "ApplicationPerformanceMonitoringStack",
        application_name=application_name,
        notification_email=notification_email,
        description=f"Automated application performance monitoring system for {application_name}",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION")
        ),
    )

    # Add application-wide tags
    cdk.Tags.of(app).add("Project", "ApplicationPerformanceMonitoring")
    cdk.Tags.of(app).add("CreatedBy", "AWS-CDK")
    cdk.Tags.of(app).add("Environment", app.node.try_get_context("environment") or "development")

    app.synth()


if __name__ == "__main__":
    main()