#!/usr/bin/env python3
"""
AWS CDK Python application for Real-time Data Synchronization with AppSync

This CDK application creates a complete real-time collaborative task management system
using AWS AppSync, DynamoDB, and IAM. The solution enables multiple users to create,
update, and delete tasks while receiving real-time notifications through GraphQL subscriptions.

Features:
- GraphQL API with real-time subscriptions
- DynamoDB table with streams for change capture
- Optimistic concurrency control for conflict resolution
- IAM roles with least privilege access
- CloudWatch monitoring and logging
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
)
from constructs import Construct
import os


class RealtimeDataSyncStack(Stack):
    """
    CDK Stack for Real-time Data Synchronization with AWS AppSync
    
    This stack creates:
    - DynamoDB table with streams enabled for task storage
    - IAM role for AppSync with DynamoDB permissions
    - AppSync GraphQL API with real-time subscriptions
    - Data sources and resolvers for CRUD operations
    - CloudWatch log groups for monitoring
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters with defaults
        self.table_name = f"tasks-{cdk.Names.unique_id(self)[:8].lower()}"
        self.api_name = f"realtime-tasks-{cdk.Names.unique_id(self)[:8].lower()}"
        
        # Create DynamoDB table for task storage
        self.tasks_table = self._create_dynamodb_table()
        
        # Create IAM role for AppSync
        self.appsync_role = self._create_appsync_role()
        
        # Create AppSync GraphQL API
        self.api = self._create_graphql_api()
        
        # Create data source
        self.data_source = self._create_data_source()
        
        # Create resolvers
        self._create_resolvers()
        
        # Create CloudWatch log group
        self._create_log_group()
        
        # Create outputs
        self._create_outputs()

    def _create_dynamodb_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table with Global Secondary Index and streams enabled
        
        The table stores task data with:
        - Hash key: id (task identifier)
        - GSI: status-createdAt-index for efficient status-based queries
        - Streams: NEW_AND_OLD_IMAGES for real-time change capture
        - Point-in-time recovery enabled for data protection
        """
        table = dynamodb.Table(
            self, 
            "TasksTable",
            table_name=self.table_name,
            partition_key=dynamodb.Attribute(
                name="id", 
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,  # For demo purposes
            table_class=dynamodb.TableClass.STANDARD,
        )

        # Add Global Secondary Index for status-based queries
        table.add_global_secondary_index(
            index_name="status-createdAt-index",
            partition_key=dynamodb.Attribute(
                name="status", 
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="createdAt", 
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL,
        )

        # Add tags for resource management
        cdk.Tags.of(table).add("Purpose", "AppSyncTutorial")
        cdk.Tags.of(table).add("Component", "DataStore")

        return table

    def _create_appsync_role(self) -> iam.Role:
        """
        Create IAM role for AppSync with DynamoDB permissions
        
        This role implements least privilege access, granting only the specific
        DynamoDB operations needed for task management:
        - GetItem, PutItem, UpdateItem, DeleteItem for individual operations
        - Query, Scan for list operations
        - Access to both table and indexes
        """
        role = iam.Role(
            self,
            "AppSyncServiceRole",
            role_name=f"appsync-tasks-role-{cdk.Names.unique_id(self)[:8].lower()}",
            assumed_by=iam.ServicePrincipal("appsync.amazonaws.com"),
            description="Service role for AppSync to access DynamoDB tasks table",
        )

        # Create custom policy with specific DynamoDB permissions
        policy_statement = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "dynamodb:GetItem",
                "dynamodb:PutItem", 
                "dynamodb:UpdateItem",
                "dynamodb:DeleteItem",
                "dynamodb:Query",
                "dynamodb:Scan",
            ],
            resources=[
                self.tasks_table.table_arn,
                f"{self.tasks_table.table_arn}/*",  # For GSI access
            ]
        )

        role.add_to_policy(policy_statement)

        # Add tags for resource management
        cdk.Tags.of(role).add("Purpose", "AppSyncTutorial")
        cdk.Tags.of(role).add("Component", "Security")

        return role

    def _create_graphql_api(self) -> appsync.GraphqlApi:
        """
        Create AppSync GraphQL API with real-time subscriptions
        
        The API includes:
        - GraphQL schema with queries, mutations, and subscriptions
        - API key authentication for development/testing
        - CloudWatch logging enabled for debugging
        - Real-time subscription support for collaborative features
        """
        
        # Define GraphQL schema with subscriptions
        schema_definition = appsync.SchemaFile.from_asset(
            os.path.join(os.path.dirname(__file__), "schema.graphql")
        )

        api = appsync.GraphqlApi(
            self,
            "TasksApi",
            name=self.api_name,
            schema=schema_definition,
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.API_KEY,
                    api_key_config=appsync.ApiKeyConfig(
                        name="TasksApiKey",
                        description="API key for tasks GraphQL API",
                        expires=cdk.Expiration.after(Duration.days(30))
                    )
                )
            ),
            log_config=appsync.LogConfig(
                exclude_verbose_content=False,
                field_log_level=appsync.FieldLogLevel.ALL,
            ),
            xray_enabled=True,  # Enable X-Ray tracing for performance monitoring
        )

        # Add tags for resource management
        cdk.Tags.of(api).add("Purpose", "AppSyncTutorial")
        cdk.Tags.of(api).add("Component", "API")

        return api

    def _create_data_source(self) -> appsync.DynamoDbDataSource:
        """
        Create DynamoDB data source for AppSync
        
        The data source connects AppSync resolvers to the DynamoDB table
        and handles connection pooling, error handling, and performance optimization.
        """
        return self.api.add_dynamo_db_data_source(
            "TasksDataSource",
            table=self.tasks_table,
            service_role=self.appsync_role,
            description="DynamoDB data source for tasks table"
        )

    def _create_resolvers(self) -> None:
        """
        Create GraphQL resolvers for queries, mutations, and subscriptions
        
        Resolvers translate GraphQL operations into DynamoDB operations:
        - Query resolvers: getTask, listTasks for data retrieval
        - Mutation resolvers: createTask, updateTask, deleteTask with conflict resolution
        - Subscription resolvers: automatic triggers for real-time updates
        """
        
        # Query Resolvers
        self._create_get_task_resolver()
        self._create_list_tasks_resolver()
        
        # Mutation Resolvers with conflict resolution
        self._create_create_task_resolver()
        self._create_update_task_resolver()
        self._create_delete_task_resolver()

    def _create_get_task_resolver(self) -> None:
        """Create resolver for getTask query"""
        self.data_source.create_resolver(
            "GetTaskResolver",
            type_name="Query",
            field_name="getTask",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2018-05-29",
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
            """)
        )

    def _create_list_tasks_resolver(self) -> None:
        """Create resolver for listTasks query with pagination"""
        self.data_source.create_resolver(
            "ListTasksResolver",
            type_name="Query", 
            field_name="listTasks",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2018-05-29",
                "operation": "Scan",
                "limit": #if($ctx.args.limit) $ctx.args.limit #else 20 #end,
                "nextToken": #if($ctx.args.nextToken) "$ctx.args.nextToken" #else null #end
            }
            """),
            response_mapping_template=appsync.MappingTemplate.from_string("""
            #if($ctx.error)
                $util.error($ctx.error.message, $ctx.error.type)
            #end
            {
                "items": $util.toJson($ctx.result.items),
                "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
            }
            """)
        )

    def _create_create_task_resolver(self) -> None:
        """Create resolver for createTask mutation"""
        self.data_source.create_resolver(
            "CreateTaskResolver",
            type_name="Mutation",
            field_name="createTask", 
            request_mapping_template=appsync.MappingTemplate.from_string("""
            #set($id = $util.autoId())
            #set($createdAt = $util.time.nowISO8601())
            {
                "version": "2018-05-29",
                "operation": "PutItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($id)
                },
                "attributeValues": {
                    "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
                    "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
                    "status": $util.dynamodb.toDynamoDBJson("TODO"),
                    "priority": $util.dynamodb.toDynamoDBJson($ctx.args.input.priority),
                    "assignedTo": $util.dynamodb.toDynamoDBJson($ctx.args.input.assignedTo),
                    "createdAt": $util.dynamodb.toDynamoDBJson($createdAt),
                    "updatedAt": $util.dynamodb.toDynamoDBJson($createdAt),
                    "version": $util.dynamodb.toDynamoDBJson(1)
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

    def _create_update_task_resolver(self) -> None:
        """Create resolver for updateTask mutation with optimistic locking"""
        self.data_source.create_resolver(
            "UpdateTaskResolver",
            type_name="Mutation",
            field_name="updateTask",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            #set($updatedAt = $util.time.nowISO8601())
            #set($updateExpression = "SET #updatedAt = :updatedAt, #version = #version + :incr")
            #set($expressionNames = {"#updatedAt": "updatedAt", "#version": "version"})
            #set($expressionValues = {":updatedAt": $util.dynamodb.toDynamoDBJson($updatedAt), ":incr": $util.dynamodb.toDynamoDBJson(1), ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)})

            ## Add optional fields to update expression
            #if($ctx.args.input.title)
                #set($updateExpression = "$updateExpression, #title = :title")
                $util.qr($expressionNames.put("#title", "title"))
                $util.qr($expressionValues.put(":title", $util.dynamodb.toDynamoDBJson($ctx.args.input.title)))
            #end
            #if($ctx.args.input.description)
                #set($updateExpression = "$updateExpression, #description = :description")
                $util.qr($expressionNames.put("#description", "description"))
                $util.qr($expressionValues.put(":description", $util.dynamodb.toDynamoDBJson($ctx.args.input.description)))
            #end
            #if($ctx.args.input.status)
                #set($updateExpression = "$updateExpression, #status = :status")
                $util.qr($expressionNames.put("#status", "status"))
                $util.qr($expressionValues.put(":status", $util.dynamodb.toDynamoDBJson($ctx.args.input.status)))
            #end
            #if($ctx.args.input.priority)
                #set($updateExpression = "$updateExpression, #priority = :priority")
                $util.qr($expressionNames.put("#priority", "priority"))
                $util.qr($expressionValues.put(":priority", $util.dynamodb.toDynamoDBJson($ctx.args.input.priority)))
            #end
            #if($ctx.args.input.assignedTo)
                #set($updateExpression = "$updateExpression, #assignedTo = :assignedTo")
                $util.qr($expressionNames.put("#assignedTo", "assignedTo"))
                $util.qr($expressionValues.put(":assignedTo", $util.dynamodb.toDynamoDBJson($ctx.args.input.assignedTo)))
            #end

            {
                "version": "2018-05-29",
                "operation": "UpdateItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
                },
                "update": {
                    "expression": "$updateExpression",
                    "expressionNames": $util.toJson($expressionNames),
                    "expressionValues": $util.toJson($expressionValues)
                },
                "condition": {
                    "expression": "#version = :expectedVersion",
                    "expressionNames": {
                        "#version": "version"
                    },
                    "expressionValues": {
                        ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)
                    }
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

    def _create_delete_task_resolver(self) -> None:
        """Create resolver for deleteTask mutation with version checking"""
        self.data_source.create_resolver(
            "DeleteTaskResolver",
            type_name="Mutation",
            field_name="deleteTask",
            request_mapping_template=appsync.MappingTemplate.from_string("""
            {
                "version": "2018-05-29",
                "operation": "DeleteItem",
                "key": {
                    "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
                },
                "condition": {
                    "expression": "#version = :expectedVersion",
                    "expressionNames": {
                        "#version": "version"
                    },
                    "expressionValues": {
                        ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.version)
                    }
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

    def _create_log_group(self) -> None:
        """Create CloudWatch log group for AppSync API logging"""
        logs.LogGroup(
            self,
            "AppSyncLogGroup", 
            log_group_name=f"/aws/appsync/apis/{self.api.api_id}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for key resources"""
        CfnOutput(
            self,
            "GraphQLApiUrl",
            value=self.api.graphql_url,
            description="GraphQL API URL for the AppSync API"
        )

        CfnOutput(
            self,
            "GraphQLApiId", 
            value=self.api.api_id,
            description="AppSync API ID"
        )

        CfnOutput(
            self,
            "GraphQLApiKey",
            value=self.api.api_key or "No API Key",
            description="API Key for GraphQL API access"
        )

        CfnOutput(
            self,
            "DynamoDBTableName",
            value=self.tasks_table.table_name,
            description="DynamoDB table name for tasks storage"
        )

        CfnOutput(
            self,
            "DynamoDBTableArn",
            value=self.tasks_table.table_arn,
            description="DynamoDB table ARN"
        )

        CfnOutput(
            self,
            "IAMRoleArn", 
            value=self.appsync_role.role_arn,
            description="IAM role ARN for AppSync service"
        )


# CDK Application
app = cdk.App()

# Create stack with environment-specific naming
stack_name = app.node.try_get_context("stack_name") or "RealtimeDataSyncStack"
env_name = app.node.try_get_context("environment") or "dev"

RealtimeDataSyncStack(
    app, 
    f"{stack_name}-{env_name}",
    description="Real-time Data Synchronization with AWS AppSync - CDK Python",
    env=cdk.Environment(
        account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
        region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
    ),
    tags={
        "Project": "RealtimeDataSync",
        "Environment": env_name,
        "IaC": "CDK-Python",
        "Purpose": "AppSyncTutorial"
    }
)

app.synth()