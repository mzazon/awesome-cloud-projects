#!/usr/bin/env python3
"""
AWS CDK Python Application for Data Catalog Governance with AWS Glue

This application implements a comprehensive data governance solution using AWS Glue
Data Catalog, Lake Formation, CloudTrail, and CloudWatch for automated data
classification, access control, and audit logging.

Author: AWS CDK Python Generator
Version: 1.0.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Tags,
    CfnOutput,
    RemovalPolicy,
    Duration,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_s3_deployment as s3_deployment
from aws_cdk import aws_iam as iam
from aws_cdk import aws_glue as glue
from aws_cdk import aws_lakeformation as lakeformation
from aws_cdk import aws_cloudtrail as cloudtrail
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_logs as logs
from constructs import Construct


class DataCatalogGovernanceStack(Stack):
    """
    AWS CDK Stack for implementing comprehensive data governance with AWS Glue.
    
    This stack creates:
    - S3 buckets for data storage and audit logs
    - Glue Data Catalog database and crawler
    - PII classifier for data classification
    - Lake Formation permissions and policies
    - CloudTrail for audit logging
    - CloudWatch dashboard for monitoring
    - IAM roles and policies for governance
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        environment_name: str = "dev",
        **kwargs,
    ) -> None:
        """
        Initialize the Data Catalog Governance Stack.
        
        Args:
            scope: CDK construct scope
            construct_id: Unique identifier for this construct
            environment_name: Environment name (dev, staging, prod)
            **kwargs: Additional stack arguments
        """
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.environment_name = environment_name
        self.stack_name = f"data-catalog-governance-{environment_name}"
        
        # Add common tags
        Tags.of(self).add("Environment", environment_name)
        Tags.of(self).add("Project", "DataCatalogGovernance")
        Tags.of(self).add("ManagedBy", "CDK")

        # Create S3 buckets for data and audit logs
        self.data_bucket = self._create_data_bucket()
        self.audit_bucket = self._create_audit_bucket()

        # Deploy sample data to S3
        self._deploy_sample_data()

        # Create IAM roles for Glue services
        self.glue_crawler_role = self._create_glue_crawler_role()
        self.data_analyst_role = self._create_data_analyst_role()

        # Create Glue Data Catalog components
        self.glue_database = self._create_glue_database()
        self.pii_classifier = self._create_pii_classifier()
        self.glue_crawler = self._create_glue_crawler()

        # Configure Lake Formation for fine-grained access control
        self._configure_lake_formation()

        # Set up CloudTrail for audit logging
        self.cloudtrail = self._create_cloudtrail()

        # Create CloudWatch dashboard for monitoring
        self.dashboard = self._create_cloudwatch_dashboard()

        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing data to be cataloged."""
        bucket = s3.Bucket(
            self,
            "DataGovernanceBucket",
            bucket_name=f"data-governance-{self.environment_name}-{self.account}-{self.region}",
            versioning=True,
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
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90),
                        ),
                    ],
                ),
            ],
        )
        
        # Add bucket notification to trigger crawler on new objects
        bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            # Note: Lambda function would be created separately for production use
        )
        
        return bucket

    def _create_audit_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing CloudTrail audit logs."""
        bucket = s3.Bucket(
            self,
            "AuditLogsBucket",
            bucket_name=f"governance-audit-{self.environment_name}-{self.account}-{self.region}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="AuditLogRetention",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30),
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(365),
                        ),
                    ],
                    expiration=Duration.days(2557),  # 7 years retention
                ),
            ],
        )
        
        return bucket

    def _deploy_sample_data(self) -> None:
        """Deploy sample customer data with PII for testing."""
        # Create sample CSV data with PII
        sample_data_content = """customer_id,first_name,last_name,email,ssn,phone,address,city,state,zip
1,John,Doe,john.doe@email.com,123-45-6789,555-123-4567,123 Main St,Anytown,NY,12345
2,Jane,Smith,jane.smith@email.com,987-65-4321,555-987-6543,456 Oak Ave,Somewhere,CA,67890
3,Bob,Johnson,bob.johnson@email.com,456-78-9012,555-456-7890,789 Pine Rd,Nowhere,TX,54321
4,Alice,Williams,alice.williams@email.com,789-01-2345,555-789-0123,321 Elm St,Anyplace,FL,98765
5,Charlie,Brown,charlie.brown@email.com,234-56-7890,555-234-5678,654 Maple Dr,Somewhere,WA,13579"""

        # Deploy sample data to S3
        s3_deployment.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3_deployment.Source.data(
                    "data/sample_customer_data.csv",
                    sample_data_content,
                )
            ],
            destination_bucket=self.data_bucket,
            destination_key_prefix="data/",
            retain_on_delete=False,
        )

    def _create_glue_crawler_role(self) -> iam.Role:
        """Create IAM role for Glue crawler with necessary permissions."""
        role = iam.Role(
            self,
            "GlueGovernanceCrawlerRole",
            role_name=f"GlueGovernanceCrawlerRole-{self.environment_name}",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="IAM role for Glue crawler with data governance permissions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueServiceRole"
                ),
            ],
        )

        # Add permissions for S3 data access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:ListBucket",
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )

        # Add permissions for Lake Formation
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "lakeformation:GetDataAccess",
                    "lakeformation:GrantPermissions",
                    "lakeformation:RevokePermissions",
                    "lakeformation:ListPermissions",
                ],
                resources=["*"],
            )
        )

        return role

    def _create_data_analyst_role(self) -> iam.Role:
        """Create IAM role for data analysts with governed access."""
        role = iam.Role(
            self,
            "DataAnalystGovernanceRole",
            role_name=f"DataAnalystGovernanceRole-{self.environment_name}",
            assumed_by=iam.AccountPrincipal(self.account),
            description="IAM role for data analysts with governed data access",
        )

        # Add permissions for Glue Data Catalog access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "glue:GetDatabase",
                    "glue:GetTable",
                    "glue:GetTables",
                    "glue:GetPartition",
                    "glue:GetPartitions",
                    "glue:SearchTables",
                    "glue:GetCrawler",
                    "glue:GetCrawlerMetrics",
                ],
                resources=["*"],
            )
        )

        # Add permissions for Lake Formation
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "lakeformation:GetDataAccess",
                    "lakeformation:ListPermissions",
                ],
                resources=["*"],
            )
        )

        # Add read-only S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:ListBucket",
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*",
                ],
            )
        )

        return role

    def _create_glue_database(self) -> glue.CfnDatabase:
        """Create Glue Data Catalog database for governance."""
        database = glue.CfnDatabase(
            self,
            "GovernanceCatalogDatabase",
            catalog_id=self.account,
            database_input={
                "name": f"governance_catalog_{self.environment_name}",
                "description": "Data governance catalog database for PII classification and access control",
                "parameters": {
                    "classification": "governance",
                    "environment": self.environment_name,
                    "created_by": "CDK",
                },
            },
        )

        return database

    def _create_pii_classifier(self) -> glue.CfnClassifier:
        """Create custom PII classifier for data classification."""
        classifier = glue.CfnClassifier(
            self,
            "PIIClassifier",
            csv_classifier={
                "name": f"pii-classifier-{self.environment_name}",
                "delimiter": ",",
                "quote_symbol": '"',
                "contains_header": "PRESENT",
                "header": [
                    "customer_id",
                    "first_name",
                    "last_name", 
                    "email",
                    "ssn",
                    "phone",
                    "address",
                    "city",
                    "state",
                    "zip",
                ],
                "disable_value_trimming": False,
                "allow_single_column": False,
            },
        )

        return classifier

    def _create_glue_crawler(self) -> glue.CfnCrawler:
        """Create Glue crawler with PII classification capabilities."""
        crawler = glue.CfnCrawler(
            self,
            "GovernanceCrawler",
            name=f"governance-crawler-{self.environment_name}",
            role=self.glue_crawler_role.role_arn,
            database_name=self.glue_database.database_input["name"],
            description="Governance crawler with PII classification capabilities",
            targets={
                "s3_targets": [
                    {
                        "path": f"s3://{self.data_bucket.bucket_name}/data/",
                        "sample_size": 100,
                    }
                ]
            },
            classifiers=[self.pii_classifier.csv_classifier["name"]],
            schedule={
                "schedule_expression": "cron(0 12 * * ? *)",  # Daily at 12 PM UTC
            },
            schema_change_policy={
                "update_behavior": "UPDATE_IN_DATABASE",
                "delete_behavior": "LOG",
            },
            recrawl_policy={
                "recrawl_behavior": "CRAWL_EVERYTHING",
            },
            lineage_configuration={
                "crawler_lineage_settings": "ENABLE",
            },
        )

        # Add dependency to ensure database is created first
        crawler.add_dependency(self.glue_database)

        return crawler

    def _configure_lake_formation(self) -> None:
        """Configure Lake Formation for fine-grained access control."""
        # Register S3 location with Lake Formation
        lakeformation.CfnResource(
            self,
            "LakeFormationResource",
            resource_arn=f"arn:aws:s3:::{self.data_bucket.bucket_name}/data/",
            use_service_linked_role=True,
        )

        # Configure Lake Formation settings
        lakeformation.CfnDataLakeSettings(
            self,
            "DataLakeSettings",
            admins=[
                {
                    "data_lake_principal_identifier": f"arn:aws:iam::{self.account}:root"
                }
            ],
            create_database_default_permissions=[],
            create_table_default_permissions=[],
            trusted_resource_owners=[self.account],
        )

        # Grant permissions to data analyst role
        lakeformation.CfnPermissions(
            self,
            "DataAnalystPermissions",
            data_lake_principal={
                "data_lake_principal_identifier": self.data_analyst_role.role_arn
            },
            resource={
                "database_resource": {
                    "catalog_id": self.account,
                    "name": self.glue_database.database_input["name"],
                }
            },
            permissions=["DESCRIBE"],
        )

    def _create_cloudtrail(self) -> cloudtrail.Trail:
        """Create CloudTrail for comprehensive audit logging."""
        # Create CloudWatch log group for CloudTrail
        log_group = logs.LogGroup(
            self,
            "CloudTrailLogGroup",
            log_group_name=f"/aws/cloudtrail/data-governance-{self.environment_name}",
            retention=logs.RetentionDays.ONE_YEAR,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "DataCatalogGovernanceTrail",
            trail_name=f"DataCatalogGovernanceTrail-{self.environment_name}",
            bucket=self.audit_bucket,
            s3_key_prefix="cloudtrail-logs/",
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            cloud_watch_logs_group=log_group,
            management_events=cloudtrail.ReadWriteType.ALL,
        )

        # Add data events for Glue Data Catalog
        trail.add_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=True,
            data_resource_type=cloudtrail.DataResourceType.GLUE_TABLE,
            data_resource_values=[
                f"arn:aws:glue:{self.region}:{self.account}:table/{self.glue_database.database_input['name']}/*"
            ],
        )

        # Add data events for S3 bucket
        trail.add_event_selector(
            read_write_type=cloudtrail.ReadWriteType.ALL,
            include_management_events=False,
            data_resource_type=cloudtrail.DataResourceType.S3_OBJECT,
            data_resource_values=[f"{self.data_bucket.bucket_arn}/*"],
        )

        return trail

    def _create_cloudwatch_dashboard(self) -> cloudwatch.Dashboard:
        """Create CloudWatch dashboard for governance monitoring."""
        dashboard = cloudwatch.Dashboard(
            self,
            "DataGovernanceDashboard",
            dashboard_name=f"DataGovernanceDashboard-{self.environment_name}",
            widgets=[
                [
                    cloudwatch.TextWidget(
                        markdown=f"# Data Catalog Governance Dashboard\n\n"
                        f"Environment: **{self.environment_name}**\n\n"
                        f"This dashboard monitors data governance activities including:\n"
                        f"- Glue Crawler execution metrics\n"
                        f"- PII detection events\n"
                        f"- Data access patterns\n"
                        f"- Audit trail compliance",
                        width=24,
                        height=6,
                    )
                ],
                [
                    cloudwatch.GraphWidget(
                        title="Glue Crawler Success Rate",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/Glue",
                                metric_name="glue.driver.aggregate.numCompletedTasks",
                                dimensions_map={
                                    "JobName": self.glue_crawler.name,
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            )
                        ],
                        right=[
                            cloudwatch.Metric(
                                namespace="AWS/Glue",
                                metric_name="glue.driver.aggregate.numFailedTasks",
                                dimensions_map={
                                    "JobName": self.glue_crawler.name,
                                },
                                statistic="Sum",
                                period=Duration.minutes(5),
                            )
                        ],
                        width=12,
                        height=6,
                    ),
                    cloudwatch.GraphWidget(
                        title="S3 Data Bucket Usage",
                        left=[
                            cloudwatch.Metric(
                                namespace="AWS/S3",
                                metric_name="BucketSizeBytes",
                                dimensions_map={
                                    "BucketName": self.data_bucket.bucket_name,
                                    "StorageType": "StandardStorage",
                                },
                                statistic="Average",
                                period=Duration.hours(24),
                            )
                        ],
                        width=12,
                        height=6,
                    ),
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="PII Detection Events",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self,
                                "GlueLogGroup",
                                f"/aws/glue/crawlers/{self.glue_crawler.name}",
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, @message",
                            "filter @message like /PII/",
                            "sort @timestamp desc",
                            "limit 100",
                        ],
                        width=24,
                        height=6,
                    )
                ],
                [
                    cloudwatch.LogQueryWidget(
                        title="Data Access Audit Trail",
                        log_groups=[
                            logs.LogGroup.from_log_group_name(
                                self,
                                "CloudTrailLogGroup",
                                f"/aws/cloudtrail/data-governance-{self.environment_name}",
                            )
                        ],
                        query_lines=[
                            "fields @timestamp, userIdentity.type, eventName, sourceIPAddress",
                            "filter eventName like /GetTable/ or eventName like /GetDatabase/",
                            "sort @timestamp desc",
                            "limit 50",
                        ],
                        width=24,
                        height=6,
                    )
                ],
            ],
        )

        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket containing data for governance",
            export_name=f"{self.stack_name}-data-bucket",
        )

        CfnOutput(
            self,
            "AuditBucketName",
            value=self.audit_bucket.bucket_name,
            description="Name of the S3 bucket containing audit logs",
            export_name=f"{self.stack_name}-audit-bucket",
        )

        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.database_input["name"],
            description="Name of the Glue Data Catalog database",
            export_name=f"{self.stack_name}-glue-database",
        )

        CfnOutput(
            self,
            "GlueCrawlerName",
            value=self.glue_crawler.name,
            description="Name of the Glue crawler for data discovery",
            export_name=f"{self.stack_name}-glue-crawler",
        )

        CfnOutput(
            self,
            "DataAnalystRoleArn",
            value=self.data_analyst_role.role_arn,
            description="ARN of the IAM role for data analysts",
            export_name=f"{self.stack_name}-data-analyst-role",
        )

        CfnOutput(
            self,
            "CloudTrailArn",
            value=self.cloudtrail.trail_arn,
            description="ARN of the CloudTrail for audit logging",
            export_name=f"{self.stack_name}-cloudtrail",
        )

        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="URL to the CloudWatch dashboard",
            export_name=f"{self.stack_name}-dashboard-url",
        )


class DataCatalogGovernanceApp(cdk.App):
    """
    CDK Application for Data Catalog Governance.
    """

    def __init__(self) -> None:
        super().__init__()

        # Get environment configuration
        environment_name = self.node.try_get_context("environment") or "dev"
        
        # Get AWS account and region from environment or CDK context
        account = os.environ.get("CDK_DEFAULT_ACCOUNT") or self.node.try_get_context("account")
        region = os.environ.get("CDK_DEFAULT_REGION") or self.node.try_get_context("region")

        # Create the stack
        DataCatalogGovernanceStack(
            self,
            "DataCatalogGovernanceStack",
            environment_name=environment_name,
            env=cdk.Environment(
                account=account,
                region=region,
            ),
            description="Comprehensive data governance solution using AWS Glue Data Catalog, Lake Formation, and CloudTrail for automated PII classification and access control",
        )


# Create the CDK app
app = DataCatalogGovernanceApp()
app.synth()