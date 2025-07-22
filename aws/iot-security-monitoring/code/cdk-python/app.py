#!/usr/bin/env python3
"""
AWS IoT Device Defender Security Implementation
CDK Python Application

This CDK application deploys a comprehensive IoT security monitoring solution
using AWS IoT Device Defender with automated audits, behavioral analysis,
and anomaly detection capabilities.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iot as iot,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_events as events,
    aws_events_targets as events_targets,
    aws_lambda as lambda_,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct
import json
from typing import Dict, List, Any


class IoTDeviceDefenderStack(Stack):
    """
    AWS CDK Stack for IoT Device Defender Security Implementation
    
    This stack creates:
    - IAM roles for Device Defender
    - SNS topic for security alerts
    - Security profiles with behavioral rules
    - Scheduled audit tasks
    - CloudWatch alarms
    - ML-based threat detection
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters
        self.email_address = cdk.CfnParameter(
            self,
            "NotificationEmail",
            type="String",
            description="Email address for security alerts",
            constraint_description="Must be a valid email address"
        )

        # Create SNS topic for security alerts
        self.security_alerts_topic = self._create_sns_topic()
        
        # Create IAM role for Device Defender
        self.device_defender_role = self._create_device_defender_role()
        
        # Create security profiles
        self.rule_based_profile = self._create_rule_based_security_profile()
        self.ml_based_profile = self._create_ml_based_security_profile()
        
        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()
        
        # Create scheduled audit task
        self._create_scheduled_audit()
        
        # Create audit configuration
        self._create_audit_configuration()
        
        # Create Lambda function for processing violations
        self.violation_processor = self._create_violation_processor()
        
        # Create outputs
        self._create_outputs()

    def _create_sns_topic(self) -> sns.Topic:
        """Create SNS topic for security alerts with email subscription."""
        topic = sns.Topic(
            self,
            "IoTSecurityAlerts",
            display_name="IoT Device Security Alerts",
            topic_name="iot-device-security-alerts"
        )

        # Add email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(
                self.email_address.value_as_string
            )
        )

        return topic

    def _create_device_defender_role(self) -> iam.Role:
        """Create IAM role for AWS IoT Device Defender service."""
        role = iam.Role(
            self,
            "DeviceDefenderRole",
            role_name="IoTDeviceDefenderServiceRole",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            description="Service role for AWS IoT Device Defender",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSIoTDeviceDefenderAudit"
                )
            ]
        )

        # Add permissions to publish to SNS
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "sns:Publish"
                ],
                resources=[self.security_alerts_topic.topic_arn]
            )
        )

        # Add permissions for CloudWatch metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData"
                ],
                resources=["*"],
                conditions={
                    "StringEquals": {
                        "cloudwatch:namespace": "AWS/IoT/DeviceDefender"
                    }
                }
            )
        )

        return role

    def _create_rule_based_security_profile(self) -> iot.CfnSecurityProfile:
        """Create rule-based security profile with behavioral monitoring."""
        behaviors = [
            {
                "name": "ExcessiveMessages",
                "metric": "aws:num-messages-sent",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 100},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 1,
                    "consecutiveDatapointsToClear": 1
                }
            },
            {
                "name": "AuthorizationFailures",
                "metric": "aws:num-authorization-failures",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 5},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 1,
                    "consecutiveDatapointsToClear": 1
                }
            },
            {
                "name": "LargeMessageSize",
                "metric": "aws:message-byte-size",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 1024},
                    "consecutiveDatapointsToAlarm": 1,
                    "consecutiveDatapointsToClear": 1
                }
            },
            {
                "name": "UnusualConnectionAttempts",
                "metric": "aws:num-connection-attempts",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 20},
                    "durationSeconds": 300,
                    "consecutiveDatapointsToAlarm": 1,
                    "consecutiveDatapointsToClear": 1
                }
            }
        ]

        security_profile = iot.CfnSecurityProfile(
            self,
            "RuleBasedSecurityProfile",
            security_profile_name="IoTSecurityProfile-RuleBased",
            security_profile_description="Rule-based IoT security monitoring profile",
            behaviors=behaviors,
            alert_targets={
                "SNS": {
                    "alertTargetArn": self.security_alerts_topic.topic_arn,
                    "roleArn": self.device_defender_role.role_arn
                }
            },
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT-Security"),
                cdk.CfnTag(key="Type", value="Rule-Based")
            ]
        )

        # Attach security profile to all registered things
        iot.CfnSecurityProfileTarget(
            self,
            "RuleBasedProfileTarget",
            security_profile_name=security_profile.security_profile_name,
            security_profile_target_arn=f"arn:aws:iot:{self.region}:{self.account}:all/registered-things"
        )

        return security_profile

    def _create_ml_based_security_profile(self) -> iot.CfnSecurityProfile:
        """Create ML-based security profile for advanced threat detection."""
        ml_behaviors = [
            {
                "name": "MLMessagesReceived",
                "metric": "aws:num-messages-received"
            },
            {
                "name": "MLMessagesSent",
                "metric": "aws:num-messages-sent"
            },
            {
                "name": "MLConnectionAttempts",
                "metric": "aws:num-connection-attempts"
            },
            {
                "name": "MLDisconnects",
                "metric": "aws:num-disconnects"
            }
        ]

        ml_security_profile = iot.CfnSecurityProfile(
            self,
            "MLBasedSecurityProfile",
            security_profile_name="IoTSecurityProfile-ML",
            security_profile_description="Machine learning based threat detection",
            behaviors=ml_behaviors,
            alert_targets={
                "SNS": {
                    "alertTargetArn": self.security_alerts_topic.topic_arn,
                    "roleArn": self.device_defender_role.role_arn
                }
            },
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT-Security"),
                cdk.CfnTag(key="Type", value="ML-Based")
            ]
        )

        # Attach ML security profile to all registered things
        iot.CfnSecurityProfileTarget(
            self,
            "MLBasedProfileTarget",
            security_profile_name=ml_security_profile.security_profile_name,
            security_profile_target_arn=f"arn:aws:iot:{self.region}:{self.account}:all/registered-things"
        )

        return ml_security_profile

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for security metrics."""
        # Alarm for security violations
        violations_alarm = cloudwatch.Alarm(
            self,
            "SecurityViolationsAlarm",
            alarm_name="IoT-SecurityViolations",
            alarm_description="Alert on IoT Device Defender violations",
            metric=cloudwatch.Metric(
                namespace="AWS/IoT/DeviceDefender",
                metric_name="Violations",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to alarm
        violations_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.security_alerts_topic)
        )

        # Alarm for audit failures
        audit_failures_alarm = cloudwatch.Alarm(
            self,
            "AuditFailuresAlarm",
            alarm_name="IoT-AuditFailures",
            alarm_description="Alert on IoT Device Defender audit failures",
            metric=cloudwatch.Metric(
                namespace="AWS/IoT/DeviceDefender",
                metric_name="AuditFindingsTotal",
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Add SNS action to audit failures alarm
        audit_failures_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.security_alerts_topic)
        )

    def _create_scheduled_audit(self) -> iot.CfnScheduledAudit:
        """Create scheduled audit task for continuous compliance monitoring."""
        target_check_names = [
            "CA_CERTIFICATE_EXPIRING_CHECK",
            "DEVICE_CERTIFICATE_EXPIRING_CHECK",
            "DEVICE_CERTIFICATE_SHARED_CHECK",
            "IOT_POLICY_OVERLY_PERMISSIVE_CHECK",
            "CONFLICTING_CLIENT_IDS_CHECK",
            "LOGGING_DISABLED_CHECK",
            "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK",
            "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK"
        ]

        scheduled_audit = iot.CfnScheduledAudit(
            self,
            "WeeklySecurityAudit",
            scheduled_audit_name="WeeklyIoTSecurityAudit",
            frequency="WEEKLY",
            day_of_week="MON",
            target_check_names=target_check_names,
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT-Security"),
                cdk.CfnTag(key="Schedule", value="Weekly")
            ]
        )

        return scheduled_audit

    def _create_audit_configuration(self) -> iot.CfnAccountAuditConfiguration:
        """Configure Device Defender audit settings."""
        audit_check_configurations = {
            "AUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": True},
            "CA_CERTIFICATE_EXPIRING_CHECK": {"enabled": True},
            "CONFLICTING_CLIENT_IDS_CHECK": {"enabled": True},
            "DEVICE_CERTIFICATE_EXPIRING_CHECK": {"enabled": True},
            "DEVICE_CERTIFICATE_SHARED_CHECK": {"enabled": True},
            "IOT_POLICY_OVERLY_PERMISSIVE_CHECK": {"enabled": True},
            "LOGGING_DISABLED_CHECK": {"enabled": True},
            "REVOKED_CA_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": True},
            "REVOKED_DEVICE_CERTIFICATE_STILL_ACTIVE_CHECK": {"enabled": True},
            "UNAUTHENTICATED_COGNITO_ROLE_OVERLY_PERMISSIVE_CHECK": {"enabled": True}
        }

        audit_config = iot.CfnAccountAuditConfiguration(
            self,
            "AuditConfiguration",
            account_id=self.account,
            role_arn=self.device_defender_role.role_arn,
            audit_check_configurations=audit_check_configurations,
            audit_notification_target_configurations={
                "SNS": {
                    "targetArn": self.security_alerts_topic.topic_arn,
                    "roleArn": self.device_defender_role.role_arn,
                    "enabled": True
                }
            }
        )

        return audit_config

    def _create_violation_processor(self) -> lambda_.Function:
        """Create Lambda function to process security violations."""
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "ViolationProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add permissions for IoT operations
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "iot:ListViolationEvents",
                    "iot:DescribeSecurityProfile",
                    "iot:ListTargetsForSecurityProfile",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )

        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process IoT Device Defender security violations.
    
    This function processes SNS notifications from Device Defender
    and can implement automated remediation actions.
    """
    try:
        logger.info(f"Processing violation event: {json.dumps(event)}")
        
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record['EventSource'] == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    process_violation(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Violation processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing violation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_violation(violation_data: Dict[str, Any]) -> None:
    """Process individual violation and implement response actions."""
    logger.info(f"Processing violation: {violation_data}")
    
    # Extract violation details
    violation_type = violation_data.get('violationEventType', 'Unknown')
    thing_name = violation_data.get('thingName', 'Unknown')
    behavior_name = violation_data.get('behavior', {}).get('name', 'Unknown')
    
    logger.info(f"Violation detected - Type: {violation_type}, Thing: {thing_name}, Behavior: {behavior_name}")
    
    # Implement automated responses based on violation type
    if behavior_name == 'ExcessiveMessages':
        handle_excessive_messages(thing_name, violation_data)
    elif behavior_name == 'AuthorizationFailures':
        handle_authorization_failures(thing_name, violation_data)
    elif behavior_name == 'LargeMessageSize':
        handle_large_messages(thing_name, violation_data)
    elif behavior_name == 'UnusualConnectionAttempts':
        handle_unusual_connections(thing_name, violation_data)

def handle_excessive_messages(thing_name: str, violation_data: Dict[str, Any]) -> None:
    """Handle excessive message sending violations."""
    logger.warning(f"Device {thing_name} is sending excessive messages")
    # Implement throttling or alerting logic here

def handle_authorization_failures(thing_name: str, violation_data: Dict[str, Any]) -> None:
    """Handle authorization failure violations."""
    logger.warning(f"Device {thing_name} has excessive authorization failures")
    # Implement security response logic here

def handle_large_messages(thing_name: str, violation_data: Dict[str, Any]) -> None:
    """Handle large message size violations."""
    logger.warning(f"Device {thing_name} is sending unusually large messages")
    # Implement message size monitoring logic here

def handle_unusual_connections(thing_name: str, violation_data: Dict[str, Any]) -> None:
    """Handle unusual connection attempt violations."""
    logger.warning(f"Device {thing_name} has unusual connection patterns")
    # Implement connection monitoring logic here
'''

        violation_processor = lambda_.Function(
            self,
            "ViolationProcessor",
            function_name="iot-security-violation-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            description="Process IoT Device Defender security violations",
            environment={
                "LOG_LEVEL": "INFO"
            }
        )

        # Subscribe Lambda to SNS topic
        self.security_alerts_topic.add_subscription(
            sns_subscriptions.LambdaSubscription(violation_processor)
        )

        return violation_processor

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.security_alerts_topic.topic_arn,
            description="ARN of the SNS topic for security alerts"
        )

        CfnOutput(
            self,
            "DeviceDefenderRoleArn",
            value=self.device_defender_role.role_arn,
            description="ARN of the Device Defender service role"
        )

        CfnOutput(
            self,
            "RuleBasedSecurityProfile",
            value=self.rule_based_profile.security_profile_name,
            description="Name of the rule-based security profile"
        )

        CfnOutput(
            self,
            "MLBasedSecurityProfile",
            value=self.ml_based_profile.security_profile_name,
            description="Name of the ML-based security profile"
        )

        CfnOutput(
            self,
            "ViolationProcessorFunction",
            value=self.violation_processor.function_name,
            description="Name of the Lambda function for processing violations"
        )


# CDK Application
app = cdk.App()

IoTDeviceDefenderStack(
    app,
    "IoTDeviceDefenderStack",
    description="AWS IoT Device Defender Security Implementation",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

app.synth()