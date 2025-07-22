#!/usr/bin/env python3
"""
AWS CDK Application for Data Lake Ingestion Pipelines with Glue

This CDK application creates a comprehensive data lake solution using AWS Glue for
automated schema discovery, ETL processing, and data catalog management. The solution
implements a medallion architecture with Bronze, Silver, and Gold data layers.

Key Components:
- S3 buckets for data lake storage with proper lifecycle policies
- AWS Glue Data Catalog database for centralized metadata management
- Glue crawlers for automated schema discovery
- Glue ETL jobs for data transformation across medallion layers
- Glue workflows for pipeline orchestration
- IAM roles with least privilege access
- CloudWatch monitoring and SNS alerting
- Data quality rules for validation

Architecture Pattern: Medallion (Bronze, Silver, Gold)
- Bronze: Raw data with minimal processing
- Silver: Cleaned and enriched business data
- Gold: Analytics-ready aggregated data
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
    aws_iam as iam,
    aws_glue as glue,
    aws_glue_alpha as glue_alpha,
    aws_cloudwatch as cloudwatch,
    aws_sns as sns,
    aws_athena as athena,
    aws_logs as logs,
    CfnOutput,
    Tags
)
from constructs import Construct
import json


class DataLakeGlueStack(Stack):
    """
    Main CDK Stack for Data Lake Ingestion Pipeline
    
    Creates a complete data lake infrastructure with AWS Glue for ETL processing,
    automated schema discovery, and data catalog management following AWS best practices.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        account_id = self.account
        region = self.region
        unique_suffix = f"{account_id[:8]}-{region}"

        # Core infrastructure components
        self._create_s3_infrastructure(unique_suffix)
        self._create_iam_roles()
        self._create_glue_database(unique_suffix)
        self._create_sample_data()
        self._create_glue_crawlers(unique_suffix)
        self._create_glue_etl_jobs(unique_suffix)
        self._create_glue_workflows(unique_suffix)
        self._create_monitoring_and_alerts(unique_suffix)
        self._create_athena_workgroup(unique_suffix)
        self._create_outputs()

        # Apply tags to all resources
        self._apply_tags()

    def _create_s3_infrastructure(self, unique_suffix: str) -> None:
        """
        Create S3 buckets for data lake with optimized configuration for analytics workloads.
        
        Implements:
        - Separate buckets for different data layers
        - Intelligent tiering for cost optimization
        - Versioning for data protection
        - Lifecycle policies for automated data management
        """
        # Main data lake bucket with medallion architecture folders
        self.data_lake_bucket = s3.Bucket(
            self, "DataLakeBucket",
            bucket_name=f"datalake-pipeline-{unique_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DataLakeLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ],
            intelligent_tiering_configurations=[
                s3.IntelligentTieringConfiguration(
                    name="EntireBucket",
                    prefix="",
                    archive_access_tier_time=Duration.days(90),
                    deep_archive_access_tier_time=Duration.days(180)
                )
            ]
        )

        # Athena query results bucket
        self.athena_results_bucket = s3.Bucket(
            self, "AthenaResultsBucket",
            bucket_name=f"athena-results-{unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AthenaResultsCleanup",
                    enabled=True,
                    expiration=Duration.days(30)
                )
            ]
        )

    def _create_iam_roles(self) -> None:
        """
        Create IAM roles with least privilege access for AWS Glue services.
        
        Implements:
        - Service roles for Glue crawlers and jobs
        - S3 access policies with specific permissions
        - CloudWatch Logs permissions for monitoring
        - Data Catalog permissions for metadata management
        """
        # Glue service role for crawlers and ETL jobs
        self.glue_role = iam.Role(
            self, "GlueServiceRole",
            role_name=f"GlueDataLakeRole-{self.account[:8]}",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="Service role for AWS Glue crawlers and ETL jobs in data lake pipeline",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole")
            ]
        )

        # Custom policy for S3 data lake access
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetBucketLocation",
                "s3:ListBucket",
                "s3:GetBucketAcl",
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectVersion"
            ],
            resources=[
                self.data_lake_bucket.bucket_arn,
                f"{self.data_lake_bucket.bucket_arn}/*",
                self.athena_results_bucket.bucket_arn,
                f"{self.athena_results_bucket.bucket_arn}/*"
            ]
        )

        # Enhanced CloudWatch Logs permissions
        cloudwatch_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "logs:DescribeLogStreams",
                "cloudwatch:PutMetricData"
            ],
            resources=["*"]
        )

        # Data Catalog permissions
        catalog_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "glue:GetDatabase",
                "glue:GetDatabases",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetPartition",
                "glue:GetPartitions",
                "glue:CreateTable",
                "glue:UpdateTable",
                "glue:DeleteTable",
                "glue:CreatePartition",
                "glue:UpdatePartition",
                "glue:DeletePartition",
                "glue:BatchCreatePartition",
                "glue:BatchDeletePartition",
                "glue:BatchUpdatePartition"
            ],
            resources=["*"]
        )

        # Attach policies to role
        self.glue_role.add_to_policy(s3_policy)
        self.glue_role.add_to_policy(cloudwatch_policy)
        self.glue_role.add_to_policy(catalog_policy)

    def _create_glue_database(self, unique_suffix: str) -> None:
        """
        Create AWS Glue Data Catalog database for centralized metadata management.
        
        The database serves as the logical container for table definitions,
        schemas, and partition information discovered by crawlers.
        """
        self.glue_database = glue.CfnDatabase(
            self, "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=f"datalake-catalog-{unique_suffix[:6]}",
                description="Data lake catalog for analytics pipeline with automated schema discovery",
                location_uri=f"s3://{self.data_lake_bucket.bucket_name}/",
                parameters={
                    "classification": "data-lake",
                    "creator": "aws-cdk",
                    "environment": "production"
                }
            )
        )

    def _create_sample_data(self) -> None:
        """
        Deploy sample data files to demonstrate the data lake ingestion pipeline.
        
        Creates realistic sample data in multiple formats:
        - JSON for event stream data with partitioning
        - CSV for structured customer data
        - Demonstrates schema evolution capabilities
        """
        # Sample JSON events data
        sample_events = [
            {
                "event_id": "evt001",
                "user_id": "user123",
                "event_type": "purchase",
                "product_id": "prod456",
                "amount": 89.99,
                "timestamp": "2024-01-15T10:30:00Z",
                "category": "electronics"
            },
            {
                "event_id": "evt002",
                "user_id": "user456",
                "event_type": "view",
                "product_id": "prod789",
                "amount": 0.0,
                "timestamp": "2024-01-15T10:31:00Z",
                "category": "books"
            },
            {
                "event_id": "evt003",
                "user_id": "user789",
                "event_type": "cart_add",
                "product_id": "prod123",
                "amount": 45.50,
                "timestamp": "2024-01-15T10:32:00Z",
                "category": "clothing"
            }
        ]

        # Sample CSV customers data
        sample_customers_csv = """customer_id,name,email,registration_date,country,age_group
user123,John Doe,john.doe@example.com,2023-05-15,US,25-34
user456,Jane Smith,jane.smith@example.com,2023-06-20,CA,35-44
user789,Bob Johnson,bob.johnson@example.com,2023-07-10,UK,45-54
user654,Alice Brown,alice.brown@example.com,2023-08-05,US,18-24
user321,Charlie Wilson,charlie.wilson@example.com,2023-09-12,AU,25-34"""

        # Deploy sample data using S3 deployment
        s3deploy.BucketDeployment(
            self, "SampleDataDeployment",
            sources=[
                s3deploy.Source.data("raw-data/events/year=2024/month=01/day=15/events.json", 
                                   "\n".join([json.dumps(event) for event in sample_events])),
                s3deploy.Source.data("raw-data/customers/customers.csv", sample_customers_csv)
            ],
            destination_bucket=self.data_lake_bucket,
            retain_on_delete=False
        )

    def _create_glue_crawlers(self, unique_suffix: str) -> None:
        """
        Create AWS Glue crawlers for automated schema discovery and catalog population.
        
        Implements:
        - Intelligent schema inference across multiple data formats
        - Automatic partition detection for optimized queries
        - Schema evolution handling for changing data structures
        """
        self.data_crawler = glue.CfnCrawler(
            self, "DataLakeCrawler",
            name=f"data-lake-crawler-{unique_suffix[:6]}",
            description="Crawler for data lake raw data sources with automatic schema discovery",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket.bucket_name}/raw-data/"
                    )
                ]
            ),
            table_prefix="raw_",
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG"
            ),
            recrawl_policy=glue.CfnCrawler.RecrawlPolicyProperty(
                recrawl_behavior="CRAWL_EVERYTHING"
            ),
            lineage_configuration=glue.CfnCrawler.LineageConfigurationProperty(
                crawler_lineage_settings="ENABLE"
            ),
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 6 * * ? *)"  # Daily at 6 AM UTC
            )
        )

        # Processed data crawler for Silver and Gold layers
        self.processed_crawler = glue.CfnCrawler(
            self, "ProcessedDataCrawler",
            name=f"processed-data-crawler-{unique_suffix[:6]}",
            description="Crawler for processed data layers (Silver and Gold)",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_lake_bucket.bucket_name}/processed-data/"
                    )
                ]
            ),
            table_prefix="processed_",
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG"
            )
        )

    def _create_glue_etl_jobs(self, unique_suffix: str) -> None:
        """
        Create AWS Glue ETL jobs for data transformation across medallion layers.
        
        Implements:
        - PySpark-based transformations for scalable processing
        - Medallion architecture (Bronze, Silver, Gold) data flow
        - Data quality validation and business logic application
        - Optimized Parquet output with partitioning
        """
        # ETL script content for medallion architecture processing
        etl_script_content = '''
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 
    'DATABASE_NAME', 
    'S3_BUCKET_NAME'
])

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read raw data from Data Catalog
    events_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name="raw_events"
    ).toDF()
    
    customers_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name="raw_customers"
    ).toDF()
    
    # Bronze layer: Raw data with basic cleansing
    print("Processing Bronze Layer...")
    events_bronze = events_df.withColumn(
        "timestamp", to_timestamp(col("timestamp"))
    ).withColumn(
        "amount", col("amount").cast("double")
    ).filter(
        col("event_id").isNotNull() & col("user_id").isNotNull()
    ).withColumn(
        "processing_date", current_date()
    ).withColumn(
        "processing_timestamp", current_timestamp()
    )
    
    # Write to Bronze layer
    events_bronze.write.mode("overwrite").option("compression", "snappy").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/bronze/events/"
    )
    
    # Silver layer: Business logic and enrichment
    print("Processing Silver Layer...")
    events_silver = events_bronze.join(
        customers_df,
        events_bronze.user_id == customers_df.customer_id,
        "left"
    ).select(
        events_bronze["*"],
        customers_df["name"].alias("customer_name"),
        customers_df["email"].alias("customer_email"),
        customers_df["country"],
        customers_df["age_group"]
    ).withColumn(
        "is_purchase", when(col("event_type") == "purchase", 1).otherwise(0)
    ).withColumn(
        "is_high_value", when(col("amount") > 100, 1).otherwise(0)
    ).withColumn(
        "event_date", to_date(col("timestamp"))
    ).withColumn(
        "event_hour", hour(col("timestamp"))
    )
    
    # Write to Silver layer with partitioning
    events_silver.write.mode("overwrite").partitionBy("event_date").option("compression", "snappy").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/silver/events/"
    )
    
    # Gold layer: Analytics-ready aggregations
    print("Processing Gold Layer...")
    daily_sales = events_silver.filter(
        col("event_type") == "purchase"
    ).groupBy(
        "event_date", "category", "country"
    ).agg(
        count("*").alias("total_purchases"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_order_value"),
        countDistinct("user_id").alias("unique_customers")
    )
    
    customer_behavior = events_silver.groupBy(
        "user_id", "customer_name", "country", "age_group"
    ).agg(
        count("*").alias("total_events"),
        sum("is_purchase").alias("total_purchases"),
        sum("amount").alias("total_spent"),
        countDistinct("category").alias("categories_engaged")
    ).withColumn(
        "avg_order_value",
        when(col("total_purchases") > 0, col("total_spent") / col("total_purchases")).otherwise(0)
    )
    
    # Write Gold layer data
    daily_sales.write.mode("overwrite").option("compression", "snappy").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/gold/daily_sales/"
    )
    
    customer_behavior.write.mode("overwrite").option("compression", "snappy").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/gold/customer_behavior/"
    )
    
    print("ETL job completed successfully!")
    
except Exception as e:
    print(f"ETL job failed with error: {str(e)}")
    raise e
finally:
    job.commit()
'''

        # Deploy ETL script to S3
        s3deploy.BucketDeployment(
            self, "ETLScriptDeployment",
            sources=[
                s3deploy.Source.data("scripts/etl-script.py", etl_script_content)
            ],
            destination_bucket=self.data_lake_bucket,
            retain_on_delete=False
        )

        # Create ETL job
        self.etl_job = glue.CfnJob(
            self, "DataLakeETLJob",
            name=f"data-lake-etl-job-{unique_suffix[:6]}",
            description="Data lake ETL pipeline for medallion architecture processing",
            role=self.glue_role.role_arn,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                script_location=f"s3://{self.data_lake_bucket.bucket_name}/scripts/etl-script.py",
                python_version="3"
            ),
            default_arguments={
                "--job-bookmark-option": "job-bookmark-enable",
                "--enable-metrics": "",
                "--enable-continuous-cloudwatch-log": "true",
                "--DATABASE_NAME": self.glue_database.ref,
                "--S3_BUCKET_NAME": self.data_lake_bucket.bucket_name,
                "--TempDir": f"s3://{self.data_lake_bucket.bucket_name}/temp/",
                "--enable-glue-datacatalog": ""
            },
            max_retries=1,
            timeout=60,
            glue_version="3.0",
            worker_type="G.1X",
            number_of_workers=5,
            max_capacity=5
        )

    def _create_glue_workflows(self, unique_suffix: str) -> None:
        """
        Create AWS Glue workflows for orchestrating crawler and ETL job execution.
        
        Implements:
        - Dependency-based execution flow
        - Scheduled triggers for automated pipeline runs
        - Error handling and retry mechanisms
        """
        # Main workflow for data pipeline orchestration
        self.data_workflow = glue.CfnWorkflow(
            self, "DataLakeWorkflow",
            name=f"data-lake-workflow-{unique_suffix[:6]}",
            description="Data lake ingestion workflow with crawler and ETL orchestration"
        )

        # Scheduled trigger for crawler (daily at 6 AM UTC)
        self.crawler_trigger = glue.CfnTrigger(
            self, "CrawlerScheduleTrigger",
            name=f"{self.data_workflow.name}-crawler-trigger",
            type="SCHEDULED",
            schedule="cron(0 6 * * ? *)",
            workflow_name=self.data_workflow.name,
            actions=[
                glue.CfnTrigger.ActionProperty(
                    crawler_name=self.data_crawler.name
                )
            ],
            start_on_creation=True,
            description="Daily trigger for data lake crawler execution"
        )

        # Conditional trigger for ETL job (after successful crawler run)
        self.etl_trigger = glue.CfnTrigger(
            self, "ETLConditionalTrigger",
            name=f"{self.data_workflow.name}-etl-trigger",
            type="CONDITIONAL",
            predicate=glue.CfnTrigger.PredicateProperty(
                conditions=[
                    glue.CfnTrigger.ConditionProperty(
                        logical_operator="EQUALS",
                        crawler_name=self.data_crawler.name,
                        crawl_state="SUCCEEDED"
                    )
                ]
            ),
            workflow_name=self.data_workflow.name,
            actions=[
                glue.CfnTrigger.ActionProperty(
                    job_name=self.etl_job.name
                )
            ],
            description="Trigger ETL job after successful crawler completion"
        )

        # On-demand trigger for processed data crawler
        self.processed_crawler_trigger = glue.CfnTrigger(
            self, "ProcessedCrawlerTrigger",
            name=f"{self.data_workflow.name}-processed-crawler-trigger",
            type="CONDITIONAL",
            predicate=glue.CfnTrigger.PredicateProperty(
                conditions=[
                    glue.CfnTrigger.ConditionProperty(
                        logical_operator="EQUALS",
                        job_name=self.etl_job.name,
                        state="SUCCEEDED"
                    )
                ]
            ),
            workflow_name=self.data_workflow.name,
            actions=[
                glue.CfnTrigger.ActionProperty(
                    crawler_name=self.processed_crawler.name
                )
            ],
            description="Trigger processed data crawler after ETL job completion"
        )

    def _create_monitoring_and_alerts(self, unique_suffix: str) -> None:
        """
        Create comprehensive monitoring and alerting for the data pipeline.
        
        Implements:
        - CloudWatch alarms for job failures and performance issues
        - SNS notifications for operational alerts
        - Custom metrics for pipeline monitoring
        """
        # SNS topic for pipeline alerts
        self.alerts_topic = sns.Topic(
            self, "DataPipelineAlerts",
            topic_name=f"DataLakeAlerts-{unique_suffix[:6]}",
            display_name="Data Lake Pipeline Alerts"
        )

        # CloudWatch alarm for ETL job failures
        etl_failure_alarm = cloudwatch.Alarm(
            self, "ETLJobFailureAlarm",
            alarm_name=f"GlueJobFailure-{self.etl_job.name}",
            alarm_description="Alert when Glue ETL job fails",
            metric=cloudwatch.Metric(
                namespace="AWS/Glue",
                metric_name="glue.driver.aggregate.numFailedTasks",
                dimensions_map={
                    "JobName": self.etl_job.name,
                    "JobRunId": "ALL"
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        etl_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alerts_topic)
        )

        # CloudWatch alarm for crawler failures
        crawler_failure_alarm = cloudwatch.Alarm(
            self, "CrawlerFailureAlarm",
            alarm_name=f"GlueCrawlerFailure-{self.data_crawler.name}",
            alarm_description="Alert when Glue crawler fails",
            metric=cloudwatch.Metric(
                namespace="AWS/Glue",
                metric_name="glue.driver.aggregate.numFailedTasks",
                dimensions_map={
                    "CrawlerName": self.data_crawler.name
                },
                statistic="Sum",
                period=Duration.minutes(5)
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            treat_missing_data=cloudwatch.TreatMissingData.NOT_BREACHING
        )
        crawler_failure_alarm.add_alarm_action(
            cloudwatch.SnsAction(self.alerts_topic)
        )

        # CloudWatch log groups for better log management
        self.glue_log_group = logs.LogGroup(
            self, "GlueLogGroup",
            log_group_name=f"/aws-glue/jobs/{self.etl_job.name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_athena_workgroup(self, unique_suffix: str) -> None:
        """
        Create Amazon Athena workgroup for SQL analytics on the data lake.
        
        Provides:
        - Isolated query environment with cost controls
        - Query result management and encryption
        - Performance optimization settings
        """
        self.athena_workgroup = athena.CfnWorkGroup(
            self, "DataLakeWorkgroup",
            name=f"DataLakeWorkgroup-{unique_suffix[:6]}",
            description="Workgroup for data lake analytics and ad-hoc queries",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.athena_results_bucket.bucket_name}/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3"
                    )
                ),
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                bytes_scanned_cutoff_per_query=1000000000,  # 1GB limit
                requester_pays_enabled=False
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources and configuration values."""
        CfnOutput(
            self, "DataLakeBucketName",
            value=self.data_lake_bucket.bucket_name,
            description="S3 bucket name for the data lake storage",
            export_name=f"{self.stack_name}-DataLakeBucket"
        )

        CfnOutput(
            self, "GlueDatabaseName",
            value=self.glue_database.ref,
            description="AWS Glue Data Catalog database name",
            export_name=f"{self.stack_name}-GlueDatabase"
        )

        CfnOutput(
            self, "GlueRoleArn",
            value=self.glue_role.role_arn,
            description="IAM role ARN for AWS Glue services",
            export_name=f"{self.stack_name}-GlueRole"
        )

        CfnOutput(
            self, "CrawlerName",
            value=self.data_crawler.name,
            description="Name of the AWS Glue crawler for raw data",
            export_name=f"{self.stack_name}-Crawler"
        )

        CfnOutput(
            self, "ETLJobName",
            value=self.etl_job.name,
            description="Name of the AWS Glue ETL job",
            export_name=f"{self.stack_name}-ETLJob"
        )

        CfnOutput(
            self, "WorkflowName",
            value=self.data_workflow.name,
            description="Name of the AWS Glue workflow for pipeline orchestration",
            export_name=f"{self.stack_name}-Workflow"
        )

        CfnOutput(
            self, "SNSTopicArn",
            value=self.alerts_topic.topic_arn,
            description="SNS topic ARN for pipeline alerts and notifications",
            export_name=f"{self.stack_name}-SNSTopic"
        )

        CfnOutput(
            self, "AthenaWorkgroupName",
            value=self.athena_workgroup.name,
            description="Amazon Athena workgroup for data lake queries",
            export_name=f"{self.stack_name}-AthenaWorkgroup"
        )

        CfnOutput(
            self, "AthenaResultsBucket",
            value=self.athena_results_bucket.bucket_name,
            description="S3 bucket for Athena query results",
            export_name=f"{self.stack_name}-AthenaResults"
        )

    def _apply_tags(self) -> None:
        """Apply consistent tags to all resources for governance and cost tracking."""
        Tags.of(self).add("Project", "DataLakeIngestionPipeline")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "DataEngineering")
        Tags.of(self).add("CostCenter", "Analytics")
        Tags.of(self).add("Architecture", "MedallionDataLake")
        Tags.of(self).add("ManagedBy", "AWS-CDK")


# CDK Application
app = cdk.App()

# Deploy the data lake stack
DataLakeGlueStack(
    app, 
    "DataLakeGlueStack",
    description="AWS Glue Data Lake Ingestion Pipeline with Medallion Architecture",
    env=cdk.Environment(
        account=app.node.try_get_context("account"),
        region=app.node.try_get_context("region")
    )
)

# Synthesize the CloudFormation template
app.synth()