#!/usr/bin/env python3
"""
AWS CDK Python application for QuickSight Business Intelligence Solutions.

This application demonstrates how to create a comprehensive business intelligence
solution using Amazon QuickSight with multiple data sources including S3 and RDS.
The infrastructure includes data sources, datasets, analyses, dashboards, and
embedded analytics capabilities.
"""

import os
import aws_cdk as cdk
from aws_cdk import (
    App,
    Environment,
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
    aws_rds as rds,
    aws_ec2 as ec2,
    aws_iam as iam,
    aws_quicksight as quicksight,
    aws_logs as logs,
)
from constructs import Construct
from typing import Dict, Any, Optional


class QuickSightBIStack(Stack):
    """
    CloudFormation stack for QuickSight Business Intelligence solution.
    
    This stack creates:
    - S3 bucket with sample sales data
    - RDS MySQL database for operational data
    - VPC and security groups for RDS
    - IAM roles for QuickSight access
    - QuickSight data sources, datasets, and dashboards
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        quicksight_user_arn: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the QuickSight BI Stack.
        
        Args:
            scope: The parent construct
            construct_id: The stack identifier
            quicksight_user_arn: ARN of the QuickSight user for permissions
            **kwargs: Additional stack properties
        """
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.quicksight_user_arn = quicksight_user_arn or self._get_default_quicksight_user()
        
        # Create VPC for RDS
        self.vpc = self._create_vpc()
        
        # Create S3 data lake
        self.data_bucket = self._create_s3_data_lake()
        
        # Create RDS database
        self.database = self._create_rds_database()
        
        # Create IAM roles
        self.quicksight_role = self._create_quicksight_iam_role()
        
        # Create QuickSight resources
        self._create_quicksight_resources()
        
        # Create outputs
        self._create_outputs()

    def _get_default_quicksight_user(self) -> str:
        """Get default QuickSight user ARN pattern."""
        account_id = self.account
        region = self.region
        return f"arn:aws:quicksight:{region}:{account_id}:user/default/quicksight-user"

    def _create_vpc(self) -> ec2.Vpc:
        """
        Create VPC for RDS database connectivity.
        
        Returns:
            VPC construct with public and private subnets
        """
        vpc = ec2.Vpc(
            self,
            "QuickSightVPC",
            vpc_name="quicksight-bi-vpc",
            max_azs=2,
            nat_gateways=1,
            subnet_configuration=[
                ec2.SubnetConfiguration(
                    name="PublicSubnet",
                    subnet_type=ec2.SubnetType.PUBLIC,
                    cidr_mask=24,
                ),
                ec2.SubnetConfiguration(
                    name="PrivateSubnet",
                    subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS,
                    cidr_mask=24,
                ),
            ],
            enable_dns_hostnames=True,
            enable_dns_support=True,
        )
        
        # Tag VPC for identification
        cdk.Tags.of(vpc).add("Purpose", "QuickSight-BI-Demo")
        cdk.Tags.of(vpc).add("Environment", "Demo")
        
        return vpc

    def _create_s3_data_lake(self) -> s3.Bucket:
        """
        Create S3 bucket for data lake with sample sales data.
        
        Returns:
            S3 bucket with versioning and lifecycle policies
        """
        # Create S3 bucket for data storage
        bucket = s3.Bucket(
            self,
            "DataLakeBucket",
            bucket_name=f"quicksight-bi-data-{self.account}-{self.region}",
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
        
        # Create sample sales data
        sample_data = """date,region,product,sales_amount,quantity,customer_segment
2024-01-15,North America,Product A,1200.50,25,Enterprise
2024-01-15,Europe,Product B,850.75,15,SMB
2024-01-16,Asia Pacific,Product A,2100.25,42,Enterprise
2024-01-16,North America,Product C,675.00,18,Consumer
2024-01-17,Europe,Product A,1450.80,29,Enterprise
2024-01-17,Asia Pacific,Product B,920.45,21,SMB
2024-01-18,North America,Product B,1100.30,22,SMB
2024-01-18,Europe,Product C,780.90,16,Consumer
2024-01-19,Asia Pacific,Product C,1350.60,35,Enterprise
2024-01-19,North America,Product A,1680.75,33,Enterprise
2024-01-20,Europe,Product B,1275.40,28,Enterprise
2024-01-20,Asia Pacific,Product A,1895.60,38,Enterprise
2024-01-21,North America,Product C,925.85,24,SMB
2024-01-21,Europe,Product A,1620.30,32,Enterprise
2024-01-22,Asia Pacific,Product B,1150.75,25,SMB"""
        
        # Deploy sample data to S3
        s3deploy.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3deploy.Source.data(
                    "sales/sales_data.csv",
                    sample_data
                )
            ],
            destination_bucket=bucket,
            destination_key_prefix="sales/",
        )
        
        # Tag bucket for identification
        cdk.Tags.of(bucket).add("Purpose", "QuickSight-DataLake")
        cdk.Tags.of(bucket).add("DataType", "Sales")
        
        return bucket

    def _create_rds_database(self) -> rds.DatabaseInstance:
        """
        Create RDS MySQL database for operational data.
        
        Returns:
            RDS database instance with proper security configuration
        """
        # Create security group for RDS
        db_security_group = ec2.SecurityGroup(
            self,
            "DatabaseSecurityGroup",
            vpc=self.vpc,
            description="Security group for QuickSight demo database",
            allow_all_outbound=False,
        )
        
        # Allow QuickSight service to connect to database
        db_security_group.add_ingress_rule(
            peer=ec2.Peer.ipv4(self.vpc.vpc_cidr_block),
            connection=ec2.Port.tcp(3306),
            description="Allow MySQL access from VPC",
        )
        
        # Create subnet group for RDS
        subnet_group = rds.SubnetGroup(
            self,
            "DatabaseSubnetGroup",
            vpc=self.vpc,
            description="Subnet group for QuickSight demo database",
            subnet_group_name="quicksight-demo-subnet-group",
            vpc_subnets=ec2.SubnetSelection(
                subnet_type=ec2.SubnetType.PRIVATE_WITH_EGRESS
            ),
        )
        
        # Create RDS parameter group for optimization
        parameter_group = rds.ParameterGroup(
            self,
            "DatabaseParameterGroup",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            description="Parameter group for QuickSight demo database",
            parameters={
                "innodb_buffer_pool_size": "{DBInstanceClassMemory*3/4}",
                "max_connections": "200",
            },
        )
        
        # Create RDS instance
        database = rds.DatabaseInstance(
            self,
            "DemoDatabase",
            engine=rds.DatabaseInstanceEngine.mysql(
                version=rds.MysqlEngineVersion.VER_8_0
            ),
            instance_type=ec2.InstanceType.of(
                ec2.InstanceClass.BURSTABLE3,
                ec2.InstanceSize.MICRO,
            ),
            credentials=rds.Credentials.from_generated_secret(
                username="admin",
                secret_name="quicksight-demo-db-credentials",
            ),
            allocated_storage=20,
            storage_type=rds.StorageType.GP3,
            storage_encrypted=True,
            vpc=self.vpc,
            subnet_group=subnet_group,
            security_groups=[db_security_group],
            parameter_group=parameter_group,
            backup_retention=Duration.days(7),
            deletion_protection=False,
            delete_automated_backups=True,
            removal_policy=RemovalPolicy.DESTROY,
            cloudwatch_logs_exports=["error", "general", "slowquery"],
            monitoring_interval=Duration.minutes(1),
            enable_performance_insights=True,
            performance_insight_retention=rds.PerformanceInsightRetention.DEFAULT,
        )
        
        # Tag database for identification
        cdk.Tags.of(database).add("Purpose", "QuickSight-Demo")
        cdk.Tags.of(database).add("DataType", "Operational")
        
        return database

    def _create_quicksight_iam_role(self) -> iam.Role:
        """
        Create IAM role for QuickSight service access.
        
        Returns:
            IAM role with necessary permissions for QuickSight
        """
        # Create trust policy for QuickSight
        quicksight_principal = iam.ServicePrincipal("quicksight.amazonaws.com")
        
        # Create IAM role for QuickSight
        role = iam.Role(
            self,
            "QuickSightServiceRole",
            assumed_by=quicksight_principal,
            role_name=f"QuickSight-S3-Role-{self.region}",
            description="IAM role for QuickSight to access S3 and RDS resources",
            max_session_duration=Duration.hours(12),
        )
        
        # Add S3 access policy
        s3_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "s3:GetObject",
                "s3:GetObjectVersion",
                "s3:ListBucket",
                "s3:GetBucketLocation",
            ],
            resources=[
                self.data_bucket.bucket_arn,
                f"{self.data_bucket.bucket_arn}/*",
            ],
        )
        
        # Add RDS access policy
        rds_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "rds:DescribeDBInstances",
                "rds:DescribeDBClusters",
                "rds:DescribeDBSubnetGroups",
                "rds:DescribeDBParameterGroups",
                "rds:DescribeDBClusterParameterGroups",
            ],
            resources=["*"],
        )
        
        # Add VPC access for RDS connectivity
        vpc_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "ec2:CreateNetworkInterface",
                "ec2:DeleteNetworkInterface",
                "ec2:DescribeNetworkInterfaces",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ec2:DescribeVpcs",
            ],
            resources=["*"],
        )
        
        # Add Secrets Manager access for RDS credentials
        secrets_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
            ],
            resources=[f"arn:aws:secretsmanager:{self.region}:{self.account}:secret:quicksight-demo-db-credentials*"],
        )
        
        # Attach policies to role
        role.add_to_policy(s3_policy)
        role.add_to_policy(rds_policy)
        role.add_to_policy(vpc_policy)
        role.add_to_policy(secrets_policy)
        
        # Tag role for identification
        cdk.Tags.of(role).add("Purpose", "QuickSight-Access")
        cdk.Tags.of(role).add("Service", "QuickSight")
        
        return role

    def _create_quicksight_resources(self) -> None:
        """Create QuickSight data sources, datasets, and dashboards."""
        # Create S3 data source
        s3_data_source = quicksight.CfnDataSource(
            self,
            "S3DataSource",
            aws_account_id=self.account,
            data_source_id="sales-data-s3",
            name="Sales Data S3",
            type="S3",
            data_source_parameters=quicksight.CfnDataSource.DataSourceParametersProperty(
                s3_parameters=quicksight.CfnDataSource.S3ParametersProperty(
                    manifest_file_location=quicksight.CfnDataSource.ManifestFileLocationProperty(
                        bucket=self.data_bucket.bucket_name,
                        key="sales/sales_data.csv",
                    )
                )
            ),
            permissions=[
                quicksight.CfnDataSource.ResourcePermissionProperty(
                    principal=self.quicksight_user_arn,
                    actions=[
                        "quicksight:DescribeDataSource",
                        "quicksight:DescribeDataSourcePermissions",
                        "quicksight:PassDataSource",
                    ],
                )
            ],
        )
        
        # Create dataset from S3 data source
        dataset = quicksight.CfnDataSet(
            self,
            "SalesDataset",
            aws_account_id=self.account,
            data_set_id="sales-dataset",
            name="Sales Analytics Dataset",
            import_mode="SPICE",
            physical_table_map={
                "sales_table": quicksight.CfnDataSet.PhysicalTableProperty(
                    s3_source=quicksight.CfnDataSet.S3SourceProperty(
                        data_source_arn=s3_data_source.attr_arn,
                        input_columns=[
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="date",
                                type="STRING",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="region",
                                type="STRING",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="product",
                                type="STRING",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="sales_amount",
                                type="DECIMAL",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="quantity",
                                type="INTEGER",
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="customer_segment",
                                type="STRING",
                            ),
                        ],
                    )
                )
            },
            logical_table_map={
                "sales_logical": quicksight.CfnDataSet.LogicalTableProperty(
                    alias="Sales Data",
                    source=quicksight.CfnDataSet.LogicalTableSourceProperty(
                        physical_table_id="sales_table"
                    ),
                    data_transforms=[
                        quicksight.CfnDataSet.TransformOperationProperty(
                            cast_column_type_operation=quicksight.CfnDataSet.CastColumnTypeOperationProperty(
                                column_name="date",
                                new_column_type="DATETIME",
                                format="yyyy-MM-dd",
                            )
                        )
                    ],
                )
            },
            permissions=[
                quicksight.CfnDataSet.ResourcePermissionProperty(
                    principal=self.quicksight_user_arn,
                    actions=[
                        "quicksight:DescribeDataSet",
                        "quicksight:DescribeDataSetPermissions",
                        "quicksight:PassDataSet",
                        "quicksight:DescribeIngestion",
                        "quicksight:ListIngestions",
                    ],
                )
            ],
        )
        
        # Create analysis
        analysis = quicksight.CfnAnalysis(
            self,
            "SalesAnalysis",
            aws_account_id=self.account,
            analysis_id="sales-analysis",
            name="Sales Performance Analysis",
            definition=quicksight.CfnAnalysis.AnalysisDefinitionProperty(
                data_set_identifier_declarations=[
                    quicksight.CfnAnalysis.DataSetIdentifierDeclarationProperty(
                        data_set_arn=dataset.attr_arn,
                        identifier="sales_data",
                    )
                ],
                sheets=[
                    quicksight.CfnAnalysis.SheetDefinitionProperty(
                        sheet_id="sales_overview",
                        name="Sales Overview",
                        visuals=[
                            quicksight.CfnAnalysis.VisualProperty(
                                bar_chart_visual=quicksight.CfnAnalysis.BarChartVisualProperty(
                                    visual_id="sales_by_region",
                                    title=quicksight.CfnAnalysis.VisualTitleLabelOptionsProperty(
                                        text="Sales by Region"
                                    ),
                                )
                            )
                        ],
                    )
                ],
            ),
            permissions=[
                quicksight.CfnAnalysis.ResourcePermissionProperty(
                    principal=self.quicksight_user_arn,
                    actions=[
                        "quicksight:RestoreAnalysis",
                        "quicksight:UpdateAnalysisPermissions",
                        "quicksight:DeleteAnalysis",
                        "quicksight:DescribeAnalysisPermissions",
                        "quicksight:QueryAnalysis",
                        "quicksight:DescribeAnalysis",
                        "quicksight:UpdateAnalysis",
                    ],
                )
            ],
        )
        
        # Create dashboard
        dashboard = quicksight.CfnDashboard(
            self,
            "SalesDashboard",
            aws_account_id=self.account,
            dashboard_id="sales-dashboard",
            name="Sales Performance Dashboard",
            definition=quicksight.CfnDashboard.DashboardVersionDefinitionProperty(
                data_set_identifier_declarations=[
                    quicksight.CfnDashboard.DataSetIdentifierDeclarationProperty(
                        data_set_arn=dataset.attr_arn,
                        identifier="sales_data",
                    )
                ],
                sheets=[
                    quicksight.CfnDashboard.SheetDefinitionProperty(
                        sheet_id="dashboard_sheet",
                        name="Sales Dashboard",
                        visuals=[
                            quicksight.CfnDashboard.VisualProperty(
                                bar_chart_visual=quicksight.CfnDashboard.BarChartVisualProperty(
                                    visual_id="sales_by_region_chart",
                                    title=quicksight.CfnDashboard.VisualTitleLabelOptionsProperty(
                                        text="Sales by Region"
                                    ),
                                )
                            ),
                            quicksight.CfnDashboard.VisualProperty(
                                pie_chart_visual=quicksight.CfnDashboard.PieChartVisualProperty(
                                    visual_id="sales_by_product_pie",
                                    title=quicksight.CfnDashboard.VisualTitleLabelOptionsProperty(
                                        text="Sales Distribution by Product"
                                    ),
                                )
                            ),
                        ],
                    )
                ],
            ),
            permissions=[
                quicksight.CfnDashboard.ResourcePermissionProperty(
                    principal=self.quicksight_user_arn,
                    actions=[
                        "quicksight:DescribeDashboard",
                        "quicksight:ListDashboardVersions",
                        "quicksight:UpdateDashboardPermissions",
                        "quicksight:QueryDashboard",
                        "quicksight:UpdateDashboard",
                        "quicksight:DeleteDashboard",
                        "quicksight:DescribeDashboardPermissions",
                        "quicksight:UpdateDashboardPublishedVersion",
                    ],
                )
            ],
            dashboard_publish_options=quicksight.CfnDashboard.DashboardPublishOptionsProperty(
                ad_hoc_filtering_option=quicksight.CfnDashboard.AdHocFilteringOptionProperty(
                    availability_status="ENABLED"
                ),
                export_to_csv_option=quicksight.CfnDashboard.ExportToCSVOptionProperty(
                    availability_status="ENABLED"
                ),
                sheet_controls_option=quicksight.CfnDashboard.SheetControlsOptionProperty(
                    visibility_state="EXPANDED"
                ),
            ),
        )
        
        # Store references for outputs
        self.s3_data_source = s3_data_source
        self.dataset = dataset
        self.analysis = analysis
        self.dashboard = dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        # S3 bucket outputs
        CfnOutput(
            self,
            "DataLakeBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket containing sample sales data",
            export_name=f"{self.stack_name}-DataLakeBucket",
        )
        
        CfnOutput(
            self,
            "DataLakeBucketArn",
            value=self.data_bucket.bucket_arn,
            description="ARN of the S3 data lake bucket",
            export_name=f"{self.stack_name}-DataLakeBucketArn",
        )
        
        # RDS outputs
        CfnOutput(
            self,
            "DatabaseEndpoint",
            value=self.database.instance_endpoint.hostname,
            description="RDS database endpoint for QuickSight connectivity",
            export_name=f"{self.stack_name}-DatabaseEndpoint",
        )
        
        CfnOutput(
            self,
            "DatabasePort",
            value=str(self.database.instance_endpoint.port),
            description="RDS database port",
            export_name=f"{self.stack_name}-DatabasePort",
        )
        
        # IAM role outputs
        CfnOutput(
            self,
            "QuickSightRoleArn",
            value=self.quicksight_role.role_arn,
            description="ARN of the IAM role for QuickSight service access",
            export_name=f"{self.stack_name}-QuickSightRoleArn",
        )
        
        # QuickSight resource outputs
        CfnOutput(
            self,
            "QuickSightDataSourceId",
            value=self.s3_data_source.data_source_id,
            description="ID of the QuickSight S3 data source",
            export_name=f"{self.stack_name}-DataSourceId",
        )
        
        CfnOutput(
            self,
            "QuickSightDatasetId",
            value=self.dataset.data_set_id,
            description="ID of the QuickSight dataset",
            export_name=f"{self.stack_name}-DatasetId",
        )
        
        CfnOutput(
            self,
            "QuickSightAnalysisId",
            value=self.analysis.analysis_id,
            description="ID of the QuickSight analysis",
            export_name=f"{self.stack_name}-AnalysisId",
        )
        
        CfnOutput(
            self,
            "QuickSightDashboardId",
            value=self.dashboard.dashboard_id,
            description="ID of the QuickSight dashboard",
            export_name=f"{self.stack_name}-DashboardId",
        )
        
        # Console URLs for easy access
        CfnOutput(
            self,
            "QuickSightConsoleUrl",
            value=f"https://quicksight.aws.amazon.com/sn/dashboards/{self.dashboard.dashboard_id}",
            description="URL to access the QuickSight dashboard in AWS Console",
        )
        
        CfnOutput(
            self,
            "S3ConsoleUrl",
            value=f"https://s3.console.aws.amazon.com/s3/buckets/{self.data_bucket.bucket_name}",
            description="URL to access the S3 data lake bucket in AWS Console",
        )


class QuickSightBIApp(App):
    """CDK application for QuickSight Business Intelligence solution."""
    
    def __init__(self) -> None:
        """Initialize the CDK application."""
        super().__init__()
        
        # Get configuration from environment or use defaults
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        quicksight_user_arn = os.environ.get("QUICKSIGHT_USER_ARN")
        
        # Create environment
        env = Environment(account=account, region=region)
        
        # Create the main stack
        QuickSightBIStack(
            self,
            "QuickSightBIStack",
            env=env,
            quicksight_user_arn=quicksight_user_arn,
            description="Infrastructure for QuickSight Business Intelligence Solutions (uksb-1tupboc57)",
            stack_name="quicksight-bi-solution",
        )
        
        # Add global tags
        cdk.Tags.of(self).add("Project", "QuickSight-BI-Demo")
        cdk.Tags.of(self).add("Environment", "Demo")
        cdk.Tags.of(self).add("Owner", "CDK-Demo")
        cdk.Tags.of(self).add("CostCenter", "Engineering")


def main() -> None:
    """Main application entry point."""
    app = QuickSightBIApp()
    app.synth()


if __name__ == "__main__":
    main()