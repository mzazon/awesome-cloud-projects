#!/usr/bin/env python3
"""
CDK Application for Offline-First Mobile Applications with Amplify DataStore

This CDK application deploys the complete infrastructure needed for building
offline-first mobile applications using AWS Amplify DataStore, including:
- Cognito User Pool for authentication
- AppSync GraphQL API with DataStore capabilities
- DynamoDB tables for data storage
- Lambda resolvers for custom business logic
- IAM roles and policies for secure access
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_cognito as cognito,
    aws_appsync as appsync,
    aws_dynamodb as dynamodb,
    aws_lambda as lambda_,
    aws_iam as iam,
    aws_logs as logs,
    Duration,
    RemovalPolicy,
    CfnOutput,
)
from constructs import Construct
import os


class OfflineFirstMobileStack(Stack):
    """
    Stack for deploying offline-first mobile application infrastructure
    using AWS Amplify DataStore pattern with AppSync and DynamoDB.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack parameters
        self.app_name = self.node.try_get_context("app_name") or "offline-tasks"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Create Cognito User Pool for authentication
        self.user_pool = self._create_user_pool()
        
        # Create AppSync GraphQL API
        self.graphql_api = self._create_graphql_api()
        
        # Create DynamoDB tables
        self.task_table = self._create_task_table()
        self.project_table = self._create_project_table()
        
        # Create Lambda resolvers
        self.lambda_resolvers = self._create_lambda_resolvers()
        
        # Create data sources and resolvers
        self._create_data_sources_and_resolvers()
        
        # Create outputs
        self._create_outputs()

    def _create_user_pool(self) -> cognito.UserPool:
        """
        Create Cognito User Pool for user authentication.
        
        Returns:
            cognito.UserPool: The created user pool
        """
        user_pool = cognito.UserPool(
            self, "UserPool",
            user_pool_name=f"{self.app_name}-user-pool",
            self_sign_up_enabled=True,
            sign_in_case_sensitive=False,
            sign_in_aliases=cognito.SignInAliases(
                username=True,
                email=True
            ),
            auto_verify=cognito.AutoVerifiedAttrs(email=True),
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
        
        # Create user pool client
        user_pool_client = cognito.UserPoolClient(
            self, "UserPoolClient",
            user_pool=user_pool,
            user_pool_client_name=f"{self.app_name}-client",
            generate_secret=False,
            auth_flows=cognito.AuthFlow(
                user_srp=True,
                user_password=True
            ),
            prevent_user_existence_errors=True,
            access_token_validity=Duration.hours(1),
            id_token_validity=Duration.hours(1),
            refresh_token_validity=Duration.days(30)
        )
        
        # Store client ID as attribute
        user_pool.client_id = user_pool_client.user_pool_client_id
        
        return user_pool

    def _create_graphql_api(self) -> appsync.GraphqlApi:
        """
        Create AppSync GraphQL API with DataStore capabilities.
        
        Returns:
            appsync.GraphqlApi: The created GraphQL API
        """
        # Define GraphQL schema
        schema = appsync.SchemaFile.from_asset("schema.graphql")
        
        # Create GraphQL API
        api = appsync.GraphqlApi(
            self, "GraphQLApi",
            name=f"{self.app_name}-api",
            schema=schema,
            authorization_config=appsync.AuthorizationConfig(
                default_authorization=appsync.AuthorizationMode(
                    authorization_type=appsync.AuthorizationType.USER_POOL,
                    user_pool_config=appsync.UserPoolConfig(
                        user_pool=self.user_pool
                    )
                )
            ),
            log_config=appsync.LogConfig(
                field_log_level=appsync.FieldLogLevel.ALL,
                retention=logs.RetentionDays.ONE_WEEK
            ),
            x_ray_enabled=True
        )
        
        return api

    def _create_task_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing task data.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "TaskTable",
            table_name=f"{self.app_name}-task-table",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            # Global Secondary Index for project-based queries
            global_secondary_indexes=[
                dynamodb.GlobalSecondaryIndex(
                    index_name="byProject",
                    partition_key=dynamodb.Attribute(
                        name="projectId",
                        type=dynamodb.AttributeType.STRING
                    ),
                    sort_key=dynamodb.Attribute(
                        name="createdAt",
                        type=dynamodb.AttributeType.STRING
                    )
                ),
                # GSI for status-based queries
                dynamodb.GlobalSecondaryIndex(
                    index_name="byStatus",
                    partition_key=dynamodb.Attribute(
                        name="status",
                        type=dynamodb.AttributeType.STRING
                    ),
                    sort_key=dynamodb.Attribute(
                        name="updatedAt",
                        type=dynamodb.AttributeType.STRING
                    )
                )
            ]
        )
        
        # Add tags
        cdk.Tags.of(table).add("Application", self.app_name)
        cdk.Tags.of(table).add("Environment", self.environment)
        
        return table

    def _create_project_table(self) -> dynamodb.Table:
        """
        Create DynamoDB table for storing project data.
        
        Returns:
            dynamodb.Table: The created DynamoDB table
        """
        table = dynamodb.Table(
            self, "ProjectTable",
            table_name=f"{self.app_name}-project-table",
            partition_key=dynamodb.Attribute(
                name="id",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES
        )
        
        # Add tags
        cdk.Tags.of(table).add("Application", self.app_name)
        cdk.Tags.of(table).add("Environment", self.environment)
        
        return table

    def _create_lambda_resolvers(self) -> dict:
        """
        Create Lambda functions for custom GraphQL resolvers.
        
        Returns:
            dict: Dictionary of Lambda functions
        """
        # Create Lambda execution role
        lambda_role = iam.Role(
            self, "LambdaResolverRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )
        
        # Grant DynamoDB permissions
        self.task_table.grant_read_write_data(lambda_role)
        self.project_table.grant_read_write_data(lambda_role)
        
        # Create conflict resolution Lambda
        conflict_resolver = lambda_.Function(
            self, "ConflictResolver",
            function_name=f"{self.app_name}-conflict-resolver",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=lambda_.Code.from_inline('''
import json
import boto3
from datetime import datetime

def handler(event, context):
    """
    Custom conflict resolution logic for DataStore conflicts.
    Implements priority-based conflict resolution.
    """
    print(f"Conflict resolver invoked with event: {json.dumps(event)}")
    
    # Extract conflict data
    conflict_data = event.get('conflictData', {})
    local_model = conflict_data.get('localModel', {})
    remote_model = conflict_data.get('remoteModel', {})
    model_name = conflict_data.get('modelName', '')
    
    if model_name == 'Task':
        return resolve_task_conflict(local_model, remote_model)
    elif model_name == 'Project':
        return resolve_project_conflict(local_model, remote_model)
    
    # Default: remote wins
    return remote_model

def resolve_task_conflict(local_model, remote_model):
    """Resolve Task model conflicts using priority-based logic."""
    # If local task is completed, it wins
    if local_model.get('status') == 'COMPLETED' and remote_model.get('status') != 'COMPLETED':
        return local_model
    
    # Higher priority wins
    priority_weights = {'LOW': 1, 'MEDIUM': 2, 'HIGH': 3, 'URGENT': 4}
    local_priority = priority_weights.get(local_model.get('priority', 'MEDIUM'), 2)
    remote_priority = priority_weights.get(remote_model.get('priority', 'MEDIUM'), 2)
    
    if local_priority > remote_priority:
        return local_model
    elif remote_priority > local_priority:
        return remote_model
    
    # Most recent update wins
    local_updated = local_model.get('updatedAt', '')
    remote_updated = remote_model.get('updatedAt', '')
    
    return local_model if local_updated > remote_updated else remote_model

def resolve_project_conflict(local_model, remote_model):
    """Resolve Project model conflicts using timestamp-based logic."""
    # Most recent update wins for projects
    local_updated = local_model.get('updatedAt', '')
    remote_updated = remote_model.get('updatedAt', '')
    
    return local_model if local_updated > remote_updated else remote_model
            '''),
            role=lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "TASK_TABLE_NAME": self.task_table.table_name,
                "PROJECT_TABLE_NAME": self.project_table.table_name,
                "LOG_LEVEL": "INFO"
            }
        )
        
        # Create data validation Lambda
        data_validator = lambda_.Function(
            self, "DataValidator",
            function_name=f"{self.app_name}-data-validator",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.handler",
            code=lambda_.Code.from_inline('''
import json
import re
from datetime import datetime

def handler(event, context):
    """
    Validate data before mutations to ensure data integrity.
    """
    print(f"Data validator invoked with event: {json.dumps(event)}")
    
    operation = event.get('operation', '')
    model_name = event.get('modelName', '')
    input_data = event.get('input', {})
    
    if model_name == 'Task':
        return validate_task_data(input_data, operation)
    elif model_name == 'Project':
        return validate_project_data(input_data, operation)
    
    return {"isValid": True, "errors": []}

def validate_task_data(data, operation):
    """Validate Task model data."""
    errors = []
    
    # Title validation
    title = data.get('title', '').strip()
    if not title:
        errors.append("Title is required")
    elif len(title) > 200:
        errors.append("Title must be less than 200 characters")
    
    # Priority validation
    priority = data.get('priority', 'MEDIUM')
    if priority not in ['LOW', 'MEDIUM', 'HIGH', 'URGENT']:
        errors.append("Priority must be one of: LOW, MEDIUM, HIGH, URGENT")
    
    # Status validation
    status = data.get('status', 'PENDING')
    if status not in ['PENDING', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED']:
        errors.append("Status must be one of: PENDING, IN_PROGRESS, COMPLETED, CANCELLED")
    
    # Due date validation
    due_date = data.get('dueDate')
    if due_date:
        try:
            datetime.fromisoformat(due_date.replace('Z', '+00:00'))
        except ValueError:
            errors.append("Due date must be a valid ISO 8601 datetime")
    
    return {"isValid": len(errors) == 0, "errors": errors}

def validate_project_data(data, operation):
    """Validate Project model data."""
    errors = []
    
    # Name validation
    name = data.get('name', '').strip()
    if not name:
        errors.append("Project name is required")
    elif len(name) > 100:
        errors.append("Project name must be less than 100 characters")
    
    # Color validation (hex color)
    color = data.get('color', '#007AFF')
    if not re.match(r'^#[0-9A-Fa-f]{6}$', color):
        errors.append("Color must be a valid hex color (e.g., #007AFF)")
    
    return {"isValid": len(errors) == 0, "errors": errors}
            '''),
            role=lambda_role,
            timeout=Duration.seconds(30),
            environment={
                "TASK_TABLE_NAME": self.task_table.table_name,
                "PROJECT_TABLE_NAME": self.project_table.table_name,
                "LOG_LEVEL": "INFO"
            }
        )
        
        return {
            "conflict_resolver": conflict_resolver,
            "data_validator": data_validator
        }

    def _create_data_sources_and_resolvers(self) -> None:
        """Create AppSync data sources and resolvers."""
        # Create DynamoDB data sources
        task_data_source = self.graphql_api.add_dynamo_db_data_source(
            "TaskDataSource",
            table=self.task_table
        )
        
        project_data_source = self.graphql_api.add_dynamo_db_data_source(
            "ProjectDataSource",
            table=self.project_table
        )
        
        # Create Lambda data sources
        conflict_resolver_data_source = self.graphql_api.add_lambda_data_source(
            "ConflictResolverDataSource",
            lambda_function=self.lambda_resolvers["conflict_resolver"]
        )
        
        validator_data_source = self.graphql_api.add_lambda_data_source(
            "ValidatorDataSource",
            lambda_function=self.lambda_resolvers["data_validator"]
        )
        
        # Create resolvers for Task operations
        self._create_task_resolvers(task_data_source, validator_data_source)
        
        # Create resolvers for Project operations
        self._create_project_resolvers(project_data_source, validator_data_source)

    def _create_task_resolvers(self, data_source: appsync.DynamoDbDataSource, validator_data_source: appsync.LambdaDataSource) -> None:
        """Create resolvers for Task operations."""
        # Task Query resolvers
        data_source.create_resolver(
            "GetTaskResolver",
            type_name="Query",
            field_name="getTask",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_get_item("id", "id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )
        
        data_source.create_resolver(
            "ListTasksResolver",
            type_name="Query",
            field_name="listTasks",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "Scan",
    "filter": #if($context.args.filter) $util.transform.toDynamoDBFilterExpression($context.args.filter) #else null #end,
    "limit": $util.defaultIfNull($context.args.limit, 20),
    "nextToken": $util.toJson($util.defaultIfNullOrEmpty($context.args.nextToken, null))
}
            '''),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_list()
        )
        
        # Task Mutation resolvers
        data_source.create_resolver(
            "CreateTaskResolver",
            type_name="Mutation",
            field_name="createTask",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "title": $util.dynamodb.toDynamoDBJson($context.args.input.title),
        "description": $util.dynamodb.toDynamoDBJson($context.args.input.description),
        "priority": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($context.args.input.priority, "MEDIUM")),
        "status": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($context.args.input.status, "PENDING")),
        "dueDate": $util.dynamodb.toDynamoDBJson($context.args.input.dueDate),
        "tags": $util.dynamodb.toDynamoDBJson($context.args.input.tags),
        "projectId": $util.dynamodb.toDynamoDBJson($context.args.input.projectId),
        "owner": $util.dynamodb.toDynamoDBJson($context.identity.username),
        "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )
        
        data_source.create_resolver(
            "UpdateTaskResolver",
            type_name="Mutation",
            field_name="updateTask",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($context.args.input.id)
    },
    "update": {
        "expression": "SET #title = :title, #description = :description, #priority = :priority, #status = :status, #dueDate = :dueDate, #tags = :tags, #updatedAt = :updatedAt",
        "expressionNames": {
            "#title": "title",
            "#description": "description",
            "#priority": "priority",
            "#status": "status",
            "#dueDate": "dueDate",
            "#tags": "tags",
            "#updatedAt": "updatedAt"
        },
        "expressionValues": {
            ":title": $util.dynamodb.toDynamoDBJson($context.args.input.title),
            ":description": $util.dynamodb.toDynamoDBJson($context.args.input.description),
            ":priority": $util.dynamodb.toDynamoDBJson($context.args.input.priority),
            ":status": $util.dynamodb.toDynamoDBJson($context.args.input.status),
            ":dueDate": $util.dynamodb.toDynamoDBJson($context.args.input.dueDate),
            ":tags": $util.dynamodb.toDynamoDBJson($context.args.input.tags),
            ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
        }
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )
        
        data_source.create_resolver(
            "DeleteTaskResolver",
            type_name="Mutation",
            field_name="deleteTask",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_delete_item("id", "id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

    def _create_project_resolvers(self, data_source: appsync.DynamoDbDataSource, validator_data_source: appsync.LambdaDataSource) -> None:
        """Create resolvers for Project operations."""
        # Project Query resolvers
        data_source.create_resolver(
            "GetProjectResolver",
            type_name="Query",
            field_name="getProject",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_get_item("id", "id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )
        
        data_source.create_resolver(
            "ListProjectsResolver",
            type_name="Query",
            field_name="listProjects",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "Scan",
    "filter": #if($context.args.filter) $util.transform.toDynamoDBFilterExpression($context.args.filter) #else null #end,
    "limit": $util.defaultIfNull($context.args.limit, 20),
    "nextToken": $util.toJson($util.defaultIfNullOrEmpty($context.args.nextToken, null))
}
            '''),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_list()
        )
        
        # Project Mutation resolvers
        data_source.create_resolver(
            "CreateProjectResolver",
            type_name="Mutation",
            field_name="createProject",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "PutItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($util.autoId())
    },
    "attributeValues": {
        "name": $util.dynamodb.toDynamoDBJson($context.args.input.name),
        "description": $util.dynamodb.toDynamoDBJson($context.args.input.description),
        "color": $util.dynamodb.toDynamoDBJson($util.defaultIfNull($context.args.input.color, "#007AFF")),
        "owner": $util.dynamodb.toDynamoDBJson($context.identity.username),
        "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
        "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )
        
        data_source.create_resolver(
            "UpdateProjectResolver",
            type_name="Mutation",
            field_name="updateProject",
            request_mapping_template=appsync.MappingTemplate.from_string('''
{
    "version": "2017-02-28",
    "operation": "UpdateItem",
    "key": {
        "id": $util.dynamodb.toDynamoDBJson($context.args.input.id)
    },
    "update": {
        "expression": "SET #name = :name, #description = :description, #color = :color, #updatedAt = :updatedAt",
        "expressionNames": {
            "#name": "name",
            "#description": "description",
            "#color": "color",
            "#updatedAt": "updatedAt"
        },
        "expressionValues": {
            ":name": $util.dynamodb.toDynamoDBJson($context.args.input.name),
            ":description": $util.dynamodb.toDynamoDBJson($context.args.input.description),
            ":color": $util.dynamodb.toDynamoDBJson($context.args.input.color),
            ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
        }
    }
}
            '''),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )
        
        data_source.create_resolver(
            "DeleteProjectResolver",
            type_name="Mutation",
            field_name="deleteProject",
            request_mapping_template=appsync.MappingTemplate.dynamo_db_delete_item("id", "id"),
            response_mapping_template=appsync.MappingTemplate.dynamo_db_result_item()
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self, "UserPoolId",
            value=self.user_pool.user_pool_id,
            description="Cognito User Pool ID"
        )
        
        CfnOutput(
            self, "UserPoolClientId",
            value=self.user_pool.client_id,
            description="Cognito User Pool Client ID"
        )
        
        CfnOutput(
            self, "GraphQLApiId",
            value=self.graphql_api.api_id,
            description="AppSync GraphQL API ID"
        )
        
        CfnOutput(
            self, "GraphQLApiUrl",
            value=self.graphql_api.graphql_url,
            description="AppSync GraphQL API URL"
        )
        
        CfnOutput(
            self, "TaskTableName",
            value=self.task_table.table_name,
            description="DynamoDB Task Table Name"
        )
        
        CfnOutput(
            self, "ProjectTableName",
            value=self.project_table.table_name,
            description="DynamoDB Project Table Name"
        )
        
        CfnOutput(
            self, "Region",
            value=self.region,
            description="AWS Region"
        )


class GraphQLSchemaAsset(Construct):
    """
    Construct to create the GraphQL schema file as an asset.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Create the GraphQL schema content
        schema_content = '''
type Task @model @auth(rules: [{ allow: owner }]) {
  id: ID!
  title: String!
  description: String
  priority: Priority!
  status: Status!
  dueDate: AWSDateTime
  tags: [String]
  projectId: ID @index(name: "byProject")
  createdAt: AWSDateTime!
  updatedAt: AWSDateTime!
  owner: String @auth(rules: [{ allow: owner, operations: [read] }])
}

type Project @model @auth(rules: [{ allow: owner }]) {
  id: ID!
  name: String!
  description: String
  color: String
  tasks: [Task] @hasMany(indexName: "byProject", fields: ["id"])
  createdAt: AWSDateTime!
  updatedAt: AWSDateTime!
  owner: String @auth(rules: [{ allow: owner, operations: [read] }])
}

enum Priority {
  LOW
  MEDIUM
  HIGH
  URGENT
}

enum Status {
  PENDING
  IN_PROGRESS
  COMPLETED
  CANCELLED
}

type Mutation {
  createTask(input: CreateTaskInput!): Task
  updateTask(input: UpdateTaskInput!): Task
  deleteTask(input: DeleteTaskInput!): Task
  createProject(input: CreateProjectInput!): Project
  updateProject(input: UpdateProjectInput!): Project
  deleteProject(input: DeleteProjectInput!): Project
}

type Query {
  getTask(id: ID!): Task
  listTasks(filter: ModelTaskFilterInput, limit: Int, nextToken: String): ModelTaskConnection
  getProject(id: ID!): Project
  listProjects(filter: ModelProjectFilterInput, limit: Int, nextToken: String): ModelProjectConnection
}

type Subscription {
  onCreateTask(owner: String): Task @aws_subscribe(mutations: ["createTask"])
  onUpdateTask(owner: String): Task @aws_subscribe(mutations: ["updateTask"])
  onDeleteTask(owner: String): Task @aws_subscribe(mutations: ["deleteTask"])
  onCreateProject(owner: String): Project @aws_subscribe(mutations: ["createProject"])
  onUpdateProject(owner: String): Project @aws_subscribe(mutations: ["updateProject"])
  onDeleteProject(owner: String): Project @aws_subscribe(mutations: ["deleteProject"])
}

input CreateTaskInput {
  title: String!
  description: String
  priority: Priority!
  status: Status
  dueDate: AWSDateTime
  tags: [String]
  projectId: ID
}

input UpdateTaskInput {
  id: ID!
  title: String
  description: String
  priority: Priority
  status: Status
  dueDate: AWSDateTime
  tags: [String]
  projectId: ID
}

input DeleteTaskInput {
  id: ID!
}

input CreateProjectInput {
  name: String!
  description: String
  color: String
}

input UpdateProjectInput {
  id: ID!
  name: String
  description: String
  color: String
}

input DeleteProjectInput {
  id: ID!
}

input ModelTaskFilterInput {
  id: ModelIDInput
  title: ModelStringInput
  description: ModelStringInput
  priority: ModelPriorityInput
  status: ModelStatusInput
  dueDate: ModelStringInput
  projectId: ModelIDInput
  and: [ModelTaskFilterInput]
  or: [ModelTaskFilterInput]
  not: ModelTaskFilterInput
}

input ModelProjectFilterInput {
  id: ModelIDInput
  name: ModelStringInput
  description: ModelStringInput
  color: ModelStringInput
  and: [ModelProjectFilterInput]
  or: [ModelProjectFilterInput]
  not: ModelProjectFilterInput
}

input ModelIDInput {
  ne: ID
  eq: ID
  le: ID
  lt: ID
  ge: ID
  gt: ID
  contains: ID
  notContains: ID
  between: [ID]
  beginsWith: ID
  attributeExists: Boolean
  attributeType: ModelAttributeTypes
  size: ModelSizeInput
}

input ModelStringInput {
  ne: String
  eq: String
  le: String
  lt: String
  ge: String
  gt: String
  contains: String
  notContains: String
  between: [String]
  beginsWith: String
  attributeExists: Boolean
  attributeType: ModelAttributeTypes
  size: ModelSizeInput
}

input ModelPriorityInput {
  eq: Priority
  ne: Priority
}

input ModelStatusInput {
  eq: Status
  ne: Status
}

input ModelSizeInput {
  ne: Int
  eq: Int
  le: Int
  lt: Int
  ge: Int
  gt: Int
  between: [Int]
}

enum ModelAttributeTypes {
  binary
  binarySet
  bool
  list
  map
  number
  numberSet
  string
  stringSet
  _null
}

type ModelTaskConnection {
  items: [Task]
  nextToken: String
}

type ModelProjectConnection {
  items: [Project]
  nextToken: String
}
'''

        # Write schema to file
        with open("schema.graphql", "w") as f:
            f.write(schema_content)


def main():
    """Main function to create and deploy the CDK app."""
    app = cdk.App()
    
    # Create the GraphQL schema asset
    GraphQLSchemaAsset(app, "GraphQLSchemaAsset")
    
    # Create the main stack
    OfflineFirstMobileStack(
        app, 
        "OfflineFirstMobileStack",
        env=cdk.Environment(
            account=os.getenv('CDK_DEFAULT_ACCOUNT'),
            region=os.getenv('CDK_DEFAULT_REGION')
        ),
        description="Infrastructure for offline-first mobile applications with Amplify DataStore"
    )
    
    app.synth()


if __name__ == "__main__":
    main()