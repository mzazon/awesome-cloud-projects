#!/usr/bin/env python3
"""
CDK Application for Real-time Analytics Dashboards
This application creates a real-time analytics pipeline using:
- Amazon Kinesis Data Streams for data ingestion
- Amazon Managed Service for Apache Flink for stream processing
- Amazon S3 for processed data storage
- IAM roles and policies for secure service integration
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_kinesis as kinesis,
    aws_s3 as s3,
    aws_iam as iam,
    aws_kinesisanalytics as kinesisanalytics,
    aws_logs as logs,
    CfnOutput,
    RemovalPolicy,
    Duration
)
from constructs import Construct
import json
from typing import Dict, Any


class RealTimeAnalyticsStack(Stack):
    """
    CDK Stack for Real-time Analytics Dashboard Infrastructure
    
    This stack creates all the necessary AWS resources for building
    real-time analytics dashboards with Kinesis Analytics and QuickSight.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()

        # Create S3 bucket for processed analytics data
        self.analytics_bucket = s3.Bucket(
            self, "AnalyticsBucket",
            bucket_name=f"analytics-results-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldData",
                    enabled=True,
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Create S3 bucket for Flink application code
        self.flink_code_bucket = s3.Bucket(
            self, "FlinkCodeBucket",
            bucket_name=f"flink-code-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Create Kinesis Data Stream for data ingestion
        self.data_stream = kinesis.Stream(
            self, "DataStream",
            stream_name=f"analytics-stream-{unique_suffix}",
            shard_count=2,
            retention_period=Duration.hours(24),
            encryption=kinesis.StreamEncryption.KMS
        )

        # Create CloudWatch Log Group for Flink application
        self.flink_log_group = logs.LogGroup(
            self, "FlinkLogGroup",
            log_group_name=f"/aws/kinesis-analytics/analytics-app-{unique_suffix}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create IAM role for Managed Service for Apache Flink
        self.flink_execution_role = self._create_flink_execution_role()

        # Create Managed Service for Apache Flink application
        self.flink_application = self._create_flink_application(unique_suffix)

        # Create outputs for reference
        self._create_outputs()

    def _create_flink_execution_role(self) -> iam.Role:
        """
        Create IAM role for Managed Service for Apache Flink execution
        
        Returns:
            iam.Role: The IAM role with necessary permissions
        """
        # Create the execution role
        role = iam.Role(
            self, "FlinkExecutionRole",
            role_name=f"FlinkAnalyticsRole-{self.node.addr[-8:].lower()}",
            assumed_by=iam.ServicePrincipal("kinesisanalytics.amazonaws.com"),
            description="Execution role for Managed Service for Apache Flink application"
        )

        # Add permissions for Kinesis Data Streams
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:DescribeStream",
                    "kinesis:GetShardIterator",
                    "kinesis:GetRecords",
                    "kinesis:ListShards"
                ],
                resources=[self.data_stream.stream_arn]
            )
        )

        # Add permissions for S3 buckets
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject"
                ],
                resources=[
                    f"{self.analytics_bucket.bucket_arn}/*",
                    f"{self.flink_code_bucket.bucket_arn}/*"
                ]
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["s3:ListBucket"],
                resources=[
                    self.analytics_bucket.bucket_arn,
                    self.flink_code_bucket.bucket_arn
                ]
            )
        )

        # Add permissions for CloudWatch Logs
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                    "logs:DescribeLogGroups",
                    "logs:DescribeLogStreams"
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws/kinesis-analytics/*"
                ]
            )
        )

        # Add permissions for CloudWatch metrics
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData"
                ],
                resources=["*"],
                conditions={
                    "StringEquals": {
                        "cloudwatch:namespace": "AWS/KinesisAnalytics"
                    }
                }
            )
        )

        return role

    def _create_flink_application(self, unique_suffix: str) -> kinesisanalytics.CfnApplication:
        """
        Create Managed Service for Apache Flink application
        
        Args:
            unique_suffix: Unique suffix for resource naming
            
        Returns:
            kinesisanalytics.CfnApplication: The Flink application
        """
        # Define application configuration
        application_config = {
            "ApplicationCodeConfiguration": {
                "CodeContent": {
                    "S3ContentLocation": {
                        "BucketARN": self.flink_code_bucket.bucket_arn,
                        "FileKey": "flink-analytics-app-1.0.jar"
                    }
                },
                "CodeContentType": "ZIPFILE"
            },
            "EnvironmentProperties": {
                "PropertyGroups": [
                    {
                        "PropertyGroupId": "kinesis.analytics.flink.run.options",
                        "PropertyMap": {
                            "input.stream.name": self.data_stream.stream_name,
                            "aws.region": self.region,
                            "s3.path": f"s3://{self.analytics_bucket.bucket_name}/analytics-results/"
                        }
                    }
                ]
            },
            "FlinkApplicationConfiguration": {
                "CheckpointConfiguration": {
                    "ConfigurationType": "DEFAULT"
                },
                "MonitoringConfiguration": {
                    "ConfigurationType": "CUSTOM",
                    "LogLevel": "INFO",
                    "MetricsLevel": "APPLICATION"
                },
                "ParallelismConfiguration": {
                    "ConfigurationType": "CUSTOM",
                    "Parallelism": 1,
                    "ParallelismPerKPU": 1,
                    "AutoScalingEnabled": True
                }
            }
        }

        # Create the Flink application
        flink_app = kinesisanalytics.CfnApplication(
            self, "FlinkApplication",
            application_name=f"analytics-app-{unique_suffix}",
            application_description="Real-time analytics application for streaming data processing",
            runtime_environment="FLINK-1_18",
            service_execution_role=self.flink_execution_role.role_arn,
            application_configuration=application_config
        )

        return flink_app

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for easy reference"""
        CfnOutput(
            self, "KinesisStreamName",
            value=self.data_stream.stream_name,
            description="Name of the Kinesis Data Stream for data ingestion",
            export_name=f"{self.stack_name}-KinesisStreamName"
        )

        CfnOutput(
            self, "KinesisStreamArn",
            value=self.data_stream.stream_arn,
            description="ARN of the Kinesis Data Stream",
            export_name=f"{self.stack_name}-KinesisStreamArn"
        )

        CfnOutput(
            self, "AnalyticsBucketName",
            value=self.analytics_bucket.bucket_name,
            description="Name of the S3 bucket containing processed analytics data",
            export_name=f"{self.stack_name}-AnalyticsBucketName"
        )

        CfnOutput(
            self, "AnalyticsBucketArn",
            value=self.analytics_bucket.bucket_arn,
            description="ARN of the S3 bucket for analytics data",
            export_name=f"{self.stack_name}-AnalyticsBucketArn"
        )

        CfnOutput(
            self, "FlinkCodeBucketName",
            value=self.flink_code_bucket.bucket_name,
            description="Name of the S3 bucket for Flink application code",
            export_name=f"{self.stack_name}-FlinkCodeBucketName"
        )

        CfnOutput(
            self, "FlinkApplicationName",
            value=self.flink_application.application_name,
            description="Name of the Managed Service for Apache Flink application",
            export_name=f"{self.stack_name}-FlinkApplicationName"
        )

        CfnOutput(
            self, "FlinkExecutionRoleArn",
            value=self.flink_execution_role.role_arn,
            description="ARN of the IAM role for Flink execution",
            export_name=f"{self.stack_name}-FlinkExecutionRoleArn"
        )

        CfnOutput(
            self, "QuickSightManifestLocation",
            value=f"s3://{self.analytics_bucket.bucket_name}/quicksight-manifest.json",
            description="S3 location for QuickSight manifest file",
            export_name=f"{self.stack_name}-QuickSightManifestLocation"
        )

        CfnOutput(
            self, "CloudWatchLogGroup",
            value=self.flink_log_group.log_group_name,
            description="CloudWatch Log Group for Flink application logs",
            export_name=f"{self.stack_name}-CloudWatchLogGroup"
        )


class RealTimeAnalyticsApp(cdk.App):
    """
    CDK Application for Real-time Analytics Dashboard
    """

    def __init__(self):
        super().__init__()

        # Create the main stack
        RealTimeAnalyticsStack(
            self, "RealTimeAnalyticsStack",
            description="Real-time Analytics Dashboard Infrastructure with Kinesis, Flink, and QuickSight",
            env=cdk.Environment(
                account=self.node.try_get_context("account"),
                region=self.node.try_get_context("region")
            )
        )


# Create and run the application
if __name__ == "__main__":
    app = RealTimeAnalyticsApp()
    app.synth()