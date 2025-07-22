#!/usr/bin/env python3
"""
CDK Application for Operational Analytics with CloudWatch Insights

This CDK application deploys a comprehensive operational analytics solution using:
- CloudWatch Logs for log aggregation
- CloudWatch Logs Insights for log analysis
- Lambda functions for log generation and alert handling
- CloudWatch Dashboards for visualization
- SNS for alerting
- CloudWatch Alarms with anomaly detection

Author: CDK Generator
Version: 2.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    CfnOutput,
    Tags,
    Duration,
    aws_logs as logs,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_sns as sns,
    aws_sns_subscriptions as subs,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct


class OperationalAnalyticsStack(Stack):
    """
    CDK Stack for Operational Analytics with CloudWatch Insights
    
    This stack creates a complete operational analytics solution including:
    - Log groups for application logs
    - Lambda functions for log generation and processing
    - CloudWatch dashboards for visualization
    - SNS topics and alarms for alerting
    - Anomaly detection for proactive monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.app_name = "operational-analytics"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Create core infrastructure
        self.log_group = self._create_log_group()
        self.sns_topic = self._create_sns_topic()
        self.log_generator_lambda = self._create_log_generator_lambda()
        self.alert_handler_lambda = self._create_alert_handler_lambda()
        
        # Create monitoring and alerting
        self.metric_filters = self._create_metric_filters()
        self.cloudwatch_alarms = self._create_cloudwatch_alarms()
        self.anomaly_detectors = self._create_anomaly_detectors()
        self.dashboard = self._create_dashboard()
        
        # Schedule log generation for demo purposes
        self._create_log_generation_schedule()
        
        # Create outputs
        self._create_outputs()
        
        # Add tags to all resources
        self._add_tags()

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch Log Group for operational analytics"""
        log_group = logs.LogGroup(
            self,
            "OperationalLogGroup",
            log_group_name=f"/aws/lambda/{self.app_name}-demo",
            retention=logs.RetentionDays.ONE_MONTH,  # Cost optimization
            removal_policy=cdk.RemovalPolicy.DESTROY
        )
        
        return log_group

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS Topic for operational alerts"""
        topic = sns.Topic(
            self,
            "OperationalAlertsTopic",
            topic_name=f"{self.app_name}-alerts",
            display_name="Operational Analytics Alerts",
            description="SNS topic for operational analytics alerts and notifications"
        )
        
        # Add email subscription if provided in context
        email = self.node.try_get_context("alertEmail")
        if email:
            topic.add_subscription(
                subs.EmailSubscription(email)
            )
        
        return topic

    def _create_log_generator_lambda(self) -> lambda_.Function:
        """Create Lambda function for generating sample log data"""
        
        # IAM role for Lambda
        lambda_role = iam.Role(
            self,
            "LogGeneratorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "LogWritePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=[f"{self.log_group.log_group_arn}:*"]
                        )
                    ]
                )
            }
        )
        
        # Lambda function code
        function_code = """
import json
import random
import time
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    \"\"\"Generate various log patterns for operational analytics\"\"\"
    
    # Generate various log patterns for analytics
    log_patterns = [
        {"level": "INFO", "message": "User authentication successful", "user_id": f"user_{random.randint(1000, 9999)}", "response_time": random.randint(100, 500)},
        {"level": "ERROR", "message": "Database connection failed", "error_code": "DB_CONN_ERR", "retry_count": random.randint(1, 3)},
        {"level": "WARN", "message": "High memory usage detected", "memory_usage": random.randint(70, 95), "threshold": 80},
        {"level": "INFO", "message": "API request processed", "endpoint": f"/api/v1/users/{random.randint(1, 100)}", "method": random.choice(["GET", "POST", "PUT"])},
        {"level": "ERROR", "message": "Payment processing failed", "transaction_id": f"txn_{random.randint(100000, 999999)}", "amount": random.randint(10, 1000)},
        {"level": "INFO", "message": "Cache hit", "cache_key": f"user_profile_{random.randint(1, 1000)}", "hit_rate": random.uniform(0.7, 0.95)},
        {"level": "DEBUG", "message": "SQL query executed", "query_time": random.randint(50, 2000), "table": random.choice(["users", "orders", "products"])},
        {"level": "WARN", "message": "Rate limit approaching", "current_rate": random.randint(80, 99), "limit": 100}
    ]
    
    # Generate 5-10 random log entries
    for i in range(random.randint(5, 10)):
        log_entry = random.choice(log_patterns)
        log_entry["timestamp"] = datetime.utcnow().isoformat()
        log_entry["request_id"] = f"req_{random.randint(1000000, 9999999)}"
        
        # Log with different levels
        if log_entry["level"] == "ERROR":
            logger.error(json.dumps(log_entry))
        elif log_entry["level"] == "WARN":
            logger.warning(json.dumps(log_entry))
        elif log_entry["level"] == "DEBUG":
            logger.debug(json.dumps(log_entry))
        else:
            logger.info(json.dumps(log_entry))
        
        # Small delay to spread timestamps
        time.sleep(0.1)
    
    return {
        'statusCode': 200,
        'body': json.dumps('Log generation completed successfully')
    }
"""
        
        function = lambda_.Function(
            self,
            "LogGeneratorFunction",
            function_name=f"{self.app_name}-log-generator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(function_code),
            timeout=Duration.seconds(30),
            role=lambda_role,
            description="Generates sample operational log data for analytics testing",
            environment={
                "LOG_GROUP_NAME": self.log_group.log_group_name
            }
        )
        
        return function

    def _create_alert_handler_lambda(self) -> lambda_.Function:
        """Create Lambda function for handling operational alerts"""
        
        # IAM role for alert handler
        alert_role = iam.Role(
            self,
            "AlertHandlerRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "AlertHandlerPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:StartQuery",
                                "logs:GetQueryResults",
                                "sns:Publish"
                            ],
                            resources=[
                                f"{self.log_group.log_group_arn}:*",
                                self.sns_topic.topic_arn
                            ]
                        )
                    ]
                )
            }
        )
        
        alert_code = """
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    \"\"\"Handle operational alerts and perform automated analysis\"\"\"
    
    # Parse SNS message
    message = json.loads(event['Records'][0]['Sns']['Message'])
    alarm_name = message.get('AlarmName', 'Unknown')
    
    logger.info(f"Processing alert for alarm: {alarm_name}")
    
    # Perform automated log analysis based on alarm type
    if 'ErrorRate' in alarm_name:
        perform_error_analysis()
    elif 'LogIngestion' in alarm_name:
        perform_ingestion_analysis()
    elif 'LogVolume' in alarm_name:
        perform_volume_analysis()
    
    return {
        'statusCode': 200,
        'body': json.dumps('Alert processed successfully')
    }

def perform_error_analysis():
    \"\"\"Analyze recent error patterns\"\"\"
    logger.info("Performing automated error pattern analysis")
    # Implementation would include CloudWatch Insights queries
    
def perform_ingestion_analysis():
    \"\"\"Analyze log ingestion anomalies\"\"\"
    logger.info("Analyzing log ingestion patterns")
    # Implementation would include anomaly investigation
    
def perform_volume_analysis():
    \"\"\"Analyze high volume log events\"\"\"
    logger.info("Investigating high log volume events")
    # Implementation would include volume breakdown analysis
"""
        
        alert_function = lambda_.Function(
            self,
            "AlertHandlerFunction",
            function_name=f"{self.app_name}-alert-handler",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(alert_code),
            timeout=Duration.seconds(60),
            role=alert_role,
            description="Handles operational alerts and performs automated analysis"
        )
        
        # Subscribe alert handler to SNS topic
        self.sns_topic.add_subscription(
            subs.LambdaSubscription(alert_function)
        )
        
        return alert_function

    def _create_metric_filters(self) -> Dict[str, logs.MetricFilter]:
        """Create CloudWatch metric filters for operational metrics"""
        
        filters = {}
        
        # Error rate metric filter
        filters['error_rate'] = logs.MetricFilter(
            self,
            "ErrorRateFilter",
            log_group=self.log_group,
            metric_filter_name="ErrorRateFilter",
            filter_pattern=logs.FilterPattern.literal('[timestamp, requestId, level="ERROR", ...]'),
            metric_namespace="OperationalAnalytics",
            metric_name="ErrorRate",
            metric_value="1",
            default_value=0
        )
        
        # Performance metric filter
        filters['response_time'] = logs.MetricFilter(
            self,
            "ResponseTimeFilter",
            log_group=self.log_group,
            metric_filter_name="ResponseTimeFilter",
            filter_pattern=logs.FilterPattern.literal('[timestamp, requestId, level, message, ..., response_time]'),
            metric_namespace="OperationalAnalytics",
            metric_name="ResponseTime",
            metric_value="$response_time",
            default_value=0
        )
        
        # Log volume metric filter
        filters['log_volume'] = logs.MetricFilter(
            self,
            "LogVolumeFilter", 
            log_group=self.log_group,
            metric_filter_name="LogVolumeFilter",
            filter_pattern=logs.FilterPattern.all(),
            metric_namespace="OperationalAnalytics",
            metric_name="LogVolume",
            metric_value="1",
            default_value=0
        )
        
        return filters

    def _create_cloudwatch_alarms(self) -> Dict[str, cloudwatch.Alarm]:
        """Create CloudWatch alarms for operational monitoring"""
        
        alarms = {}
        
        # High error rate alarm
        alarms['high_error_rate'] = cloudwatch.Alarm(
            self,
            "HighErrorRateAlarm",
            alarm_name=f"{self.app_name}-high-error-rate",
            alarm_description="Alert when error rate exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="OperationalAnalytics",
                metric_name="ErrorRate",
                statistic="Sum"
            ),
            threshold=5,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            period=Duration.minutes(5),
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # High log volume alarm  
        alarms['high_log_volume'] = cloudwatch.Alarm(
            self,
            "HighLogVolumeAlarm",
            alarm_name=f"{self.app_name}-high-log-volume",
            alarm_description="Alert when log volume exceeds budget threshold",
            metric=cloudwatch.Metric(
                namespace="OperationalAnalytics", 
                metric_name="LogVolume",
                statistic="Sum"
            ),
            threshold=10000,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            period=Duration.hours(1),
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Add SNS actions to alarms
        for alarm in alarms.values():
            alarm.add_alarm_action(
                cloudwatch.SnsAction(self.sns_topic)
            )
        
        return alarms

    def _create_anomaly_detectors(self) -> Dict[str, cloudwatch.CfnAnomalyDetector]:
        """Create CloudWatch anomaly detectors for intelligent monitoring"""
        
        detectors = {}
        
        # Log ingestion anomaly detector
        detectors['log_ingestion'] = cloudwatch.CfnAnomalyDetector(
            self,
            "LogIngestionAnomalyDetector",
            namespace="AWS/Logs",
            metric_name="IncomingBytes",
            stat="Average",
            dimensions=[{
                "name": "LogGroupName",
                "value": self.log_group.log_group_name
            }]
        )
        
        # Create anomaly alarm
        anomaly_alarm = cloudwatch.CfnAlarm(
            self,
            "LogIngestionAnomalyAlarm",
            alarm_name=f"{self.app_name}-log-ingestion-anomaly",
            alarm_description="Detect anomalies in log ingestion patterns",
            comparison_operator="LessThanLowerOrGreaterThanUpperThreshold",
            evaluation_periods=2,
            threshold=2,
            metrics=[
                {
                    "id": "m1",
                    "metricStat": {
                        "metric": {
                            "namespace": "AWS/Logs",
                            "metricName": "IncomingBytes",
                            "dimensions": [{"name": "LogGroupName", "value": self.log_group.log_group_name}]
                        },
                        "period": 300,
                        "stat": "Average"
                    }
                },
                {
                    "id": "ad1", 
                    "expression": "ANOMALY_DETECTION_FUNCTION(m1, 2)"
                }
            ],
            alarm_actions=[self.sns_topic.topic_arn],
            treat_missing_data="notBreaching"
        )
        
        return detectors

    def _create_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for operational analytics visualization"""
        
        dashboard = cloudwatch.Dashboard(
            self,
            "OperationalAnalyticsDashboard",
            dashboard_name=f"{self.app_name}-dashboard",
            widgets=[
                [
                    # Error analysis widget
                    cloudwatch.LogQueryWidget(
                        title="Error Analysis",
                        log_groups=[self.log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| filter @message like /ERROR/",
                            "| stats count() as error_count by bin(5m)",
                            "| sort @timestamp desc",
                            "| limit 50"
                        ],
                        width=12,
                        height=6
                    ),
                    
                    # Performance metrics widget
                    cloudwatch.LogQueryWidget(
                        title="Performance Metrics",
                        log_groups=[self.log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| filter @message like /response_time/",
                            "| parse @message '\"response_time\": *' as response_time",
                            "| stats avg(response_time) as avg_response_time, max(response_time) as max_response_time by bin(1m)",
                            "| sort @timestamp desc"
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # User activity widget
                    cloudwatch.LogQueryWidget(
                        title="Top Active Users",
                        log_groups=[self.log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| filter @message like /user_id/",
                            "| parse @message '\"user_id\": \"*\"' as user_id",
                            "| stats count() as activity_count by user_id",
                            "| sort activity_count desc",
                            "| limit 20"
                        ],
                        width=24,
                        height=6
                    )
                ],
                [
                    # Error rate metric widget
                    cloudwatch.GraphWidget(
                        title="Error Rate Trend",
                        left=[
                            cloudwatch.Metric(
                                namespace="OperationalAnalytics",
                                metric_name="ErrorRate",
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    ),
                    
                    # Log volume metric widget  
                    cloudwatch.GraphWidget(
                        title="Log Volume Trend",
                        left=[
                            cloudwatch.Metric(
                                namespace="OperationalAnalytics",
                                metric_name="LogVolume", 
                                statistic="Sum",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )
        
        return dashboard

    def _create_log_generation_schedule(self) -> None:
        """Create EventBridge rule to periodically generate log data for demo"""
        
        # EventBridge rule for scheduled log generation
        rule = events.Rule(
            self,
            "LogGenerationSchedule",
            schedule=events.Schedule.rate(Duration.minutes(5)),
            description="Generates sample log data every 5 minutes for demo purposes"
        )
        
        # Add Lambda target
        rule.add_target(
            targets.LambdaFunction(self.log_generator_lambda)
        )
        
        # Grant EventBridge permission to invoke Lambda
        self.log_generator_lambda.add_permission(
            "AllowEventBridgeInvoke",
            principal=iam.ServicePrincipal("events.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=rule.rule_arn
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="CloudWatch Log Group for operational analytics"
        )
        
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL for operational analytics"
        )
        
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="SNS Topic ARN for operational alerts"
        )
        
        CfnOutput(
            self,
            "LogGeneratorFunctionName",
            value=self.log_generator_lambda.function_name,
            description="Lambda function name for log generation"
        )

    def _add_tags(self) -> None:
        """Add tags to all resources in the stack"""
        
        Tags.of(self).add("Project", self.app_name)
        Tags.of(self).add("Environment", self.environment)
        Tags.of(self).add("Purpose", "operational-analytics")
        Tags.of(self).add("ManagedBy", "CDK")


# CDK Application
app = App()

# Stack configuration from context
stack_name = app.node.try_get_context("stackName") or "OperationalAnalyticsStack"
environment = app.node.try_get_context("environment") or "dev"

# Deploy stack
OperationalAnalyticsStack(
    app,
    stack_name,
    env=cdk.Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    ),
    description=f"Operational Analytics with CloudWatch Insights - {environment} environment"
)

app.synth()