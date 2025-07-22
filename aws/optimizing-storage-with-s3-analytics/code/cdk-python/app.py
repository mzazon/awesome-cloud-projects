#!/usr/bin/env python3
"""
CDK Python Application for S3 Inventory and Storage Analytics Reporting

This CDK application creates the infrastructure for automated S3 storage analytics
and reporting, including S3 inventory configuration, storage analytics, Athena
database setup, CloudWatch dashboards, and Lambda-based automation.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, Any
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Environment,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_events as events,
    aws_events_targets as targets,
    aws_athena as athena,
    aws_glue as glue,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct


class S3StorageAnalyticsStack(Stack):
    """
    CDK Stack for S3 Inventory and Storage Analytics Reporting
    
    This stack creates:
    - Source and destination S3 buckets
    - S3 inventory and storage analytics configurations
    - Athena database and workgroup
    - Lambda function for automated reporting
    - EventBridge rule for scheduling
    - CloudWatch dashboard for monitoring
    - IAM roles and policies with least privilege
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Configuration parameters
        self.source_bucket_name = f"storage-analytics-source-{unique_suffix}"
        self.dest_bucket_name = f"storage-analytics-reports-{unique_suffix}"
        self.inventory_config_id = "daily-inventory-config"
        self.analytics_config_id = "storage-class-analysis"
        self.athena_database_name = "s3_inventory_db"
        self.athena_table_name = "inventory_table"

        # Create S3 buckets
        self._create_s3_buckets()
        
        # Create IAM roles
        self._create_iam_roles()
        
        # Configure S3 inventory and analytics
        self._configure_s3_analytics()
        
        # Create Athena resources
        self._create_athena_resources()
        
        # Create Lambda function
        self._create_lambda_function()
        
        # Create EventBridge scheduling
        self._create_event_scheduling()
        
        # Create CloudWatch dashboard
        self._create_cloudwatch_dashboard()

    def _create_s3_buckets(self) -> None:
        """Create source and destination S3 buckets with appropriate configurations."""
        
        # Source bucket for storing data to be analyzed
        self.source_bucket = s3.Bucket(
            self, "SourceBucket",
            bucket_name=self.source_bucket_name,
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Destination bucket for inventory and analytics reports
        self.dest_bucket = s3.Bucket(
            self, "DestinationBucket",
            bucket_name=self.dest_bucket_name,
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="InventoryReportsLifecycle",
                    enabled=True,
                    prefix="inventory-reports/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INTELLIGENT_TIERING,
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

        # Add bucket policy for S3 inventory service
        inventory_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    sid="InventoryDestinationBucketPolicy",
                    effect=iam.Effect.ALLOW,
                    principals=[iam.ServicePrincipal("s3.amazonaws.com")],
                    actions=["s3:PutObject"],
                    resources=[f"{self.dest_bucket.bucket_arn}/*"],
                    conditions={
                        "ArnLike": {
                            "aws:SourceArn": self.source_bucket.bucket_arn
                        },
                        "StringEquals": {
                            "aws:SourceAccount": self.account,
                            "s3:x-amz-acl": "bucket-owner-full-control"
                        }
                    }
                )
            ]
        )
        
        # Apply the bucket policy
        s3.CfnBucketPolicy(
            self, "InventoryBucketPolicy",
            bucket=self.dest_bucket.bucket_name,
            policy_document=inventory_policy
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Lambda function with least privilege access."""
        
        # Lambda execution role
        self.lambda_role = iam.Role(
            self, "StorageAnalyticsLambdaRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Storage Analytics Lambda function",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "StorageAnalyticsPolicy": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "athena:StartQueryExecution",
                                "athena:GetQueryExecution",
                                "athena:GetQueryResults",
                                "athena:GetWorkGroup"
                            ],
                            resources=[
                                f"arn:aws:athena:{self.region}:{self.account}:workgroup/primary",
                                f"arn:aws:athena:{self.region}:{self.account}:workgroup/storage-analytics-workgroup"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.dest_bucket.bucket_arn,
                                f"{self.dest_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "glue:GetDatabase",
                                "glue:GetTable",
                                "glue:GetPartitions"
                            ],
                            resources=[
                                f"arn:aws:glue:{self.region}:{self.account}:catalog",
                                f"arn:aws:glue:{self.region}:{self.account}:database/{self.athena_database_name}",
                                f"arn:aws:glue:{self.region}:{self.account}:table/{self.athena_database_name}/*"
                            ]
                        )
                    ]
                )
            }
        )

    def _configure_s3_analytics(self) -> None:
        """Configure S3 inventory and storage analytics."""
        
        # S3 Inventory Configuration
        inventory_config = s3.CfnBucket.InventoryConfigurationProperty(
            id=self.inventory_config_id,
            enabled=True,
            included_object_versions="Current",
            schedule_frequency="Daily",
            optional_fields=[
                "Size",
                "LastModifiedDate", 
                "StorageClass",
                "ETag",
                "ReplicationStatus",
                "EncryptionStatus"
            ],
            destination=s3.CfnBucket.DestinationProperty(
                bucket_arn=self.dest_bucket.bucket_arn,
                format="CSV",
                bucket_account_id=self.account,
                prefix="inventory-reports/"
            )
        )

        # Apply inventory configuration to source bucket
        cfn_source_bucket = self.source_bucket.node.default_child
        cfn_source_bucket.inventory_configurations = [inventory_config]

        # Storage Analytics Configuration
        analytics_config = s3.CfnBucket.AnalyticsConfigurationProperty(
            id=self.analytics_config_id,
            storage_class_analysis=s3.CfnBucket.StorageClassAnalysisProperty(
                data_export=s3.CfnBucket.DataExportProperty(
                    output_schema_version="V_1",
                    destination=s3.CfnBucket.DestinationProperty(
                        bucket_arn=self.dest_bucket.bucket_arn,
                        format="CSV",
                        bucket_account_id=self.account,
                        prefix="analytics-reports/"
                    )
                )
            ),
            prefix="data/"
        )

        # Apply analytics configuration to source bucket
        cfn_source_bucket.analytics_configurations = [analytics_config]

    def _create_athena_resources(self) -> None:
        """Create Athena database and workgroup for querying inventory data."""
        
        # Create Glue database for Athena
        self.glue_database = glue.CfnDatabase(
            self, "S3InventoryDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.athena_database_name,
                description="Database for S3 inventory and storage analytics queries"
            )
        )

        # Create Athena workgroup for cost control and result management
        self.athena_workgroup = athena.CfnWorkGroup(
            self, "StorageAnalyticsWorkGroup",
            name="storage-analytics-workgroup",
            description="Workgroup for S3 storage analytics queries",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.dest_bucket.bucket_name}/athena-results/"
                ),
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                bytes_scanned_cutoff_per_query=1073741824  # 1 GB limit
            )
        )

    def _create_lambda_function(self) -> None:
        """Create Lambda function for automated storage analytics reporting."""
        
        # Lambda function code
        lambda_code = '''
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Lambda function to execute storage analytics queries using Athena.
    
    This function runs predefined queries against S3 inventory data to generate
    storage optimization insights and cost analysis reports.
    """
    athena = boto3.client('athena')
    s3 = boto3.client('s3')
    
    # Configuration from environment variables
    database = os.environ['ATHENA_DATABASE']
    table = os.environ['ATHENA_TABLE']
    output_bucket = os.environ['DEST_BUCKET']
    workgroup = os.environ.get('ATHENA_WORKGROUP', 'primary')
    
    # Storage optimization insights query
    query = f"""
    SELECT 
        storage_class,
        COUNT(*) as object_count,
        SUM(size) as total_size_bytes,
        ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
        ROUND(AVG(size) / 1024.0 / 1024.0, 2) as avg_size_mb,
        MIN(last_modified_date) as oldest_object,
        MAX(last_modified_date) as newest_object
    FROM {database}.{table}
    WHERE last_modified_date IS NOT NULL
    GROUP BY storage_class
    ORDER BY total_size_bytes DESC;
    """
    
    try:
        # Execute Athena query
        response = athena.start_query_execution(
            QueryString=query,
            ResultConfiguration={
                'OutputLocation': f's3://{output_bucket}/athena-results/'
            },
            WorkGroup=workgroup
        )
        
        query_execution_id = response['QueryExecutionId']
        
        # Log successful execution
        print(f"Storage analytics query executed successfully: {query_execution_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Storage analytics query executed successfully',
                'queryExecutionId': query_execution_id,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        print(f"Error executing storage analytics query: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }
'''

        # Create Lambda function
        self.lambda_function = lambda_.Function(
            self, "StorageAnalyticsFunction",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.minutes(5),
            memory_size=256,
            environment={
                'ATHENA_DATABASE': self.athena_database_name,
                'ATHENA_TABLE': self.athena_table_name,
                'DEST_BUCKET': self.dest_bucket.bucket_name,
                'ATHENA_WORKGROUP': self.athena_workgroup.name
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            description="Lambda function for automated S3 storage analytics reporting"
        )

    def _create_event_scheduling(self) -> None:
        """Create EventBridge rule for scheduled Lambda execution."""
        
        # EventBridge rule for daily execution
        self.schedule_rule = events.Rule(
            self, "StorageAnalyticsSchedule",
            description="Daily trigger for storage analytics reporting",
            schedule=events.Schedule.rate(Duration.days(1))
        )

        # Add Lambda function as target
        self.schedule_rule.add_target(
            targets.LambdaFunction(
                self.lambda_function,
                retry_attempts=2
            )
        )

    def _create_cloudwatch_dashboard(self) -> None:
        """Create CloudWatch dashboard for storage analytics monitoring."""
        
        # Create dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "StorageAnalyticsDashboard",
            dashboard_name=f"S3-Storage-Analytics-{self.source_bucket_name}",
            widgets=[
                [
                    # S3 Storage metrics widget
                    cloudwatch.GraphWidget(
                        title="S3 Storage Metrics",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.source_bucket.bucket_name,
                                    "StorageType": "StandardStorage"
                                },
                                statistic="Average",
                                period=Duration.days(1)
                            ),
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.source_bucket.bucket_name,
                                    "StorageType": "StandardIAStorage"
                                },
                                statistic="Average",
                                period=Duration.days(1)
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="NumberOfObjects",
                                dimensions_map={
                                    "BucketName": self.source_bucket.bucket_name,
                                    "StorageType": "AllStorageTypes"
                                },
                                statistic="Average",
                                period=Duration.days(1)
                            )
                        ],
                        width=12,
                        height=6
                    )
                ],
                [
                    # Lambda function metrics widget
                    cloudwatch.GraphWidget(
                        title="Storage Analytics Function Metrics",
                        left=[
                            self.lambda_function.metric_invocations(),
                            self.lambda_function.metric_errors(),
                        ],
                        right=[
                            self.lambda_function.metric_duration()
                        ],
                        width=12,
                        height=6
                    )
                ]
            ]
        )


class S3StorageAnalyticsApp(App):
    """CDK Application for S3 Storage Analytics"""

    def __init__(self, **kwargs):
        super().__init__(**kwargs)

        # Get environment configuration
        account = os.environ.get('CDK_DEFAULT_ACCOUNT')
        region = os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')

        # Create the stack
        S3StorageAnalyticsStack(
            self, "S3StorageAnalyticsStack",
            env=Environment(account=account, region=region),
            description="S3 Inventory and Storage Analytics Reporting Infrastructure",
            tags={
                "Project": "S3StorageAnalytics",
                "Environment": self.node.try_get_context("environment") or "development",
                "Owner": self.node.try_get_context("owner") or "cdk-user",
                "CostCenter": self.node.try_get_context("cost_center") or "engineering"
            }
        )


# Application entry point
if __name__ == "__main__":
    app = S3StorageAnalyticsApp()
    app.synth()