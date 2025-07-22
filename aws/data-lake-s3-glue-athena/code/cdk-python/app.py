#!/usr/bin/env python3
"""
CDK Python application for building data lake architectures with S3, Glue, and Athena.

This application deploys a complete serverless data lake solution including:
- S3 buckets for data storage with lifecycle policies
- IAM roles and policies for Glue services
- Glue database, crawlers, and ETL jobs
- Athena workgroup for SQL analytics
- Sample data and ETL scripts
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Stack,
    StackProps,
    aws_athena as athena,
    aws_glue as glue,
    aws_iam as iam,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
)
from constructs import Construct


class DataLakeStack(Stack):
    """
    CDK Stack for serverless data lake architecture using S3, Glue, and Athena.
    
    This stack creates a complete data lake solution with:
    - Multi-zone S3 storage (raw, processed, archive)
    - Automated data cataloging with Glue crawlers
    - ETL processing with Glue jobs
    - SQL analytics with Athena
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs: Any) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = cdk.Names.unique_id(self)[:8].lower()
        
        # Create S3 buckets for data lake
        self.data_lake_bucket = self._create_data_lake_bucket(unique_suffix)
        self.athena_results_bucket = self._create_athena_results_bucket(unique_suffix)
        
        # Create IAM role for Glue services
        self.glue_role = self._create_glue_service_role()
        
        # Create Glue database
        self.glue_database = self._create_glue_database(unique_suffix)
        
        # Create Glue crawlers for schema discovery
        self.sales_crawler = self._create_sales_data_crawler(unique_suffix)
        self.logs_crawler = self._create_web_logs_crawler(unique_suffix)
        
        # Create Glue ETL job
        self.etl_job = self._create_etl_job(unique_suffix)
        
        # Create Athena workgroup
        self.athena_workgroup = self._create_athena_workgroup(unique_suffix)
        
        # Deploy sample data and scripts
        self._deploy_sample_data()
        self._deploy_etl_scripts()
        
        # Create stack outputs
        self._create_outputs()

    def _create_data_lake_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for data lake with lifecycle policies and versioning.
        
        Args:
            suffix: Unique suffix for bucket name
            
        Returns:
            S3 bucket configured for data lake storage
        """
        bucket = s3.Bucket(
            self,
            "DataLakeBucket",
            bucket_name=f"data-lake-{suffix}",
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            enforce_ssl=True,
            server_access_logs_prefix="access-logs/",
            lifecycle_rules=[
                # Raw zone lifecycle rule
                s3.LifecycleRule(
                    id="RawZoneLifecycle",
                    enabled=True,
                    prefix="raw-zone/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365),
                        ),
                    ],
                ),
                # Processed zone lifecycle rule
                s3.LifecycleRule(
                    id="ProcessedZoneLifecycle",
                    enabled=True,
                    prefix="processed-zone/",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(90),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(180),
                        ),
                    ],
                ),
            ],
        )
        
        # Add bucket notification for future Lambda triggers
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3.NotificationKeyFilter(prefix="raw-zone/"),
        )
        
        return bucket

    def _create_athena_results_bucket(self, suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for Athena query results.
        
        Args:
            suffix: Unique suffix for bucket name
            
        Returns:
            S3 bucket for Athena results
        """
        return s3.Bucket(
            self,
            "AthenaResultsBucket",
            bucket_name=f"athena-results-{suffix}",
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AthenaResultsCleanup",
                    enabled=True,
                    expiration=Duration.days(30),
                ),
            ],
        )

    def _create_glue_service_role(self) -> iam.Role:
        """
        Create IAM role for AWS Glue with necessary permissions.
        
        Returns:
            IAM role for Glue services
        """
        role = iam.Role(
            self,
            "GlueServiceRole",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueServiceRole"
                ),
            ],
        )
        
        # Add custom policy for S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[
                    self.data_lake_bucket.bucket_arn,
                    f"{self.data_lake_bucket.bucket_arn}/*",
                ],
            )
        )
        
        # Add CloudWatch Logs permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents",
                ],
                resources=[
                    f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws-glue/*",
                ],
            )
        )
        
        return role

    def _create_glue_database(self, suffix: str) -> glue.CfnDatabase:
        """
        Create Glue database for data catalog.
        
        Args:
            suffix: Unique suffix for database name
            
        Returns:
            Glue database resource
        """
        return glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=f"datalake_db_{suffix}",
                description="Data lake database for analytics and ETL processing",
                parameters={
                    "classification": "data-lake",
                    "created_by": "cdk",
                },
            ),
        )

    def _create_sales_data_crawler(self, suffix: str) -> glue.CfnCrawler:
        """
        Create Glue crawler for sales data schema discovery.
        
        Args:
            suffix: Unique suffix for crawler name
            
        Returns:
            Glue crawler for sales data
        """
        return glue.CfnCrawler(
            self,
            "SalesDataCrawler",
            name=f"sales-data-crawler-{suffix}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket.bucket_name}/raw-zone/sales-data/",
                    ),
                ],
            ),
            description="Crawler for sales data in CSV format",
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 6 * * ? *)",  # Daily at 6 AM
            ),
            configuration='{"Version": 1.0, "CrawlerOutput": {"Partitions": {"AddOrUpdateBehavior": "InheritFromTable"}}}',
        )

    def _create_web_logs_crawler(self, suffix: str) -> glue.CfnCrawler:
        """
        Create Glue crawler for web logs schema discovery.
        
        Args:
            suffix: Unique suffix for crawler name
            
        Returns:
            Glue crawler for web logs
        """
        return glue.CfnCrawler(
            self,
            "WebLogsCrawler",
            name=f"web-logs-crawler-{suffix}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket.bucket_name}/raw-zone/web-logs/",
                    ),
                ],
            ),
            description="Crawler for web logs in JSON format",
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 6 * * ? *)",  # Daily at 6 AM
            ),
            configuration='{"Version": 1.0, "CrawlerOutput": {"Partitions": {"AddOrUpdateBehavior": "InheritFromTable"}}}',
        )

    def _create_etl_job(self, suffix: str) -> glue.CfnJob:
        """
        Create Glue ETL job for data transformation.
        
        Args:
            suffix: Unique suffix for job name
            
        Returns:
            Glue ETL job resource
        """
        return glue.CfnJob(
            self,
            "SalesDataETLJob",
            name=f"sales-data-etl-{suffix}",
            role=self.glue_role.role_arn,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                python_version="3",
                script_location=f"s3://{self.data_lake_bucket.bucket_name}/scripts/glue-etl-script.py",
            ),
            default_arguments={
                "--DATABASE_NAME": self.glue_database.ref,
                "--TABLE_NAME": "sales_data",
                "--OUTPUT_PATH": f"s3://{self.data_lake_bucket.bucket_name}/processed-zone/sales-data-processed/",
                "--enable-metrics": "",
                "--enable-continuous-cloudwatch-log": "true",
                "--enable-spark-ui": "true",
                "--spark-event-logs-path": f"s3://{self.data_lake_bucket.bucket_name}/spark-logs/",
            },
            glue_version="4.0",
            max_capacity=2,
            timeout=60,
            description="ETL job to transform sales data from CSV to optimized Parquet format",
        )

    def _create_athena_workgroup(self, suffix: str) -> athena.CfnWorkGroup:
        """
        Create Athena workgroup for SQL analytics.
        
        Args:
            suffix: Unique suffix for workgroup name
            
        Returns:
            Athena workgroup resource
        """
        return athena.CfnWorkGroup(
            self,
            "DataLakeWorkgroup",
            name=f"DataLakeWorkgroup-{suffix}",
            description="Workgroup for data lake analytics and queries",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.athena_results_bucket.bucket_name}/query-results/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3",
                    ),
                ),
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics_enabled=True,
                bytes_scanned_cutoff_per_query=1000000000,  # 1GB limit
                requester_pays_enabled=False,
            ),
        )

    def _deploy_sample_data(self) -> None:
        """Deploy sample data files to S3 for testing and demonstration."""
        # Create sample CSV data
        sample_csv_content = """order_id,customer_id,product_name,category,quantity,price,order_date,region
1001,C001,Laptop,Electronics,1,999.99,2024-01-15,North
1002,C002,Coffee Maker,Appliances,2,79.99,2024-01-15,South
1003,C003,Book Set,Books,3,45.50,2024-01-16,East
1004,C001,Wireless Mouse,Electronics,1,29.99,2024-01-16,North
1005,C004,Desk Chair,Furniture,1,199.99,2024-01-17,West
1006,C005,Smartphone,Electronics,1,699.99,2024-01-17,South
1007,C002,Blender,Appliances,1,89.99,2024-01-18,South
1008,C006,Novel,Books,5,12.99,2024-01-18,East
1009,C003,Monitor,Electronics,2,299.99,2024-01-19,East
1010,C007,Coffee Table,Furniture,1,149.99,2024-01-19,West"""

        # Create sample JSON data
        sample_json_content = """{"timestamp":"2024-01-15T10:30:00Z","user_id":"U001","page":"/home","action":"view","duration":45,"ip":"192.168.1.100"}
{"timestamp":"2024-01-15T10:31:00Z","user_id":"U002","page":"/products","action":"view","duration":120,"ip":"192.168.1.101"}
{"timestamp":"2024-01-15T10:32:00Z","user_id":"U001","page":"/cart","action":"add_item","duration":30,"ip":"192.168.1.100"}
{"timestamp":"2024-01-15T10:33:00Z","user_id":"U003","page":"/checkout","action":"purchase","duration":180,"ip":"192.168.1.102"}
{"timestamp":"2024-01-15T10:34:00Z","user_id":"U002","page":"/profile","action":"update","duration":90,"ip":"192.168.1.101"}"""

        # Deploy sample data using S3 deployment
        s3_deployment.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3_deployment.Source.data(
                    "raw-zone/sales-data/year=2024/month=01/sample-sales-data.csv",
                    sample_csv_content,
                ),
                s3_deployment.Source.data(
                    "raw-zone/web-logs/year=2024/month=01/sample-web-logs.json",
                    sample_json_content,
                ),
            ],
            destination_bucket=self.data_lake_bucket,
        )

    def _deploy_etl_scripts(self) -> None:
        """Deploy ETL scripts to S3 for Glue jobs."""
        etl_script_content = """import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F

# Get job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'TABLE_NAME', 'OUTPUT_PATH'])

# Initialize Spark and Glue contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from Glue catalog
datasource = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name=args['TABLE_NAME']
)

# Convert to Spark DataFrame for transformations
df = datasource.toDF()

# Add processing timestamp and data quality columns
df_processed = df.withColumn("processed_timestamp", F.current_timestamp()) \\
                .withColumn("data_quality_score", F.lit(95.0)) \\
                .withColumn("processing_version", F.lit("1.0"))

# Data quality checks
df_processed = df_processed.filter(F.col("price") > 0)  # Remove invalid prices
df_processed = df_processed.filter(F.col("quantity") > 0)  # Remove invalid quantities

# Convert back to DynamicFrame
processed_dynamic_frame = DynamicFrame.fromDF(df_processed, glueContext, "processed_data")

# Write to S3 in Parquet format with partitioning
glueContext.write_dynamic_frame.from_options(
    frame=processed_dynamic_frame,
    connection_type="s3",
    connection_options={
        "path": args['OUTPUT_PATH'],
        "partitionKeys": ["year", "month"]
    },
    format="parquet",
    transformation_ctx="write_processed_data"
)

job.commit()
"""

        # Deploy ETL script
        s3_deployment.BucketDeployment(
            self,
            "ETLScriptDeployment",
            sources=[
                s3_deployment.Source.data(
                    "scripts/glue-etl-script.py",
                    etl_script_content,
                ),
            ],
            destination_bucket=self.data_lake_bucket,
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "DataLakeBucketName",
            value=self.data_lake_bucket.bucket_name,
            description="Name of the S3 bucket for data lake storage",
        )
        
        CfnOutput(
            self,
            "AthenaResultsBucketName",
            value=self.athena_results_bucket.bucket_name,
            description="Name of the S3 bucket for Athena query results",
        )
        
        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="Name of the Glue database for data catalog",
        )
        
        CfnOutput(
            self,
            "GlueRoleArn",
            value=self.glue_role.role_arn,
            description="ARN of the IAM role for Glue services",
        )
        
        CfnOutput(
            self,
            "AthenaWorkgroupName",
            value=self.athena_workgroup.name,
            description="Name of the Athena workgroup for analytics",
        )
        
        CfnOutput(
            self,
            "SalesDataCrawlerName",
            value=self.sales_crawler.name,
            description="Name of the Glue crawler for sales data",
        )
        
        CfnOutput(
            self,
            "WebLogsCrawlerName",
            value=self.logs_crawler.name,
            description="Name of the Glue crawler for web logs",
        )
        
        CfnOutput(
            self,
            "ETLJobName",
            value=self.etl_job.name,
            description="Name of the Glue ETL job for data transformation",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment from context or use defaults
    env = cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
    )
    
    # Create the data lake stack
    DataLakeStack(
        app,
        "DataLakeStack",
        env=env,
        description="Serverless data lake architecture with S3, Glue, and Athena",
        tags={
            "Project": "DataLake",
            "Environment": "Development",
            "ManagedBy": "CDK",
        },
    )
    
    app.synth()


if __name__ == "__main__":
    main()