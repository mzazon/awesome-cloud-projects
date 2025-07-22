#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Real-time Data Synchronization with AWS AppSync
 * 
 * This stack creates:
 * - DynamoDB table with streams for task storage
 * - AppSync GraphQL API with real-time subscriptions
 * - IAM roles and policies for secure access
 * - CloudWatch logging for monitoring and debugging
 */
export class RealtimeDataSyncAppSyncStack extends cdk.Stack {
  public readonly graphqlApi: appsync.GraphqlApi;
  public readonly tasksTable: dynamodb.Table;
  public readonly apiKey: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create DynamoDB table for task storage with streams enabled
    this.tasksTable = new dynamodb.Table(this, 'TasksTable', {
      tableName: `tasks-${this.stackName.toLowerCase()}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      tags: {
        Purpose: 'AppSyncRealTimeDemo',
        Component: 'DataStorage',
      },
    });

    // Add Global Secondary Index for querying by status
    this.tasksTable.addGlobalSecondaryIndex({
      indexName: 'status-createdAt-index',
      partitionKey: {
        name: 'status',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Create CloudWatch Log Group for AppSync
    const logGroup = new logs.LogGroup(this, 'AppSyncLogGroup', {
      logGroupName: `/aws/appsync/apis/${id.toLowerCase()}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Define GraphQL schema with real-time subscriptions
    const schema = appsync.SchemaFile.fromAsset('schema.graphql');

    // Create AppSync GraphQL API
    this.graphqlApi = new appsync.GraphqlApi(this, 'TasksApi', {
      name: `realtime-tasks-${this.stackName.toLowerCase()}`,
      schema,
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.API_KEY,
          apiKeyConfig: {
            name: 'TasksApiKey',
            description: 'API Key for Real-time Tasks API',
            expires: cdk.Expiration.after(cdk.Duration.days(30)),
          },
        },
      },
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        cloudWatchLogsRoleArn: this.createCloudWatchLogsRole().roleArn,
      },
      xrayEnabled: true,
    });

    // Create DynamoDB data source
    const tasksDataSource = this.graphqlApi.addDynamoDbDataSource(
      'TasksDataSource',
      this.tasksTable,
      {
        description: 'DynamoDB data source for tasks',
      }
    );

    // Create resolvers for queries
    this.createQueryResolvers(tasksDataSource);

    // Create resolvers for mutations with conflict resolution
    this.createMutationResolvers(tasksDataSource);

    // Output important values
    new cdk.CfnOutput(this, 'GraphQLAPIURL', {
      value: this.graphqlApi.graphqlUrl,
      description: 'GraphQL API URL',
    });

    new cdk.CfnOutput(this, 'GraphQLAPIKey', {
      value: this.graphqlApi.apiKey || 'No API Key',
      description: 'GraphQL API Key',
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: this.tasksTable.tableName,
      description: 'DynamoDB Table Name',
    });

    new cdk.CfnOutput(this, 'GraphQLAPIID', {
      value: this.graphqlApi.apiId,
      description: 'GraphQL API ID',
    });

    // Store API key for easy access
    this.apiKey = this.graphqlApi.apiKey || '';
  }

  /**
   * Create CloudWatch Logs role for AppSync
   */
  private createCloudWatchLogsRole(): iam.Role {
    const role = new iam.Role(this, 'AppSyncCloudWatchLogsRole', {
      assumedBy: new iam.ServicePrincipal('appsync.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AppSyncPushToCloudWatchLogs'),
      ],
    });

    return role;
  }

  /**
   * Create query resolvers for getting and listing tasks
   */
  private createQueryResolvers(dataSource: appsync.DynamoDbDataSource): void {
    // getTask resolver
    dataSource.createResolver('GetTaskResolver', {
      typeName: 'Query',
      fieldName: 'getTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2018-05-29",
          "operation": "GetItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
          }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    // listTasks resolver
    dataSource.createResolver('ListTasksResolver', {
      typeName: 'Query',
      fieldName: 'listTasks',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2018-05-29",
          "operation": "Scan",
          "limit": #if($ctx.args.limit) $ctx.args.limit #else 20 #end,
          "nextToken": #if($ctx.args.nextToken) "$ctx.args.nextToken" #else null #end
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        {
          "items": $util.toJson($ctx.result.items),
          "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
        }
      `),
    });

    // listTasksByStatus resolver using GSI
    dataSource.createResolver('ListTasksByStatusResolver', {
      typeName: 'Query',
      fieldName: 'listTasksByStatus',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2018-05-29",
          "operation": "Query",
          "index": "status-createdAt-index",
          "query": {
            "expression": "#status = :status",
            "expressionNames": {
              "#status": "status"
            },
            "expressionValues": {
              ":status": $util.dynamodb.toDynamoDBJson($ctx.args.status)
            }
          },
          "limit": #if($ctx.args.limit) $ctx.args.limit #else 20 #end,
          "nextToken": #if($ctx.args.nextToken) "$ctx.args.nextToken" #else null #end,
          "scanIndexForward": false
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        {
          "items": $util.toJson($ctx.result.items),
          "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
        }
      `),
    });
  }

  /**
   * Create mutation resolvers with optimistic locking for conflict resolution
   */
  private createMutationResolvers(dataSource: appsync.DynamoDbDataSource): void {
    // createTask resolver
    dataSource.createResolver('CreateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'createTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    // updateTask resolver with optimistic locking
    dataSource.createResolver('UpdateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'updateTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($updatedAt = $util.time.nowISO8601())
        #set($updateExpression = "SET #updatedAt = :updatedAt, #version = #version + :incr")
        #set($expressionNames = {
          "#updatedAt": "updatedAt",
          "#version": "version"
        })
        #set($expressionValues = {
          ":updatedAt": $util.dynamodb.toDynamoDBJson($updatedAt),
          ":incr": $util.dynamodb.toDynamoDBJson(1),
          ":expectedVersion": $util.dynamodb.toDynamoDBJson($ctx.args.input.version)
        })

        ## Add conditional updates for provided fields
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    // deleteTask resolver with version checking
    dataSource.createResolver('DeleteTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });
  }
}

/**
 * CDK App - Entry point for the application
 */
const app = new cdk.App();

// Get environment configuration
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Create the stack
new RealtimeDataSyncAppSyncStack(app, 'RealtimeDataSyncAppSyncStack', {
  env,
  description: 'Real-time Data Synchronization with AWS AppSync - CDK Stack',
  tags: {
    Project: 'AWSRecipes',
    Component: 'RealtimeDataSync',
    Technology: 'AppSync',
  },
});

// Create schema.graphql file inline for simplicity
import * as fs from 'fs';
import * as path from 'path';

const schemaContent = `type Task {
    id: ID!
    title: String!
    description: String
    status: TaskStatus!
    priority: Priority!
    assignedTo: String
    createdAt: AWSDateTime!
    updatedAt: AWSDateTime!
    version: Int!
}

enum TaskStatus {
    TODO
    IN_PROGRESS
    COMPLETED
    ARCHIVED
}

enum Priority {
    LOW
    MEDIUM
    HIGH
    URGENT
}

input CreateTaskInput {
    title: String!
    description: String
    priority: Priority!
    assignedTo: String
}

input UpdateTaskInput {
    id: ID!
    title: String
    description: String
    status: TaskStatus
    priority: Priority
    assignedTo: String
    version: Int!
}

type Query {
    getTask(id: ID!): Task
    listTasks(status: TaskStatus, limit: Int, nextToken: String): TaskConnection
    listTasksByStatus(status: TaskStatus!, limit: Int, nextToken: String): TaskConnection
}

type Mutation {
    createTask(input: CreateTaskInput!): Task
    updateTask(input: UpdateTaskInput!): Task
    deleteTask(id: ID!, version: Int!): Task
}

type Subscription {
    onTaskCreated: Task
        @aws_subscribe(mutations: ["createTask"])
    onTaskUpdated: Task
        @aws_subscribe(mutations: ["updateTask"])
    onTaskDeleted: Task
        @aws_subscribe(mutations: ["deleteTask"])
}

type TaskConnection {
    items: [Task]
    nextToken: String
}

schema {
    query: Query
    mutation: Mutation
    subscription: Subscription
}`;

// Write schema file during build
const schemaPath = path.join(__dirname, 'schema.graphql');
if (!fs.existsSync(schemaPath)) {
  fs.writeFileSync(schemaPath, schemaContent);
}