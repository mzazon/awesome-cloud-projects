#!/usr/bin/env python3
"""
AWS CDK Python application for Data Visualization Pipelines with QuickSight.

This application creates a comprehensive data visualization pipeline including:
- S3 buckets for raw data, processed data, and Athena query results
- AWS Glue crawlers and ETL jobs for data cataloging and transformation
- Athena workgroup for serverless querying
- Lambda function for pipeline automation
- QuickSight data source for visualization
- IAM roles and policies with least privilege access

Author: AWS CDK Generator
Version: 1.0
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    CfnParameter,
    CfnCondition,
    CfnOutput,
    Fn,
    Tags,
    Duration,
    RemovalPolicy,
)
import aws_cdk.aws_s3 as s3
import aws_cdk.aws_iam as iam
import aws_cdk.aws_glue as glue
import aws_cdk.aws_athena as athena
import aws_cdk.aws_lambda as lambda_
import aws_cdk.aws_quicksight as quicksight
import aws_cdk.aws_s3_notifications as s3n
from constructs import Construct
from typing import Dict, Any, Optional


class DataVisualizationPipelineStack(Stack):
    """
    CDK Stack for deploying a complete data visualization pipeline with QuickSight and S3.
    
    This stack creates all necessary resources for ingesting, processing, and visualizing
    data using AWS managed services in a serverless architecture.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # ========================================
        # STACK PARAMETERS
        # ========================================
        
        self.project_name = CfnParameter(
            self, "ProjectName",
            type="String",
            default="data-viz-pipeline",
            description="Base name for all resources",
            allowed_pattern=r"^[a-z0-9-]{3,20}$",
            constraint_description="Must be 3-20 characters, lowercase letters, numbers, and hyphens only"
        )

        self.quicksight_user_arn = CfnParameter(
            self, "QuickSightUserArn",
            type="String",
            description="QuickSight user ARN for data source permissions (format: arn:aws:quicksight:region:account:user/default/username)",
            allowed_pattern=r"^arn:aws:quicksight:[a-z0-9-]+:[0-9]{12}:user/.+$",
            constraint_description="Must be a valid QuickSight user ARN"
        )

        self.enable_s3_notifications = CfnParameter(
            self, "EnableS3EventNotifications",
            type="String",
            default="true",
            allowed_values=["true", "false"],
            description="Enable S3 event notifications to trigger automated pipeline processing"
        )

        self.glue_version = CfnParameter(
            self, "GlueVersion",
            type="String",
            default="4.0",
            allowed_values=["3.0", "4.0"],
            description="AWS Glue version for ETL jobs"
        )

        self.enable_encryption = CfnParameter(
            self, "EnableEncryption",
            type="String",
            default="true",
            allowed_values=["true", "false"],
            description="Enable encryption for S3 buckets and Athena query results"
        )

        # ========================================
        # CONDITIONS
        # ========================================
        
        self.create_s3_notifications = CfnCondition(
            self, "CreateS3Notifications",
            expression=Fn.condition_equals(self.enable_s3_notifications.value_as_string, "true")
        )

        self.enable_s3_encryption = CfnCondition(
            self, "EnableS3Encryption",
            expression=Fn.condition_equals(self.enable_encryption.value_as_string, "true")
        )

        # ========================================
        # S3 STORAGE BUCKETS
        # ========================================
        
        # Create S3 buckets for the data pipeline
        self._create_storage_buckets()

        # ========================================
        # IAM ROLES AND POLICIES
        # ========================================
        
        # Create IAM roles with least privilege access
        self._create_iam_roles()

        # ========================================
        # GLUE DATA CATALOG AND CRAWLERS
        # ========================================
        
        # Create Glue database and crawlers
        self._create_glue_resources()

        # ========================================
        # ATHENA WORKGROUP
        # ========================================
        
        # Create Athena workgroup for query management
        self._create_athena_workgroup()

        # ========================================
        # LAMBDA AUTOMATION
        # ========================================
        
        # Create Lambda function for pipeline automation
        self._create_lambda_automation()

        # ========================================
        # QUICKSIGHT DATA SOURCE
        # ========================================
        
        # Create QuickSight data source
        self._create_quicksight_resources()

        # ========================================
        # ETL SCRIPT DEPLOYMENT
        # ========================================
        
        # Deploy ETL script to S3
        self._create_etl_script_deployment()

        # ========================================
        # STACK OUTPUTS
        # ========================================
        
        # Create stack outputs for resource references
        self._create_outputs()

    def _create_storage_buckets(self) -> None:
        """Create S3 buckets for raw data, processed data, and Athena results."""
        
        # Raw data bucket with lifecycle policies and versioning
        self.raw_data_bucket = s3.Bucket(
            self, "RawDataBucket",
            bucket_name=f"{self.project_name.value_as_string}-raw-data-{self.account}-{self.region}",
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                    enabled=True
                ),
                s3.LifecycleRule(
                    id="ArchiveOldVersions",
                    enabled=True,
                    noncurrent_version_transitions=[
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.NoncurrentVersionTransition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.RETAIN
        )

        # Apply conditional encryption
        if self.enable_s3_encryption.value_as_string == "true":
            self.raw_data_bucket.encryption = s3.BucketEncryption.S3_MANAGED

        # Processed data bucket with lifecycle optimization
        self.processed_data_bucket = s3.Bucket(
            self, "ProcessedDataBucket",
            bucket_name=f"{self.project_name.value_as_string}-processed-data-{self.account}-{self.region}",
            versioned=True,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                    enabled=True
                ),
                s3.LifecycleRule(
                    id="OptimizeStorageClass",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.RETAIN
        )

        if self.enable_s3_encryption.value_as_string == "true":
            self.processed_data_bucket.encryption = s3.BucketEncryption.S3_MANAGED

        # Athena results bucket with automatic cleanup
        self.athena_results_bucket = s3.Bucket(
            self, "AthenaResultsBucket",
            bucket_name=f"{self.project_name.value_as_string}-athena-results-{self.account}-{self.region}",
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteQueryResults",
                    enabled=True,
                    expiration=Duration.days(30)
                ),
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                    enabled=True
                )
            ],
            removal_policy=RemovalPolicy.DESTROY
        )

        if self.enable_s3_encryption.value_as_string == "true":
            self.athena_results_bucket.encryption = s3.BucketEncryption.S3_MANAGED

        # Add tags to all buckets
        Tags.of(self.raw_data_bucket).add("Purpose", "Raw data storage for visualization pipeline")
        Tags.of(self.raw_data_bucket).add("Project", self.project_name.value_as_string)
        Tags.of(self.processed_data_bucket).add("Purpose", "Processed data storage for visualization pipeline")
        Tags.of(self.processed_data_bucket).add("Project", self.project_name.value_as_string)
        Tags.of(self.athena_results_bucket).add("Purpose", "Athena query results storage")
        Tags.of(self.athena_results_bucket).add("Project", self.project_name.value_as_string)

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Glue and Lambda with least privilege access."""
        
        # Glue service role for crawlers and ETL jobs
        self.glue_service_role = iam.Role(
            self, "GlueServiceRole",
            role_name=f"{self.project_name.value_as_string}-glue-service-role",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole")
            ],
            inline_policies={
                "S3DataAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:ListBucket"
                            ],
                            resources=[
                                self.raw_data_bucket.bucket_arn,
                                f"{self.raw_data_bucket.bucket_arn}/*",
                                self.processed_data_bucket.bucket_arn,
                                f"{self.processed_data_bucket.bucket_arn}/*"
                            ]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=[f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws-glue/*"]
                        )
                    ]
                )
            }
        )

        # Lambda execution role for automation function
        self.lambda_execution_role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"{self.project_name.value_as_string}-lambda-execution-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "GlueOperations": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "glue:StartCrawler",
                                "glue:GetCrawler",
                                "glue:StartJobRun",
                                "glue:GetJobRun",
                                "glue:GetJobRuns"
                            ],
                            resources=[
                                f"arn:aws:glue:{self.region}:{self.account}:crawler/{self.project_name.value_as_string}-*",
                                f"arn:aws:glue:{self.region}:{self.account}:job/{self.project_name.value_as_string}-*"
                            ]
                        )
                    ]
                ),
                "S3ReadAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion"
                            ],
                            resources=[f"{self.raw_data_bucket.bucket_arn}/*"]
                        )
                    ]
                )
            }
        )

        # Add tags to IAM roles
        Tags.of(self.glue_service_role).add("Purpose", "Service role for Glue crawlers and ETL jobs")
        Tags.of(self.glue_service_role).add("Project", self.project_name.value_as_string)
        Tags.of(self.lambda_execution_role).add("Purpose", "Execution role for pipeline automation Lambda")
        Tags.of(self.lambda_execution_role).add("Project", self.project_name.value_as_string)

    def _create_glue_resources(self) -> None:
        """Create Glue database, crawlers, and ETL job."""
        
        # Glue database for data catalog
        self.glue_database = glue.CfnDatabase(
            self, "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=f"{self.project_name.value_as_string}-database",
                description="Database for data visualization pipeline"
            )
        )

        # Crawler for raw data discovery
        self.raw_data_crawler = glue.CfnCrawler(
            self, "RawDataCrawler",
            name=f"{self.project_name.value_as_string}-raw-crawler",
            role=self.glue_service_role.role_arn,
            database_name=self.glue_database.ref,
            description="Crawler for raw sales data discovery",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.raw_data_bucket.bucket_name}/sales-data/"
                    )
                ]
            ),
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG"
            ),
            configuration='{"Version": 1.0, "Grouping": {"TableGroupingPolicy": "CombineCompatibleSchemas"}}'
        )

        # Crawler for processed data discovery
        self.processed_data_crawler = glue.CfnCrawler(
            self, "ProcessedDataCrawler",
            name=f"{self.project_name.value_as_string}-processed-crawler",
            role=self.glue_service_role.role_arn,
            database_name=self.glue_database.ref,
            description="Crawler for processed data discovery",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.processed_data_bucket.bucket_name}/"
                    )
                ]
            ),
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG"
            ),
            configuration='{"Version": 1.0, "Grouping": {"TableGroupingPolicy": "CombineCompatibleSchemas"}}'
        )

        # ETL job for data transformation
        self.data_transformation_job = glue.CfnJob(
            self, "DataTransformationJob",
            name=f"{self.project_name.value_as_string}-etl-job",
            role=self.glue_service_role.role_arn,
            description="ETL job for sales data transformation and enrichment",
            glue_version=self.glue_version.value_as_string,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                python_version="3",
                script_location=f"s3://{self.processed_data_bucket.bucket_name}/scripts/sales-etl.py"
            ),
            default_arguments={
                "--SOURCE_DATABASE": self.glue_database.ref,
                "--TARGET_BUCKET": self.processed_data_bucket.bucket_name,
                "--enable-metrics": "",
                "--enable-continuous-cloudwatch-log": "true",
                "--job-language": "python",
                "--TempDir": f"s3://{self.processed_data_bucket.bucket_name}/temp/"
            },
            execution_property=glue.CfnJob.ExecutionPropertyProperty(
                max_concurrent_runs=2
            ),
            max_retries=1,
            timeout=60,
            worker_type="G.1X",
            number_of_workers=2
        )

        # Add dependencies
        self.raw_data_crawler.add_dependency(self.glue_database)
        self.processed_data_crawler.add_dependency(self.glue_database)
        self.data_transformation_job.add_dependency(self.glue_database)

        # Add tags to Glue resources
        Tags.of(self.raw_data_crawler).add("Purpose", "Raw data schema discovery")
        Tags.of(self.raw_data_crawler).add("Project", self.project_name.value_as_string)
        Tags.of(self.processed_data_crawler).add("Purpose", "Processed data schema discovery")
        Tags.of(self.processed_data_crawler).add("Project", self.project_name.value_as_string)
        Tags.of(self.data_transformation_job).add("Purpose", "Data transformation and enrichment")
        Tags.of(self.data_transformation_job).add("Project", self.project_name.value_as_string)

    def _create_athena_workgroup(self) -> None:
        """Create Athena workgroup for query management and cost control."""
        
        # Configure encryption for query results if enabled
        encryption_config = None
        if self.enable_s3_encryption.value_as_string == "true":
            encryption_config = athena.CfnWorkGroup.EncryptionConfigurationProperty(
                encryption_option="SSE_S3"
            )

        # Create Athena workgroup
        self.athena_workgroup = athena.CfnWorkGroup(
            self, "AthenaWorkGroup",
            name=f"{self.project_name.value_as_string}-workgroup",
            description="Workgroup for data visualization pipeline queries",
            state="ENABLED",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.athena_results_bucket.bucket_name}/",
                    encryption_configuration=encryption_config
                ),
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                bytes_scanned_cutoff_per_query=1000000000  # 1GB limit
            )
        )

        # Add tags
        Tags.of(self.athena_workgroup).add("Purpose", "Query execution management for visualization pipeline")
        Tags.of(self.athena_workgroup).add("Project", self.project_name.value_as_string)

    def _create_lambda_automation(self) -> None:
        """Create Lambda function for pipeline automation."""
        
        # Lambda function code for automation
        automation_code = """
const AWS = require('aws-sdk');
const glue = new AWS.Glue();

const PROJECT_NAME = process.env.PROJECT_NAME;
const RAW_CRAWLER_NAME = process.env.RAW_CRAWLER_NAME;
const ETL_JOB_NAME = process.env.ETL_JOB_NAME;

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    try {
        // Check if new data was uploaded to raw bucket
        for (const record of event.Records) {
            if (record.eventSource === 'aws:s3' && record.eventName.startsWith('ObjectCreated')) {
                const bucketName = record.s3.bucket.name;
                const objectKey = record.s3.object.key;
                
                console.log(`New file uploaded: ${objectKey} in bucket ${bucketName}`);
                
                // Trigger crawler to update schema
                await triggerCrawler(RAW_CRAWLER_NAME);
                
                // Wait a bit then trigger ETL job
                setTimeout(async () => {
                    await triggerETLJob(ETL_JOB_NAME);
                }, 60000); // Wait 1 minute for crawler to complete
            }
        }
        
        return {
            statusCode: 200,
            body: JSON.stringify('Pipeline triggered successfully')
        };
        
    } catch (error) {
        console.error('Error:', error);
        throw error;
    }
};

async function triggerCrawler(crawlerName) {
    try {
        const params = { Name: crawlerName };
        await glue.startCrawler(params).promise();
        console.log(`Started crawler: ${crawlerName}`);
    } catch (error) {
        if (error.code === 'CrawlerRunningException') {
            console.log(`Crawler ${crawlerName} is already running`);
        } else {
            throw error;
        }
    }
}

async function triggerETLJob(jobName) {
    try {
        const params = { JobName: jobName };
        const result = await glue.startJobRun(params).promise();
        console.log(`Started ETL job: ${jobName}, Run ID: ${result.JobRunId}`);
    } catch (error) {
        console.error(`Error starting ETL job ${jobName}:`, error);
        throw error;
    }
}
"""

        # Create Lambda function conditionally
        self.automation_function = lambda_.Function(
            self, "PipelineAutomationFunction",
            function_name=f"{self.project_name.value_as_string}-automation",
            description="Automates pipeline processing when new data is uploaded",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),
            code=lambda_.Code.from_inline(automation_code),
            environment={
                "PROJECT_NAME": self.project_name.value_as_string,
                "RAW_CRAWLER_NAME": self.raw_data_crawler.name,
                "ETL_JOB_NAME": self.data_transformation_job.name
            }
        )

        # Add S3 notification trigger conditionally
        if self.enable_s3_notifications.value_as_string == "true":
            self.raw_data_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.automation_function),
                s3.NotificationKeyFilter(prefix="sales-data/")
            )

        # Add tags
        Tags.of(self.automation_function).add("Purpose", "Automated pipeline processing trigger")
        Tags.of(self.automation_function).add("Project", self.project_name.value_as_string)

    def _create_quicksight_resources(self) -> None:
        """Create QuickSight data source for visualization."""
        
        # QuickSight data source (Athena connection)
        self.quicksight_data_source = quicksight.CfnDataSource(
            self, "QuickSightDataSource",
            aws_account_id=self.account,
            data_source_id=f"{self.project_name.value_as_string}-athena-source",
            name="Sales Analytics Data Source",
            type="ATHENA",
            data_source_parameters=quicksight.CfnDataSource.DataSourceParametersProperty(
                athena_parameters=quicksight.CfnDataSource.AthenaParametersProperty(
                    work_group=self.athena_workgroup.name
                )
            ),
            permissions=[
                quicksight.CfnDataSource.ResourcePermissionProperty(
                    principal=self.quicksight_user_arn.value_as_string,
                    actions=[
                        "quicksight:DescribeDataSource",
                        "quicksight:DescribeDataSourcePermissions",
                        "quicksight:PassDataSource",
                        "quicksight:UpdateDataSource",
                        "quicksight:DeleteDataSource",
                        "quicksight:UpdateDataSourcePermissions"
                    ]
                )
            ]
        )

        # Add tags
        Tags.of(self.quicksight_data_source).add("Purpose", "QuickSight data source for visualization pipeline")
        Tags.of(self.quicksight_data_source).add("Project", self.project_name.value_as_string)

    def _create_etl_script_deployment(self) -> None:
        """Create custom resource to deploy ETL script to S3."""
        
        # ETL script deployment role
        etl_script_deployment_role = iam.Role(
            self, "ETLScriptDeploymentRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ],
            inline_policies={
                "S3Access": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:PutObject",
                                "s3:DeleteObject",
                                "s3:GetObject"
                            ],
                            resources=[f"{self.processed_data_bucket.bucket_arn}/*"]
                        )
                    ]
                )
            }
        )

        # ETL script deployment function
        etl_script_deployment_code = '''
import boto3
import cfnresponse
import json

def handler(event, context):
    try:
        s3 = boto3.client('s3')
        bucket = event['ResourceProperties']['ProcessedBucket']
        project_name = event['ResourceProperties']['ProjectName']
        
        if event['RequestType'] == 'Create' or event['RequestType'] == 'Update':
            # ETL script content
            etl_script = """
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_DATABASE', 'TARGET_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read sales data
    sales_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['SOURCE_DATABASE'],
        table_name="sales_2024_q1_csv"
    ).toDF()
    
    # Data transformations
    # Convert data types
    sales_df = sales_df.withColumn("quantity", F.col("quantity").cast(IntegerType())) \\
                     .withColumn("unit_price", F.col("unit_price").cast(DoubleType())) \\
                     .withColumn("order_date", F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    
    # Calculate total amount
    sales_df = sales_df.withColumn("total_amount", F.col("quantity") * F.col("unit_price"))
    
    # Add derived columns
    sales_df = sales_df.withColumn("order_month", F.month(F.col("order_date"))) \\
                     .withColumn("order_year", F.year(F.col("order_date"))) \\
                     .withColumn("order_quarter", F.quarter(F.col("order_date")))
    
    # Write enriched sales data
    target_bucket = args['TARGET_BUCKET']
    sales_df.write.mode("overwrite").parquet(f"s3://{target_bucket}/enriched-sales/")
    
    # Create monthly sales summary
    monthly_sales = sales_df.groupBy("order_year", "order_month", "region") \\
        .agg(
            F.sum("total_amount").alias("total_revenue"),
            F.count("order_id").alias("total_orders"),
            F.avg("total_amount").alias("avg_order_value"),
            F.countDistinct("customer_id").alias("unique_customers")
        )
    
    monthly_sales.write.mode("overwrite").parquet(f"s3://{target_bucket}/monthly-sales/")
    
    # Product category performance
    category_performance = sales_df.groupBy("product_category", "region") \\
        .agg(
            F.sum("total_amount").alias("category_revenue"),
            F.sum("quantity").alias("total_quantity"),
            F.count("order_id").alias("total_orders")
        )
    
    category_performance.write.mode("overwrite").parquet(f"s3://{target_bucket}/category-performance/")
    
except Exception as e:
    print(f"Error processing data: {str(e)}")
    # Create empty datasets if tables don't exist yet
    schema = StructType([
        StructField("placeholder", StringType(), True)
    ])
    empty_df = spark.createDataFrame([], schema)
    target_bucket = args['TARGET_BUCKET']
    empty_df.write.mode("overwrite").parquet(f"s3://{target_bucket}/enriched-sales/")
    empty_df.write.mode("overwrite").parquet(f"s3://{target_bucket}/monthly-sales/")
    empty_df.write.mode("overwrite").parquet(f"s3://{target_bucket}/category-performance/")

job.commit()
"""
            
            # Upload ETL script to S3
            s3.put_object(
                Bucket=bucket,
                Key='scripts/sales-etl.py',
                Body=etl_script.encode('utf-8'),
                ContentType='text/x-python'
            )
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'Message': 'ETL script deployed successfully'
            })
        
        elif event['RequestType'] == 'Delete':
            # Clean up ETL script
            try:
                s3.delete_object(Bucket=bucket, Key='scripts/sales-etl.py')
            except:
                pass  # Ignore errors during cleanup
            
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {
                'Message': 'ETL script cleanup completed'
            })
    
    except Exception as e:
        print(f'Error: {str(e)}')
        cfnresponse.send(event, context, cfnresponse.FAILED, {
            'Message': f'Error: {str(e)}'
        })
'''

        etl_script_deployment_function = lambda_.Function(
            self, "ETLScriptDeploymentFunction",
            function_name=f"{self.project_name.value_as_string}-etl-script-deployment",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            role=etl_script_deployment_role,
            timeout=Duration.minutes(5),
            code=lambda_.Code.from_inline(etl_script_deployment_code)
        )

        # Custom resource for ETL script deployment
        self.etl_script_deployment = cdk.CustomResource(
            self, "ETLScriptDeployment",
            service_token=etl_script_deployment_function.function_arn,
            properties={
                "ProcessedBucket": self.processed_data_bucket.bucket_name,
                "ProjectName": self.project_name.value_as_string
            }
        )

        # Ensure the bucket exists before deploying script
        self.etl_script_deployment.node.add_dependency(self.processed_data_bucket)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource references."""
        
        # S3 bucket outputs
        CfnOutput(
            self, "RawDataBucketName",
            description="Name of the S3 bucket for raw data storage",
            value=self.raw_data_bucket.bucket_name,
            export_name=f"{self.stack_name}-RawDataBucket"
        )

        CfnOutput(
            self, "ProcessedDataBucketName",
            description="Name of the S3 bucket for processed data storage",
            value=self.processed_data_bucket.bucket_name,
            export_name=f"{self.stack_name}-ProcessedDataBucket"
        )

        CfnOutput(
            self, "AthenaResultsBucketName",
            description="Name of the S3 bucket for Athena query results",
            value=self.athena_results_bucket.bucket_name,
            export_name=f"{self.stack_name}-AthenaResultsBucket"
        )

        # Glue resource outputs
        CfnOutput(
            self, "GlueDatabaseName",
            description="Name of the Glue database for data catalog",
            value=self.glue_database.ref,
            export_name=f"{self.stack_name}-GlueDatabase"
        )

        CfnOutput(
            self, "RawDataCrawlerName",
            description="Name of the Glue crawler for raw data",
            value=self.raw_data_crawler.name,
            export_name=f"{self.stack_name}-RawDataCrawler"
        )

        CfnOutput(
            self, "ProcessedDataCrawlerName",
            description="Name of the Glue crawler for processed data",
            value=self.processed_data_crawler.name,
            export_name=f"{self.stack_name}-ProcessedDataCrawler"
        )

        CfnOutput(
            self, "ETLJobName",
            description="Name of the Glue ETL job for data transformation",
            value=self.data_transformation_job.name,
            export_name=f"{self.stack_name}-ETLJob"
        )

        # Athena and QuickSight outputs
        CfnOutput(
            self, "AthenaWorkGroupName",
            description="Name of the Athena workgroup for query execution",
            value=self.athena_workgroup.name,
            export_name=f"{self.stack_name}-AthenaWorkGroup"
        )

        CfnOutput(
            self, "QuickSightDataSourceId",
            description="ID of the QuickSight data source",
            value=self.quicksight_data_source.ref,
            export_name=f"{self.stack_name}-QuickSightDataSource"
        )

        # Conditional Lambda output
        CfnOutput(
            self, "AutomationFunctionName",
            description="Name of the Lambda function for pipeline automation",
            value=self.automation_function.function_name,
            export_name=f"{self.stack_name}-AutomationFunction",
            condition=self.create_s3_notifications
        )

        # IAM role output
        CfnOutput(
            self, "GlueServiceRoleArn",
            description="ARN of the Glue service role",
            value=self.glue_service_role.role_arn,
            export_name=f"{self.stack_name}-GlueServiceRole"
        )

        # Helpful command outputs
        CfnOutput(
            self, "SampleDataUploadCommand",
            description="AWS CLI command to upload sample data",
            value=f"aws s3 cp your-data-file.csv s3://{self.raw_data_bucket.bucket_name}/sales-data/"
        )

        CfnOutput(
            self, "AthenaQueryLocation",
            description="S3 location for Athena query results",
            value=f"s3://{self.athena_results_bucket.bucket_name}/"
        )

        CfnOutput(
            self, "QuickSightSetupInstructions",
            description="Instructions for setting up QuickSight dashboards",
            value="Use the QuickSight data source to create datasets from the Glue Data Catalog tables, then build visualizations and dashboards"
        )


# ========================================
# CDK APPLICATION
# ========================================

def main() -> None:
    """Main function to create and deploy the CDK application."""
    
    app = App()
    
    # Create the data visualization pipeline stack
    DataVisualizationPipelineStack(
        app, 
        "DataVisualizationPipelineStack",
        description="Comprehensive data visualization pipeline with QuickSight, S3, Glue, Athena, and Lambda automation",
        env=Environment(
            # Uncomment and specify account/region if needed
            # account="123456789012",
            # region="us-east-1"
        )
    )
    
    app.synth()


if __name__ == "__main__":
    main()