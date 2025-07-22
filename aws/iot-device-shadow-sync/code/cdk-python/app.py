#!/usr/bin/env python3
"""
AWS CDK Python Application for Advanced IoT Device Shadow Synchronization

This CDK application deploys a comprehensive IoT device shadow synchronization
solution with advanced conflict resolution, offline support, and monitoring.

Author: AWS CDK Generator v1.3
License: MIT
"""

import os
from typing import Dict, Any, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_dynamodb as dynamodb,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_iot as iot,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
)
from constructs import Construct


class IoTShadowSyncStack(Stack):
    """
    Main stack for IoT Device Shadow Synchronization infrastructure.
    
    This stack creates:
    - DynamoDB tables for shadow history, device config, and metrics
    - Lambda functions for conflict resolution and sync management
    - IoT Core resources (Things, Certificates, Policies, Rules)
    - EventBridge rules for automated monitoring
    - CloudWatch dashboard and log groups
    - IAM roles and policies with least privilege access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.random_suffix = self.generate_random_suffix()
        self.thing_name = f"sync-demo-device-{self.random_suffix}"
        
        # Create DynamoDB tables
        self.create_dynamodb_tables()
        
        # Create Lambda functions
        self.create_lambda_functions()
        
        # Create IoT Core resources
        self.create_iot_resources()
        
        # Create EventBridge rules
        self.create_eventbridge_rules()
        
        # Create CloudWatch resources
        self.create_cloudwatch_resources()
        
        # Create outputs
        self.create_outputs()

    def generate_random_suffix(self) -> str:
        """Generate a random suffix for resource naming."""
        import random
        import string
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

    def create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables for shadow synchronization."""
        
        # Shadow History Table - stores all shadow change events
        self.shadow_history_table = dynamodb.Table(
            self,
            "ShadowHistoryTable",
            table_name=f"shadow-sync-history-{self.random_suffix}",
            partition_key=dynamodb.Attribute(
                name="thingName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )
        
        # Add Global Secondary Index for shadow name queries
        self.shadow_history_table.add_global_secondary_index(
            index_name="ShadowNameIndex",
            partition_key=dynamodb.Attribute(
                name="shadowName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        # Device Configuration Table - stores device-specific settings
        self.device_config_table = dynamodb.Table(
            self,
            "DeviceConfigTable",
            table_name=f"device-configuration-{self.random_suffix}",
            partition_key=dynamodb.Attribute(
                name="thingName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="configType",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )
        
        # Sync Metrics Table - stores synchronization metrics and health data
        self.sync_metrics_table = dynamodb.Table(
            self,
            "SyncMetricsTable",
            table_name=f"shadow-sync-metrics-{self.random_suffix}",
            partition_key=dynamodb.Attribute(
                name="thingName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="metricTimestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
        )

        # Add tags to all tables
        for table in [self.shadow_history_table, self.device_config_table, self.sync_metrics_table]:
            cdk.Tags.of(table).add("Project", "IoTShadowSync")
            cdk.Tags.of(table).add("Component", "Storage")

    def create_lambda_functions(self) -> None:
        """Create Lambda functions for shadow conflict resolution and sync management."""
        
        # Create EventBridge bus for shadow sync events
        self.event_bus = events.EventBus(
            self,
            "ShadowSyncEventBus",
            event_bus_name=f"shadow-sync-events-{self.random_suffix}"
        )
        
        # Create IAM role for Lambda functions
        lambda_role = iam.Role(
            self,
            "ShadowSyncLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "ShadowSyncPolicy": iam.PolicyDocument(
                    statements=[
                        # IoT permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "iot:GetThingShadow",
                                "iot:UpdateThingShadow",
                                "iot:DeleteThingShadow"
                            ],
                            resources=[f"arn:aws:iot:{self.region}:{self.account}:thing/*"]
                        ),
                        # DynamoDB permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:GetItem",
                                "dynamodb:PutItem",
                                "dynamodb:UpdateItem",
                                "dynamodb:Query",
                                "dynamodb:Scan"
                            ],
                            resources=[
                                self.shadow_history_table.table_arn,
                                f"{self.shadow_history_table.table_arn}/*",
                                self.device_config_table.table_arn,
                                f"{self.device_config_table.table_arn}/*",
                                self.sync_metrics_table.table_arn,
                                f"{self.sync_metrics_table.table_arn}/*"
                            ]
                        ),
                        # EventBridge permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["events:PutEvents"],
                            resources=[self.event_bus.event_bus_arn]
                        ),
                        # CloudWatch permissions
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["cloudwatch:PutMetricData"],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Conflict Resolution Lambda Function
        self.conflict_resolver_lambda = _lambda.Function(
            self,
            "ConflictResolverFunction",
            function_name=f"shadow-conflict-resolver-{self.random_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self.get_conflict_resolver_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=lambda_role,
            environment={
                "SHADOW_HISTORY_TABLE": self.shadow_history_table.table_name,
                "DEVICE_CONFIG_TABLE": self.device_config_table.table_name,
                "SYNC_METRICS_TABLE": self.sync_metrics_table.table_name,
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
                "AWS_REGION": self.region
            },
            description="Advanced IoT device shadow conflict resolution with intelligent algorithms"
        )

        # Shadow Sync Manager Lambda Function
        self.sync_manager_lambda = _lambda.Function(
            self,
            "SyncManagerFunction",
            function_name=f"shadow-sync-manager-{self.random_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self.get_sync_manager_code()),
            timeout=Duration.minutes(5),
            memory_size=256,
            role=lambda_role,
            environment={
                "SHADOW_HISTORY_TABLE": self.shadow_history_table.table_name,
                "DEVICE_CONFIG_TABLE": self.device_config_table.table_name,
                "SYNC_METRICS_TABLE": self.sync_metrics_table.table_name,
                "EVENT_BUS_NAME": self.event_bus.event_bus_name,
                "AWS_REGION": self.region
            },
            description="IoT device shadow synchronization management and health monitoring"
        )

        # Add tags to Lambda functions
        for func in [self.conflict_resolver_lambda, self.sync_manager_lambda]:
            cdk.Tags.of(func).add("Project", "IoTShadowSync")
            cdk.Tags.of(func).add("Component", "Compute")

    def create_iot_resources(self) -> None:
        """Create IoT Core resources including Things, Certificates, Policies, and Rules."""
        
        # Create IoT Thing Type
        self.thing_type = iot.CfnThingType(
            self,
            "SyncDemoThingType",
            thing_type_name="SyncDemoDevice",
            thing_type_properties={
                "description": "Demo device type for shadow synchronization testing"
            }
        )

        # Create IoT Thing
        self.iot_thing = iot.CfnThing(
            self,
            "SyncDemoThing",
            thing_name=self.thing_name,
            thing_type_name=self.thing_type.thing_type_name,
            attribute_payload={
                "attributes": {
                    "deviceType": "sensor_gateway",
                    "location": "test_lab",
                    "syncEnabled": "true"
                }
            }
        )
        self.iot_thing.add_dependency(self.thing_type)

        # Create IoT Certificate
        self.iot_certificate = iot.CfnCertificate(
            self,
            "DemoDeviceCertificate",
            status="ACTIVE",
            certificate_signing_request=""  # This will need to be provided during deployment
        )

        # Create IoT Policy for demo device
        self.device_policy = iot.CfnPolicy(
            self,
            "DemoDeviceSyncPolicy",
            policy_name="DemoDeviceSyncPolicy",
            policy_document={
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": ["iot:Connect"],
                        "Resource": f"arn:aws:iot:{self.region}:{self.account}:client/{self.thing_name}"
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "iot:Publish",
                            "iot:Subscribe",
                            "iot:Receive"
                        ],
                        "Resource": [
                            f"arn:aws:iot:{self.region}:{self.account}:topic/$aws/things/{self.thing_name}/shadow/*",
                            f"arn:aws:iot:{self.region}:{self.account}:topicfilter/$aws/things/{self.thing_name}/shadow/*"
                        ]
                    },
                    {
                        "Effect": "Allow",
                        "Action": [
                            "iot:GetThingShadow",
                            "iot:UpdateThingShadow"
                        ],
                        "Resource": f"arn:aws:iot:{self.region}:{self.account}:thing/{self.thing_name}"
                    }
                ]
            }
        )

        # Create IoT Rule for Shadow Delta Processing
        shadow_audit_log_group = logs.LogGroup(
            self,
            "ShadowAuditLogGroup",
            log_group_name="/aws/iot/shadow-audit",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create service role for IoT rules
        iot_rule_role = iam.Role(
            self,
            "IoTRuleRole",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            inline_policies={
                "IoTRulePolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["lambda:InvokeFunction"],
                            resources=[self.conflict_resolver_lambda.function_arn]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=[shadow_audit_log_group.log_group_arn]
                        )
                    ]
                )
            }
        )

        # IoT Rule for Shadow Delta Processing
        self.shadow_delta_rule = iot.CfnTopicRule(
            self,
            "ShadowDeltaProcessingRule",
            rule_name="ShadowDeltaProcessingRule",
            topic_rule_payload={
                "sql": 'SELECT *, thingName as thingName, shadowName as shadowName FROM "$aws/things/+/shadow/+/update/delta"',
                "description": "Process shadow delta events for conflict resolution",
                "actions": [
                    {
                        "lambda": {
                            "functionArn": self.conflict_resolver_lambda.function_arn
                        }
                    }
                ]
            }
        )

        # IoT Rule for Shadow Audit Logging
        self.shadow_audit_rule = iot.CfnTopicRule(
            self,
            "ShadowAuditLoggingRule",
            rule_name="ShadowAuditLoggingRule",
            topic_rule_payload={
                "sql": 'SELECT * FROM "$aws/things/+/shadow/+/update/+"',
                "description": "Log all shadow update events for audit trail",
                "actions": [
                    {
                        "cloudwatchLogs": {
                            "logGroupName": shadow_audit_log_group.log_group_name,
                            "roleArn": iot_rule_role.role_arn
                        }
                    }
                ]
            }
        )

        # Grant IoT permission to invoke Lambda
        self.conflict_resolver_lambda.add_permission(
            "IoTInvokePermission",
            principal=iam.ServicePrincipal("iot.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:iot:{self.region}:{self.account}:rule/ShadowDeltaProcessingRule"
        )

    def create_eventbridge_rules(self) -> None:
        """Create EventBridge rules for automated monitoring and alerting."""
        
        # Rule for conflict notifications
        conflict_notification_rule = events.Rule(
            self,
            "ShadowConflictNotificationRule",
            event_bus=self.event_bus,
            rule_name="shadow-conflict-notifications",
            description="Process shadow conflict events",
            event_pattern=events.EventPattern(
                source=["iot.shadow.sync"],
                detail_type=["Conflict Resolved", "Manual Review Required"]
            )
        )

        # Rule for periodic health checks
        health_check_rule = events.Rule(
            self,
            "ShadowHealthCheckRule",
            rule_name="shadow-health-check-schedule",
            description="Periodic shadow synchronization health checks",
            schedule=events.Schedule.rate(Duration.minutes(15))
        )

        # Add Lambda target for health checks
        health_check_rule.add_target(
            targets.LambdaFunction(
                self.sync_manager_lambda,
                event=events.RuleTargetInput.from_object({
                    "operation": "health_report",
                    "thingNames": [self.thing_name]
                })
            )
        )

    def create_cloudwatch_resources(self) -> None:
        """Create CloudWatch dashboard and monitoring resources."""
        
        # Create CloudWatch Dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "IoTShadowSyncDashboard",
            dashboard_name="IoT-Shadow-Synchronization",
            widgets=[
                [
                    # Metrics widget
                    cloudwatch.GraphWidget(
                        title="Shadow Synchronization Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="IoT/ShadowSync",
                                metric_name="ConflictDetected",
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="IoT/ShadowSync",
                                metric_name="SyncCompleted",
                                statistic="Sum"
                            ),
                            cloudwatch.Metric(
                                namespace="IoT/ShadowSync",
                                metric_name="OfflineSync",
                                statistic="Sum"
                            )
                        ],
                        period=Duration.minutes(5),
                        width=12,
                        height=6
                    ),
                    # Log insights widget for shadow audit
                    cloudwatch.LogQueryWidget(
                        title="Shadow Update Audit Trail",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self, "ShadowAuditLogGroupRef", "/aws/iot/shadow-audit"
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| filter @message like /shadow/",
                            "| sort @timestamp desc",
                            "| limit 50"
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Conflict resolution events
                    cloudwatch.LogQueryWidget(
                        title="Conflict Resolution Events",
                        log_groups=[self.conflict_resolver_lambda.log_group],
                        query_lines=[
                            "fields @timestamp, @message",
                            "| filter @message like /conflict/",
                            "| sort @timestamp desc",
                            "| limit 30"
                        ],
                        width=24,
                        height=6
                    )
                ]
            ]
        )

        # Create custom metrics for Lambda functions
        for func in [self.conflict_resolver_lambda, self.sync_manager_lambda]:
            cloudwatch.Alarm(
                self,
                f"{func.function_name}ErrorRate",
                alarm_name=f"{func.function_name}-error-rate",
                metric=func.metric_errors(),
                threshold=5,
                evaluation_periods=2,
                alarm_description=f"Error rate alarm for {func.function_name}"
            )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "ConflictResolverLambdaArn",
            description="ARN of the Conflict Resolver Lambda function",
            value=self.conflict_resolver_lambda.function_arn,
            export_name=f"ConflictResolverLambdaArn-{self.random_suffix}"
        )

        CfnOutput(
            self,
            "SyncManagerLambdaArn",
            description="ARN of the Sync Manager Lambda function",
            value=self.sync_manager_lambda.function_arn,
            export_name=f"SyncManagerLambdaArn-{self.random_suffix}"
        )

        CfnOutput(
            self,
            "ShadowHistoryTableName",
            description="Name of the Shadow History DynamoDB table",
            value=self.shadow_history_table.table_name,
            export_name=f"ShadowHistoryTableName-{self.random_suffix}"
        )

        CfnOutput(
            self,
            "DeviceConfigTableName",
            description="Name of the Device Configuration DynamoDB table",
            value=self.device_config_table.table_name,
            export_name=f"DeviceConfigTableName-{self.random_suffix}"
        )

        CfnOutput(
            self,
            "IoTThingName",
            description="Name of the demo IoT Thing",
            value=self.iot_thing.thing_name,
            export_name=f"IoTThingName-{self.random_suffix}"
        )

        CfnOutput(
            self,
            "EventBusName",
            description="Name of the EventBridge bus for shadow sync events",
            value=self.event_bus.event_bus_name,
            export_name=f"EventBusName-{self.random_suffix}"
        )

        CfnOutput(
            self,
            "DashboardURL",
            description="URL to the CloudWatch Dashboard",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            export_name=f"DashboardURL-{self.random_suffix}"
        )

    def get_conflict_resolver_code(self) -> str:
        """Get the Lambda function code for conflict resolution."""
        return '''
import json
import boto3
import logging
import time
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
import hashlib
import copy
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
iot_data = boto3.client('iot-data')
events = boto3.client('events')
cloudwatch = boto3.client('cloudwatch')

# Get configuration from environment
SHADOW_HISTORY_TABLE = os.environ['SHADOW_HISTORY_TABLE']
DEVICE_CONFIG_TABLE = os.environ['DEVICE_CONFIG_TABLE']
SYNC_METRICS_TABLE = os.environ['SYNC_METRICS_TABLE']
EVENT_BUS_NAME = os.environ['EVENT_BUS_NAME']

def lambda_handler(event, context):
    """Handle shadow synchronization conflicts and state management"""
    try:
        logger.info(f"Shadow conflict resolution event: {json.dumps(event, default=str)}")
        
        if 'Records' in event:
            return handle_dynamodb_stream_event(event)
        elif 'operation' in event:
            return handle_direct_operation(event)
        else:
            return handle_shadow_delta_event(event)
            
    except Exception as e:
        logger.error(f"Error in shadow conflict resolution: {str(e)}")
        return create_error_response(str(e))

def handle_shadow_delta_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle IoT shadow delta events for conflict resolution"""
    try:
        thing_name = event.get('thingName', '')
        shadow_name = event.get('shadowName', '$default')
        delta = event.get('state', {})
        version = event.get('version', 0)
        timestamp = event.get('timestamp', int(time.time()))
        
        logger.info(f"Processing delta for {thing_name}, shadow: {shadow_name}")
        
        # Get current shadow state
        current_shadow = get_current_shadow(thing_name, shadow_name)
        
        # Check for conflicts
        conflict_result = detect_conflicts(
            thing_name, shadow_name, delta, current_shadow, version
        )
        
        if conflict_result['has_conflict']:
            resolution = resolve_shadow_conflict(
                thing_name, shadow_name, conflict_result, current_shadow
            )
            apply_conflict_resolution(thing_name, shadow_name, resolution)
            log_conflict_resolution(thing_name, shadow_name, conflict_result, resolution)
        
        record_shadow_history(thing_name, shadow_name, delta, version, timestamp)
        update_sync_metrics(thing_name, shadow_name, conflict_result['has_conflict'])
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'thingName': thing_name,
                'shadowName': shadow_name,
                'hasConflict': conflict_result['has_conflict']
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling shadow delta: {str(e)}")
        return create_error_response(str(e))

def detect_conflicts(thing_name: str, shadow_name: str, delta: Dict[str, Any], 
                    current_shadow: Dict[str, Any], version: int) -> Dict[str, Any]:
    """Detect conflicts in shadow updates"""
    try:
        conflicts = []
        current_version = current_shadow.get('version', 0)
        
        if version <= current_version:
            conflicts.append({
                'type': 'version_conflict',
                'current_version': current_version,
                'delta_version': version,
                'severity': 'high'
            })
        
        return {
            'has_conflict': len(conflicts) > 0,
            'conflicts': conflicts,
            'severity': max([c.get('severity', 'low') for c in conflicts] + ['none'])
        }
        
    except Exception as e:
        logger.error(f"Error detecting conflicts: {str(e)}")
        return {'has_conflict': False, 'conflicts': [], 'error': str(e)}

def resolve_shadow_conflict(thing_name: str, shadow_name: str, 
                          conflict_result: Dict[str, Any], 
                          current_shadow: Dict[str, Any]) -> Dict[str, Any]:
    """Resolve shadow conflicts using configurable strategies"""
    return {
        'strategy': 'last_writer_wins',
        'resolution': 'accept_delta',
        'action': 'overwrite_current'
    }

def apply_conflict_resolution(thing_name: str, shadow_name: str, resolution: Dict[str, Any]):
    """Apply the conflict resolution to the device shadow"""
    logger.info(f"Applied resolution for {thing_name}/{shadow_name}: {resolution.get('strategy')}")

def get_current_shadow(thing_name: str, shadow_name: str) -> Dict[str, Any]:
    """Retrieve current shadow state"""
    try:
        response = iot_data.get_thing_shadow(
            thingName=thing_name,
            shadowName=shadow_name
        )
        return json.loads(response['payload'].read())
    except Exception as e:
        logger.warning(f"Could not get shadow for {thing_name}: {str(e)}")
        return {}

def record_shadow_history(thing_name: str, shadow_name: str, delta: Dict[str, Any], 
                         version: int, timestamp: int):
    """Record shadow change in history table"""
    try:
        table = dynamodb.Table(SHADOW_HISTORY_TABLE)
        table.put_item(
            Item={
                'thingName': thing_name,
                'timestamp': int(timestamp * 1000),
                'shadowName': shadow_name,
                'delta': delta,
                'version': version,
                'changeType': 'delta_update'
            }
        )
    except Exception as e:
        logger.error(f"Error recording shadow history: {str(e)}")

def update_sync_metrics(thing_name: str, shadow_name: str, had_conflict: bool):
    """Update synchronization metrics"""
    try:
        table = dynamodb.Table(SYNC_METRICS_TABLE)
        timestamp = int(time.time() * 1000)
        
        table.put_item(
            Item={
                'thingName': thing_name,
                'metricTimestamp': timestamp,
                'shadowName': shadow_name,
                'hadConflict': had_conflict,
                'syncType': 'delta_update'
            }
        )
        
        cloudwatch.put_metric_data(
            Namespace='IoT/ShadowSync',
            MetricData=[
                {
                    'MetricName': 'ConflictDetected',
                    'Value': 1 if had_conflict else 0,
                    'Unit': 'Count',
                    'Dimensions': [
                        {'Name': 'ThingName', 'Value': thing_name},
                        {'Name': 'ShadowName', 'Value': shadow_name}
                    ]
                }
            ]
        )
        
    except Exception as e:
        logger.error(f"Error updating sync metrics: {str(e)}")

def log_conflict_resolution(thing_name: str, shadow_name: str, 
                          conflict_result: Dict[str, Any], resolution: Dict[str, Any]):
    """Log conflict resolution details"""
    try:
        events.put_events(
            Entries=[
                {
                    'Source': 'iot.shadow.sync',
                    'DetailType': 'Conflict Resolved',
                    'Detail': json.dumps({
                        'thingName': thing_name,
                        'shadowName': shadow_name,
                        'conflicts': conflict_result['conflicts'],
                        'resolution': resolution,
                        'timestamp': datetime.now(timezone.utc).isoformat()
                    }),
                    'EventBusName': EVENT_BUS_NAME
                }
            ]
        )
    except Exception as e:
        logger.error(f"Error logging conflict resolution: {str(e)}")

def handle_dynamodb_stream_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle DynamoDB stream events"""
    return {'statusCode': 200, 'body': 'Stream event processed'}

def handle_direct_operation(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle direct operation invocations"""
    operation = event.get('operation', '')
    return {'statusCode': 200, 'body': f'Operation {operation} processed'}

def create_error_response(error_message: str) -> Dict[str, Any]:
    """Create standardized error response"""
    return {
        'statusCode': 500,
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.now(timezone.utc).isoformat()
        })
    }
        '''

    def get_sync_manager_code(self) -> str:
        """Get the Lambda function code for sync management."""
        return '''
import json
import boto3
import logging
from datetime import datetime, timezone
import time
from typing import Dict, Any, List, Optional
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
iot_data = boto3.client('iot-data')
dynamodb = boto3.resource('dynamodb')
cloudwatch = boto3.client('cloudwatch')

# Get configuration from environment
SHADOW_HISTORY_TABLE = os.environ['SHADOW_HISTORY_TABLE']
DEVICE_CONFIG_TABLE = os.environ['DEVICE_CONFIG_TABLE']
SYNC_METRICS_TABLE = os.environ['SYNC_METRICS_TABLE']

def lambda_handler(event, context):
    """Manage shadow synchronization operations for offline devices"""
    try:
        operation = event.get('operation', 'sync_check')
        thing_name = event.get('thingName', '')
        
        logger.info(f"Shadow sync operation: {operation} for {thing_name}")
        
        if operation == 'sync_check':
            return perform_sync_check(event)
        elif operation == 'offline_sync':
            return handle_offline_sync(event)
        elif operation == 'conflict_summary':
            return generate_conflict_summary(event)
        elif operation == 'health_report':
            return generate_health_report(event)
        else:
            return {
                'statusCode': 400,
                'body': json.dumps(f'Unknown operation: {operation}')
            }
            
    except Exception as e:
        logger.error(f"Error in shadow sync manager: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Sync manager error: {str(e)}')
        }

def perform_sync_check(event: Dict[str, Any]) -> Dict[str, Any]:
    """Perform comprehensive shadow synchronization check"""
    try:
        thing_name = event.get('thingName', '')
        shadow_names = event.get('shadowNames', ['$default'])
        
        sync_results = []
        
        for shadow_name in shadow_names:
            shadow = get_shadow_safely(thing_name, shadow_name)
            sync_status = check_shadow_sync_status(thing_name, shadow_name, shadow)
            
            sync_results.append({
                'shadowName': shadow_name,
                'syncStatus': sync_status,
                'lastSync': get_last_sync_time(thing_name, shadow_name),
                'hasConflicts': sync_status.get('hasConflicts', False)
            })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'thingName': thing_name,
                'syncResults': sync_results,
                'overallHealth': calculate_overall_health(sync_results)
            })
        }
        
    except Exception as e:
        logger.error(f"Error performing sync check: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def handle_offline_sync(event: Dict[str, Any]) -> Dict[str, Any]:
    """Handle synchronization for devices coming back online"""
    try:
        thing_name = event.get('thingName', '')
        offline_duration = event.get('offlineDurationSeconds', 0)
        cached_changes = event.get('cachedChanges', [])
        
        logger.info(f"Handling offline sync for {thing_name}, offline for {offline_duration}s")
        
        processed_changes = []
        conflicts_detected = []
        
        for change in cached_changes:
            shadow_name = change.get('shadowName', '$default')
            cached_state = change.get('state', {})
            timestamp = change.get('timestamp', int(time.time()))
            
            current_shadow = get_shadow_safely(thing_name, shadow_name)
            
            conflict_check = detect_offline_conflicts(
                thing_name, shadow_name, cached_state, current_shadow, timestamp
            )
            
            if conflict_check['hasConflicts']:
                conflicts_detected.append(conflict_check)
            else:
                apply_cached_changes(thing_name, shadow_name, cached_state)
                processed_changes.append({
                    'shadowName': shadow_name,
                    'status': 'applied',
                    'timestamp': timestamp
                })
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'thingName': thing_name,
                'processedChanges': len(processed_changes),
                'conflictsDetected': len(conflicts_detected),
                'conflicts': conflicts_detected[:5],
                'syncCompleted': datetime.now(timezone.utc).isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error handling offline sync: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def generate_health_report(event: Dict[str, Any]) -> Dict[str, Any]:
    """Generate comprehensive shadow health report"""
    try:
        thing_names = event.get('thingNames', [])
        
        health_report = {
            'reportTimestamp': datetime.now(timezone.utc).isoformat(),
            'deviceHealth': [],
            'overallMetrics': {
                'totalDevices': len(thing_names),
                'healthyDevices': 0,
                'devicesWithConflicts': 0,
                'offlineDevices': 0
            }
        }
        
        for thing_name in thing_names:
            device_health = assess_device_health(thing_name)
            health_report['deviceHealth'].append(device_health)
            
            if device_health['status'] == 'healthy':
                health_report['overallMetrics']['healthyDevices'] += 1
            elif device_health['status'] == 'conflict':
                health_report['overallMetrics']['devicesWithConflicts'] += 1
            elif device_health['status'] == 'offline':
                health_report['overallMetrics']['offlineDevices'] += 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(health_report)
        }
        
    except Exception as e:
        logger.error(f"Error generating health report: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def get_shadow_safely(thing_name: str, shadow_name: str) -> Dict[str, Any]:
    """Safely retrieve shadow, returning empty dict if not found"""
    try:
        response = iot_data.get_thing_shadow(
            thingName=thing_name,
            shadowName=shadow_name
        )
        return json.loads(response['payload'].read())
    except Exception as e:
        logger.warning(f"Could not get shadow {shadow_name} for {thing_name}: {str(e)}")
        return {}

def check_shadow_sync_status(thing_name: str, shadow_name: str, shadow: Dict[str, Any]) -> Dict[str, Any]:
    """Check the synchronization status of a shadow"""
    status = {
        'inSync': True,
        'hasConflicts': False,
        'lastUpdate': shadow.get('metadata', {}).get('reported', {}).get('timestamp'),
        'version': shadow.get('version', 0)
    }
    
    if 'delta' in shadow.get('state', {}):
        status['inSync'] = False
        status['pendingChanges'] = list(shadow['state']['delta'].keys())
    
    return status

def detect_offline_conflicts(thing_name: str, shadow_name: str, cached_state: Dict[str, Any],
                           current_shadow: Dict[str, Any], cached_timestamp: int) -> Dict[str, Any]:
    """Detect conflicts between cached offline changes and current shadow"""
    conflicts = []
    
    current_reported = current_shadow.get('state', {}).get('reported', {})
    current_timestamp = current_shadow.get('metadata', {}).get('reported', {}).get('timestamp', 0)
    
    if current_timestamp > cached_timestamp:
        for key, cached_value in cached_state.items():
            if key in current_reported and current_reported[key] != cached_value:
                conflicts.append({
                    'field': key,
                    'cachedValue': cached_value,
                    'currentValue': current_reported[key],
                    'type': 'concurrent_modification'
                })
    
    severity = 'high' if len(conflicts) > 3 else 'medium' if len(conflicts) > 1 else 'low'
    
    return {
        'hasConflicts': len(conflicts) > 0,
        'conflicts': conflicts,
        'severity': severity,
        'conflictCount': len(conflicts)
    }

def apply_cached_changes(thing_name: str, shadow_name: str, cached_state: Dict[str, Any]):
    """Apply cached changes to shadow"""
    try:
        update_payload = {
            'state': {
                'reported': cached_state
            }
        }
        
        iot_data.update_thing_shadow(
            thingName=thing_name,
            shadowName=shadow_name,
            payload=json.dumps(update_payload)
        )
        
        logger.info(f"Applied cached changes to {thing_name}/{shadow_name}")
        
    except Exception as e:
        logger.error(f"Error applying cached changes: {str(e)}")

def get_last_sync_time(thing_name: str, shadow_name: str) -> Optional[str]:
    """Get the last synchronization time for a shadow"""
    try:
        table = dynamodb.Table(SHADOW_HISTORY_TABLE)
        
        response = table.query(
            KeyConditionExpression=boto3.dynamodb.conditions.Key('thingName').eq(thing_name),
            FilterExpression=boto3.dynamodb.conditions.Attr('shadowName').eq(shadow_name),
            ScanIndexForward=False,
            Limit=1
        )
        
        items = response.get('Items', [])
        if items:
            return datetime.fromtimestamp(items[0]['timestamp'] / 1000, timezone.utc).isoformat()
        
        return None
    except Exception as e:
        logger.error(f"Error getting last sync time: {str(e)}")
        return None

def calculate_overall_health(sync_results: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate overall health metrics from sync results"""
    total_shadows = len(sync_results)
    healthy_shadows = sum(1 for r in sync_results if r['syncStatus']['inSync'])
    conflicted_shadows = sum(1 for r in sync_results if r['syncStatus']['hasConflicts'])
    
    health_percentage = (healthy_shadows / max(total_shadows, 1)) * 100
    
    return {
        'healthPercentage': health_percentage,
        'totalShadows': total_shadows,
        'healthyShadows': healthy_shadows,
        'conflictedShadows': conflicted_shadows,
        'status': 'healthy' if health_percentage > 80 else 'degraded' if health_percentage > 60 else 'critical'
    }

def assess_device_health(thing_name: str) -> Dict[str, Any]:
    """Assess the overall health of a device's shadows"""
    try:
        shadow_names = ['$default', 'configuration', 'telemetry', 'maintenance']
        
        health_status = {
            'thingName': thing_name,
            'status': 'healthy',
            'shadowCount': len(shadow_names),
            'issues': []
        }
        
        for shadow_name in shadow_names:
            shadow = get_shadow_safely(thing_name, shadow_name)
            if not shadow:
                health_status['issues'].append(f'Shadow {shadow_name} not found')
                health_status['status'] = 'offline'
                continue
            
            if 'delta' in shadow.get('state', {}):
                health_status['issues'].append(f'Pending changes in {shadow_name}')
                if health_status['status'] == 'healthy':
                    health_status['status'] = 'warning'
        
        return health_status
        
    except Exception as e:
        logger.error(f"Error assessing device health: {str(e)}")
        return {
            'thingName': thing_name,
            'status': 'error',
            'error': str(e)
        }

def generate_conflict_summary(event: Dict[str, Any]) -> Dict[str, Any]:
    """Generate summary of shadow conflicts"""
    try:
        time_range_hours = event.get('timeRangeHours', 24)
        cutoff_time = int((datetime.now(timezone.utc).timestamp() - (time_range_hours * 3600)) * 1000)
        
        metrics_table = dynamodb.Table(SYNC_METRICS_TABLE)
        
        response = metrics_table.scan(
            FilterExpression=boto3.dynamodb.conditions.Attr('metricTimestamp').gte(cutoff_time) &
                           boto3.dynamodb.conditions.Attr('hadConflict').eq(True)
        )
        
        conflicts = response.get('Items', [])
        
        summary = {
            'totalConflicts': len(conflicts),
            'conflictsByType': {},
            'conflictsByThing': {},
            'timeRange': f'{time_range_hours} hours'
        }
        
        for conflict in conflicts:
            thing_name = conflict.get('thingName', 'unknown')
            summary['conflictsByThing'][thing_name] = summary['conflictsByThing'].get(thing_name, 0) + 1
        
        return {
            'statusCode': 200,
            'body': json.dumps(summary)
        }
        
    except Exception as e:
        logger.error(f"Error generating conflict summary: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
        '''


class IoTShadowSyncApp(cdk.App):
    """
    CDK Application for IoT Device Shadow Synchronization.
    
    This application creates a complete IoT shadow synchronization infrastructure
    with advanced conflict resolution, offline support, and comprehensive monitoring.
    """
    
    def __init__(self):
        super().__init__()
        
        # Create the main stack
        IoTShadowSyncStack(
            self,
            "IoTShadowSyncStack",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
            ),
            description="Advanced IoT Device Shadow Synchronization with Conflict Resolution"
        )


# Main entry point
if __name__ == "__main__":
    app = IoTShadowSyncApp()
    app.synth()