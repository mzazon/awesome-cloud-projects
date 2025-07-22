#!/usr/bin/env python3
"""
CDK Python application for Full-Stack Real-Time Applications with Amplify and AppSync GraphQL Subscriptions.

This CDK application creates the complete infrastructure for a real-time chat application
using AWS AppSync, Amazon Cognito, DynamoDB, and Lambda functions.
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_appsync as appsync,
    aws_cognito as cognito,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
)
from constructs import Construct
import os
from typing import Dict, List


class RealtimeAppStack(Stack):
    """
    CDK Stack for Real-Time Chat Application Infrastructure.
    
    This stack creates:
    - Amazon Cognito User Pool with groups for authentication
    - AWS AppSync GraphQL API with real-time subscriptions
    - DynamoDB tables for data storage with GSI indexes
    - Lambda functions for custom real-time operations
    - IAM roles and policies for secure resource access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.app_name = self.node.try_get_context("app_name") or "realtime-app"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Create Cognito User Pool for authentication
        self.user_pool = self._create_user_pool()
        
        # Create DynamoDB tables for data storage
        self.tables = self._create_dynamodb_tables()
        
        # Create Lambda functions for real-time operations
        self.lambda_functions = self._create_lambda_functions()
        
        # Create AppSync GraphQL API
        self.appsync_api = self._create_appsync_api()
        
        # Create data sources and resolvers
        self._create_data_sources_and_resolvers()
        
        # Create stack outputs
        self._create_outputs()

    def _create_user_pool(self) -> cognito.UserPool:
        """Create Cognito User Pool with groups for role-based access control."""
        
        # Create User Pool
        user_pool = cognito.UserPool(
            self, "RealtimeUserPool",
            user_pool_name=f"{self.app_name}-user-pool-{self.environment}",
            self_sign_up_enabled=True,
            sign_in_aliases=cognito.SignInAliases(
                email=True,
                username=True
            ),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            standard_attributes=cognito.StandardAttributes(
                email=cognito.StandardAttribute(
                    required=True,
                    mutable=True
                ),
                given_name=cognito.StandardAttribute(
                    required=True,
                    mutable=True
                ),
                family_name=cognito.StandardAttribute(
                    required=True,
                    mutable=True
                )
            ),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=True
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY
        )

        # Create User Pool Client
        user_pool_client = cognito.UserPoolClient(
            self, "RealtimeUserPoolClient",
            user_pool=user_pool,
            user_pool_client_name=f"{self.app_name}-client-{self.environment}",
            auth_flows=cognito.AuthFlow(
                user_password=True,
                user_srp=True,
                admin_user_password=True
            ),
            generate_secret=False,
            prevent_user_existence_errors=True,
            refresh_token_validity=Duration.days(30),
            access_token_validity=Duration.minutes(60),
            id_token_validity=Duration.minutes(60)
        )

        # Create Identity Pool
        identity_pool = cognito.CfnIdentityPool(
            self, "RealtimeIdentityPool",
            identity_pool_name=f"{self.app_name}-identity-pool-{self.environment}",
            allow_unauthenticated_identities=False,
            cognito_identity_providers=[
                cognito.CfnIdentityPool.CognitoIdentityProviderProperty(
                    client_id=user_pool_client.user_pool_client_id,
                    provider_name=user_pool.user_pool_provider_name
                )
            ]
        )

        # Create User Groups
        user_groups = [
            {"name": "Admins", "description": "Administrator users with full access"},
            {"name": "Moderators", "description": "Moderator users with room management access"},
            {"name": "Users", "description": "Regular users with basic chat access"}
        ]

        for group in user_groups:
            cognito.CfnUserPoolGroup(
                self, f"UserGroup{group['name']}",
                user_pool_id=user_pool.user_pool_id,
                group_name=group["name"],
                description=group["description"]
            )

        return user_pool

    def _create_dynamodb_tables(self) -> Dict[str, dynamodb.Table]:
        """Create DynamoDB tables for chat data storage with GSI indexes."""
        
        tables = {}

        # ChatRoom table
        tables["ChatRoom"] = dynamodb.Table(
            self, "ChatRoomTable",
            table_name=f"{self.app_name}-chatroom-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Message table with GSI for room-based queries
        tables["Message"] = dynamodb.Table(
            self, "MessageTable",
            table_name=f"{self.app_name}-message-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Add GSI for querying messages by room
        tables["Message"].add_global_secondary_index(
            index_name="byRoom",
            partition_key=dynamodb.Attribute(
                name="chatRoomId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            )
        )

        # Add GSI for querying replies
        tables["Message"].add_global_secondary_index(
            index_name="byReply",
            partition_key=dynamodb.Attribute(
                name="replyToId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            )
        )

        # Reaction table
        tables["Reaction"] = dynamodb.Table(
            self, "ReactionTable",
            table_name=f"{self.app_name}-reaction-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Add GSI for querying reactions by message
        tables["Reaction"].add_global_secondary_index(
            index_name="byMessage",
            partition_key=dynamodb.Attribute(
                name="messageId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            )
        )

        # UserPresence table
        tables["UserPresence"] = dynamodb.Table(
            self, "UserPresenceTable",
            table_name=f"{self.app_name}-userpresence-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        # Notification table
        tables["Notification"] = dynamodb.Table(
            self, "NotificationTable",
            table_name=f"{self.app_name}-notification-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED
        )

        return tables

    def _create_lambda_functions(self) -> Dict[str, lambda_.Function]:
        """Create Lambda functions for real-time operations."""
        
        functions = {}

        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "RealtimeLambdaRole",
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
                    "dynamodb:PutItem",
                    "dynamodb:GetItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:DeleteItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                resources=[
                    table.table_arn for table in self.tables.values()
                ] + [
                    f"{table.table_arn}/index/*" for table in self.tables.values()
                ]
            )
        )

        # Add AppSync permissions for publishing to subscriptions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "appsync:GraphQL"
                ],
                resources=["*"]  # Will be restricted after AppSync API creation
            )
        )

        # Real-time handler function
        functions["RealtimeHandler"] = lambda_.Function(
            self, "RealtimeHandlerFunction",
            function_name=f"{self.app_name}-realtime-handler-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_realtime_handler_code()),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment={
                "CHATROOM_TABLE": self.tables["ChatRoom"].table_name,
                "MESSAGE_TABLE": self.tables["Message"].table_name,
                "REACTION_TABLE": self.tables["Reaction"].table_name,
                "PRESENCE_TABLE": self.tables["UserPresence"].table_name,
                "NOTIFICATION_TABLE": self.tables["Notification"].table_name,
                "AWS_REGION": self.region
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Post-confirmation trigger for user setup
        functions["PostConfirmation"] = lambda_.Function(
            self, "PostConfirmationFunction",
            function_name=f"{self.app_name}-post-confirmation-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_post_confirmation_code()),
            role=lambda_role,
            timeout=Duration.seconds(30),
            memory_size=128,
            environment={
                "PRESENCE_TABLE": self.tables["UserPresence"].table_name,
                "AWS_REGION": self.region
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        return functions

    def _create_appsync_api(self) -> appsync.GraphqlApi:
        """Create AppSync GraphQL API with real-time subscriptions."""
        
        # Create AppSync API
        api = appsync.GraphqlApi(
            self, "RealtimeGraphQLAPI",
            name=f"{self.app_name}-api-{self.environment}",
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
                        authorization_type=appsync.AuthorizationType.API_KEY
                    )
                ]
            ),
            log_config=appsync.LogConfig(
                field_log_level=appsync.FieldLogLevel.ALL,
                retention=logs.RetentionDays.ONE_WEEK
            ),
            x_ray_enabled=True
        )

        # Create API Key for public access
        api.add_api_key(
            "RealtimeAPIKey",
            expires=cdk.Expiration.after(Duration.days(365))
        )

        return api

    def _create_data_sources_and_resolvers(self) -> None:
        """Create AppSync data sources and resolvers."""
        
        # Create DynamoDB data sources
        data_sources = {}
        
        for table_name, table in self.tables.items():
            data_sources[table_name] = self.appsync_api.add_dynamo_db_data_source(
                f"{table_name}DataSource",
                table=table,
                description=f"Data source for {table_name} table"
            )

        # Create Lambda data source
        lambda_data_source = self.appsync_api.add_lambda_data_source(
            "RealtimeHandlerDataSource",
            lambda_function=self.lambda_functions["RealtimeHandler"],
            description="Data source for real-time operations"
        )

        # Create resolvers for queries
        self._create_query_resolvers(data_sources)
        
        # Create resolvers for mutations
        self._create_mutation_resolvers(data_sources, lambda_data_source)
        
        # Create resolvers for subscriptions
        self._create_subscription_resolvers()

    def _create_query_resolvers(self, data_sources: Dict[str, appsync.DynamoDbDataSource]) -> None:
        """Create GraphQL query resolvers."""
        
        # List ChatRooms resolver
        data_sources["ChatRoom"].create_resolver(
            "ListChatRoomsResolver",
            type_name="Query",
            field_name="listChatRooms",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2017-02-28",
                "operation": "Scan",
                "limit": $util.defaultIfNull($ctx.args.limit, 20),
                "nextToken": $util.toJson($util.defaultIfNullOrBlank($ctx.args.nextToken, null))
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "items": $util.toJson($ctx.result.items),
                "nextToken": $util.toJson($util.defaultIfNullOrBlank($ctx.result.nextToken, null))
            }
            """)
        )

        # Get ChatRoom resolver
        data_sources["ChatRoom"].create_resolver(
            "GetChatRoomResolver",
            type_name="Query",
            field_name="getChatRoom",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2017-02-28",
                "operation": "GetItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
                }
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            $util.toJson($ctx.result)
            """)
        )

        # Messages by Room resolver
        data_sources["Message"].create_resolver(
            "MessagesByRoomResolver",
            type_name="Query",
            field_name="messagesByRoom",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2017-02-28",
                "operation": "Query",
                "index": "byRoom",
                "query": {
                    "expression": "chatRoomId = :chatRoomId",
                    "expressionValues": {
                        ":chatRoomId": $util.dynamodb.toDynamoDBJson($ctx.args.chatRoomId)
                    }
                },
                "limit": $util.defaultIfNull($ctx.args.limit, 50),
                "nextToken": $util.toJson($util.defaultIfNullOrBlank($ctx.args.nextToken, null)),
                "scanIndexForward": $util.defaultIfNull($ctx.args.sortDirection, true)
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "items": $util.toJson($ctx.result.items),
                "nextToken": $util.toJson($util.defaultIfNullOrBlank($ctx.result.nextToken, null))
            }
            """)
        )

    def _create_mutation_resolvers(self, data_sources: Dict[str, appsync.DynamoDbDataSource], lambda_data_source: appsync.LambdaDataSource) -> None:
        """Create GraphQL mutation resolvers."""
        
        # Create ChatRoom resolver
        data_sources["ChatRoom"].create_resolver(
            "CreateChatRoomResolver",
            type_name="Mutation",
            field_name="createChatRoom",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2017-02-28",
                "operation": "PutItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
                },
                "attributeValues": {
                    "name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
                    "description": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($ctx.args.input.description, "")),
                    "isPrivate": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($ctx.args.input.isPrivate, false)),
                    "createdBy": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
                    "members": $util.dynamodb.toDynamoDBJson([$ctx.identity.sub]),
                    "messageCount": $util.dynamodb.toDynamoDBJson(0),
                    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
                }
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            $util.toJson($ctx.result)
            """)
        )

        # Create Message resolver
        data_sources["Message"].create_resolver(
            "CreateMessageResolver",
            type_name="Mutation",
            field_name="createMessage",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2017-02-28",
                "operation": "PutItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
                },
                "attributeValues": {
                    "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
                    "messageType": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($ctx.args.input.messageType, "TEXT")),
                    "author": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
                    "authorName": $util.dynamodb.toDynamoDBJson($ctx.args.input.authorName),
                    "chatRoomId": $util.dynamodb.toDynamoDBJson($ctx.args.input.chatRoomId),
                    "replyToId": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($ctx.args.input.replyToId, null)),
                    "attachments": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($ctx.args.input.attachments, [])),
                    "isEdited": $util.dynamodb.toDynamoDBJson(false),
                    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
                }
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            $util.toJson($ctx.result)
            """)
        )

        # Create Reaction resolver
        data_sources["Reaction"].create_resolver(
            "CreateReactionResolver",
            type_name="Mutation",
            field_name="createReaction",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2017-02-28",
                "operation": "PutItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($util.autoId())
                },
                "attributeValues": {
                    "emoji": $util.dynamodb.toDynamoDBJson($ctx.args.input.emoji),
                    "author": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
                    "authorName": $util.dynamodb.toDynamoDBJson($ctx.args.input.authorName),
                    "messageId": $util.dynamodb.toDynamoDBJson($ctx.args.input.messageId),
                    "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                    "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
                }
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            $util.toJson($ctx.result)
            """)
        )

        # Lambda-based real-time operation resolvers
        lambda_operations = [
            "startTyping",
            "stopTyping",
            "updatePresence",
            "joinRoom",
            "leaveRoom"
        ]

        for operation in lambda_operations:
            lambda_data_source.create_resolver(
                f"{operation.capitalize()}Resolver",
                type_name="Mutation",
                field_name=operation,
                request_mapping_template=appsync.MappingTemplate.from_string(f"""
                {{
                    "version": "2017-02-28",
                    "operation": "Invoke",
                    "payload": {{
                        "field": "{operation}",
                        "arguments": $util.toJson($ctx.args),
                        "identity": $util.toJson($ctx.identity),
                        "source": $util.toJson($ctx.source),
                        "request": $util.toJson($ctx.request)
                    }}
                }}
                """),
                response_mapping_template=appsync.MappingTemplate.from_string("""
                $util.toJson($ctx.result)
                """)
            )

    def _create_subscription_resolvers(self) -> None:
        """Create GraphQL subscription resolvers."""
        
        # Subscription resolvers are automatically created by AppSync
        # based on the @aws_subscribe directive in the schema
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation stack outputs."""
        
        CfnOutput(
            self, "GraphQLAPIId",
            value=self.appsync_api.api_id,
            description="AppSync GraphQL API ID"
        )

        CfnOutput(
            self, "GraphQLAPIURL",
            value=self.appsync_api.graphql_url,
            description="AppSync GraphQL API URL"
        )

        CfnOutput(
            self, "GraphQLAPIKey",
            value=self.appsync_api.api_key or "No API Key",
            description="AppSync GraphQL API Key"
        )

        CfnOutput(
            self, "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID"
        )

        CfnOutput(
            self, "UserPoolClientId",
            value=self.user_pool.user_pool_client_id,
            description="Cognito User Pool Client ID"
        )

        CfnOutput(
            self, "Region",
            value=self.region,
            description="AWS Region"
        )

        # Table names
        for table_name, table in self.tables.items():
            CfnOutput(
                self, f"{table_name}TableName",
                value=table.table_name,
                description=f"{table_name} DynamoDB Table Name"
            )

    def _get_realtime_handler_code(self) -> str:
        """Return the Lambda function code for real-time operations."""
        
        return '''
import json
import boto3
import os
from datetime import datetime
from typing import Dict, Any

dynamodb = boto3.resource('dynamodb')
appsync = boto3.client('appsync')

# Environment variables
CHATROOM_TABLE = os.environ['CHATROOM_TABLE']
MESSAGE_TABLE = os.environ['MESSAGE_TABLE']
REACTION_TABLE = os.environ['REACTION_TABLE']
PRESENCE_TABLE = os.environ['PRESENCE_TABLE']
NOTIFICATION_TABLE = os.environ['NOTIFICATION_TABLE']

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Lambda function handler for real-time operations.
    
    Handles typing indicators, presence updates, and room management.
    """
    print(f"Real-time event received: {json.dumps(event, indent=2)}")
    
    field = event.get('field')
    arguments = event.get('arguments', {})
    identity = event.get('identity', {})
    
    user_id = identity.get('claims', {}).get('sub')
    username = identity.get('claims', {}).get('cognito:username', 'Unknown')
    
    if not user_id:
        raise Exception("User not authenticated")
    
    try:
        if field == 'startTyping':
            return handle_typing_start(arguments.get('chatRoomId'), user_id, username)
        elif field == 'stopTyping':
            return handle_typing_stop(arguments.get('chatRoomId'), user_id, username)
        elif field == 'updatePresence':
            return update_user_presence(user_id, username, arguments.get('status'), arguments.get('currentRoom'))
        elif field == 'joinRoom':
            return join_chat_room(arguments.get('roomId'), user_id, username)
        elif field == 'leaveRoom':
            return leave_chat_room(arguments.get('roomId'), user_id, username)
        else:
            raise Exception(f"Unknown field: {field}")
    except Exception as e:
        print(f"Error processing real-time operation: {str(e)}")
        raise Exception(f"Failed to process {field}: {str(e)}")

def handle_typing_start(chat_room_id: str, user_id: str, username: str) -> Dict[str, Any]:
    """Handle typing indicator start event."""
    typing_indicator = {
        'userId': user_id,
        'userName': username,
        'chatRoomId': chat_room_id,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    }
    
    print(f"User {username} started typing in room {chat_room_id}")
    return typing_indicator

def handle_typing_stop(chat_room_id: str, user_id: str, username: str) -> Dict[str, Any]:
    """Handle typing indicator stop event."""
    typing_indicator = {
        'userId': user_id,
        'userName': username,
        'chatRoomId': chat_room_id,
        'timestamp': datetime.utcnow().isoformat() + 'Z'
    }
    
    print(f"User {username} stopped typing in room {chat_room_id}")
    return typing_indicator

def update_user_presence(user_id: str, username: str, status: str, current_room: str = None) -> Dict[str, Any]:
    """Update user presence status."""
    table = dynamodb.Table(PRESENCE_TABLE)
    
    presence = {
        'id': user_id,
        'userId': user_id,
        'userName': username,
        'status': status,
        'lastSeen': datetime.utcnow().isoformat() + 'Z',
        'currentRoom': current_room,
        'deviceInfo': 'Web',
        'updatedAt': datetime.utcnow().isoformat() + 'Z'
    }
    
    # Remove None values
    presence = {k: v for k, v in presence.items() if v is not None}
    
    table.put_item(Item=presence)
    
    print(f"Updated presence for user {username}: {status}")
    return presence

def join_chat_room(room_id: str, user_id: str, username: str) -> Dict[str, Any]:
    """Add user to chat room members."""
    table = dynamodb.Table(CHATROOM_TABLE)
    
    try:
        # Add user to room members and update last activity
        response = table.update_item(
            Key={'id': room_id},
            UpdateExpression='ADD members :user_set SET lastActivity = :timestamp',
            ExpressionAttributeValues={
                ':user_set': {user_id},
                ':timestamp': datetime.utcnow().isoformat() + 'Z'
            },
            ReturnValues='ALL_NEW'
        )
        
        # Update user presence
        update_user_presence(user_id, username, 'ONLINE', room_id)
        
        print(f"User {username} joined room {room_id}")
        return response['Attributes']
        
    except Exception as e:
        print(f"Error joining room: {str(e)}")
        raise

def leave_chat_room(room_id: str, user_id: str, username: str) -> Dict[str, Any]:
    """Remove user from chat room members."""
    table = dynamodb.Table(CHATROOM_TABLE)
    
    try:
        # Remove user from room members and update last activity
        response = table.update_item(
            Key={'id': room_id},
            UpdateExpression='DELETE members :user_set SET lastActivity = :timestamp',
            ExpressionAttributeValues={
                ':user_set': {user_id},
                ':timestamp': datetime.utcnow().isoformat() + 'Z'
            },
            ReturnValues='ALL_NEW'
        )
        
        # Update user presence
        update_user_presence(user_id, username, 'ONLINE', None)
        
        print(f"User {username} left room {room_id}")
        return response['Attributes']
        
    except Exception as e:
        print(f"Error leaving room: {str(e)}")
        raise
'''

    def _get_post_confirmation_code(self) -> str:
        """Return the Lambda function code for post-confirmation trigger."""
        
        return '''
import json
import boto3
import os
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
PRESENCE_TABLE = os.environ['PRESENCE_TABLE']

def handler(event, context):
    """
    Cognito post-confirmation trigger to initialize user presence.
    """
    print(f"Post-confirmation event: {json.dumps(event, indent=2)}")
    
    try:
        user_attributes = event['request']['userAttributes']
        user_id = user_attributes['sub']
        username = user_attributes.get('cognito:username', user_attributes.get('email', 'Unknown'))
        
        # Initialize user presence
        table = dynamodb.Table(PRESENCE_TABLE)
        
        presence = {
            'id': user_id,
            'userId': user_id,
            'userName': username,
            'status': 'ONLINE',
            'lastSeen': datetime.utcnow().isoformat() + 'Z',
            'deviceInfo': 'Web',
            'createdAt': datetime.utcnow().isoformat() + 'Z',
            'updatedAt': datetime.utcnow().isoformat() + 'Z'
        }
        
        table.put_item(Item=presence)
        
        print(f"Initialized presence for user {username}")
        
    except Exception as e:
        print(f"Error in post-confirmation: {str(e)}")
        # Don't raise exception to avoid blocking user confirmation
    
    return event
'''


def main():
    """Main function to create and deploy the CDK app."""
    
    app = cdk.App()
    
    # Get configuration from context
    app_name = app.node.try_get_context("app_name") or "realtime-app"
    environment = app.node.try_get_context("environment") or "dev"
    
    # Create the stack
    RealtimeAppStack(
        app, 
        f"RealtimeAppStack-{environment}",
        stack_name=f"{app_name}-stack-{environment}",
        description=f"Full-Stack Real-Time Applications with Amplify and AppSync - {environment}",
        env=cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        ),
        tags={
            "Project": "RealtimeApp",
            "Environment": environment,
            "ManagedBy": "CDK"
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()