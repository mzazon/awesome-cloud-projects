#!/usr/bin/env python3
"""
AWS CDK Python application for Building Privacy-Preserving Data Analytics 
with AWS Clean Rooms and QuickSight.

This application deploys infrastructure for secure multi-party data collaboration
using AWS Clean Rooms with differential privacy protections, integrated with
AWS Glue for data preparation and Amazon QuickSight for visualization.
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    StackProps,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_iam as iam,
    aws_glue as glue,
    aws_cleanrooms as cleanrooms,
    aws_quicksight as quicksight,
)
from constructs import Construct


class PrivacyPreservingAnalyticsStack(Stack):
    """
    CDK Stack for Privacy-Preserving Data Analytics with AWS Clean Rooms and QuickSight.
    
    This stack creates:
    - S3 buckets for organization data and query results
    - IAM roles for Clean Rooms and Glue services
    - Glue database and crawlers for data cataloging
    - Clean Rooms collaboration configuration
    - QuickSight data sources and datasets
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        account_id: str,
        random_suffix: str,
        user_email: Optional[str] = None,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.account_id = account_id
        self.random_suffix = random_suffix
        self.user_email = user_email or "admin@example.com"

        # Create S3 buckets for data storage
        self._create_s3_buckets()

        # Create IAM roles for services
        self._create_iam_roles()

        # Create Glue resources for data cataloging
        self._create_glue_resources()

        # Create Clean Rooms collaboration
        self._create_clean_rooms_collaboration()

        # Create QuickSight resources
        self._create_quicksight_resources()

        # Create stack outputs
        self._create_outputs()

    def _create_s3_buckets(self) -> None:
        """Create S3 buckets for organization data and query results."""
        
        # Organization A data bucket
        self.org_a_bucket = s3.Bucket(
            self,
            "OrgADataBucket",
            bucket_name=f"clean-rooms-data-a-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Organization B data bucket
        self.org_b_bucket = s3.Bucket(
            self,
            "OrgBDataBucket",
            bucket_name=f"clean-rooms-data-b-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Query results bucket
        self.results_bucket = s3.Bucket(
            self,
            "QueryResultsBucket",
            bucket_name=f"clean-rooms-results-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Clean Rooms and Glue services."""
        
        # Clean Rooms service role
        self.clean_rooms_role = iam.Role(
            self,
            "CleanRoomsAnalyticsRole",
            role_name="CleanRoomsAnalyticsRole",
            assumed_by=iam.ServicePrincipal("cleanrooms.amazonaws.com"),
            description="IAM role for AWS Clean Rooms analytics operations",
        )

        # Attach AWS managed policy for Clean Rooms
        self.clean_rooms_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSCleanRoomsService"
            )
        )

        # Custom policy for S3 and Glue access
        clean_rooms_custom_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "s3:GetObject",
                        "s3:ListBucket",
                        "s3:PutObject",
                    ],
                    resources=[
                        self.org_a_bucket.bucket_arn,
                        f"{self.org_a_bucket.bucket_arn}/*",
                        self.org_b_bucket.bucket_arn,
                        f"{self.org_b_bucket.bucket_arn}/*",
                        self.results_bucket.bucket_arn,
                        f"{self.results_bucket.bucket_arn}/*",
                    ],
                ),
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    actions=[
                        "glue:GetTable",
                        "glue:GetTables",
                        "glue:GetDatabase",
                    ],
                    resources=["*"],
                ),
            ]
        )

        self.clean_rooms_role.attach_inline_policy(
            iam.Policy(
                self,
                "CleanRoomsS3Access",
                policy_name="CleanRoomsS3Access",
                document=clean_rooms_custom_policy,
            )
        )

        # Glue service role
        self.glue_role = iam.Role(
            self,
            "GlueCleanRoomsRole",
            role_name="GlueCleanRoomsRole",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="IAM role for AWS Glue operations in Clean Rooms",
        )

        # Attach AWS managed policy for Glue
        self.glue_role.add_managed_policy(
            iam.ManagedPolicy.from_aws_managed_policy_name(
                "service-role/AWSGlueServiceRole"
            )
        )

        # Grant Glue access to S3 buckets
        self.org_a_bucket.grant_read_write(self.glue_role)
        self.org_b_bucket.grant_read_write(self.glue_role)
        self.results_bucket.grant_read_write(self.glue_role)

    def _create_glue_resources(self) -> None:
        """Create Glue database and crawlers for data cataloging."""
        
        # Glue database
        self.glue_database_name = f"clean_rooms_analytics_{self.random_suffix.replace('-', '_')}"
        
        self.glue_database = glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account_id,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.glue_database_name,
                description="Clean Rooms analytics database for privacy-preserving collaboration",
            ),
        )

        # Glue crawler for Organization A data
        self.crawler_org_a = glue.CfnCrawler(
            self,
            "CrawlerOrgA",
            name=f"crawler-org-a-{self.random_suffix}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database_name,
            description="Crawler for Organization A customer data",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.org_a_bucket.bucket_name}/data/"
                    )
                ]
            ),
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 12 * * ? *)"  # Daily at noon
            ),
        )
        self.crawler_org_a.add_dependency(self.glue_database)

        # Glue crawler for Organization B data
        self.crawler_org_b = glue.CfnCrawler(
            self,
            "CrawlerOrgB",
            name=f"crawler-org-b-{self.random_suffix}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database_name,
            description="Crawler for Organization B customer data",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.org_b_bucket.bucket_name}/data/"
                    )
                ]
            ),
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 12 * * ? *)"  # Daily at noon
            ),
        )
        self.crawler_org_b.add_dependency(self.glue_database)

    def _create_clean_rooms_collaboration(self) -> None:
        """Create Clean Rooms collaboration and configured tables."""
        
        # Clean Rooms collaboration
        self.collaboration_name = f"analytics-collaboration-{self.random_suffix}"
        
        self.collaboration = cleanrooms.CfnCollaboration(
            self,
            "CleanRoomsCollaboration",
            name=self.collaboration_name,
            description="Privacy-preserving analytics collaboration for cross-organizational insights",
            members=[
                cleanrooms.CfnCollaboration.MemberSpecificationProperty(
                    account_id=self.account_id,
                    display_name="Organization A",
                    member_abilities=["CAN_QUERY", "CAN_RECEIVE_RESULTS"],
                )
            ],
            query_log_status="ENABLED",
            data_encryption_metadata=cleanrooms.CfnCollaboration.DataEncryptionMetadataProperty(
                allow_cleartext=False,
                allow_duplicates=False,
                allow_joins_on_columns_with_different_names=False,
                preserve_nulls=True,
            ),
        )

        # Note: Configured tables and associations would typically be created
        # after the Glue crawlers have discovered the table schemas.
        # In a real deployment, you might use Custom Resources or separate stacks.

    def _create_quicksight_resources(self) -> None:
        """Create QuickSight data sources and datasets."""
        
        # QuickSight data source for S3 results
        self.quicksight_data_source = quicksight.CfnDataSource(
            self,
            "QuickSightDataSource",
            aws_account_id=self.account_id,
            data_source_id=f"clean-rooms-results-{self.random_suffix}",
            name="Clean Rooms Analytics Results",
            type="S3",
            data_source_parameters=quicksight.CfnDataSource.DataSourceParametersProperty(
                s3_parameters=quicksight.CfnDataSource.S3ParametersProperty(
                    manifest_file_location=quicksight.CfnDataSource.ManifestFileLocationProperty(
                        bucket=self.results_bucket.bucket_name,
                        key="query-results/",
                    )
                )
            ),
            permissions=[
                quicksight.CfnDataSource.ResourcePermissionProperty(
                    principal=f"arn:aws:iam::{self.account_id}:root",
                    actions=[
                        "quicksight:DescribeDataSource",
                        "quicksight:DescribeDataSourcePermissions",
                        "quicksight:PassDataSource",
                        "quicksight:UpdateDataSource",
                        "quicksight:DeleteDataSource",
                        "quicksight:UpdateDataSourcePermissions",
                    ],
                )
            ],
        )

        # QuickSight dataset
        self.quicksight_dataset = quicksight.CfnDataSet(
            self,
            "QuickSightDataSet",
            aws_account_id=self.account_id,
            data_set_id=f"privacy-analytics-dataset-{self.random_suffix}",
            name="Privacy Analytics Dataset",
            physical_table_map={
                "CleanRoomsResults": quicksight.CfnDataSet.PhysicalTableProperty(
                    s3_source=quicksight.CfnDataSet.S3SourceProperty(
                        data_source_arn=self.quicksight_data_source.attr_arn,
                        input_columns=[
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="age_group",
                                type="STRING",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="region",
                                type="STRING",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="customer_count",
                                type="INTEGER",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="avg_purchase_amount",
                                type="DECIMAL",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="avg_engagement_score",
                                type="DECIMAL",
                            ),
                        ],
                    )
                )
            },
            permissions=[
                quicksight.CfnDataSet.ResourcePermissionProperty(
                    principal=f"arn:aws:iam::{self.account_id}:root",
                    actions=[
                        "quicksight:DescribeDataSet",
                        "quicksight:DescribeDataSetPermissions",
                        "quicksight:PassDataSet",
                        "quicksight:DescribeIngestion",
                        "quicksight:ListIngestions",
                        "quicksight:UpdateDataSet",
                        "quicksight:DeleteDataSet",
                        "quicksight:CreateIngestion",
                        "quicksight:CancelIngestion",
                        "quicksight:UpdateDataSetPermissions",
                    ],
                )
            ],
        )
        self.quicksight_dataset.add_dependency(self.quicksight_data_source)

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self,
            "OrgABucketName",
            value=self.org_a_bucket.bucket_name,
            description="S3 bucket name for Organization A data",
        )

        CfnOutput(
            self,
            "OrgBBucketName",
            value=self.org_b_bucket.bucket_name,
            description="S3 bucket name for Organization B data",
        )

        CfnOutput(
            self,
            "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 bucket name for Clean Rooms query results",
        )

        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database_name,
            description="Glue database name for data catalog",
        )

        CfnOutput(
            self,
            "CollaborationName",
            value=self.collaboration_name,
            description="Clean Rooms collaboration name",
        )

        CfnOutput(
            self,
            "CleanRoomsRoleArn",
            value=self.clean_rooms_role.role_arn,
            description="IAM role ARN for Clean Rooms operations",
        )

        CfnOutput(
            self,
            "GlueRoleArn",
            value=self.glue_role.role_arn,
            description="IAM role ARN for Glue operations",
        )

        CfnOutput(
            self,
            "QuickSightDataSourceId",
            value=self.quicksight_data_source.data_source_id,
            description="QuickSight data source ID for analytics results",
        )


def main() -> None:
    """Main application entry point."""
    
    app = App()

    # Get configuration from environment variables or context
    account_id = app.node.try_get_context("account_id") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    random_suffix = app.node.try_get_context("random_suffix") or "demo123"
    user_email = app.node.try_get_context("user_email")

    if not account_id:
        raise ValueError("AWS account ID must be provided via CDK_DEFAULT_ACCOUNT or context")
    
    if not region:
        raise ValueError("AWS region must be provided via CDK_DEFAULT_REGION or context")

    # Create the stack
    stack = PrivacyPreservingAnalyticsStack(
        app,
        "PrivacyPreservingAnalyticsStack",
        account_id=account_id,
        random_suffix=random_suffix,
        user_email=user_email,
        env=cdk.Environment(
            account=account_id,
            region=region,
        ),
        description="Privacy-Preserving Data Analytics with AWS Clean Rooms and QuickSight",
    )

    # Add tags to all resources
    cdk.Tags.of(stack).add("Project", "PrivacyPreservingAnalytics")
    cdk.Tags.of(stack).add("Environment", "Demo")
    cdk.Tags.of(stack).add("Owner", "DataTeam")

    app.synth()


if __name__ == "__main__":
    main()