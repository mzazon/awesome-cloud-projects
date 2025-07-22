import * as cdk from 'aws-cdk-lib';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for Serverless GraphQL API with AppSync and EventBridge Scheduler
 * 
 * This stack creates a complete task management system with:
 * - GraphQL API using AWS AppSync with real-time subscriptions
 * - DynamoDB table for persistent task storage
 * - Lambda function for business logic and task processing
 * - EventBridge Scheduler for automated task reminders
 * - Proper IAM roles and security configurations
 */
export class ServerlessGraphQLApiStack extends cdk.Stack {
  // Public properties for cross-stack references
  public readonly api: appsync.GraphqlApi;
  public readonly tasksTable: dynamodb.Table;
  public readonly taskProcessor: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create DynamoDB table for task storage
    this.tasksTable = this.createTasksTable(uniqueSuffix);

    // Create Lambda function for task processing
    this.taskProcessor = this.createTaskProcessor(uniqueSuffix);

    // Create AppSync GraphQL API
    this.api = this.createGraphQLAPI(uniqueSuffix);

    // Configure data sources and resolvers
    this.configureDataSources();

    // Create EventBridge Scheduler role
    this.createSchedulerRole();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates a DynamoDB table for storing tasks with optimized access patterns
   */
  private createTasksTable(uniqueSuffix: string): dynamodb.Table {
    const table = new dynamodb.Table(this, 'TasksTable', {
      tableName: `Tasks-${uniqueSuffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      tags: [
        { key: 'Component', value: 'TaskStorage' },
        { key: 'DataType', value: 'Tasks' }
      ]
    });

    // Add Global Secondary Index for querying tasks by user
    table.addGlobalSecondaryIndex({
      indexName: 'UserIdIndex',
      partitionKey: {
        name: 'userId',
        type: dynamodb.AttributeType.STRING
      },
      projectionType: dynamodb.ProjectionType.ALL
    });

    // Add Local Secondary Index for querying tasks by status
    table.addLocalSecondaryIndex({
      indexName: 'StatusIndex',
      sortKey: {
        name: 'status',
        type: dynamodb.AttributeType.STRING
      },
      projectionType: dynamodb.ProjectionType.ALL
    });

    return table;
  }

  /**
   * Creates a Lambda function for processing tasks and handling business logic
   */
  private createTaskProcessor(uniqueSuffix: string): lambda.Function {
    // Create IAM role for Lambda with minimum required permissions
    const lambdaRole = new iam.Role(this, 'TaskProcessorRole', {
      roleName: `TaskProcessor-Role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        AppSyncAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['appsync:GraphQL'],
              resources: ['*'] // Will be refined after API creation
            })
          ]
        })
      }
    });

    // Create Lambda function
    const taskProcessor = new lambda.Function(this, 'TaskProcessor', {
      functionName: `TaskProcessor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(1),
      memorySize: 256,
      environment: {
        TASKS_TABLE_NAME: this.tasksTable.tableName,
        // API_ID will be set after API creation
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timezone

appsync = boto3.client('appsync')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    """
    Process scheduled task reminders from EventBridge Scheduler
    """
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Extract task ID from event
        task_id = event.get('taskId')
        if not task_id:
            raise ValueError("No taskId provided in event")
        
        # Get API ID from environment
        api_id = os.environ.get('API_ID')
        if not api_id:
            raise ValueError("API_ID environment variable not set")
        
        # Prepare GraphQL mutation for sending reminder
        mutation = '''
        mutation SendReminder($taskId: ID!) {
            sendReminder(taskId: $taskId) {
                id
                title
                status
                updatedAt
            }
        }
        '''
        
        # Execute mutation via AppSync
        response = appsync.graphql(
            apiId=api_id,
            query=mutation,
            variables={'taskId': task_id}
        )
        
        print(f"Reminder sent successfully: {response}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Reminder sent successfully',
                'taskId': task_id
            })
        }
        
    except Exception as e:
        print(f"Error processing reminder: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'taskId': event.get('taskId', 'unknown')
            })
        }
`)
    });

    // Grant the Lambda function read access to the DynamoDB table
    this.tasksTable.grantReadData(taskProcessor);

    return taskProcessor;
  }

  /**
   * Creates the AppSync GraphQL API with comprehensive schema and security
   */
  private createGraphQLAPI(uniqueSuffix: string): appsync.GraphqlApi {
    // Create the AppSync API with inline schema
    const api = new appsync.GraphqlApi(this, 'TaskManagerAPI', {
      name: `TaskManagerAPI-${uniqueSuffix}`,
      schema: appsync.SchemaFile.fromInline(`
        type Task {
          id: ID!
          userId: String!
          title: String!
          description: String
          dueDate: String!
          status: TaskStatus!
          reminderTime: String
          createdAt: String!
          updatedAt: String!
        }
        
        enum TaskStatus {
          PENDING
          IN_PROGRESS
          COMPLETED
          CANCELLED
        }
        
        input CreateTaskInput {
          title: String!
          description: String
          dueDate: String!
          reminderTime: String
        }
        
        input UpdateTaskInput {
          id: ID!
          title: String
          description: String
          status: TaskStatus
          dueDate: String
          reminderTime: String
        }
        
        type Query {
          getTask(id: ID!): Task
          listUserTasks(userId: String!): [Task]
        }
        
        type Mutation {
          createTask(input: CreateTaskInput!): Task
          updateTask(input: UpdateTaskInput!): Task
          deleteTask(id: ID!): Task
          sendReminder(taskId: ID!): Task
        }
        
        type Subscription {
          onTaskCreated(userId: String!): Task
            @aws_subscribe(mutations: ["createTask"])
          onTaskUpdated(userId: String!): Task
            @aws_subscribe(mutations: ["updateTask", "sendReminder"])
          onTaskDeleted(userId: String!): Task
            @aws_subscribe(mutations: ["deleteTask"])
        }
        
        schema {
          query: Query
          mutation: Mutation
          subscription: Subscription
        }
      `),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.IAM
        },
        additionalAuthorizationModes: [
          {
            authorizationType: appsync.AuthorizationType.API_KEY,
            apiKeyConfig: {
              expires: cdk.Expiration.after(cdk.Duration.days(365))
            }
          }
        ]
      },
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        retention: logs.RetentionDays.ONE_WEEK
      },
      xrayEnabled: true
    });

    // Update Lambda function environment with API ID
    this.taskProcessor.addEnvironment('API_ID', api.apiId);

    return api;
  }

  /**
   * Configures data sources and resolvers for the GraphQL API
   */
  private configureDataSources(): void {
    // Create DynamoDB data source
    const tasksDataSource = this.api.addDynamoDbDataSource(
      'TasksDataSource',
      this.tasksTable,
      {
        description: 'Data source for Tasks table'
      }
    );

    // Create Lambda data source
    const lambdaDataSource = this.api.addLambdaDataSource(
      'TaskProcessorDataSource',
      this.taskProcessor,
      {
        description: 'Data source for task processing logic'
      }
    );

    // Create resolvers for queries
    tasksDataSource.createResolver('GetTaskResolver', {
      typeName: 'Query',
      fieldName: 'getTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "operation": "GetItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
          }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)')
    });

    tasksDataSource.createResolver('ListUserTasksResolver', {
      typeName: 'Query',
      fieldName: 'listUserTasks',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "operation": "Query",
          "index": "UserIdIndex",
          "query": {
            "expression": "userId = :userId",
            "expressionValues": {
              ":userId": $util.dynamodb.toDynamoDBJson($ctx.args.userId)
            }
          }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result.items)')
    });

    // Create resolvers for mutations
    tasksDataSource.createResolver('CreateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'createTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($id = $util.autoId())
        {
          "version": "2017-02-28",
          "operation": "PutItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($id)
          },
          "attributeValues": {
            "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.userArn),
            "title": $util.dynamodb.toDynamoDBJson($ctx.args.input.title),
            "description": $util.dynamodb.toDynamoDBJson($ctx.args.input.description),
            "dueDate": $util.dynamodb.toDynamoDBJson($ctx.args.input.dueDate),
            "status": $util.dynamodb.toDynamoDBJson("PENDING"),
            "reminderTime": $util.dynamodb.toDynamoDBJson($ctx.args.input.reminderTime),
            "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
            "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
          }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)')
    });

    tasksDataSource.createResolver('UpdateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'updateTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($update = {
          "expression": "SET updatedAt = :updatedAt",
          "expressionNames": {},
          "expressionValues": {
            ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
          }
        })
        
        #if($ctx.args.input.title)
          #set($update.expression = "$update.expression, title = :title")
          $util.qr($update.expressionValues.put(":title", $util.dynamodb.toDynamoDBJson($ctx.args.input.title)))
        #end
        
        #if($ctx.args.input.description)
          #set($update.expression = "$update.expression, description = :description")
          $util.qr($update.expressionValues.put(":description", $util.dynamodb.toDynamoDBJson($ctx.args.input.description)))
        #end
        
        #if($ctx.args.input.status)
          #set($update.expression = "$update.expression, #status = :status")
          $util.qr($update.expressionNames.put("#status", "status"))
          $util.qr($update.expressionValues.put(":status", $util.dynamodb.toDynamoDBJson($ctx.args.input.status)))
        #end
        
        #if($ctx.args.input.dueDate)
          #set($update.expression = "$update.expression, dueDate = :dueDate")
          $util.qr($update.expressionValues.put(":dueDate", $util.dynamodb.toDynamoDBJson($ctx.args.input.dueDate)))
        #end
        
        #if($ctx.args.input.reminderTime)
          #set($update.expression = "$update.expression, reminderTime = :reminderTime")
          $util.qr($update.expressionValues.put(":reminderTime", $util.dynamodb.toDynamoDBJson($ctx.args.input.reminderTime)))
        #end
        
        {
          "version": "2017-02-28",
          "operation": "UpdateItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
          },
          "update": $util.toJson($update)
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)')
    });

    tasksDataSource.createResolver('DeleteTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "operation": "DeleteItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($ctx.args.id)
          }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)')
    });

    // Use Lambda data source for sendReminder mutation
    lambdaDataSource.createResolver('SendReminderResolver', {
      typeName: 'Mutation',
      fieldName: 'sendReminder',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "operation": "Invoke",
          "payload": {
            "taskId": "$ctx.args.taskId",
            "action": "sendReminder",
            "timestamp": "$util.time.nowISO8601()"
          }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)')
    });
  }

  /**
   * Creates IAM role for EventBridge Scheduler to invoke AppSync
   */
  private createSchedulerRole(): iam.Role {
    const schedulerRole = new iam.Role(this, 'SchedulerRole', {
      roleName: `EventBridge-Scheduler-Role-${Math.random().toString(36).substring(2, 8)}`,
      assumedBy: new iam.ServicePrincipal('scheduler.amazonaws.com'),
      inlinePolicies: {
        AppSyncInvokePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['appsync:GraphQL'],
              resources: [this.api.arn + '/*']
            })
          ]
        })
      }
    });

    return schedulerRole;
  }

  /**
   * Creates CloudFormation outputs for important resource values
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'GraphQLAPIURL', {
      value: this.api.graphqlUrl,
      description: 'AppSync GraphQL API URL'
    });

    new cdk.CfnOutput(this, 'GraphQLAPIID', {
      value: this.api.apiId,
      description: 'AppSync GraphQL API ID'
    });

    new cdk.CfnOutput(this, 'GraphQLAPIKey', {
      value: this.api.apiKey || 'Not configured',
      description: 'AppSync API Key (if configured)'
    });

    new cdk.CfnOutput(this, 'TasksTableName', {
      value: this.tasksTable.tableName,
      description: 'DynamoDB Tasks table name'
    });

    new cdk.CfnOutput(this, 'TasksTableArn', {
      value: this.tasksTable.tableArn,
      description: 'DynamoDB Tasks table ARN'
    });

    new cdk.CfnOutput(this, 'TaskProcessorFunctionName', {
      value: this.taskProcessor.functionName,
      description: 'Lambda Task Processor function name'
    });

    new cdk.CfnOutput(this, 'TaskProcessorFunctionArn', {
      value: this.taskProcessor.functionArn,
      description: 'Lambda Task Processor function ARN'
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region where resources are deployed'
    });
  }
}