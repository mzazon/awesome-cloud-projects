#!/usr/bin/env python3
"""
AWS CDK Python Application for Analytics-Ready Data Storage with S3 Tables

This application creates a complete analytics infrastructure using Amazon S3 Tables
with Apache Iceberg format for optimized tabular data storage and querying.

Features:
- S3 Table Bucket for analytics data storage
- Namespace for logical data organization
- Apache Iceberg tables for structured data
- Athena integration for SQL queries
- AWS Glue Data Catalog integration
- IAM roles and policies for secure access
"""

import os
from typing import Dict, Any, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_s3tables as s3tables,
    aws_athena as athena,
    aws_glue as glue,
    aws_iam as iam,
)
from constructs import Construct


class AnalyticsS3TablesStack(Stack):
    """
    CDK Stack for Analytics-Ready Data Storage with S3 Tables.
    
    This stack creates:
    - S3 Table Bucket optimized for analytics workloads
    - Namespace for data organization
    - Sample Iceberg table for customer events
    - Athena workgroup for querying
    - IAM roles and policies for secure access
    - Integration with AWS Glue Data Catalog
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        table_bucket_name: Optional[str] = None,
        namespace_name: str = "analytics_data",
        sample_table_name: str = "customer_events",
        athena_workgroup_name: str = "s3-tables-workgroup",
        **kwargs: Any
    ) -> None:
        """
        Initialize the Analytics S3 Tables stack.

        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            table_bucket_name: Name for the S3 table bucket (auto-generated if None)
            namespace_name: Name for the S3 Tables namespace
            sample_table_name: Name for the sample table
            athena_workgroup_name: Name for the Athena workgroup
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique resource names if not provided
        self.unique_suffix = self._generate_unique_suffix()
        self.table_bucket_name = table_bucket_name or f"analytics-data-{self.unique_suffix}"
        self.namespace_name = namespace_name
        self.sample_table_name = sample_table_name
        self.athena_workgroup_name = athena_workgroup_name

        # Create supporting S3 bucket for Athena query results
        self.athena_results_bucket = self._create_athena_results_bucket()

        # Create S3 Table Bucket for analytics storage
        self.table_bucket = self._create_table_bucket()

        # Create namespace for logical data organization
        self.namespace = self._create_namespace()

        # Create sample Iceberg table
        self.sample_table = self._create_sample_table()

        # Create IAM roles for analytics services integration
        self.analytics_role = self._create_analytics_role()

        # Configure table bucket policy for AWS services integration
        self._configure_table_bucket_policy()

        # Create Athena workgroup for S3 Tables queries
        self.athena_workgroup = self._create_athena_workgroup()

        # Create AWS Glue database for table catalog integration
        self.glue_database = self._create_glue_database()

        # Output important resource information
        self._create_outputs()

    def _generate_unique_suffix(self) -> str:
        """Generate a unique suffix for resource naming."""
        import string
        import secrets
        
        # Generate 6-character lowercase alphanumeric suffix
        alphabet = string.ascii_lowercase + string.digits
        return ''.join(secrets.choice(alphabet) for _ in range(6))

    def _create_athena_results_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing Athena query results.
        
        Returns:
            S3 bucket for Athena query results
        """
        bucket = s3.Bucket(
            self,
            "AthenaResultsBucket",
            bucket_name=f"athena-results-{self.unique_suffix}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldQueryResults",
                    enabled=True,
                    expiration=Duration.days(30),
                    abort_incomplete_multipart_upload_after=Duration.days(1),
                )
            ],
        )

        # Add tags for cost tracking and organization
        cdk.Tags.of(bucket).add("Purpose", "AthenaQueryResults")
        cdk.Tags.of(bucket).add("Component", "Analytics")

        return bucket

    def _create_table_bucket(self) -> s3tables.CfnTableBucket:
        """
        Create S3 Table Bucket optimized for analytics workloads.
        
        Returns:
            S3 Table Bucket for storing Iceberg tables
        """
        table_bucket = s3tables.CfnTableBucket(
            self,
            "AnalyticsTableBucket",
            name=self.table_bucket_name,
        )

        # Add tags for resource organization
        table_bucket.tags = [
            cdk.CfnTag(key="Purpose", value="AnalyticsStorage"),
            cdk.CfnTag(key="Format", value="ApacheIceberg"),
            cdk.CfnTag(key="Component", value="Analytics"),
        ]

        return table_bucket

    def _create_namespace(self) -> s3tables.CfnNamespace:
        """
        Create namespace for logical data organization.
        
        Returns:
            S3 Tables namespace for organizing related tables
        """
        namespace = s3tables.CfnNamespace(
            self,
            "AnalyticsNamespace",
            table_bucket_arn=self.table_bucket.attr_arn,
            namespace=self.namespace_name,
        )

        # Ensure namespace is created after table bucket
        namespace.add_dependency(self.table_bucket)

        return namespace

    def _create_sample_table(self) -> s3tables.CfnTable:
        """
        Create sample Apache Iceberg table for customer events.
        
        Returns:
            S3 Tables Iceberg table for storing structured data
        """
        table = s3tables.CfnTable(
            self,
            "CustomerEventsTable",
            table_bucket_arn=self.table_bucket.attr_arn,
            namespace=self.namespace_name,
            name=self.sample_table_name,
            format="ICEBERG",
        )

        # Ensure table is created after namespace
        table.add_dependency(self.namespace)

        return table

    def _create_analytics_role(self) -> iam.Role:
        """
        Create IAM role for AWS analytics services integration.
        
        Returns:
            IAM role with permissions for analytics services
        """
        role = iam.Role(
            self,
            "AnalyticsServicesRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("glue.amazonaws.com"),
                iam.ServicePrincipal("athena.amazonaws.com"),
            ),
            description="Role for AWS analytics services to access S3 Tables",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole"),
            ],
        )

        # Add custom policy for S3 Tables access
        s3_tables_policy = iam.Policy(
            self,
            "S3TablesAccessPolicy",
            document=iam.PolicyDocument(
                statements=[
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        actions=[
                            "s3tables:GetTable",
                            "s3tables:GetTableMetadata",
                            "s3tables:ListTables",
                            "s3tables:GetNamespace",
                            "s3tables:ListNamespaces",
                        ],
                        resources=[
                            self.table_bucket.attr_arn,
                            f"{self.table_bucket.attr_arn}/*",
                        ],
                    ),
                    iam.PolicyStatement(
                        effect=iam.Effect.ALLOW,
                        actions=[
                            "s3:GetObject",
                            "s3:PutObject",
                            "s3:DeleteObject",
                            "s3:ListBucket",
                        ],
                        resources=[
                            self.athena_results_bucket.bucket_arn,
                            f"{self.athena_results_bucket.bucket_arn}/*",
                        ],
                    ),
                ]
            ),
        )

        role.attach_inline_policy(s3_tables_policy)
        return role

    def _configure_table_bucket_policy(self) -> None:
        """Configure table bucket policy for AWS services integration."""
        # Note: Table bucket policy is configured through the resource policy
        # This is handled automatically by the S3 Tables service integration
        pass

    def _create_athena_workgroup(self) -> athena.CfnWorkGroup:
        """
        Create Athena workgroup for S3 Tables queries.
        
        Returns:
            Athena workgroup configured for analytics queries
        """
        workgroup = athena.CfnWorkGroup(
            self,
            "S3TablesWorkGroup",
            name=self.athena_workgroup_name,
            description="Workgroup for querying S3 Tables with Apache Iceberg format",
            state="ENABLED",
            work_group_configuration=athena.CfnWorkGroup.WorkGroupConfigurationProperty(
                enforce_work_group_configuration=True,
                result_configuration=athena.CfnWorkGroup.ResultConfigurationProperty(
                    output_location=f"s3://{self.athena_results_bucket.bucket_name}/",
                    encryption_configuration=athena.CfnWorkGroup.EncryptionConfigurationProperty(
                        encryption_option="SSE_S3"
                    ),
                ),
                engine_version=athena.CfnWorkGroup.EngineVersionProperty(
                    selected_engine_version="Athena engine version 3"
                ),
                bytes_scanned_cutoff_per_query=1000000000,  # 1GB limit
                publish_cloud_watch_metrics=True,
            ),
            tags=[
                cdk.CfnTag(key="Purpose", value="S3TablesAnalytics"),
                cdk.CfnTag(key="Component", value="Analytics"),
            ],
        )

        return workgroup

    def _create_glue_database(self) -> glue.CfnDatabase:
        """
        Create AWS Glue database for table catalog integration.
        
        Returns:
            Glue database for S3 Tables catalog integration
        """
        database = glue.CfnDatabase(
            self,
            "AnalyticsGlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.namespace_name,
                description="Glue database for S3 Tables analytics data",
                parameters={
                    "classification": "iceberg",
                    "s3_tables_integration": "enabled",
                },
            ),
        )

        return database

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self,
            "TableBucketName",
            value=self.table_bucket.name,
            description="Name of the S3 Table Bucket for analytics storage",
            export_name=f"{self.stack_name}-TableBucketName",
        )

        CfnOutput(
            self,
            "TableBucketArn",
            value=self.table_bucket.attr_arn,
            description="ARN of the S3 Table Bucket",
            export_name=f"{self.stack_name}-TableBucketArn",
        )

        CfnOutput(
            self,
            "NamespaceName",
            value=self.namespace_name,
            description="Name of the S3 Tables namespace",
            export_name=f"{self.stack_name}-NamespaceName",
        )

        CfnOutput(
            self,
            "SampleTableName",
            value=self.sample_table_name,
            description="Name of the sample customer events table",
            export_name=f"{self.stack_name}-SampleTableName",
        )

        CfnOutput(
            self,
            "AthenaWorkGroupName",
            value=self.athena_workgroup_name,
            description="Name of the Athena workgroup for S3 Tables queries",
            export_name=f"{self.stack_name}-AthenaWorkGroupName",
        )

        CfnOutput(
            self,
            "AthenaResultsBucket",
            value=self.athena_results_bucket.bucket_name,
            description="S3 bucket for storing Athena query results",
            export_name=f"{self.stack_name}-AthenaResultsBucket",
        )

        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="Name of the Glue database for catalog integration",
            export_name=f"{self.stack_name}-GlueDatabaseName",
        )

        CfnOutput(
            self,
            "AnalyticsRoleArn",
            value=self.analytics_role.role_arn,
            description="ARN of the IAM role for analytics services",
            export_name=f"{self.stack_name}-AnalyticsRoleArn",
        )


class AnalyticsS3TablesApp(cdk.App):
    """CDK Application for Analytics-Ready Data Storage with S3 Tables."""

    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()

        # Get configuration from environment variables or use defaults
        env_config = self._get_environment_config()

        # Create the main stack
        AnalyticsS3TablesStack(
            self,
            "AnalyticsS3TablesStack",
            env=env_config,
            description="Analytics-Ready Data Storage with S3 Tables and Apache Iceberg",
            tags={
                "Project": "AnalyticsS3Tables",
                "Environment": env_config.get("environment", "development"),
                "Recipe": "analytics-ready-data-storage-s3-tables",
                "Version": "1.0",
            },
        )

    def _get_environment_config(self) -> Dict[str, Any]:
        """
        Get environment configuration from environment variables.
        
        Returns:
            Dictionary containing environment configuration
        """
        return {
            "account": os.environ.get("CDK_DEFAULT_ACCOUNT"),
            "region": os.environ.get("CDK_DEFAULT_REGION", "us-east-1"),
            "environment": os.environ.get("ENVIRONMENT", "development"),
        }


# Create and run the CDK application
if __name__ == "__main__":
    app = AnalyticsS3TablesApp()
    app.synth()