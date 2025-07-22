#!/usr/bin/env python3
"""
Analytics-Optimized Data Storage with S3 Tables CDK Application

This CDK application deploys a complete analytics infrastructure using Amazon S3 Tables
with Apache Iceberg support, providing optimized storage for analytics workloads.

The stack includes:
- S3 Table Bucket with namespace organization
- Apache Iceberg table configuration
- AWS Glue Data Catalog integration
- Amazon Athena workgroup for interactive querying
- IAM roles and policies for secure access
- Sample data infrastructure for testing

Features:
- Built-in Apache Iceberg support with automatic maintenance
- 3x faster query performance compared to self-managed tables
- 10x higher transactions per second
- Automated compaction and file management
- Schema evolution and time travel capabilities
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_s3 as s3,
    aws_glue as glue,
    aws_athena as athena,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3_deployment as s3deploy,
)
from constructs import Construct


class AnalyticsOptimizedS3TablesStack(Stack):
    """
    CDK Stack for Analytics-Optimized Data Storage with S3 Tables
    
    This stack creates a comprehensive analytics infrastructure leveraging Amazon S3 Tables
    with Apache Iceberg format for optimized analytics workloads. The architecture includes
    automated maintenance operations, AWS analytics services integration, and enterprise-grade
    data management capabilities.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        **kwargs: Any
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource naming
        self.unique_suffix = self.node.try_get_context("unique_suffix") or "dev"
        
        # Configuration parameters
        self.table_bucket_name = f"analytics-tables-{self.unique_suffix}"
        self.namespace_name = "sales_analytics"
        self.table_name = "transaction_data"
        self.glue_database_name = f"s3-tables-analytics-{self.unique_suffix}"
        
        # Create core infrastructure components
        self._create_iam_roles()
        self._create_s3_table_bucket()
        self._create_glue_database()
        self._create_athena_workgroup()
        self._create_sample_data_infrastructure()
        self._create_outputs()

    def _create_iam_roles(self) -> None:
        """Create IAM roles for S3 Tables and analytics services integration."""
        
        # Service role for AWS Glue to access S3 Tables
        self.glue_service_role = iam.Role(
            self,
            "GlueS3TablesServiceRole",
            role_name=f"S3TablesGlueServiceRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="Service role for AWS Glue to access S3 Tables and Data Catalog",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole")
            ],
        )

        # Custom policy for S3 Tables access
        s3_tables_policy = iam.Policy(
            self,
            "S3TablesAccessPolicy",
            policy_name=f"S3TablesAccess-{self.unique_suffix}",
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3tables:GetTable",
                        "s3tables:GetTableMetadataLocation",
                        "s3tables:ListTables",
                        "s3tables:GetTableBucket",
                        "s3tables:ListNamespaces",
                    ],
                    resources=["*"],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:GetObjectVersion",
                        "s3:PutObject",
                        "s3:DeleteObject",
                        "s3:ListBucket",
                    ],
                    resources=[
                        f"arn:aws:s3:::{self.table_bucket_name}",
                        f"arn:aws:s3:::{self.table_bucket_name}/*",
                    ],
                ),
            ],
        )

        # Attach policy to Glue service role
        self.glue_service_role.attach_inline_policy(s3_tables_policy)

        # Athena execution role
        self.athena_execution_role = iam.Role(
            self,
            "AthenaExecutionRole",
            role_name=f"S3TablesAthenaRole-{self.unique_suffix}",
            assumed_by=iam.ServicePrincipal("athena.amazonaws.com"),
            description="Execution role for Athena to query S3 Tables",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonAthenaFullAccess")
            ],
        )

        # Attach S3 Tables policy to Athena role
        self.athena_execution_role.attach_inline_policy(s3_tables_policy)

    def _create_s3_table_bucket(self) -> None:
        """
        Create S3 Table Bucket for analytics workloads.
        
        Note: S3 Tables are created via AWS CLI or API calls as CDK doesn't yet
        have native L2 constructs. This method creates supporting infrastructure.
        """
        
        # Create CloudWatch log group for S3 Tables operations
        self.s3_tables_log_group = logs.LogGroup(
            self,
            "S3TablesLogGroup",
            log_group_name=f"/aws/s3tables/{self.table_bucket_name}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Custom resource to create S3 Table Bucket via AWS CLI
        # Note: This is a placeholder for the actual S3 Tables creation
        # In production, use AWS CLI or AWS SDK in a custom resource Lambda
        
        # Output the table bucket configuration for manual creation
        CfnOutput(
            self,
            "TableBucketName",
            value=self.table_bucket_name,
            description="Name for the S3 Table Bucket to be created manually",
        )

        CfnOutput(
            self,
            "TableNamespace",
            value=self.namespace_name,
            description="Namespace for organizing tables within the bucket",
        )

        CfnOutput(
            self,
            "TableName",
            value=self.table_name,
            description="Name of the Apache Iceberg table to be created",
        )

    def _create_glue_database(self) -> None:
        """Create AWS Glue Data Catalog database for S3 Tables integration."""
        
        self.glue_database = glue.CfnDatabase(
            self,
            "S3TablesDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.glue_database_name,
                description="AWS Glue database for S3 Tables analytics integration",
                parameters={
                    "classification": "iceberg",
                    "typeOfData": "table",
                    "has_encrypted_data": "false",
                    "created_by": "aws-cdk",
                },
            ),
        )

        # Output database information
        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="AWS Glue Data Catalog database name",
        )

    def _create_athena_workgroup(self) -> None:
        """Create Amazon Athena workgroup for S3 Tables querying."""
        
        # S3 bucket for Athena query results
        self.athena_results_bucket = s3.Bucket(
            self,
            "AthenaResultsBucket",
            bucket_name=f"aws-athena-query-results-{self.account}-{self.region}-{self.unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AthenaResultsCleanup",
                    enabled=True,
                    expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                )
            ],
        )

        # Athena workgroup configuration
        self.athena_workgroup = athena.CfnWorkGroup(
            self,
            "S3TablesWorkGroup",
            name=f"s3-tables-workgroup-{self.unique_suffix}",
            description="Workgroup for querying S3 Tables with optimized performance",
            state="ENABLED",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                enforce_work_group_configuration=True,
                publish_cloud_watch_metrics=True,
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.athena_results_bucket.bucket_name}/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3"
                    ),
                ),
                engine_version=athena.CfnWorkGroup.EngineVersionProperty(
                    selected_engine_version="Athena engine version 3"
                ),
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="S3TablesAnalytics"),
                cdk.CfnTag(key="Environment", value=self.unique_suffix),
            ],
        )

        # Grant Athena access to results bucket
        self.athena_results_bucket.grant_read_write(self.athena_execution_role)

        # Output Athena workgroup information
        CfnOutput(
            self,
            "AthenaWorkGroupName",
            value=self.athena_workgroup.ref,
            description="Athena workgroup for S3 Tables queries",
        )

        CfnOutput(
            self,
            "AthenaResultsBucketName",
            value=self.athena_results_bucket.bucket_name,
            description="S3 bucket for Athena query results",
        )

    def _create_sample_data_infrastructure(self) -> None:
        """Create infrastructure for sample data ingestion and ETL processing."""
        
        # S3 bucket for sample data storage and ETL processing
        self.data_ingestion_bucket = s3.Bucket(
            self,
            "DataIngestionBucket",
            bucket_name=f"glue-etl-data-{self.unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DataIngestionCleanup",
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
                )
            ],
        )

        # Create sample transaction data file
        sample_data_content = """transaction_id,customer_id,product_id,quantity,price,transaction_date,region
1,101,501,2,29.99,2024-01-15,us-east-1
2,102,502,1,149.99,2024-01-15,us-west-2
3,103,503,3,19.99,2024-01-16,eu-west-1
4,104,501,1,29.99,2024-01-16,us-east-1
5,105,504,2,79.99,2024-01-17,ap-southeast-1
6,106,505,1,199.99,2024-01-17,us-east-1
7,107,506,4,9.99,2024-01-18,eu-central-1
8,108,507,2,59.99,2024-01-18,ap-southeast-2
9,109,508,1,299.99,2024-01-19,us-west-1
10,110,509,3,39.99,2024-01-19,us-east-1"""

        # Deploy sample data to S3
        self.sample_data_deployment = s3deploy.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[s3deploy.Source.data("input/sample_transactions.csv", sample_data_content)],
            destination_bucket=self.data_ingestion_bucket,
            destination_key_prefix="input/",
        )

        # Grant Glue service role access to data ingestion bucket
        self.data_ingestion_bucket.grant_read_write(self.glue_service_role)

        # Output data ingestion bucket information
        CfnOutput(
            self,
            "DataIngestionBucketName",
            value=self.data_ingestion_bucket.bucket_name,
            description="S3 bucket for data ingestion and ETL processing",
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for stack information and deployment verification."""
        
        # Deployment commands for manual S3 Tables creation
        CfnOutput(
            self,
            "CreateTableBucketCommand",
            value=f"aws s3tables create-table-bucket --name {self.table_bucket_name}",
            description="AWS CLI command to create the S3 table bucket",
        )

        CfnOutput(
            self,
            "CreateNamespaceCommand",
            value=f"aws s3tables create-namespace --table-bucket-arn arn:aws:s3tables:{self.region}:{self.account}:bucket/{self.table_bucket_name} --namespace {self.namespace_name}",
            description="AWS CLI command to create the table namespace",
        )

        CfnOutput(
            self,
            "CreateTableCommand",
            value=f"aws s3tables create-table --table-bucket-arn arn:aws:s3tables:{self.region}:{self.account}:bucket/{self.table_bucket_name} --namespace {self.namespace_name} --name {self.table_name} --format ICEBERG",
            description="AWS CLI command to create the Apache Iceberg table",
        )

        # Analytics integration information
        CfnOutput(
            self,
            "AthenaQueryExample",
            value=f'SELECT COUNT(*) FROM "{self.glue_database_name}"."{self.table_name}";',
            description="Example Athena SQL query for the S3 Tables data",
        )

        CfnOutput(
            self,
            "QuickSightDataSourceInfo",
            value=f"Connect QuickSight to Athena workgroup: {self.athena_workgroup.ref}",
            description="Information for connecting QuickSight to the analytics infrastructure",
        )

        # IAM role information for manual configuration
        CfnOutput(
            self,
            "GlueServiceRoleArn",
            value=self.glue_service_role.role_arn,
            description="ARN of the Glue service role for S3 Tables access",
        )

        CfnOutput(
            self,
            "AthenaExecutionRoleArn",
            value=self.athena_execution_role.role_arn,
            description="ARN of the Athena execution role for S3 Tables queries",
        )


# CDK Application
app = cdk.App()

# Get environment configuration
env = Environment(
    account=os.getenv("CDK_DEFAULT_ACCOUNT"),
    region=os.getenv("CDK_DEFAULT_REGION", "us-east-1"),
)

# Deploy the stack
AnalyticsOptimizedS3TablesStack(
    app,
    "AnalyticsOptimizedS3TablesStack",
    env=env,
    description="Analytics-Optimized Data Storage with S3 Tables and Apache Iceberg",
    tags={
        "Project": "S3TablesAnalytics",
        "Environment": app.node.try_get_context("unique_suffix") or "dev",
        "Purpose": "AnalyticsOptimizedStorage",
        "Recipe": "analytics-optimized-data-storage-s3-tables",
    },
)

# Synthesize the CloudFormation template
app.synth()