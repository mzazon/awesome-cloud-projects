#!/usr/bin/env python3
"""
Progressive Web Application with AWS Amplify - CDK Python Application

This CDK application deploys a complete Progressive Web Application infrastructure
using AWS Amplify, including authentication, real-time GraphQL APIs, storage,
and hosting capabilities.

Author: AWS CDK Team
Version: 1.0.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnParameter,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_amplify as amplify,
    aws_cognito as cognito,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_cloudfront as cloudfront,
    aws_logs as logs,
)
from constructs import Construct


class ProgressiveWebAppStack(Stack):
    """
    CDK Stack for Progressive Web Application with AWS Amplify
    
    This stack creates:
    - Amazon Cognito User Pool and Identity Pool for authentication
    - AWS AppSync GraphQL API for real-time data operations
    - DynamoDB table for task storage
    - S3 bucket for file attachments
    - Lambda functions for custom resolvers
    - CloudWatch Log Groups for monitoring
    - IAM roles and policies for secure access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Parameters for customization
        self.project_name = CfnParameter(
            self,
            "ProjectName",
            type="String",
            description="Name of the PWA project",
            default="fullstack-pwa",
            min_length=3,
            max_length=50,
            allowed_pattern="^[a-zA-Z0-9-]+$"
        )

        self.environment_name = CfnParameter(
            self,
            "EnvironmentName",
            type="String",
            description="Environment name (dev, staging, prod)",
            default="dev",
            allowed_values=["dev", "staging", "prod"]
        )

        self.enable_deletion_protection = CfnParameter(
            self,
            "EnableDeletionProtection",
            type="String",
            description="Enable deletion protection for production resources",
            default="false",
            allowed_values=["true", "false"]
        )

        # Create all infrastructure components
        self.cognito_resources = self._create_cognito_resources()
        self.dynamodb_table = self._create_dynamodb_table()
        self.s3_bucket = self._create_s3_bucket()
        self.lambda_functions = self._create_lambda_functions()
        self.appsync_api = self._create_appsync_api()
        self.amplify_app = self._create_amplify_app()

        # Create outputs
        self._create_outputs()

    def _create_cognito_resources(self) -> Dict[str, cognito.CfnResource]:
        """
        Create Amazon Cognito resources for authentication
        
        Returns:
            Dict containing User Pool and Identity Pool resources
        """
        # Create User Pool for user management
        user_pool = cognito.UserPool(
            self,
            "UserPool",
            user_pool_name=f"{self.project_name.value_as_string}-user-pool",
            sign_in_aliases=cognito.SignInAliases(
                username=True,
                email=True
            ),
            self_sign_up_enabled=True,
            user_verification=cognito.UserVerificationConfig(
                email_subject="Verify your email for PWA Task Manager",
                email_body="Thanks for signing up! Your verification code is {####}",
                email_style=cognito.VerificationEmailStyle.CODE
            ),
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(
                    required=True,
                    mutable=True
                ),
                given_name=cognito.StandardAttribute(
                    required=False,
                    mutable=True
                ),
                family_name=cognito.StandardAttribute(
                    required=False,
                    mutable=True
                )
            ),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=False
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY if self.enable_deletion_protection.value_as_string == "false" else RemovalPolicy.RETAIN
        )

        # Create User Pool Client for application access
        user_pool_client = cognito.UserPoolClient(
            self,
            "UserPoolClient",
            user_pool=user_pool,
            user_pool_client_name=f"{self.project_name.value_as_string}-client",
            generate_secret=False,
            auth_flows=cognito.AuthFlow(
                user_password=True,
                user_srp=True
            ),
            o_auth=cognito.OAuthSettings(
                flows=cognito.OAuthFlows(
                    authorization_code_grant=True,
                    implicit_code_grant=True
                ),
                scopes=[
                    cognito.OAuthScope.EMAIL,
                    cognito.OAuthScope.OPENID,
                    cognito.OAuthScope.PROFILE
                ]
            ),
            prevent_user_existence_errors=True,
            refresh_token_validity=Duration.days(30),
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1)
        )

        # Create Identity Pool for AWS resource access
        identity_pool = cognito.CfnIdentityPool(
            self,
            "IdentityPool",
            identity_pool_name=f"{self.project_name.value_as_string}-identity-pool",
            allow_unauthenticated_identities=True,
            cognito_identity_providers=[
                cognito.CfnIdentityPool.CognitoIdentityProviderProperty(
                    client_id=user_pool_client.user_pool_client_id,
                    provider_name=user_pool.user_pool_provider_name
                )
            ]
        )

        # Create IAM roles for authenticated and unauthenticated users
        authenticated_role = iam.Role(
            self,
            "AuthenticatedRole",
            assumed_by=iam.FederatedPrincipal(
                "cognito-identity.amazonaws.com",
                conditions={
                    "StringEquals": {
                        "cognito-identity.amazonaws.com:aud": identity_pool.ref
                    },
                    "ForAnyValue:StringLike": {
                        "cognito-identity.amazonaws.com:amr": "authenticated"
                    }
                }
            ),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AWSMobileClient")
            ]
        )

        unauthenticated_role = iam.Role(
            self,
            "UnauthenticatedRole",
            assumed_by=iam.FederatedPrincipal(
                "cognito-identity.amazonaws.com",
                conditions={
                    "StringEquals": {
                        "cognito-identity.amazonaws.com:aud": identity_pool.ref
                    },
                    "ForAnyValue:StringLike": {
                        "cognito-identity.amazonaws.com:amr": "unauthenticated"
                    }
                }
            )
        )

        # Attach roles to Identity Pool
        cognito.CfnIdentityPoolRoleAttachment(
            self,
            "IdentityPoolRoleAttachment",
            identity_pool_id=identity_pool.ref,
            roles={
                "authenticated": authenticated_role.role_arn,
                "unauthenticated": unauthenticated_role.role_arn
            }
        )

        return {
            "user_pool": user_pool,
            "user_pool_client": user_pool_client,
            "identity_pool": identity_pool,
            "authenticated_role": authenticated_role,
            "unauthenticated_role": unauthenticated_role
        }

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for task storage
        
        Returns:
            DynamoDB Table resource
        """
        table = dynamodb.Table(
            self,
            "TaskTable",
            table_name=f"{self.project_name.value_as_string}-tasks",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="owner",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY if self.enable_deletion_protection.value_as_string == "false" else RemovalPolicy.RETAIN,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Add Global Secondary Index for querying by owner
        table.add_global_secondary_index(
            index_name="owner-index",
            partition_key=dynamodb.Attribute(
                name="owner",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        # Add Global Secondary Index for querying by priority
        table.add_global_secondary_index(
            index_name="priority-index",
            partition_key=dynamodb.Attribute(
                name="priority",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="dueDate",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

        return table

    def _create_s3_bucket(self) -> s3.Bucket:
        """
        Create S3 bucket for file attachments
        
        Returns:
            S3 Bucket resource
        """
        bucket = s3.Bucket(
            self,
            "AttachmentsBucket",
            bucket_name=f"{self.project_name.value_as_string}-attachments-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY if self.enable_deletion_protection.value_as_string == "false" else RemovalPolicy.RETAIN,
            auto_delete_objects=True if self.enable_deletion_protection.value_as_string == "false" else False,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="delete-incomplete-multipart-uploads",
                    abort_incomplete_multipart_upload_after=Duration.days(7),
                    enabled=True
                ),
                s3.LifecycleRule(
                    id="transition-to-ia",
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ],
                    enabled=True
                )
            ]
        )

        # Add CORS configuration for web uploads
        bucket.add_cors_rule(
            allowed_methods=[
                s3.HttpMethods.GET,
                s3.HttpMethods.POST,
                s3.HttpMethods.PUT,
                s3.HttpMethods.DELETE,
                s3.HttpMethods.HEAD
            ],
            allowed_origins=["*"],
            allowed_headers=["*"],
            max_age=3000
        )

        return bucket

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """
        Create Lambda functions for custom resolvers
        
        Returns:
            Dict containing Lambda function resources
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )

        # Add DynamoDB permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                resources=[
                    self.dynamodb_table.table_arn,
                    f"{self.dynamodb_table.table_arn}/*"
                ]
            )
        )

        # Add S3 permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:GetObjectVersion"
                ],
                resources=[
                    f"{self.s3_bucket.bucket_arn}/*"
                ]
            )
        )

        # Create Lambda function for task operations
        task_resolver = lambda_.Function(
            self,
            "TaskResolver",
            function_name=f"{self.project_name.value_as_string}-task-resolver",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=lambda_.Code.from_inline('''
import json
import boto3
import uuid
from datetime import datetime
from typing import Dict, Any, Optional

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('${table_name}')

def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to handle GraphQL resolvers for task operations
    
    Args:
        event: AppSync resolver event
        context: Lambda context
        
    Returns:
        Response data for GraphQL
    """
    print(f"Received event: {json.dumps(event)}")
    
    field_name = event.get('info', {}).get('fieldName')
    arguments = event.get('arguments', {})
    identity = event.get('identity', {})
    
    # Extract user identity
    user_id = identity.get('sub') or identity.get('username', 'anonymous')
    
    try:
        if field_name == 'createTask':
            return create_task(arguments, user_id)
        elif field_name == 'updateTask':
            return update_task(arguments, user_id)
        elif field_name == 'deleteTask':
            return delete_task(arguments, user_id)
        elif field_name == 'getTask':
            return get_task(arguments, user_id)
        elif field_name == 'listTasks':
            return list_tasks(arguments, user_id)
        else:
            raise ValueError(f"Unknown field: {field_name}")
            
    except Exception as e:
        print(f"Error: {str(e)}")
        raise e

def create_task(arguments: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """Create a new task"""
    task_input = arguments.get('input', {})
    
    task_id = str(uuid.uuid4())
    now = datetime.utcnow().isoformat()
    
    task = {
        'id': task_id,
        'owner': user_id,
        'title': task_input.get('title'),
        'description': task_input.get('description'),
        'completed': task_input.get('completed', False),
        'priority': task_input.get('priority', 'MEDIUM'),
        'dueDate': task_input.get('dueDate'),
        'createdAt': now,
        'updatedAt': now
    }
    
    table.put_item(Item=task)
    return task

def update_task(arguments: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """Update an existing task"""
    task_input = arguments.get('input', {})
    task_id = task_input.get('id')
    
    if not task_id:
        raise ValueError("Task ID is required")
    
    # Get existing task to verify ownership
    response = table.get_item(
        Key={'id': task_id, 'owner': user_id}
    )
    
    if 'Item' not in response:
        raise ValueError("Task not found or access denied")
    
    task = response['Item']
    
    # Update fields
    if 'title' in task_input:
        task['title'] = task_input['title']
    if 'description' in task_input:
        task['description'] = task_input['description']
    if 'completed' in task_input:
        task['completed'] = task_input['completed']
    if 'priority' in task_input:
        task['priority'] = task_input['priority']
    if 'dueDate' in task_input:
        task['dueDate'] = task_input['dueDate']
    
    task['updatedAt'] = datetime.utcnow().isoformat()
    
    table.put_item(Item=task)
    return task

def delete_task(arguments: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """Delete a task"""
    task_id = arguments.get('input', {}).get('id')
    
    if not task_id:
        raise ValueError("Task ID is required")
    
    # Get existing task to verify ownership
    response = table.get_item(
        Key={'id': task_id, 'owner': user_id}
    )
    
    if 'Item' not in response:
        raise ValueError("Task not found or access denied")
    
    task = response['Item']
    
    # Delete the task
    table.delete_item(
        Key={'id': task_id, 'owner': user_id}
    )
    
    return task

def get_task(arguments: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """Get a single task"""
    task_id = arguments.get('id')
    
    if not task_id:
        raise ValueError("Task ID is required")
    
    response = table.get_item(
        Key={'id': task_id, 'owner': user_id}
    )
    
    if 'Item' not in response:
        raise ValueError("Task not found or access denied")
    
    return response['Item']

def list_tasks(arguments: Dict[str, Any], user_id: str) -> Dict[str, Any]:
    """List tasks for a user"""
    filter_args = arguments.get('filter', {})
    limit = arguments.get('limit', 20)
    next_token = arguments.get('nextToken')
    
    # Query using the owner-index GSI
    query_params = {
        'IndexName': 'owner-index',
        'KeyConditionExpression': 'owner = :owner',
        'ExpressionAttributeValues': {':owner': user_id},
        'Limit': limit,
        'ScanIndexForward': False  # Sort by createdAt descending
    }
    
    if next_token:
        query_params['ExclusiveStartKey'] = json.loads(next_token)
    
    response = table.query(**query_params)
    
    result = {
        'items': response['Items']
    }
    
    if 'LastEvaluatedKey' in response:
        result['nextToken'] = json.dumps(response['LastEvaluatedKey'])
    
    return result
            '''.replace('${table_name}', self.dynamodb_table.table_name)),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "TABLE_NAME": self.dynamodb_table.table_name,
                "BUCKET_NAME": self.s3_bucket.bucket_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        return {
            "task_resolver": task_resolver
        }

    def _create_appsync_api(self) -> appsync.GraphqlApi:
        """
        Create AWS AppSync GraphQL API
        
        Returns:
            AppSync GraphQL API resource
        """
        # Create CloudWatch log group for AppSync
        log_group = logs.LogGroup(
            self,
            "AppSyncLogGroup",
            log_group_name=f"/aws/appsync/{self.project_name.value_as_string}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create AppSync API
        api = appsync.GraphqlApi(
            self,
            "TaskManagerApi",
            name=f"{self.project_name.value_as_string}-api",
            schema=appsync.SchemaFile.from_asset("schema.graphql"),
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.USER_POOL,
                    user_pool_config=appsync.UserPoolConfig(
                        user_pool=self.cognito_resources["user_pool"]
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
                retention=logs.RetentionDays.ONE_WEEK
            ),
            xray_enabled=True
        )

        # Create Lambda data source
        lambda_data_source = api.add_lambda_data_source(
            "TaskResolverDataSource",
            self.lambda_functions["task_resolver"]
        )

        # Create DynamoDB data source
        dynamodb_data_source = api.add_dynamo_db_data_source(
            "TaskTableDataSource",
            self.dynamodb_table
        )

        # Create resolvers
        resolvers = [
            # Task mutations
            {
                "type_name": "Mutation",
                "field_name": "createTask",
                "data_source": lambda_data_source
            },
            {
                "type_name": "Mutation", 
                "field_name": "updateTask",
                "data_source": lambda_data_source
            },
            {
                "type_name": "Mutation",
                "field_name": "deleteTask", 
                "data_source": lambda_data_source
            },
            # Task queries
            {
                "type_name": "Query",
                "field_name": "getTask",
                "data_source": lambda_data_source
            },
            {
                "type_name": "Query",
                "field_name": "listTasks",
                "data_source": lambda_data_source
            }
        ]

        for resolver_config in resolvers:
            appsync.Resolver(
                self,
                f"{resolver_config['type_name']}{resolver_config['field_name']}Resolver",
                api=api,
                type_name=resolver_config["type_name"],
                field_name=resolver_config["field_name"],
                data_source=resolver_config["data_source"]
            )

        return api

    def _create_amplify_app(self) -> amplify.App:
        """
        Create AWS Amplify application for hosting
        
        Returns:
            Amplify App resource
        """
        # Create IAM role for Amplify
        amplify_role = iam.Role(
            self,
            "AmplifyRole",
            assumed_by=iam.ServicePrincipal("amplify.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("AdministratorAccess-Amplify")
            ]
        )

        # Create Amplify app
        amplify_app = amplify.App(
            self,
            "PWAApp",
            app_name=f"{self.project_name.value_as_string}-pwa",
            description="Progressive Web Application with AWS Amplify",
            role=amplify_role,
            build_spec=amplify.BuildSpec.from_object({
                "version": "1.0",
                "frontend": {
                    "phases": {
                        "preBuild": {
                            "commands": [
                                "npm install"
                            ]
                        },
                        "build": {
                            "commands": [
                                "npm run build"
                            ]
                        }
                    },
                    "artifacts": {
                        "baseDirectory": "build",
                        "files": [
                            "**/*"
                        ]
                    },
                    "cache": {
                        "paths": [
                            "node_modules/**/*"
                        ]
                    }
                }
            }),
            auto_branch_creation=amplify.AutoBranchCreation(
                enabled=True,
                patterns=["feature/*", "develop"],
                auto_build=True,
                pull_request_preview=True
            ),
            environment_variables={
                "AMPLIFY_DIFF_DEPLOY": "false",
                "AMPLIFY_MONOREPO_APP_ROOT": ".",
                "_LIVE_UPDATES": "[{'name':'Amplify CLI','pkg':'@aws-amplify/cli','type':'npm','version':'latest'}]"
            }
        )

        # Create main branch
        main_branch = amplify_app.add_branch(
            "main",
            auto_build=True,
            branch_name="main",
            stage=amplify.Stage.PRODUCTION
        )

        # Create domain (optional - requires custom domain)
        # amplify_app.add_domain("example.com")

        return amplify_app

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs"""
        
        # Cognito outputs
        CfnOutput(
            self,
            "UserPoolId",
            value=self.cognito_resources["user_pool"].user_pool_id,
            description="Cognito User Pool ID",
            export_name=f"{self.stack_name}-UserPoolId"
        )

        CfnOutput(
            self,
            "UserPoolClientId",
            value=self.cognito_resources["user_pool_client"].user_pool_client_id,
            description="Cognito User Pool Client ID",
            export_name=f"{self.stack_name}-UserPoolClientId"
        )

        CfnOutput(
            self,
            "IdentityPoolId",
            value=self.cognito_resources["identity_pool"].ref,
            description="Cognito Identity Pool ID",
            export_name=f"{self.stack_name}-IdentityPoolId"
        )

        # AppSync outputs
        CfnOutput(
            self,
            "GraphQLApiId",
            value=self.appsync_api.api_id,
            description="AppSync GraphQL API ID",
            export_name=f"{self.stack_name}-GraphQLApiId"
        )

        CfnOutput(
            self,
            "GraphQLApiUrl",
            value=self.appsync_api.graphql_url,
            description="AppSync GraphQL API URL",
            export_name=f"{self.stack_name}-GraphQLApiUrl"
        )

        # DynamoDB outputs
        CfnOutput(
            self,
            "TaskTableName",
            value=self.dynamodb_table.table_name,
            description="DynamoDB Task Table Name",
            export_name=f"{self.stack_name}-TaskTableName"
        )

        # S3 outputs
        CfnOutput(
            self,
            "AttachmentsBucketName",
            value=self.s3_bucket.bucket_name,
            description="S3 Attachments Bucket Name",
            export_name=f"{self.stack_name}-AttachmentsBucketName"
        )

        # Amplify outputs
        CfnOutput(
            self,
            "AmplifyAppId",
            value=self.amplify_app.app_id,
            description="Amplify App ID",
            export_name=f"{self.stack_name}-AmplifyAppId"
        )

        CfnOutput(
            self,
            "AmplifyAppUrl",
            value=f"https://{self.amplify_app.default_domain}",
            description="Amplify App URL",
            export_name=f"{self.stack_name}-AmplifyAppUrl"
        )

        # Region output
        CfnOutput(
            self,
            "Region",
            value=self.region,
            description="AWS Region",
            export_name=f"{self.stack_name}-Region"
        )


# Create the CDK app
app = cdk.App()

# Create the stack with enhanced naming
stack_name = app.node.try_get_context("stackName") or "ProgressiveWebAppStack"
env_name = app.node.try_get_context("environment") or "dev"

ProgressiveWebAppStack(
    app,
    f"{stack_name}-{env_name}",
    env=cdk.Environment(
        account=os.getenv("CDK_DEFAULT_ACCOUNT"),
        region=os.getenv("CDK_DEFAULT_REGION")
    ),
    description="Progressive Web Application infrastructure with AWS Amplify, Cognito, AppSync, and DynamoDB",
    tags={
        "Project": "Progressive Web App",
        "Environment": env_name,
        "ManagedBy": "CDK",
        "CostCenter": "Development"
    }
)

app.synth()