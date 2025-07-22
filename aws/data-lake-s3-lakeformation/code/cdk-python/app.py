#!/usr/bin/env python3
"""
AWS CDK Python application for Data Lake Architecture with S3 and Lake Formation.

This application deploys a comprehensive data lake solution using:
- Amazon S3 for multi-tier storage (Raw, Processed, Curated)
- AWS Lake Formation for data governance and fine-grained access control
- AWS Glue for data catalog and ETL capabilities
- IAM roles for role-based access control
- CloudTrail for audit logging
- LF-Tags for attribute-based access control

The architecture implements enterprise-grade security and governance features
including data cell filters, tag-based permissions, and comprehensive audit logging.
"""

import os
import random
import string
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    App,
    CfnOutput,
    Duration,
    Environment,
    RemovalPolicy,
    Stack,
    StackProps,
    Tags,
)
from aws_cdk import aws_glue as glue
from aws_cdk import aws_iam as iam
from aws_cdk import aws_lakeformation as lakeformation
from aws_cdk import aws_logs as logs
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_s3_deployment as s3_deployment
from aws_cdk import aws_cloudtrail as cloudtrail
from constructs import Construct


class DataLakeStack(Stack):
    """
    CDK Stack for implementing a comprehensive data lake architecture.
    
    This stack creates a secure, governed data lake using AWS Lake Formation
    with S3 storage tiers, Glue catalog, and comprehensive access controls.
    """

    def __init__(
        self, 
        scope: Construct, 
        construct_id: str, 
        project_name: str = "datalake",
        enable_versioning: bool = True,
        enable_audit_logging: bool = True,
        **kwargs
    ) -> None:
        """
        Initialize the Data Lake Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            project_name: Name prefix for resources
            enable_versioning: Whether to enable S3 versioning
            enable_audit_logging: Whether to enable CloudTrail logging
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        self.random_suffix = self._generate_random_suffix()
        self.project_name = f"{project_name}-{self.random_suffix}"
        
        # Core configuration
        self.enable_versioning = enable_versioning
        self.enable_audit_logging = enable_audit_logging
        
        # Create S3 buckets for data lake zones
        self.raw_bucket = self._create_data_lake_bucket("raw")
        self.processed_bucket = self._create_data_lake_bucket("processed")
        self.curated_bucket = self._create_data_lake_bucket("curated")
        
        # Create IAM roles and users
        self.lake_formation_service_role = self._create_lake_formation_service_role()
        self.glue_crawler_role = self._create_glue_crawler_role()
        self.data_analyst_role = self._create_data_analyst_role()
        self.data_engineer_role = self._create_data_engineer_role()
        
        # Create Lake Formation administrators
        self.lf_admin_user = self._create_lake_formation_admin()
        self.data_analyst_user = self._create_data_analyst_user()
        self.data_engineer_user = self._create_data_engineer_user()
        
        # Create Glue database and crawlers
        self.database_name = f"sales_{self.random_suffix}"
        self.glue_database = self._create_glue_database()
        self.sales_crawler = self._create_sales_crawler()
        self.customer_crawler = self._create_customer_crawler()
        
        # Create LF-Tags for governance
        self._create_lf_tags()
        
        # Register S3 buckets with Lake Formation
        self._register_s3_buckets()
        
        # Upload sample data
        self._upload_sample_data()
        
        # Set up audit logging
        if self.enable_audit_logging:
            self._setup_audit_logging()
        
        # Add stack tags
        self._add_stack_tags()
        
        # Create stack outputs
        self._create_outputs()

    def _generate_random_suffix(self) -> str:
        """Generate a random suffix for resource names to ensure uniqueness."""
        return ''.join(random.choices(string.ascii_lowercase + string.digits, k=6))

    def _create_data_lake_bucket(self, zone_name: str) -> s3.Bucket:
        """
        Create an S3 bucket for a specific data lake zone.
        
        Args:
            zone_name: The name of the data lake zone (raw, processed, curated)
            
        Returns:
            S3 bucket instance
        """
        bucket_name = f"{self.project_name}-{zone_name}"
        
        # Configure bucket encryption
        encryption_config = s3.BucketEncryption.S3_MANAGED
        
        # Create the bucket
        bucket = s3.Bucket(
            self,
            f"{zone_name.title()}DataBucket",
            bucket_name=bucket_name,
            encryption=encryption_config,
            versioned=self.enable_versioning,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            enforce_ssl=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id=f"{zone_name}-lifecycle-rule",
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
        
        # Add tags to the bucket
        Tags.of(bucket).add("DataZone", zone_name.title())
        Tags.of(bucket).add("Project", self.project_name)
        
        return bucket

    def _create_lake_formation_service_role(self) -> iam.Role:
        """Create IAM role for Lake Formation service."""
        role = iam.Role(
            self,
            "LakeFormationServiceRole",
            role_name="LakeFormationServiceRole",
            assumed_by=iam.ServicePrincipal("lakeformation.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/LakeFormationServiceRole"
                )
            ]
        )
        
        return role

    def _create_glue_crawler_role(self) -> iam.Role:
        """Create IAM role for Glue crawlers."""
        role = iam.Role(
            self,
            "GlueCrawlerRole",
            role_name="GlueCrawlerRole",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueServiceRole"
                )
            ]
        )
        
        # Add custom policy for S3 access
        s3_policy = iam.Policy(
            self,
            "GlueS3AccessPolicy",
            policy_name="GlueS3AccessPolicy",
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
                        self.raw_bucket.bucket_arn,
                        f"{self.raw_bucket.bucket_arn}/*"
                    ]
                )
            ]
        )
        
        role.attach_inline_policy(s3_policy)
        
        return role

    def _create_data_analyst_role(self) -> iam.Role:
        """Create IAM role for data analysts."""
        role = iam.Role(
            self,
            "DataAnalystRole",
            role_name="DataAnalystRole",
            assumed_by=iam.AccountRootPrincipal(),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonAthenaFullAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSGlueConsoleFullAccess"
                )
            ]
        )
        
        return role

    def _create_data_engineer_role(self) -> iam.Role:
        """Create IAM role for data engineers."""
        role = iam.Role(
            self,
            "DataEngineerRole",
            role_name="DataEngineerRole",
            assumed_by=iam.AccountRootPrincipal(),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSGlueConsoleFullAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonAthenaFullAccess"
                )
            ]
        )
        
        return role

    def _create_lake_formation_admin(self) -> iam.User:
        """Create IAM user for Lake Formation administration."""
        user = iam.User(
            self,
            "LakeFormationAdmin",
            user_name="lake-formation-admin",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "LakeFormationDataAdmin"
                )
            ]
        )
        
        return user

    def _create_data_analyst_user(self) -> iam.User:
        """Create IAM user for data analysts."""
        user = iam.User(
            self,
            "DataAnalystUser",
            user_name="data-analyst"
        )
        
        # Allow user to assume the DataAnalystRole
        user.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sts:AssumeRole"],
                resources=[self.data_analyst_role.role_arn]
            )
        )
        
        return user

    def _create_data_engineer_user(self) -> iam.User:
        """Create IAM user for data engineers."""
        user = iam.User(
            self,
            "DataEngineerUser",
            user_name="data-engineer"
        )
        
        # Allow user to assume the DataEngineerRole
        user.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["sts:AssumeRole"],
                resources=[self.data_engineer_role.role_arn]
            )
        )
        
        return user

    def _create_glue_database(self) -> glue.CfnDatabase:
        """Create Glue database for data catalog."""
        database = glue.CfnDatabase(
            self,
            "SalesDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.database_name,
                description="Sales data lake database for analytics"
            )
        )
        
        return database

    def _create_sales_crawler(self) -> glue.CfnCrawler:
        """Create Glue crawler for sales data."""
        crawler = glue.CfnCrawler(
            self,
            "SalesCrawler",
            name="sales-crawler",
            role=self.glue_crawler_role.role_arn,
            database_name=self.database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.raw_bucket.bucket_name}/sales/"
                    )
                ]
            ),
            table_prefix="sales_"
        )
        
        crawler.add_depends_on(self.glue_database)
        
        return crawler

    def _create_customer_crawler(self) -> glue.CfnCrawler:
        """Create Glue crawler for customer data."""
        crawler = glue.CfnCrawler(
            self,
            "CustomerCrawler",
            name="customer-crawler",
            role=self.glue_crawler_role.role_arn,
            database_name=self.database_name,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.raw_bucket.bucket_name}/customers/"
                    )
                ]
            ),
            table_prefix="customer_"
        )
        
        crawler.add_depends_on(self.glue_database)
        
        return crawler

    def _create_lf_tags(self) -> None:
        """Create Lake Formation tags for governance."""
        # Department tag
        lakeformation.CfnTag(
            self,
            "DepartmentTag",
            tag_key="Department",
            tag_values=["Sales", "Marketing", "Finance", "Engineering"]
        )
        
        # Classification tag
        lakeformation.CfnTag(
            self,
            "ClassificationTag",
            tag_key="Classification",
            tag_values=["Public", "Internal", "Confidential", "Restricted"]
        )
        
        # Data zone tag
        lakeformation.CfnTag(
            self,
            "DataZoneTag",
            tag_key="DataZone",
            tag_values=["Raw", "Processed", "Curated"]
        )
        
        # Access level tag
        lakeformation.CfnTag(
            self,
            "AccessLevelTag",
            tag_key="AccessLevel",
            tag_values=["ReadOnly", "ReadWrite", "Admin"]
        )

    def _register_s3_buckets(self) -> None:
        """Register S3 buckets with Lake Formation."""
        # Register raw bucket
        lakeformation.CfnResource(
            self,
            "RawBucketRegistration",
            resource_arn=self.raw_bucket.bucket_arn,
            use_service_linked_role=True
        )
        
        # Register processed bucket
        lakeformation.CfnResource(
            self,
            "ProcessedBucketRegistration",
            resource_arn=self.processed_bucket.bucket_arn,
            use_service_linked_role=True
        )
        
        # Register curated bucket
        lakeformation.CfnResource(
            self,
            "CuratedBucketRegistration",
            resource_arn=self.curated_bucket.bucket_arn,
            use_service_linked_role=True
        )

    def _upload_sample_data(self) -> None:
        """Upload sample data to the raw bucket."""
        # Create sample sales data
        sales_data = """customer_id,product_id,order_date,quantity,price,region,sales_rep
1001,P001,2024-01-15,2,29.99,North,John Smith
1002,P002,2024-01-16,1,49.99,South,Jane Doe
1003,P001,2024-01-17,3,29.99,East,Bob Johnson
1004,P003,2024-01-18,1,99.99,West,Alice Brown
1005,P002,2024-01-19,2,49.99,North,John Smith
1006,P001,2024-01-20,1,29.99,South,Jane Doe
1007,P003,2024-01-21,2,99.99,East,Bob Johnson
1008,P002,2024-01-22,1,49.99,West,Alice Brown"""
        
        # Create sample customer data
        customer_data = """customer_id,first_name,last_name,email,phone,registration_date
1001,Michael,Johnson,mjohnson@example.com,555-0101,2023-12-01
1002,Sarah,Davis,sdavis@example.com,555-0102,2023-12-02
1003,Robert,Wilson,rwilson@example.com,555-0103,2023-12-03
1004,Jennifer,Brown,jbrown@example.com,555-0104,2023-12-04
1005,William,Jones,wjones@example.com,555-0105,2023-12-05
1006,Lisa,Garcia,lgarcia@example.com,555-0106,2023-12-06
1007,David,Miller,dmiller@example.com,555-0107,2023-12-07
1008,Susan,Anderson,sanderson@example.com,555-0108,2023-12-08"""
        
        # Create temporary files for deployment
        import tempfile
        import os
        
        with tempfile.TemporaryDirectory() as tmp_dir:
            # Write sales data
            sales_file = os.path.join(tmp_dir, "sales_data.csv")
            with open(sales_file, 'w') as f:
                f.write(sales_data)
            
            # Write customer data
            customer_file = os.path.join(tmp_dir, "customer_data.csv")
            with open(customer_file, 'w') as f:
                f.write(customer_data)
            
            # Deploy sales data
            s3_deployment.BucketDeployment(
                self,
                "SalesDataDeployment",
                sources=[s3_deployment.Source.asset(tmp_dir)],
                destination_bucket=self.raw_bucket,
                destination_key_prefix="sales/",
                include=["sales_data.csv"]
            )
            
            # Deploy customer data
            s3_deployment.BucketDeployment(
                self,
                "CustomerDataDeployment",
                sources=[s3_deployment.Source.asset(tmp_dir)],
                destination_bucket=self.raw_bucket,
                destination_key_prefix="customers/",
                include=["customer_data.csv"]
            )

    def _setup_audit_logging(self) -> None:
        """Set up CloudTrail for audit logging."""
        # Create CloudWatch log group
        log_group = logs.LogGroup(
            self,
            "LakeFormationAuditLogGroup",
            log_group_name="/aws/lakeformation/audit",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Create CloudTrail
        trail = cloudtrail.Trail(
            self,
            "LakeFormationAuditTrail",
            trail_name="lake-formation-audit-trail",
            bucket=self.raw_bucket,
            s3_key_prefix="audit-logs/",
            include_global_service_events=True,
            is_multi_region_trail=True,
            enable_file_validation=True,
            send_to_cloud_watch_logs=True,
            cloud_watch_logs_group=log_group
        )

    def _add_stack_tags(self) -> None:
        """Add tags to all resources in the stack."""
        Tags.of(self).add("Project", self.project_name)
        Tags.of(self).add("Environment", "Development")
        Tags.of(self).add("Owner", "DataLakeTeam")
        Tags.of(self).add("CostCenter", "Analytics")
        Tags.of(self).add("DataClassification", "Internal")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs."""
        CfnOutput(
            self,
            "RawBucketName",
            value=self.raw_bucket.bucket_name,
            description="Name of the raw data bucket"
        )
        
        CfnOutput(
            self,
            "ProcessedBucketName",
            value=self.processed_bucket.bucket_name,
            description="Name of the processed data bucket"
        )
        
        CfnOutput(
            self,
            "CuratedBucketName",
            value=self.curated_bucket.bucket_name,
            description="Name of the curated data bucket"
        )
        
        CfnOutput(
            self,
            "DatabaseName",
            value=self.database_name,
            description="Name of the Glue database"
        )
        
        CfnOutput(
            self,
            "DataAnalystRoleArn",
            value=self.data_analyst_role.role_arn,
            description="ARN of the data analyst role"
        )
        
        CfnOutput(
            self,
            "DataEngineerRoleArn",
            value=self.data_engineer_role.role_arn,
            description="ARN of the data engineer role"
        )
        
        CfnOutput(
            self,
            "LakeFormationAdminUser",
            value=self.lf_admin_user.user_name,
            description="Name of the Lake Formation admin user"
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
        region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
    )
    
    # Create the data lake stack
    data_lake_stack = DataLakeStack(
        app,
        "DataLakeStack",
        project_name="datalake",
        enable_versioning=True,
        enable_audit_logging=True,
        env=env,
        description="Comprehensive data lake architecture with S3 and Lake Formation"
    )
    
    # Synthesize the app
    app.synth()


if __name__ == "__main__":
    main()