#!/usr/bin/env python3
"""
AWS CDK Python Application for Data Pipeline Orchestration with AWS Glue Workflows

This application creates a comprehensive data pipeline orchestration system using AWS Glue Workflows,
including S3 buckets, IAM roles, Glue jobs, crawlers, and triggers for automated ETL processing.
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_iam as iam,
    aws_glue as glue,
    aws_logs as logs,
)
from constructs import Construct


class DataPipelineOrchestrationStack(Stack):
    """
    CDK Stack for Data Pipeline Orchestration with AWS Glue Workflows.
    
    This stack creates:
    - S3 buckets for raw and processed data
    - IAM role for Glue service
    - Glue Data Catalog database
    - Glue crawlers for source and target data
    - Glue ETL job for data processing
    - Glue workflow with schedule and event triggers
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        project_name: str = "data-pipeline",
        environment: str = "dev",
        schedule_expression: str = "cron(0 2 * * ? *)",
        glue_version: str = "4.0",
        **kwargs: Any
    ) -> None:
        """
        Initialize the DataPipelineOrchestrationStack.

        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            project_name: Name prefix for resources
            environment: Environment name (dev, staging, prod)
            schedule_expression: Cron expression for workflow schedule
            glue_version: AWS Glue version to use
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        self.project_name = project_name
        self.environment = environment
        self.resource_prefix = f"{project_name}-{environment}-{unique_suffix}"

        # Create S3 buckets
        self.raw_data_bucket = self._create_raw_data_bucket()
        self.processed_data_bucket = self._create_processed_data_bucket()

        # Create IAM role for Glue
        self.glue_role = self._create_glue_service_role()

        # Create Glue Data Catalog database
        self.glue_database = self._create_glue_database()

        # Create Glue crawlers
        self.source_crawler = self._create_source_crawler()
        self.target_crawler = self._create_target_crawler()

        # Create Glue ETL job
        self.etl_job = self._create_etl_job(glue_version)

        # Create Glue workflow with triggers
        self.workflow = self._create_workflow()
        self.schedule_trigger = self._create_schedule_trigger(schedule_expression)
        self.crawler_success_trigger = self._create_crawler_success_trigger()
        self.job_success_trigger = self._create_job_success_trigger()

        # Create CloudWatch log group for centralized logging
        self.log_group = self._create_log_group()

        # Upload sample data and ETL script
        self._upload_sample_resources()

        # Create stack outputs
        self._create_outputs()

    def _create_raw_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for raw data storage."""
        return s3.Bucket(
            self,
            "RawDataBucket",
            bucket_name=f"{self.resource_prefix}-raw-data",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_processed_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for processed data storage."""
        return s3.Bucket(
            self,
            "ProcessedDataBucket",
            bucket_name=f"{self.resource_prefix}-processed-data",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_glue_service_role(self) -> iam.Role:
        """Create IAM role for AWS Glue service with necessary permissions."""
        role = iam.Role(
            self,
            "GlueServiceRole",
            role_name=f"{self.resource_prefix}-glue-role",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="IAM role for AWS Glue workflow operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueServiceRole"
                )
            ],
        )

        # Add custom policy for S3 access
        s3_policy = iam.Policy(
            self,
            "GlueS3AccessPolicy",
            policy_name=f"{self.resource_prefix}-s3-access",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                    ],
                    resources=[
                        self.raw_data_bucket.bucket_arn,
                        f"{self.raw_data_bucket.bucket_arn}/*",
                        self.processed_data_bucket.bucket_arn,
                        f"{self.processed_data_bucket.bucket_arn}/*",
                    ],
                )
            ],
        )
        role.attach_inline_policy(s3_policy)

        return role

    def _create_glue_database(self) -> glue.CfnDatabase:
        """Create AWS Glue Data Catalog database."""
        return glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=f"{self.resource_prefix.replace('-', '_')}_database",
                description="Database for data pipeline workflow catalog",
                parameters={
                    "environment": self.environment,
                    "project": self.project_name,
                },
            ),
        )

    def _create_source_crawler(self) -> glue.CfnCrawler:
        """Create Glue crawler for source data discovery."""
        return glue.CfnCrawler(
            self,
            "SourceCrawler",
            name=f"{self.resource_prefix}-source-crawler",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            description="Crawler to discover source data schema",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.raw_data_bucket.bucket_name}/input/"
                    )
                ]
            ),
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG",
            ),
        )

    def _create_target_crawler(self) -> glue.CfnCrawler:
        """Create Glue crawler for processed data discovery."""
        return glue.CfnCrawler(
            self,
            "TargetCrawler",
            name=f"{self.resource_prefix}-target-crawler",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            description="Crawler to discover processed data schema",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.processed_data_bucket.bucket_name}/output/"
                    )
                ]
            ),
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG",
            ),
        )

    def _create_etl_job(self, glue_version: str) -> glue.CfnJob:
        """Create AWS Glue ETL job for data processing."""
        return glue.CfnJob(
            self,
            "ETLJob",
            name=f"{self.resource_prefix}-etl-job",
            role=self.glue_role.role_arn,
            description="ETL job for data processing in workflow",
            glue_version=glue_version,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                script_location=f"s3://{self.processed_data_bucket.bucket_name}/scripts/etl-script.py",
                python_version="3",
            ),
            default_arguments={
                "--DATABASE_NAME": self.glue_database.ref,
                "--OUTPUT_BUCKET": self.processed_data_bucket.bucket_name,
                "--TempDir": f"s3://{self.processed_data_bucket.bucket_name}/temp/",
                "--job-bookmark-option": "job-bookmark-enable",
                "--enable-continuous-cloudwatch-log": "true",
                "--enable-metrics": "true",
            },
            max_retries=1,
            timeout=60,
            max_capacity=2.0,
        )

    def _create_workflow(self) -> glue.CfnWorkflow:
        """Create AWS Glue workflow for orchestration."""
        return glue.CfnWorkflow(
            self,
            "DataPipelineWorkflow",
            name=f"{self.resource_prefix}-workflow",
            description="Data pipeline workflow orchestrating crawlers and ETL jobs",
            max_concurrent_runs=1,
            default_run_properties={
                "environment": self.environment,
                "pipeline_version": "1.0",
                "project": self.project_name,
            },
        )

    def _create_schedule_trigger(self, schedule_expression: str) -> glue.CfnTrigger:
        """Create schedule trigger to start the workflow."""
        return glue.CfnTrigger(
            self,
            "ScheduleTrigger",
            name=f"{self.resource_prefix}-schedule-trigger",
            workflow_name=self.workflow.ref,
            type="SCHEDULED",
            schedule=schedule_expression,
            description="Daily trigger to start workflow",
            start_on_creation=True,
            actions=[
                glue.CfnTrigger.ActionProperty(
                    crawler_name=self.source_crawler.ref
                )
            ],
        )

    def _create_crawler_success_trigger(self) -> glue.CfnTrigger:
        """Create event trigger for ETL job after crawler success."""
        return glue.CfnTrigger(
            self,
            "CrawlerSuccessTrigger",
            name=f"{self.resource_prefix}-crawler-success-trigger",
            workflow_name=self.workflow.ref,
            type="CONDITIONAL",
            description="Trigger ETL job after successful crawler completion",
            start_on_creation=True,
            predicate=glue.CfnTrigger.PredicateProperty(
                logical="AND",
                conditions=[
                    glue.CfnTrigger.ConditionProperty(
                        logical_operator="EQUALS",
                        crawler_name=self.source_crawler.ref,
                        crawl_state="SUCCEEDED",
                    )
                ],
            ),
            actions=[
                glue.CfnTrigger.ActionProperty(
                    job_name=self.etl_job.ref
                )
            ],
        )

    def _create_job_success_trigger(self) -> glue.CfnTrigger:
        """Create event trigger for target crawler after job success."""
        return glue.CfnTrigger(
            self,
            "JobSuccessTrigger",
            name=f"{self.resource_prefix}-job-success-trigger",
            workflow_name=self.workflow.ref,
            type="CONDITIONAL",
            description="Trigger target crawler after successful job completion",
            start_on_creation=True,
            predicate=glue.CfnTrigger.PredicateProperty(
                logical="AND",
                conditions=[
                    glue.CfnTrigger.ConditionProperty(
                        logical_operator="EQUALS",
                        job_name=self.etl_job.ref,
                        state="SUCCEEDED",
                    )
                ],
            ),
            actions=[
                glue.CfnTrigger.ActionProperty(
                    crawler_name=self.target_crawler.ref
                )
            ],
        )

    def _create_log_group(self) -> logs.LogGroup:
        """Create CloudWatch log group for centralized logging."""
        return logs.LogGroup(
            self,
            "WorkflowLogGroup",
            log_group_name=f"/aws/glue/{self.resource_prefix}-workflow",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY,
        )

    def _upload_sample_resources(self) -> None:
        """Upload sample data and ETL script to S3."""
        # ETL script content
        etl_script_content = '''import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Read data from the catalog
datasource0 = glueContext.create_dynamic_frame.from_catalog(
    database=args['DATABASE_NAME'],
    table_name="input"
)

# Apply transformations
mapped_data = ApplyMapping.apply(
    frame=datasource0,
    mappings=[
        ("customer_id", "string", "customer_id", "int"),
        ("name", "string", "customer_name", "string"),
        ("email", "string", "email", "string"),
        ("purchase_amount", "string", "purchase_amount", "double"),
        ("purchase_date", "string", "purchase_date", "string")
    ]
)

# Write to S3
glueContext.write_dynamic_frame.from_options(
    frame=mapped_data,
    connection_type="s3",
    connection_options={"path": f"s3://{args['OUTPUT_BUCKET']}/output/"},
    format="parquet"
)

job.commit()
'''

        # Sample data content
        sample_data_content = '''customer_id,name,email,purchase_amount,purchase_date
1,John Doe,john@example.com,150.00,2024-01-15
2,Jane Smith,jane@example.com,200.00,2024-01-16
3,Bob Johnson,bob@example.com,75.00,2024-01-17
4,Alice Brown,alice@example.com,300.00,2024-01-18
5,Charlie Wilson,charlie@example.com,125.00,2024-01-19
'''

        # Upload ETL script
        s3.BucketDeployment(
            self,
            "ETLScriptDeployment",
            sources=[cdk.aws_s3_deployment.Source.data("etl-script.py", etl_script_content)],
            destination_bucket=self.processed_data_bucket,
            destination_key_prefix="scripts/",
        )

        # Upload sample data
        s3.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[cdk.aws_s3_deployment.Source.data("sample-data.csv", sample_data_content)],
            destination_bucket=self.raw_data_bucket,
            destination_key_prefix="input/",
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "WorkflowName",
            value=self.workflow.ref,
            description="Name of the AWS Glue workflow",
            export_name=f"{self.stack_name}-workflow-name",
        )

        CfnOutput(
            self,
            "RawDataBucketName",
            value=self.raw_data_bucket.bucket_name,
            description="Name of the S3 bucket for raw data",
            export_name=f"{self.stack_name}-raw-bucket",
        )

        CfnOutput(
            self,
            "ProcessedDataBucketName",
            value=self.processed_data_bucket.bucket_name,
            description="Name of the S3 bucket for processed data",
            export_name=f"{self.stack_name}-processed-bucket",
        )

        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="Name of the AWS Glue database",
            export_name=f"{self.stack_name}-database-name",
        )

        CfnOutput(
            self,
            "GlueRoleArn",
            value=self.glue_role.role_arn,
            description="ARN of the AWS Glue service role",
            export_name=f"{self.stack_name}-glue-role-arn",
        )

        CfnOutput(
            self,
            "SourceCrawlerName",
            value=self.source_crawler.ref,
            description="Name of the source data crawler",
            export_name=f"{self.stack_name}-source-crawler",
        )

        CfnOutput(
            self,
            "TargetCrawlerName",
            value=self.target_crawler.ref,
            description="Name of the target data crawler",
            export_name=f"{self.stack_name}-target-crawler",
        )

        CfnOutput(
            self,
            "ETLJobName",
            value=self.etl_job.ref,
            description="Name of the AWS Glue ETL job",
            export_name=f"{self.stack_name}-etl-job",
        )


class DataPipelineOrchestrationApp(cdk.App):
    """CDK Application for Data Pipeline Orchestration."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment or use defaults
        project_name = os.getenv("PROJECT_NAME", "data-pipeline")
        environment = os.getenv("ENVIRONMENT", "dev")
        aws_region = os.getenv("AWS_REGION", "us-east-1")
        aws_account = os.getenv("AWS_ACCOUNT_ID")

        # Create the main stack
        DataPipelineOrchestrationStack(
            self,
            f"{project_name}-{environment}-stack",
            project_name=project_name,
            environment=environment,
            env=cdk.Environment(
                account=aws_account,
                region=aws_region,
            ),
            description="AWS CDK stack for data pipeline orchestration with Glue workflows",
        )


def main() -> None:
    """Main entry point for the CDK application."""
    app = DataPipelineOrchestrationApp()
    app.synth()


if __name__ == "__main__":
    main()