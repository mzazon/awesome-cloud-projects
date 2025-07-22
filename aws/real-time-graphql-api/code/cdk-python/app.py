#!/usr/bin/env python3
"""
CDK Python application for Real-Time GraphQL API with AppSync
This application creates a complete GraphQL API with AppSync, DynamoDB, and Cognito authentication.
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    RemovalPolicy,
    Duration,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_cognito as cognito,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct


class GraphQLAppSyncStack(Stack):
    """
    CDK Stack for GraphQL API with AWS AppSync
    
    This stack creates:
    - DynamoDB table for blog posts with GSI for author queries
    - Cognito User Pool for authentication
    - AppSync GraphQL API with schema and resolvers
    - IAM roles and policies for secure access
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.addr[-8:].lower()
        
        # Create DynamoDB table for blog posts
        self.blog_table = self._create_blog_table(unique_suffix)
        
        # Create Cognito User Pool for authentication
        self.user_pool, self.user_pool_client = self._create_user_pool(unique_suffix)
        
        # Create AppSync GraphQL API
        self.graphql_api = self._create_graphql_api(unique_suffix)
        
        # Create data source and resolvers
        self._create_data_source_and_resolvers()
        
        # Create API key for testing
        self._create_api_key()
        
        # Create outputs
        self._create_outputs()

    def _create_blog_table(self, suffix: str) -> dynamodb.Table:
        """
        Create DynamoDB table for blog posts with GSI for author queries
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            DynamoDB table construct
        """
        table = dynamodb.Table(
            self, "BlogPostsTable",
            table_name=f"BlogPosts-{suffix}",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PROVISIONED,
            read_capacity=5,
            write_capacity=5,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )
        
        # Add Global Secondary Index for author queries
        table.add_global_secondary_index(
            index_name="AuthorIndex",
            partition_key=dynamodb.Attribute(
                name="author",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
            read_capacity=5,
            write_capacity=5,
        )
        
        return table

    def _create_user_pool(self, suffix: str) -> tuple[cognito.UserPool, cognito.UserPoolClient]:
        """
        Create Cognito User Pool for authentication
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            Tuple of UserPool and UserPoolClient constructs
        """
        user_pool = cognito.UserPool(
            self, "BlogUserPool",
            user_pool_name=f"BlogUserPool-{suffix}",
            sign_in_aliases=cognito.SignInAliases(email=True),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_uppercase=True,
                require_lowercase=True,
                require_digits=True,
                require_symbols=False,
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY,
        )
        
        user_pool_client = cognito.UserPoolClient(
            self, "BlogUserPoolClient",
            user_pool=user_pool,
            client_name=f"BlogUserPoolClient-{suffix}",
            auth_flows=cognito.AuthFlow(
                admin_user_password=True,
                user_password=True,
                user_srp=True,
            ),
            generate_secret=True,
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1),
            refresh_token_validity=Duration.days(30),
        )
        
        return user_pool, user_pool_client

    def _create_graphql_api(self, suffix: str) -> appsync.GraphqlApi:
        """
        Create AppSync GraphQL API with schema
        
        Args:
            suffix: Unique suffix for resource naming
            
        Returns:
            GraphQL API construct
        """
        # Define GraphQL schema
        schema = appsync.SchemaFile.from_asset("schema.graphql")
        
        # Create the GraphQL API
        api = appsync.GraphqlApi(
            self, "BlogGraphQLApi",
            name=f"blog-api-{suffix}",
            schema=schema,
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.USER_POOL,
                    user_pool_config=appsync.UserPoolConfig(
                        user_pool=self.user_pool,
                        default_action=appsync.UserPoolDefaultAction.ALLOW,
                    )
                ),
                additional_authorization_modes=[
                    appsync.AuthorizationMode(
                        authorization_type=appsync.AuthorizationType.API_KEY,
                        api_key_config=appsync.ApiKeyConfig(
                            expires=cdk.Expiration.after(Duration.days(30))
                        )
                    )
                ]
            ),
            log_config=appsync.LogConfig(
                retention=logs.RetentionDays.ONE_WEEK,
                field_log_level=appsync.FieldLogLevel.ALL,
            ),
            x_ray_enabled=True,
        )
        
        return api

    def _create_data_source_and_resolvers(self) -> None:
        """
        Create DynamoDB data source and GraphQL resolvers
        """
        # Create DynamoDB data source
        data_source = self.graphql_api.add_dynamo_db_data_source(
            "BlogPostsDataSource",
            table=self.blog_table,
            description="DynamoDB data source for blog posts",
        )
        
        # Create resolvers
        self._create_resolvers(data_source)

    def _create_resolvers(self, data_source: appsync.DynamoDbDataSource) -> None:
        """
        Create GraphQL resolvers for all operations
        
        Args:
            data_source: DynamoDB data source
        """
        # getBlogPost resolver
        data_source.create_resolver(
            "getBlogPostResolver",
            type_name="Query",
            field_name="getBlogPost",
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
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """),
        )
        
        # createBlogPost resolver
        data_source.create_resolver(
            "createBlogPostResolver",
            type_name="Mutation",
            field_name="createBlogPost",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($id = $util.autoId())
#set($createdAt = $util.time.nowISO8601())
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($id)
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
        "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
        "author": $util.dynamodb.toDynamoDBJson($ctx.identity.username),
        "createdAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "updatedAt": $util.dynamodb.toDynamoDBJson($createdAt),
        "tags": $util.dynamodb.toDynamoDBJson($ctx.args.input.tags),
        "published": $util.dynamodb.toDynamoDBJson($ctx.args.input.published)
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """),
        )
        
        # updateBlogPost resolver
        data_source.create_resolver(
            "updateBlogPostResolver",
            type_name="Mutation",
            field_name="updateBlogPost",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($updatedAt = $util.time.nowISO8601())
{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
    },
    "update": {
        "expression": "SET updatedAt = :updatedAt",
        "expressionNames": {},
        "expressionValues": {
            ":updatedAt": $util.dynamodb.toDynamoDBJson($updatedAt)
        }
    },
    "condition": {
        "expression": "author = :author",
        "expressionValues": {
            ":author": $util.dynamodb.toDynamoDBJson($ctx.identity.username)
        }
    }
}
#if($ctx.args.input.title)
    #set($update.expression = $update.expression + ", title = :title")
    $util.qr($update.expressionValues.put(":title", $util.dynamodb.toDynamoDBJson($ctx.args.input.title)))
#end
#if($ctx.args.input.content)
    #set($update.expression = $update.expression + ", content = :content")
    $util.qr($update.expressionValues.put(":content", $util.dynamodb.toDynamoDBJson($ctx.args.input.content)))
#end
#if($ctx.args.input.tags)
    #set($update.expression = $update.expression + ", tags = :tags")
    $util.qr($update.expressionValues.put(":tags", $util.dynamodb.toDynamoDBJson($ctx.args.input.tags)))
#end
#if($ctx.args.input.published != null)
    #set($update.expression = $update.expression + ", published = :published")
    $util.qr($update.expressionValues.put(":published", $util.dynamodb.toDynamoDBJson($ctx.args.input.published)))
#end
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """),
        )
        
        # deleteBlogPost resolver
        data_source.create_resolver(
            "deleteBlogPostResolver",
            type_name="Mutation",
            field_name="deleteBlogPost",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "DeleteItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
    },
    "condition": {
        "expression": "author = :author",
        "expressionValues": {
            ":author": $util.dynamodb.toDynamoDBJson($ctx.identity.username)
        }
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """),
        )
        
        # listBlogPosts resolver
        data_source.create_resolver(
            "listBlogPostsResolver",
            type_name="Query",
            field_name="listBlogPosts",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "Scan",
    #if($ctx.args.limit)
    "limit": $ctx.args.limit,
    #end
    #if($ctx.args.nextToken)
    "nextToken": "$ctx.args.nextToken",
    #end
    "filter": {
        "expression": "published = :published",
        "expressionValues": {
            ":published": $util.dynamodb.toDynamoDBJson(true)
        }
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
{
    "items": $util.toJson($ctx.result.items),
    #if($ctx.result.nextToken)
    "nextToken": "$ctx.result.nextToken"
    #end
}
            """),
        )
        
        # listBlogPostsByAuthor resolver
        data_source.create_resolver(
            "listBlogPostsByAuthorResolver",
            type_name="Query",
            field_name="listBlogPostsByAuthor",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "Query",
    "index": "AuthorIndex",
    "query": {
        "expression": "author = :author",
        "expressionValues": {
            ":author": $util.dynamodb.toDynamoDBJson($ctx.args.author)
        }
    },
    #if($ctx.args.limit)
    "limit": $ctx.args.limit,
    #end
    #if($ctx.args.nextToken)
    "nextToken": "$ctx.args.nextToken",
    #end
    "scanIndexForward": false
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
{
    "items": $util.toJson($ctx.result.items),
    #if($ctx.result.nextToken)
    "nextToken": "$ctx.result.nextToken"
    #end
}
            """),
        )

    def _create_api_key(self) -> None:
        """
        Create API key for testing purposes
        """
        self.api_key = appsync.ApiKey(
            self, "BlogApiKey",
            api=self.graphql_api,
            description="API key for testing blog GraphQL API",
            expires=cdk.Expiration.after(Duration.days(30)),
        )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for important resources
        """
        CfnOutput(
            self, "GraphQLApiId",
            value=self.graphql_api.api_id,
            description="AppSync GraphQL API ID",
            export_name=f"{self.stack_name}-GraphQLApiId",
        )
        
        CfnOutput(
            self, "GraphQLApiUrl",
            value=self.graphql_api.graphql_url,
            description="AppSync GraphQL API URL",
            export_name=f"{self.stack_name}-GraphQLApiUrl",
        )
        
        CfnOutput(
            self, "GraphQLApiKey",
            value=self.api_key.api_key,
            description="AppSync API Key for testing",
            export_name=f"{self.stack_name}-GraphQLApiKey",
        )
        
        CfnOutput(
            self, "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID",
            export_name=f"{self.stack_name}-UserPoolId",
        )
        
        CfnOutput(
            self, "UserPoolClientId",
            value=self.user_pool_client.user_pool_client_id,
            description="Cognito User Pool Client ID",
            export_name=f"{self.stack_name}-UserPoolClientId",
        )
        
        CfnOutput(
            self, "DynamoDBTableName",
            value=self.blog_table.table_name,
            description="DynamoDB table name for blog posts",
            export_name=f"{self.stack_name}-DynamoDBTableName",
        )
        
        CfnOutput(
            self, "RealtimeUrl",
            value=self.graphql_api.graphql_url.replace("graphql", "realtime"),
            description="AppSync real-time subscription URL",
            export_name=f"{self.stack_name}-RealtimeUrl",
        )


# CDK App
app = cdk.App()

# Get environment configuration
env = cdk.Environment(
    account=os.getenv('CDK_DEFAULT_ACCOUNT'),
    region=os.getenv('CDK_DEFAULT_REGION', 'us-east-1')
)

# Create the stack
GraphQLAppSyncStack(
    app, 
    "GraphQLAppSyncStack",
    env=env,
    description="Complete GraphQL API with AWS AppSync, DynamoDB, and Cognito authentication"
)

# Synthesize the app
app.synth()