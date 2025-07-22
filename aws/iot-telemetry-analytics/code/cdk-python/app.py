#!/usr/bin/env python3
"""
CDK Python Application for IoT Analytics Pipelines with AWS IoT Analytics

This application demonstrates building IoT analytics pipelines using AWS IoT Analytics
and provides a modern alternative using Kinesis Data Streams and Amazon Timestream.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_iot as iot,
    aws_iotanalytics as iotanalytics,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_lambda_event_sources as event_sources,
    aws_timestream as timestream,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct


class IoTAnalyticsPipelineStack(Stack):
    """
    CDK Stack for IoT Analytics Pipelines with AWS IoT Analytics and modern alternatives.
    
    This stack creates:
    1. Legacy IoT Analytics components (Channel, Pipeline, Datastore, Dataset)
    2. Modern alternative using Kinesis Data Streams and Amazon Timestream
    3. Lambda function for data processing
    4. IoT Rules for routing data
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create IoT Analytics components (legacy)
        self._create_iot_analytics_components(unique_suffix)
        
        # Create modern alternative with Kinesis and Timestream
        self._create_modern_analytics_pipeline(unique_suffix)
        
        # Create IoT Rules for data routing
        self._create_iot_rules(unique_suffix)

    def _create_iot_analytics_components(self, unique_suffix: str) -> None:
        """
        Create AWS IoT Analytics components including channel, pipeline, datastore, and dataset.
        
        Args:
            unique_suffix: Unique suffix for resource naming
        """
        # Create IoT Analytics Channel
        self.iot_channel = iotanalytics.CfnChannel(
            self,
            "IoTAnalyticsChannel",
            channel_name=f"iot-sensor-channel-{unique_suffix}",
            retention_period=iotanalytics.CfnChannel.RetentionPeriodProperty(
                unlimited=True
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT Analytics Demo"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )
        
        # Create IoT Analytics Datastore
        self.iot_datastore = iotanalytics.CfnDatastore(
            self,
            "IoTAnalyticsDatastore",
            datastore_name=f"iot-sensor-datastore-{unique_suffix}",
            retention_period=iotanalytics.CfnDatastore.RetentionPeriodProperty(
                unlimited=True
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT Analytics Demo"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )
        
        # Create IoT Analytics Pipeline
        self.iot_pipeline = iotanalytics.CfnPipeline(
            self,
            "IoTAnalyticsPipeline",
            pipeline_name=f"iot-sensor-pipeline-{unique_suffix}",
            pipeline_activities=[
                # Channel activity (data source)
                iotanalytics.CfnPipeline.ActivityProperty(
                    channel=iotanalytics.CfnPipeline.ChannelProperty(
                        name="ChannelActivity",
                        channel_name=self.iot_channel.channel_name,
                        next="FilterActivity"
                    )
                ),
                # Filter activity (remove invalid readings)
                iotanalytics.CfnPipeline.ActivityProperty(
                    filter=iotanalytics.CfnPipeline.FilterProperty(
                        name="FilterActivity",
                        filter="temperature > 0 AND temperature < 100",
                        next="MathActivity"
                    )
                ),
                # Math activity (temperature conversion)
                iotanalytics.CfnPipeline.ActivityProperty(
                    math=iotanalytics.CfnPipeline.MathProperty(
                        name="MathActivity",
                        math="temperature",
                        attribute="temperature_celsius",
                        next="AddAttributesActivity"
                    )
                ),
                # Add attributes activity (enrich data)
                iotanalytics.CfnPipeline.ActivityProperty(
                    add_attributes=iotanalytics.CfnPipeline.AddAttributesProperty(
                        name="AddAttributesActivity",
                        attributes={
                            "location": "factory_floor_1",
                            "device_type": "temperature_sensor"
                        },
                        next="DatastoreActivity"
                    )
                ),
                # Datastore activity (final destination)
                iotanalytics.CfnPipeline.ActivityProperty(
                    datastore=iotanalytics.CfnPipeline.DatastoreProperty(
                        name="DatastoreActivity",
                        datastore_name=self.iot_datastore.datastore_name
                    )
                )
            ],
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT Analytics Demo"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )
        
        # Create IoT Analytics Dataset
        self.iot_dataset = iotanalytics.CfnDataset(
            self,
            "IoTAnalyticsDataset",
            dataset_name=f"iot-sensor-dataset-{unique_suffix}",
            actions=[
                iotanalytics.CfnDataset.ActionProperty(
                    action_name="SqlAction",
                    query_action=iotanalytics.CfnDataset.QueryActionProperty(
                        sql_query=f"SELECT * FROM {self.iot_datastore.datastore_name} WHERE temperature_celsius > 25 ORDER BY timestamp DESC LIMIT 100"
                    )
                )
            ],
            triggers=[
                iotanalytics.CfnDataset.TriggerProperty(
                    schedule=iotanalytics.CfnDataset.ScheduleProperty(
                        schedule_expression="rate(1 hour)"
                    )
                )
            ],
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT Analytics Demo"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )

    def _create_modern_analytics_pipeline(self, unique_suffix: str) -> None:
        """
        Create modern analytics pipeline using Kinesis Data Streams and Amazon Timestream.
        
        Args:
            unique_suffix: Unique suffix for resource naming
        """
        # Create Kinesis Data Stream
        self.kinesis_stream = kinesis.Stream(
            self,
            "IoTKinesisStream",
            stream_name=f"iot-sensor-stream-{unique_suffix}",
            shard_count=1,
            retention_period=Duration.hours(24),
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create Timestream Database
        self.timestream_database = timestream.CfnDatabase(
            self,
            "IoTTimestreamDatabase",
            database_name=f"iot-sensor-db-{unique_suffix}",
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT Analytics Demo"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )
        
        # Create Timestream Table
        self.timestream_table = timestream.CfnTable(
            self,
            "IoTTimestreamTable",
            database_name=self.timestream_database.database_name,
            table_name="sensor-data",
            retention_properties=timestream.CfnTable.RetentionPropertiesProperty(
                memory_store_retention_period_in_hours="24",
                magnetic_store_retention_period_in_days="365"
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="IoT Analytics Demo"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )
        
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "LambdaTimestreamRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaKinesisExecutionRole")
            ],
            inline_policies={
                "TimestreamAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "timestream:WriteRecords",
                                "timestream:DescribeEndpoints"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )
        
        # Create Lambda function for processing Kinesis data
        lambda_function_code = """
import json
import boto3
import time
import base64
from datetime import datetime
from typing import Dict, Any, List

timestream = boto3.client('timestream-write')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    \"\"\"
    Process Kinesis records and write to Timestream.
    
    Args:
        event: Kinesis event with records
        context: Lambda context
        
    Returns:
        Response with status code
    \"\"\"
    database_name = 'DATABASE_NAME_PLACEHOLDER'
    table_name = 'sensor-data'
    
    records = []
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload_data = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            payload = json.loads(payload_data)
            
            # Prepare Timestream record
            current_time = str(int(time.time() * 1000))
            
            # Create temperature measurement
            if 'temperature' in payload:
                timestream_record = {
                    'Time': current_time,
                    'TimeUnit': 'MILLISECONDS',
                    'Dimensions': [
                        {
                            'Name': 'DeviceId',
                            'Value': payload.get('deviceId', 'unknown')
                        },
                        {
                            'Name': 'Location',
                            'Value': 'factory_floor_1'
                        },
                        {
                            'Name': 'DeviceType',
                            'Value': 'temperature_sensor'
                        }
                    ],
                    'MeasureName': 'temperature',
                    'MeasureValue': str(payload['temperature']),
                    'MeasureValueType': 'DOUBLE'
                }
                records.append(timestream_record)
            
            # Create humidity measurement if present
            if 'humidity' in payload:
                humidity_record = {
                    'Time': current_time,
                    'TimeUnit': 'MILLISECONDS',
                    'Dimensions': [
                        {
                            'Name': 'DeviceId',
                            'Value': payload.get('deviceId', 'unknown')
                        },
                        {
                            'Name': 'Location',
                            'Value': 'factory_floor_1'
                        },
                        {
                            'Name': 'DeviceType',
                            'Value': 'humidity_sensor'
                        }
                    ],
                    'MeasureName': 'humidity',
                    'MeasureValue': str(payload['humidity']),
                    'MeasureValueType': 'DOUBLE'
                }
                records.append(humidity_record)
                
        except Exception as e:
            print(f"Error processing record: {e}")
            continue
    
    # Write to Timestream in batches
    if records:
        try:
            # Timestream supports up to 100 records per batch
            batch_size = 100
            for i in range(0, len(records), batch_size):
                batch = records[i:i + batch_size]
                
                timestream.write_records(
                    DatabaseName=database_name,
                    TableName=table_name,
                    Records=batch
                )
                
            print(f"Successfully wrote {len(records)} records to Timestream")
            
        except Exception as e:
            print(f"Error writing to Timestream: {e}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Processed {len(records)} records')
    }
"""
        
        # Replace placeholder with actual database name
        lambda_function_code = lambda_function_code.replace(
            'DATABASE_NAME_PLACEHOLDER',
            self.timestream_database.database_name
        )
        
        self.lambda_function = lambda_.Function(
            self,
            "ProcessIoTDataFunction",
            function_name=f"ProcessIoTData-{unique_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_function_code),
            role=lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                "TIMESTREAM_DATABASE": self.timestream_database.database_name,
                "TIMESTREAM_TABLE": self.timestream_table.table_name
            }
        )
        
        # Add Kinesis event source to Lambda
        self.lambda_function.add_event_source(
            event_sources.KinesisEventSource(
                self.kinesis_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=100,
                max_batching_window=Duration.seconds(5)
            )
        )

    def _create_iot_rules(self, unique_suffix: str) -> None:
        """
        Create IoT Rules for routing data to both legacy and modern pipelines.
        
        Args:
            unique_suffix: Unique suffix for resource naming
        """
        # Create IoT Rule for legacy IoT Analytics
        self.iot_analytics_rule = iot.CfnTopicRule(
            self,
            "IoTAnalyticsRule",
            rule_name=f"IoTAnalyticsRule_{unique_suffix}",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM 'topic/sensor/data'",
                description="Route sensor data to IoT Analytics",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        iot_analytics=iot.CfnTopicRule.IotAnalyticsActionProperty(
                            channel_name=self.iot_channel.channel_name
                        )
                    )
                ]
            )
        )
        
        # Create IoT Rule for modern Kinesis pipeline
        self.kinesis_rule = iot.CfnTopicRule(
            self,
            "KinesisRule",
            rule_name=f"KinesisRule_{unique_suffix}",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT * FROM 'topic/sensor/data/kinesis'",
                description="Route sensor data to Kinesis Data Streams",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        kinesis=iot.CfnTopicRule.KinesisActionProperty(
                            stream_name=self.kinesis_stream.stream_name,
                            partition_key="${deviceId}",
                            role_arn=self._create_iot_kinesis_role().role_arn
                        )
                    )
                ]
            )
        )
        
        # Create outputs for easy access
        CfnOutput(
            self,
            "IoTAnalyticsChannelName",
            value=self.iot_channel.channel_name,
            description="Name of the IoT Analytics Channel"
        )
        
        CfnOutput(
            self,
            "IoTAnalyticsDatastoreName",
            value=self.iot_datastore.datastore_name,
            description="Name of the IoT Analytics Datastore"
        )
        
        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis Data Stream"
        )
        
        CfnOutput(
            self,
            "TimestreamDatabaseName",
            value=self.timestream_database.database_name,
            description="Name of the Timestream Database"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda Function"
        )
        
        CfnOutput(
            self,
            "IoTAnalyticsTopicName",
            value="topic/sensor/data",
            description="IoT Topic for sending data to IoT Analytics"
        )
        
        CfnOutput(
            self,
            "KinesisTopicName",
            value="topic/sensor/data/kinesis",
            description="IoT Topic for sending data to Kinesis"
        )

    def _create_iot_kinesis_role(self) -> iam.Role:
        """
        Create IAM role for IoT Core to write to Kinesis.
        
        Returns:
            IAM Role for IoT Core Kinesis access
        """
        return iam.Role(
            self,
            "IoTKinesisRole",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            inline_policies={
                "KinesisAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:PutRecord",
                                "kinesis:PutRecords"
                            ],
                            resources=[self.kinesis_stream.stream_arn]
                        )
                    ]
                )
            }
        )


# CDK App
app = cdk.App()

# Create the stack
IoTAnalyticsPipelineStack(
    app,
    "IoTAnalyticsPipelineStack",
    env=cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    ),
    description="IoT Analytics Pipelines with AWS IoT Analytics and modern alternatives"
)

# Synthesize the CloudFormation template
app.synth()