#!/usr/bin/env python3
"""
AWS CDK Python application for IoT Device Fleet Monitoring with CloudWatch and Device Defender.

This application creates a comprehensive IoT device fleet monitoring system using:
- AWS IoT Device Defender for security monitoring and behavioral analysis
- CloudWatch for operational metrics and automated alerting
- Lambda functions for automated remediation
- SNS for notifications and event routing
- IoT Core for device management and message routing

The architecture provides real-time threat detection, automated remediation workflows,
and centralized dashboards for fleet health monitoring.
"""

import os
import json
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_iot as iot,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    aws_dynamodb as dynamodb,
    Environment,
)
from constructs import Construct


class IoTFleetMonitoringStack(Stack):
    """
    Main stack for IoT Device Fleet Monitoring with CloudWatch and Device Defender.
    
    This stack creates all necessary resources for comprehensive IoT fleet monitoring
    including security profiles, alarms, automated remediation, and dashboards.
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        fleet_name: str,
        notification_email: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Store configuration
        self.fleet_name = fleet_name
        self.notification_email = notification_email
        
        # Create foundational resources
        self._create_iam_roles()
        self._create_sns_topic()
        self._create_storage_resources()
        self._create_remediation_function()
        self._create_iot_resources()
        self._create_cloudwatch_resources()
        self._create_dashboard()
        
        # Create stack outputs
        self._create_outputs()

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Device Defender and Lambda functions."""
        
        # Device Defender role for audit and security monitoring
        self.device_defender_role = iam.Role(
            self,
            "DeviceDefenderRole",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            description="Role for IoT Device Defender audit and security monitoring",
        )
        
        # Attach Device Defender audit policy
        self.device_defender_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSIoTDeviceDefenderAudit"
            )
        )
        
        # Add permissions for CloudWatch Logs and SNS
        self.device_defender_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams",
                    "sns:Publish",
                    "cloudwatch:PutMetricData",
                ],
                resources=["*"],
            )
        )
        
        # Lambda execution role for remediation function
        self.lambda_execution_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for IoT fleet remediation Lambda function",
        )
        
        # Attach basic Lambda execution policy
        self.lambda_execution_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSLambdaBasicExecutionRole"
            )
        )
        
        # Add IoT and CloudWatch permissions
        self.lambda_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "iot:UpdateCertificate",
                    "iot:DetachThingPrincipal",
                    "iot:ListThingPrincipals",
                    "iot:DescribeThing",
                    "iot:ListThings",
                    "iot:UpdateThing",
                    "cloudwatch:PutMetricData",
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan",
                ],
                resources=["*"],
            )
        )

    def _create_sns_topic(self) -> None:
        """Create SNS topic for fleet alerts and notifications."""
        
        # Create SNS topic for security alerts
        self.sns_topic = sns.Topic(
            self,
            "FleetAlertsTopic",
            display_name=f"IoT Fleet Alerts - {self.fleet_name}",
            description="SNS topic for IoT fleet security alerts and notifications",
        )
        
        # Subscribe email endpoint
        self.sns_topic.add_subscription(
            sns_subscriptions.EmailSubscription(self.notification_email)
        )
        
        # Add topic policy to allow Device Defender to publish
        self.sns_topic.add_to_resource_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("iot.amazonaws.com")],
                actions=["SNS:Publish"],
                resources=[self.sns_topic.topic_arn],
            )
        )

    def _create_storage_resources(self) -> None:
        """Create S3 bucket and DynamoDB table for data storage."""
        
        # S3 bucket for device data and audit logs
        self.data_bucket = s3.Bucket(
            self,
            "FleetDataBucket",
            bucket_name=f"iot-fleet-data-{self.fleet_name.lower()}-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # DynamoDB table for device metadata and security events
        self.device_table = dynamodb.Table(
            self,
            "DeviceMetadataTable",
            table_name=f"iot-device-metadata-{self.fleet_name.lower()}",
            partition_key=dynamodb.Attribute(
                name="deviceId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add GSI for querying by event type
        self.device_table.add_global_secondary_index(
            index_name="EventTypeIndex",
            partition_key=dynamodb.Attribute(
                name="eventType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            ),
        )

    def _create_remediation_function(self) -> None:
        """Create Lambda function for automated security remediation."""
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import logging
from datetime import datetime, timezone
from typing import Dict, Any
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')
cloudwatch = boto3.client('cloudwatch')
dynamodb = boto3.resource('dynamodb')

# Environment variables
DEVICE_TABLE_NAME = os.environ.get('DEVICE_TABLE_NAME')
FLEET_NAME = os.environ.get('FLEET_NAME')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for processing IoT security violations.
    
    Args:
        event: Lambda event containing SNS message
        context: Lambda context object
        
    Returns:
        Response dictionary with status and message
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Parse SNS message
        if 'Records' in event:
            for record in event['Records']:
                if record.get('EventSource') == 'aws:sns':
                    message = json.loads(record['Sns']['Message'])
                    process_security_violation(message)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Successfully processed security violation')
        }
    
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_security_violation(message: Dict[str, Any]) -> None:
    """
    Process Device Defender security violation message.
    
    Args:
        message: Parsed SNS message containing violation details
    """
    
    violation_type = message.get('violationEventType', 'unknown')
    thing_name = message.get('thingName', 'unknown')
    behavior_name = message.get('behavior', {}).get('name', 'unknown')
    violation_id = message.get('violationId', str(uuid.uuid4()))
    
    logger.info(f"Processing violation: {violation_type} for {thing_name}, behavior: {behavior_name}")
    
    # Store violation in DynamoDB
    store_violation_event(thing_name, violation_type, behavior_name, violation_id, message)
    
    # Send custom metric to CloudWatch
    send_cloudwatch_metric(violation_type, behavior_name, thing_name)
    
    # Implement remediation logic based on violation type
    if violation_type == 'in-alarm':
        handle_security_alarm(thing_name, behavior_name, violation_id)
    elif violation_type == 'alarm-cleared':
        handle_alarm_cleared(thing_name, behavior_name, violation_id)

def store_violation_event(
    thing_name: str, 
    violation_type: str, 
    behavior_name: str, 
    violation_id: str,
    full_message: Dict[str, Any]
) -> None:
    """
    Store security violation event in DynamoDB.
    
    Args:
        thing_name: Name of the IoT thing
        violation_type: Type of security violation
        behavior_name: Name of the behavior that triggered the violation
        violation_id: Unique identifier for the violation
        full_message: Complete violation message
    """
    
    if not DEVICE_TABLE_NAME:
        logger.warning("DEVICE_TABLE_NAME not configured, skipping DynamoDB storage")
        return
    
    try:
        table = dynamodb.Table(DEVICE_TABLE_NAME)
        
        table.put_item(
            Item={
                'deviceId': thing_name,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'eventType': 'security_violation',
                'violationType': violation_type,
                'behaviorName': behavior_name,
                'violationId': violation_id,
                'fleetName': FLEET_NAME,
                'message': json.dumps(full_message),
                'processed': False,
                'severity': get_violation_severity(behavior_name),
                'ttl': int((datetime.now(timezone.utc).timestamp() + 2592000))  # 30 days TTL
            }
        )
        
        logger.info(f"Stored violation event for {thing_name} in DynamoDB")
    
    except Exception as e:
        logger.error(f"Error storing violation event: {str(e)}")

def send_cloudwatch_metric(violation_type: str, behavior_name: str, thing_name: str) -> None:
    """
    Send custom CloudWatch metric for security violation.
    
    Args:
        violation_type: Type of security violation
        behavior_name: Name of the behavior that triggered the violation
        thing_name: Name of the IoT thing
    """
    
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/IoT/FleetMonitoring',
            MetricData=[
                {
                    'MetricName': 'SecurityViolations',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'ViolationType',
                            'Value': violation_type
                        },
                        {
                            'Name': 'BehaviorName',
                            'Value': behavior_name
                        },
                        {
                            'Name': 'FleetName',
                            'Value': FLEET_NAME
                        }
                    ]
                }
            ]
        )
        
        logger.info(f"Sent CloudWatch metric for {violation_type} violation")
    
    except Exception as e:
        logger.error(f"Error sending CloudWatch metric: {str(e)}")

def get_violation_severity(behavior_name: str) -> str:
    """
    Determine severity level based on behavior name.
    
    Args:
        behavior_name: Name of the behavior
        
    Returns:
        Severity level (LOW, MEDIUM, HIGH, CRITICAL)
    """
    
    severity_map = {
        'AuthorizationFailures': 'HIGH',
        'MessageByteSize': 'MEDIUM',
        'MessagesReceived': 'MEDIUM',
        'MessagesSent': 'MEDIUM',
        'ConnectionAttempts': 'HIGH',
        'DeviceDisconnected': 'LOW',
        'CertificateExpiring': 'MEDIUM',
        'UnauthorizedAccess': 'CRITICAL'
    }
    
    return severity_map.get(behavior_name, 'MEDIUM')

def handle_security_alarm(thing_name: str, behavior_name: str, violation_id: str) -> None:
    """
    Handle security alarm with appropriate remediation.
    
    Args:
        thing_name: Name of the IoT thing
        behavior_name: Name of the behavior that triggered the alarm
        violation_id: Unique identifier for the violation
    """
    
    logger.info(f"Handling security alarm for {thing_name}, behavior: {behavior_name}")
    
    if behavior_name == 'AuthorizationFailures':
        # For repeated authorization failures, log and consider device isolation
        logger.warning(f"Authorization failures detected for {thing_name}")
        # In production, you might disable the certificate temporarily
        # disable_device_certificate(thing_name)
        
    elif behavior_name == 'MessageByteSize':
        # Large message size might indicate data exfiltration
        logger.warning(f"Unusual message size detected for {thing_name}")
        # Consider implementing message size limits or traffic shaping
        
    elif behavior_name in ['MessagesReceived', 'MessagesSent']:
        # Unusual message volume might indicate compromised device
        logger.warning(f"Unusual message volume detected for {thing_name}")
        # Consider implementing rate limiting or temporary throttling
        
    elif behavior_name == 'ConnectionAttempts':
        # Multiple connection attempts might indicate brute force attack
        logger.warning(f"Multiple connection attempts detected for {thing_name}")
        # Consider implementing connection rate limiting
    
    # Update device metadata with security event
    update_device_security_status(thing_name, 'ALERT', behavior_name, violation_id)

def handle_alarm_cleared(thing_name: str, behavior_name: str, violation_id: str) -> None:
    """
    Handle alarm cleared event.
    
    Args:
        thing_name: Name of the IoT thing
        behavior_name: Name of the behavior
        violation_id: Unique identifier for the violation
    """
    
    logger.info(f"Alarm cleared for {thing_name}, behavior: {behavior_name}")
    
    # Send metric indicating alarm cleared
    try:
        cloudwatch.put_metric_data(
            Namespace='AWS/IoT/FleetMonitoring',
            MetricData=[
                {
                    'MetricName': 'SecurityAlarmsCleared',
                    'Value': 1,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'BehaviorName',
                            'Value': behavior_name
                        },
                        {
                            'Name': 'FleetName',
                            'Value': FLEET_NAME
                        }
                    ]
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error sending alarm cleared metric: {str(e)}")
    
    # Update device security status
    update_device_security_status(thing_name, 'NORMAL', behavior_name, violation_id)

def update_device_security_status(
    thing_name: str, 
    status: str, 
    behavior_name: str, 
    violation_id: str
) -> None:
    """
    Update device security status in DynamoDB.
    
    Args:
        thing_name: Name of the IoT thing
        status: Security status (ALERT, NORMAL, etc.)
        behavior_name: Name of the behavior
        violation_id: Unique identifier for the violation
    """
    
    if not DEVICE_TABLE_NAME:
        return
    
    try:
        table = dynamodb.Table(DEVICE_TABLE_NAME)
        
        table.put_item(
            Item={
                'deviceId': thing_name,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'eventType': 'security_status_update',
                'securityStatus': status,
                'behaviorName': behavior_name,
                'violationId': violation_id,
                'fleetName': FLEET_NAME,
                'ttl': int((datetime.now(timezone.utc).timestamp() + 2592000))  # 30 days TTL
            }
        )
        
        logger.info(f"Updated security status for {thing_name} to {status}")
    
    except Exception as e:
        logger.error(f"Error updating device security status: {str(e)}")

def disable_device_certificate(thing_name: str) -> None:
    """
    Disable device certificate for security isolation.
    
    Args:
        thing_name: Name of the IoT thing
    """
    
    try:
        # Get device principals (certificates)
        principals = iot_client.list_thing_principals(thingName=thing_name)
        
        for principal in principals['principals']:
            # Extract certificate ID from principal ARN
            cert_id = principal.split('/')[-1]
            
            # Set certificate to INACTIVE
            iot_client.update_certificate(
                certificateId=cert_id,
                newStatus='INACTIVE'
            )
            
            logger.warning(f"Disabled certificate {cert_id} for device {thing_name}")
    
    except Exception as e:
        logger.error(f"Error disabling certificate for {thing_name}: {str(e)}")
'''
        
        # Create Lambda function
        self.remediation_function = lambda_.Function(
            self,
            "RemediationFunction",
            function_name=f"iot-fleet-remediation-{self.fleet_name.lower()}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=self.lambda_execution_role,
            environment={
                "DEVICE_TABLE_NAME": self.device_table.table_name,
                "FLEET_NAME": self.fleet_name,
                "DATA_BUCKET_NAME": self.data_bucket.bucket_name,
            },
            description="Automated remediation for IoT fleet security violations",
        )
        
        # Subscribe Lambda to SNS topic
        self.sns_topic.add_subscription(
            sns_subscriptions.LambdaSubscription(self.remediation_function)
        )
        
        # Grant Lambda permissions to access DynamoDB and S3
        self.device_table.grant_read_write_data(self.remediation_function)
        self.data_bucket.grant_read_write(self.remediation_function)

    def _create_iot_resources(self) -> None:
        """Create IoT Core resources including thing group and security profiles."""
        
        # Create thing group for fleet management
        self.thing_group = iot.CfnThingGroup(
            self,
            "FleetThingGroup",
            thing_group_name=self.fleet_name,
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description=f"IoT device fleet for monitoring - {self.fleet_name}"
            ),
        )
        
        # Create security profile with comprehensive behaviors
        self.security_profile = iot.CfnSecurityProfile(
            self,
            "FleetSecurityProfile",
            security_profile_name=f"fleet-security-profile-{self.fleet_name.lower()}",
            security_profile_description="Comprehensive security monitoring for IoT device fleet",
            behaviors=[
                iot.CfnSecurityProfile.BehaviorProperty(
                    name="AuthorizationFailures",
                    metric="aws:num-authorization-failures",
                    criteria=iot.CfnSecurityProfile.BehaviorCriteriaProperty(
                        comparison_operator="greater-than",
                        value=iot.CfnSecurityProfile.MetricValueProperty(count=5),
                        duration_seconds=300,
                        consecutive_datapoints_to_alarm=2,
                        consecutive_datapoints_to_clear=2,
                    ),
                ),
                iot.CfnSecurityProfile.BehaviorProperty(
                    name="MessageByteSize",
                    metric="aws:message-byte-size",
                    criteria=iot.CfnSecurityProfile.BehaviorCriteriaProperty(
                        comparison_operator="greater-than",
                        value=iot.CfnSecurityProfile.MetricValueProperty(count=1024),
                        consecutive_datapoints_to_alarm=3,
                        consecutive_datapoints_to_clear=1,
                    ),
                ),
                iot.CfnSecurityProfile.BehaviorProperty(
                    name="MessagesReceived",
                    metric="aws:num-messages-received",
                    criteria=iot.CfnSecurityProfile.BehaviorCriteriaProperty(
                        comparison_operator="greater-than",
                        value=iot.CfnSecurityProfile.MetricValueProperty(count=100),
                        duration_seconds=300,
                        consecutive_datapoints_to_alarm=2,
                        consecutive_datapoints_to_clear=2,
                    ),
                ),
                iot.CfnSecurityProfile.BehaviorProperty(
                    name="MessagesSent",
                    metric="aws:num-messages-sent",
                    criteria=iot.CfnSecurityProfile.BehaviorCriteriaProperty(
                        comparison_operator="greater-than",
                        value=iot.CfnSecurityProfile.MetricValueProperty(count=100),
                        duration_seconds=300,
                        consecutive_datapoints_to_alarm=2,
                        consecutive_datapoints_to_clear=2,
                    ),
                ),
                iot.CfnSecurityProfile.BehaviorProperty(
                    name="ConnectionAttempts",
                    metric="aws:num-connection-attempts",
                    criteria=iot.CfnSecurityProfile.BehaviorCriteriaProperty(
                        comparison_operator="greater-than",
                        value=iot.CfnSecurityProfile.MetricValueProperty(count=10),
                        duration_seconds=300,
                        consecutive_datapoints_to_alarm=2,
                        consecutive_datapoints_to_clear=2,
                    ),
                ),
            ],
            alert_targets={
                "SNS": iot.CfnSecurityProfile.AlertTargetProperty(
                    alert_target_arn=self.sns_topic.topic_arn,
                    role_arn=self.device_defender_role.role_arn,
                )
            },
            targets=[f"arn:aws:iot:{self.region}:{self.account}:thinggroup/{self.fleet_name}"],
        )
        
        # Security profile depends on thing group
        self.security_profile.add_depends_on(self.thing_group)
        
        # Create CloudWatch log group for IoT events
        self.iot_log_group = logs.LogGroup(
            self,
            "IoTFleetLogGroup",
            log_group_name="/aws/iot/fleet-monitoring",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Create IoT topic rules for advanced monitoring
        self.connection_monitoring_rule = iot.CfnTopicRule(
            self,
            "ConnectionMonitoringRule",
            rule_name=f"DeviceConnectionMonitoring{self.fleet_name}",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM '$aws/events/presence/connected/+' WHERE eventType = 'connected' OR eventType = 'disconnected'",
                description="Monitor device connection events",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        cloudwatch_metric=iot.CfnTopicRule.CloudwatchMetricActionProperty(
                            role_arn=self.device_defender_role.role_arn,
                            metric_namespace="AWS/IoT/FleetMonitoring",
                            metric_name="DeviceConnectionEvents",
                            metric_value="1",
                            metric_unit="Count",
                            metric_timestamp="${timestamp()}",
                        )
                    ),
                    iot.CfnTopicRule.ActionProperty(
                        cloudwatch_logs=iot.CfnTopicRule.CloudwatchLogsActionProperty(
                            role_arn=self.device_defender_role.role_arn,
                            log_group_name=self.iot_log_group.log_group_name,
                        )
                    ),
                ],
            ),
        )
        
        self.message_monitoring_rule = iot.CfnTopicRule(
            self,
            "MessageMonitoringRule",
            rule_name=f"MessageVolumeMonitoring{self.fleet_name}",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT clientId, timestamp, topic FROM 'device/+/data'",
                description="Monitor message volume from devices",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        cloudwatch_metric=iot.CfnTopicRule.CloudwatchMetricActionProperty(
                            role_arn=self.device_defender_role.role_arn,
                            metric_namespace="AWS/IoT/FleetMonitoring",
                            metric_name="MessageVolume",
                            metric_value="1",
                            metric_unit="Count",
                            metric_timestamp="${timestamp()}",
                        )
                    ),
                ],
            ),
        )

    def _create_cloudwatch_resources(self) -> None:
        """Create CloudWatch alarms for fleet monitoring."""
        
        # Alarm for high security violations
        self.security_violations_alarm = cloudwatch.Alarm(
            self,
            "SecurityViolationsAlarm",
            alarm_name=f"IoT-Fleet-High-Security-Violations-{self.fleet_name}",
            alarm_description="High number of security violations detected",
            metric=cloudwatch.Metric(
                namespace="AWS/IoT/FleetMonitoring",
                metric_name="SecurityViolations",
                dimensions_map={"FleetName": self.fleet_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        # Add SNS action to alarm
        self.security_violations_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )
        
        # Alarm for device connectivity issues
        self.connectivity_alarm = cloudwatch.Alarm(
            self,
            "ConnectivityAlarm",
            alarm_name=f"IoT-Fleet-Low-Connectivity-{self.fleet_name}",
            alarm_description="Low device connectivity detected",
            metric=cloudwatch.Metric(
                namespace="AWS/IoT",
                metric_name="ConnectedDevices",
                statistic="Average",
                period=Duration.minutes(5),
            ),
            threshold=3,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )
        
        self.connectivity_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )
        
        # Alarm for message processing errors
        self.processing_errors_alarm = cloudwatch.Alarm(
            self,
            "ProcessingErrorsAlarm",
            alarm_name=f"IoT-Fleet-Message-Processing-Errors-{self.fleet_name}",
            alarm_description="High message processing error rate",
            metric=cloudwatch.Metric(
                namespace="AWS/IoT",
                metric_name="RuleMessageProcessingErrors",
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=10,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )
        
        self.processing_errors_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.sns_topic)
        )

    def _create_dashboard(self) -> None:
        """Create CloudWatch dashboard for fleet monitoring."""
        
        # Create dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "FleetDashboard",
            dashboard_name=f"IoT-Fleet-Dashboard-{self.fleet_name}",
        )
        
        # Add IoT fleet overview widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="IoT Fleet Overview",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="ConnectedDevices",
                        statistic="Average",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="MessagesSent",
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="MessagesReceived",
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
                height=6,
            )
        )
        
        # Add security violations widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Security Violations",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/IoT/FleetMonitoring",
                        metric_name="SecurityViolations",
                        dimensions_map={"FleetName": self.fleet_name},
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/IoT/FleetMonitoring",
                        metric_name="SecurityAlarmsCleared",
                        dimensions_map={"FleetName": self.fleet_name},
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
                height=6,
            )
        )
        
        # Add message processing widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Message Processing",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="RuleMessageProcessingErrors",
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/IoT",
                        metric_name="RuleMessageProcessingSuccess",
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
                width=12,
                height=6,
            )
        )
        
        # Add security violation logs widget
        self.dashboard.add_widgets(
            cloudwatch.LogQueryWidget(
                title="Security Violation Logs",
                log_groups=[
                    logs.LogGroup.from_log_group_name(
                        self, 
                        "RemediationLogGroup", 
                        f"/aws/lambda/{self.remediation_function.function_name}"
                    )
                ],
                query_lines=[
                    "SOURCE '/aws/lambda/{}'".format(self.remediation_function.function_name),
                    "| fields @timestamp, @message",
                    "| filter @message like /violation/",
                    "| sort @timestamp desc",
                    "| limit 20",
                ],
                width=12,
                height=6,
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        cdk.CfnOutput(
            self,
            "FleetNameOutput",
            value=self.fleet_name,
            description="Name of the IoT device fleet",
        )
        
        cdk.CfnOutput(
            self,
            "ThingGroupArnOutput",
            value=self.thing_group.attr_arn,
            description="ARN of the IoT thing group",
        )
        
        cdk.CfnOutput(
            self,
            "SecurityProfileNameOutput",
            value=self.security_profile.security_profile_name,
            description="Name of the Device Defender security profile",
        )
        
        cdk.CfnOutput(
            self,
            "SNSTopicArnOutput",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for alerts",
        )
        
        cdk.CfnOutput(
            self,
            "LambdaFunctionArnOutput",
            value=self.remediation_function.function_arn,
            description="ARN of the remediation Lambda function",
        )
        
        cdk.CfnOutput(
            self,
            "DashboardUrlOutput",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
        )
        
        cdk.CfnOutput(
            self,
            "DataBucketNameOutput",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for device data",
        )
        
        cdk.CfnOutput(
            self,
            "DeviceTableNameOutput",
            value=self.device_table.table_name,
            description="Name of the DynamoDB table for device metadata",
        )


class IoTFleetMonitoringApp(cdk.App):
    """
    Main CDK application for IoT Device Fleet Monitoring.
    """
    
    def __init__(self, **kwargs) -> None:
        super().__init__(**kwargs)
        
        # Configuration parameters
        fleet_name = self.node.try_get_context("fleet_name") or "production-fleet"
        notification_email = self.node.try_get_context("notification_email") or "admin@example.com"
        
        # Environment configuration
        env = Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )
        
        # Create the main stack
        IoTFleetMonitoringStack(
            self,
            "IoTFleetMonitoringStack",
            fleet_name=fleet_name,
            notification_email=notification_email,
            env=env,
            description="IoT Device Fleet Monitoring with CloudWatch and Device Defender",
        )


# Create the app
app = IoTFleetMonitoringApp()
app.synth()