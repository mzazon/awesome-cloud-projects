#!/usr/bin/env python3
"""
CDK Python application for Amazon Timestream Time-Series Data Solution

This application creates a comprehensive time-series data solution using Amazon Timestream
to ingest, store, and analyze IoT sensor data at scale. The solution demonstrates:

- Amazon Timestream database and table with retention policies
- Lambda function for data ingestion and transformation
- IoT Core rule for direct Timestream integration
- IAM roles and policies with least privilege access
- CloudWatch monitoring and alerting
- S3 bucket for rejected data storage

Architecture:
- IoT devices send data to IoT Core
- IoT Core rules route data directly to Timestream or Lambda
- Lambda functions process and transform data before ingestion
- Timestream provides scalable time-series storage with automatic tiering
- CloudWatch monitors performance and triggers alerts
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_timestream as timestream,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_iot as iot,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from constructs import Construct
import json


class TimestreamTimeSeriesStack(Stack):
    """
    CDK Stack for Amazon Timestream Time-Series Data Solution
    
    This stack creates all the infrastructure needed for a production-ready
    time-series data solution using Amazon Timestream with IoT integration.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.database_name = "iot-timeseries-db"
        self.table_name = "sensor-data"
        self.function_name = "timestream-data-ingestion"
        self.iot_rule_name = "timestream-iot-rule"

        # Create S3 bucket for rejected data
        self.rejected_data_bucket = self._create_rejected_data_bucket()

        # Create Timestream database and table
        self.database = self._create_timestream_database()
        self.table = self._create_timestream_table()

        # Create IAM roles
        self.lambda_role = self._create_lambda_role()
        self.iot_role = self._create_iot_role()

        # Create Lambda function for data ingestion
        self.lambda_function = self._create_lambda_function()

        # Create IoT Core rule
        self.iot_rule = self._create_iot_rule()

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        # Add outputs
        self._create_outputs()

        # Apply tags to all resources
        self._apply_tags()

    def _create_rejected_data_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing rejected Timestream records
        
        Returns:
            s3.Bucket: The created S3 bucket
        """
        bucket = s3.Bucket(
            self, "RejectedDataBucket",
            bucket_name=f"timestream-rejected-data-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldRejectedData",
                    enabled=True,
                    expiration=Duration.days(90),
                    abort_incomplete_multipart_upload_after=Duration.days(7)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        return bucket

    def _create_timestream_database(self) -> timestream.CfnDatabase:
        """
        Create Amazon Timestream database
        
        Returns:
            timestream.CfnDatabase: The created Timestream database
        """
        database = timestream.CfnDatabase(
            self, "TimestreamDatabase",
            database_name=self.database_name,
            tags=[
                cdk.CfnTag(key="Project", value="IoTTimeSeries"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

        return database

    def _create_timestream_table(self) -> timestream.CfnTable:
        """
        Create Amazon Timestream table with retention policies and magnetic store configuration
        
        Returns:
            timestream.CfnTable: The created Timestream table
        """
        table = timestream.CfnTable(
            self, "TimestreamTable",
            database_name=self.database.database_name,
            table_name=self.table_name,
            retention_properties=timestream.CfnTable.RetentionPropertiesProperty(
                memory_store_retention_period_in_hours="24",  # 24 hours in memory store
                magnetic_store_retention_period_in_days="1095"  # 3 years in magnetic store
            ),
            magnetic_store_write_properties=timestream.CfnTable.MagneticStoreWritePropertiesProperty(
                enable_magnetic_store_writes=True,
                magnetic_store_rejected_data_location=timestream.CfnTable.MagneticStoreRejectedDataLocationProperty(
                    s3_configuration=timestream.CfnTable.S3ConfigurationProperty(
                        bucket_name=self.rejected_data_bucket.bucket_name,
                        object_key_prefix="rejected-records/"
                    )
                )
            ),
            tags=[
                cdk.CfnTag(key="Project", value="IoTTimeSeries"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

        # Ensure table depends on database
        table.add_dependency(self.database)

        return table

    def _create_lambda_role(self) -> iam.Role:
        """
        Create IAM role for Lambda function with Timestream write permissions
        
        Returns:
            iam.Role: The created IAM role for Lambda
        """
        role = iam.Role(
            self, "LambdaTimestreamRole",
            role_name=f"{self.function_name}-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add Timestream write permissions
        timestream_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "timestream:WriteRecords",
                "timestream:DescribeEndpoints"
            ],
            resources=[
                f"arn:aws:timestream:{self.region}:{self.account}:database/{self.database_name}",
                f"arn:aws:timestream:{self.region}:{self.account}:database/{self.database_name}/table/{self.table_name}"
            ]
        )

        role.add_to_policy(timestream_policy)

        return role

    def _create_iot_role(self) -> iam.Role:
        """
        Create IAM role for IoT Core rule with Timestream write permissions
        
        Returns:
            iam.Role: The created IAM role for IoT Core
        """
        role = iam.Role(
            self, "IoTTimestreamRole",
            role_name=f"{self.iot_rule_name}-role",
            assumed_by=iam.ServicePrincipal("iot.amazonaws.com")
        )

        # Add Timestream write permissions
        timestream_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "timestream:WriteRecords",
                "timestream:DescribeEndpoints"
            ],
            resources=[
                f"arn:aws:timestream:{self.region}:{self.account}:database/{self.database_name}",
                f"arn:aws:timestream:{self.region}:{self.account}:database/{self.database_name}/table/{self.table_name}"
            ]
        )

        role.add_to_policy(timestream_policy)

        return role

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for data ingestion and transformation
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Lambda function code
        lambda_code = """
import json
import boto3
import os
import time
from datetime import datetime, timezone

timestream = boto3.client('timestream-write')

def lambda_handler(event, context):
    try:
        database_name = os.environ['DATABASE_NAME']
        table_name = os.environ['TABLE_NAME']
        
        # Parse IoT message or direct invocation
        if 'Records' in event:
            # SQS/SNS records
            for record in event['Records']:
                body = json.loads(record['body'])
                write_to_timestream(database_name, table_name, body)
        else:
            # Direct invocation
            write_to_timestream(database_name, table_name, event)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Data written to Timestream successfully')
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def write_to_timestream(database_name, table_name, data):
    current_time = str(int(time.time() * 1000))
    
    records = []
    
    # Handle different data structures
    if isinstance(data, list):
        for item in data:
            records.extend(create_records(item, current_time))
    else:
        records.extend(create_records(data, current_time))
    
    if records:
        try:
            result = timestream.write_records(
                DatabaseName=database_name,
                TableName=table_name,
                Records=records
            )
            print(f"Successfully wrote {len(records)} records")
            return result
        except Exception as e:
            print(f"Error writing to Timestream: {str(e)}")
            raise

def create_records(data, current_time):
    records = []
    device_id = data.get('device_id', 'unknown')
    location = data.get('location', 'unknown')
    
    # Create dimensions (metadata)
    dimensions = [
        {'Name': 'device_id', 'Value': str(device_id)},
        {'Name': 'location', 'Value': str(location)}
    ]
    
    # Handle sensor readings
    if 'sensors' in data:
        for sensor_type, value in data['sensors'].items():
            records.append({
                'Dimensions': dimensions,
                'MeasureName': sensor_type,
                'MeasureValue': str(value),
                'MeasureValueType': 'DOUBLE',
                'Time': current_time,
                'TimeUnit': 'MILLISECONDS'
            })
    
    # Handle single measurements
    if 'measurement' in data:
        records.append({
            'Dimensions': dimensions,
            'MeasureName': data.get('metric_name', 'value'),
            'MeasureValue': str(data['measurement']),
            'MeasureValueType': 'DOUBLE',
            'Time': current_time,
            'TimeUnit': 'MILLISECONDS'
        })
    
    return records
"""

        function = lambda_.Function(
            self, "TimestreamDataIngestion",
            function_name=self.function_name,
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            timeout=Duration.seconds(60),
            memory_size=256,
            role=self.lambda_role,
            environment={
                "DATABASE_NAME": self.database.database_name,
                "TABLE_NAME": self.table.table_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Ensure function depends on table creation
        function.node.add_dependency(self.table)

        return function

    def _create_iot_rule(self) -> iot.CfnTopicRule:
        """
        Create IoT Core rule for direct Timestream integration
        
        Returns:
            iot.CfnTopicRule: The created IoT rule
        """
        # IoT rule SQL and actions
        rule_payload = iot.CfnTopicRule.TopicRulePayloadProperty(
            sql="SELECT device_id, location, timestamp, temperature, humidity, pressure FROM 'topic/sensors'",
            description="Route IoT sensor data to Timestream",
            rule_disabled=False,
            aws_iot_sql_version="2016-03-23",
            actions=[
                iot.CfnTopicRule.ActionProperty(
                    timestream=iot.CfnTopicRule.TimestreamActionProperty(
                        role_arn=self.iot_role.role_arn,
                        database_name=self.database.database_name,
                        table_name=self.table.table_name,
                        dimensions=[
                            iot.CfnTopicRule.TimestreamDimensionProperty(
                                name="device_id",
                                value="${device_id}"
                            ),
                            iot.CfnTopicRule.TimestreamDimensionProperty(
                                name="location",
                                value="${location}"
                            )
                        ]
                    )
                )
            ]
        )

        rule = iot.CfnTopicRule(
            self, "IoTTimestreamRule",
            rule_name=self.iot_rule_name,
            topic_rule_payload=rule_payload,
            tags=[
                cdk.CfnTag(key="Project", value="IoTTimeSeries"),
                cdk.CfnTag(key="Environment", value="Production")
            ]
        )

        # Ensure rule depends on table and role creation
        rule.add_dependency(self.table)
        rule.node.add_dependency(self.iot_role)

        return rule

    def _create_cloudwatch_alarms(self) -> None:
        """
        Create CloudWatch alarms for monitoring Timestream performance
        """
        # Alarm for ingestion rate monitoring
        ingestion_alarm = cloudwatch.Alarm(
            self, "TimestreamIngestionAlarm",
            alarm_name=f"Timestream-IngestionRate-{self.database_name}",
            alarm_description="Monitor Timestream ingestion rate",
            metric=cloudwatch.Metric(
                namespace="AWS/Timestream",
                metric_name="SuccessfulRequestLatency",
                dimensions_map={
                    "DatabaseName": self.database_name,
                    "TableName": self.table_name,
                    "Operation": "WriteRecords"
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=1000,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Alarm for query latency monitoring
        query_alarm = cloudwatch.Alarm(
            self, "TimestreamQueryAlarm",
            alarm_name=f"Timestream-QueryLatency-{self.database_name}",
            alarm_description="Monitor Timestream query latency",
            metric=cloudwatch.Metric(
                namespace="AWS/Timestream",
                metric_name="QueryLatency",
                dimensions_map={
                    "DatabaseName": self.database_name
                },
                statistic="Average",
                period=Duration.minutes(5)
            ),
            threshold=5000,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=2,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )

        # Lambda function error monitoring
        lambda_error_alarm = cloudwatch.Alarm(
            self, "LambdaErrorAlarm",
            alarm_name=f"Lambda-Errors-{self.function_name}",
            alarm_description="Monitor Lambda function errors",
            metric=self.lambda_function.metric_errors(
                period=Duration.minutes(5)
            ),
            threshold=5,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=2
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resource identifiers
        """
        CfnOutput(
            self, "DatabaseName",
            value=self.database.database_name,
            description="Name of the Timestream database",
            export_name=f"{self.stack_name}-DatabaseName"
        )

        CfnOutput(
            self, "TableName",
            value=self.table.table_name,
            description="Name of the Timestream table",
            export_name=f"{self.stack_name}-TableName"
        )

        CfnOutput(
            self, "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for data ingestion",
            export_name=f"{self.stack_name}-LambdaFunctionName"
        )

        CfnOutput(
            self, "LambdaFunctionArn",
            value=self.lambda_function.function_arn,
            description="ARN of the Lambda function for data ingestion",
            export_name=f"{self.stack_name}-LambdaFunctionArn"
        )

        CfnOutput(
            self, "IoTRuleName",
            value=self.iot_rule.rule_name,
            description="Name of the IoT Core rule",
            export_name=f"{self.stack_name}-IoTRuleName"
        )

        CfnOutput(
            self, "RejectedDataBucket",
            value=self.rejected_data_bucket.bucket_name,
            description="S3 bucket for rejected Timestream data",
            export_name=f"{self.stack_name}-RejectedDataBucket"
        )

        CfnOutput(
            self, "SampleQueryCommand",
            value=f'aws timestream-query query --query-string "SELECT device_id, location, measure_name, measure_value::double, time FROM \\"{self.database_name}\\".\\"{self.table_name}\\" WHERE time >= ago(1h) ORDER BY time DESC LIMIT 10"',
            description="Sample command to query the time-series data"
        )

    def _apply_tags(self) -> None:
        """
        Apply common tags to all resources in the stack
        """
        Tags.of(self).add("Project", "IoTTimeSeries")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Solution", "TimeSeriesDataAnalytics")
        Tags.of(self).add("ManagedBy", "CDK")


class TimestreamApp(cdk.App):
    """
    CDK Application for Amazon Timestream Time-Series Data Solution
    """

    def __init__(self):
        super().__init__()

        # Create the main stack
        TimestreamTimeSeriesStack(
            self, "TimestreamTimeSeriesStack",
            description="Amazon Timestream Time-Series Data Solution - Complete IoT data ingestion and analytics platform",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


# Create and run the application
app = TimestreamApp()
app.synth()