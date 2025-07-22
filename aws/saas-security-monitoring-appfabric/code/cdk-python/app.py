#!/usr/bin/env python3
"""
AWS CDK Python Application for Centralized SaaS Security Monitoring.

This application creates a comprehensive security monitoring solution using
AWS AppFabric, EventBridge, Lambda, and SNS to monitor SaaS applications
and generate intelligent security alerts.
"""

import os
from typing import Any, Dict, Optional
import aws_cdk as cdk
from aws_cdk import (
    App,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk.aws_s3 import Bucket, BucketEncryption, VersioningConfiguration
from aws_cdk.aws_iam import (
    Role,
    ServicePrincipal,
    PolicyDocument,
    PolicyStatement,
    Effect,
    ManagedPolicy,
)
from aws_cdk.aws_events import EventBus, Rule, EventPattern
from aws_cdk.aws_lambda import (
    Function,
    Runtime,
    Code,
    Architecture,
    LayerVersion,
)
from aws_cdk.aws_sns import Topic, Subscription, SubscriptionProtocol
from aws_cdk.aws_events_targets import LambdaFunction
from aws_cdk.aws_logs import LogGroup, RetentionDays
from constructs import Construct


class CentralizedSaasSecurityMonitoringStack(Stack):
    """
    CDK Stack for centralized SaaS security monitoring infrastructure.
    
    This stack creates all the necessary AWS resources for monitoring
    SaaS applications using AppFabric, EventBridge, Lambda, and SNS.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        notification_email: Optional[str] = None,
        **kwargs: Any,
    ) -> None:
        """
        Initialize the SaaS Security Monitoring stack.
        
        Args:
            scope: CDK app or parent construct
            construct_id: Unique identifier for this construct
            notification_email: Email address for security alerts
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.notification_email = notification_email or "security@company.com"
        
        # Create S3 bucket for AppFabric security logs
        self.security_logs_bucket = self._create_security_logs_bucket()
        
        # Create IAM roles for service integration
        self.appfabric_role = self._create_appfabric_service_role()
        self.lambda_role = self._create_lambda_execution_role()
        
        # Create custom EventBridge bus for security events
        self.security_event_bus = self._create_security_event_bus()
        
        # Create SNS topic for security alerts
        self.security_alerts_topic = self._create_security_alerts_topic()
        
        # Create Lambda function for security event processing
        self.security_processor = self._create_security_processor_function()
        
        # Create EventBridge rule for automatic event processing
        self.security_event_rule = self._create_security_event_rule()
        
        # Output important resource information
        self._create_outputs()

    def _create_security_logs_bucket(self) -> Bucket:
        """Create S3 bucket for storing AppFabric security logs."""
        bucket = Bucket(
            self,
            "SecurityLogsBucket",
            bucket_name=f"security-logs-{self.account}-{self.region}",
            encryption=BucketEncryption.S3_MANAGED,
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            event_bridge_enabled=True,  # Enable EventBridge notifications
        )
        
        Tags.of(bucket).add("Purpose", "SecurityMonitoring")
        Tags.of(bucket).add("DataClassification", "Sensitive")
        
        return bucket

    def _create_appfabric_service_role(self) -> Role:
        """Create IAM role for AppFabric to write logs to S3."""
        role = Role(
            self,
            "AppFabricServiceRole",
            assumed_by=ServicePrincipal("appfabric.amazonaws.com"),
            description="Service role for AWS AppFabric to access S3 bucket",
            inline_policies={
                "S3AccessPolicy": PolicyDocument(
                    statements=[
                        PolicyStatement(
                            effect=Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:PutObjectAcl",
                                "s3:GetBucketLocation",
                            ],
                            resources=[
                                self.security_logs_bucket.bucket_arn,
                                f"{self.security_logs_bucket.bucket_arn}/*",
                            ],
                        )
                    ]
                )
            },
        )
        
        Tags.of(role).add("Service", "AppFabric")
        return role

    def _create_lambda_execution_role(self) -> Role:
        """Create IAM role for Lambda function execution."""
        role = Role(
            self,
            "LambdaSecurityProcessorRole",
            assumed_by=ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for security event processing Lambda",
            managed_policies=[
                ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add inline policy for SNS and S3 access
        role.add_to_policy(
            PolicyStatement(
                effect=Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[f"arn:aws:sns:{self.region}:{self.account}:*"],
            )
        )
        
        role.add_to_policy(
            PolicyStatement(
                effect=Effect.ALLOW,
                actions=["s3:GetObject"],
                resources=[f"{self.security_logs_bucket.bucket_arn}/*"],
            )
        )
        
        Tags.of(role).add("Service", "Lambda")
        return role

    def _create_security_event_bus(self) -> EventBus:
        """Create custom EventBridge bus for security events."""
        event_bus = EventBus(
            self,
            "SecurityMonitoringEventBus",
            event_bus_name="security-monitoring-bus",
            description="Custom event bus for SaaS security monitoring events",
        )
        
        Tags.of(event_bus).add("Purpose", "SecurityMonitoring")
        return event_bus

    def _create_security_alerts_topic(self) -> Topic:
        """Create SNS topic for security alerts."""
        topic = Topic(
            self,
            "SecurityAlertsTopic",
            topic_name="security-alerts",
            display_name="SaaS Security Monitoring Alerts",
            description="SNS topic for centralized security alerts from SaaS monitoring",
        )
        
        # Subscribe email endpoint if provided
        if self.notification_email:
            Subscription(
                self,
                "EmailSubscription",
                topic=topic,
                protocol=SubscriptionProtocol.EMAIL,
                endpoint=self.notification_email,
            )
        
        Tags.of(topic).add("Purpose", "SecurityAlerting")
        return topic

    def _create_security_processor_function(self) -> Function:
        """Create Lambda function for processing security events."""
        
        # Create log group with retention policy
        log_group = LogGroup(
            self,
            "SecurityProcessorLogGroup",
            log_group_name=f"/aws/lambda/security-processor-{self.region}",
            retention=RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Lambda function code
        lambda_code = '''import json
import boto3
import logging
import os
import re
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

sns = boto3.client('sns')

def lambda_handler(event, context):
    """Process security events from AppFabric and generate alerts"""
    
    try:
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Process S3 events from EventBridge
        if 'source' in event and event['source'] == 'aws.s3':
            process_s3_security_log(event)
        
        # Process direct EventBridge events
        elif 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    process_s3_security_log(record)
        
        # Process custom security events
        else:
            process_custom_security_event(event)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Security events processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing security event: {str(e)}")
        raise

def process_s3_security_log(event):
    """Process security logs uploaded to S3 by AppFabric"""
    
    detail = event.get('detail', {})
    bucket = detail.get('bucket', {}).get('name', 'unknown')
    key = detail.get('object', {}).get('key', 'unknown')
    
    logger.info(f"Processing security log: s3://{bucket}/{key}")
    
    # Extract application name from S3 key path
    app_name = extract_app_name(key)
    
    # Generate alert for new security log
    alert_message = {
        'alert_type': 'NEW_SECURITY_LOG',
        'application': app_name,
        'timestamp': datetime.utcnow().isoformat(),
        's3_location': f"s3://{bucket}/{key}",
        'severity': 'INFO',
        'event_source': 'AppFabric'
    }
    
    send_security_alert(alert_message)

def process_custom_security_event(event):
    """Process custom security events from EventBridge"""
    
    event_type = event.get('detail-type', 'Unknown')
    source = event.get('source', 'Unknown')
    
    logger.info(f"Processing custom security event: {event_type} from {source}")
    
    # Apply threat detection logic based on event patterns
    if is_suspicious_activity(event):
        alert_message = {
            'alert_type': 'SUSPICIOUS_ACTIVITY',
            'event_type': event_type,
            'source': source,
            'timestamp': datetime.utcnow().isoformat(),
            'severity': 'HIGH',
            'details': event.get('detail', {}),
            'event_source': 'EventBridge'
        }
        
        send_security_alert(alert_message)

def is_suspicious_activity(event):
    """Apply threat detection logic to identify suspicious activities"""
    
    detail = event.get('detail', {})
    
    # Example threat detection rules
    suspicious_indicators = [
        'failed_login_attempt',
        'privilege_escalation',
        'unusual_access_pattern',
        'data_exfiltration',
        'multiple_failed_logins',
        'admin_privilege_granted'
    ]
    
    event_text = json.dumps(detail).lower()
    return any(indicator in event_text for indicator in suspicious_indicators)

def extract_app_name(s3_key):
    """Extract application name from S3 key path"""
    
    # AppFabric S3 key format: app-bundle-id/app-name/yyyy/mm/dd/file
    path_parts = s3_key.split('/')
    return path_parts[1] if len(path_parts) > 1 else 'unknown'

def send_security_alert(alert_message):
    """Send security alert via SNS"""
    
    topic_arn = os.environ.get('SNS_TOPIC_ARN')
    if not topic_arn:
        logger.error("SNS_TOPIC_ARN environment variable not set")
        return
    
    try:
        # Create multi-format message for different endpoints
        message = {
            'default': json.dumps(alert_message, indent=2),
            'email': format_email_alert(alert_message),
            'sms': format_sms_alert(alert_message)
        }
        
        response = sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message),
            MessageStructure='json',
            Subject=f"Security Alert: {alert_message['alert_type']}",
            MessageAttributes={
                'severity': {
                    'DataType': 'String',
                    'StringValue': alert_message.get('severity', 'INFO')
                },
                'alert_type': {
                    'DataType': 'String',
                    'StringValue': alert_message.get('alert_type', 'UNKNOWN')
                }
            }
        )
        
        logger.info(f"Security alert sent: {alert_message['alert_type']} - MessageId: {response.get('MessageId')}")
        
    except Exception as e:
        logger.error(f"Failed to send security alert: {str(e)}")

def format_email_alert(alert):
    """Format security alert for email delivery"""
    
    return f\"\"\"
Security Alert: {alert['alert_type']}

=== ALERT DETAILS ===
Severity: {alert['severity']}
Timestamp: {alert['timestamp']}
Application: {alert.get('application', 'N/A')}
Source: {alert.get('source', 'N/A')}
Event Source: {alert.get('event_source', 'N/A')}

=== EVENT DETAILS ===
{json.dumps(alert.get('details', {}), indent=2)}

=== ADDITIONAL INFO ===
S3 Location: {alert.get('s3_location', 'N/A')}
Event Type: {alert.get('event_type', 'N/A')}

This is an automated security alert from your centralized SaaS monitoring system.
Please review and take appropriate action if necessary.
\"\"\"

def format_sms_alert(alert):
    """Format security alert for SMS delivery"""
    
    return f"🚨 SECURITY ALERT: {alert['alert_type']} - {alert['severity']} severity detected at {alert['timestamp'][:19]}"
'''
        
        function = Function(
            self,
            "SecurityProcessorFunction",
            function_name=f"security-processor-{self.region}",
            runtime=Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            architecture=Architecture.X86_64,
            environment={
                "SNS_TOPIC_ARN": self.security_alerts_topic.topic_arn,
                "LOG_LEVEL": "INFO",
            },
            log_group=log_group,
            description="Processes security events from AppFabric and generates intelligent alerts",
        )
        
        Tags.of(function).add("Purpose", "SecurityMonitoring")
        Tags.of(function).add("Component", "EventProcessor")
        
        return function

    def _create_security_event_rule(self) -> Rule:
        """Create EventBridge rule for processing S3 security log events."""
        rule = Rule(
            self,
            "SecurityLogProcessingRule",
            rule_name="SecurityLogProcessingRule",
            description="Route S3 security logs to Lambda processor",
            event_bus=self.security_event_bus,
            event_pattern=EventPattern(
                source=["aws.s3"],
                detail_type=["Object Created"],
                detail={
                    "bucket": {"name": [self.security_logs_bucket.bucket_name]},
                    "object": {"key": [{"prefix": "security-logs/"}]},
                },
            ),
        )
        
        # Add Lambda function as target
        rule.add_target(LambdaFunction(self.security_processor))
        
        Tags.of(rule).add("Purpose", "SecurityMonitoring")
        return rule

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        cdk.CfnOutput(
            self,
            "SecurityLogsBucketName",
            value=self.security_logs_bucket.bucket_name,
            description="S3 bucket for AppFabric security logs",
        )
        
        cdk.CfnOutput(
            self,
            "SecurityLogsBucketArn",
            value=self.security_logs_bucket.bucket_arn,
            description="ARN of the S3 bucket for security logs",
        )
        
        cdk.CfnOutput(
            self,
            "AppFabricServiceRoleArn",
            value=self.appfabric_role.role_arn,
            description="IAM role ARN for AppFabric service",
        )
        
        cdk.CfnOutput(
            self,
            "SecurityEventBusArn",
            value=self.security_event_bus.event_bus_arn,
            description="Custom EventBridge bus for security events",
        )
        
        cdk.CfnOutput(
            self,
            "SecurityAlertsTopicArn",
            value=self.security_alerts_topic.topic_arn,
            description="SNS topic for security alerts",
        )
        
        cdk.CfnOutput(
            self,
            "SecurityProcessorFunctionArn",
            value=self.security_processor.function_arn,
            description="Lambda function for processing security events",
        )


def main() -> None:
    """Main application entry point."""
    app = App()
    
    # Get configuration from environment variables or context
    notification_email = app.node.try_get_context("notificationEmail") or os.getenv("NOTIFICATION_EMAIL")
    env_name = app.node.try_get_context("environment") or os.getenv("ENVIRONMENT", "dev")
    
    # Create stack with appropriate environment
    stack = CentralizedSaasSecurityMonitoringStack(
        app,
        f"CentralizedSaasSecurityMonitoring-{env_name}",
        notification_email=notification_email,
        description="Centralized SaaS security monitoring with AppFabric and EventBridge",
        env=Environment(
            account=os.getenv("CDK_DEFAULT_ACCOUNT"),
            region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
        ),
    )
    
    # Add global tags
    Tags.of(stack).add("Project", "SaasSecurityMonitoring")
    Tags.of(stack).add("Environment", env_name)
    Tags.of(stack).add("Owner", "SecurityTeam")
    Tags.of(stack).add("CostCenter", "Security")
    
    app.synth()


if __name__ == "__main__":
    main()