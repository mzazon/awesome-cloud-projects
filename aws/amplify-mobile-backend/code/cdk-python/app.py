#!/usr/bin/env python3
"""
AWS CDK application for Mobile Backend Services with Amplify
Deploys a complete mobile backend infrastructure including authentication,
GraphQL API, storage, analytics, and push notifications.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    CfnOutput,
    aws_cognito as cognito,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_pinpoint as pinpoint,
    aws_cloudwatch as cloudwatch,
    aws_logs as logs,
)
from constructs import Construct
import json


class MobileBackendStack(Stack):
    """
    CDK Stack for Mobile Backend Services using AWS Amplify-compatible services.
    
    This stack creates a complete mobile backend infrastructure including:
    - Amazon Cognito for user authentication
    - AWS AppSync for GraphQL API
    - Amazon DynamoDB for data storage
    - Amazon S3 for file storage
    - AWS Lambda for custom business logic
    - Amazon Pinpoint for analytics and push notifications
    - CloudWatch for monitoring and logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique identifier for resources
        stack_name = self.stack_name.lower()
        
        # Create Cognito User Pool for authentication
        self.user_pool = self._create_user_pool(stack_name)
        
        # Create Cognito Identity Pool for AWS resource access
        self.identity_pool = self._create_identity_pool(stack_name)
        
        # Create DynamoDB tables for data storage
        self.post_table = self._create_post_table(stack_name)
        self.user_table = self._create_user_table(stack_name)
        
        # Create S3 bucket for file storage
        self.storage_bucket = self._create_storage_bucket(stack_name)
        
        # Create Lambda functions for custom business logic
        self.post_processor_function = self._create_lambda_function(stack_name)
        
        # Create AppSync GraphQL API
        self.graphql_api = self._create_appsync_api(stack_name)
        
        # Create Pinpoint project for analytics and push notifications
        self.pinpoint_app = self._create_pinpoint_app(stack_name)
        
        # Create CloudWatch dashboard for monitoring
        self._create_monitoring_dashboard(stack_name)
        
        # Output important resource information
        self._create_outputs()

    def _create_user_pool(self, stack_name: str) -> cognito.UserPool:
        """
        Create Amazon Cognito User Pool for user authentication.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            cognito.UserPool: The created user pool
        """
        user_pool = cognito.UserPool(
            self, "UserPool",
            user_pool_name=f"{stack_name}-user-pool",
            # Email as username for user registration
            sign_in_aliases=cognito.SignInAliases(
                email=True,
                username=True
            ),
            # Required attributes for user registration
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(required=True, mutable=True),
                given_name=cognito.StandardAttribute(required=True, mutable=True),
                family_name=cognito.StandardAttribute(required=True, mutable=True),
                phone_number=cognito.StandardAttribute(required=False, mutable=True),
            ),
            # Password policy for security
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=True,
                temp_password_validity=Duration.days(3)
            ),
            # Email verification settings
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            user_verification=cognito.UserVerificationConfig(
                email_subject="Verify your mobile app account",
                email_body="Your verification code is {####}",
                email_style=cognito.VerificationEmailStyle.CODE,
            ),
            # User pool triggers (can be extended with Lambda functions)
            lambda_triggers=cognito.UserPoolTriggers(),
            # MFA configuration
            mfa=cognito.Mfa.OPTIONAL,
            mfa_second_factor=cognito.MfaSecondFactor(
                sms=True,
                otp=True
            ),
            # Self service actions
            self_sign_up_enabled=True,
            user_invitation=cognito.UserInvitationConfig(
                email_subject="Welcome to our mobile app!",
                email_body="Your username is {username} and temporary password is {####}. Please sign in and change your password.",
            ),
            # Deletion protection
            removal_policy=cdk.RemovalPolicy.DESTROY  # Change to RETAIN for production
        )

        # Create User Pool Client for mobile app integration
        user_pool_client = cognito.UserPoolClient(
            self, "UserPoolClient",
            user_pool=user_pool,
            user_pool_client_name=f"{stack_name}-mobile-client",
            # Authentication flows for mobile apps
            auth_flows=cognito.AuthFlow(
                user_password=True,
                user_srp=True,
                custom=True,
                admin_user_password=True
            ),
            # OAuth configuration for social login (can be extended)
            o_auth=cognito.OAuthSettings(
                flows=cognito.OAuthFlows(
                    authorization_code_grant=True,
                    implicit_code_grant=True
                ),
                scopes=[
                    cognito.OAuthScope.EMAIL,
                    cognito.OAuthScope.OPENID,
                    cognito.OAuthScope.PROFILE,
                    cognito.OAuthScope.PHONE
                ]
            ),
            # Security settings
            prevent_user_existence_errors=True,
            # Token validity periods for mobile apps
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1),
            refresh_token_validity=Duration.days(30)
        )

        return user_pool

    def _create_identity_pool(self, stack_name: str) -> cognito.CfnIdentityPool:
        """
        Create Amazon Cognito Identity Pool for AWS resource access.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            cognito.CfnIdentityPool: The created identity pool
        """
        # Create Identity Pool
        identity_pool = cognito.CfnIdentityPool(
            self, "IdentityPool",
            identity_pool_name=f"{stack_name}-identity-pool",
            allow_unauthenticated_identities=False,
            cognito_identity_providers=[
                cognito.CfnIdentityPool.CognitoIdentityProviderProperty(
                    client_id=self.user_pool.user_pool_client_id,
                    provider_name=self.user_pool.user_pool_provider_name
                )
            ]
        )

        # Create IAM roles for authenticated and unauthenticated users
        authenticated_role = iam.Role(
            self, "AuthenticatedRole",
            role_name=f"{stack_name}-auth-role",
            assumed_by=iam.FederatedPrincipal(
                "cognito-identity.amazonaws.com",
                conditions={
                    "StringEquals": {
                        "cognito-identity.amazonaws.com:aud": identity_pool.ref
                    },
                    "ForAnyValue:StringLike": {
                        "cognito-identity.amazonaws.com:amr": "authenticated"
                    }
                },
                assume_role_action="sts:AssumeRoleWithWebIdentity"
            ),
            description="Role for authenticated users"
        )

        unauthenticated_role = iam.Role(
            self, "UnauthenticatedRole",
            role_name=f"{stack_name}-unauth-role",
            assumed_by=iam.FederatedPrincipal(
                "cognito-identity.amazonaws.com",
                conditions={
                    "StringEquals": {
                        "cognito-identity.amazonaws.com:aud": identity_pool.ref
                    },
                    "ForAnyValue:StringLike": {
                        "cognito-identity.amazonaws.com:amr": "unauthenticated"
                    }
                },
                assume_role_action="sts:AssumeRoleWithWebIdentity"
            ),
            description="Role for unauthenticated users"
        )

        # Attach role to Identity Pool
        cognito.CfnIdentityPoolRoleAttachment(
            self, "IdentityPoolRoleAttachment",
            identity_pool_id=identity_pool.ref,
            roles={
                "authenticated": authenticated_role.role_arn,
                "unauthenticated": unauthenticated_role.role_arn
            }
        )

        return identity_pool

    def _create_post_table(self, stack_name: str) -> dynamodb.Table:
        """
        Create DynamoDB table for storing post data.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "PostTable",
            table_name=f"{stack_name}-posts",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            # Global Secondary Index for querying by author
            global_secondary_indexes=[
                dynamodb.GlobalSecondaryIndex(
                    index_name="byAuthor",
                    partition_key=dynamodb.Attribute(
                        name="authorId",
                        type=dynamodb.AttributeType.STRING
                    ),
                    sort_key=dynamodb.Attribute(
                        name="createdAt",
                        type=dynamodb.AttributeType.STRING
                    ),
                    projection_type=dynamodb.ProjectionType.ALL
                )
            ],
            # Billing and performance settings
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            # Data retention and backup
            removal_policy=cdk.RemovalPolicy.DESTROY,  # Change to RETAIN for production
            # Encryption at rest
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            # Stream for real-time processing
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )

        return table

    def _create_user_table(self, stack_name: str) -> dynamodb.Table:
        """
        Create DynamoDB table for storing user profile data.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "UserTable",
            table_name=f"{stack_name}-users",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            # Billing and performance settings
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            # Data retention and backup
            removal_policy=cdk.RemovalPolicy.DESTROY,  # Change to RETAIN for production
            # Encryption at rest
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        return table

    def _create_storage_bucket(self, stack_name: str) -> s3.Bucket:
        """
        Create S3 bucket for file storage with secure access controls.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            s3.Bucket: The created S3 bucket
        """
        # Create S3 bucket for user file storage
        bucket = s3.Bucket(
            self, "StorageBucket",
            bucket_name=f"{stack_name}-user-files-{self.account}",
            # Security settings
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            enforce_ssl=True,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            # Lifecycle management
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteIncompleteMultipartUploads",
                    abort_incomplete_multipart_upload_after=Duration.days(1)
                ),
                s3.LifecycleRule(
                    id="TransitionToIA",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        )
                    ]
                )
            ],
            # CORS configuration for mobile apps
            cors=[
                s3.CorsRule(
                    allowed_methods=[
                        s3.HttpMethods.GET,
                        s3.HttpMethods.POST,
                        s3.HttpMethods.PUT,
                        s3.HttpMethods.DELETE,
                        s3.HttpMethods.HEAD
                    ],
                    allowed_origins=["*"],  # Configure specific origins for production
                    allowed_headers=["*"],
                    max_age=3000
                )
            ],
            # Deletion policy
            removal_policy=cdk.RemovalPolicy.DESTROY  # Change to RETAIN for production
        )

        return bucket

    def _create_lambda_function(self, stack_name: str) -> lambda_.Function:
        """
        Create Lambda function for custom business logic processing.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            lambda_.Function: The created Lambda function
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "PostProcessorRole",
            role_name=f"{stack_name}-post-processor-role",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Grant permissions to access DynamoDB tables
        self.post_table.grant_read_write_data(lambda_role)
        self.user_table.grant_read_data(lambda_role)

        # Create Lambda function
        post_processor = lambda_.Function(
            self, "PostProcessorFunction",
            function_name=f"{stack_name}-post-processor",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.handler",
            role=lambda_role,
            code=lambda_.Code.from_inline("""
import json
import boto3
import logging
from datetime import datetime
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource('dynamodb')
post_table = dynamodb.Table('""" + f"{stack_name}-posts" + """')
user_table = dynamodb.Table('""" + f"{stack_name}-users" + """')

def handler(event, context):
    \"\"\"
    Lambda function for processing post creation and updates.
    Handles content validation, user verification, and notification triggers.
    \"\"\"
    logger.info(f'Event received: {json.dumps(event, default=str)}')
    
    try:
        # Handle AppSync GraphQL events
        if 'typeName' in event and 'fieldName' in event:
            return handle_appsync_event(event, context)
        
        # Handle direct invocation
        return handle_direct_invocation(event, context)
        
    except Exception as e:
        logger.error(f'Error processing event: {str(e)}')
        raise e

def handle_appsync_event(event, context):
    \"\"\"Handle events from AppSync GraphQL API\"\"\"
    type_name = event.get('typeName')
    field_name = event.get('fieldName')
    arguments = event.get('arguments', {})
    
    if type_name == 'Mutation' and field_name == 'createPost':
        return process_post_creation(arguments.get('input', {}))
    
    elif type_name == 'Mutation' and field_name == 'updatePost':
        return process_post_update(arguments.get('input', {}))
    
    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Event processed successfully'})
    }

def handle_direct_invocation(event, context):
    \"\"\"Handle direct Lambda invocation\"\"\"
    action = event.get('action', 'unknown')
    
    if action == 'healthCheck':
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Post processor function is healthy',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
    
    return {
        'statusCode': 400,
        'body': json.dumps({'error': 'Unknown action'})
    }

def process_post_creation(post_input):
    \"\"\"Process new post creation with validation and enrichment\"\"\"
    try:
        # Validate post content
        if not post_input.get('content'):
            raise ValueError('Post content is required')
        
        # Verify user exists
        user_id = post_input.get('authorId')
        if user_id:
            verify_user_exists(user_id)
        
        # Enrich post data
        enriched_post = {
            **post_input,
            'id': post_input.get('id', str(uuid.uuid4())),
            'createdAt': datetime.utcnow().isoformat(),
            'updatedAt': datetime.utcnow().isoformat(),
            'status': 'published',
            'version': 1
        }
        
        # Content moderation (placeholder for actual implementation)
        moderation_result = moderate_content(enriched_post['content'])
        if not moderation_result['approved']:
            enriched_post['status'] = 'pending_review'
            enriched_post['moderationFlags'] = moderation_result['flags']
        
        logger.info(f'Post processed successfully: {enriched_post["id"]}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Post created and processed successfully',
                'postId': enriched_post['id'],
                'status': enriched_post['status']
            })
        }
        
    except Exception as e:
        logger.error(f'Error processing post creation: {str(e)}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to process post creation'})
        }

def process_post_update(post_input):
    \"\"\"Process post updates\"\"\"
    try:
        post_id = post_input.get('id')
        if not post_id:
            raise ValueError('Post ID is required for updates')
        
        # Update timestamp
        updated_post = {
            **post_input,
            'updatedAt': datetime.utcnow().isoformat()
        }
        
        logger.info(f'Post updated successfully: {post_id}')
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Post updated successfully',
                'postId': post_id
            })
        }
        
    except Exception as e:
        logger.error(f'Error processing post update: {str(e)}')
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to process post update'})
        }

def verify_user_exists(user_id):
    \"\"\"Verify that the user exists in the user table\"\"\"
    try:
        response = user_table.get_item(Key={'id': user_id})
        if 'Item' not in response:
            raise ValueError(f'User {user_id} not found')
        return response['Item']
    except Exception as e:
        logger.warning(f'Could not verify user {user_id}: {str(e)}')
        # Continue processing even if user verification fails
        return None

def moderate_content(content):
    \"\"\"
    Basic content moderation (placeholder for comprehensive solution)
    In production, integrate with Amazon Comprehend or Amazon Rekognition
    \"\"\"
    flags = []
    
    # Basic keyword filtering
    inappropriate_words = ['spam', 'inappropriate']
    content_lower = content.lower()
    
    for word in inappropriate_words:
        if word in content_lower:
            flags.append(f'Contains inappropriate word: {word}')
    
    return {
        'approved': len(flags) == 0,
        'flags': flags,
        'confidence': 0.95 if len(flags) == 0 else 0.5
    }
"""),
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "POST_TABLE_NAME": self.post_table.table_name,
                "USER_TABLE_NAME": self.user_table.table_name,
                "LOG_LEVEL": "INFO"
            },
            description="Lambda function for processing mobile app posts and business logic"
        )

        return post_processor

    def _create_appsync_api(self, stack_name: str) -> appsync.GraphqlApi:
        """
        Create AWS AppSync GraphQL API with schema and resolvers.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            appsync.GraphqlApi: The created GraphQL API
        """
        # Create the GraphQL API
        api = appsync.GraphqlApi(
            self, "GraphQLAPI",
            name=f"{stack_name}-mobile-api",
            # Use Cognito User Pool for authorization
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.USER_POOL,
                    user_pool_config=appsync.UserPoolConfig(
                        user_pool=self.user_pool
                    )
                ),
                # Additional authorization modes
                additional_authorization_modes=[
                    appsync.AuthorizationMode(
                        authorization_type=appsync.AuthorizationType.IAM
                    )
                ]
            ),
            # GraphQL schema definition
            schema=appsync.SchemaFile.from_asset("schema.graphql"),
            # Logging configuration
            log_config=appsync.LogConfig(
                field_log_level=appsync.FieldLogLevel.ALL,
                retention=logs.RetentionDays.ONE_WEEK
            ),
            # XRay tracing for performance monitoring
            xray_enabled=True
        )

        # Create DynamoDB data sources
        post_data_source = api.add_dynamo_db_data_source(
            "PostDataSource",
            table=self.post_table,
            description="DynamoDB data source for posts"
        )

        user_data_source = api.add_dynamo_db_data_source(
            "UserDataSource",
            table=self.user_table,
            description="DynamoDB data source for users"
        )

        # Create Lambda data source
        lambda_data_source = api.add_lambda_data_source(
            "PostProcessorDataSource",
            lambda_function=self.post_processor_function,
            description="Lambda data source for post processing"
        )

        # Create resolvers for posts
        post_data_source.create_resolver(
            "GetPostResolver",
            type_name="Query",
            field_name="getPost",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_get_item("id", "id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

        post_data_source.create_resolver(
            "ListPostsResolver",
            type_name="Query",
            field_name="listPosts",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_scan_table(),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_list()
        )

        post_data_source.create_resolver(
            "CreatePostResolver",
            type_name="Mutation",
            field_name="createPost",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_put_item(
                appsync.PrimaryKey.partition("id").auto(),
                appsync.Values.projecting("input")
            ),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

        post_data_source.create_resolver(
            "UpdatePostResolver",
            type_name="Mutation",
            field_name="updatePost",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_put_item(
                appsync.PrimaryKey.partition("id").is("input.id"),
                appsync.Values.projecting("input")
            ),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

        post_data_source.create_resolver(
            "DeletePostResolver",
            type_name="Mutation",
            field_name="deletePost",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_delete_item("id", "input.id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

        # Create resolvers for users
        user_data_source.create_resolver(
            "GetUserResolver",
            type_name="Query",
            field_name="getUser",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_get_item("id", "id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

        user_data_source.create_resolver(
            "CreateUserResolver",
            type_name="Mutation",
            field_name="createUser",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_put_item(
                appsync.PrimaryKey.partition("id").auto(),
                appsync.Values.projecting("input")
            ),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

        # Create subscription resolver for real-time updates
        post_data_source.create_resolver(
            "OnCreatePostResolver",
            type_name="Subscription",
            field_name="onCreatePost",
            request_mapping_template=appsync.MappingTemplate.from_string(
                '{"version": "2017-02-28", "payload": {}}'
            ),
            response_mapping_template=appsync.MappingTemplate.from_string("$util.toJson($context.result)")
        )

        return api

    def _create_pinpoint_app(self, stack_name: str) -> pinpoint.CfnApp:
        """
        Create Amazon Pinpoint application for analytics and push notifications.
        
        Args:
            stack_name: The stack name for resource naming
            
        Returns:
            pinpoint.CfnApp: The created Pinpoint application
        """
        # Create Pinpoint application
        pinpoint_app = pinpoint.CfnApp(
            self, "PinpointApp",
            name=f"{stack_name}-mobile-analytics"
        )

        # Configure application settings
        pinpoint.CfnApplicationSettings(
            self, "PinpointAppSettings",
            application_id=pinpoint_app.ref,
            # Campaign settings
            campaign_hook=pinpoint.CfnApplicationSettings.CampaignHookProperty(
                lambda_function_name=self.post_processor_function.function_name,
                mode="DELIVERY"
            ),
            # Limits to prevent spam
            limits=pinpoint.CfnApplicationSettings.LimitsProperty(
                daily=100,
                maximum_duration=600,
                messages_per_second=10,
                total=1000
            ),
            # Enable quiet time
            quiet_time=pinpoint.CfnApplicationSettings.QuietTimeProperty(
                start="22:00",
                end="08:00"
            )
        )

        # Grant Pinpoint permissions to invoke Lambda
        self.post_processor_function.add_permission(
            "PinpointInvokePermission",
            principal=iam.ServicePrincipal("pinpoint.amazonaws.com"),
            action="lambda:InvokeFunction",
            source_arn=f"arn:aws:pinpoint:{self.region}:{self.account}:apps/{pinpoint_app.ref}/*"
        )

        return pinpoint_app

    def _create_monitoring_dashboard(self, stack_name: str) -> None:
        """
        Create CloudWatch dashboard for monitoring mobile backend services.
        
        Args:
            stack_name: The stack name for resource naming
        """
        dashboard = cloudwatch.Dashboard(
            self, "MonitoringDashboard",
            dashboard_name=f"{stack_name}-mobile-backend-dashboard",
            period_override=cloudwatch.PeriodOverride.AUTO
        )

        # Add AppSync metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="AppSync API Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/AppSync",
                        metric_name="4XXError",
                        dimensions_map={"GraphQLAPIId": self.graphql_api.api_id}
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/AppSync",
                        metric_name="5XXError",
                        dimensions_map={"GraphQLAPIId": self.graphql_api.api_id}
                    )
                ],
                right=[
                    cloudwatch.Metric(
                        namespace="AWS/AppSync",
                        metric_name="RequestCount",
                        dimensions_map={"GraphQLAPIId": self.graphql_api.api_id}
                    )
                ]
            )
        )

        # Add DynamoDB metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="DynamoDB Metrics",
                left=[
                    self.post_table.metric_consumed_read_capacity_units(),
                    self.post_table.metric_consumed_write_capacity_units()
                ],
                right=[
                    self.post_table.metric_successful_request_latency(),
                    self.post_table.metric_system_errors()
                ]
            )
        )

        # Add Lambda metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Metrics",
                left=[
                    self.post_processor_function.metric_invocations(),
                    self.post_processor_function.metric_errors()
                ],
                right=[
                    self.post_processor_function.metric_duration(),
                    self.post_processor_function.metric_throttles()
                ]
            )
        )

        # Add Cognito metrics
        dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Cognito Metrics",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/Cognito",
                        metric_name="SignInSuccesses",
                        dimensions_map={"UserPool": self.user_pool.user_pool_id}
                    ),
                    cloudwatch.Metric(
                        namespace="AWS/Cognito",
                        metric_name="SignInFailures",
                        dimensions_map={"UserPool": self.user_pool.user_pool_id}
                    )
                ]
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        
        CfnOutput(
            self, "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID for mobile app configuration",
            export_name=f"{self.stack_name}-UserPoolId"
        )

        CfnOutput(
            self, "UserPoolClientId",
            value=self.user_pool.user_pool_client_id,
            description="Cognito User Pool Client ID for mobile app configuration",
            export_name=f"{self.stack_name}-UserPoolClientId"
        )

        CfnOutput(
            self, "IdentityPoolId",
            value=self.identity_pool.ref,
            description="Cognito Identity Pool ID for AWS resource access",
            export_name=f"{self.stack_name}-IdentityPoolId"
        )

        CfnOutput(
            self, "GraphQLAPIURL",
            value=self.graphql_api.graphql_url,
            description="GraphQL API URL for mobile app integration",
            export_name=f"{self.stack_name}-GraphQLAPIURL"
        )

        CfnOutput(
            self, "GraphQLAPIKey",
            value=self.graphql_api.api_key or "N/A",
            description="GraphQL API Key (if API key auth is enabled)",
            export_name=f"{self.stack_name}-GraphQLAPIKey"
        )

        CfnOutput(
            self, "StorageBucketName",
            value=self.storage_bucket.bucket_name,
            description="S3 bucket name for file storage",
            export_name=f"{self.stack_name}-StorageBucket"
        )

        CfnOutput(
            self, "PostTableName",
            value=self.post_table.table_name,
            description="DynamoDB table name for posts",
            export_name=f"{self.stack_name}-PostTable"
        )

        CfnOutput(
            self, "UserTableName",
            value=self.user_table.table_name,
            description="DynamoDB table name for users",
            export_name=f"{self.stack_name}-UserTable"
        )

        CfnOutput(
            self, "PinpointApplicationId",
            value=self.pinpoint_app.ref,
            description="Pinpoint Application ID for analytics and push notifications",
            export_name=f"{self.stack_name}-PinpointAppId"
        )

        CfnOutput(
            self, "PostProcessorFunctionName",
            value=self.post_processor_function.function_name,
            description="Lambda function name for post processing",
            export_name=f"{self.stack_name}-PostProcessorFunction"
        )


class MobileBackendApp(cdk.App):
    """CDK Application class for Mobile Backend Services."""
    
    def __init__(self) -> None:
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=self.node.try_get_context("account") or "123456789012",
            region=self.node.try_get_context("region") or "us-east-1"
        )
        
        # Create the mobile backend stack
        MobileBackendStack(
            self,
            "MobileBackendStack",
            env=env,
            description="Complete mobile backend infrastructure with Amplify-compatible services",
            tags={
                "Project": "MobileBackendServices",
                "Environment": self.node.try_get_context("environment") or "development",
                "Owner": "mobile-team",
                "CostCenter": "mobile-development"
            }
        )


# Create and run the CDK application
if __name__ == "__main__":
    app = MobileBackendApp()
    app.synth()