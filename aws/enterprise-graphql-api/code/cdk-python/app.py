#!/usr/bin/env python3
"""
AWS CDK Python application for GraphQL APIs with AppSync and DynamoDB
Based on the recipe: Enterprise GraphQL API Architecture

This CDK application creates a comprehensive GraphQL API ecosystem using AWS AppSync
with multiple data sources including DynamoDB for transactional data, OpenSearch for
advanced search capabilities, and Lambda for custom business logic execution.
"""

import os
from aws_cdk import (
    App,
    Stack,
    StackProps,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_opensearch as opensearch,
    aws_lambda as _lambda,
    aws_cognito as cognito,
    aws_iam as iam,
    aws_logs as logs,
    aws_s3 as s3,
    aws_s3_deployment as s3deploy,
)
from constructs import Construct
from typing import Dict, Any


class GraphQLAppSyncStack(Stack):
    """
    CDK Stack for GraphQL APIs with AppSync and DynamoDB
    
    This stack implements an enterprise-grade GraphQL API architecture with:
    - AWS AppSync GraphQL API with multiple authentication methods
    - DynamoDB tables with Global Secondary Indexes for efficient querying
    - OpenSearch Service for advanced search capabilities
    - Lambda functions for custom business logic
    - Cognito User Pool for user authentication
    - Comprehensive monitoring and logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Project configuration
        self.project_name = "ecommerce-api"
        
        # Create DynamoDB tables
        self._create_dynamodb_tables()
        
        # Create OpenSearch domain
        self._create_opensearch_domain()
        
        # Create Cognito User Pool
        self._create_cognito_user_pool()
        
        # Create Lambda functions
        self._create_lambda_functions()
        
        # Create AppSync GraphQL API
        self._create_appsync_api()
        
        # Create data sources
        self._create_data_sources()
        
        # Create resolvers
        self._create_resolvers()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_tables(self) -> None:
        """Create DynamoDB tables with Global Secondary Indexes"""
        
        # Products table with multiple GSIs for efficient querying
        self.products_table = dynamodb.Table(
            self, "ProductsTable",
            table_name=f"{self.project_name}-products",
            partition_key=dynamodb.Attribute(
                name="productId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )
        
        # Category index for efficient category-based queries
        self.products_table.add_global_secondary_index(
            index_name="CategoryIndex",
            partition_key=dynamodb.Attribute(
                name="category",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        # Price range index for filtering by price
        self.products_table.add_global_secondary_index(
            index_name="PriceRangeIndex",
            partition_key=dynamodb.Attribute(
                name="priceRange",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        # Users table for user management
        self.users_table = dynamodb.Table(
            self, "UsersTable",
            table_name=f"{self.project_name}-users",
            partition_key=dynamodb.Attribute(
                name="userId",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            point_in_time_recovery=True,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )
        
        # User type index for role-based queries
        self.users_table.add_global_secondary_index(
            index_name="UserTypeIndex",
            partition_key=dynamodb.Attribute(
                name="userType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )
        
        # Analytics table for real-time metrics
        self.analytics_table = dynamodb.Table(
            self, "AnalyticsTable",
            table_name=f"{self.project_name}-analytics",
            partition_key=dynamodb.Attribute(
                name="metricId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            time_to_live_attribute="ttl",
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
        )

    def _create_opensearch_domain(self) -> None:
        """Create OpenSearch domain for advanced search capabilities"""
        
        # Create a custom log group for OpenSearch
        self.opensearch_log_group = logs.LogGroup(
            self, "OpenSearchLogGroup",
            log_group_name=f"/aws/opensearch/domains/{self.project_name}-search",
            removal_policy=RemovalPolicy.DESTROY,
            retention=logs.RetentionDays.ONE_WEEK
        )
        
        # OpenSearch domain for full-text search
        self.opensearch_domain = opensearch.Domain(
            self, "OpenSearchDomain",
            domain_name=f"{self.project_name}-search",
            version=opensearch.EngineVersion.OPENSEARCH_2_3,
            capacity=opensearch.CapacityConfig(
                data_nodes=1,
                data_node_instance_type="t3.small.search"
            ),
            ebs=opensearch.EbsOptions(
                enabled=True,
                volume_type=opensearch.EbsDeviceVolumeType.GP3,
                volume_size=20
            ),
            zone_awareness=opensearch.ZoneAwarenessConfig(
                enabled=False  # Single node for development
            ),
            logging=opensearch.LoggingOptions(
                slow_search_log_enabled=True,
                app_log_enabled=True,
                slow_index_log_enabled=True,
                slow_search_log_group=self.opensearch_log_group,
                app_log_group=self.opensearch_log_group,
                slow_index_log_group=self.opensearch_log_group
            ),
            encryption_at_rest=opensearch.EncryptionAtRestOptions(enabled=True),
            node_to_node_encryption=True,
            enforce_https=True,
            tls_security_policy=opensearch.TLSSecurityPolicy.TLS_1_2,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
        )
        
        # Allow access from the account
        self.opensearch_domain.add_access_policies(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                principals=[iam.AccountRootPrincipal()],
                actions=["es:*"],
                resources=[f"{self.opensearch_domain.domain_arn}/*"]
            )
        )

    def _create_cognito_user_pool(self) -> None:
        """Create Cognito User Pool with custom attributes"""
        
        # User Pool with custom attributes and security policies
        self.user_pool = cognito.UserPool(
            self, "UserPool",
            user_pool_name=f"{self.project_name}-users",
            self_sign_up_enabled=True,
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
            sign_in_aliases=cognito.SignInAliases(email=True),
            password_policy=cognito.PasswordPolicy(
                min_length=8,
                require_lowercase=True,
                require_uppercase=True,
                require_digits=True,
                require_symbols=True
            ),
            account_recovery=cognito.AccountRecovery.EMAIL_ONLY,
            removal_policy=RemovalPolicy.DESTROY,  # Use RETAIN for production
            custom_attributes={
                "user_type": cognito.StringAttribute(mutable=True),
                "company": cognito.StringAttribute(mutable=True)
            }
        )
        
        # User Pool Client for AppSync authentication
        self.user_pool_client = self.user_pool.add_client(
            "AppSyncClient",
            user_pool_client_name=f"{self.project_name}-client",
            auth_flows=cognito.AuthFlow(
                admin_user_password=True,
                custom=True,
                user_password=True,
                user_srp=True
            ),
            prevent_user_existence_errors=True,
            access_token_validity=Duration.minutes(60),
            id_token_validity=Duration.minutes(60),
            refresh_token_validity=Duration.days(30)
        )
        
        # Create user groups for role-based access control
        cognito.CfnUserPoolGroup(
            self, "AdminGroup",
            user_pool_id=self.user_pool.user_pool_id,
            group_name="admin",
            description="Administrator users with full access"
        )
        
        cognito.CfnUserPoolGroup(
            self, "SellerGroup",
            user_pool_id=self.user_pool.user_pool_id,
            group_name="seller",
            description="Seller users with product management access"
        )
        
        cognito.CfnUserPoolGroup(
            self, "CustomerGroup",
            user_pool_id=self.user_pool.user_pool_id,
            group_name="customer",
            description="Customer users with read-only access"
        )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for custom business logic"""
        
        # Create Lambda execution role
        self.lambda_role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Add DynamoDB permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "dynamodb:GetItem",
                    "dynamodb:PutItem",
                    "dynamodb:UpdateItem",
                    "dynamodb:Query",
                    "dynamodb:Scan"
                ],
                resources=[
                    self.products_table.table_arn,
                    f"{self.products_table.table_arn}/*",
                    self.users_table.table_arn,
                    self.analytics_table.table_arn
                ]
            )
        )
        
        # Add OpenSearch permissions
        self.lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "es:ESHttpGet",
                    "es:ESHttpPost",
                    "es:ESHttpPut",
                    "es:ESHttpDelete"
                ],
                resources=[f"{self.opensearch_domain.domain_arn}/*"]
            )
        )
        
        # Business logic Lambda function
        self.business_logic_function = _lambda.Function(
            self, "BusinessLogicFunction",
            function_name=f"{self.project_name}-business-logic",
            runtime=_lambda.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.seconds(30),
            memory_size=512,
            role=self.lambda_role,
            environment={
                "PRODUCTS_TABLE": self.products_table.table_name,
                "USERS_TABLE": self.users_table.table_name,
                "ANALYTICS_TABLE": self.analytics_table.table_name,
                "OPENSEARCH_ENDPOINT": self.opensearch_domain.domain_endpoint
            },
            tracing=_lambda.Tracing.ACTIVE,
            log_retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_appsync_api(self) -> None:
        """Create AppSync GraphQL API with multiple authentication methods"""
        
        # Create CloudWatch logs role for AppSync
        self.appsync_logs_role = iam.Role(
            self, "AppSyncLogsRole",
            assumed_by=iam.ServicePrincipal("appsync.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AppSyncPushToCloudWatchLogs"
                )
            ]
        )
        
        # GraphQL API with multiple authentication methods
        self.graphql_api = appsync.GraphqlApi(
            self, "GraphQLAPI",
            name=self.project_name,
            definition=appsync.Definition.from_file("schema.graphql"),
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.USER_POOL,
                    user_pool_config=appsync.UserPoolConfig(
                        user_pool=self.user_pool
                    )
                ),
                additional_authorization_modes=[
                    appsync.AuthorizationMode(
                        authorization_type=appsync.AuthorizationType.API_KEY,
                        api_key_config=appsync.ApiKeyConfig(
                            expires=Duration.days(365)
                        )
                    ),
                    appsync.AuthorizationMode(
                        authorization_type=appsync.AuthorizationType.IAM
                    )
                ]
            ),
            log_config=appsync.LogConfig(
                field_log_level=appsync.FieldLogLevel.ALL,
                role=self.appsync_logs_role
            ),
            xray_enabled=True
        )

    def _create_data_sources(self) -> None:
        """Create AppSync data sources"""
        
        # DynamoDB data sources
        self.products_data_source = self.graphql_api.add_dynamo_db_data_source(
            "ProductsDataSource",
            table=self.products_table,
            description="Products DynamoDB table data source"
        )
        
        self.users_data_source = self.graphql_api.add_dynamo_db_data_source(
            "UsersDataSource",
            table=self.users_table,
            description="Users DynamoDB table data source"
        )
        
        self.analytics_data_source = self.graphql_api.add_dynamo_db_data_source(
            "AnalyticsDataSource",
            table=self.analytics_table,
            description="Analytics DynamoDB table data source"
        )
        
        # Lambda data source for business logic
        self.lambda_data_source = self.graphql_api.add_lambda_data_source(
            "BusinessLogicDataSource",
            lambda_function=self.business_logic_function,
            description="Lambda data source for business logic"
        )

    def _create_resolvers(self) -> None:
        """Create GraphQL resolvers for all operations"""
        
        # Query resolvers
        self._create_query_resolvers()
        
        # Mutation resolvers
        self._create_mutation_resolvers()
        
        # Subscription resolvers
        self._create_subscription_resolvers()

    def _create_query_resolvers(self) -> None:
        """Create resolvers for Query operations"""
        
        # getProduct resolver
        self.products_data_source.create_resolver(
            "GetProductResolver",
            type_name="Query",
            field_name="getProduct",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "GetItem",
    "key": {
        "productId": $util.dynamodb.toDynamoDBJson($ctx.args.productId)
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end

#if($ctx.result)
    $util.toJson($ctx.result)
#else
    null
#end
            """)
        )
        
        # listProducts resolver with filtering
        self.products_data_source.create_resolver(
            "ListProductsResolver",
            type_name="Query",
            field_name="listProducts",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($limit = $util.defaultIfNull($ctx.args.limit, 20))
#set($filter = $util.defaultIfNull($ctx.args.filter, {}))

{
    "version": "2017-02-28",
    "operation": "Scan",
    "limit": $limit,
    #if($ctx.args.nextToken)
    "nextToken": "$ctx.args.nextToken",
    #end
    #if($filter && $filter.keySet().size() > 0)
    "filter": {
        #set($filterExpressions = [])
        #set($expressionValues = {})
        
        #if($filter.category)
            #set($dummy = $filterExpressions.add("category = :category"))
            #set($dummy = $expressionValues.put(":category", $util.dynamodb.toDynamoDBJson($filter.category)))
        #end
        
        #if($filter.inStock != null)
            #set($dummy = $filterExpressions.add("inStock = :inStock"))
            #set($dummy = $expressionValues.put(":inStock", $util.dynamodb.toDynamoDBJson($filter.inStock)))
        #end
        
        #if($filter.minPrice)
            #set($dummy = $filterExpressions.add("price >= :minPrice"))
            #set($dummy = $expressionValues.put(":minPrice", $util.dynamodb.toDynamoDBJson($filter.minPrice)))
        #end
        
        #if($filter.maxPrice)
            #set($dummy = $filterExpressions.add("price <= :maxPrice"))
            #set($dummy = $expressionValues.put(":maxPrice", $util.dynamodb.toDynamoDBJson($filter.maxPrice)))
        #end
        
        #if($filterExpressions.size() > 0)
        "expression": "$util.join(" AND ", $filterExpressions)",
        "expressionValues": $util.toJson($expressionValues)
        #end
    }
    #end
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end

{
    "items": $util.toJson($ctx.result.items),
    #if($ctx.result.nextToken)
    "nextToken": "$ctx.result.nextToken",
    #end
    "scannedCount": $ctx.result.scannedCount
}
            """)
        )
        
        # listProductsByCategory resolver using GSI
        self.products_data_source.create_resolver(
            "ListProductsByCategoryResolver",
            type_name="Query",
            field_name="listProductsByCategory",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($limit = $util.defaultIfNull($ctx.args.limit, 20))
#set($sortDirection = $util.defaultIfNull($ctx.args.sortDirection, "DESC"))

{
    "version": "2017-02-28",
    "operation": "Query",
    "index": "CategoryIndex",
    "query": {
        "expression": "category = :category",
        "expressionValues": {
            ":category": $util.dynamodb.toDynamoDBJson($ctx.args.category)
        }
    },
    "limit": $limit,
    "scanIndexForward": #if($sortDirection == "ASC") true #else false #end,
    #if($ctx.args.nextToken)
    "nextToken": "$ctx.args.nextToken"
    #end
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end

{
    "items": $util.toJson($ctx.result.items),
    #if($ctx.result.nextToken)
    "nextToken": "$ctx.result.nextToken",
    #end
    "scannedCount": $ctx.result.scannedCount
}
            """)
        )
        
        # Lambda-powered resolvers for business logic
        self.lambda_data_source.create_resolver(
            "GetProductScoreResolver",
            type_name="Query",
            field_name="getProductScore",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "Invoke",
    "payload": {
        "field": "calculateProductScore",
        "arguments": $util.toJson($ctx.args),
        "identity": $util.toJson($ctx.identity)
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """)
        )
        
        self.lambda_data_source.create_resolver(
            "GetProductRecommendationsResolver",
            type_name="Query",
            field_name="getProductRecommendations",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "Invoke",
    "payload": {
        "field": "getProductRecommendations",
        "arguments": $util.toJson($ctx.args),
        "identity": $util.toJson($ctx.identity)
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """)
        )

    def _create_mutation_resolvers(self) -> None:
        """Create resolvers for Mutation operations"""
        
        # createProduct resolver
        self.products_data_source.create_resolver(
            "CreateProductResolver",
            type_name="Mutation",
            field_name="createProduct",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($productId = $util.autoId())
#set($now = $util.time.nowISO8601())

{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "productId": $util.dynamodb.toDynamoDBJson($productId)
    },
    "attributeValues": {
        "name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
        "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
        "price": $util.dynamodb.toDynamoDBJson($ctx.args.input.price),
        "category": $util.dynamodb.toDynamoDBJson($ctx.args.input.category),
        "inStock": $util.dynamodb.toDynamoDBJson($ctx.args.input.inStock),
        "createdAt": $util.dynamodb.toDynamoDBJson($now),
        "updatedAt": $util.dynamodb.toDynamoDBJson($now),
        #if($ctx.identity.username)
        "seller": $util.dynamodb.toDynamoDBJson($ctx.identity.username),
        #end
        #if($ctx.args.input.tags)
        "tags": $util.dynamodb.toDynamoDBJson($ctx.args.input.tags),
        #end
        #if($ctx.args.input.imageUrl)
        "imageUrl": $util.dynamodb.toDynamoDBJson($ctx.args.input.imageUrl),
        #end
        #if($ctx.args.input.priceRange)
        "priceRange": $util.dynamodb.toDynamoDBJson($ctx.args.input.priceRange)
        #end
    },
    "condition": {
        "expression": "attribute_not_exists(productId)"
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """)
        )
        
        # updateProduct resolver
        self.products_data_source.create_resolver(
            "UpdateProductResolver",
            type_name="Mutation",
            field_name="updateProduct",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($now = $util.time.nowISO8601())
#set($updateExpressions = [])
#set($expressionNames = {})
#set($expressionValues = {})

## Build dynamic update expression
#if($ctx.args.input.name)
    #set($dummy = $updateExpressions.add("#name = :name"))
    #set($dummy = $expressionNames.put("#name", "name"))
    #set($dummy = $expressionValues.put(":name", $util.dynamodb.toDynamoDBJson($ctx.args.input.name)))
#end

#if($ctx.args.input.description)
    #set($dummy = $updateExpressions.add("description = :description"))
    #set($dummy = $expressionValues.put(":description", $util.dynamodb.toDynamoDBJson($ctx.args.input.description)))
#end

#if($ctx.args.input.price)
    #set($dummy = $updateExpressions.add("price = :price"))
    #set($dummy = $expressionValues.put(":price", $util.dynamodb.toDynamoDBJson($ctx.args.input.price)))
#end

#if($ctx.args.input.category)
    #set($dummy = $updateExpressions.add("category = :category"))
    #set($dummy = $expressionValues.put(":category", $util.dynamodb.toDynamoDBJson($ctx.args.input.category)))
#end

#if($ctx.args.input.inStock != null)
    #set($dummy = $updateExpressions.add("inStock = :inStock"))
    #set($dummy = $expressionValues.put(":inStock", $util.dynamodb.toDynamoDBJson($ctx.args.input.inStock)))
#end

#if($ctx.args.input.tags)
    #set($dummy = $updateExpressions.add("tags = :tags"))
    #set($dummy = $expressionValues.put(":tags", $util.dynamodb.toDynamoDBJson($ctx.args.input.tags)))
#end

#if($ctx.args.input.imageUrl)
    #set($dummy = $updateExpressions.add("imageUrl = :imageUrl"))
    #set($dummy = $expressionValues.put(":imageUrl", $util.dynamodb.toDynamoDBJson($ctx.args.input.imageUrl)))
#end

#if($ctx.args.input.priceRange)
    #set($dummy = $updateExpressions.add("priceRange = :priceRange"))
    #set($dummy = $expressionValues.put(":priceRange", $util.dynamodb.toDynamoDBJson($ctx.args.input.priceRange)))
#end

## Always update the updatedAt timestamp
#set($dummy = $updateExpressions.add("updatedAt = :updatedAt"))
#set($dummy = $expressionValues.put(":updatedAt", $util.dynamodb.toDynamoDBJson($now)))

{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "productId": $util.dynamodb.toDynamoDBJson($ctx.args.input.productId)
    },
    "update": {
        "expression": "SET $util.join(", ", $updateExpressions)",
        #if($expressionNames.keySet().size() > 0)
        "expressionNames": $util.toJson($expressionNames),
        #end
        "expressionValues": $util.toJson($expressionValues)
    },
    "condition": {
        "expression": "attribute_exists(productId)"
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """)
        )
        
        # deleteProduct resolver
        self.products_data_source.create_resolver(
            "DeleteProductResolver",
            type_name="Mutation",
            field_name="deleteProduct",
            request_mapping_template=appsync.MappingTemplate.from_string("""
{
    "version": "2017-02-28",
    "operation": "DeleteItem",
    "key": {
        "productId": $util.dynamodb.toDynamoDBJson($ctx.args.productId)
    },
    "condition": {
        "expression": "attribute_exists(productId)"
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """)
        )
        
        # Analytics tracking resolver
        self.analytics_data_source.create_resolver(
            "TrackEventResolver",
            type_name="Mutation",
            field_name="trackEvent",
            request_mapping_template=appsync.MappingTemplate.from_string("""
#set($eventId = $util.autoId())
#set($now = $util.time.nowISO8601())
#set($ttl = $util.time.nowEpochSeconds() + (30 * 24 * 60 * 60))

{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "metricId": $util.dynamodb.toDynamoDBJson($eventId),
        "timestamp": $util.dynamodb.toDynamoDBJson($now)
    },
    "attributeValues": {
        "eventType": $util.dynamodb.toDynamoDBJson($ctx.args.input.eventType),
        #if($ctx.identity.sub)
        "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
        #end
        #if($ctx.args.input.data)
        "data": $util.dynamodb.toDynamoDBJson($ctx.args.input.data),
        #end
        "processed": $util.dynamodb.toDynamoDBJson(false),
        "ttl": $util.dynamodb.toDynamoDBJson($ttl)
    }
}
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
#if($ctx.error)
    $util.error($ctx.error.message, $ctx.error.type)
#end
$util.toJson($ctx.result)
            """)
        )

    def _create_subscription_resolvers(self) -> None:
        """Create resolvers for Subscription operations"""
        
        # Subscriptions are automatically handled by AppSync
        # when using the @aws_subscribe directive in the schema
        pass

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        
        CfnOutput(
            self, "GraphQLAPIId",
            value=self.graphql_api.api_id,
            description="AppSync GraphQL API ID"
        )
        
        CfnOutput(
            self, "GraphQLEndpoint",
            value=self.graphql_api.graphql_url,
            description="AppSync GraphQL API endpoint"
        )
        
        CfnOutput(
            self, "RealtimeEndpoint",
            value=self.graphql_api.realtime_url,
            description="AppSync real-time endpoint for subscriptions"
        )
        
        CfnOutput(
            self, "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID"
        )
        
        CfnOutput(
            self, "UserPoolClientId",
            value=self.user_pool_client.user_pool_client_id,
            description="Cognito User Pool Client ID"
        )
        
        CfnOutput(
            self, "ProductsTableName",
            value=self.products_table.table_name,
            description="DynamoDB Products table name"
        )
        
        CfnOutput(
            self, "UsersTableName",
            value=self.users_table.table_name,
            description="DynamoDB Users table name"
        )
        
        CfnOutput(
            self, "AnalyticsTableName",
            value=self.analytics_table.table_name,
            description="DynamoDB Analytics table name"
        )
        
        CfnOutput(
            self, "OpenSearchDomainEndpoint",
            value=f"https://{self.opensearch_domain.domain_endpoint}",
            description="OpenSearch domain endpoint"
        )
        
        CfnOutput(
            self, "LambdaFunctionName",
            value=self.business_logic_function.function_name,
            description="Lambda business logic function name"
        )

    def _get_lambda_code(self) -> str:
        """Return the Lambda function code as a string"""
        return """
const AWS = require('aws-sdk');
const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const { field, arguments: args, source, identity } = event;
    
    try {
        switch (field) {
            case 'calculateProductScore':
                return await calculateProductScore(args.productId);
            case 'getProductRecommendations':
                return await getProductRecommendations(args.userId, args.category);
            case 'updateProductSearchIndex':
                return await updateProductSearchIndex(args.productData);
            case 'processAnalytics':
                return await processAnalytics(args.event, identity);
            default:
                throw new Error(`Unknown field: ${field}`);
        }
    } catch (error) {
        console.error('Error:', error);
        throw error;
    }
};

async function calculateProductScore(productId) {
    // Complex scoring algorithm based on multiple factors
    const product = await dynamodb.get({
        TableName: process.env.PRODUCTS_TABLE,
        Key: { productId }
    }).promise();
    
    if (!product.Item) {
        throw new Error('Product not found');
    }
    
    const { rating = 0, reviewCount = 0, price = 0 } = product.Item;
    
    // Calculate composite score
    const ratingScore = rating * 0.4;
    const popularityScore = Math.min(reviewCount / 100, 1) * 0.3;
    const priceScore = (price < 50 ? 0.3 : price < 200 ? 0.2 : 0.1) * 0.3;
    
    const totalScore = ratingScore + popularityScore + priceScore;
    
    return {
        productId,
        score: Math.round(totalScore * 100) / 100,
        breakdown: {
            rating: ratingScore,
            popularity: popularityScore,
            price: priceScore
        }
    };
}

async function getProductRecommendations(userId, category) {
    // Get products in the same category
    const params = {
        TableName: process.env.PRODUCTS_TABLE,
        IndexName: 'CategoryIndex',
        KeyConditionExpression: 'category = :category',
        ExpressionAttributeValues: {
            ':category': category
        },
        Limit: 10
    };
    
    const result = await dynamodb.query(params).promise();
    
    // Apply simple recommendation scoring
    const recommendations = result.Items.map(item => ({
        ...item,
        recommendationScore: Math.random() * 0.3 + 0.7 // Simplified scoring
    })).sort((a, b) => b.recommendationScore - a.recommendationScore);
    
    return recommendations.slice(0, 5);
}

async function updateProductSearchIndex(productData) {
    // In a real implementation, this would update OpenSearch
    // For now, return success
    return { 
        success: true, 
        productId: productData.productId,
        message: 'Search index update simulated'
    };
}

async function processAnalytics(eventData, identity) {
    // Process analytics events
    const analyticsRecord = {
        metricId: `${eventData.type}-${Date.now()}`,
        timestamp: new Date().toISOString(),
        eventType: eventData.type,
        userId: identity?.sub || 'anonymous',
        data: eventData.data,
        ttl: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days TTL
    };
    
    await dynamodb.put({
        TableName: process.env.ANALYTICS_TABLE,
        Item: analyticsRecord
    }).promise();
    
    return { 
        success: true, 
        eventId: analyticsRecord.metricId 
    };
}
        """


app = App()
GraphQLAppSyncStack(app, "GraphQLAppSyncStack")
app.synth()