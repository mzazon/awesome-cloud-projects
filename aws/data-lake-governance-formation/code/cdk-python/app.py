#!/usr/bin/env python3
"""
AWS CDK Python application for Advanced Data Lake Governance with Lake Formation and DataZone.

This application deploys a comprehensive data lake governance platform including:
- S3 data lake with tiered storage (raw, curated, analytics)
- AWS Lake Formation for fine-grained access control
- Amazon DataZone for data discovery and cataloging
- AWS Glue for ETL operations and data catalog
- IAM roles for secure data access
- CloudWatch monitoring and alerting
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    Tags,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from aws_cdk import aws_s3 as s3
from aws_cdk import aws_iam as iam
from aws_cdk import aws_glue as glue
from aws_cdk import aws_lakeformation as lakeformation
from aws_cdk import aws_datazone as datazone
from aws_cdk import aws_logs as logs
from aws_cdk import aws_sns as sns
from aws_cdk import aws_cloudwatch as cloudwatch
from aws_cdk import aws_cloudwatch_actions as cw_actions
from constructs import Construct


class DataLakeGovernanceStack(Stack):
    """
    CDK Stack for Advanced Data Lake Governance with Lake Formation and DataZone.
    
    This stack creates a complete data governance platform with:
    - Multi-tier S3 data lake (raw, curated, analytics zones)
    - Lake Formation governance with fine-grained access control
    - DataZone domain for business data cataloging
    - Glue data catalog and ETL jobs with lineage tracking
    - IAM roles for secure, role-based data access
    - Comprehensive monitoring and alerting
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.domain_name = "enterprise-data-governance"
        self.glue_database_name = "enterprise_data_catalog"
        
        # Create core infrastructure
        self.data_lake_bucket = self._create_data_lake_storage()
        self.iam_roles = self._create_iam_roles()
        self.glue_resources = self._create_glue_resources()
        self.lake_formation_config = self._configure_lake_formation()
        self.datazone_domain = self._create_datazone_domain()
        self.monitoring = self._create_monitoring_and_alerts()

        # Apply common tags
        self._apply_tags()

        # Create outputs
        self._create_outputs()

    def _create_data_lake_storage(self) -> s3.Bucket:
        """
        Create S3 bucket for data lake with proper security and lifecycle configuration.
        
        Returns:
            s3.Bucket: The configured data lake bucket with encryption and versioning
        """
        # Create data lake bucket with security best practices
        bucket = s3.Bucket(
            self, "DataLakeBucket",
            bucket_name=f"enterprise-datalake-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            versioned=True,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            auto_delete_objects=True,  # For demo purposes
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DataLakeLifecycle",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.DEEP_ARCHIVE,
                            transition_after=Duration.days(365)
                        )
                    ]
                )
            ]
        )

        # Create folder structure for data lake zones
        for prefix in ["raw-data", "curated-data", "analytics-data", "scripts", "athena-results", "spark-logs"]:
            s3.BucketDeployment(
                self, f"Create{prefix.title().replace('-', '')}Folder",
                sources=[],
                destination_bucket=bucket,
                destination_key_prefix=f"{prefix}/",
                retain_on_delete=False
            )

        return bucket

    def _create_iam_roles(self) -> Dict[str, iam.Role]:
        """
        Create IAM roles for Lake Formation service and data access.
        
        Returns:
            Dict[str, iam.Role]: Dictionary containing the created IAM roles
        """
        roles = {}

        # Lake Formation service role
        lf_service_role = iam.Role(
            self, "LakeFormationServiceRole",
            role_name="LakeFormationServiceRole",
            assumed_by=iam.CompositePrincipal(
                iam.ServicePrincipal("lakeformation.amazonaws.com"),
                iam.ServicePrincipal("glue.amazonaws.com")
            ),
            description="Service role for Lake Formation and Glue operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/LakeFormationDataAccessRole")
            ]
        )

        # Add custom policy for comprehensive Lake Formation operations
        lf_service_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:ListBucketMultipartUploads",
                    "s3:ListMultipartUploadParts",
                    "s3:AbortMultipartUpload"
                ],
                resources=[
                    self.data_lake_bucket.bucket_arn,
                    f"{self.data_lake_bucket.bucket_arn}/*"
                ]
            )
        )

        lf_service_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "glue:*",
                    "lakeformation:GetDataAccess",
                    "lakeformation:GrantPermissions",
                    "lakeformation:RevokePermissions",
                    "lakeformation:BatchGrantPermissions",
                    "lakeformation:BatchRevokePermissions",
                    "lakeformation:ListPermissions",
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=["*"]
            )
        )

        roles["lake_formation_service"] = lf_service_role

        # Data analyst role for restricted data access
        data_analyst_role = iam.Role(
            self, "DataAnalystRole",
            role_name="DataAnalystRole",
            assumed_by=iam.CompositePrincipal(
                iam.ArnPrincipal(f"arn:aws:iam::{self.account}:root"),
                iam.ServicePrincipal("athena.amazonaws.com")
            ),
            description="Role for data analysts with governed data access",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AmazonAthenaFullAccess"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSGlueConsoleFullAccess")
            ]
        )

        # Add Lake Formation permissions
        data_analyst_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "lakeformation:GetDataAccess",
                    "lakeformation:GetWorkUnits",
                    "lakeformation:StartQueryPlanning",
                    "lakeformation:GetWorkUnitResults",
                    "lakeformation:GetQueryState",
                    "lakeformation:GetQueryStatistics"
                ],
                resources=["*"]
            )
        )

        roles["data_analyst"] = data_analyst_role

        # DataZone execution role
        datazone_execution_role = iam.Role(
            self, "DataZoneExecutionRole",
            role_name="DataZoneExecutionRole",
            assumed_by=iam.ServicePrincipal("datazone.amazonaws.com"),
            description="Execution role for Amazon DataZone domain",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AmazonDataZoneServiceRole")
            ]
        )

        roles["datazone_execution"] = datazone_execution_role

        return roles

    def _create_glue_resources(self) -> Dict[str, Any]:
        """
        Create AWS Glue resources including database, tables, and ETL job.
        
        Returns:
            Dict[str, Any]: Dictionary containing created Glue resources
        """
        resources = {}

        # Create Glue database for enterprise data catalog
        glue_database = glue.CfnDatabase(
            self, "EnterpriseDataCatalog",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=self.glue_database_name,
                description="Enterprise data catalog for governed data lake",
                location_uri=f"s3://{self.data_lake_bucket.bucket_name}/curated-data/",
                parameters={
                    "classification": "curated",
                    "environment": "production"
                }
            )
        )

        resources["database"] = glue_database

        # Create customer data table with PII classification
        customer_table = glue.CfnTable(
            self, "CustomerDataTable",
            catalog_id=self.account,
            database_name=self.glue_database_name,
            table_input=glue.CfnTable.TableInputProperty(
                name="customer_data",
                description="Customer information with PII protection",
                table_type="EXTERNAL_TABLE",
                parameters={
                    "classification": "csv",
                    "delimiter": ",",
                    "has_encrypted_data": "false",
                    "data_classification": "confidential"
                },
                partition_keys=[
                    glue.CfnTable.ColumnProperty(name="year", type="string"),
                    glue.CfnTable.ColumnProperty(name="month", type="string")
                ],
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    columns=[
                        glue.CfnTable.ColumnProperty(name="customer_id", type="bigint", comment="Unique customer identifier"),
                        glue.CfnTable.ColumnProperty(name="first_name", type="string", comment="Customer first name - PII"),
                        glue.CfnTable.ColumnProperty(name="last_name", type="string", comment="Customer last name - PII"),
                        glue.CfnTable.ColumnProperty(name="email", type="string", comment="Customer email - PII"),
                        glue.CfnTable.ColumnProperty(name="phone", type="string", comment="Customer phone - PII"),
                        glue.CfnTable.ColumnProperty(name="registration_date", type="date", comment="Account registration date"),
                        glue.CfnTable.ColumnProperty(name="customer_segment", type="string", comment="Business customer segment"),
                        glue.CfnTable.ColumnProperty(name="lifetime_value", type="double", comment="Customer lifetime value"),
                        glue.CfnTable.ColumnProperty(name="region", type="string", comment="Customer geographic region")
                    ],
                    location=f"s3://{self.data_lake_bucket.bucket_name}/curated-data/customer_data/",
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

        customer_table.add_dependency(glue_database)
        resources["customer_table"] = customer_table

        # Create transaction data table
        transaction_table = glue.CfnTable(
            self, "TransactionDataTable",
            catalog_id=self.account,
            database_name=self.glue_database_name,
            table_input=glue.CfnTable.TableInputProperty(
                name="transaction_data",
                description="Customer transaction records",
                table_type="EXTERNAL_TABLE",
                parameters={
                    "classification": "parquet",
                    "data_classification": "internal"
                },
                partition_keys=[
                    glue.CfnTable.ColumnProperty(name="year", type="string"),
                    glue.CfnTable.ColumnProperty(name="month", type="string"),
                    glue.CfnTable.ColumnProperty(name="day", type="string")
                ],
                storage_descriptor=glue.CfnTable.StorageDescriptorProperty(
                    columns=[
                        glue.CfnTable.ColumnProperty(name="transaction_id", type="string", comment="Unique transaction identifier"),
                        glue.CfnTable.ColumnProperty(name="customer_id", type="bigint", comment="Associated customer ID"),
                        glue.CfnTable.ColumnProperty(name="transaction_date", type="timestamp", comment="Transaction timestamp"),
                        glue.CfnTable.ColumnProperty(name="amount", type="double", comment="Transaction amount"),
                        glue.CfnTable.ColumnProperty(name="currency", type="string", comment="Transaction currency"),
                        glue.CfnTable.ColumnProperty(name="merchant_category", type="string", comment="Merchant category code"),
                        glue.CfnTable.ColumnProperty(name="payment_method", type="string", comment="Payment method used"),
                        glue.CfnTable.ColumnProperty(name="status", type="string", comment="Transaction status")
                    ],
                    location=f"s3://{self.data_lake_bucket.bucket_name}/curated-data/transaction_data/",
                    input_format="org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                    output_format="org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
                    serde_info=glue.CfnTable.SerdeInfoProperty(
                        serialization_library="org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
                    )
                )
            )
        )

        transaction_table.add_dependency(glue_database)
        resources["transaction_table"] = transaction_table

        # Create ETL job with lineage tracking
        etl_job = glue.CfnJob(
            self, "CustomerDataETLJob",
            name="CustomerDataETLWithLineage",
            role=self.iam_roles["lake_formation_service"].role_arn,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                python_version="3",
                script_location=f"s3://{self.data_lake_bucket.bucket_name}/scripts/customer_data_etl.py"
            ),
            default_arguments={
                "--job-language": "python",
                "--job-bookmark-option": "job-bookmark-enable",
                "--enable-metrics": "true",
                "--enable-continuous-cloudwatch-log": "true",
                "--enable-spark-ui": "true",
                "--spark-event-logs-path": f"s3://{self.data_lake_bucket.bucket_name}/spark-logs/",
                "--enable-glue-datacatalog": "true",
                "--DATA_LAKE_BUCKET": self.data_lake_bucket.bucket_name
            },
            description="ETL job for customer data processing with lineage tracking",
            glue_version="4.0",
            max_capacity=2.0,
            max_retries=1,
            timeout=60
        )

        resources["etl_job"] = etl_job

        return resources

    def _configure_lake_formation(self) -> Dict[str, Any]:
        """
        Configure Lake Formation settings and permissions.
        
        Returns:
            Dict[str, Any]: Dictionary containing Lake Formation configuration
        """
        config = {}

        # Configure Lake Formation data lake settings
        data_lake_settings = lakeformation.CfnDataLakeSettings(
            self, "DataLakeSettings",
            admins=[
                lakeformation.CfnDataLakeSettings.DataLakeAdminProperty(
                    data_lake_admin_type="IAMUser",
                    data_lake_admin_identifier=f"arn:aws:iam::{self.account}:root"
                )
            ],
            create_database_default_permissions=[],
            create_table_default_permissions=[],
            parameters={
                "CROSS_ACCOUNT_VERSION": "3"
            },
            trusted_resource_owners=[self.account],
            allow_external_data_filtering=True,
            external_data_filtering_allow_list=[self.account]
        )

        config["data_lake_settings"] = data_lake_settings

        # Register S3 location with Lake Formation
        s3_resource = lakeformation.CfnResource(
            self, "DataLakeS3Resource",
            resource_arn=self.data_lake_bucket.bucket_arn,
            use_service_linked_role=True
        )

        config["s3_resource"] = s3_resource

        # Create data cell filter for PII protection
        data_filter = lakeformation.CfnDataCellsFilter(
            self, "CustomerDataPIIFilter",
            table_catalog_id=self.account,
            database_name=self.glue_database_name,
            table_name="customer_data",
            name="customer_data_pii_filter",
            row_filter=lakeformation.CfnDataCellsFilter.RowFilterProperty(
                filter_expression="customer_segment IN ('premium', 'standard')"
            ),
            column_names=["customer_id", "registration_date", "customer_segment", "lifetime_value", "region"]
        )

        data_filter.add_dependency(self.glue_resources["customer_table"])
        config["data_filter"] = data_filter

        return config

    def _create_datazone_domain(self) -> datazone.CfnDomain:
        """
        Create Amazon DataZone domain for data governance and discovery.
        
        Returns:
            datazone.CfnDomain: The created DataZone domain
        """
        # Create DataZone domain
        domain = datazone.CfnDomain(
            self, "DataZoneDomain",
            name=self.domain_name,
            description="Enterprise data governance domain with Lake Formation integration",
            domain_execution_role=self.iam_roles["datazone_execution"].role_arn,
            single_sign_on=datazone.CfnDomain.SingleSignOnProperty(
                type="IAM_IDC",
                user_assignment="AUTOMATIC"
            )
        )

        return domain

    def _create_monitoring_and_alerts(self) -> Dict[str, Any]:
        """
        Create CloudWatch monitoring and SNS alerting for data quality.
        
        Returns:
            Dict[str, Any]: Dictionary containing monitoring resources
        """
        monitoring = {}

        # Create log group for data quality monitoring
        log_group = logs.LogGroup(
            self, "DataQualityLogGroup",
            log_group_name="/aws/datazone/data-quality",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY
        )

        monitoring["log_group"] = log_group

        # Create SNS topic for data quality alerts
        alert_topic = sns.Topic(
            self, "DataQualityAlerts",
            topic_name="DataQualityAlerts",
            description="Alerts for data quality issues in the data lake"
        )

        monitoring["alert_topic"] = alert_topic

        # Create CloudWatch alarm for failed ETL jobs
        etl_failure_alarm = cloudwatch.Alarm(
            self, "ETLJobFailureAlarm",
            alarm_name="DataLakeETLFailures",
            alarm_description="Alert when ETL jobs fail",
            metric=cloudwatch.Metric(
                namespace="AWS/Glue",
                metric_name="glue.driver.aggregate.numFailedTasks",
                dimensions_map={
                    "JobName": "CustomerDataETLWithLineage"
                },
                statistic="Sum"
            ),
            threshold=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
            evaluation_periods=1,
            period=Duration.minutes(5)
        )

        etl_failure_alarm.add_alarm_action(
            cw_actions.SnsAction(alert_topic)
        )

        monitoring["etl_failure_alarm"] = etl_failure_alarm

        return monitoring

    def _apply_tags(self) -> None:
        """Apply common tags to all resources in the stack."""
        Tags.of(self).add("Project", "DataLakeGovernance")
        Tags.of(self).add("Environment", "Production")
        Tags.of(self).add("Owner", "DataEngineering")
        Tags.of(self).add("CostCenter", "Analytics")
        Tags.of(self).add("Compliance", "Required")

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "DataLakeBucketName",
            value=self.data_lake_bucket.bucket_name,
            description="Name of the S3 data lake bucket",
            export_name=f"{self.stack_name}-DataLakeBucket"
        )

        CfnOutput(
            self, "GlueDatabaseName",
            value=self.glue_database_name,
            description="Name of the Glue data catalog database",
            export_name=f"{self.stack_name}-GlueDatabase"
        )

        CfnOutput(
            self, "DataZoneDomainId",
            value=self.datazone_domain.attr_id,
            description="ID of the DataZone domain",
            export_name=f"{self.stack_name}-DataZoneDomain"
        )

        CfnOutput(
            self, "LakeFormationServiceRoleArn",
            value=self.iam_roles["lake_formation_service"].role_arn,
            description="ARN of the Lake Formation service role",
            export_name=f"{self.stack_name}-LakeFormationServiceRole"
        )

        CfnOutput(
            self, "DataAnalystRoleArn",
            value=self.iam_roles["data_analyst"].role_arn,
            description="ARN of the data analyst role",
            export_name=f"{self.stack_name}-DataAnalystRole"
        )

        CfnOutput(
            self, "AlertTopicArn",
            value=self.monitoring["alert_topic"].topic_arn,
            description="ARN of the SNS topic for data quality alerts",
            export_name=f"{self.stack_name}-AlertTopic"
        )


def main():
    """Main function to create and deploy the CDK application."""
    app = cdk.App()

    # Get environment from context or use defaults
    account = app.node.try_get_context("account") or os.environ.get("CDK_DEFAULT_ACCOUNT")
    region = app.node.try_get_context("region") or os.environ.get("CDK_DEFAULT_REGION")

    # Create the stack
    DataLakeGovernanceStack(
        app,
        "DataLakeGovernanceStack",
        env=Environment(account=account, region=region),
        description="Advanced Data Lake Governance with Lake Formation and DataZone"
    )

    # Synthesize the CloudFormation template
    app.synth()


if __name__ == "__main__":
    main()