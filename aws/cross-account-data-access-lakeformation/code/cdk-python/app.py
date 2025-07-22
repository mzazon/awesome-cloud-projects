#!/usr/bin/env python3
"""
AWS CDK Python Application for Cross-Account Data Access with Lake Formation

This CDK application deploys infrastructure for implementing secure cross-account
data sharing using AWS Lake Formation with tag-based access control (LF-TBAC).

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    aws_s3 as s3,
    aws_iam as iam,
    aws_glue as glue,
    aws_lakeformation as lf,
    aws_ram as ram,
    aws_s3_deployment as s3deploy,
    RemovalPolicy,
    CfnOutput,
    Stack,
    StackProps,
)
from constructs import Construct


class LakeFormationCrossAccountStack(Stack):
    """
    CDK Stack for Lake Formation Cross-Account Data Access
    
    This stack creates:
    - S3 data lake bucket with sample data
    - Glue Data Catalog databases and tables
    - Lake Formation configuration with LF-Tags
    - Cross-account resource sharing via AWS RAM
    - IAM roles and policies for data governance
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        consumer_account_id: str,
        data_lake_admin_arn: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the Lake Formation Cross-Account Stack.
        
        Args:
            scope: CDK scope
            construct_id: Unique identifier for this construct
            consumer_account_id: AWS account ID that will consume shared data
            data_lake_admin_arn: ARN of the data lake administrator (optional)
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.consumer_account_id = consumer_account_id
        self.account_id = self.account
        self.region = self.region
        
        # Use provided admin ARN or default to root
        self.data_lake_admin_arn = (
            data_lake_admin_arn or f"arn:aws:iam::{self.account_id}:root"
        )

        # Create core infrastructure
        self.s3_bucket = self._create_data_lake_bucket()
        self.glue_service_role = self._create_glue_service_role()
        self._deploy_sample_data()
        
        # Create databases and crawlers
        self.financial_db = self._create_financial_database()
        self.customer_db = self._create_customer_database()
        self.financial_crawler = self._create_financial_crawler()
        
        # Configure Lake Formation
        self._setup_lake_formation()
        self._create_lf_tags()
        self._assign_lf_tags_to_resources()
        
        # Create cross-account resource share
        self.resource_share = self._create_cross_account_resource_share()
        
        # Create data analyst role for consumer account demonstration
        self.data_analyst_role_template = self._create_data_analyst_role_template()
        
        # Create outputs
        self._create_outputs()

    def _create_data_lake_bucket(self) -> s3.Bucket:
        """Create S3 bucket for the data lake with appropriate configuration."""
        bucket = s3.Bucket(
            self,
            "DataLakeBucket",
            bucket_name=f"data-lake-{self.account_id}-{cdk.Aws.STACK_NAME.lower()}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )
        
        # Add bucket policy for Lake Formation service
        bucket.add_to_resource_policy(
            iam.PolicyStatement(
                sid="LakeFormationServiceAccess",
                effect=iam.Effect.ALLOW,
                principals=[iam.ServicePrincipal("lakeformation.amazonaws.com")],
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                ],
                resources=[bucket.bucket_arn, f"{bucket.bucket_arn}/*"],
            )
        )
        
        cdk.Tags.of(bucket).add("Project", "LakeFormationCrossAccount")
        cdk.Tags.of(bucket).add("Environment", "Demo")
        
        return bucket

    def _create_glue_service_role(self) -> iam.Role:
        """Create IAM role for AWS Glue service operations."""
        role = iam.Role(
            self,
            "GlueServiceRole",
            role_name="AWSGlueServiceRole-LakeFormation",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="Service role for AWS Glue to access data lake resources",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSGlueServiceRole"
                ),
            ],
        )
        
        # Add S3 permissions for the data lake bucket
        role.add_to_policy(
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
                    self.s3_bucket.bucket_arn,
                    f"{self.s3_bucket.bucket_arn}/*",
                ],
            )
        )
        
        return role

    def _deploy_sample_data(self) -> None:
        """Deploy sample data files to the S3 data lake bucket."""
        # Create sample financial data
        financial_data = """department,revenue,expenses,profit,quarter
finance,1000000,800000,200000,Q1
marketing,500000,450000,50000,Q1
engineering,750000,700000,50000,Q1
hr,300000,280000,20000,Q1"""

        # Create sample customer data
        customer_data = """customer_id,name,department,region
1001,Acme Corp,finance,us-east
1002,TechStart Inc,engineering,us-west
1003,Marketing Pro,marketing,eu-west
1004,HR Solutions,hr,us-central"""

        # Deploy sample data using assets
        s3deploy.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3deploy.Source.data(
                    "financial-reports/2024-q1.csv", financial_data
                ),
                s3deploy.Source.data(
                    "customer-data/customers.csv", customer_data
                ),
            ],
            destination_bucket=self.s3_bucket,
            retain_on_delete=False,
        )

    def _create_financial_database(self) -> glue.CfnDatabase:
        """Create Glue database for financial data."""
        return glue.CfnDatabase(
            self,
            "FinancialDatabase",
            catalog_id=self.account_id,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="financial_db",
                description="Financial reporting database for cross-account sharing",
            ),
        )

    def _create_customer_database(self) -> glue.CfnDatabase:
        """Create Glue database for customer data."""
        return glue.CfnDatabase(
            self,
            "CustomerDatabase", 
            catalog_id=self.account_id,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="customer_db",
                description="Customer information database",
            ),
        )

    def _create_financial_crawler(self) -> glue.CfnCrawler:
        """Create Glue crawler for financial reports data."""
        return glue.CfnCrawler(
            self,
            "FinancialReportsCrawler",
            name="financial-reports-crawler",
            role=self.glue_service_role.role_arn,
            database_name=self.financial_db.ref,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.s3_bucket.bucket_name}/financial-reports/"
                    )
                ]
            ),
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG",
            ),
            description="Crawler for financial reports data in the data lake",
        )

    def _setup_lake_formation(self) -> None:
        """Configure Lake Formation as the data lake service."""
        # Register data lake administrators
        lf.CfnDataLakeSettings(
            self,
            "DataLakeSettings",
            admins=[
                lf.CfnDataLakeSettings.AdminsProperty(
                    data_lake_principal_identifier=self.data_lake_admin_arn
                )
            ],
            # Disable default database and table permissions for fine-grained control
            create_database_default_permissions=[],
            create_table_default_permissions=[],
        )

        # Register S3 location with Lake Formation
        lf.CfnResource(
            self,
            "DataLakeResource",
            resource_arn=self.s3_bucket.bucket_arn,
            use_service_linked_role=True,
        )

    def _create_lf_tags(self) -> None:
        """Create Lake Formation tags for tag-based access control."""
        # Department LF-Tag
        self.department_tag = lf.CfnTag(
            self,
            "DepartmentTag",
            tag_key="department",
            tag_values=["finance", "marketing", "engineering", "hr"],
        )

        # Classification LF-Tag
        self.classification_tag = lf.CfnTag(
            self,
            "ClassificationTag",
            tag_key="classification", 
            tag_values=["public", "internal", "confidential", "restricted"],
        )

        # Data category LF-Tag
        self.data_category_tag = lf.CfnTag(
            self,
            "DataCategoryTag",
            tag_key="data-category",
            tag_values=["financial", "customer", "operational", "analytics"],
        )

    def _assign_lf_tags_to_resources(self) -> None:
        """Assign LF-Tags to databases and tables."""
        # Tag financial database
        lf.CfnTagAssociation(
            self,
            "FinancialDatabaseTags",
            resource=lf.CfnTagAssociation.ResourceProperty(
                database=lf.CfnTagAssociation.DatabaseResourceProperty(
                    catalog_id=self.account_id,
                    name=self.financial_db.ref,
                )
            ),
            lf_tags=[
                lf.CfnTagAssociation.LFTagPairProperty(
                    catalog_id=self.account_id,
                    tag_key="department",
                    tag_values=["finance"],
                ),
                lf.CfnTagAssociation.LFTagPairProperty(
                    catalog_id=self.account_id,
                    tag_key="classification",
                    tag_values=["confidential"],
                ),
                lf.CfnTagAssociation.LFTagPairProperty(
                    catalog_id=self.account_id,
                    tag_key="data-category",
                    tag_values=["financial"],
                ),
            ],
        )

        # Tag customer database
        lf.CfnTagAssociation(
            self,
            "CustomerDatabaseTags",
            resource=lf.CfnTagAssociation.ResourceProperty(
                database=lf.CfnTagAssociation.DatabaseResourceProperty(
                    catalog_id=self.account_id,
                    name=self.customer_db.ref,
                )
            ),
            lf_tags=[
                lf.CfnTagAssociation.LFTagPairProperty(
                    catalog_id=self.account_id,
                    tag_key="department",
                    tag_values=["marketing"],
                ),
                lf.CfnTagAssociation.LFTagPairProperty(
                    catalog_id=self.account_id,
                    tag_key="classification",
                    tag_values=["internal"],
                ),
                lf.CfnTagAssociation.LFTagPairProperty(
                    catalog_id=self.account_id,
                    tag_key="data-category",
                    tag_values=["customer"],
                ),
            ],
        )

    def _create_cross_account_resource_share(self) -> ram.CfnResourceShare:
        """Create AWS RAM resource share for cross-account access."""
        # Grant permissions to consumer account for finance department data
        lf.CfnPermissions(
            self,
            "CrossAccountLFPermissions",
            data_lake_principal=lf.CfnPermissions.DataLakePrincipalProperty(
                data_lake_principal_identifier=self.consumer_account_id
            ),
            resource=lf.CfnPermissions.ResourceProperty(
                lf_tag=lf.CfnPermissions.LFTagKeyResourceProperty(
                    catalog_id=self.account_id,
                    tag_key="department",
                    tag_values=["finance"],
                )
            ),
            permissions=["ASSOCIATE", "DESCRIBE"],
            permissions_with_grant_option=["ASSOCIATE"],
        )

        # Create resource share
        resource_share = ram.CfnResourceShare(
            self,
            "LakeFormationResourceShare",
            name="lake-formation-cross-account-share",
            resource_arns=[
                f"arn:aws:glue:{self.region}:{self.account_id}:database/{self.financial_db.ref}"
            ],
            principals=[self.consumer_account_id],
            allow_external_principals=True,
        )

        return resource_share

    def _create_data_analyst_role_template(self) -> Dict[str, any]:
        """Create template for data analyst role in consumer account."""
        # This creates a template that can be used in the consumer account
        role_template = {
            "RoleName": "DataAnalystRole",
            "AssumeRolePolicyDocument": {
                "Version": "2012-10-17",
                "Statement": [
                    {
                        "Effect": "Allow",
                        "Principal": {
                            "AWS": f"arn:aws:iam::{self.consumer_account_id}:root"
                        },
                        "Action": "sts:AssumeRole",
                    }
                ],
            },
            "ManagedPolicyArns": [
                "arn:aws:iam::aws:policy/AmazonAthenaFullAccess",
                "arn:aws:iam::aws:policy/AWSGlueConsoleFullAccess",
            ],
        }
        
        return role_template

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "DataLakeBucketName",
            value=self.s3_bucket.bucket_name,
            description="Name of the S3 data lake bucket",
            export_name=f"{self.stack_name}-DataLakeBucket",
        )

        CfnOutput(
            self,
            "FinancialDatabaseName",
            value=self.financial_db.ref,
            description="Name of the financial database in Glue Data Catalog",
            export_name=f"{self.stack_name}-FinancialDatabase",
        )

        CfnOutput(
            self,
            "ResourceShareArn",
            value=self.resource_share.attr_arn,
            description="ARN of the AWS RAM resource share",
            export_name=f"{self.stack_name}-ResourceShare",
        )

        CfnOutput(
            self,
            "ConsumerAccountId",
            value=self.consumer_account_id,
            description="Consumer account ID for cross-account sharing",
        )

        CfnOutput(
            self,
            "GlueServiceRoleArn",
            value=self.glue_service_role.role_arn,
            description="ARN of the Glue service role",
        )

        CfnOutput(
            self,
            "LakeFormationResourceArn",
            value=self.s3_bucket.bucket_arn,
            description="ARN of the registered Lake Formation resource",
        )


class LakeFormationConsumerStack(Stack):
    """
    CDK Stack for the consumer account in Lake Formation cross-account sharing.
    
    This stack should be deployed in the consumer account and creates:
    - Data analyst IAM role with appropriate permissions
    - Resource links to shared databases
    - Lake Formation permissions for data access
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        *,
        producer_account_id: str,
        shared_database_name: str = "financial_db",
        **kwargs
    ) -> None:
        """
        Initialize the Consumer Stack.
        
        Args:
            scope: CDK scope
            construct_id: Unique identifier for this construct
            producer_account_id: AWS account ID that shared the data
            shared_database_name: Name of the shared database
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        self.producer_account_id = producer_account_id
        self.consumer_account_id = self.account
        self.shared_database_name = shared_database_name

        # Configure Lake Formation in consumer account
        self._setup_consumer_lake_formation()
        
        # Create data analyst role
        self.data_analyst_role = self._create_data_analyst_role()
        
        # Create resource link to shared database
        self.shared_database_link = self._create_shared_database_link()
        
        # Grant permissions to data analyst role
        self._grant_analyst_permissions()
        
        # Create outputs
        self._create_consumer_outputs()

    def _setup_consumer_lake_formation(self) -> None:
        """Configure Lake Formation settings in consumer account."""
        lf.CfnDataLakeSettings(
            self,
            "ConsumerDataLakeSettings",
            admins=[
                lf.CfnDataLakeSettings.AdminsProperty(
                    data_lake_principal_identifier=f"arn:aws:iam::{self.consumer_account_id}:root"
                )
            ],
            create_database_default_permissions=[],
            create_table_default_permissions=[],
        )

    def _create_data_analyst_role(self) -> iam.Role:
        """Create IAM role for data analysts in the consumer account."""
        role = iam.Role(
            self,
            "DataAnalystRole",
            role_name="DataAnalystRole",
            assumed_by=iam.AccountPrincipal(self.consumer_account_id),
            description="Role for data analysts to access shared Lake Formation data",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AmazonAthenaFullAccess"
                ),
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "AWSGlueConsoleFullAccess"
                ),
            ],
        )

        return role

    def _create_shared_database_link(self) -> glue.CfnDatabase:
        """Create resource link to shared database from producer account."""
        return glue.CfnDatabase(
            self,
            "SharedFinancialDatabaseLink",
            catalog_id=self.consumer_account_id,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="shared_financial_db",
                description="Resource link to shared financial database",
                target_database=glue.CfnDatabase.DatabaseIdentifierProperty(
                    catalog_id=self.producer_account_id,
                    database_name=self.shared_database_name,
                ),
            ),
        )

    def _grant_analyst_permissions(self) -> None:
        """Grant Lake Formation permissions to the data analyst role."""
        # Grant permissions on the finance department data via LF-Tags
        lf.CfnPermissions(
            self,
            "AnalystLFTagPermissions",
            data_lake_principal=lf.CfnPermissions.DataLakePrincipalProperty(
                data_lake_principal_identifier=self.data_analyst_role.role_arn
            ),
            resource=lf.CfnPermissions.ResourceProperty(
                lf_tag=lf.CfnPermissions.LFTagKeyResourceProperty(
                    catalog_id=self.producer_account_id,
                    tag_key="department",
                    tag_values=["finance"],
                )
            ),
            permissions=["SELECT", "DESCRIBE"],
        )

        # Grant permissions on the resource link database
        lf.CfnPermissions(
            self,
            "AnalystDatabasePermissions",
            data_lake_principal=lf.CfnPermissions.DataLakePrincipalProperty(
                data_lake_principal_identifier=self.data_analyst_role.role_arn
            ),
            resource=lf.CfnPermissions.ResourceProperty(
                database=lf.CfnPermissions.DatabaseResourceProperty(
                    catalog_id=self.consumer_account_id,
                    name=self.shared_database_link.ref,
                )
            ),
            permissions=["DESCRIBE"],
        )

    def _create_consumer_outputs(self) -> None:
        """Create outputs for the consumer stack."""
        CfnOutput(
            self,
            "DataAnalystRoleArn",
            value=self.data_analyst_role.role_arn,
            description="ARN of the data analyst role",
            export_name=f"{self.stack_name}-DataAnalystRole",
        )

        CfnOutput(
            self,
            "SharedDatabaseLinkName",
            value=self.shared_database_link.ref,
            description="Name of the shared database resource link",
            export_name=f"{self.stack_name}-SharedDatabaseLink",
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    app = cdk.App()

    # Get configuration from context or environment variables
    consumer_account_id = app.node.try_get_context("consumer_account_id") or os.environ.get(
        "CONSUMER_ACCOUNT_ID"
    )
    
    if not consumer_account_id:
        raise ValueError(
            "Consumer account ID must be provided via context or CONSUMER_ACCOUNT_ID environment variable"
        )

    # Get optional data lake admin ARN
    data_lake_admin_arn = app.node.try_get_context("data_lake_admin_arn") or os.environ.get(
        "DATA_LAKE_ADMIN_ARN"
    )

    # Create producer account stack
    producer_stack = LakeFormationCrossAccountStack(
        app,
        "LakeFormationProducerStack",
        consumer_account_id=consumer_account_id,
        data_lake_admin_arn=data_lake_admin_arn,
        description="Producer account stack for Lake Formation cross-account data sharing",
    )

    # Add tags to the producer stack
    cdk.Tags.of(producer_stack).add("Project", "LakeFormationCrossAccount")
    cdk.Tags.of(producer_stack).add("Environment", "Demo")
    cdk.Tags.of(producer_stack).add("AccountType", "Producer")

    # Optionally create consumer stack (commented out as it should be deployed in different account)
    # Uncomment and customize when deploying to consumer account
    """
    consumer_stack = LakeFormationConsumerStack(
        app,
        "LakeFormationConsumerStack",
        producer_account_id=producer_stack.account,
        shared_database_name="financial_db",
        description="Consumer account stack for Lake Formation cross-account data sharing",
    )
    
    cdk.Tags.of(consumer_stack).add("Project", "LakeFormationCrossAccount")
    cdk.Tags.of(consumer_stack).add("Environment", "Demo")
    cdk.Tags.of(consumer_stack).add("AccountType", "Consumer")
    """

    app.synth()


if __name__ == "__main__":
    main()