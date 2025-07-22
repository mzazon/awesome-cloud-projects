#!/usr/bin/env python3
"""
AWS CDK Python application for Industrial IoT Data Collection with AWS IoT SiteWise

This application creates a complete industrial IoT data collection solution using:
- AWS IoT SiteWise for asset modeling and data collection
- Amazon Timestream for time-series data storage
- CloudWatch for monitoring and alerting
- IAM roles and policies for secure access

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Tags,
    Duration,
    CfnOutput,
    aws_iam as iam,
    aws_iotsitewise as iotsitewise,
    aws_timestream as timestream,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_lambda as lambda_,
    aws_logs as logs,
)
from constructs import Construct


class IndustrialIoTDataCollectionStack(Stack):
    """
    CDK Stack for Industrial IoT Data Collection using AWS IoT SiteWise
    
    This stack creates:
    - IoT SiteWise asset model and assets
    - Timestream database for time-series storage
    - CloudWatch alarms and dashboards
    - IAM roles and policies
    - SNS topics for alerts
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Industrial IoT Data Collection stack
        
        Args:
            scope: The parent construct
            construct_id: Unique identifier for this stack
            project_name: Name of the project for resource naming
            **kwargs: Additional arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)
        
        self.project_name = project_name
        
        # Create core resources
        self.create_iam_roles()
        self.create_sitewise_resources()
        self.create_timestream_resources()
        self.create_monitoring_resources()
        self.create_alerting_resources()
        self.create_outputs()
        
        # Apply tags to all resources
        self.apply_tags()

    def create_iam_roles(self) -> None:
        """Create IAM roles required for the industrial IoT solution"""
        
        # Role for IoT SiteWise to access Timestream
        self.sitewise_timestream_role = iam.Role(
            self,
            "SiteWiseTimestreamRole",
            assumed_by=iam.ServicePrincipal("iotsitewise.amazonaws.com"),
            description="Role for IoT SiteWise to write data to Timestream",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonTimestreamWriteOnlyAccess"
                )
            ]
        )
        
        # Role for data processing Lambda functions
        self.data_processing_role = iam.Role(
            self,
            "DataProcessingRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Role for data processing Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add inline policies for specific permissions
        self.data_processing_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "iotsitewise:GetAssetPropertyValue",
                    "iotsitewise:GetAssetPropertyValueHistory",
                    "iotsitewise:BatchPutAssetPropertyValue",
                    "timestream:WriteRecords",
                    "timestream:DescribeEndpoints",
                    "cloudwatch:PutMetricData"
                ],
                resources=["*"]
            )
        )

    def create_sitewise_resources(self) -> None:
        """Create AWS IoT SiteWise assets and models"""
        
        # Create asset model for production line equipment
        self.asset_model = iotsitewise.CfnAssetModel(
            self,
            "ProductionLineAssetModel",
            asset_model_name="ProductionLineEquipment",
            asset_model_description="Asset model for production line machinery",
            asset_model_properties=[
                # Temperature measurement property
                iotsitewise.CfnAssetModel.AssetModelPropertyProperty(
                    name="Temperature",
                    data_type="DOUBLE",
                    unit="Celsius",
                    type=iotsitewise.CfnAssetModel.PropertyTypeProperty(
                        type_name="Measurement"
                    )
                ),
                # Pressure measurement property
                iotsitewise.CfnAssetModel.AssetModelPropertyProperty(
                    name="Pressure",
                    data_type="DOUBLE",
                    unit="PSI",
                    type=iotsitewise.CfnAssetModel.PropertyTypeProperty(
                        type_name="Measurement"
                    )
                ),
                # Calculated operational efficiency property
                iotsitewise.CfnAssetModel.AssetModelPropertyProperty(
                    name="OperationalEfficiency",
                    data_type="DOUBLE",
                    unit="Percent",
                    type=iotsitewise.CfnAssetModel.PropertyTypeProperty(
                        type_name="Transform",
                        transform=iotsitewise.CfnAssetModel.TransformProperty(
                            expression="temp / 100 * pressure / 50",
                            variables=[
                                iotsitewise.CfnAssetModel.ExpressionVariableProperty(
                                    name="temp",
                                    value=iotsitewise.CfnAssetModel.VariableValueProperty(
                                        property_logical_id="Temperature"
                                    )
                                ),
                                iotsitewise.CfnAssetModel.ExpressionVariableProperty(
                                    name="pressure",
                                    value=iotsitewise.CfnAssetModel.VariableValueProperty(
                                        property_logical_id="Pressure"
                                    )
                                )
                            ]
                        )
                    )
                ),
                # Operating status attribute
                iotsitewise.CfnAssetModel.AssetModelPropertyProperty(
                    name="OperatingStatus",
                    data_type="STRING",
                    type=iotsitewise.CfnAssetModel.PropertyTypeProperty(
                        type_name="Attribute",
                        attribute=iotsitewise.CfnAssetModel.AttributeProperty(
                            default_value="OPERATIONAL"
                        )
                    )
                )
            ]
        )
        
        # Create physical asset instance
        self.production_asset = iotsitewise.CfnAsset(
            self,
            "ProductionLineAsset",
            asset_name=f"ProductionLine-A-Pump-001-{self.project_name}",
            asset_model_id=self.asset_model.attr_asset_model_id,
            asset_properties=[
                iotsitewise.CfnAsset.AssetPropertyProperty(
                    logical_id="OperatingStatus",
                    alias="/production/line-a/pump-001/status"
                )
            ]
        )
        
        # Create gateway for data collection simulation
        self.gateway = iotsitewise.CfnGateway(
            self,
            "IndustrialGateway",
            gateway_name=f"manufacturing-gateway-{self.project_name}",
            gateway_platform=iotsitewise.CfnGateway.GatewayPlatformProperty(
                greengrass_v2=iotsitewise.CfnGateway.GreengrassV2Property(
                    core_device_thing_name=f"sitewise-gateway-{self.project_name}"
                )
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="Development"),
                cdk.CfnTag(key="Project", value=self.project_name),
                cdk.CfnTag(key="Purpose", value="Industrial IoT Data Collection")
            ]
        )

    def create_timestream_resources(self) -> None:
        """Create Amazon Timestream database and table for time-series data"""
        
        # Create Timestream database
        self.timestream_database = timestream.CfnDatabase(
            self,
            "IndustrialTimestreamDB",
            database_name=f"industrial-data-{self.project_name}",
            tags=[
                cdk.CfnTag(key="Environment", value="Development"),
                cdk.CfnTag(key="Project", value=self.project_name)
            ]
        )
        
        # Create Timestream table for equipment metrics
        self.timestream_table = timestream.CfnTable(
            self,
            "EquipmentMetricsTable",
            database_name=self.timestream_database.database_name,
            table_name="equipment-metrics",
            retention_properties=timestream.CfnTable.RetentionPropertiesProperty(
                memory_store_retention_period_in_hours=24,
                magnetic_store_retention_period_in_days=365
            ),
            tags=[
                cdk.CfnTag(key="Environment", value="Development"),
                cdk.CfnTag(key="Project", value=self.project_name)
            ]
        )
        
        # Ensure table is created after database
        self.timestream_table.add_dependency(self.timestream_database)

    def create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring resources"""
        
        # Create CloudWatch alarm for high temperature
        self.temperature_alarm = cloudwatch.Alarm(
            self,
            "HighTemperatureAlarm",
            alarm_name=f"ProductionLine-A-HighTemperature-{self.project_name}",
            alarm_description="Alert when equipment temperature exceeds threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/IoTSiteWise",
                metric_name="Temperature",
                dimensions_map={
                    "AssetId": self.production_asset.attr_asset_id
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=80.0,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Create CloudWatch alarm for low pressure
        self.pressure_alarm = cloudwatch.Alarm(
            self,
            "LowPressureAlarm",
            alarm_name=f"ProductionLine-A-LowPressure-{self.project_name}",
            alarm_description="Alert when equipment pressure drops below threshold",
            metric=cloudwatch.Metric(
                namespace="AWS/IoTSiteWise",
                metric_name="Pressure",
                dimensions_map={
                    "AssetId": self.production_asset.attr_asset_id
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=30.0,
            comparison_operator=cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "IndustrialIoTDashboard",
            dashboard_name=f"Industrial-IoT-Monitoring-{self.project_name}",
            widgets=[
                [
                    cloudwatch.GraphWidget(
                        title="Equipment Temperature",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/IoTSiteWise",
                                metric_name="Temperature",
                                dimensions_map={
                                    "AssetId": self.production_asset.attr_asset_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Equipment Pressure",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/IoTSiteWise",
                                metric_name="Pressure",
                                dimensions_map={
                                    "AssetId": self.production_asset.attr_asset_id
                                },
                                statistic="Average",
                                period=Duration.minutes(5)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )

    def create_alerting_resources(self) -> None:
        """Create SNS topic and subscriptions for alerts"""
        
        # Create SNS topic for equipment alerts
        self.alert_topic = sns.Topic(
            self,
            "EquipmentAlertsTopic",
            topic_name=f"equipment-alerts-{self.project_name}",
            display_name="Industrial Equipment Alerts"
        )
        
        # Add SNS topic as alarm action
        self.temperature_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )
        
        self.pressure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alert_topic)
        )
        
        # Create Lambda function for alert processing
        self.alert_processor = lambda_.Function(
            self,
            "AlertProcessor",
            function_name=f"industrial-alert-processor-{self.project_name}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def handler(event, context):
    '''Process equipment alerts and take appropriate actions'''
    
    try:
        # Parse SNS message
        for record in event['Records']:
            sns_message = json.loads(record['Sns']['Message'])
            
            alarm_name = sns_message['AlarmName']
            new_state = sns_message['NewStateValue']
            reason = sns_message['NewStateReason']
            
            logger.info(f"Processing alarm: {alarm_name}, State: {new_state}")
            
            # Process based on alarm type
            if 'Temperature' in alarm_name and new_state == 'ALARM':
                process_temperature_alert(sns_message)
            elif 'Pressure' in alarm_name and new_state == 'ALARM':
                process_pressure_alert(sns_message)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Alerts processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing alerts: {str(e)}")
        raise

def process_temperature_alert(alarm_data):
    '''Handle high temperature alerts'''
    logger.info("Processing high temperature alert - implementing cooling procedures")
    # Add custom logic for temperature alerts
    
def process_pressure_alert(alarm_data):
    '''Handle low pressure alerts'''
    logger.info("Processing low pressure alert - checking pump status")
    # Add custom logic for pressure alerts
            """),
            role=self.data_processing_role,
            timeout=Duration.minutes(5),
            log_retention=logs.RetentionDays.ONE_WEEK
        )
        
        # Subscribe Lambda to SNS topic
        self.alert_topic.add_subscription(
            sns.LambdaSubscription(self.alert_processor)
        )

    def create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self,
            "AssetModelId",
            value=self.asset_model.attr_asset_model_id,
            description="ID of the production line asset model",
            export_name=f"{self.stack_name}-AssetModelId"
        )
        
        CfnOutput(
            self,
            "AssetId",
            value=self.production_asset.attr_asset_id,
            description="ID of the production line asset",
            export_name=f"{self.stack_name}-AssetId"
        )
        
        CfnOutput(
            self,
            "TimestreamDatabaseName",
            value=self.timestream_database.database_name,
            description="Name of the Timestream database",
            export_name=f"{self.stack_name}-TimestreamDB"
        )
        
        CfnOutput(
            self,
            "TimestreamTableName",
            value=self.timestream_table.table_name,
            description="Name of the Timestream table",
            export_name=f"{self.stack_name}-TimestreamTable"
        )
        
        CfnOutput(
            self,
            "GatewayId",
            value=self.gateway.attr_gateway_id,
            description="ID of the IoT SiteWise gateway",
            export_name=f"{self.stack_name}-GatewayId"
        )
        
        CfnOutput(
            self,
            "AlertTopicArn",
            value=self.alert_topic.topic_arn,
            description="ARN of the SNS topic for equipment alerts",
            export_name=f"{self.stack_name}-AlertTopicArn"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name=f"{self.stack_name}-DashboardUrl"
        )

    def apply_tags(self) -> None:
        """Apply consistent tags to all resources in the stack"""
        
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("Purpose", "Industrial IoT Data Collection")
        Tags.of(self).add("ManagedBy", "AWS CDK")
        Tags.of(self).add("Recipe", "industrial-iot-data-collection-aws-iot-sitewise")


class IndustrialIoTDataCollectionApp(cdk.App):
    """
    CDK Application for Industrial IoT Data Collection
    """
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get project name from environment or use default
        project_name = os.environ.get("PROJECT_NAME", "industrial-iot-demo")
        
        # Create the main stack
        IndustrialIoTDataCollectionStack(
            self,
            "IndustrialIoTDataCollectionStack",
            project_name=project_name,
            description="Industrial IoT Data Collection solution using AWS IoT SiteWise",
            env=cdk.Environment(
                account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
                region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
            )
        )


if __name__ == "__main__":
    app = IndustrialIoTDataCollectionApp()
    app.synth()