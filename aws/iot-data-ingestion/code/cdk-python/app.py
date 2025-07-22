#!/usr/bin/env python3
"""
AWS CDK Application for IoT Data Ingestion Pipeline

This CDK application deploys a complete IoT data ingestion pipeline using:
- AWS IoT Core for device connectivity and MQTT message routing
- AWS Lambda for real-time data processing and business logic
- Amazon DynamoDB for scalable data storage
- Amazon SNS for alert notifications
- AWS IAM for security and access control

The architecture supports secure device authentication, real-time message processing,
and automatic scaling based on IoT device message volume.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iot as iot,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_sns as sns,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class IoTDataIngestionStack(Stack):
    """
    AWS CDK Stack for IoT Data Ingestion Pipeline
    
    This stack creates a comprehensive IoT data ingestion solution that includes:
    - IoT Thing registration and certificate management
    - DynamoDB table for sensor data storage
    - Lambda function for real-time data processing
    - SNS topic for alert notifications
    - IoT Rules Engine configuration for message routing
    - CloudWatch integration for monitoring and metrics
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create DynamoDB table for sensor data storage
        self.sensor_data_table = self._create_dynamodb_table(unique_suffix)
        
        # Create SNS topic for alert notifications
        self.alert_topic = self._create_sns_topic(unique_suffix)
        
        # Create Lambda function for data processing
        self.processor_function = self._create_lambda_function(unique_suffix)
        
        # Create IoT Thing and security policy
        self.iot_thing, self.iot_policy = self._create_iot_resources(unique_suffix)
        
        # Create IoT Rules Engine rule
        self.iot_rule = self._create_iot_rule(unique_suffix)
        
        # Create CloudWatch Log Group for IoT logs
        self.iot_log_group = self._create_log_group(unique_suffix)
        
        # Output important values
        self._create_outputs()

    def _create_dynamodb_table(self, suffix: str) -> dynamodb.Table:
        """
        Create DynamoDB table for storing IoT sensor data.
        
        The table uses a composite primary key (deviceId + timestamp) for efficient
        querying and optimal data distribution across partitions. Pay-per-request
        billing ensures cost optimization for variable IoT workloads.
        """
        table = dynamodb.Table(
            self, "SensorDataTable",
            table_name=f"SensorData-{suffix}",
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
        cdk.Tags.of(table).add("Purpose", "IoT-Data-Storage")
        cdk.Tags.of(table).add("Environment", "Development")
        
        return table

    def _create_sns_topic(self, suffix: str) -> sns.Topic:
        """
        Create SNS topic for IoT alert notifications.
        
        This topic receives notifications when sensor readings exceed thresholds
        or when anomalies are detected in the data processing pipeline.
        """
        topic = sns.Topic(
            self, "IoTAlertTopic",
            topic_name=f"IoTAlerts-{suffix}",
            display_name="IoT Sensor Alerts",
            fifo=False,
        )
        
        # Add tags for resource management
        cdk.Tags.of(topic).add("Purpose", "IoT-Alerts")
        cdk.Tags.of(topic).add("Environment", "Development")
        
        return topic

    def _create_lambda_function(self, suffix: str) -> lambda_.Function:
        """
        Create Lambda function for real-time IoT data processing.
        
        The function processes incoming IoT messages, validates data, stores to DynamoDB,
        publishes CloudWatch metrics, and sends alerts when thresholds are exceeded.
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self, "IoTProcessorRole",
            role_name=f"IoTProcessorRole-{suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )
        
        # Add inline policy for DynamoDB, SNS, and CloudWatch access
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                ],
                resources=[self.sensor_data_table.table_arn],
            )
        )
        
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sns:Publish"],
                resources=[self.alert_topic.topic_arn],
            )
        )
        
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["cloudwatch:PutMetricData"],
                resources=["*"],
            )
        )
        
        # Create Lambda function
        function = lambda_.Function(
            self, "IoTProcessorFunction",
            function_name=f"iot-processor-{suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="lambda_function.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "DYNAMODB_TABLE": self.sensor_data_table.table_name,
                "SNS_TOPIC_ARN": self.alert_topic.topic_arn,
                "TEMPERATURE_THRESHOLD": "30.0",
                "HUMIDITY_THRESHOLD": "80.0",
            },
            description="Processes IoT sensor data and triggers alerts",
        )
        
        # Create CloudWatch Log Group with retention
        logs.LogGroup(
            self, "ProcessorFunctionLogGroup",
            log_group_name=f"/aws/lambda/{function.function_name}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        # Add tags for resource management
        cdk.Tags.of(function).add("Purpose", "IoT-Data-Processing")
        cdk.Tags.of(function).add("Environment", "Development")
        
        return function

    def _create_iot_resources(self, suffix: str) -> tuple[iot.CfnThing, iot.CfnPolicy]:
        """
        Create IoT Thing and security policy for device authentication.
        
        The IoT Thing represents a physical device in the AWS IoT registry,
        while the policy defines the permissions for MQTT operations.
        """
        # Create IoT Thing Type for device classification
        thing_type = iot.CfnThingType(
            self, "SensorDeviceType",
            thing_type_name=f"SensorDevice-{suffix}",
            thing_type_description="Temperature and humidity sensor devices",
            thing_type_properties=iot.CfnThingType.ThingTypePropertiesProperty(
                description="IoT sensors for environmental monitoring",
                searchable_attributes=["deviceType", "location", "firmware"],
            ),
        )
        
        # Create IoT Thing
        thing = iot.CfnThing(
            self, "SensorThing",
            thing_name=f"sensor-device-{suffix}",
            thing_type_name=thing_type.thing_type_name,
            attribute_payload=iot.CfnThing.AttributePayloadProperty(
                attributes={
                    "deviceType": "environmental-sensor",
                    "location": "facility-1",
                    "firmware": "1.0.0",
                }
            ),
        )
        
        # Create IoT Policy for device permissions
        policy_document = {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Effect": "Allow",
                    "Action": ["iot:Connect"],
                    "Resource": f"arn:aws:iot:{self.region}:{self.account}:client/${{iot:Connection.Thing.ThingName}}",
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Publish"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topic/topic/sensor/data",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/topic/sensor/status",
                    ],
                },
                {
                    "Effect": "Allow",
                    "Action": ["iot:Subscribe", "iot:Receive"],
                    "Resource": [
                        f"arn:aws:iot:{self.region}:{self.account}:topicfilter/topic/sensor/commands",
                        f"arn:aws:iot:{self.region}:{self.account}:topic/topic/sensor/commands",
                    ],
                },
            ],
        }
        
        policy = iot.CfnPolicy(
            self, "SensorPolicy",
            policy_name=f"SensorPolicy-{suffix}",
            policy_document=policy_document,
        )
        
        # Add dependencies
        thing.add_dependency(thing_type)
        
        return thing, policy

    def _create_iot_rule(self, suffix: str) -> iot.CfnTopicRule:
        """
        Create IoT Rules Engine rule for message routing.
        
        The rule filters incoming MQTT messages and routes them to the Lambda function
        for processing. It uses SQL-like syntax to query message content and metadata.
        """
        # Grant IoT permission to invoke Lambda function
        self.processor_function.add_permission(
            "IoTInvokePermission",
            principal=iam.ServicePrincipal("iot.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:iot:{self.region}:{self.account}:rule/ProcessSensorData-{suffix}",
        )
        
        # Create IoT Rule
        rule = iot.CfnTopicRule(
            self, "ProcessSensorDataRule",
            rule_name=f"ProcessSensorData-{suffix}",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT *, topic() as topic, timestamp() as aws_timestamp FROM 'topic/sensor/data'",
                description="Route sensor data to Lambda for real-time processing",
                rule_disabled=False,
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        lambda_=iot.CfnTopicRule.LambdaActionProperty(
                            function_arn=self.processor_function.function_arn
                        )
                    )
                ],
                error_action=iot.CfnTopicRule.ActionProperty(
                    cloudwatch_logs=iot.CfnTopicRule.CloudwatchLogsActionProperty(
                        log_group_name=f"/aws/iot/rules/ProcessSensorData-{suffix}",
                        role_arn=self._create_iot_rule_role(suffix).role_arn,
                    )
                ),
                aws_iot_sql_version="2016-03-23",
            ),
        )
        
        return rule

    def _create_iot_rule_role(self, suffix: str) -> iam.Role:
        """Create IAM role for IoT Rules Engine CloudWatch logging."""
        role = iam.Role(
            self, "IoTRuleRole",
            role_name=f"IoTRuleRole-{suffix}",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
        )
        
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/iot/rules/*"
                ],
            )
        )
        
        return role

    def _create_log_group(self, suffix: str) -> logs.LogGroup:
        """Create CloudWatch Log Group for IoT Rules Engine."""
        log_group = logs.LogGroup(
            self, "IoTRuleLogGroup",
            log_group_name=f"/aws/iot/rules/ProcessSensorData-{suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        return log_group

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code for IoT data processing."""
        return '''
import json
import boto3
import logging
from datetime import datetime
import os
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Process IoT sensor data and perform real-time analytics.
    
    This function:
    1. Validates incoming IoT message format
    2. Stores data in DynamoDB for historical analysis
    3. Publishes custom metrics to CloudWatch
    4. Triggers alerts for threshold violations
    5. Implements error handling and logging
    """
    try:
        logger.info(f"Processing IoT event: {json.dumps(event)}")
        
        # Extract device data from IoT message
        device_id = event.get('deviceId', 'unknown')
        timestamp = event.get('timestamp', int(datetime.now().timestamp()))
        temperature = float(event.get('temperature', 0))
        humidity = float(event.get('humidity', 0))
        location = event.get('location', 'unknown')
        
        # Validate data ranges
        if not (0 <= temperature <= 100):
            logger.warning(f"Temperature out of range: {temperature}")
        if not (0 <= humidity <= 100):
            logger.warning(f"Humidity out of range: {humidity}")
        
        logger.info(f"Processing data from device: {device_id}")
        
        # Store data in DynamoDB
        table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
        table.put_item(
            Item={
                'deviceId': device_id,
                'timestamp': timestamp,
                'temperature': temperature,
                'humidity': humidity,
                'location': location,
                'processed_at': int(datetime.now().timestamp()),
                'ttl': int(datetime.now().timestamp()) + (30 * 24 * 60 * 60)  # 30 days TTL
            }
        )
        
        # Publish custom metrics to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='IoT/Sensors',
            MetricData=[
                {
                    'MetricName': 'Temperature',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id},
                        {'Name': 'Location', 'Value': location}
                    ],
                    'Value': temperature,
                    'Unit': 'None',
                    'Timestamp': datetime.fromtimestamp(timestamp)
                },
                {
                    'MetricName': 'Humidity',
                    'Dimensions': [
                        {'Name': 'DeviceId', 'Value': device_id},
                        {'Name': 'Location', 'Value': location}
                    ],
                    'Value': humidity,
                    'Unit': 'Percent',
                    'Timestamp': datetime.fromtimestamp(timestamp)
                }
            ]
        )
        
        # Check for temperature alerts
        temp_threshold = float(os.environ.get('TEMPERATURE_THRESHOLD', '30.0'))
        if temperature > temp_threshold:
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'High Temperature Alert - Device {device_id}',
                Message=f'''
High temperature detected!

Device: {device_id}
Location: {location}
Temperature: {temperature}°C
Threshold: {temp_threshold}°C
Timestamp: {datetime.fromtimestamp(timestamp)}

Please investigate immediately.
                '''
            )
            logger.warning(f"High temperature alert sent for device {device_id}")
        
        # Check for humidity alerts
        humidity_threshold = float(os.environ.get('HUMIDITY_THRESHOLD', '80.0'))
        if humidity > humidity_threshold:
            sns.publish(
                TopicArn=os.environ['SNS_TOPIC_ARN'],
                Subject=f'High Humidity Alert - Device {device_id}',
                Message=f'''
High humidity detected!

Device: {device_id}
Location: {location}
Humidity: {humidity}%
Threshold: {humidity_threshold}%
Timestamp: {datetime.fromtimestamp(timestamp)}

Please check ventilation systems.
                '''
            )
            logger.warning(f"High humidity alert sent for device {device_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data processed successfully',
                'deviceId': device_id,
                'timestamp': timestamp,
                'metrics_published': True
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing IoT data: {str(e)}")
        
        # Publish error metric
        try:
            cloudwatch.put_metric_data(
                Namespace='IoT/Sensors',
                MetricData=[
                    {
                        'MetricName': 'ProcessingErrors',
                        'Value': 1,
                        'Unit': 'Count'
                    }
                ]
            )
        except Exception as metric_error:
            logger.error(f"Failed to publish error metric: {metric_error}")
        
        raise
'''

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "IoTEndpoint",
            description="AWS IoT Core endpoint for device connections",
            value=f"a{self.account}-ats.iot.{self.region}.amazonaws.com",
        )
        
        CfnOutput(
            self, "IoTThingName",
            description="Name of the created IoT Thing",
            value=self.iot_thing.thing_name,
        )
        
        CfnOutput(
            self, "IoTPolicyName",
            description="Name of the IoT policy for device permissions",
            value=self.iot_policy.policy_name,
        )
        
        CfnOutput(
            self, "DynamoDBTableName",
            description="DynamoDB table name for sensor data storage",
            value=self.sensor_data_table.table_name,
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            description="Lambda function name for data processing",
            value=self.processor_function.function_name,
        )
        
        CfnOutput(
            self, "SNSTopicArn",
            description="SNS topic ARN for alert notifications",
            value=self.alert_topic.topic_arn,
        )
        
        CfnOutput(
            self, "IoTRuleName",
            description="IoT Rules Engine rule name",
            value=self.iot_rule.rule_name,
        )


class IoTDataIngestionApp(cdk.App):
    """
    CDK Application for IoT Data Ingestion Pipeline
    
    This application creates a complete IoT data ingestion solution
    following AWS best practices for security, scalability, and cost optimization.
    """

    def __init__(self):
        super().__init__()
        
        # Get configuration from context or environment
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
        )
        
        # Create the main stack
        IoTDataIngestionStack(
            self, "IoTDataIngestionStack",
            env=env,
            description="Complete IoT data ingestion pipeline with AWS IoT Core, Lambda, and DynamoDB",
            tags={
                "Project": "IoT-Data-Ingestion",
                "Environment": "Development",
                "CostCenter": "Engineering",
                "Owner": "DevOps-Team",
            },
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = IoTDataIngestionApp()
    app.synth()