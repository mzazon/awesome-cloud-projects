#!/usr/bin/env python3
"""
Multi-Tenant SaaS Application with Amplify and Fine-Grained Authorization

This CDK application creates a comprehensive multi-tenant SaaS platform using:
- AWS Amplify for frontend hosting and CI/CD
- Amazon Cognito for tenant-aware authentication
- AWS AppSync for GraphQL API with fine-grained authorization
- Amazon DynamoDB for tenant-isolated data storage
- AWS Lambda for business logic and tenant management
- Amazon S3 for tenant-specific file storage
- Amazon CloudWatch for monitoring and analytics

The architecture supports complete tenant isolation, role-based access control,
subscription management, and enterprise-grade security features.
"""

import os
from typing import Dict, List, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Environment,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_amplify_alpha as amplify,
    aws_appsync as appsync,
    aws_cognito as cognito,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_lambda_python_alpha as lambda_python,
    aws_iam as iam,
    aws_s3 as s3,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
    aws_ssm as ssm,
    aws_secretsmanager as secrets,
)
from constructs import Construct


class MultiTenantSaaSStack(Stack):
    """
    CDK Stack for Multi-Tenant SaaS Application
    
    This stack creates a production-ready multi-tenant SaaS platform with:
    - Complete tenant isolation and data security
    - Fine-grained authorization and role-based access control
    - Scalable serverless architecture
    - Comprehensive monitoring and analytics
    - Enterprise-grade security features
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Application configuration
        self.app_name = "multitenant-saas"
        self.stage = kwargs.get('stage', 'dev')
        
        # Create core infrastructure
        self._create_storage_layer()
        self._create_authentication_layer()
        self._create_api_layer()
        self._create_business_logic_layer()
        self._create_file_storage()
        self._create_monitoring()
        self._create_frontend_hosting()
        self._create_outputs()

    def _create_storage_layer(self) -> None:
        """
        Create DynamoDB tables for tenant-isolated data storage
        
        The data model implements multiple isolation patterns:
        - Row-level security with tenant ID partitioning
        - Global secondary indexes for efficient tenant-scoped queries
        - Fine-grained access control through table-level permissions
        """
        # Tenant management table
        self.tenant_table = dynamodb.Table(
            self,
            "TenantTable",
            table_name=f"{self.app_name}-{self.stage}-tenants",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

        # Add GSI for subdomain lookups
        self.tenant_table.add_global_secondary_index(
            index_name="subdomainIndex",
            partition_key=dynamodb.Attribute(
                name="subdomain",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # User management table with tenant isolation
        self.user_table = dynamodb.Table(
            self,
            "UserTable",
            table_name=f"{self.app_name}-{self.stage}-users",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
        )

        # GSI for tenant-scoped user queries
        self.user_table.add_global_secondary_index(
            index_name="byTenant",
            partition_key=dynamodb.Attribute(
                name="tenantId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # GSI for user ID lookups
        self.user_table.add_global_secondary_index(
            index_name="byUserId",
            partition_key=dynamodb.Attribute(
                name="userId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # Project management table
        self.project_table = dynamodb.Table(
            self,
            "ProjectTable",
            table_name=f"{self.app_name}-{self.stage}-projects",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
        )

        # GSI for tenant-scoped project queries
        self.project_table.add_global_secondary_index(
            index_name="byTenant",
            partition_key=dynamodb.Attribute(
                name="tenantId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # Task management table
        self.task_table = dynamodb.Table(
            self,
            "TaskTable",
            table_name=f"{self.app_name}-{self.stage}-tasks",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
        )

        # GSI for tenant-scoped task queries
        self.task_table.add_global_secondary_index(
            index_name="byTenantAndStatus",
            partition_key=dynamodb.Attribute(
                name="tenantId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="status",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # GSI for project-scoped task queries
        self.task_table.add_global_secondary_index(
            index_name="byProject",
            partition_key=dynamodb.Attribute(
                name="projectId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="status",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # Billing and usage tracking table
        self.billing_table = dynamodb.Table(
            self,
            "BillingTable",
            table_name=f"{self.app_name}-{self.stage}-billing",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
        )

        # Usage analytics table for tenant metrics
        self.usage_table = dynamodb.Table(
            self,
            "UsageTable",
            table_name=f"{self.app_name}-{self.stage}-usage",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
        )

        # GSI for monthly usage queries
        self.usage_table.add_global_secondary_index(
            index_name="byMonth",
            partition_key=dynamodb.Attribute(
                name="month",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="tenantId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # Activity logging table for audit trails
        self.activity_table = dynamodb.Table(
            self,
            "ActivityTable",
            table_name=f"{self.app_name}-{self.stage}-activity",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            point_in_time_recovery=True,
        )

        # GSI for tenant-scoped activity queries
        self.activity_table.add_global_secondary_index(
            index_name="byTenantAndAction",
            partition_key=dynamodb.Attribute(
                name="tenantId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="action",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # GSI for user-scoped activity queries
        self.activity_table.add_global_secondary_index(
            index_name="byUser",
            partition_key=dynamodb.Attribute(
                name="userId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

    def _create_authentication_layer(self) -> None:
        """
        Create Cognito User Pool with tenant-aware authentication
        
        This implementation provides:
        - Multi-tenant user isolation
        - Fine-grained role and group management
        - Custom JWT claims for tenant context
        - Lambda triggers for tenant-aware authentication workflows
        """
        # Create user pool with enhanced security settings
        self.user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=f"{self.app_name}-{self.stage}-users",
            self_sign_up_enabled=True,
            sign_in_aliases=cognito.SignInAliases(
                email=True,
                username=True
            ),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            password_policy=cognito.PasswordPolicy(
                min_length=12,
                require_digits=True,
                require_lowercase=True,
                require_uppercase=True,
                require_symbols=True,
                temp_password_validity=Duration.days(1)
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            mfa=cognito.Mfa.OPTIONAL,
            mfa_second_factor=cognito.MfaSecondFactor(
                sms=True,
                otp=True
            ),
            custom_attributes={
                "tenant_id": cognito.StringAttribute(
                    min_len=1,
                    max_len=256,
                    mutable=False
                ),
                "tenant_name": cognito.StringAttribute(
                    min_len=1,
                    max_len=256,
                    mutable=True
                ),
                "user_role": cognito.StringAttribute(
                    min_len=1,
                    max_len=100,
                    mutable=True
                ),
                "permissions": cognito.StringAttribute(
                    min_len=1,
                    max_len=2048,
                    mutable=True
                )
            },
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN
        )

        # Create user pool client for web application
        self.user_pool_client = cognito.UserPoolClient(
            self,
            "UserPoolClient",
            user_pool=self.user_pool,
            user_pool_client_name=f"{self.app_name}-{self.stage}-client",
            auth_flows=cognito.AuthFlow(
                admin_user_password=True,
                custom=True,
                user_password=True,
                user_srp=True
            ),
            generate_secret=False,
            token_validity=cognito.TokenValidity(
                access_token=Duration.hours(1),
                id_token=Duration.hours(1),
                refresh_token=Duration.days(30)
            ),
            o_auth=cognito.OAuthSettings(
                flows=cognito.OAuthFlows(
                    authorization_code_grant=True,
                    implicit_code_grant=False
                ),
                scopes=[
                    cognito.OAuthScope.EMAIL,
                    cognito.OAuthScope.OPENID,
                    cognito.OAuthScope.PROFILE
                ],
                callback_urls=["http://localhost:3000/", "https://localhost:3000/"]
            )
        )

        # Create identity pool for AWS service access
        self.identity_pool = cognito.CfnIdentityPool(
            self,
            "IdentityPool",
            identity_pool_name=f"{self.app_name}-{self.stage}-identity",
            allow_unauthenticated_identities=False,
            cognito_identity_providers=[
                cognito.CfnIdentityPool.CognitoIdentityProviderProperty(
                    client_id=self.user_pool_client.user_pool_client_id,
                    provider_name=self.user_pool.user_pool_provider_name
                )
            ]
        )

        # Create user groups for role-based access control
        self._create_user_groups()

    def _create_user_groups(self) -> None:
        """Create Cognito user groups for role-based access control"""
        
        # Super Administrators group
        self.super_admin_group = cognito.CfnUserPoolGroup(
            self,
            "SuperAdminGroup",
            group_name="SuperAdmins",
            user_pool_id=self.user_pool.user_pool_id,
            description="Platform super administrators with full access",
            precedence=1
        )

        # Tenant Administrators group
        self.tenant_admin_group = cognito.CfnUserPoolGroup(
            self,
            "TenantAdminGroup",
            group_name="TenantAdmins", 
            user_pool_id=self.user_pool.user_pool_id,
            description="Tenant administrators with tenant-scoped management access",
            precedence=10
        )

        # Project Managers group
        self.project_manager_group = cognito.CfnUserPoolGroup(
            self,
            "ProjectManagerGroup",
            group_name="ProjectManagers",
            user_pool_id=self.user_pool.user_pool_id,
            description="Project managers with project management capabilities",
            precedence=20
        )

        # Team Leads group
        self.team_lead_group = cognito.CfnUserPoolGroup(
            self,
            "TeamLeadGroup",
            group_name="TeamLeads",
            user_pool_id=self.user_pool.user_pool_id,
            description="Team leads with team management capabilities",
            precedence=30
        )

        # Developers group
        self.developer_group = cognito.CfnUserPoolGroup(
            self,
            "DeveloperGroup",
            group_name="Developers",
            user_pool_id=self.user_pool.user_pool_id,
            description="Developers with task and project access",
            precedence=40
        )

        # Viewers group
        self.viewer_group = cognito.CfnUserPoolGroup(
            self,
            "ViewerGroup", 
            group_name="Viewers",
            user_pool_id=self.user_pool.user_pool_id,
            description="Read-only access to assigned resources",
            precedence=50
        )

    def _create_api_layer(self) -> None:
        """
        Create AWS AppSync GraphQL API with fine-grained authorization
        
        The API layer implements:
        - Tenant-aware GraphQL schema
        - Fine-grained authorization rules
        - Custom resolvers for complex business logic
        - Real-time subscriptions with tenant isolation
        """
        # Create GraphQL API
        self.graphql_api = appsync.GraphqlApi(
            self,
            "GraphQLAPI",
            name=f"{self.app_name}-{self.stage}-api",
            schema=appsync.SchemaFile.from_asset("schema.graphql"),
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.USER_POOL,
                    user_pool_config=appsync.UserPoolConfig(
                        user_pool=self.user_pool
                    )
                ),
                additional_authorization_modes=[
                    appsync.AuthorizationMode(
                        authorization_type=appsync.AuthorizationType.IAM
                    )
                ]
            ),
            log_config=appsync.LogConfig(
                field_log_level=appsync.FieldLogLevel.ALL,
                retention=logs.RetentionDays.ONE_MONTH
            ),
            xray_enabled=True
        )

        # Create data sources for DynamoDB tables
        self._create_data_sources()

    def _create_data_sources(self) -> None:
        """Create AppSync data sources for DynamoDB tables"""
        
        # Tenant table data source
        self.tenant_data_source = self.graphql_api.add_dynamo_db_data_source(
            "TenantDataSource",
            table=self.tenant_table,
            description="Data source for tenant management"
        )

        # User table data source
        self.user_data_source = self.graphql_api.add_dynamo_db_data_source(
            "UserDataSource", 
            table=self.user_table,
            description="Data source for user management"
        )

        # Project table data source
        self.project_data_source = self.graphql_api.add_dynamo_db_data_source(
            "ProjectDataSource",
            table=self.project_table,
            description="Data source for project management"
        )

        # Task table data source
        self.task_data_source = self.graphql_api.add_dynamo_db_data_source(
            "TaskDataSource",
            table=self.task_table,
            description="Data source for task management"
        )

        # Billing table data source
        self.billing_data_source = self.graphql_api.add_dynamo_db_data_source(
            "BillingDataSource",
            table=self.billing_table,
            description="Data source for billing information"
        )

        # Usage table data source
        self.usage_data_source = self.graphql_api.add_dynamo_db_data_source(
            "UsageDataSource",
            table=self.usage_table,
            description="Data source for usage analytics"
        )

        # Activity table data source
        self.activity_data_source = self.graphql_api.add_dynamo_db_data_source(
            "ActivityDataSource",
            table=self.activity_table,
            description="Data source for activity logging"
        )

    def _create_business_logic_layer(self) -> None:
        """
        Create Lambda functions for business logic and tenant management
        
        Lambda functions handle:
        - Complex tenant provisioning workflows
        - Business rule enforcement
        - Integration with external services
        - Custom authorization logic
        """
        # Create tenant resolver Lambda function
        self.tenant_resolver_function = lambda_python.PythonFunction(
            self,
            "TenantResolverFunction",
            function_name=f"{self.app_name}-{self.stage}-tenant-resolver",
            entry="lambda/tenant_resolver",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="handler",
            timeout=Duration.seconds(30),
            memory_size=512,
            environment={
                "TENANT_TABLE": self.tenant_table.table_name,
                "USER_TABLE": self.user_table.table_name,
                "BILLING_TABLE": self.billing_table.table_name,
                "ACTIVITY_TABLE": self.activity_table.table_name,
                "USER_POOL_ID": self.user_pool.user_pool_id,
                "STAGE": self.stage
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            tracing=lambda_.Tracing.ACTIVE
        )

        # Grant necessary permissions to tenant resolver
        self.tenant_table.grant_read_write_data(self.tenant_resolver_function)
        self.user_table.grant_read_write_data(self.tenant_resolver_function)
        self.billing_table.grant_read_write_data(self.tenant_resolver_function)
        self.activity_table.grant_read_write_data(self.tenant_resolver_function)

        # Grant Cognito permissions
        self.tenant_resolver_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cognito-idp:AdminCreateUser",
                    "cognito-idp:AdminSetUserPassword",
                    "cognito-idp:AdminAddUserToGroup",
                    "cognito-idp:AdminRemoveUserFromGroup",
                    "cognito-idp:AdminListGroupsForUser",
                    "cognito-idp:AdminGetUser",
                    "cognito-idp:AdminUpdateUserAttributes"
                ],
                resources=[self.user_pool.user_pool_arn]
            )
        )

        # Create authentication triggers Lambda function
        self.auth_triggers_function = lambda_python.PythonFunction(
            self,
            "AuthTriggersFunction",
            function_name=f"{self.app_name}-{self.stage}-auth-triggers",
            entry="lambda/auth_triggers",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="handler",
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "TENANT_TABLE": self.tenant_table.table_name,
                "USER_TABLE": self.user_table.table_name,
                "ACTIVITY_TABLE": self.activity_table.table_name,
                "STAGE": self.stage
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            tracing=lambda_.Tracing.ACTIVE
        )

        # Grant permissions to authentication triggers
        self.tenant_table.grant_read_data(self.auth_triggers_function)
        self.user_table.grant_read_write_data(self.auth_triggers_function)
        self.activity_table.grant_write_data(self.auth_triggers_function)

        # Grant Cognito permissions for user management
        self.auth_triggers_function.add_to_role_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "cognito-idp:AdminAddUserToGroup",
                    "cognito-idp:AdminListGroupsForUser",
                    "cognito-idp:AdminGetUser"
                ],
                resources=[self.user_pool.user_pool_arn]
            )
        )

        # Configure Cognito triggers
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.PRE_SIGN_UP,
            self.auth_triggers_function
        )
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.POST_CONFIRMATION,
            self.auth_triggers_function
        )
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.PRE_AUTHENTICATION,
            self.auth_triggers_function
        )
        self.user_pool.add_trigger(
            cognito.UserPoolOperation.CREATE_AUTH_CHALLENGE,
            self.auth_triggers_function
        )

        # Create usage tracking Lambda function
        self.usage_tracker_function = lambda_python.PythonFunction(
            self,
            "UsageTrackerFunction",
            function_name=f"{self.app_name}-{self.stage}-usage-tracker",
            entry="lambda/usage_tracker",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="handler",
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "USAGE_TABLE": self.usage_table.table_name,
                "TENANT_TABLE": self.tenant_table.table_name,
                "BILLING_TABLE": self.billing_table.table_name,
                "STAGE": self.stage
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            tracing=lambda_.Tracing.ACTIVE
        )

        # Grant permissions to usage tracker
        self.usage_table.grant_read_write_data(self.usage_tracker_function)
        self.tenant_table.grant_read_data(self.usage_tracker_function)
        self.billing_table.grant_read_write_data(self.usage_tracker_function)

        # Create billing processor Lambda function
        self.billing_processor_function = lambda_python.PythonFunction(
            self,
            "BillingProcessorFunction",
            function_name=f"{self.app_name}-{self.stage}-billing-processor",
            entry="lambda/billing_processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="handler",
            timeout=Duration.minutes(10),
            memory_size=1024,
            environment={
                "BILLING_TABLE": self.billing_table.table_name,
                "USAGE_TABLE": self.usage_table.table_name,
                "TENANT_TABLE": self.tenant_table.table_name,
                "STAGE": self.stage
            },
            log_retention=logs.RetentionDays.ONE_MONTH,
            tracing=lambda_.Tracing.ACTIVE
        )

        # Grant permissions to billing processor
        self.billing_table.grant_read_write_data(self.billing_processor_function)
        self.usage_table.grant_read_data(self.billing_processor_function)
        self.tenant_table.grant_read_write_data(self.billing_processor_function)

        # Add Lambda data source to AppSync
        self.tenant_lambda_data_source = self.graphql_api.add_lambda_data_source(
            "TenantLambdaDataSource",
            lambda_function=self.tenant_resolver_function,
            description="Lambda data source for tenant operations"
        )

    def _create_file_storage(self) -> None:
        """
        Create S3 buckets for tenant-specific file storage
        
        File storage implements:
        - Tenant-isolated storage buckets
        - Lifecycle policies for cost optimization
        - Encryption at rest and in transit
        - Access logging for audit trails
        """
        # Create main storage bucket with tenant prefixes
        self.storage_bucket = s3.Bucket(
            self,
            "StorageBucket",
            bucket_name=f"{self.app_name}-{self.stage}-storage-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            versioned=True,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="transition-to-ia",
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
                ),
                s3.LifecycleRule(
                    id="delete-incomplete-uploads",
                    enabled=True,
                    abort_incomplete_multipart_upload_after=Duration.days(1)
                )
            ],
            cors=[
                s3.CorsRule(
                    allowed_origins=["*"],
                    allowed_methods=[s3.HttpMethods.GET, s3.HttpMethods.POST, s3.HttpMethods.PUT],
                    allowed_headers=["*"],
                    max_age=3000
                )
            ]
        )

        # Create access logs bucket
        self.access_logs_bucket = s3.Bucket(
            self,
            "AccessLogsBucket",
            bucket_name=f"{self.app_name}-{self.stage}-access-logs-{self.account}-{self.region}",
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            removal_policy=RemovalPolicy.DESTROY if self.stage == 'dev' else RemovalPolicy.RETAIN,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-old-logs",
                    enabled=True,
                    expiration=Duration.days(90)
                )
            ]
        )

        # Enable access logging
        self.storage_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            destinations=None  # Could add SQS/SNS for processing
        )

    def _create_monitoring(self) -> None:
        """
        Create comprehensive monitoring and analytics
        
        Monitoring includes:
        - CloudWatch dashboards for tenant metrics
        - Custom metrics for business KPIs
        - Alarms for operational issues
        - Log aggregation and analysis
        """
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self,
            "MultiTenantDashboard",
            dashboard_name=f"{self.app_name}-{self.stage}-dashboard"
        )

        # Add API metrics widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="API Requests",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/AppSync",
                        metric_name="4XXError",
                        dimensions_map={
                            "GraphQLAPIId": self.graphql_api.api_id
                        },
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/AppSync", 
                        metric_name="5XXError",
                        dimensions_map={
                            "GraphQLAPIId": self.graphql_api.api_id
                        },
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Add DynamoDB metrics widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Database Operations",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/DynamoDB",
                        metric_name="ConsumedReadCapacityUnits",
                        dimensions_map={
                            "TableName": self.tenant_table.table_name
                        },
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/DynamoDB",
                        metric_name="ConsumedWriteCapacityUnits", 
                        dimensions_map={
                            "TableName": self.tenant_table.table_name
                        },
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Add Lambda metrics widget
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Functions",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Invocations",
                        dimensions_map={
                            "FunctionName": self.tenant_resolver_function.function_name
                        },
                        statistic="Sum"
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Lambda",
                        metric_name="Errors",
                        dimensions_map={
                            "FunctionName": self.tenant_resolver_function.function_name
                        },
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Create alarms for critical metrics
        self._create_alarms()

    def _create_alarms(self) -> None:
        """Create CloudWatch alarms for critical system metrics"""
        
        # API error rate alarm
        cloudwatch.Alarm(
            self,
            "APIErrorRateAlarm",
            alarm_name=f"{self.app_name}-{self.stage}-api-error-rate",
            alarm_description="High API error rate detected",
            metric=cloudwatch.Metric(
                namespace="AWS/AppSync",
                metric_name="5XXError",
                dimensions_map={
                    "GraphQLAPIId": self.graphql_api.api_id
                },
                statistic="Sum"
            ),
            threshold=10,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # Lambda error rate alarm
        cloudwatch.Alarm(
            self,
            "LambdaErrorRateAlarm",
            alarm_name=f"{self.app_name}-{self.stage}-lambda-error-rate",
            alarm_description="High Lambda error rate detected",
            metric=cloudwatch.Metric(
                namespace="AWS/Lambda",
                metric_name="Errors",
                dimensions_map={
                    "FunctionName": self.tenant_resolver_function.function_name
                },
                statistic="Sum"
            ),
            threshold=5,
            evaluation_periods=2,
            datapoints_to_alarm=2,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

        # DynamoDB throttle alarm
        cloudwatch.Alarm(
            self,
            "DynamoDBThrottleAlarm",
            alarm_name=f"{self.app_name}-{self.stage}-dynamodb-throttle",
            alarm_description="DynamoDB throttling detected",
            metric=cloudwatch.Metric(
                namespace="AWS/DynamoDB",
                metric_name="UserErrors",
                dimensions_map={
                    "TableName": self.tenant_table.table_name
                },
                statistic="Sum"
            ),
            threshold=0,
            evaluation_periods=1,
            datapoints_to_alarm=1,
            comparison_operator=cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD
        )

    def _create_frontend_hosting(self) -> None:
        """
        Create Amplify hosting for the frontend application
        
        Amplify hosting provides:
        - CI/CD pipeline for frontend deployments
        - Custom domain support for tenant subdomains
        - Global CDN for performance
        - SSL certificates for security
        """
        # Create Amplify app for frontend hosting
        self.amplify_app = amplify.App(
            self,
            "AmplifyApp",
            app_name=f"{self.app_name}-{self.stage}",
            description="Multi-tenant SaaS frontend application",
            environment_variables={
                "REACT_APP_GRAPHQL_ENDPOINT": self.graphql_api.graphql_url,
                "REACT_APP_USER_POOL_ID": self.user_pool.user_pool_id,
                "REACT_APP_USER_POOL_CLIENT_ID": self.user_pool_client.user_pool_client_id,
                "REACT_APP_IDENTITY_POOL_ID": self.identity_pool.ref,
                "REACT_APP_REGION": self.region,
                "REACT_APP_STAGE": self.stage
            },
            custom_rules=[
                amplify.CustomRule(
                    source="https://www.example.com",
                    target="https://main.example.com",
                    status=amplify.RedirectStatus.PERMANENT_REDIRECT
                )
            ]
        )

        # Create main branch
        self.main_branch = self.amplify_app.add_branch(
            "main",
            branch_name="main",
            auto_build=True,
            environment_variables={
                "NODE_ENV": "production" if self.stage == 'prod' else "development"
            }
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for easy reference"""
        
        # API outputs
        CfnOutput(
            self,
            "GraphQLAPIEndpoint",
            value=self.graphql_api.graphql_url,
            description="GraphQL API endpoint URL",
            export_name=f"{self.app_name}-{self.stage}-graphql-url"
        )

        CfnOutput(
            self,
            "GraphQLAPIKey",
            value=self.graphql_api.api_key or "No API Key",
            description="GraphQL API key (if enabled)",
            export_name=f"{self.app_name}-{self.stage}-graphql-key"
        )

        # Authentication outputs
        CfnOutput(
            self,
            "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID",
            export_name=f"{self.app_name}-{self.stage}-user-pool-id"
        )

        CfnOutput(
            self,
            "UserPoolClientId",
            value=self.user_pool_client.user_pool_client_id,
            description="Cognito User Pool Client ID",
            export_name=f"{self.app_name}-{self.stage}-user-pool-client-id"
        )

        CfnOutput(
            self,
            "IdentityPoolId",
            value=self.identity_pool.ref,
            description="Cognito Identity Pool ID",
            export_name=f"{self.app_name}-{self.stage}-identity-pool-id"
        )

        # Storage outputs
        CfnOutput(
            self,
            "StorageBucketName",
            value=self.storage_bucket.bucket_name,
            description="S3 storage bucket name",
            export_name=f"{self.app_name}-{self.stage}-storage-bucket"
        )

        # Frontend outputs
        CfnOutput(
            self,
            "AmplifyAppId",
            value=self.amplify_app.app_id,
            description="Amplify App ID",
            export_name=f"{self.app_name}-{self.stage}-amplify-app-id"
        )

        CfnOutput(
            self,
            "AmplifyURL",
            value=f"https://main.{self.amplify_app.app_id}.amplifyapp.com",
            description="Amplify App URL",
            export_name=f"{self.app_name}-{self.stage}-amplify-url"
        )

        # Database outputs
        CfnOutput(
            self,
            "TenantTableName",
            value=self.tenant_table.table_name,
            description="DynamoDB Tenant table name",
            export_name=f"{self.app_name}-{self.stage}-tenant-table"
        )

        CfnOutput(
            self,
            "UserTableName",
            value=self.user_table.table_name,
            description="DynamoDB User table name",
            export_name=f"{self.app_name}-{self.stage}-user-table"
        )

        # Monitoring outputs
        CfnOutput(
            self,
            "DashboardURL",
            value=f"https://console.aws.amazon.com/cloudwatch/home?region={self.region}#dashboards:name={self.dashboard.dashboard_name}",
            description="CloudWatch Dashboard URL",
            export_name=f"{self.app_name}-{self.stage}-dashboard-url"
        )


class MultiTenantSaaSApp(cdk.App):
    """CDK Application for Multi-Tenant SaaS Platform"""
    
    def __init__(self):
        super().__init__()
        
        # Get configuration from environment or context
        stage = self.node.try_get_context("stage") or os.environ.get("STAGE", "dev")
        account = os.environ.get("CDK_DEFAULT_ACCOUNT")
        region = os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        
        if not account:
            raise ValueError("CDK_DEFAULT_ACCOUNT environment variable is required")
        
        # Create the main stack
        MultiTenantSaaSStack(
            self,
            f"MultiTenantSaaSStack-{stage}",
            env=Environment(account=account, region=region),
            stage=stage,
            description=f"Multi-Tenant SaaS Application Stack ({stage})"
        )


# Entry point
app = MultiTenantSaaSApp()
app.synth()