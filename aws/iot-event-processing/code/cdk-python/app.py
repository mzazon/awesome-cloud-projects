#!/usr/bin/env python3
"""
AWS CDK Python application for IoT Rules Engine Event Processing.

This application implements a comprehensive IoT Rules Engine solution for processing
sensor data from industrial IoT devices. It includes rules for temperature monitoring,
motor status tracking, security events, and data archival.

Author: AWS CDK Generator
License: MIT
"""

import os
from typing import Any, Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_iot as iot,
    aws_lambda as lambda_,
    aws_logs as logs,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
)
from constructs import Construct


class IoTRulesEngineStack(Stack):
    """
    AWS CDK Stack for IoT Rules Engine Event Processing.
    
    This stack creates:
    - DynamoDB table for telemetry data storage
    - SNS topic for alerts and notifications
    - Lambda function for custom event processing
    - IoT Rules for temperature, motor, security, and archival processing
    - IAM roles and policies for secure service integration
    - CloudWatch log group for monitoring
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.table_name = f"factory-telemetry-{self.account}-{self.region}"
        self.function_name = f"factory-event-processor-{self.account}-{self.region}"
        self.topic_name = f"factory-alerts-{self.account}-{self.region}"
        self.log_group_name = "/aws/iot/rules"

        # Create core infrastructure
        self.telemetry_table = self._create_dynamodb_table()
        self.alerts_topic = self._create_sns_topic()
        self.event_processor = self._create_lambda_function()
        self.iot_rules_role = self._create_iot_rules_role()
        self.log_group = self._create_log_group()

        # Create IoT Rules
        self._create_temperature_rule()
        self._create_motor_status_rule()
        self._create_security_event_rule()
        self._create_data_archival_rule()

        # Configure Lambda permissions
        self._configure_lambda_permissions()

        # Create stack outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing telemetry data.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self,
            "TelemetryTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="deviceId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

        # Add tags for resource management
        cdk.Tags.of(table).add("Project", "IoTRulesEngine")
        cdk.Tags.of(table).add("Environment", "Production")
        cdk.Tags.of(table).add("Service", "IoT-Core")

        return table

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for alerts and notifications.
        
        Returns:
            sns.Topic: The created SNS topic
        """
        topic = sns.Topic(
            self,
            "AlertsTopic",
            topic_name=self.topic_name,
            display_name="Factory Alerts",
            fifo=False,
        )

        # Add tags for resource management
        cdk.Tags.of(topic).add("Project", "IoTRulesEngine")
        cdk.Tags.of(topic).add("Environment", "Production")
        cdk.Tags.of(topic).add("Service", "SNS")

        return topic

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for custom event processing.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Lambda function code
        lambda_code = '''
import json
import boto3
from datetime import datetime
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process IoT events and perform custom business logic.
    
    Args:
        event: The IoT event data
        context: Lambda context object
        
    Returns:
        Dict containing processing results
    """
    try:
        # Parse the incoming IoT message
        device_id = event.get('deviceId', 'unknown')
        temperature = event.get('temperature', 0)
        motor_status = event.get('motorStatus', 'unknown')
        vibration = event.get('vibration', 0)
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        
        # Custom processing logic for temperature
        severity = 'normal'
        if temperature > 85:
            severity = 'critical'
        elif temperature > 75:
            severity = 'warning'
        
        # Custom processing logic for motor status
        motor_health = 'healthy'
        if motor_status == 'error' or vibration > 5.0:
            motor_health = 'unhealthy'
        elif vibration > 3.0:
            motor_health = 'degraded'
        
        # Log the processed event
        print(f"Processing event from {device_id}: temp={temperature}°C, "
              f"motor={motor_status}, vibration={vibration}, "
              f"severity={severity}, health={motor_health}")
        
        # Return enriched data
        return {
            'statusCode': 200,
            'body': json.dumps({
                'deviceId': device_id,
                'temperature': temperature,
                'motorStatus': motor_status,
                'vibration': vibration,
                'severity': severity,
                'motorHealth': motor_health,
                'processedAt': timestamp,
                'message': f'Event processed: temp={temperature}°C, '
                          f'motor={motor_status}, severity={severity}'
            })
        }
        
    except Exception as e:
        print(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
'''

        function = lambda_.Function(
            self,
            "EventProcessor",
            function_name=self.function_name,
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(30),
            memory_size=256,
            retry_attempts=2,
            environment={
                "DYNAMODB_TABLE": self.telemetry_table.table_name,
                "SNS_TOPIC": self.alerts_topic.topic_arn,
                "LOG_LEVEL": "INFO"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Grant permissions to access DynamoDB and SNS
        self.telemetry_table.grant_read_write_data(function)
        self.alerts_topic.grant_publish(function)

        # Add tags for resource management
        cdk.Tags.of(function).add("Project", "IoTRulesEngine")
        cdk.Tags.of(function).add("Environment", "Production")
        cdk.Tags.of(function).add("Service", "Lambda")

        return function

    def _create_iot_rules_role(self) -> iam.Role:
        """
        Create IAM role for IoT Rules Engine with appropriate permissions.
        
        Returns:
            iam.Role: The created IAM role
        """
        role = iam.Role(
            self,
            "IoTRulesRole",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            description="IAM role for IoT Rules Engine to access AWS services",
        )

        # Policy for DynamoDB access
        dynamodb_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:GetItem",
                "dynamodb:Query",
                "dynamodb:Scan"
            ],
            resources=[self.telemetry_table.table_arn]
        )

        # Policy for SNS access
        sns_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["sns:Publish"],
            resources=[self.alerts_topic.topic_arn]
        )

        # Policy for Lambda access
        lambda_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=["lambda:InvokeFunction"],
            resources=[self.event_processor.function_arn]
        )

        # Policy for CloudWatch Logs
        logs_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            resources=[f"arn:aws:logs:{self.region}:{self.account}:*"]
        )

        # Attach policies to the role
        role.add_to_policy(dynamodb_policy)
        role.add_to_policy(sns_policy)
        role.add_to_policy(lambda_policy)
        role.add_to_policy(logs_policy)

        # Add tags for resource management
        cdk.Tags.of(role).add("Project", "IoTRulesEngine")
        cdk.Tags.of(role).add("Environment", "Production")
        cdk.Tags.of(role).add("Service", "IAM")

        return role

    def _create_log_group(self) -> logs.LogGroup:
        """
        Create CloudWatch log group for IoT Rules Engine.
        
        Returns:
            logs.LogGroup: The created log group
        """
        log_group = logs.LogGroup(
            self,
            "IoTRulesLogGroup",
            log_group_name=self.log_group_name,
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Add tags for resource management
        cdk.Tags.of(log_group).add("Project", "IoTRulesEngine")
        cdk.Tags.of(log_group).add("Environment", "Production")
        cdk.Tags.of(log_group).add("Service", "CloudWatch")

        return log_group

    def _create_temperature_rule(self) -> None:
        """Create IoT Rule for temperature monitoring."""
        rule = iot.CfnTopicRule(
            self,
            "TemperatureRule",
            rule_name="TemperatureAlertRule",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT deviceId, temperature, timestamp() as timestamp "
                    "FROM 'factory/temperature' WHERE temperature > 70",
                description="Monitor temperature sensors and trigger alerts for high temperatures",
                rule_disabled=False,
                aws_iot_sql_version="2016-03-23",
                actions=[
                    # DynamoDB action
                    iot.CfnTopicRule.ActionProperty(
                        dynamo_db=iot.CfnTopicRule.DynamoDBActionProperty(
                            table_name=self.telemetry_table.table_name,
                            role_arn=self.iot_rules_role.role_arn,
                            hash_key_field="deviceId",
                            hash_key_value="${deviceId}",
                            range_key_field="timestamp",
                            range_key_value="${timestamp}",
                            payload_field="data"
                        )
                    ),
                    # SNS action
                    iot.CfnTopicRule.ActionProperty(
                        sns=iot.CfnTopicRule.SnsActionProperty(
                            topic_arn=self.alerts_topic.topic_arn,
                            role_arn=self.iot_rules_role.role_arn,
                            message_format="JSON"
                        )
                    )
                ]
            )
        )

        # Add tags for resource management
        cdk.Tags.of(rule).add("Project", "IoTRulesEngine")
        cdk.Tags.of(rule).add("Environment", "Production")
        cdk.Tags.of(rule).add("Service", "IoT-Core")

    def _create_motor_status_rule(self) -> None:
        """Create IoT Rule for motor status monitoring."""
        rule = iot.CfnTopicRule(
            self,
            "MotorStatusRule",
            rule_name="MotorStatusRule",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT deviceId, motorStatus, vibration, timestamp() as timestamp "
                    "FROM 'factory/motors' WHERE motorStatus = 'error' OR vibration > 5.0",
                description="Monitor motor controllers for errors and excessive vibration",
                rule_disabled=False,
                aws_iot_sql_version="2016-03-23",
                actions=[
                    # DynamoDB action
                    iot.CfnTopicRule.ActionProperty(
                        dynamo_db=iot.CfnTopicRule.DynamoDBActionProperty(
                            table_name=self.telemetry_table.table_name,
                            role_arn=self.iot_rules_role.role_arn,
                            hash_key_field="deviceId",
                            hash_key_value="${deviceId}",
                            range_key_field="timestamp",
                            range_key_value="${timestamp}",
                            payload_field="data"
                        )
                    ),
                    # Lambda action
                    iot.CfnTopicRule.ActionProperty(
                        lambda_=iot.CfnTopicRule.LambdaActionProperty(
                            function_arn=self.event_processor.function_arn
                        )
                    )
                ]
            )
        )

        # Add tags for resource management
        cdk.Tags.of(rule).add("Project", "IoTRulesEngine")
        cdk.Tags.of(rule).add("Environment", "Production")
        cdk.Tags.of(rule).add("Service", "IoT-Core")

    def _create_security_event_rule(self) -> None:
        """Create IoT Rule for security event processing."""
        rule = iot.CfnTopicRule(
            self,
            "SecurityEventRule",
            rule_name="SecurityEventRule",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT deviceId, eventType, severity, location, timestamp() as timestamp "
                    "FROM 'factory/security' WHERE eventType IN ('intrusion', 'unauthorized_access', 'door_breach')",
                description="Process security events and trigger immediate alerts",
                rule_disabled=False,
                aws_iot_sql_version="2016-03-23",
                actions=[
                    # SNS action (prioritized for immediate alerts)
                    iot.CfnTopicRule.ActionProperty(
                        sns=iot.CfnTopicRule.SnsActionProperty(
                            topic_arn=self.alerts_topic.topic_arn,
                            role_arn=self.iot_rules_role.role_arn,
                            message_format="JSON"
                        )
                    ),
                    # DynamoDB action for audit trail
                    iot.CfnTopicRule.ActionProperty(
                        dynamo_db=iot.CfnTopicRule.DynamoDBActionProperty(
                            table_name=self.telemetry_table.table_name,
                            role_arn=self.iot_rules_role.role_arn,
                            hash_key_field="deviceId",
                            hash_key_value="${deviceId}",
                            range_key_field="timestamp",
                            range_key_value="${timestamp}",
                            payload_field="data"
                        )
                    )
                ]
            )
        )

        # Add tags for resource management
        cdk.Tags.of(rule).add("Project", "IoTRulesEngine")
        cdk.Tags.of(rule).add("Environment", "Production")
        cdk.Tags.of(rule).add("Service", "IoT-Core")

    def _create_data_archival_rule(self) -> None:
        """Create IoT Rule for data archival."""
        rule = iot.CfnTopicRule(
            self,
            "DataArchivalRule",
            rule_name="DataArchivalRule",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM 'factory/+' WHERE timestamp() % 300 = 0",
                description="Archive all factory data every 5 minutes for historical analysis",
                rule_disabled=False,
                aws_iot_sql_version="2016-03-23",
                actions=[
                    # DynamoDB action for data archival
                    iot.CfnTopicRule.ActionProperty(
                        dynamo_db=iot.CfnTopicRule.DynamoDBActionProperty(
                            table_name=self.telemetry_table.table_name,
                            role_arn=self.iot_rules_role.role_arn,
                            hash_key_field="deviceId",
                            hash_key_value="${deviceId}",
                            range_key_field="timestamp",
                            range_key_value="${timestamp}",
                            payload_field="data"
                        )
                    )
                ]
            )
        )

        # Add tags for resource management
        cdk.Tags.of(rule).add("Project", "IoTRulesEngine")
        cdk.Tags.of(rule).add("Environment", "Production")
        cdk.Tags.of(rule).add("Service", "IoT-Core")

    def _configure_lambda_permissions(self) -> None:
        """Configure Lambda permissions for IoT Rules Engine."""
        # Grant IoT permission to invoke Lambda function
        self.event_processor.add_permission(
            "IoTRulesPermission",
            principal=iam.ServicePrincipal("iot.amazonaws.com"),
            source_arn=f"arn:aws:iot:{self.region}:{self.account}:rule/MotorStatusRule",
            action="lambda:InvokeFunction"
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        cdk.CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.telemetry_table.table_name,
            description="Name of the DynamoDB table for telemetry data"
        )

        cdk.CfnOutput(
            self,
            "SNSTopicArn",
            value=self.alerts_topic.topic_arn,
            description="ARN of the SNS topic for alerts"
        )

        cdk.CfnOutput(
            self,
            "LambdaFunctionArn",
            value=self.event_processor.function_arn,
            description="ARN of the Lambda function for event processing"
        )

        cdk.CfnOutput(
            self,
            "IoTRulesRoleArn",
            value=self.iot_rules_role.role_arn,
            description="ARN of the IAM role for IoT Rules Engine"
        )

        cdk.CfnOutput(
            self,
            "LogGroupName",
            value=self.log_group.log_group_name,
            description="Name of the CloudWatch log group"
        )


# CDK App
app = cdk.App()

# Get environment configuration
env = cdk.Environment(
    account=os.getenv('CDK_DEFAULT_ACCOUNT'),
    region=os.getenv('CDK_DEFAULT_REGION')
)

# Create the stack
IoTRulesEngineStack(
    app,
    "IoTRulesEngineStack",
    env=env,
    description="IoT Rules Engine for Event Processing - Complete serverless solution for industrial IoT data processing"
)

# Synthesize the template
app.synth()