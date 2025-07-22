#!/usr/bin/env python3
"""
CDK Python Application for Real-Time IoT Analytics with Kinesis and Managed Service for Apache Flink

This application deploys a complete IoT analytics pipeline including:
- Kinesis Data Streams for data ingestion
- Lambda functions for event processing
- Managed Service for Apache Flink for stream analytics
- S3 buckets for data storage
- SNS topics for alerting
- CloudWatch monitoring and dashboards
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnParameter,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_kinesis as kinesis,
    aws_lambda as lambda_,
    aws_lambda_event_sources as lambda_event_sources,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_iam as iam,
    aws_kinesisanalyticsv2 as kinesisanalytics,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from typing import Dict, Any
from constructs import Construct


class IoTAnalyticsStack(Stack):
    """
    CDK Stack for Real-Time IoT Analytics Pipeline
    
    Creates a complete IoT analytics infrastructure with:
    - Kinesis Data Streams for high-throughput data ingestion
    - Lambda functions for event-driven processing and anomaly detection
    - Managed Service for Apache Flink for stream processing
    - S3 buckets for data storage with organized folder structure
    - SNS topics for real-time alerting
    - CloudWatch monitoring and dashboards
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.email_address = CfnParameter(
            self,
            "EmailAddress",
            type="String",
            description="Email address for IoT analytics alerts",
            constraint_description="Must be a valid email address",
        )

        self.project_name = CfnParameter(
            self,
            "ProjectName",
            type="String",
            default="iot-analytics",
            description="Project name for resource naming",
            constraint_description="Must be a valid project name",
        )

        # Create core infrastructure
        self.data_bucket = self._create_s3_bucket()
        self.kinesis_stream = self._create_kinesis_stream()
        self.sns_topic = self._create_sns_topic()
        self.lambda_function = self._create_lambda_function()
        self.flink_application = self._create_flink_application()
        self.monitoring_dashboard = self._create_monitoring_dashboard()

        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for IoT data storage with organized folder structure
        
        Returns:
            S3 bucket with versioning and lifecycle policies
        """
        bucket = s3.Bucket(
            self,
            "IoTDataBucket",
            bucket_name=f"{self.project_name.value_as_string}-data-{self.account}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="iot-data-lifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                ),
            ],
        )

        # Create folder structure using deployment resources
        for folder in ["raw-data/", "processed-data/", "analytics-results/"]:
            cdk.CustomResource(
                self,
                f"CreateFolder{folder.replace('/', '').replace('-', '').title()}",
                service_token=cdk.CustomResourceProvider.get_or_create_provider(
                    self,
                    "CreateS3Folders",
                    code_directory=os.path.join(os.path.dirname(__file__), "custom-resources"),
                    runtime=lambda_.Runtime.PYTHON_3_11,
                    handler="s3_folder_handler.handler",
                ).service_token,
                properties={
                    "BucketName": bucket.bucket_name,
                    "FolderName": folder,
                },
            )

        return bucket

    def _create_kinesis_stream(self) -> kinesis.Stream:
        """
        Create Kinesis Data Stream for IoT data ingestion
        
        Returns:
            Kinesis stream with appropriate shard configuration
        """
        stream = kinesis.Stream(
            self,
            "IoTKinesisStream",
            stream_name=f"{self.project_name.value_as_string}-stream",
            shard_count=2,
            retention_period=Duration.days(7),
            stream_mode=kinesis.StreamMode.PROVISIONED,
        )

        return stream

    def _create_sns_topic(self) -> sns.Topic:
        """
        Create SNS topic for IoT analytics alerts
        
        Returns:
            SNS topic with email subscription
        """
        topic = sns.Topic(
            self,
            "IoTAlertsTopic",
            topic_name=f"{self.project_name.value_as_string}-alerts",
            display_name="IoT Analytics Alerts",
        )

        # Add email subscription
        topic.add_subscription(
            sns_subscriptions.EmailSubscription(
                email_address=self.email_address.value_as_string
            )
        )

        return topic

    def _create_lambda_function(self) -> lambda_.Function:
        """
        Create Lambda function for IoT data processing and anomaly detection
        
        Returns:
            Lambda function with Kinesis event source mapping
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "IoTLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "IoTLambdaPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetRecords",
                                "kinesis:GetShardIterator",
                                "kinesis:ListStreams",
                            ],
                            resources=[self.kinesis_stream.stream_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["s3:PutObject", "s3:GetObject"],
                            resources=[f"{self.data_bucket.bucket_arn}/*"],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=["sns:Publish"],
                            resources=[self.sns_topic.topic_arn],
                        ),
                    ]
                )
            },
        )

        # Create Lambda function
        lambda_function = lambda_.Function(
            self,
            "IoTProcessorFunction",
            function_name=f"{self.project_name.value_as_string}-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            role=lambda_role,
            timeout=Duration.seconds(60),
            memory_size=256,
            environment={
                "S3_BUCKET_NAME": self.data_bucket.bucket_name,
                "SNS_TOPIC_ARN": self.sns_topic.topic_arn,
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
        )

        # Create event source mapping
        lambda_function.add_event_source(
            lambda_event_sources.KinesisEventSource(
                stream=self.kinesis_stream,
                starting_position=lambda_.StartingPosition.LATEST,
                batch_size=10,
                max_batching_window=Duration.seconds(5),
            )
        )

        return lambda_function

    def _create_flink_application(self) -> kinesisanalytics.CfnApplicationV2:
        """
        Create Managed Service for Apache Flink application for stream analytics
        
        Returns:
            Flink application for real-time analytics
        """
        # Create IAM role for Flink application
        flink_role = iam.Role(
            self,
            "FlinkApplicationRole",
            assumed_by=iam.ServicePrincipal("kinesisanalytics.amazonaws.com"),
            inline_policies={
                "FlinkApplicationPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetRecords",
                                "kinesis:GetShardIterator",
                                "kinesis:ListStreams",
                            ],
                            resources=[self.kinesis_stream.stream_arn],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:GetObject",
                                "s3:ListBucket",
                            ],
                            resources=[
                                self.data_bucket.bucket_arn,
                                f"{self.data_bucket.bucket_arn}/*",
                            ],
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents",
                            ],
                            resources=["arn:aws:logs:*:*:*"],
                        ),
                    ]
                )
            },
        )

        # Create Flink application
        flink_app = kinesisanalytics.CfnApplicationV2(
            self,
            "FlinkApplication",
            application_name=f"{self.project_name.value_as_string}-flink-app",
            runtime_environment="FLINK-1_18",
            service_execution_role=flink_role.role_arn,
            application_configuration=kinesisanalytics.CfnApplicationV2.ApplicationConfigurationProperty(
                application_code_configuration=kinesisanalytics.CfnApplicationV2.ApplicationCodeConfigurationProperty(
                    code_content=kinesisanalytics.CfnApplicationV2.CodeContentProperty(
                        text_content=self._get_flink_code()
                    ),
                    code_content_type="PLAINTEXT",
                ),
                environment_properties=kinesisanalytics.CfnApplicationV2.EnvironmentPropertiesProperty(
                    property_groups=[
                        kinesisanalytics.CfnApplicationV2.PropertyGroupProperty(
                            property_group_id="kinesis.analytics.flink.run.options",
                            property_map={
                                "python": "main.py",
                                "jarfile": "flink-python-runtime.jar",
                            },
                        )
                    ]
                ),
                flink_application_configuration=kinesisanalytics.CfnApplicationV2.FlinkApplicationConfigurationProperty(
                    checkpoint_configuration=kinesisanalytics.CfnApplicationV2.CheckpointConfigurationProperty(
                        configuration_type="DEFAULT"
                    ),
                    monitoring_configuration=kinesisanalytics.CfnApplicationV2.MonitoringConfigurationProperty(
                        configuration_type="DEFAULT",
                        log_level="INFO",
                        metrics_level="APPLICATION",
                    ),
                    parallelism_configuration=kinesisanalytics.CfnApplicationV2.ParallelismConfigurationProperty(
                        configuration_type="DEFAULT",
                        parallelism=1,
                        parallelism_per_kpu=1,
                    ),
                ),
            ),
        )

        return flink_app

    def _create_monitoring_dashboard(self) -> cloudwatch.Dashboard:
        """
        Create CloudWatch dashboard for monitoring IoT analytics pipeline
        
        Returns:
            CloudWatch dashboard with key metrics
        """
        dashboard = cloudwatch.Dashboard(
            self,
            "IoTAnalyticsDashboard",
            dashboard_name=f"{self.project_name.value_as_string}-analytics",
        )

        # Kinesis metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Kinesis Stream Metrics",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Kinesis",
                        metric_name="IncomingRecords",
                        dimensions_map={"StreamName": self.kinesis_stream.stream_name},
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Kinesis",
                        metric_name="OutgoingRecords",
                        dimensions_map={"StreamName": self.kinesis_stream.stream_name},
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
            ),
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                width=12,
                height=6,
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Invocations",
                        dimensions_map={"FunctionName": self.lambda_function.function_name},
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Errors",
                        dimensions_map={"FunctionName": self.lambda_function.function_name},
                        statistic="Sum",
                        period=Duration.minutes(5),
                    ),
                ],
            ),
        )

        # Create CloudWatch alarms
        self._create_cloudwatch_alarms()

        return dashboard

    def _create_cloudwatch_alarms(self) -> None:
        """Create CloudWatch alarms for monitoring critical metrics"""
        # Kinesis stream alarm
        kinesis_alarm = cloudwatch.Alarm(
            self,
            "KinesisRecordsAlarm",
            alarm_name=f"{self.project_name.value_as_string}-kinesis-records",
            alarm_description="Monitor Kinesis stream incoming records",
            metric=cloudwatch.Metric(
                namespace="AWS/Kinesis",
                metric_name="IncomingRecords",
                dimensions_map={"StreamName": self.kinesis_stream.stream_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=100,
            evaluation_periods=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Lambda errors alarm
        lambda_alarm = cloudwatch.Alarm(
            self,
            "LambdaErrorsAlarm",
            alarm_name=f"{self.project_name.value_as_string}-lambda-errors",
            alarm_description="Monitor Lambda function errors",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={"FunctionName": self.lambda_function.function_name},
                statistic="Sum",
                period=Duration.minutes(5),
            ),
            threshold=5,
            evaluation_periods=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
        )

        # Add SNS actions to alarms
        kinesis_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )
        lambda_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.sns_topic)
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "KinesisStreamName",
            value=self.kinesis_stream.stream_name,
            description="Name of the Kinesis Data Stream",
        )

        CfnOutput(
            self,
            "KinesisStreamArn",
            value=self.kinesis_stream.stream_arn,
            description="ARN of the Kinesis Data Stream",
        )

        CfnOutput(
            self,
            "S3BucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket for data storage",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Name of the Lambda function for data processing",
        )

        CfnOutput(
            self,
            "SNSTopicArn",
            value=self.sns_topic.topic_arn,
            description="ARN of the SNS topic for alerts",
        )

        CfnOutput(
            self,
            "FlinkApplicationName",
            value=self.flink_application.application_name,
            description="Name of the Flink application for stream analytics",
        )

        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://{self.region}.console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.project_name.value_as_string}-analytics",
            description="URL to the CloudWatch dashboard",
        )

    def _get_lambda_code(self) -> str:
        """
        Get the Lambda function code for IoT data processing
        
        Returns:
            Lambda function code as string
        """
        return '''
import json
import boto3
import base64
from datetime import datetime
import os

s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Process IoT data from Kinesis stream
    - Decode and process sensor data
    - Store raw data in S3
    - Detect anomalies and send alerts
    """
    bucket_name = os.environ['S3_BUCKET_NAME']
    topic_arn = os.environ['SNS_TOPIC_ARN']
    
    processed_records = []
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data']).decode('utf-8')
            data = json.loads(payload)
            
            # Process the IoT data
            processed_data = process_iot_data(data)
            processed_records.append(processed_data)
            
            # Store raw data in S3
            timestamp = datetime.now().strftime('%Y/%m/%d/%H')
            key = f"raw-data/{timestamp}/{record['kinesis']['sequenceNumber']}.json"
            
            s3.put_object(
                Bucket=bucket_name,
                Key=key,
                Body=json.dumps(data),
                ContentType='application/json'
            )
            
            # Check for anomalies and send alerts
            if is_anomaly(processed_data):
                send_alert(processed_data, topic_arn)
                
        except Exception as e:
            print(f"Error processing record: {e}")
            continue
    
    return {
        'statusCode': 200,
        'body': json.dumps(f'Successfully processed {len(processed_records)} records')
    }

def process_iot_data(data):
    """Process and enrich IoT sensor data"""
    return {
        'device_id': data.get('device_id', 'unknown'),
        'timestamp': data.get('timestamp', datetime.now().isoformat()),
        'sensor_type': data.get('sensor_type', 'unknown'),
        'value': data.get('value', 0),
        'unit': data.get('unit', 'unknown'),
        'location': data.get('location', 'unknown'),
        'processed_at': datetime.now().isoformat()
    }

def is_anomaly(data):
    """Simple rule-based anomaly detection"""
    value = float(data.get('value', 0))
    sensor_type = data.get('sensor_type', '')
    
    # Threshold-based anomaly detection
    thresholds = {
        'temperature': 80,
        'pressure': 100,
        'vibration': 50,
        'flow': 200
    }
    
    threshold = thresholds.get(sensor_type, 1000)
    return value > threshold

def send_alert(data, topic_arn):
    """Send anomaly alert via SNS"""
    message = (
        f"ALERT: Anomaly detected in {data['sensor_type']} sensor {data['device_id']}. "
        f"Value: {data['value']} {data['unit']} at {data['location']}"
    )
    
    try:
        sns.publish(
            TopicArn=topic_arn,
            Message=message,
            Subject="IoT Sensor Anomaly Alert"
        )
    except Exception as e:
        print(f"Error sending alert: {e}")
'''

    def _get_flink_code(self) -> str:
        """
        Get the Flink application code for stream analytics
        
        Returns:
            Flink application code as string
        """
        return '''
from pyflink.table import EnvironmentSettings, TableEnvironment
from pyflink.common import Configuration
import os

def create_iot_analytics_job():
    """
    Create Flink job for IoT analytics with windowed aggregations
    """
    # Set up the execution environment
    config = Configuration()
    config.set_string("execution.checkpointing.interval", "60s")
    config.set_string("execution.checkpointing.mode", "EXACTLY_ONCE")
    
    env_settings = EnvironmentSettings.new_instance().in_streaming_mode().with_configuration(config).build()
    table_env = TableEnvironment.create(env_settings)
    
    # Define source table from Kinesis
    source_ddl = f"""
    CREATE TABLE iot_source (
        device_id STRING,
        timestamp TIMESTAMP(3),
        sensor_type STRING,
        value DOUBLE,
        unit STRING,
        location STRING,
        WATERMARK FOR timestamp AS timestamp - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kinesis',
        'stream' = '{os.environ.get('KINESIS_STREAM_NAME', 'iot-analytics-stream')}',
        'aws.region' = '{os.environ.get('AWS_REGION', 'us-east-1')}',
        'format' = 'json',
        'scan.stream.initpos' = 'LATEST'
    )
    """
    
    # Define sink table to S3
    sink_ddl = f"""
    CREATE TABLE iot_analytics_sink (
        device_id STRING,
        sensor_type STRING,
        location STRING,
        avg_value DOUBLE,
        max_value DOUBLE,
        min_value DOUBLE,
        record_count BIGINT,
        window_start TIMESTAMP(3),
        window_end TIMESTAMP(3)
    ) WITH (
        'connector' = 's3',
        'path' = 's3://{os.environ.get('S3_BUCKET_NAME', 'iot-analytics-bucket')}/analytics-results/',
        'format' = 'json',
        'sink.rolling-policy.file-size' = '128MB',
        'sink.rolling-policy.rollover-interval' = '30min'
    )
    """
    
    # Create tables
    table_env.execute_sql(source_ddl)
    table_env.execute_sql(sink_ddl)
    
    # Define analytics query with 5-minute tumbling windows
    analytics_query = """
    INSERT INTO iot_analytics_sink
    SELECT 
        device_id,
        sensor_type,
        location,
        AVG(value) as avg_value,
        MAX(value) as max_value,
        MIN(value) as min_value,
        COUNT(*) as record_count,
        TUMBLE_START(timestamp, INTERVAL '5' MINUTE) as window_start,
        TUMBLE_END(timestamp, INTERVAL '5' MINUTE) as window_end
    FROM iot_source
    WHERE value IS NOT NULL
    GROUP BY 
        device_id,
        sensor_type,
        location,
        TUMBLE(timestamp, INTERVAL '5' MINUTE)
    """
    
    # Execute the analytics query
    table_env.execute_sql(analytics_query)

if __name__ == "__main__":
    create_iot_analytics_job()
'''


def main() -> None:
    """Main application entry point"""
    app = cdk.App()
    
    # Get environment variables or use defaults
    account = os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    
    # Create the stack
    IoTAnalyticsStack(
        app,
        "IoTAnalyticsStack",
        env=cdk.Environment(account=account, region=region),
        description="Real-Time IoT Analytics Pipeline with Kinesis and Managed Service for Apache Flink",
    )
    
    # Add tags to all resources
    cdk.Tags.of(app).add("Project", "IoT-Analytics")
    cdk.Tags.of(app).add("Environment", "Production")
    cdk.Tags.of(app).add("ManagedBy", "CDK")
    
    app.synth()


if __name__ == "__main__":
    main()