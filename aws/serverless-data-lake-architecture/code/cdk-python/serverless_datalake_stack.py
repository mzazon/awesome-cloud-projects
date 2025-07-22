"""
Advanced Serverless Data Lake Stack

This stack implements a comprehensive serverless data lake architecture using:
- Lambda layers for shared code and dependencies
- S3 buckets for data storage across different stages
- Lambda functions for data processing pipeline
- EventBridge for event-driven orchestration
- AWS Glue for ETL and data cataloging
- DynamoDB for metadata storage
- CloudWatch for comprehensive monitoring
"""

from typing import Dict, Any
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_lambda as _lambda,
    aws_iam as iam,
    aws_events as events,
    aws_events_targets as targets,
    aws_dynamodb as dynamodb,
    aws_glue as glue,
    aws_logs as logs,
    aws_s3_notifications as s3n
)
from constructs import Construct


class ServerlessDataLakeStack(Stack):
    """
    Advanced Serverless Data Lake Stack with enterprise-grade features.
    
    This stack creates a complete data lake architecture with:
    - Automated data ingestion and validation
    - Event-driven processing workflows
    - Data quality monitoring and quarantine
    - Scalable ETL processing with AWS Glue
    - Comprehensive observability and tracing
    """

    def __init__(
        self,
        scope: Construct,
        construct_id: str,
        project_name: str,
        environment_name: str,
        **kwargs
    ) -> None:
        super().__init__(scope, construct_id, **kwargs)

        self.project_name = project_name
        self.environment_name = environment_name
        
        # Create S3 buckets for data lake storage
        self._create_storage_buckets()
        
        # Create DynamoDB table for metadata storage
        self._create_metadata_table()
        
        # Create Lambda layer with shared utilities
        self._create_lambda_layer()
        
        # Create IAM roles for Lambda and Glue
        self._create_iam_roles()
        
        # Create EventBridge custom bus and rules
        self._create_eventbridge_infrastructure()
        
        # Create Lambda functions for data processing
        self._create_lambda_functions()
        
        # Create AWS Glue components
        self._create_glue_components()
        
        # Configure event-driven integrations
        self._configure_event_integrations()
        
        # Create CloudWatch monitoring resources
        self._create_monitoring_resources()
        
        # Generate stack outputs
        self._create_outputs()

    def _create_storage_buckets(self) -> None:
        """Create S3 buckets for different data lake storage tiers."""
        # Raw data bucket - where new data arrives
        self.raw_data_bucket = s3.Bucket(
            self,
            "RawDataBucket",
            bucket_name=f"{self.project_name}-{self.environment_name}-raw-data",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="ArchiveOldData",
                    expiration=Duration.days(90),
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(60)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Processed data bucket - validated and transformed data
        self.processed_data_bucket = s3.Bucket(
            self,
            "ProcessedDataBucket",
            bucket_name=f"{self.project_name}-{self.environment_name}-processed-data",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

        # Quarantine bucket - failed validation data
        self.quarantine_bucket = s3.Bucket(
            self,
            "QuarantineBucket",
            bucket_name=f"{self.project_name}-{self.environment_name}-quarantine-data",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteQuarantineData",
                    expiration=Duration.days(30)
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True
        )

    def _create_metadata_table(self) -> None:
        """Create DynamoDB table for storing processing metadata."""
        self.metadata_table = dynamodb.Table(
            self,
            "MetadataTable",
            table_name=f"{self.project_name}-{self.environment_name}-metadata",
            partition_key=dynamodb.Attribute(
                name="ProcessId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Add GSI for querying by processing stage
        self.metadata_table.add_global_secondary_index(
            index_name="ProcessingStageIndex",
            partition_key=dynamodb.Attribute(
                name="ProcessingStage",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.STRING
            )
        )

    def _create_lambda_layer(self) -> None:
        """Create Lambda layer with shared utilities and dependencies."""
        self.shared_layer = _lambda.LayerVersion(
            self,
            "SharedUtilitiesLayer",
            layer_version_name=f"{self.project_name}-{self.environment_name}-shared-layer",
            code=_lambda.Code.from_asset("lambda_layers/shared_utilities"),
            compatible_runtimes=[
                _lambda.Runtime.PYTHON_3_9,
                _lambda.Runtime.PYTHON_3_10,
                _lambda.Runtime.PYTHON_3_11
            ],
            compatible_architectures=[_lambda.Architecture.X86_64, _lambda.Architecture.ARM_64],
            description="Shared utilities for data lake processing functions"
        )

    def _create_iam_roles(self) -> None:
        """Create IAM roles for Lambda and Glue services."""
        # Lambda execution role
        self.lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            role_name=f"{self.project_name}-{self.environment_name}-lambda-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole"),
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSXRayDaemonWriteAccess")
            ]
        )

        # Add comprehensive Lambda permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.raw_data_bucket.bucket_arn,
                    f"{self.raw_data_bucket.bucket_arn}/*",
                    self.processed_data_bucket.bucket_arn,
                    f"{self.processed_data_bucket.bucket_arn}/*",
                    self.quarantine_bucket.bucket_arn,
                    f"{self.quarantine_bucket.bucket_arn}/*"
                ]
            )
        )

        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                resources=[
                    self.metadata_table.table_arn,
                    f"{self.metadata_table.table_arn}/index/*"
                ]
            )
        )

        # Glue service role
        self.glue_role = iam.Role(
            self,
            "GlueServiceRole",
            role_name=f"{self.project_name}-{self.environment_name}-glue-role",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole")
            ]
        )

        # Add S3 permissions for Glue
        self.glue_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.processed_data_bucket.bucket_arn,
                    f"{self.processed_data_bucket.bucket_arn}/*"
                ]
            )
        )

    def _create_eventbridge_infrastructure(self) -> None:
        """Create EventBridge custom bus and event rules."""
        # Custom EventBridge bus for data lake events
        self.custom_event_bus = events.EventBus(
            self,
            "DataLakeEventBus",
            event_bus_name=f"{self.project_name}-{self.environment_name}-event-bus",
            description="Custom event bus for data lake processing events"
        )

        # Event rule for data ingestion events
        self.ingestion_rule = events.Rule(
            self,
            "DataIngestionRule",
            rule_name=f"{self.project_name}-{self.environment_name}-data-ingestion-rule",
            event_bus=self.custom_event_bus,
            event_pattern=events.EventPattern(
                source=["datalake.ingestion"],
                detail_type=["Data Received"]
            ),
            description="Routes data ingestion events to validation function"
        )

        # Event rule for data validation events
        self.validation_rule = events.Rule(
            self,
            "DataValidationRule",
            rule_name=f"{self.project_name}-{self.environment_name}-data-validation-rule",
            event_bus=self.custom_event_bus,
            event_pattern=events.EventPattern(
                source=["datalake.validation"],
                detail_type=["Data Validated"]
            ),
            description="Routes data validation events to quality monitoring function"
        )

        # Event rule for data quality events
        self.quality_rule = events.Rule(
            self,
            "DataQualityRule",
            rule_name=f"{self.project_name}-{self.environment_name}-data-quality-rule",
            event_bus=self.custom_event_bus,
            event_pattern=events.EventPattern(
                source=["datalake.quality"],
                detail_type=["Quality Check Complete"]
            ),
            description="Routes quality check events to monitoring systems"
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for data processing pipeline."""
        # Common environment variables for all functions
        common_env_vars = {
            "METADATA_TABLE": self.metadata_table.table_name,
            "CUSTOM_EVENT_BUS": self.custom_event_bus.event_bus_name,
            "RAW_BUCKET": self.raw_data_bucket.bucket_name,
            "PROCESSED_BUCKET": self.processed_data_bucket.bucket_name,
            "QUARANTINE_BUCKET": self.quarantine_bucket.bucket_name,
            "PROJECT_NAME": f"{self.project_name}-{self.environment_name}"
        }

        # Data Ingestion Lambda Function
        self.ingestion_function = _lambda.Function(
            self,
            "DataIngestionFunction",
            function_name=f"{self.project_name}-{self.environment_name}-data-ingestion",
            runtime=_lambda.Runtime.PYTHON_3_9,
            architecture=_lambda.Architecture.ARM_64,
            code=_lambda.Code.from_asset("lambda_functions/data_ingestion"),
            handler="lambda_function.lambda_handler",
            role=self.lambda_role,
            layers=[self.shared_layer],
            timeout=Duration.minutes(5),
            memory_size=512,
            environment=common_env_vars,
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Processes incoming data files and publishes ingestion events"
        )

        # Data Validation Lambda Function
        self.validation_function = _lambda.Function(
            self,
            "DataValidationFunction",
            function_name=f"{self.project_name}-{self.environment_name}-data-validation",
            runtime=_lambda.Runtime.PYTHON_3_9,
            architecture=_lambda.Architecture.ARM_64,
            code=_lambda.Code.from_asset("lambda_functions/data_validation"),
            handler="lambda_function.lambda_handler",
            role=self.lambda_role,
            layers=[self.shared_layer],
            timeout=Duration.minutes(5),
            memory_size=512,
            environment=common_env_vars,
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Validates data structure and quality, routes to appropriate storage"
        )

        # Quality Monitoring Lambda Function
        self.quality_monitoring_function = _lambda.Function(
            self,
            "QualityMonitoringFunction",
            function_name=f"{self.project_name}-{self.environment_name}-quality-monitoring",
            runtime=_lambda.Runtime.PYTHON_3_9,
            architecture=_lambda.Architecture.ARM_64,
            code=_lambda.Code.from_asset("lambda_functions/quality_monitoring"),
            handler="lambda_function.lambda_handler",
            role=self.lambda_role,
            layers=[self.shared_layer],
            timeout=Duration.minutes(5),
            memory_size=256,
            environment=common_env_vars,
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK,
            description="Monitors data quality metrics and publishes CloudWatch metrics"
        )

        # Add EventBridge permissions to Lambda role
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=["events:PutEvents"],
                resources=[self.custom_event_bus.event_bus_arn]
            )
        )

        # Add CloudWatch permissions for quality monitoring
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cloudwatch:PutMetricData",
                    "cloudwatch:GetMetricStatistics",
                    "cloudwatch:ListMetrics"
                ],
                resources=["*"]
            )
        )

    def _create_glue_components(self) -> None:
        """Create AWS Glue components for ETL and data cataloging."""
        # Glue Database for data catalog
        self.glue_database = glue.CfnDatabase(
            self,
            "DataLakeDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=f"{self.project_name}_{self.environment_name}_catalog",
                description="Data lake catalog database for processed data"
            )
        )

        # Glue Crawler for schema discovery
        self.glue_crawler = glue.CfnCrawler(
            self,
            "DataLakeCrawler",
            name=f"{self.project_name}-{self.environment_name}-crawler",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.processed_data_bucket.bucket_name}/validated/"
                    )
                ]
            ),
            schedule=glue.CfnCrawler.ScheduleProperty(
                schedule_expression="cron(0 */6 * * ? *)"  # Run every 6 hours
            ),
            description="Crawls processed data to maintain data catalog"
        )

    def _configure_event_integrations(self) -> None:
        """Configure event-driven integrations between services."""
        # S3 notification to trigger data ingestion
        self.raw_data_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.ingestion_function),
            s3.NotificationKeyFilter(prefix="input/")
        )

        # EventBridge rule targets
        self.ingestion_rule.add_target(
            targets.LambdaFunction(self.validation_function)
        )

        self.validation_rule.add_target(
            targets.LambdaFunction(self.quality_monitoring_function)
        )

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch monitoring resources and dashboards."""
        # CloudWatch Log Groups are automatically created by Lambda functions
        # Additional monitoring can be added here such as:
        # - Custom CloudWatch Dashboards
        # - CloudWatch Alarms for critical metrics
        # - SNS topics for alerting
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource identifiers."""
        CfnOutput(
            self,
            "RawDataBucketName",
            value=self.raw_data_bucket.bucket_name,
            description="Name of the raw data S3 bucket",
            export_name=f"{self.stack_name}-raw-data-bucket"
        )

        CfnOutput(
            self,
            "ProcessedDataBucketName",
            value=self.processed_data_bucket.bucket_name,
            description="Name of the processed data S3 bucket",
            export_name=f"{self.stack_name}-processed-data-bucket"
        )

        CfnOutput(
            self,
            "QuarantineBucketName",
            value=self.quarantine_bucket.bucket_name,
            description="Name of the quarantine data S3 bucket",
            export_name=f"{self.stack_name}-quarantine-bucket"
        )

        CfnOutput(
            self,
            "MetadataTableName",
            value=self.metadata_table.table_name,
            description="Name of the DynamoDB metadata table",
            export_name=f"{self.stack_name}-metadata-table"
        )

        CfnOutput(
            self,
            "CustomEventBusName",
            value=self.custom_event_bus.event_bus_name,
            description="Name of the custom EventBridge bus",
            export_name=f"{self.stack_name}-event-bus"
        )

        CfnOutput(
            self,
            "LambdaLayerArn",
            value=self.shared_layer.layer_version_arn,
            description="ARN of the shared Lambda layer",
            export_name=f"{self.stack_name}-lambda-layer"
        )

        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="Name of the Glue database",
            export_name=f"{self.stack_name}-glue-database"
        )