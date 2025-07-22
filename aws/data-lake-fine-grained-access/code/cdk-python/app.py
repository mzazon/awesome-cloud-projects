#!/usr/bin/env python3
"""
AWS CDK Python application for Data Lake Formation Fine-Grained Access Control

This CDK application implements a complete data lake architecture with AWS Lake Formation
providing fine-grained access controls at the table, column, and row level.

Key Components:
- S3 bucket for data lake storage
- AWS Glue Data Catalog database and table
- Lake Formation configuration with data lake administrator
- IAM roles representing different user personas
- Fine-grained permissions for column-level access control
- Data cell filters for row-level security

The architecture demonstrates how to implement enterprise-grade data governance
using Lake Formation's centralized security management capabilities.
"""

import os
from typing import List, Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_glue as glue,
    aws_iam as iam,
    aws_lakeformation as lakeformation,
    RemovalPolicy,
    CfnOutput
)
from constructs import Construct


class DataLakeFormationStack(Stack):
    """
    CDK Stack implementing AWS Lake Formation with fine-grained access control.
    
    This stack creates a complete data lake infrastructure with:
    - S3 bucket for data storage
    - Glue Data Catalog with database and table
    - Lake Formation configuration
    - IAM roles for different user types
    - Fine-grained access permissions
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Create S3 bucket for data lake
        self.data_lake_bucket = self._create_data_lake_bucket(unique_suffix)
        
        # Create sample data in S3
        self._deploy_sample_data()
        
        # Create Glue Data Catalog resources
        self.database, self.table = self._create_glue_catalog()
        
        # Create IAM roles for different user personas
        self.user_roles = self._create_user_roles()
        
        # Configure Lake Formation
        self._configure_lake_formation()
        
        # Grant fine-grained permissions
        self._grant_lake_formation_permissions()
        
        # Create data cell filters for row-level security
        self._create_data_cell_filters()
        
        # Add stack outputs
        self._create_outputs()

    def _create_data_lake_bucket(self, unique_suffix: str) -> s3.Bucket:
        """
        Create S3 bucket for data lake storage with appropriate security settings.
        
        Args:
            unique_suffix: Unique suffix for bucket naming
            
        Returns:
            S3 bucket construct
        """
        bucket_name = f"data-lake-fgac-{unique_suffix}"
        
        bucket = s3.Bucket(
            self, "DataLakeBucket",
            bucket_name=bucket_name,
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUpload",
                    abort_incomplete_multipart_upload_after=cdk.Duration.days(7)
                )
            ]
        )
        
        # Add tags for governance
        Tags.of(bucket).add("Project", "DataLakeFormation")
        Tags.of(bucket).add("Environment", "Demo")
        Tags.of(bucket).add("DataClassification", "Restricted")
        
        return bucket

    def _deploy_sample_data(self) -> None:
        """Deploy sample CSV data to the S3 bucket for testing."""
        
        # Create sample customer data
        sample_data_content = """customer_id,name,email,department,salary,ssn
1,John Doe,john@example.com,Engineering,75000,123-45-6789
2,Jane Smith,jane@example.com,Marketing,65000,987-65-4321
3,Bob Johnson,bob@example.com,Finance,80000,456-78-9012
4,Alice Brown,alice@example.com,Engineering,70000,321-54-9876
5,Charlie Wilson,charlie@example.com,HR,60000,654-32-1098
6,Diana Prince,diana@example.com,Engineering,85000,111-22-3333
7,Bruce Wayne,bruce@example.com,Finance,90000,444-55-6666
8,Clark Kent,clark@example.com,Marketing,68000,777-88-9999
9,Tony Stark,tony@example.com,Engineering,95000,000-11-2222
10,Steve Rogers,steve@example.com,HR,62000,333-44-5555"""

        # Deploy sample data using BucketDeployment
        s3_deployment.BucketDeployment(
            self, "SampleDataDeployment",
            sources=[s3_deployment.Source.data("customer_data/sample_data.csv", sample_data_content)],
            destination_bucket=self.data_lake_bucket,
            prune=False
        )

    def _create_glue_catalog(self) -> tuple[glue.CfnDatabase, glue.CfnTable]:
        """
        Create AWS Glue Data Catalog database and table.
        
        Returns:
            Tuple of (database, table) constructs
        """
        # Create Glue database
        database = glue.CfnDatabase(
            self, "SampleDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name="sample_database",
                description="Sample database for fine-grained access control demonstration"
            )
        )
        
        # Define table schema
        columns = [
            glue.CfnTable.ColumnProperty(name="customer_id", type="bigint"),
            glue.CfnTable.ColumnProperty(name="name", type="string"),
            glue.CfnTable.ColumnProperty(name="email", type="string"),
            glue.CfnTable.ColumnProperty(name="department", type="string"),
            glue.CfnTable.ColumnProperty(name="salary", type="bigint"),
            glue.CfnTable.ColumnProperty(name="ssn", type="string")
        ]
        
        # Create Glue table
        table = glue.CfnTable(
            self, "CustomerDataTable",
            catalog_id=self.account,
            database_name=database.ref,
            table_input=glue.CfnTable.TableInputProperty(
                name="customer_data",
                description="Customer data table with sensitive information",
                table_type="EXTERNAL_TABLE",
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    columns=columns,
                    location=f"s3://{self.data_lake_bucket.bucket_name}/customer_data/",
                    input_format="org.apache.hadoop.mapred.TextInputFormat",
                    output_format="org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat",
                    serde_info=glue.CfnTable.SerdeInfoProperty(
                        serialization_library="org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe",
                        parameters={
                            "field.delim": ",",
                            "skip.header.line.count": "1"
                        }
                    )
                )
            )
        )
        
        # Add dependency
        table.add_dependency(database)
        
        return database, table

    def _create_user_roles(self) -> Dict[str, iam.Role]:
        """
        Create IAM roles representing different user personas.
        
        Returns:
            Dictionary of role names to IAM role constructs
        """
        roles = {}
        
        # Trust policy for roles
        trust_policy = iam.PolicyDocument(
            statements=[
                iam.PolicyStatement(
                    effect=iam.Effect.ALLOW,
                    principals=[
                        iam.ServicePrincipal("glue.amazonaws.com"),
                        iam.AccountRootPrincipal()
                    ],
                    actions=["sts:AssumeRole"]
                )
            ]
        )
        
        # Basic policies for data access
        basic_glue_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "glue:GetDatabase",
                "glue:GetDatabases",
                "glue:GetTable",
                "glue:GetTables",
                "glue:GetPartition",
                "glue:GetPartitions"
            ],
            resources=["*"]
        )
        
        athena_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "athena:StartQueryExecution",
                "athena:GetQueryExecution",
                "athena:GetQueryResults",
                "athena:StopQueryExecution",
                "athena:GetWorkGroup"
            ],
            resources=["*"]
        )
        
        s3_query_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetBucketLocation",
                "s3:GetObject",
                "s3:ListBucket",
                "s3:PutObject"
            ],
            resources=[
                self.data_lake_bucket.bucket_arn,
                f"{self.data_lake_bucket.bucket_arn}/*"
            ]
        )
        
        # Data Analyst Role (full access)
        roles["data_analyst"] = iam.Role(
            self, "DataAnalystRole",
            role_name="DataAnalystRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("glue.amazonaws.com"),
                iam.AccountRootPrincipal()
            ),
            description="Role for data analysts with full table access",
            inline_policies={
                "DataAnalystPolicy": iam.PolicyDocument(
                    statements=[basic_glue_policy, athena_policy, s3_query_policy]
                )
            }
        )
        
        # Finance Team Role (limited columns)
        roles["finance_team"] = iam.Role(
            self, "FinanceTeamRole",
            role_name="FinanceTeamRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("glue.amazonaws.com"),
                iam.AccountRootPrincipal()
            ),
            description="Role for finance team with column-level restrictions",
            inline_policies={
                "FinanceTeamPolicy": iam.PolicyDocument(
                    statements=[basic_glue_policy, athena_policy, s3_query_policy]
                )
            }
        )
        
        # HR Role (very limited access)
        roles["hr"] = iam.Role(
            self, "HRRole",
            role_name="HRRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("glue.amazonaws.com"),
                iam.AccountRootPrincipal()
            ),
            description="Role for HR with minimal data access",
            inline_policies={
                "HRPolicy": iam.PolicyDocument(
                    statements=[basic_glue_policy, athena_policy, s3_query_policy]
                )
            }
        )
        
        return roles

    def _configure_lake_formation(self) -> None:
        """Configure Lake Formation settings and register S3 location."""
        
        # Register S3 location with Lake Formation
        lakeformation.CfnResource(
            self, "DataLakeResource",
            resource_arn=self.data_lake_bucket.bucket_arn,
            use_service_linked_role=True
        )
        
        # Configure Lake Formation settings to disable default IAM permissions
        lakeformation.CfnDataLakeSettings(
            self, "DataLakeSettings",
            # Note: In a real deployment, you would specify actual data lake admins
            # For this demo, we'll configure it through the CLI in the deployment script
            create_database_default_permissions=[],
            create_table_default_permissions=[]
        )

    def _grant_lake_formation_permissions(self) -> None:
        """Grant fine-grained Lake Formation permissions to different roles."""
        
        # Grant full table access to data analyst
        lakeformation.CfnPermissions(
            self, "DataAnalystTablePermissions",
            data_lake_principal=lakeformation.CfnPermissions.DataLakePrincipalProperty(
                data_lake_principal_identifier=self.user_roles["data_analyst"].role_arn
            ),
            resource=lakeformation.CfnPermissions.ResourceProperty(
                table=lakeformation.CfnPermissions.TableResourceProperty(
                    catalog_id=self.account,
                    database_name=self.database.ref,
                    name=self.table.ref
                )
            ),
            permissions=["SELECT"],
            permissions_with_grant_option=[]
        )
        
        # Grant limited column access to finance team (no SSN)
        lakeformation.CfnPermissions(
            self, "FinanceTeamColumnPermissions",
            data_lake_principal=lakeformation.CfnPermissions.DataLakePrincipalProperty(
                data_lake_principal_identifier=self.user_roles["finance_team"].role_arn
            ),
            resource=lakeformation.CfnPermissions.ResourceProperty(
                table_with_columns=lakeformation.CfnPermissions.TableWithColumnsResourceProperty(
                    catalog_id=self.account,
                    database_name=self.database.ref,
                    name=self.table.ref,
                    column_names=["customer_id", "name", "department", "salary"]
                )
            ),
            permissions=["SELECT"],
            permissions_with_grant_option=[]
        )
        
        # Grant very limited access to HR (only name and department)
        lakeformation.CfnPermissions(
            self, "HRColumnPermissions",
            data_lake_principal=lakeformation.CfnPermissions.DataLakePrincipalProperty(
                data_lake_principal_identifier=self.user_roles["hr"].role_arn
            ),
            resource=lakeformation.CfnPermissions.ResourceProperty(
                table_with_columns=lakeformation.CfnPermissions.TableWithColumnsResourceProperty(
                    catalog_id=self.account,
                    database_name=self.database.ref,
                    name=self.table.ref,
                    column_names=["customer_id", "name", "department"]
                )
            ),
            permissions=["SELECT"],
            permissions_with_grant_option=[]
        )

    def _create_data_cell_filters(self) -> None:
        """Create data cell filters for row-level security."""
        
        # Create data filter for finance team (only Engineering department)
        lakeformation.CfnDataCellsFilter(
            self, "EngineeringOnlyFilter",
            table_catalog_id=self.account,
            database_name=self.database.ref,
            table_name=self.table.ref,
            name="engineering-only-filter",
            row_filter=lakeformation.CfnDataCellsFilter.RowFilterProperty(
                filter_expression='department = "Engineering"'
            ),
            column_names=["customer_id", "name", "department", "salary"]
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources."""
        
        CfnOutput(
            self, "DataLakeBucketName",
            value=self.data_lake_bucket.bucket_name,
            description="Name of the S3 bucket used for data lake storage"
        )
        
        CfnOutput(
            self, "GlueDatabaseName",
            value=self.database.ref,
            description="Name of the Glue database"
        )
        
        CfnOutput(
            self, "GlueTableName",
            value=self.table.ref,
            description="Name of the Glue table"
        )
        
        CfnOutput(
            self, "DataAnalystRoleArn",
            value=self.user_roles["data_analyst"].role_arn,
            description="ARN of the Data Analyst role"
        )
        
        CfnOutput(
            self, "FinanceTeamRoleArn",
            value=self.user_roles["finance_team"].role_arn,
            description="ARN of the Finance Team role"
        )
        
        CfnOutput(
            self, "HRRoleArn",
            value=self.user_roles["hr"].role_arn,
            description="ARN of the HR role"
        )


def main() -> None:
    """Main function to create and deploy the CDK application."""
    
    app = cdk.App()
    
    # Get environment from context or use default
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")
    
    env = Environment(account=account, region=region)
    
    # Create the stack
    stack = DataLakeFormationStack(
        app, "DataLakeFormationStack",
        env=env,
        description="AWS Lake Formation with Fine-Grained Access Control"
    )
    
    # Add stack-level tags
    Tags.of(stack).add("Project", "DataLakeFormation")
    Tags.of(stack).add("Recipe", "data-lake-formation-fine-grained-access-control")
    Tags.of(stack).add("Environment", "Demo")
    
    # Synthesize the application
    app.synth()


if __name__ == "__main__":
    main()