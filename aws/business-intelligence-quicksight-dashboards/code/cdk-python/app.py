#!/usr/bin/env python3
"""
CDK Python Application for Amazon QuickSight Business Intelligence Dashboards

This CDK application deploys a complete business intelligence solution using Amazon QuickSight
including S3 data sources, IAM roles, datasets, analyses, and dashboards for interactive
data visualization and self-service analytics.

Author: AWS CDK Generator
Version: 1.0
"""

import os
from typing import Dict, List, Optional

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    aws_s3 as s3,
    aws_s3_deployment as s3_deployment,
    aws_iam as iam,
    aws_quicksight as quicksight,
    CfnOutput,
)
from constructs import Construct


class QuickSightBusinessIntelligenceStack(Stack):
    """
    CDK Stack for deploying Amazon QuickSight Business Intelligence solution.
    
    This stack creates:
    - S3 bucket with sample sales data
    - IAM role for QuickSight data access
    - QuickSight data source connected to S3
    - QuickSight dataset with proper schema
    - QuickSight analysis with visualizations
    - QuickSight dashboard for business users
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        quicksight_user_arn: Optional[str] = None,
        **kwargs
    ) -> None:
        """
        Initialize the QuickSight Business Intelligence Stack.
        
        Args:
            scope: The scope in which to define this construct
            construct_id: The scoped construct ID
            quicksight_user_arn: ARN of the QuickSight user (required for permissions)
            **kwargs: Additional arguments passed to Stack
        """
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        self.random_suffix = self.node.try_get_context("random_suffix") or "demo"
        
        # QuickSight user ARN (must be provided for permissions)
        self.quicksight_user_arn = (
            quicksight_user_arn or 
            self.node.try_get_context("quicksight_user_arn") or
            f"arn:aws:quicksight:{self.region}:{self.account}:user/default/admin"
        )

        # Create S3 bucket for data storage
        self.data_bucket = self._create_data_bucket()
        
        # Deploy sample data to S3
        self._deploy_sample_data()
        
        # Create IAM role for QuickSight
        self.quicksight_role = self._create_quicksight_iam_role()
        
        # Create QuickSight data source
        self.data_source = self._create_quicksight_data_source()
        
        # Create QuickSight dataset
        self.dataset = self._create_quicksight_dataset()
        
        # Create QuickSight analysis
        self.analysis = self._create_quicksight_analysis()
        
        # Create QuickSight dashboard
        self.dashboard = self._create_quicksight_dashboard()
        
        # Create outputs
        self._create_outputs()

    def _create_data_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for storing analytics data.
        
        Returns:
            S3 bucket configured for QuickSight access
        """
        bucket = s3.Bucket(
            self,
            "DataBucket",
            bucket_name=f"quicksight-data-{self.random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )
        
        # Add CORS configuration for QuickSight access
        bucket.add_cors_rule(
            allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.HEAD],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )
        
        return bucket

    def _deploy_sample_data(self) -> None:
        """Deploy sample sales data to S3 bucket for demonstration."""
        # Create sample CSV data inline
        sample_data_content = """date,region,product,sales_amount,quantity
2024-01-01,North,Widget A,1200,10
2024-01-01,South,Widget B,800,8
2024-01-02,North,Widget A,1400,12
2024-01-02,South,Widget B,900,9
2024-01-03,East,Widget C,1100,11
2024-01-03,West,Widget A,1300,13
2024-01-04,North,Widget B,1600,16
2024-01-04,South,Widget C,1000,10
2024-01-05,East,Widget A,1500,15
2024-01-05,West,Widget B,1100,11
2024-01-06,North,Widget C,1800,18
2024-01-06,South,Widget A,1200,12
2024-01-07,East,Widget B,1400,14
2024-01-07,West,Widget C,1600,16
2024-01-08,North,Widget A,2000,20
2024-01-08,South,Widget B,1300,13
2024-01-09,East,Widget C,1700,17
2024-01-09,West,Widget A,1500,15
2024-01-10,North,Widget B,1900,19
2024-01-10,South,Widget C,1400,14"""

        # Deploy the sample data using s3_deployment
        s3_deployment.BucketDeployment(
            self,
            "SampleDataDeployment",
            sources=[
                s3_deployment.Source.data(
                    "data/sales_data.csv",
                    sample_data_content
                )
            ],
            destination_bucket=self.data_bucket,
            destination_key_prefix="data/"
        )

    def _create_quicksight_iam_role(self) -> iam.Role:
        """
        Create IAM role for QuickSight to access data sources.
        
        Returns:
            IAM role with appropriate permissions for QuickSight
        """
        role = iam.Role(
            self,
            "QuickSightDataSourceRole",
            role_name=f"QuickSight-DataSource-Role-{self.random_suffix}",
            assumed_by=iam.ServicePrincipal("quicksight.amazonaws.com"),
            description="Role for QuickSight to access data sources securely",
            inline_policies={
                "S3DataAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "s3:GetObject",
                                "s3:GetObjectVersion",
                                "s3:ListBucket",
                                "s3:GetBucketLocation"
                            ],
                            resources=[
                                self.data_bucket.bucket_arn,
                                f"{self.data_bucket.bucket_arn}/*"
                            ]
                        )
                    ]
                )
            }
        )
        
        return role

    def _create_quicksight_data_source(self) -> quicksight.CfnDataSource:
        """
        Create QuickSight data source connected to S3.
        
        Returns:
            QuickSight data source for S3 analytics
        """
        data_source = quicksight.CfnDataSource(
            self,
            "S3DataSource",
            aws_account_id=self.account,
            data_source_id=f"s3-sales-data-{self.random_suffix}",
            name="Sales Data S3 Source",
            type="S3",
            data_source_parameters=quicksight.CfnDataSource.DataSourceParametersProperty(
                s3_parameters=quicksight.CfnDataSource.S3ParametersProperty(
                    manifest_file_location=quicksight.CfnDataSource.ManifestFileLocationProperty(
                        bucket=self.data_bucket.bucket_name,
                        key="data/sales_data.csv"
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
                        "quicksight:UpdateDataSource",
                        "quicksight:DeleteDataSource",
                        "quicksight:UpdateDataSourcePermissions"
                    ]
                )
            ]
        )
        
        return data_source

    def _create_quicksight_dataset(self) -> quicksight.CfnDataSet:
        """
        Create QuickSight dataset with proper schema mapping.
        
        Returns:
            QuickSight dataset with sales data schema
        """
        dataset = quicksight.CfnDataSet(
            self,
            "SalesDataset",
            aws_account_id=self.account,
            data_set_id=f"sales-dataset-{self.random_suffix}",
            name="Sales Dataset",
            import_mode="SPICE",
            physical_table_map={
                "SalesTable": quicksight.CfnDataSet.PhysicalTableProperty(
                    s3_source=quicksight.CfnDataSet.S3SourceProperty(
                        data_source_arn=f"arn:aws:quicksight:{self.region}:{self.account}:datasource/{self.data_source.data_source_id}",
                        upload_settings=quicksight.CfnDataSet.UploadSettingsProperty(
                            format="CSV",
                            start_from_row=1,
                            contains_header=True,
                            delimiter=","
                        ),
                        input_columns=[
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="date",
                                type="DATETIME"
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="region",
                                type="STRING"
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="product",
                                type="STRING"
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="sales_amount",
                                type="DECIMAL"
                            ),
                            quicksight.CfnDataSet.InputColumnProperty(
                                name="quantity",
                                type="INTEGER"
                            )
                        ]
                    )
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
                        "quicksight:UpdateDataSet",
                        "quicksight:DeleteDataSet",
                        "quicksight:CreateIngestion",
                        "quicksight:CancelIngestion",
                        "quicksight:UpdateDataSetPermissions"
                    ]
                )
            ]
        )
        
        # Add dependency on data source
        dataset.add_dependency(self.data_source)
        
        return dataset

    def _create_quicksight_analysis(self) -> quicksight.CfnAnalysis:
        """
        Create QuickSight analysis with business visualizations.
        
        Returns:
            QuickSight analysis with sales insights
        """
        analysis = quicksight.CfnAnalysis(
            self,
            "SalesAnalysis",
            aws_account_id=self.account,
            analysis_id=f"sales-analysis-{self.random_suffix}",
            name="Sales Analysis",
            definition=quicksight.CfnAnalysis.AnalysisDefinitionProperty(
                data_set_identifier_declarations=[
                    quicksight.CfnAnalysis.DataSetIdentifierDeclarationProperty(
                        data_set_arn=f"arn:aws:quicksight:{self.region}:{self.account}:dataset/{self.dataset.data_set_id}",
                        identifier="SalesDataSet"
                    )
                ],
                sheets=[
                    quicksight.CfnAnalysis.SheetDefinitionProperty(
                        sheet_id="sales-overview",
                        name="Sales Overview",
                        visuals=[
                            # Sales by Region Bar Chart
                            quicksight.CfnAnalysis.VisualProperty(
                                bar_chart_visual=quicksight.CfnAnalysis.BarChartVisualProperty(
                                    visual_id="sales-by-region",
                                    title=quicksight.CfnAnalysis.VisualTitleLabelOptionsProperty(
                                        visibility="VISIBLE",
                                        format_text=quicksight.CfnAnalysis.ShortFormatTextProperty(
                                            plain_text="Sales by Region"
                                        )
                                    ),
                                    chart_configuration=quicksight.CfnAnalysis.BarChartConfigurationProperty(
                                        field_wells=quicksight.CfnAnalysis.BarChartFieldWellsProperty(
                                            bar_chart_aggregated_field_wells=quicksight.CfnAnalysis.BarChartAggregatedFieldWellsProperty(
                                                category=[
                                                    quicksight.CfnAnalysis.DimensionFieldProperty(
                                                        categorical_dimension_field=quicksight.CfnAnalysis.CategoricalDimensionFieldProperty(
                                                            field_id="region",
                                                            column=quicksight.CfnAnalysis.ColumnIdentifierProperty(
                                                                data_set_identifier="SalesDataSet",
                                                                column_name="region"
                                                            )
                                                        )
                                                    )
                                                ],
                                                values=[
                                                    quicksight.CfnAnalysis.MeasureFieldProperty(
                                                        numerical_measure_field=quicksight.CfnAnalysis.NumericalMeasureFieldProperty(
                                                            field_id="sales_amount",
                                                            column=quicksight.CfnAnalysis.ColumnIdentifierProperty(
                                                                data_set_identifier="SalesDataSet",
                                                                column_name="sales_amount"
                                                            ),
                                                            aggregation_function=quicksight.CfnAnalysis.NumericalAggregationFunctionProperty(
                                                                simple_numerical_aggregation="SUM"
                                                            )
                                                        )
                                                    )
                                                ]
                                            )
                                        )
                                    )
                                )
                            ),
                            # Sales by Product Pie Chart
                            quicksight.CfnAnalysis.VisualProperty(
                                pie_chart_visual=quicksight.CfnAnalysis.PieChartVisualProperty(
                                    visual_id="sales-by-product",
                                    title=quicksight.CfnAnalysis.VisualTitleLabelOptionsProperty(
                                        visibility="VISIBLE",
                                        format_text=quicksight.CfnAnalysis.ShortFormatTextProperty(
                                            plain_text="Sales by Product"
                                        )
                                    ),
                                    chart_configuration=quicksight.CfnAnalysis.PieChartConfigurationProperty(
                                        field_wells=quicksight.CfnAnalysis.PieChartFieldWellsProperty(
                                            pie_chart_aggregated_field_wells=quicksight.CfnAnalysis.PieChartAggregatedFieldWellsProperty(
                                                category=[
                                                    quicksight.CfnAnalysis.DimensionFieldProperty(
                                                        categorical_dimension_field=quicksight.CfnAnalysis.CategoricalDimensionFieldProperty(
                                                            field_id="product",
                                                            column=quicksight.CfnAnalysis.ColumnIdentifierProperty(
                                                                data_set_identifier="SalesDataSet",
                                                                column_name="product"
                                                            )
                                                        )
                                                    )
                                                ],
                                                values=[
                                                    quicksight.CfnAnalysis.MeasureFieldProperty(
                                                        numerical_measure_field=quicksight.CfnAnalysis.NumericalMeasureFieldProperty(
                                                            field_id="sales_amount_product",
                                                            column=quicksight.CfnAnalysis.ColumnIdentifierProperty(
                                                                data_set_identifier="SalesDataSet",
                                                                column_name="sales_amount"
                                                            ),
                                                            aggregation_function=quicksight.CfnAnalysis.NumericalAggregationFunctionProperty(
                                                                simple_numerical_aggregation="SUM"
                                                            )
                                                        )
                                                    )
                                                ]
                                            )
                                        )
                                    )
                                )
                            )
                        ]
                    )
                ]
            ),
            permissions=[
                quicksight.CfnAnalysis.ResourcePermissionProperty(
                    principal=self.quicksight_user_arn,
                    actions=[
                        "quicksight:RestoreAnalysis",
                        "quicksight:UpdateAnalysisPermissions",
                        "quicksight:DeleteAnalysis",
                        "quicksight:QueryAnalysis",
                        "quicksight:DescribeAnalysisPermissions",
                        "quicksight:DescribeAnalysis",
                        "quicksight:UpdateAnalysis"
                    ]
                )
            ]
        )
        
        # Add dependency on dataset
        analysis.add_dependency(self.dataset)
        
        return analysis

    def _create_quicksight_dashboard(self) -> quicksight.CfnDashboard:
        """
        Create QuickSight dashboard for business stakeholders.
        
        Returns:
            QuickSight dashboard with interactive visualizations
        """
        dashboard = quicksight.CfnDashboard(
            self,
            "SalesDashboard",
            aws_account_id=self.account,
            dashboard_id=f"sales-dashboard-{self.random_suffix}",
            name="Sales Dashboard",
            source_entity=quicksight.CfnDashboard.DashboardSourceEntityProperty(
                source_template=quicksight.CfnDashboard.DashboardSourceTemplateProperty(
                    data_set_references=[
                        quicksight.CfnDashboard.DataSetReferenceProperty(
                            data_set_arn=f"arn:aws:quicksight:{self.region}:{self.account}:dataset/{self.dataset.data_set_id}",
                            data_set_placeholder="SalesDataSet"
                        )
                    ],
                    arn=f"arn:aws:quicksight:{self.region}:{self.account}:analysis/{self.analysis.analysis_id}"
                )
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
                        "quicksight:UpdateDashboardPublishedVersion"
                    ]
                )
            ]
        )
        
        # Add dependency on analysis
        dashboard.add_dependency(self.analysis)
        
        return dashboard

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for the deployed resources."""
        CfnOutput(
            self,
            "DataBucketName",
            value=self.data_bucket.bucket_name,
            description="Name of the S3 bucket containing sales data"
        )
        
        CfnOutput(
            self,
            "QuickSightRoleArn",
            value=self.quicksight_role.role_arn,
            description="ARN of the IAM role for QuickSight data access"
        )
        
        CfnOutput(
            self,
            "DataSourceId",
            value=self.data_source.data_source_id,
            description="ID of the QuickSight data source"
        )
        
        CfnOutput(
            self,
            "DatasetId",
            value=self.dataset.data_set_id,
            description="ID of the QuickSight dataset"
        )
        
        CfnOutput(
            self,
            "AnalysisId",
            value=self.analysis.analysis_id,
            description="ID of the QuickSight analysis"
        )
        
        CfnOutput(
            self,
            "DashboardId",
            value=self.dashboard.dashboard_id,
            description="ID of the QuickSight dashboard"
        )
        
        CfnOutput(
            self,
            "DashboardUrl",
            value=f"https://quicksight.aws.amazon.com/sn/dashboards/{self.dashboard.dashboard_id}",
            description="URL to access the QuickSight dashboard"
        )


app = cdk.App()

# Get configuration from context or environment
quicksight_user_arn = app.node.try_get_context("quicksight_user_arn")
random_suffix = app.node.try_get_context("random_suffix") or "demo"

# Create the stack
QuickSightBusinessIntelligenceStack(
    app,
    "QuickSightBusinessIntelligenceStack",
    quicksight_user_arn=quicksight_user_arn,
    description="Amazon QuickSight Business Intelligence Dashboard solution with S3 data source and interactive visualizations",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION")
    )
)

app.synth()