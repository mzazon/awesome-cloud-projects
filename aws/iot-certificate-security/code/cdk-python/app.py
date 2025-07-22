#!/usr/bin/env python3
"""
AWS CDK Python Application for IoT Security with Device Certificates and Policies

This CDK application implements a comprehensive IoT security framework using AWS IoT Core's 
X.509 certificate-based authentication combined with fine-grained security policies.

Features:
- X.509 certificate-based device authentication
- Fine-grained IoT security policies
- AWS IoT Device Defender security monitoring
- CloudWatch logging and alerting
- DynamoDB for security event storage
- Lambda functions for automated security processing
- Device quarantine capabilities
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iot as iot,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
    CfnOutput,
    Duration,
    RemovalPolicy
)
from constructs import Construct
from typing import Dict, List, Any
import json


class IoTSecurityStack(Stack):
    """
    CDK Stack for IoT Certificate Security with X.509 Authentication.
    
    This stack creates a complete IoT security infrastructure including:
    - Thing types and security policies
    - Device Defender security profiles
    - CloudWatch monitoring and alerting
    - Lambda functions for security event processing
    - DynamoDB table for security event storage
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create thing type for industrial sensors
        self.thing_type = self._create_thing_type()
        
        # Create IoT security policies
        self.iot_policies = self._create_iot_policies()
        
        # Create DynamoDB table for security events
        self.security_events_table = self._create_security_events_table()
        
        # Create Lambda functions for security processing
        self.security_processor = self._create_security_processor_lambda()
        self.certificate_rotation = self._create_certificate_rotation_lambda()
        self.device_quarantine = self._create_device_quarantine_lambda()
        
        # Create IoT Rules for security event processing
        self.iot_rules = self._create_iot_rules()
        
        # Create Device Defender security profile
        self.security_profile = self._create_device_defender_security_profile()
        
        # Create thing group for organizing devices
        self.thing_group = self._create_thing_group()
        
        # Create CloudWatch resources
        self.log_group = self._create_cloudwatch_log_group()
        self.dashboard = self._create_cloudwatch_dashboard()
        self.alarms = self._create_cloudwatch_alarms()
        
        # Create EventBridge rules for automation
        self.event_rules = self._create_eventbridge_rules()
        
        # Create outputs
        self._create_outputs()

    def _create_thing_type(self) -> iot.CfnThingType:
        """Create IoT Thing Type for industrial sensors."""
        return iot.CfnThingType(
            self, "IndustrialSensorThingType",
            thing_type_name="IndustrialSensor",
            thing_type_description="Industrial IoT sensors with security controls",
            thing_type_properties=iot.CfnThingType.ThingTypePropertiesProperty(
                searchable_attributes=["location", "deviceType", "firmwareVersion"]
            )
        )

    def _create_iot_policies(self) -> Dict[str, iot.CfnPolicy]:
        """Create IoT security policies with fine-grained access controls."""
        policies = {}
        
        # Restrictive sensor policy
        restrictive_policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": "iot:Connect",
                    "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
                    "Condition": {
                        "Bool": {
                            "iot:Connection.Thing.IsAttached": "true"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": "iot:Publish",
                    "Resource": [
                        "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/telemetry",
                        "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/status"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": "iot:Subscribe",
                    "Resource": [
                        "arn:aws:iot:*:*:topicfilter/sensors/${iot:Connection.Thing.ThingName}/commands",
                        "arn:aws:iot:*:*:topicfilter/sensors/${iot:Connection.Thing.ThingName}/config"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": "iot:Receive",
                    "Resource": [
                        "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/commands",
                        "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/config"
                    ]
                },
                {
                    "Effect": "Allow",
                    "Action": [
                        "iot:UpdateThingShadow",
                        "iot:GetThingShadow"
                    ],
                    "Resource": "arn:aws:iot:*:*:thing/${iot:Connection.Thing.ThingName}"
                }
            ]
        }
        
        policies["restrictive"] = iot.CfnPolicy(
            self, "RestrictiveSensorPolicy",
            policy_name="RestrictiveSensorPolicy",
            policy_document=restrictive_policy_document
        )
        
        # Time-based access policy
        time_based_policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": "iot:Connect",
                    "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
                    "Condition": {
                        "Bool": {
                            "iot:Connection.Thing.IsAttached": "true"
                        },
                        "DateGreaterThan": {
                            "aws:CurrentTime": "08:00:00Z"
                        },
                        "DateLessThan": {
                            "aws:CurrentTime": "18:00:00Z"
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": "iot:Publish",
                    "Resource": "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/telemetry",
                    "Condition": {
                        "StringEquals": {
                            "iot:Connection.Thing.ThingTypeName": "IndustrialSensor"
                        }
                    }
                }
            ]
        }
        
        policies["time_based"] = iot.CfnPolicy(
            self, "TimeBasedAccessPolicy",
            policy_name="TimeBasedAccessPolicy",
            policy_document=time_based_policy_document
        )
        
        # Location-based access policy
        location_based_policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": "iot:Connect",
                    "Resource": "arn:aws:iot:*:*:client/${iot:Connection.Thing.ThingName}",
                    "Condition": {
                        "Bool": {
                            "iot:Connection.Thing.IsAttached": "true"
                        },
                        "StringEquals": {
                            "iot:Connection.Thing.Attributes[location]": [
                                "factory-001",
                                "factory-002",
                                "factory-003"
                            ]
                        }
                    }
                },
                {
                    "Effect": "Allow",
                    "Action": "iot:Publish",
                    "Resource": "arn:aws:iot:*:*:topic/sensors/${iot:Connection.Thing.ThingName}/*",
                    "Condition": {
                        "StringLike": {
                            "iot:Connection.Thing.Attributes[location]": "factory-*"
                        }
                    }
                }
            ]
        }
        
        policies["location_based"] = iot.CfnPolicy(
            self, "LocationBasedAccessPolicy",
            policy_name="LocationBasedAccessPolicy",
            policy_document=location_based_policy_document
        )
        
        # Device quarantine policy
        quarantine_policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Deny",
                    "Action": "*",
                    "Resource": "*"
                }
            ]
        }
        
        policies["quarantine"] = iot.CfnPolicy(
            self, "DeviceQuarantinePolicy",
            policy_name="DeviceQuarantinePolicy",
            policy_document=quarantine_policy_document
        )
        
        return policies

    def _create_security_events_table(self) -> dynamodb.Table:
        """Create DynamoDB table for storing security events."""
        return dynamodb.Table(
            self, "IoTSecurityEventsTable",
            table_name="IoTSecurityEvents",
            partition_key=dynamodb.Attribute(
                name="eventId",
                type=dynamodb.AttributeType.STRING
            ),
            global_secondary_indexes=[
                dynamodb.GlobalSecondaryIndex(
                    index_name="DeviceIndex",
                    partition_key=dynamodb.Attribute(
                        name="deviceId",
                        type=dynamodb.AttributeType.STRING
                    ),
                    projection_type=dynamodb.ProjectionType.ALL
                )
            ],
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True
        )

    def _create_security_processor_lambda(self) -> lambda_.Function:
        """Create Lambda function for processing IoT security events."""
        return lambda_.Function(
            self, "SecurityProcessorFunction",
            function_name="iot-security-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    '''Process IoT security events and take appropriate actions'''
    
    # Log the security event
    logger.info(f"Security event received: {json.dumps(event)}")
    
    # Extract device information
    device_id = event.get('clientId', 'unknown')
    event_type = event.get('eventType', 'unknown')
    
    # Example security actions
    if event_type == 'Connect.AuthError':
        logger.warning(f"Authentication failure for device: {device_id}")
        # Could trigger device quarantine or alert
    
    elif event_type == 'Publish.AuthError':
        logger.warning(f"Unauthorized publish attempt from device: {device_id}")
        # Could update device policy or disable device
    
    # Store event for analysis
    dynamodb = boto3.resource('dynamodb')
    table = dynamodb.Table('IoTSecurityEvents')
    
    try:
        table.put_item(
            Item={
                'eventId': context.aws_request_id,
                'deviceId': device_id,
                'eventType': event_type,
                'timestamp': datetime.utcnow().isoformat(),
                'eventData': json.dumps(event)
            }
        )
    except Exception as e:
        logger.error(f"Failed to store security event: {str(e)}")
    
    return {
        'statusCode': 200,
        'body': json.dumps('Security event processed')
    }
            """),
            timeout=Duration.minutes(5),
            environment={
                "SECURITY_EVENTS_TABLE": self.security_events_table.table_name
            }
        )

    def _create_certificate_rotation_lambda(self) -> lambda_.Function:
        """Create Lambda function for certificate rotation monitoring."""
        return lambda_.Function(
            self, "CertificateRotationFunction",
            function_name="iot-certificate-rotation",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')

def lambda_handler(event, context):
    '''Rotate certificates for IoT devices based on expiration'''
    
    try:
        # List all certificates
        certificates = iot_client.list_certificates(pageSize=100)
        
        rotation_actions = []
        
        for cert in certificates['certificates']:
            cert_id = cert['certificateId']
            cert_arn = cert['certificateArn']
            
            # Get certificate details
            cert_details = iot_client.describe_certificate(
                certificateId=cert_id
            )
            
            # Check if certificate is expiring soon (within 30 days)
            # This is a simplified check - production should parse actual expiry
            creation_date = cert_details['certificateDescription']['creationDate']
            
            # Log certificate status
            logger.info(f"Certificate {cert_id} created on {creation_date}")
            
            # In production, implement actual certificate rotation logic
            rotation_actions.append({
                'certificateId': cert_id,
                'certificateArn': cert_arn,
                'action': 'monitor',
                'creationDate': creation_date.isoformat()
            })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Certificate rotation check completed',
                'actions': rotation_actions
            })
        }
        
    except Exception as e:
        logger.error(f"Certificate rotation failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
            """),
            timeout=Duration.minutes(5)
        )

    def _create_device_quarantine_lambda(self) -> lambda_.Function:
        """Create Lambda function for device quarantine operations."""
        return lambda_.Function(
            self, "DeviceQuarantineFunction",
            function_name="iot-device-quarantine",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iot_client = boto3.client('iot')

def lambda_handler(event, context):
    '''Quarantine suspicious IoT devices'''
    
    try:
        device_id = event['deviceId']
        reason = event.get('reason', 'Security violation')
        
        # Create quarantine policy
        quarantine_policy = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Deny",
                    "Action": "*",
                    "Resource": "*"
                }
            ]
        }
        
        # Create quarantine policy if it doesn't exist
        policy_name = "DeviceQuarantinePolicy"
        
        try:
            iot_client.create_policy(
                policyName=policy_name,
                policyDocument=json.dumps(quarantine_policy)
            )
        except iot_client.exceptions.ResourceAlreadyExistsException:
            pass
        
        # Get device certificates
        principals = iot_client.list_thing_principals(thingName=device_id)
        
        for principal in principals['principals']:
            # Detach existing policies
            attached_policies = iot_client.list_attached_policies(target=principal)
            
            for policy in attached_policies['policies']:
                iot_client.detach_policy(
                    policyName=policy['policyName'],
                    target=principal
                )
            
            # Attach quarantine policy
            iot_client.attach_policy(
                policyName=policy_name,
                target=principal
            )
        
        logger.info(f"Device {device_id} quarantined: {reason}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(f'Device {device_id} quarantined successfully')
        }
        
    except Exception as e:
        logger.error(f"Device quarantine failed: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
            """),
            timeout=Duration.minutes(5)
        )

    def _create_iot_rules(self) -> Dict[str, iot.CfnTopicRule]:
        """Create IoT Rules for processing security events."""
        rules = {}
        
        # Security event processing rule
        rules["security_events"] = iot.CfnTopicRule(
            self, "SecurityEventProcessingRule",
            rule_name="SecurityEventProcessing",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM '$aws/events/security/+/+'",
                description="Process IoT security events",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        lambda_=iot.CfnTopicRule.LambdaActionProperty(
                            function_arn=self.security_processor.function_arn
                        )
                    )
                ]
            )
        )
        
        return rules

    def _create_device_defender_security_profile(self) -> iot.CfnSecurityProfile:
        """Create Device Defender security profile for monitoring."""
        behaviors = [
            {
                "name": "ExcessiveConnections",
                "metric": "aws:num-connections",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 3},
                    "consecutiveDatapointsToAlarm": 2,
                    "consecutiveDatapointsToClear": 2
                }
            },
            {
                "name": "UnauthorizedOperations",
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
                "name": "MessageSizeAnomaly",
                "metric": "aws:message-byte-size",
                "criteria": {
                    "comparisonOperator": "greater-than",
                    "value": {"count": 1024},
                    "consecutiveDatapointsToAlarm": 3,
                    "consecutiveDatapointsToClear": 3
                }
            }
        ]
        
        return iot.CfnSecurityProfile(
            self, "IndustrialSensorSecurityProfile",
            security_profile_name="IndustrialSensorSecurity",
            security_profile_description="Security monitoring for industrial IoT sensors",
            behaviors=behaviors
        )

    def _create_thing_group(self) -> iot.CfnThingGroup:
        """Create thing group for organizing devices."""
        return iot.CfnThingGroup(
            self, "IndustrialSensorsGroup",
            thing_group_name="IndustrialSensors",
            thing_group_properties=iot.CfnThingGroup.ThingGroupPropertiesProperty(
                thing_group_description="Industrial sensor devices"
            )
        )

    def _create_cloudwatch_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for IoT security events."""
        return logs.LogGroup(
            self, "IoTSecurityLogGroup",
            log_group_name="/aws/iot/security-events",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for IoT security monitoring."""
        dashboard = cloudwatch.Dashboard(
            self, "IoTSecurityDashboard",
            dashboard_name="IoT-Security-Dashboard"
        )
        
        # Add connection metrics widget
        connection_widget = cloudwatch.GraphWidget(
            title="IoT Connection Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="Connect.Success",
                    statistic="Sum"
                ),
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="Connect.AuthError",
                    statistic="Sum"
                ),
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="Connect.ClientError",
                    statistic="Sum"
                )
            ],
            period=Duration.minutes(5)
        )
        
        # Add message metrics widget
        message_widget = cloudwatch.GraphWidget(
            title="IoT Message Metrics",
            left=[
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="PublishIn.Success",
                    statistic="Sum"
                ),
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="PublishIn.AuthError",
                    statistic="Sum"
                ),
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="Subscribe.Success",
                    statistic="Sum"
                ),
                cloudwatch.Metric(
                    namespace="AWS/IoT",
                    metric_name="Subscribe.AuthError",
                    statistic="Sum"
                )
            ],
            period=Duration.minutes(5)
        )
        
        dashboard.add_widgets(connection_widget)
        dashboard.add_widgets(message_widget)
        
        return dashboard

    def _create_cloudwatch_alarms(self) -> List[cloudwatch.Alarm]:
        """Create CloudWatch alarms for security monitoring."""
        alarms = []
        
        # Unauthorized connections alarm
        unauthorized_alarm = cloudwatch.Alarm(
            self, "UnauthorizedConnectionsAlarm",
            alarm_name="IoT-Unauthorized-Connections",
            alarm_description="Alert on unauthorized IoT connection attempts",
            metric=cloudwatch.Metric(
                namespace="AWS/IoT",
                metric_name="Connect.AuthError",
                statistic="Sum"
            ),
            threshold=5,
            evaluation_periods=2,
            period=Duration.minutes(5),
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        alarms.append(unauthorized_alarm)
        
        return alarms

    def _create_eventbridge_rules(self) -> Dict[str, events.Rule]:
        """Create EventBridge rules for automation."""
        rules = {}
        
        # Certificate rotation check rule
        rules["certificate_rotation"] = events.Rule(
            self, "CertificateRotationRule",
            rule_name="IoT-Certificate-Rotation-Check",
            description="Weekly check for certificate rotation needs",
            schedule=events.Schedule.rate(Duration.days(7)),
            targets=[
                targets.LambdaFunction(self.certificate_rotation)
            ]
        )
        
        return rules

    def _create_outputs(self) -> None:
        """Create CDK outputs for important resources."""
        CfnOutput(
            self, "ThingTypeName",
            value=self.thing_type.thing_type_name or "IndustrialSensor",
            description="Name of the IoT Thing Type"
        )
        
        CfnOutput(
            self, "ThingGroupName",
            value=self.thing_group.thing_group_name or "IndustrialSensors",
            description="Name of the IoT Thing Group"
        )
        
        CfnOutput(
            self, "SecurityEventsTableName",
            value=self.security_events_table.table_name,
            description="Name of the DynamoDB table for security events"
        )
        
        CfnOutput(
            self, "SecurityProcessorFunctionName",
            value=self.security_processor.function_name,
            description="Name of the security processor Lambda function"
        )
        
        CfnOutput(
            self, "SecurityProfileName",
            value=self.security_profile.security_profile_name or "IndustrialSensorSecurity",
            description="Name of the Device Defender security profile"
        )
        
        CfnOutput(
            self, "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group"
        )


# Grant necessary permissions
def _grant_permissions(stack: IoTSecurityStack) -> None:
    """Grant necessary IAM permissions to Lambda functions."""
    
    # Grant DynamoDB permissions to security processor
    stack.security_events_table.grant_write_data(stack.security_processor)
    
    # Grant IoT permissions to certificate rotation function
    stack.certificate_rotation.add_to_role_policy(
        iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "iot:ListCertificates",
                "iot:DescribeCertificate",
                "iot:UpdateCertificate",
                "iot:CreateKeysAndCertificate"
            ],
            resources=["*"]
        )
    )
    
    # Grant IoT permissions to device quarantine function
    stack.device_quarantine.add_to_role_policy(
        iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "iot:ListThingPrincipals",
                "iot:ListAttachedPolicies",
                "iot:DetachPolicy",
                "iot:AttachPolicy",
                "iot:CreatePolicy"
            ],
            resources=["*"]
        )
    )
    
    # Grant IoT Rules permission to invoke Lambda
    stack.security_processor.add_permission(
        "AllowIoTRuleInvoke",
        principal=iam.ServicePrincipal("iot.amazonaws.com"),
        action="lambda:InvokeFunction"
    )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Create the IoT Security stack
    iot_security_stack = IoTSecurityStack(
        app, "IoTSecurityStack",
        description="IoT Security implementation with device certificates and policies",
        env=cdk.Environment(
            account=app.node.try_get_context("account"),
            region=app.node.try_get_context("region")
        )
    )
    
    # Grant necessary permissions
    _grant_permissions(iot_security_stack)
    
    # Add tags to all resources
    cdk.Tags.of(app).add("Project", "IoTSecurity")
    cdk.Tags.of(app).add("Environment", "Production")
    cdk.Tags.of(app).add("Owner", "SecurityTeam")
    
    app.synth()


if __name__ == "__main__":
    main()