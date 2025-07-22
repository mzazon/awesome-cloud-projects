#!/usr/bin/env python3
"""
CDK Python application for S3 Access Logging and Security Monitoring.

This application deploys a comprehensive S3 access logging and security monitoring
solution that combines S3 Server Access Logging with CloudTrail API monitoring,
real-time alerting through EventBridge and SNS, and automated analysis using Lambda.
"""

import aws_cdk as cdk
from constructs import Construct
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_cloudtrail as cloudtrail,
    aws_logs as logs,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_lambda as lambda_,
    aws_cloudwatch as cloudwatch,
    Duration,
    CfnOutput,
    RemovalPolicy,
)
import json
from typing import Dict, List, Any


class S3AccessLoggingSecurityMonitoringStack(Stack):
    """
    CDK Stack for S3 Access Logging and Security Monitoring.
    
    This stack creates:
    - Source S3 bucket for monitoring
    - Access logs bucket with proper permissions
    - CloudTrail for API monitoring
    - CloudWatch integration for real-time monitoring
    - EventBridge rules for security alerts
    - SNS topic for notifications
    - Lambda function for advanced security analysis
    - CloudWatch dashboard for operational visibility
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: str,
        **kwargs
    ) -> None:
        """
        Initialize the S3 Access Logging and Security Monitoring stack.
        
        Args:
            scope: CDK scope
            construct_id: Construct identifier
            notification_email: Email address for security alerts
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.notification_email = notification_email
        self.account_id = self.account
        self.region = self.region

        # Create S3 buckets
        self._create_s3_buckets()
        
        # Create CloudTrail infrastructure
        self._create_cloudtrail()
        
        # Create security monitoring
        self._create_security_monitoring()
        
        # Create Lambda function for advanced analysis
        self._create_lambda_function()
        
        # Create CloudWatch dashboard
        self._create_dashboard()
        
        # Create stack outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for source data and access logs."""
        
        # Source bucket for monitoring
        self.source_bucket = s3.Bucket(
            self,
            "SourceBucket",
            bucket_name=f"secure-docs-{self.account_id}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Access logs bucket
        self.logs_bucket = s3.Bucket(
            self,
            "LogsBucket",
            bucket_name=f"s3-access-logs-{self.account_id}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # CloudTrail bucket
        self.cloudtrail_bucket = s3.Bucket(
            self,
            "CloudTrailBucket",
            bucket_name=f"cloudtrail-logs-{self.account_id}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Configure S3 Server Access Logging
        self._configure_access_logging()

    def _configure_access_logging(self) -> None:
        """Configure S3 Server Access Logging with proper permissions."""
        
        # Create bucket policy for S3 logging service
        logging_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="S3ServerAccessLogsPolicy",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("logging.s3.amazonaws.com")],
                    actions=["s3:PutObject"],
                    resources=[f"{self.logs_bucket.bucket_arn}/access-logs/*"],
                    conditions={
                        "ArnLike": {
                            "aws:SourceArn": self.source_bucket.bucket_arn
                        },
                        "StringEquals": {
                            "aws:SourceAccount": self.account_id
                        }
                    }
                )
            ]
        )

        # Apply policy to logs bucket
        self.logs_bucket.add_to_resource_policy(logging_policy.statements[0])

        # Enable server access logging with date-based partitioning
        cfn_bucket = self.source_bucket.node.default_child
        cfn_bucket.logging_configuration = {
            "destinationBucketName": self.logs_bucket.bucket_name,
            "logFilePrefix": "access-logs/",
            "targetObjectKeyFormat": {
                "partitionedPrefix": {
                    "partitionDateSource": "EventTime"
                }
            }
        }

    def _create_cloudtrail(self) -> None:
        """Create CloudTrail for S3 API monitoring."""
        
        # Create CloudWatch log group for CloudTrail
        self.cloudtrail_log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name="/aws/cloudtrail/s3-security-monitoring",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create IAM role for CloudTrail CloudWatch integration
        self.cloudtrail_role = iam.Role(
            self,
            "CloudTrailLogsRole",
            assumed_by=iam.ServicePrincipal("cloudtrail.amazonaws.com"),
            inline_policies={
                "CloudTrailLogsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                                "logs:DescribeLogGroups",
                                "logs:DescribeLogStreams",
                            ],
                            resources=[f"{self.cloudtrail_log_group.log_group_arn}*"],
                        )
                    ]
                )
            },
        )

        # Create CloudTrail
        self.trail = cloudtrail.Trail(
            self,
            "S3SecurityMonitoringTrail",
            trail_name="s3-security-monitoring-trail",
            bucket=self.cloudtrail_bucket,
            s3_key_prefix="cloudtrail-logs/",
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            cloud_watch_logs_group=self.cloudtrail_log_group,
            cloud_watch_logs_role=self.cloudtrail_role,
        )

        # Add S3 data events
        self.trail.add_s3_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            s3_bucket_and_object_prefix=[f"{self.source_bucket.bucket_name}/"],
        )

    def _create_security_monitoring(self) -> None:
        """Create security monitoring with EventBridge and SNS."""
        
        # Create SNS topic for security alerts
        self.security_topic = sns.Topic(
            self,
            "SecurityAlertsTopic",
            topic_name="s3-security-alerts",
            display_name="S3 Security Alerts",
        )

        # Subscribe email to SNS topic
        self.security_topic.add_subscription(
            subscriptions.EmailSubscription(self.notification_email)
        )

        # Create EventBridge rule for unauthorized access attempts
        self.unauthorized_access_rule = events.Rule(
            self,
            "UnauthorizedAccessRule",
            rule_name="S3UnauthorizedAccess",
            description="Detects unauthorized S3 access attempts",
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["AWS API Call via CloudTrail"],
                detail={
                    "eventName": ["GetObject", "PutObject", "DeleteObject"],
                    "errorCode": ["AccessDenied", "SignatureDoesNotMatch"],
                },
            ),
        )

        # Add SNS target to EventBridge rule
        self.unauthorized_access_rule.add_target(
            targets.SnsTopic(self.security_topic)
        )

        # Create EventBridge rule for administrative actions
        self.admin_actions_rule = events.Rule(
            self,
            "AdminActionsRule",
            rule_name="S3AdminActions",
            description="Detects S3 administrative actions",
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["AWS API Call via CloudTrail"],
                detail={
                    "eventName": [
                        "PutBucketPolicy",
                        "DeleteBucketPolicy",
                        "PutBucketAcl",
                        "DeleteBucket",
                    ]
                },
            ),
        )

        # Add SNS target to admin actions rule
        self.admin_actions_rule.add_target(
            targets.SnsTopic(self.security_topic)
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for advanced security analysis."""
        
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "SecurityMonitorLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                ),
            ],
            inline_policies={
                "SecurityMonitorPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.security_topic.topic_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["*"],
                        ),
                    ]
                )
            },
        )

        # Lambda function code
        lambda_code = """
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    try:
        # Get SNS topic ARN from environment
        sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
        
        # Parse CloudTrail event
        if 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws.s3':
                    analyze_s3_event(record, sns_topic_arn)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Security monitoring completed')
        }
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        raise

def analyze_s3_event(event, sns_topic_arn):
    event_name = event.get('eventName', '')
    source_ip = event.get('sourceIPAddress', '')
    user_identity = event.get('userIdentity', {})
    
    # Check for suspicious patterns
    if is_suspicious_activity(event_name, source_ip, user_identity):
        send_alert(event, sns_topic_arn)

def is_suspicious_activity(event_name, source_ip, user_identity):
    # Example security checks
    suspicious_actions = ['DeleteBucket', 'PutBucketPolicy', 'PutBucketAcl']
    
    if event_name in suspicious_actions:
        return True
    
    # Check for access from unusual locations (customize as needed)
    if source_ip and not source_ip.startswith('10.') and not source_ip.startswith('192.168.'):
        return True
    
    return False

def send_alert(event, sns_topic_arn):
    if not sns_topic_arn:
        logger.error("SNS topic ARN not configured")
        return
    
    sns = boto3.client('sns')
    
    message = f"Security Alert: Suspicious S3 activity detected\\n"
    message += f"Event: {event.get('eventName', 'Unknown')}\\n"
    message += f"Source IP: {event.get('sourceIPAddress', 'Unknown')}\\n"
    message += f"Time: {event.get('eventTime', 'Unknown')}\\n"
    message += f"User: {event.get('userIdentity', {}).get('arn', 'Unknown')}"
    
    sns.publish(
        TopicArn=sns_topic_arn,
        Message=message,
        Subject='S3 Security Alert'
    )
    
    logger.info(f"Security alert sent for event: {event.get('eventName', 'Unknown')}")
"""

        # Create Lambda function
        self.security_monitor_function = lambda_.Function(
            self,
            "SecurityMonitorFunction",
            function_name="s3-security-monitor",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "SNS_TOPIC_ARN": self.security_topic.topic_arn,
            },
        )

        # Create EventBridge rule to trigger Lambda
        security_analysis_rule = events.Rule(
            self,
            "SecurityAnalysisRule",
            rule_name="S3SecurityAnalysis",
            description="Triggers Lambda for advanced S3 security analysis",
            event_pattern=events.EventPattern(
                source=["aws.s3"],
                detail_type=["AWS API Call via CloudTrail"],
            ),
        )

        # Add Lambda target to EventBridge rule
        security_analysis_rule.add_target(
            targets.LambdaFunction(self.security_monitor_function)
        )

    def _create_dashboard(self) -> None:
        """Create CloudWatch dashboard for monitoring."""
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "S3SecurityDashboard",
            dashboard_name="S3SecurityMonitoring",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="S3 Bucket Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.source_bucket.bucket_name,
                                    "StorageType": "StandardStorage",
                                },
                                statistic="Average",
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="NumberOfObjects",
                                dimensions_map={
                                    "BucketName": self.source_bucket.bucket_name,
                                    "StorageType": "AllStorageTypes",
                                },
                                statistic="Average",
                            ),
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Top S3 API Calls",
                        log_groups=[self.cloudtrail_log_group],
                        query_lines=[
                            "fields @timestamp, eventName, sourceIPAddress, userIdentity.type",
                            "| filter eventName like /GetObject|PutObject|DeleteObject/",
                            "| stats count() by eventName",
                            "| sort count desc",
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Failed Access Attempts",
                        log_groups=[self.cloudtrail_log_group],
                        query_lines=[
                            "fields @timestamp, eventName, sourceIPAddress, errorCode, errorMessage",
                            "| filter errorCode = 'AccessDenied'",
                            "| stats count() by sourceIPAddress",
                            "| sort count desc",
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Administrative Actions",
                        log_groups=[self.cloudtrail_log_group],
                        query_lines=[
                            "fields @timestamp, eventName, sourceIPAddress, userIdentity.arn",
                            "| filter eventName like /PutBucket|DeleteBucket|PutBucketPolicy/",
                            "| sort @timestamp desc",
                        ],
                        width=12,
                        height=6,
                    ),
                ],
            ],
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        
        CfnOutput(
            self,
            "SourceBucketName",
            value=self.source_bucket.bucket_name,
            description="Name of the source S3 bucket being monitored",
        )

        CfnOutput(
            self,
            "LogsBucketName",
            value=self.logs_bucket.bucket_name,
            description="Name of the S3 access logs bucket",
        )

        CfnOutput(
            self,
            "CloudTrailBucketName",
            value=self.cloudtrail_bucket.bucket_name,
            description="Name of the CloudTrail logs bucket",
        )

        CfnOutput(
            self,
            "CloudTrailName",
            value=self.trail.trail_name,
            description="Name of the CloudTrail trail",
        )

        CfnOutput(
            self,
            "SecurityTopicArn",
            value=self.security_topic.topic_arn,
            description="ARN of the SNS topic for security alerts",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.security_monitor_function.function_name,
            description="Name of the Lambda function for security monitoring",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
        )

        CfnOutput(
            self,
            "LogGroupName",
            value=self.cloudtrail_log_group.log_group_name,
            description="Name of the CloudWatch log group for CloudTrail",
        )


class S3AccessLoggingApp(cdk.App):
    """CDK Application for S3 Access Logging and Security Monitoring."""

    def __init__(self):
        super().__init__()

        # Get notification email from context or environment
        notification_email = self.node.try_get_context("notification_email")
        if not notification_email:
            import os
            notification_email = os.environ.get("NOTIFICATION_EMAIL", "admin@example.com")

        # Create the main stack
        S3AccessLoggingSecurityMonitoringStack(
            self,
            "S3AccessLoggingSecurityMonitoringStack",
            notification_email=notification_email,
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            ),
        )


# Create the CDK app
app = S3AccessLoggingApp()
app.synth()