#!/usr/bin/env python3
"""
CDK Python application for IoT Data Visualization with QuickSight.

This application deploys the complete infrastructure needed for collecting,
processing, and visualizing IoT sensor data using AWS services.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_iot as iot,
    aws_iam as iam,
    aws_kinesis as kinesis,
    aws_kinesisfirehose as firehose,
    aws_s3 as s3,
    aws_glue as glue,
    aws_quicksight as quicksight,
)
from constructs import Construct


class IoTDataVisualizationStack(Stack):
    """
    CDK Stack for IoT Data Visualization with QuickSight.
    
    This stack creates:
    - IoT Core resources for device connectivity
    - Kinesis Data Streams for real-time data processing
    - Kinesis Data Firehose for data delivery to S3
    - S3 bucket for data storage
    - Glue Data Catalog for schema management
    - QuickSight resources for data visualization
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 bucket for IoT data storage
        self.data_bucket = s3.Bucket(
            self,
            "IoTDataBucket",
            bucket_name=f"iot-analytics-bucket-{unique_suffix}",
            versioning=s3.BucketVersioning.ENABLED,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="IoTDataLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )

        # Create Kinesis Data Stream for real-time processing
        self.kinesis_stream = kinesis.Stream(
            self,
            "IoTDataStream",
            stream_name=f"iot-data-stream-{unique_suffix}",
            shard_count=1,
            retention_period=Duration.days(1),
            stream_mode=kinesis.StreamMode.PROVISIONED
        )

        # Create IAM role for IoT Rules Engine to access Kinesis
        self.iot_kinesis_role = iam.Role(
            self,
            "IoTKinesisRole",
            role_name=f"IoTKinesisRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com"),
            description="Role for IoT Rules Engine to publish to Kinesis",
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

        # Create IAM role for Firehose to access S3
        self.firehose_role = iam.Role(
            self,
            "FirehoseDeliveryRole",
            role_name=f"FirehoseDeliveryRole-{unique_suffix}",
            assumed_by=iam.ServicePrincipal("firehose.amazonaws.com"),
            description="Role for Firehose to deliver data to S3",
            inline_policies={
                "S3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:AbortMultipartUpload",
                                "s3:GetBucketLocation",
                                "s3:GetObject",
                                "s3:ListBucket",
                                "s3:ListBucketMultipartUploads",
                                "s3:PutObject"
                            ],
                            resources=[
                                self.data_bucket.bucket_arn,
                                f"{self.data_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                )
            }
        )

        # Create Kinesis Data Firehose delivery stream
        self.firehose_stream = firehose.CfnDeliveryStream(
            self,
            "IoTFirehoseStream",
            delivery_stream_name=f"iot-firehose-{unique_suffix}",
            delivery_stream_type="KinesisStreamAsSource",
            kinesis_stream_source_configuration=firehose.CfnDeliveryStream.KinesisStreamSourceConfigurationProperty(
                kinesis_stream_arn=self.kinesis_stream.stream_arn,
                role_arn=self.firehose_role.role_arn
            ),
            extended_s3_destination_configuration=firehose.CfnDeliveryStream.ExtendedS3DestinationConfigurationProperty(
                bucket_arn=self.data_bucket.bucket_arn,
                role_arn=self.firehose_role.role_arn,
                prefix="iot-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/",
                error_output_prefix="errors/",
                buffering_hints=firehose.CfnDeliveryStream.BufferingHintsProperty(
                    size_in_m_bs=1,
                    interval_in_seconds=60
                ),
                compression_format="GZIP",
                data_format_conversion_configuration=firehose.CfnDeliveryStream.DataFormatConversionConfigurationProperty(
                    enabled=False
                )
            )
        )

        # Create IoT policy for device permissions
        self.iot_policy = iot.CfnPolicy(
            self,
            "IoTDevicePolicy",
            policy_name=f"iot-device-policy-{unique_suffix}",
            policy_document={
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Action": [
                            "iot:Connect",
                            "iot:Publish"
                        ],
                        "Resource": "*"
                    }
                ]
            }
        )

        # Create IoT Thing representing sensor device
        self.iot_thing = iot.CfnThing(
            self,
            "IoTSensorThing",
            thing_name=f"iot-sensor-{unique_suffix}",
            thing_type_name="SensorDevice",
            attribute_payload=iot.CfnThing.AttributePayloadProperty(
                attributes={
                    "DeviceType": "MultiSensor",
                    "Location": "Factory Floor",
                    "Model": "SensorPro-3000"
                }
            )
        )

        # Create IoT Rule to route data to Kinesis
        self.iot_rule = iot.CfnTopicRule(
            self,
            "IoTKinesisRule",
            rule_name="RouteToKinesis",
            topic_rule_payload=iot.CfnTopicRule.TopicRulePayloadProperty(
                sql="SELECT *, timestamp() as event_time FROM 'topic/sensor/data'",
                description="Route IoT sensor data to Kinesis Data Streams",
                actions=[
                    iot.CfnTopicRule.ActionProperty(
                        kinesis=iot.CfnTopicRule.KinesisActionProperty(
                            stream_name=self.kinesis_stream.stream_name,
                            role_arn=self.iot_kinesis_role.role_arn
                        )
                    )
                ]
            )
        )

        # Create Glue database for data catalog
        self.glue_database = glue.CfnDatabase(
            self,
            "IoTAnalyticsDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="iot_analytics_db",
                description="Database for IoT sensor data analytics"
            )
        )

        # Create Glue table for IoT sensor data
        self.glue_table = glue.CfnTable(
            self,
            "IoTSensorTable",
            catalog_id=self.account,
            database_name=self.glue_database.ref,
            table_input=glue.CfnTable.TableInputProperty(
                name="iot_sensor_data",
                description="Table for IoT sensor data",
                table_type="EXTERNAL_TABLE",
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    columns=[
                        glue.CfnTable.ColumnProperty(
                            name="device_id",
                            type="string",
                            comment="IoT device identifier"
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="temperature",
                            type="int",
                            comment="Temperature reading in Celsius"
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="humidity",
                            type="int",
                            comment="Humidity percentage"
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="pressure",
                            type="int",
                            comment="Pressure reading in hPa"
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="timestamp",
                            type="string",
                            comment="Device timestamp"
                        ),
                        glue.CfnTable.ColumnProperty(
                            name="event_time",
                            type="bigint",
                            comment="Server-side timestamp"
                        )
                    ],
                    location=f"s3://{self.data_bucket.bucket_name}/iot-data/",
                    input_format="org.apache.hadoop.mapred.TextInputFormat",
                    output_format="org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                    serde_info=glue.CfnTable.SerdeInfoProperty(
                        serialization_library="org.openx.data.jsonserde.JsonSerDe"
                    )
                )
            )
        )

        # Create QuickSight data source (requires manual setup of QuickSight account)
        # Note: QuickSight account creation is typically done through the console
        # This creates the data source configuration that can be used once QuickSight is set up
        try:
            self.quicksight_data_source = quicksight.CfnDataSource(
                self,
                "IoTQuickSightDataSource",
                aws_account_id=self.account,
                data_source_id="iot-athena-datasource",
                name="IoT Analytics Data Source",
                type="ATHENA",
                data_source_parameters=quicksight.CfnDataSource.DataSourceParametersProperty(
                    athena_parameters=quicksight.CfnDataSource.AthenaParametersProperty(
                        work_group="primary"
                    )
                )
            )
        except Exception:
            # QuickSight resources may fail if account is not set up
            pass

        # Create outputs
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket name for IoT data storage"
        )

        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Kinesis Data Stream name"
        )

        CfnOutput(
            self,
            "IoTThingName",
            value=self.iot_thing.thing_name,
            description="IoT Thing name for sensor device"
        )

        CfnOutput(
            self,
            "IoTPolicyName",
            value=self.iot_policy.policy_name,
            description="IoT Policy name for device permissions"
        )

        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="Glue database name for data catalog"
        )

        CfnOutput(
            self,
            "GlueTableName",
            value=self.glue_table.ref,
            description="Glue table name for IoT sensor data"
        )

        CfnOutput(
            self,
            "IoTDataTopic",
            value="topic/sensor/data",
            description="MQTT topic for publishing sensor data"
        )

        CfnOutput(
            self,
            "AthenaQueryLocation",
            value=f"s3://{self.data_bucket.bucket_name}/athena-results/",
            description="S3 location for Athena query results"
        )


def main() -> None:
    """Main function to deploy the CDK application."""
    app = cdk.App()
    
    # Get unique suffix from context or environment
    unique_suffix = app.node.try_get_context("unique_suffix") or os.environ.get("UNIQUE_SUFFIX", "demo")
    
    # Create the stack
    IoTDataVisualizationStack(
        app,
        "IoTDataVisualizationStack",
        description="IoT Data Visualization with QuickSight - Complete infrastructure for IoT analytics",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        ),
        tags={
            "Project": "IoT Data Visualization",
            "Environment": "Demo",
            "ManagedBy": "CDK",
            "Recipe": "iot-data-visualization-quicksight"
        }
    )
    
    # Synthesize the CDK app
    app.synth()


if __name__ == "__main__":
    main()