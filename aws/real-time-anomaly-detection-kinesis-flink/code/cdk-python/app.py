#!/usr/bin/env python3
"""
AWS CDK Python application for Real-time Anomaly Detection with Kinesis Data Analytics.

This application deploys infrastructure for real-time anomaly detection using:
- Amazon Kinesis Data Streams for data ingestion
- AWS Managed Service for Apache Flink for stream processing
- AWS Lambda for anomaly alert processing
- Amazon SNS for notifications
- Amazon CloudWatch for monitoring
- Amazon S3 for application artifacts and data storage

The solution analyzes streaming transaction data to detect unusual patterns
and send real-time alerts for potential fraud or system anomalies.
"""

import os
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    Duration,
    RemovalPolicy,
    aws_kinesis as kinesis,
    aws_kinesisanalytics as kinesisanalytics,
    aws_lambda as lambda_,
    aws_sns as sns,
    aws_sns_subscriptions as subscriptions,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
    aws_iam as iam,
    aws_cloudwatch as cloudwatch,
    aws_cloudwatch_actions as cloudwatch_actions,
    aws_logs as logs,
    CfnOutput,
)
from constructs import Construct


class AnomalyDetectionStack(Stack):
    """
    CDK Stack for Real-time Anomaly Detection infrastructure.
    
    This stack creates all the necessary AWS resources for a production-ready
    anomaly detection system using Kinesis Data Analytics and Apache Flink.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 bucket for application artifacts and data storage
        self.artifacts_bucket = s3.Bucket(
            self,
            "ArtifactsBucket",
            bucket_name=f"anomaly-detection-artifacts-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Create Kinesis Data Stream for transaction ingestion
        self.transaction_stream = kinesis.Stream(
            self,
            "TransactionStream",
            stream_name=f"transaction-stream-{unique_suffix}",
            shard_count=2,  # 2 shards for moderate throughput
            retention_period=Duration.hours(24),  # Retain data for 24 hours
        )

        # Create SNS topic for anomaly alerts
        self.alerts_topic = sns.Topic(
            self,
            "AlertsTopic",
            topic_name=f"anomaly-alerts-{unique_suffix}",
            display_name="Real-time Anomaly Detection Alerts",
        )

        # Create Lambda function for anomaly processing
        self.anomaly_processor = self._create_anomaly_processor_lambda()

        # Create IAM role for Managed Service for Apache Flink
        self.flink_execution_role = self._create_flink_execution_role()

        # Create Managed Service for Apache Flink application
        self.flink_application = self._create_flink_application()

        # Create CloudWatch monitoring and alarms
        self._create_cloudwatch_monitoring()

        # Create outputs for easy access to resource identifiers
        self._create_outputs()

    def _create_anomaly_processor_lambda(self) -> lambda_.Function:
        """
        Creates the Lambda function for processing anomaly alerts.
        
        This function receives anomaly notifications, enriches them with context,
        publishes metrics to CloudWatch, and sends notifications via SNS.
        
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create IAM role for Lambda function
        lambda_role = iam.Role(
            self,
            "AnomalyProcessorRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
        )

        # Add permissions for CloudWatch and SNS
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "sns:Publish",
                ],
                resources=[
                    f"arn:aws:cloudwatch:{self.region}:{self.account}:*",
                    self.alerts_topic.topic_arn,
                ],
            )
        )

        # Create Lambda function
        function = lambda_.Function(
            self,
            "AnomalyProcessor",
            function_name=f"anomaly-processor-{self.node.addr[-8:].lower()}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(60),
            environment={
                "SNS_TOPIC_ARN": self.alerts_topic.topic_arn,
                "CLOUDWATCH_NAMESPACE": "AnomalyDetection",
            },
            role=lambda_role,
            description="Processes anomaly detection alerts and sends notifications",
        )

        return function

    def _get_lambda_code(self) -> str:
        """
        Returns the Python code for the Lambda function.
        
        Returns:
            str: The Lambda function code as a string
        """
        return """
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any, List

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    '''
    Lambda function to process anomaly detection alerts.
    
    This function receives anomaly notifications, publishes metrics to CloudWatch,
    and sends notifications via SNS for immediate alerting.
    
    Args:
        event: Lambda event containing anomaly data
        context: Lambda runtime context
        
    Returns:
        Dict containing status code and response message
    '''
    # Initialize AWS clients
    cloudwatch = boto3.client('cloudwatch')
    sns = boto3.client('sns')
    
    # Get environment variables
    sns_topic_arn = os.environ['SNS_TOPIC_ARN']
    namespace = os.environ['CLOUDWATCH_NAMESPACE']
    
    processed_count = 0
    
    try:
        # Process each record in the event
        records = event.get('Records', [])
        
        for record in records:
            # Extract anomaly information
            message_body = record.get('body', '')
            
            # Check if this is an anomaly alert
            if 'ANOMALY DETECTED' in message_body:
                # Parse anomaly details
                anomaly_data = parse_anomaly_message(message_body)
                
                # Send custom metric to CloudWatch
                put_anomaly_metric(cloudwatch, namespace, anomaly_data)
                
                # Send notification via SNS
                send_sns_notification(sns, sns_topic_arn, anomaly_data)
                
                processed_count += 1
                
                print(f"Processed anomaly: {anomaly_data}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {processed_count} anomalies',
                'processed_count': processed_count
            })
        }
        
    except Exception as e:
        print(f"Error processing anomalies: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'message': 'Failed to process anomalies'
            })
        }

def parse_anomaly_message(message: str) -> Dict[str, Any]:
    '''
    Parse anomaly message to extract structured data.
    
    Args:
        message: Raw anomaly message string
        
    Returns:
        Dict containing parsed anomaly data
    '''
    # Simple parser for demo - in production, use structured JSON
    parts = message.split()
    
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'message': message,
        'severity': 'HIGH' if 'CRITICAL' in message else 'MEDIUM',
        'source': 'Kinesis Data Analytics'
    }

def put_anomaly_metric(cloudwatch: Any, namespace: str, anomaly_data: Dict[str, Any]) -> None:
    '''
    Send anomaly metrics to CloudWatch.
    
    Args:
        cloudwatch: CloudWatch client
        namespace: CloudWatch namespace
        anomaly_data: Parsed anomaly data
    '''
    cloudwatch.put_metric_data(
        Namespace=namespace,
        MetricData=[
            {
                'MetricName': 'AnomalyCount',
                'Value': 1,
                'Unit': 'Count',
                'Timestamp': datetime.utcnow(),
                'Dimensions': [
                    {
                        'Name': 'Severity',
                        'Value': anomaly_data.get('severity', 'UNKNOWN')
                    }
                ]
            }
        ]
    )

def send_sns_notification(sns: Any, topic_arn: str, anomaly_data: Dict[str, Any]) -> None:
    '''
    Send anomaly notification via SNS.
    
    Args:
        sns: SNS client
        topic_arn: SNS topic ARN
        anomaly_data: Parsed anomaly data
    '''
    subject = f"Anomaly Detected - {anomaly_data.get('severity', 'UNKNOWN')} Severity"
    message = f\"\"\"
Anomaly Detection Alert

Timestamp: {anomaly_data.get('timestamp')}
Severity: {anomaly_data.get('severity')}
Source: {anomaly_data.get('source')}

Details:
{anomaly_data.get('message')}

This is an automated alert from the real-time anomaly detection system.
Please investigate and take appropriate action if necessary.
\"\"\"
    
    sns.publish(
        TopicArn=topic_arn,
        Message=message,
        Subject=subject
    )
"""

    def _create_flink_execution_role(self) -> iam.Role:
        """
        Creates the IAM role for Managed Service for Apache Flink execution.
        
        This role allows the Flink application to read from Kinesis streams,
        write to CloudWatch, and access S3 for application artifacts.
        
        Returns:
            iam.Role: The created execution role
        """
        role = iam.Role(
            self,
            "FlinkExecutionRole",
            role_name=f"FlinkAnomalyDetectionRole-{self.node.addr[-8:].lower()}",
            assumed_by=iam.ServicePrincipal("kinesisanalytics.amazonaws.com"),
            description="Execution role for Managed Service for Apache Flink anomaly detection application",
        )

        # Add permissions for Kinesis Data Streams
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:GetShardIterator",
                    "kinesis:GetRecords",
                    "kinesis:ListShards",
                ],
                resources=[self.transaction_stream.stream_arn],
            )
        )

        # Add permissions for CloudWatch metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["cloudwatch:PutMetricData"],
                resources=["*"],
            )
        )

        # Add permissions for S3 access (application artifacts)
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:GetObject", "s3:PutObject"],
                resources=[f"{self.artifacts_bucket.bucket_arn}/*"],
            )
        )

        # Add permissions for VPC configuration (if needed)
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "ec2:CreateNetworkInterface",
                    "ec2:DescribeNetworkInterfaces",
                    "ec2:DeleteNetworkInterface",
                    "ec2:AttachNetworkInterface",
                    "ec2:DetachNetworkInterface",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_flink_application(self) -> kinesisanalytics.CfnApplicationV2:
        """
        Creates the Managed Service for Apache Flink application.
        
        This application processes streaming transaction data and detects anomalies
        using statistical analysis and windowing functions.
        
        Returns:
            kinesisanalytics.CfnApplicationV2: The created Flink application
        """
        # Create the Flink application configuration
        application = kinesisanalytics.CfnApplicationV2(
            self,
            "AnomalyDetectionApp",
            application_name=f"anomaly-detector-{self.node.addr[-8:].lower()}",
            application_description="Real-time anomaly detection for transaction data using Apache Flink",
            runtime_environment="FLINK-1_17",
            service_execution_role=self.flink_execution_role.role_arn,
            application_configuration=kinesisanalytics.CfnApplicationV2.ApplicationConfigurationProperty(
                application_code_configuration=kinesisanalytics.CfnApplicationV2.ApplicationCodeConfigurationProperty(
                    code_content=kinesisanalytics.CfnApplicationV2.CodeContentProperty(
                        s3_content_location=kinesisanalytics.CfnApplicationV2.S3ContentLocationProperty(
                            bucket_arn=self.artifacts_bucket.bucket_arn,
                            file_key="applications/anomaly-detection-1.0-SNAPSHOT.jar",
                        )
                    ),
                    code_content_type="ZIPFILE",
                ),
                environment_properties=kinesisanalytics.CfnApplicationV2.EnvironmentPropertiesProperty(
                    property_groups=[
                        kinesisanalytics.CfnApplicationV2.PropertyGroupProperty(
                            property_group_id="kinesis.analytics.flink.run.options",
                            property_map={
                                "python.fn-execution.bundle.size": "1000",
                                "python.fn-execution.bundle.time": "1000",
                            },
                        )
                    ]
                ),
                flink_application_configuration=kinesisanalytics.CfnApplicationV2.FlinkApplicationConfigurationProperty(
                    checkpoint_configuration=kinesisanalytics.CfnApplicationV2.CheckpointConfigurationProperty(
                        configuration_type="CUSTOM",
                        checkpointing_enabled=True,
                        checkpoint_interval=60000,  # 60 seconds
                        min_pause_between_checkpoints=5000,  # 5 seconds
                    ),
                    monitoring_configuration=kinesisanalytics.CfnApplicationV2.MonitoringConfigurationProperty(
                        configuration_type="CUSTOM",
                        log_level="INFO",
                        metrics_level="APPLICATION",
                    ),
                    parallelism_configuration=kinesisanalytics.CfnApplicationV2.ParallelismConfigurationProperty(
                        configuration_type="CUSTOM",
                        parallelism=2,
                        parallelism_per_kpu=1,
                    ),
                ),
            ),
        )

        return application

    def _create_cloudwatch_monitoring(self) -> None:
        """
        Creates CloudWatch monitoring and alarms for the anomaly detection system.
        
        This includes anomaly detectors for automatic threshold detection and
        alarms for immediate notification when anomalies exceed expected levels.
        """
        # Create CloudWatch anomaly detector
        anomaly_detector = cloudwatch.CfnAnomalyDetector(
            self,
            "AnomalyDetector",
            namespace="AnomalyDetection",
            metric_name="AnomalyCount",
            stat="Sum",
            dimensions=[
                cloudwatch.CfnAnomalyDetector.DimensionProperty(
                    name="Source", value="FlinkApp"
                )
            ],
        )

        # Create CloudWatch alarm for anomaly detection
        anomaly_alarm = cloudwatch.Alarm(
            self,
            "AnomalyDetectionAlarm",
            alarm_name=f"AnomalyDetectionAlarm-{self.node.addr[-8:].lower()}",
            alarm_description="Alarm triggered when anomaly detection rate exceeds normal patterns",
            metric=cloudwatch.Metric(
                namespace="AnomalyDetection",
                metric_name="AnomalyCount",
                dimensions_map={"Source": "FlinkApp"},
                statistic="Sum",
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
            evaluation_periods=1,
            period=Duration.minutes(5),
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING,
        )

        # Add SNS notification to the alarm
        anomaly_alarm.add_alarm_action(
            cloudwatch_actions.SnsAction(self.alerts_topic)
        )

        # Create dashboard for monitoring
        dashboard = cloudwatch.Dashboard(
            self,
            "AnomalyDetectionDashboard",
            dashboard_name=f"AnomalyDetection-{self.node.addr[-8:].lower()}",
        )

        # Add widgets to dashboard
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Anomaly Detection Rate",
                left=[
                    cloudwatch.Metric(
                        namespace="AnomalyDetection",
                        metric_name="AnomalyCount",
                        statistic="Sum",
                    )
                ],
                period=Duration.minutes(5),
                width=12,
                height=6,
            ),
            cloudwatch.GraphWidget(
                title="Kinesis Stream Metrics",
                left=[
                    self.transaction_stream.metric_incoming_records(),
                    self.transaction_stream.metric_incoming_bytes(),
                ],
                period=Duration.minutes(5),
                width=12,
                height=6,
            ),
        )

    def _create_outputs(self) -> None:
        """
        Creates CloudFormation outputs for important resource identifiers.
        
        These outputs make it easy to reference the created resources from
        other stacks or for manual testing and verification.
        """
        CfnOutput(
            self,
            "TransactionStreamName",
            value=self.transaction_stream.stream_name,
            description="Name of the Kinesis Data Stream for transaction ingestion",
            export_name=f"{self.stack_name}-TransactionStreamName",
        )

        CfnOutput(
            self,
            "TransactionStreamArn",
            value=self.transaction_stream.stream_arn,
            description="ARN of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-TransactionStreamArn",
        )

        CfnOutput(
            self,
            "FlinkApplicationName",
            value=self.flink_application.application_name,
            description="Name of the Managed Service for Apache Flink application",
            export_name=f"{self.stack_name}-FlinkApplicationName",
        )

        CfnOutput(
            self,
            "AlertsTopicArn",
            value=self.alerts_topic.topic_arn,
            description="ARN of the SNS topic for anomaly alerts",
            export_name=f"{self.stack_name}-AlertsTopicArn",
        )

        CfnOutput(
            self,
            "ArtifactsBucketName",
            value=self.artifacts_bucket.bucket_name,
            description="Name of the S3 bucket for application artifacts",
            export_name=f"{self.stack_name}-ArtifactsBucketName",
        )

        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.anomaly_processor.function_name,
            description="Name of the Lambda function for anomaly processing",
            export_name=f"{self.stack_name}-LambdaFunctionName",
        )


def main() -> None:
    """
    Main function to create and deploy the CDK application.
    
    This function creates the CDK app and adds the anomaly detection stack
    with appropriate environment configuration.
    """
    app = App()

    # Get environment from context or use defaults
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
    )

    # Create the anomaly detection stack
    AnomalyDetectionStack(
        app,
        "AnomalyDetectionStack",
        env=env,
        description="Real-time Anomaly Detection with Kinesis Data Analytics and Apache Flink",
        tags={
            "Project": "AnomalyDetection",
            "Environment": "Development",
            "Owner": "DataEngineering",
            "CostCenter": "Analytics",
        },
    )

    app.synth()


if __name__ == "__main__":
    main()