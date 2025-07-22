#!/usr/bin/env python3
"""
CDK Python application for Basic Log Monitoring with CloudWatch Logs and SNS

This application creates an automated log monitoring system using:
- CloudWatch Logs with metric filters to detect error patterns
- CloudWatch Alarms to trigger notifications
- SNS for real-time alert delivery
- Lambda function for log event processing and analysis

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cw_actions,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
)
from constructs import Construct


class LogMonitoringStack(Stack):
    """
    CDK Stack for Basic Log Monitoring Infrastructure
    
    Creates a complete log monitoring solution with CloudWatch Logs,
    metric filters, alarms, SNS notifications, and Lambda processing.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        notification_email: str,
        log_retention_days: int = 7,
        error_threshold: int = 2,
        evaluation_period_minutes: int = 5,
        **kwargs
    ) -> None:
        """
        Initialize the Log Monitoring Stack
        
        Args:
            scope: CDK App scope
            construct_id: Stack identifier
            notification_email: Email address for notifications
            log_retention_days: CloudWatch Logs retention period
            error_threshold: Number of errors to trigger alarm
            evaluation_period_minutes: Alarm evaluation period
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration parameters
        self.notification_email = notification_email
        self.log_retention_days = log_retention_days
        self.error_threshold = error_threshold
        self.evaluation_period = evaluation_period_minutes

        # Create all infrastructure components
        self._create_log_group()
        self._create_sns_topic()
        self._create_lambda_function()
        self._create_metric_filter()
        self._create_cloudwatch_alarm()
        self._create_outputs()

    def _create_log_group(self) -> None:
        """Create CloudWatch Log Group for application logs"""
        self.log_group = logs.LogGroup(
            self,
            "ApplicationLogGroup",
            log_group_name="/aws/application/monitoring-demo",
            retention=logs.RetentionDays(f"ONE_WEEK" if self.log_retention_days == 7 else "ONE_MONTH"),
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add tags for resource management
        cdk.Tags.of(self.log_group).add("Purpose", "LogMonitoring")
        cdk.Tags.of(self.log_group).add("Environment", "Demo")

    def _create_sns_topic(self) -> None:
        """Create SNS topic for alert notifications"""
        self.sns_topic = sns.Topic(
            self,
            "LogMonitoringTopic",
            topic_name="log-monitoring-alerts",
            display_name="Log Monitoring Alerts",
            description="SNS topic for application log monitoring alerts",
        )

        # Subscribe email to the topic
        self.sns_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )

        # Add tags for resource management
        cdk.Tags.of(self.sns_topic).add("Purpose", "LogMonitoring")
        cdk.Tags.of(self.sns_topic).add("Environment", "Demo")

    def _create_lambda_function(self) -> None:
        """Create Lambda function for log event processing"""
        
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "LogProcessorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for log processor Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
        )

        # Add CloudWatch Logs permissions for advanced processing
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                    "logs:GetLogEvents",
                    "logs:FilterLogEvents",
                ],
                resources=[self.log_group.log_group_arn + ":*"],
            )
        )

        # Lambda function code
        lambda_code = """
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process CloudWatch alarm notifications and enrich alert data
    
    Args:
        event: Lambda event containing SNS records
        context: Lambda context object
        
    Returns:
        Response dictionary with status code and body
    """
    
    try:
        processed_records = 0
        
        # Process each SNS record
        for record in event.get('Records', []):
            if 'Sns' not in record:
                logger.warning("Record missing SNS data")
                continue
                
            sns_message = json.loads(record['Sns']['Message'])
            
            # Extract alarm details
            alarm_name = sns_message.get('AlarmName', 'Unknown')
            alarm_reason = sns_message.get('NewStateReason', 'No reason provided')
            alarm_state = sns_message.get('NewStateValue', 'Unknown')
            timestamp = sns_message.get('StateChangeTime', datetime.now().isoformat())
            region = sns_message.get('Region', 'Unknown')
            
            # Log processing details
            logger.info(f"Processing alarm notification:")
            logger.info(f"  Alarm Name: {alarm_name}")
            logger.info(f"  State: {alarm_state}")
            logger.info(f"  Reason: {alarm_reason}")
            logger.info(f"  Timestamp: {timestamp}")
            logger.info(f"  Region: {region}")
            
            # Additional processing can be implemented here:
            # - Query CloudWatch Logs for error context
            # - Send notifications to external systems (Slack, PagerDuty)
            # - Trigger automated remediation workflows
            # - Store alert data in DynamoDB for analysis
            # - Create support tickets automatically
            
            if alarm_state == 'ALARM':
                logger.warning(f"ALERT: {alarm_name} is in ALARM state - {alarm_reason}")
                # Implement custom alert handling logic here
                
            elif alarm_state == 'OK':
                logger.info(f"RECOVERY: {alarm_name} has recovered to OK state")
                # Implement recovery notification logic here
            
            processed_records += 1
            
        logger.info(f"Successfully processed {processed_records} alarm notifications")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Log processing completed successfully',
                'processed_records': processed_records
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"Error parsing SNS message JSON: {str(e)}")
        return {
            'statusCode': 400,
            'body': json.dumps(f'JSON parsing error: {str(e)}')
        }
        
    except Exception as e:
        logger.error(f"Error processing log event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Processing error: {str(e)}')
        }
"""

        # Create Lambda function
        self.lambda_function = lambda_.Function(
            self,
            "LogProcessorFunction",
            function_name="log-processor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            description="Process CloudWatch alarm notifications for log monitoring",
            environment={
                "LOG_GROUP_NAME": self.log_group.log_group_name,
                "AWS_REGION": self.region,
            },
        )

        # Subscribe Lambda function to SNS topic
        self.sns_topic.add_subscription(
            sns_subscriptions.LambdaSubscription(self.lambda_function)
        )

        # Add tags for resource management
        cdk.Tags.of(self.lambda_function).add("Purpose", "LogMonitoring")
        cdk.Tags.of(self.lambda_function).add("Environment", "Demo")

    def _create_metric_filter(self) -> None:
        """Create CloudWatch Logs metric filter for error detection"""
        
        # Define error detection pattern for structured and unstructured logs
        filter_pattern = (
            '{ ($.level = "ERROR") || ($.message = "*ERROR*") || '
            '($.message = "*FAILED*") || ($.message = "*EXCEPTION*") || '
            '($.message = "*TIMEOUT*") }'
        )

        self.metric_filter = logs.MetricFilter(
            self,
            "ErrorCountFilter",
            log_group=self.log_group,
            filter_pattern=logs.FilterPattern.literal(filter_pattern),
            metric_name="ApplicationErrors",
            metric_namespace="CustomApp/Monitoring",
            metric_value="1",
            default_value=0,
        )

    def _create_cloudwatch_alarm(self) -> None:
        """Create CloudWatch alarm for error threshold monitoring"""
        
        # Create custom metric for the alarm
        error_metric = cloudwatch.Metric(
            namespace="CustomApp/Monitoring",
            metric_name="ApplicationErrors",
            statistic="Sum",
            period=Duration.minutes(self.evaluation_period),
        )

        # Create CloudWatch alarm
        self.alarm = cloudwatch.Alarm(
            self,
            "ApplicationErrorsAlarm",
            alarm_name="application-errors-alarm",
            alarm_description="Alert when application errors exceed threshold",
            metric=error_metric,
            threshold=self.error_threshold,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS action to the alarm
        self.alarm.add_alarm_action(
            cw_actions.SnsAction(self.sns_topic)
        )
        
        # Add OK action for recovery notifications
        self.alarm.add_ok_action(
            cw_actions.SnsAction(self.sns_topic)
        )

        # Add tags for resource management
        cdk.Tags.of(self.alarm).add("Purpose", "LogMonitoring")
        cdk.Tags.of(self.alarm).add("Environment", "Demo")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information"""
        
        cdk.CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group name for application logs",
            export_name="LogMonitoringLogGroupName",
        )

        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for log monitoring alerts",
            export_name="LogMonitoringSNSTopicArn",
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function name for log processing",
            export_name="LogMonitoringLambdaFunctionName",
        )

        cdk.CfnOutput(
            self,
            "CloudWatchAlarmName",
            value=self.alarm.alarm_name,
            description="CloudWatch alarm name for error monitoring",
            export_name="LogMonitoringAlarmName",
        )

        cdk.CfnOutput(
            self,
            "MetricNamespace",
            value="CustomApp/Monitoring",
            description="CloudWatch metric namespace for application errors",
            export_name="LogMonitoringMetricNamespace",
        )


class LogMonitoringApp(cdk.App):
    """CDK App for Log Monitoring Infrastructure"""

    def __init__(self) -> None:
        super().__init__()

        # Get configuration from environment variables or use defaults
        notification_email = os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")
        log_retention_days = int(os.environ.get("LOG_RETENTION_DAYS", "7"))
        error_threshold = int(os.environ.get("ERROR_THRESHOLD", "2"))
        evaluation_period = int(os.environ.get("EVALUATION_PERIOD_MINUTES", "5"))

        # Create the stack
        LogMonitoringStack(
            self,
            "LogMonitoringStack",
            notification_email=notification_email,
            log_retention_days=log_retention_days,
            error_threshold=error_threshold,
            evaluation_period_minutes=evaluation_period,
            description="Basic Log Monitoring with CloudWatch Logs and SNS",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


def main() -> None:
    """Main entry point for the CDK application"""
    app = LogMonitoringApp()
    app.synth()


if __name__ == "__main__":
    main()