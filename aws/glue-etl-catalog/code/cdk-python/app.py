#!/usr/bin/env python3
"""
AWS CDK application for ETL Pipelines with AWS Glue and Data Catalog Management.

This application creates a complete serverless ETL pipeline using AWS Glue services
including crawlers, data catalog, ETL jobs, and supporting infrastructure like S3
buckets and IAM roles.

Author: CDK Generator v1.3
Recipe: etl-pipelines-aws-glue-data-catalog-management
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_iam as iam,
    aws_glue as glue,
    aws_s3_deployment as s3deploy,
    RemovalPolicy,
    CfnOutput,
    Duration,
)
from constructs import Construct


class GlueEtlPipelineStack(Stack):
    """
    CDK Stack for AWS Glue ETL Pipeline with Data Catalog Management.
    
    This stack creates:
    - S3 buckets for raw and processed data
    - IAM roles for Glue services
    - Glue database for data catalog
    - Glue crawlers for data discovery
    - Glue ETL job for data transformation
    - Sample data for demonstration
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        database_name: Optional[str] = None,
        **kwargs: Any
    ) -> None:
        """
        Initialize the Glue ETL Pipeline stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            database_name: Name for the Glue database (optional)
            **kwargs: Additional keyword arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        self.database_name = database_name or f"analytics-database-{unique_suffix}"

        # Create S3 buckets for data storage
        self._create_s3_buckets()
        
        # Create IAM roles for Glue services
        self._create_iam_roles()
        
        # Create Glue database
        self._create_glue_database()
        
        # Deploy sample data
        self._deploy_sample_data()
        
        # Create Glue crawlers
        self._create_glue_crawlers()
        
        # Create Glue ETL job
        self._create_glue_etl_job()
        
        # Create outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for raw and processed data storage."""
        # Raw data bucket
        self.raw_data_bucket = s3.Bucket(
            self,
            "RawDataBucket",
            bucket_name=f"raw-data-{self.account}-{self.region}-{self.node.addr[-8:].lower()}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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

        # Processed data bucket
        self.processed_data_bucket = s3.Bucket(
            self,
            "ProcessedDataBucket",
            bucket_name=f"processed-data-{self.account}-{self.region}-{self.node.addr[-8:].lower()}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
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

    def _create_iam_roles(self) -> None:
        """Create IAM roles for AWS Glue services."""
        # Glue service role
        self.glue_role = iam.Role(
            self,
            "GlueServiceRole",
            role_name=f"GlueServiceRole-{self.node.addr[-8:].lower()}",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="IAM role for AWS Glue ETL jobs and crawlers",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole"),
            ],
            inline_policies={
                "GlueS3Access": iam.PolicyDocument(
                    statements=[
                        # S3 object access
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:PutObject",
                                "s3:DeleteObject"
                            ],
                            resources=[
                                f"{self.raw_data_bucket.bucket_arn}/*",
                                f"{self.processed_data_bucket.bucket_arn}/*"
                            ]
                        ),
                        # S3 bucket access
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:ListBucket",
                                "s3:GetBucketLocation"
                            ],
                            resources=[
                                self.raw_data_bucket.bucket_arn,
                                self.processed_data_bucket.bucket_arn
                            ]
                        ),
                        # CloudWatch Logs
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "logs:CreateLogGroup",
                                "logs:CreateLogStream",
                                "logs:PutLogEvents"
                            ],
                            resources=[
                                f"arn:aws:logs:{self.region}:{self.account}:log-group:/aws-glue/*"
                            ]
                        )
                    ]
                )
            }
        )

    def _create_glue_database(self) -> None:
        """Create Glue database for data catalog."""
        self.glue_database = glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.database_name,
                description="Analytics database for ETL pipeline with comprehensive data catalog management"
            )
        )

    def _deploy_sample_data(self) -> None:
        """Deploy sample data files to S3 for demonstration."""
        # Create sample CSV data
        sales_csv_content = """order_id,customer_id,product_name,quantity,price,order_date
1001,C001,Laptop,1,999.99,2024-01-15
1002,C002,Mouse,2,25.50,2024-01-15
1003,C001,Keyboard,1,75.00,2024-01-16
1004,C003,Monitor,1,299.99,2024-01-16
1005,C002,Headphones,1,149.99,2024-01-17
1006,C003,Webcam,1,89.99,2024-01-17
1007,C001,Desk Pad,2,19.99,2024-01-18
1008,C002,USB Hub,1,34.99,2024-01-18
1009,C003,External Drive,1,129.99,2024-01-19
1010,C001,Wireless Charger,1,49.99,2024-01-19"""

        # Create sample JSON data
        customers_json_content = '''{"customer_id": "C001", "name": "John Smith", "email": "john@email.com", "region": "North", "signup_date": "2023-12-01"}
{"customer_id": "C002", "name": "Jane Doe", "email": "jane@email.com", "region": "South", "signup_date": "2023-11-15"}
{"customer_id": "C003", "name": "Bob Johnson", "email": "bob@email.com", "region": "East", "signup_date": "2023-10-20"}'''

        # Deploy sample data to S3
        s3deploy.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3deploy.Source.data("sales/sample-sales.csv", sales_csv_content),
                s3deploy.Source.data("customers/sample-customers.json", customers_json_content)
            ],
            destination_bucket=self.raw_data_bucket,
            retain_on_delete=False
        )

    def _create_glue_crawlers(self) -> None:
        """Create Glue crawlers for data discovery."""
        # Raw data crawler
        self.raw_data_crawler = glue.CfnCrawler(
            self,
            "RawDataCrawler",
            name=f"data-discovery-crawler-{self.node.addr[-8:].lower()}",
            role=self.glue_role.role_arn,
            database_name=self.database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.raw_data_bucket.bucket_name}/"
                    )
                ]
            ),
            description="Crawler to discover raw data schemas and populate data catalog",
            configuration='''{
                "Version": 1.0,
                "CrawlerOutput": {
                    "Partitions": {"AddOrUpdateBehavior": "InheritFromTable"},
                    "Tables": {"AddOrUpdateBehavior": "MergeNewColumns"}
                },
                "Grouping": {"TableGroupingPolicy": "CombineCompatibleSchemas"}
            }''',
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 6 * * ? *)"  # Daily at 6 AM UTC
            )
        )

        # Processed data crawler
        self.processed_data_crawler = glue.CfnCrawler(
            self,
            "ProcessedDataCrawler",
            name=f"processed-data-crawler-{self.node.addr[-8:].lower()}",
            role=self.glue_role.role_arn,
            database_name=self.database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.processed_data_bucket.bucket_name}/enriched-sales/"
                    )
                ]
            ),
            description="Crawler for processed and transformed data",
            configuration='''{
                "Version": 1.0,
                "CrawlerOutput": {
                    "Partitions": {"AddOrUpdateBehavior": "InheritFromTable"},
                    "Tables": {"AddOrUpdateBehavior": "MergeNewColumns"}
                }
            }'''
        )

        # Add dependencies
        self.raw_data_crawler.add_dependency(self.glue_database)
        self.processed_data_crawler.add_dependency(self.glue_database)

    def _create_glue_etl_job(self) -> None:
        """Create Glue ETL job for data transformation."""
        # ETL script content
        etl_script_content = f'''import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql.functions import col, lit, when, regexp_replace
from datetime import datetime

# Parse job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME'])

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read sales data from catalog
    print("Reading sales data from Glue catalog...")
    sales_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database = "{self.database_name}",
        table_name = "sales"
    )
    
    # Read customer data from catalog
    print("Reading customer data from Glue catalog...")
    customers_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database = "{self.database_name}",
        table_name = "customers"
    )
    
    # Convert to DataFrames for complex transformations
    sales_df = sales_dynamic_frame.toDF()
    customers_df = customers_dynamic_frame.toDF()
    
    print(f"Sales data count: {{sales_df.count()}}")
    print(f"Customer data count: {{customers_df.count()}}")
    
    # Data quality checks and transformations
    # Clean and standardize customer names
    customers_df = customers_df.withColumn(
        "name_cleaned",
        regexp_replace(col("name"), r"[^a-zA-Z0-9\\s]", "")
    )
    
    # Add customer tier based on region
    customers_df = customers_df.withColumn(
        "customer_tier",
        when(col("region") == "North", "Premium")
        .when(col("region") == "South", "Standard")
        .otherwise("Basic")
    )
    
    # Calculate total amount and add business metrics
    sales_df = sales_df.withColumn("total_amount", col("quantity") * col("price"))
    sales_df = sales_df.withColumn(
        "order_size_category",
        when(col("total_amount") >= 500, "Large")
        .when(col("total_amount") >= 100, "Medium")
        .otherwise("Small")
    )
    
    # Join sales with customer data to enrich the dataset
    print("Joining sales and customer data...")
    enriched_sales = sales_df.join(customers_df, "customer_id", "left")
    
    # Add processing timestamp
    enriched_sales = enriched_sales.withColumn(
        "processed_at",
        lit(datetime.now().isoformat())
    )
    
    # Select final columns for output
    final_columns = [
        "order_id", "customer_id", "name_cleaned", "email", "region", "customer_tier",
        "product_name", "quantity", "price", "total_amount", "order_size_category",
        "order_date", "processed_at"
    ]
    
    enriched_sales_final = enriched_sales.select(*final_columns)
    
    print(f"Enriched sales data count: {{enriched_sales_final.count()}}")
    
    # Convert back to DynamicFrame for Glue optimizations
    enriched_dynamic_frame = DynamicFrame.fromDF(
        enriched_sales_final, 
        glueContext, 
        "enriched_sales"
    )
    
    # Write to S3 in Parquet format with partitioning
    print("Writing enriched data to S3...")
    glueContext.write_dynamic_frame.from_options(
        frame = enriched_dynamic_frame,
        connection_type = "s3",
        connection_options = {{
            "path": "s3://{self.processed_data_bucket.bucket_name}/enriched-sales/",
            "partitionKeys": ["region"]
        }},
        format = "parquet",
        transformation_ctx = "enriched_sales_sink"
    )
    
    print("ETL job completed successfully!")
    
except Exception as e:
    print(f"ETL job failed with error: {{str(e)}}")
    raise e

finally:
    job.commit()
'''

        # Deploy ETL script to S3
        s3deploy.BucketDeployment(
            self,
            "ETLScriptDeployment",
            sources=[
                s3deploy.Source.data("scripts/etl-script.py", etl_script_content)
            ],
            destination_bucket=self.processed_data_bucket,
            retain_on_delete=False
        )

        # Create Glue ETL job
        self.glue_job = glue.CfnJob(
            self,
            "GlueETLJob",
            name=f"etl-transformation-job-{self.node.addr[-8:].lower()}",
            role=self.glue_role.role_arn,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                script_location=f"s3://{self.processed_data_bucket.bucket_name}/scripts/etl-script.py",
                python_version="3"
            ),
            default_arguments={
                "--job-language": "python",
                "--job-bookmark-option": "job-bookmark-enable",
                "--enable-metrics": "true",
                "--enable-spark-ui": "true",
                "--spark-event-logs-path": f"s3://{self.processed_data_bucket.bucket_name}/spark-logs/",
                "--enable-continuous-cloudwatch-log": "true",
                "--TempDir": f"s3://{self.processed_data_bucket.bucket_name}/temp/"
            },
            description="ETL job for transforming and enriching sales data with customer information",
            glue_version="4.0",
            max_retries=1,
            timeout=60,
            worker_type="G.1X",
            number_of_workers=2,
            execution_property=glue.CfnJob.ExecutionPropertyProperty(
                max_concurrent_runs=1
            )
        )

        # Add dependencies
        self.glue_job.add_dependency(self.glue_database)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.database_name,
            description="Name of the Glue database for data catalog"
        )

        CfnOutput(
            self,
            "RawDataBucketName",
            value=self.raw_data_bucket.bucket_name,
            description="S3 bucket for raw data storage"
        )

        CfnOutput(
            self,
            "ProcessedDataBucketName",
            value=self.processed_data_bucket.bucket_name,
            description="S3 bucket for processed data storage"
        )

        CfnOutput(
            self,
            "GlueRoleArn",
            value=self.glue_role.role_arn,
            description="ARN of the IAM role used by Glue services"
        )

        CfnOutput(
            self,
            "RawDataCrawlerName",
            value=self.raw_data_crawler.name,
            description="Name of the Glue crawler for raw data discovery"
        )

        CfnOutput(
            self,
            "ProcessedDataCrawlerName",
            value=self.processed_data_crawler.name,
            description="Name of the Glue crawler for processed data"
        )

        CfnOutput(
            self,
            "ETLJobName",
            value=self.glue_job.name,
            description="Name of the Glue ETL job for data transformation"
        )

        CfnOutput(
            self,
            "AthenaQueryLocation",
            value=f"s3://{self.processed_data_bucket.bucket_name}/athena-results/",
            description="S3 location for Athena query results"
        )


def main() -> None:
    """Main application entry point."""
    app = cdk.App()
    
    # Get configuration from context or environment
    env = cdk.Environment(
        account=os.getenv('CDK_DEFAULT_ACCOUNT'),
        region=os.getenv('CDK_DEFAULT_REGION')
    )
    
    # Create the stack
    GlueEtlPipelineStack(
        app,
        "GlueEtlPipelineStack",
        env=env,
        description="AWS Glue ETL Pipeline with Data Catalog Management - Complete serverless data processing solution",
        tags={
            "Project": "ETL-Pipeline",
            "Recipe": "etl-pipelines-aws-glue-data-catalog-management",
            "Environment": "Development",
            "CostCenter": "Analytics",
            "Owner": "DataEngineering"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()