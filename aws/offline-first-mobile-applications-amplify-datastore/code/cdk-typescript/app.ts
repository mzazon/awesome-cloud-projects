#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as amplify from '@aws-cdk/aws-amplify-alpha';
import * as fs from 'fs';
import * as path from 'path';

export interface OfflineFirstMobileAppProps extends cdk.StackProps {
  readonly appName?: string;
  readonly environment?: string;
  readonly enableBackup?: boolean;
  readonly conflictResolution?: 'OPTIMISTIC_CONCURRENCY' | 'LAMBDA' | 'AUTOMERGE';
  readonly syncPageSize?: number;
  readonly maxRecordsToSync?: number;
}

export class OfflineFirstMobileAppStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly identityPool: cognito.CfnIdentityPool;
  public readonly graphqlApi: appsync.GraphqlApi;
  public readonly taskTable: dynamodb.Table;
  public readonly projectTable: dynamodb.Table;
  public readonly amplifyApp: amplify.App;

  constructor(scope: Construct, id: string, props: OfflineFirstMobileAppProps = {}) {
    super(scope, id, props);

    const appName = props.appName || 'offline-first-mobile-app';
    const environment = props.environment || 'dev';
    const enableBackup = props.enableBackup ?? true;
    const conflictResolution = props.conflictResolution || 'AUTOMERGE';
    const syncPageSize = props.syncPageSize || 1000;
    const maxRecordsToSync = props.maxRecordsToSync || 10000;

    // Tags for all resources
    const commonTags = {
      Project: appName,
      Environment: environment,
      Stack: 'OfflineFirstMobileApp',
      ManagedBy: 'CDK'
    };

    // Apply tags to the stack
    cdk.Tags.of(this).add('Project', appName);
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('Stack', 'OfflineFirstMobileApp');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');

    // Create Cognito User Pool for authentication
    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `${appName}-user-pool`,
      selfSignUpEnabled: true,
      userVerification: {
        emailSubject: 'Verify your email for our app!',
        emailBody: 'Thanks for signing up! Your verification code is {####}',
        emailStyle: cognito.VerificationEmailStyle.CODE,
      },
      signInAliases: {
        username: true,
        email: true,
      },
      signInCaseSensitive: false,
      standardAttributes: {
        email: {
          required: true,
          mutable: true,
        },
        givenName: {
          required: true,
          mutable: true,
        },
        familyName: {
          required: true,
          mutable: true,
        },
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create User Pool Client
    this.userPoolClient = this.userPool.addClient('UserPoolClient', {
      userPoolClientName: `${appName}-user-pool-client`,
      generateSecret: false,
      authFlows: {
        userSrp: true,
        userPassword: true,
      },
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
      },
      preventUserExistenceErrors: true,
    });

    // Create Identity Pool
    this.identityPool = new cognito.CfnIdentityPool(this, 'IdentityPool', {
      identityPoolName: `${appName}-identity-pool`,
      allowUnauthenticatedIdentities: false,
      cognitoIdentityProviders: [{
        clientId: this.userPoolClient.userPoolClientId,
        providerName: this.userPool.userPoolProviderName,
      }],
    });

    // Create IAM roles for authenticated and unauthenticated users
    const authenticatedRole = new iam.Role(this, 'AuthenticatedRole', {
      assumedBy: new iam.FederatedPrincipal(
        'cognito-identity.amazonaws.com',
        {
          StringEquals: {
            'cognito-identity.amazonaws.com:aud': this.identityPool.ref,
          },
          'ForAnyValue:StringLike': {
            'cognito-identity.amazonaws.com:amr': 'authenticated',
          },
        },
        'sts:AssumeRoleWithWebIdentity'
      ),
    });

    const unauthenticatedRole = new iam.Role(this, 'UnauthenticatedRole', {
      assumedBy: new iam.FederatedPrincipal(
        'cognito-identity.amazonaws.com',
        {
          StringEquals: {
            'cognito-identity.amazonaws.com:aud': this.identityPool.ref,
          },
          'ForAnyValue:StringLike': {
            'cognito-identity.amazonaws.com:amr': 'unauthenticated',
          },
        },
        'sts:AssumeRoleWithWebIdentity'
      ),
    });

    // Attach roles to identity pool
    new cognito.CfnIdentityPoolRoleAttachment(this, 'IdentityPoolRoleAttachment', {
      identityPoolId: this.identityPool.ref,
      roles: {
        authenticated: authenticatedRole.roleArn,
        unauthenticated: unauthenticatedRole.roleArn,
      },
    });

    // Create DynamoDB tables for data storage
    this.taskTable = new dynamodb.Table(this, 'TaskTable', {
      tableName: `${appName}-Task-${environment}`,
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: enableBackup,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add Global Secondary Index for Task queries
    this.taskTable.addGlobalSecondaryIndex({
      indexName: 'byOwner',
      partitionKey: { name: 'owner', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
    });

    this.taskTable.addGlobalSecondaryIndex({
      indexName: 'byStatus',
      partitionKey: { name: 'status', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'updatedAt', type: dynamodb.AttributeType.STRING },
    });

    this.taskTable.addGlobalSecondaryIndex({
      indexName: 'byProject',
      partitionKey: { name: 'projectId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
    });

    this.projectTable = new dynamodb.Table(this, 'ProjectTable', {
      tableName: `${appName}-Project-${environment}`,
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: enableBackup,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add Global Secondary Index for Project queries
    this.projectTable.addGlobalSecondaryIndex({
      indexName: 'byOwner',
      partitionKey: { name: 'owner', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
    });

    // Create conflict resolution Lambda if using LAMBDA strategy
    let conflictResolverFunction: lambda.Function | undefined;
    if (conflictResolution === 'LAMBDA') {
      conflictResolverFunction = new lambda.Function(this, 'ConflictResolverFunction', {
        runtime: lambda.Runtime.NODEJS_18_X,
        handler: 'index.handler',
        code: lambda.Code.fromInline(`
          exports.handler = async (event) => {
            console.log('Conflict resolver event:', JSON.stringify(event, null, 2));
            
            // Extract conflict data
            const { localModel, remoteModel, modelName } = event;
            
            // Custom conflict resolution logic
            if (modelName === 'Task') {
              return resolveTaskConflict(localModel, remoteModel);
            } else if (modelName === 'Project') {
              return resolveProjectConflict(localModel, remoteModel);
            }
            
            // Default to most recent update
            return new Date(localModel.updatedAt) > new Date(remoteModel.updatedAt) 
              ? localModel : remoteModel;
          };
          
          function resolveTaskConflict(localModel, remoteModel) {
            // Priority-based conflict resolution
            const priorityWeights = {
              'LOW': 1,
              'MEDIUM': 2,
              'HIGH': 3,
              'URGENT': 4
            };
            
            // Completed tasks take precedence
            if (localModel.status === 'COMPLETED' && remoteModel.status !== 'COMPLETED') {
              return localModel;
            }
            
            // Higher priority wins
            const localPriority = priorityWeights[localModel.priority] || 1;
            const remotePriority = priorityWeights[remoteModel.priority] || 1;
            
            if (localPriority > remotePriority) {
              return localModel;
            }
            
            // Most recent update wins
            return new Date(localModel.updatedAt) > new Date(remoteModel.updatedAt) 
              ? localModel : remoteModel;
          }
          
          function resolveProjectConflict(localModel, remoteModel) {
            // Most recent update wins for projects
            return new Date(localModel.updatedAt) > new Date(remoteModel.updatedAt) 
              ? localModel : remoteModel;
          }
        `),
        timeout: cdk.Duration.seconds(30),
        environment: {
          NODE_ENV: environment,
        },
      });
    }

    // Create AppSync GraphQL API
    this.graphqlApi = new appsync.GraphqlApi(this, 'GraphqlApi', {
      name: `${appName}-api`,
      schema: appsync.SchemaFile.fromAsset(path.join(__dirname, 'schema.graphql')),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.USER_POOL,
          userPoolConfig: {
            userPool: this.userPool,
          },
        },
      },
      xrayEnabled: true,
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
      },
    });

    // Create data sources
    const taskDataSource = this.graphqlApi.addDynamoDbDataSource('TaskDataSource', this.taskTable);
    const projectDataSource = this.graphqlApi.addDynamoDbDataSource('ProjectDataSource', this.projectTable);

    // Create resolvers for Task operations
    taskDataSource.createResolver('CreateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'createTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($input = $ctx.args.input)
        #set($input.id = $util.autoId())
        #set($input.owner = $ctx.identity.username)
        #set($input.createdAt = $util.time.nowISO8601())
        #set($input.updatedAt = $util.time.nowISO8601())
        #set($input._version = 1)
        {
          "version": "2018-05-29",
          "operation": "PutItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($input.id)
          },
          "attributeValues": $util.dynamodb.toMapValuesJson($input),
          "condition": {
            "expression": "attribute_not_exists(#id)",
            "expressionNames": {
              "#id": "id"
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

    taskDataSource.createResolver('UpdateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'updateTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($input = $ctx.args.input)
        #set($input.updatedAt = $util.time.nowISO8601())
        #set($input._version = $input._version + 1)
        {
          "version": "2018-05-29",
          "operation": "UpdateItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($input.id)
          },
          "update": {
            "expression": "SET #updatedAt = :updatedAt, #version = :version",
            "expressionNames": {
              "#updatedAt": "updatedAt",
              "#version": "_version"
            },
            "expressionValues": {
              ":updatedAt": $util.dynamodb.toDynamoDBJson($input.updatedAt),
              ":version": $util.dynamodb.toDynamoDBJson($input._version)
            }
          },
          "condition": {
            "expression": "#owner = :owner",
            "expressionNames": {
              "#owner": "owner"
            },
            "expressionValues": {
              ":owner": $util.dynamodb.toDynamoDBJson($ctx.identity.username)
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

    taskDataSource.createResolver('GetTaskResolver', {
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
        #if($ctx.result.owner != $ctx.identity.username)
          $util.unauthorized()
        #end
        $util.toJson($ctx.result)
      `),
    });

    taskDataSource.createResolver('ListTasksResolver', {
      typeName: 'Query',
      fieldName: 'listTasks',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2018-05-29",
          "operation": "Query",
          "index": "byOwner",
          "query": {
            "expression": "#owner = :owner",
            "expressionNames": {
              "#owner": "owner"
            },
            "expressionValues": {
              ":owner": $util.dynamodb.toDynamoDBJson($ctx.identity.username)
            }
          },
          "limit": $util.defaultIfNull($ctx.args.limit, 20),
          "nextToken": $util.toJson($util.defaultIfNullOrBlank($ctx.args.nextToken, null))
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    taskDataSource.createResolver('DeleteTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteTask',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2018-05-29",
          "operation": "DeleteItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($ctx.args.input.id)
          },
          "condition": {
            "expression": "#owner = :owner",
            "expressionNames": {
              "#owner": "owner"
            },
            "expressionValues": {
              ":owner": $util.dynamodb.toDynamoDBJson($ctx.identity.username)
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

    // Create resolvers for Project operations
    projectDataSource.createResolver('CreateProjectResolver', {
      typeName: 'Mutation',
      fieldName: 'createProject',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($input = $ctx.args.input)
        #set($input.id = $util.autoId())
        #set($input.owner = $ctx.identity.username)
        #set($input.createdAt = $util.time.nowISO8601())
        #set($input.updatedAt = $util.time.nowISO8601())
        #set($input._version = 1)
        {
          "version": "2018-05-29",
          "operation": "PutItem",
          "key": {
            "id": $util.dynamodb.toDynamoDBJson($input.id)
          },
          "attributeValues": $util.dynamodb.toMapValuesJson($input),
          "condition": {
            "expression": "attribute_not_exists(#id)",
            "expressionNames": {
              "#id": "id"
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

    projectDataSource.createResolver('ListProjectsResolver', {
      typeName: 'Query',
      fieldName: 'listProjects',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2018-05-29",
          "operation": "Query",
          "index": "byOwner",
          "query": {
            "expression": "#owner = :owner",
            "expressionNames": {
              "#owner": "owner"
            },
            "expressionValues": {
              ":owner": $util.dynamodb.toDynamoDBJson($ctx.identity.username)
            }
          },
          "limit": $util.defaultIfNull($ctx.args.limit, 20),
          "nextToken": $util.toJson($util.defaultIfNullOrBlank($ctx.args.nextToken, null))
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    // Grant authenticated users access to their own data
    const authenticatedPolicy = new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:GetItem',
        'dynamodb:PutItem',
        'dynamodb:UpdateItem',
        'dynamodb:DeleteItem',
        'dynamodb:Query',
        'dynamodb:Scan',
      ],
      resources: [
        this.taskTable.tableArn,
        `${this.taskTable.tableArn}/index/*`,
        this.projectTable.tableArn,
        `${this.projectTable.tableArn}/index/*`,
      ],
      conditions: {
        'ForAllValues:StringEquals': {
          'dynamodb:LeadingKeys': ['${cognito-identity.amazonaws.com:sub}'],
        },
      },
    });

    authenticatedRole.addToPolicy(authenticatedPolicy);

    // Grant AppSync access to DynamoDB
    this.taskTable.grantFullAccess(this.graphqlApi);
    this.projectTable.grantFullAccess(this.graphqlApi);

    // Grant conflict resolver function access to tables if using LAMBDA strategy
    if (conflictResolverFunction) {
      this.taskTable.grantReadWriteData(conflictResolverFunction);
      this.projectTable.grantReadWriteData(conflictResolverFunction);
    }

    // Create Amplify App for hosting (optional)
    this.amplifyApp = new amplify.App(this, 'AmplifyApp', {
      appName: `${appName}-amplify`,
      sourceCodeProvider: new amplify.GitHubSourceCodeProvider({
        owner: 'your-github-username',
        repository: 'your-repo-name',
        oauthToken: cdk.SecretValue.secretsManager('github-token'),
      }),
      environmentVariables: {
        AMPLIFY_MONOREPO_APP_ROOT: 'mobile',
        AMPLIFY_DIFF_DEPLOY: 'false',
        AMPLIFY_DIFF_DEPLOY_ROOT: 'mobile',
      },
      customRules: [
        {
          source: '/<*>',
          target: '/index.html',
          status: amplify.RedirectStatus.NOT_FOUND_REWRITE,
        },
      ],
    });

    // Add branch
    const mainBranch = this.amplifyApp.addBranch('main', {
      branchName: 'main',
      stage: environment === 'prod' ? 'PRODUCTION' : 'DEVELOPMENT',
    });

    // Output important values
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: `${appName}-UserPoolId`,
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: `${appName}-UserPoolClientId`,
    });

    new cdk.CfnOutput(this, 'IdentityPoolId', {
      value: this.identityPool.ref,
      description: 'Cognito Identity Pool ID',
      exportName: `${appName}-IdentityPoolId`,
    });

    new cdk.CfnOutput(this, 'GraphQLAPIEndpoint', {
      value: this.graphqlApi.graphqlUrl,
      description: 'AppSync GraphQL API Endpoint',
      exportName: `${appName}-GraphQLAPIEndpoint`,
    });

    new cdk.CfnOutput(this, 'GraphQLAPIKey', {
      value: this.graphqlApi.apiKey || 'N/A',
      description: 'AppSync GraphQL API Key (if applicable)',
      exportName: `${appName}-GraphQLAPIKey`,
    });

    new cdk.CfnOutput(this, 'TaskTableName', {
      value: this.taskTable.tableName,
      description: 'Task DynamoDB Table Name',
      exportName: `${appName}-TaskTableName`,
    });

    new cdk.CfnOutput(this, 'ProjectTableName', {
      value: this.projectTable.tableName,
      description: 'Project DynamoDB Table Name',
      exportName: `${appName}-ProjectTableName`,
    });

    new cdk.CfnOutput(this, 'AmplifyAppId', {
      value: this.amplifyApp.appId,
      description: 'Amplify App ID',
      exportName: `${appName}-AmplifyAppId`,
    });

    new cdk.CfnOutput(this, 'AmplifyAppURL', {
      value: `https://${mainBranch.branchName}.${this.amplifyApp.appId}.amplifyapp.com`,
      description: 'Amplify App URL',
      exportName: `${appName}-AmplifyAppURL`,
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
      exportName: `${appName}-Region`,
    });

    // Configuration for Amplify CLI
    new cdk.CfnOutput(this, 'AmplifyConfiguration', {
      value: JSON.stringify({
        Auth: {
          region: this.region,
          userPoolId: this.userPool.userPoolId,
          userPoolWebClientId: this.userPoolClient.userPoolClientId,
          identityPoolId: this.identityPool.ref,
        },
        API: {
          GraphQL: {
            endpoint: this.graphqlApi.graphqlUrl,
            region: this.region,
            authMode: 'AMAZON_COGNITO_USER_POOLS',
          },
        },
        DataStore: {
          syncPageSize: syncPageSize,
          maxRecordsToSync: maxRecordsToSync,
          conflictResolution: conflictResolution,
          syncExpressions: [
            {
              modelName: 'Task',
              conditionExpression: 'createdAt > :thirtyDaysAgo AND status <> :cancelled',
              expressionAttributeValues: {
                ':thirtyDaysAgo': new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(),
                ':cancelled': 'CANCELLED',
              },
            },
            {
              modelName: 'Project',
              conditionExpression: 'attribute_exists(id)',
            },
          ],
        },
      }, null, 2),
      description: 'Amplify Configuration JSON',
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Get context values
const appName = app.node.tryGetContext('appName') || 'offline-first-mobile-app';
const environment = app.node.tryGetContext('environment') || 'dev';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

// Create the stack
new OfflineFirstMobileAppStack(app, `${appName}-stack-${environment}`, {
  appName,
  environment,
  enableBackup: environment === 'prod',
  conflictResolution: 'AUTOMERGE',
  syncPageSize: 1000,
  maxRecordsToSync: 10000,
  env: {
    account,
    region,
  },
  description: `CDK Stack for ${appName} offline-first mobile application (${environment})`,
});

// Write schema file
if (!fs.existsSync(path.join(__dirname, 'schema.graphql'))) {
  fs.writeFileSync(path.join(__dirname, 'schema.graphql'), `
type Task @model @auth(rules: [{ allow: owner }]) {
  id: ID!
  title: String!
  description: String
  priority: Priority!
  status: Status!
  dueDate: AWSDateTime
  tags: [String]
  projectId: ID
  createdAt: AWSDateTime!
  updatedAt: AWSDateTime!
  owner: String @auth(rules: [{ allow: owner, operations: [read] }])
  _version: Int!
  _deleted: Boolean
  _lastChangedAt: AWSTimestamp!
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
  _version: Int!
  _deleted: Boolean
  _lastChangedAt: AWSTimestamp!
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

type ModelTaskConnection {
  items: [Task!]!
  nextToken: String
  startedAt: AWSTimestamp
}

type ModelProjectConnection {
  items: [Project!]!
  nextToken: String
  startedAt: AWSTimestamp
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

input ModelIntInput {
  ne: Int
  eq: Int
  le: Int
  lt: Int
  ge: Int
  gt: Int
  between: [Int]
  attributeExists: Boolean
  attributeType: ModelAttributeTypes
}

input ModelFloatInput {
  ne: Float
  eq: Float
  le: Float
  lt: Float
  ge: Float
  gt: Float
  between: [Float]
  attributeExists: Boolean
  attributeType: ModelAttributeTypes
}

input ModelBooleanInput {
  ne: Boolean
  eq: Boolean
  attributeExists: Boolean
  attributeType: ModelAttributeTypes
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

type Query {
  getTask(id: ID!): Task
  listTasks(filter: ModelTaskFilterInput, limit: Int, nextToken: String): ModelTaskConnection
  syncTasks(filter: ModelTaskFilterInput, limit: Int, nextToken: String, lastSync: AWSTimestamp): ModelTaskConnection
  
  getProject(id: ID!): Project
  listProjects(filter: ModelProjectFilterInput, limit: Int, nextToken: String): ModelProjectConnection
  syncProjects(filter: ModelProjectFilterInput, limit: Int, nextToken: String, lastSync: AWSTimestamp): ModelProjectConnection
}

input ModelTaskFilterInput {
  id: ModelIDInput
  title: ModelStringInput
  description: ModelStringInput
  priority: ModelPriorityInput
  status: ModelStatusInput
  dueDate: ModelStringInput
  tags: ModelStringInput
  projectId: ModelIDInput
  createdAt: ModelStringInput
  updatedAt: ModelStringInput
  owner: ModelStringInput
  and: [ModelTaskFilterInput]
  or: [ModelTaskFilterInput]
  not: ModelTaskFilterInput
}

input ModelProjectFilterInput {
  id: ModelIDInput
  name: ModelStringInput
  description: ModelStringInput
  color: ModelStringInput
  createdAt: ModelStringInput
  updatedAt: ModelStringInput
  owner: ModelStringInput
  and: [ModelProjectFilterInput]
  or: [ModelProjectFilterInput]
  not: ModelProjectFilterInput
}

input ModelPriorityInput {
  eq: Priority
  ne: Priority
}

input ModelStatusInput {
  eq: Status
  ne: Status
}

type Mutation {
  createTask(input: CreateTaskInput!, condition: ModelTaskConditionInput): Task
  updateTask(input: UpdateTaskInput!, condition: ModelTaskConditionInput): Task
  deleteTask(input: DeleteTaskInput!, condition: ModelTaskConditionInput): Task
  
  createProject(input: CreateProjectInput!, condition: ModelProjectConditionInput): Project
  updateProject(input: UpdateProjectInput!, condition: ModelProjectConditionInput): Project
  deleteProject(input: DeleteProjectInput!, condition: ModelProjectConditionInput): Project
}

input CreateTaskInput {
  id: ID
  title: String!
  description: String
  priority: Priority!
  status: Status!
  dueDate: AWSDateTime
  tags: [String]
  projectId: ID
  _version: Int
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
  _version: Int
}

input DeleteTaskInput {
  id: ID!
  _version: Int
}

input CreateProjectInput {
  id: ID
  name: String!
  description: String
  color: String
  _version: Int
}

input UpdateProjectInput {
  id: ID!
  name: String
  description: String
  color: String
  _version: Int
}

input DeleteProjectInput {
  id: ID!
  _version: Int
}

input ModelTaskConditionInput {
  title: ModelStringInput
  description: ModelStringInput
  priority: ModelPriorityInput
  status: ModelStatusInput
  dueDate: ModelStringInput
  tags: ModelStringInput
  projectId: ModelIDInput
  createdAt: ModelStringInput
  updatedAt: ModelStringInput
  owner: ModelStringInput
  and: [ModelTaskConditionInput]
  or: [ModelTaskConditionInput]
  not: ModelTaskConditionInput
}

input ModelProjectConditionInput {
  name: ModelStringInput
  description: ModelStringInput
  color: ModelStringInput
  createdAt: ModelStringInput
  updatedAt: ModelStringInput
  owner: ModelStringInput
  and: [ModelProjectConditionInput]
  or: [ModelProjectConditionInput]
  not: ModelProjectConditionInput
}

type Subscription {
  onCreateTask(owner: String): Task
    @aws_subscribe(mutations: ["createTask"])
  onUpdateTask(owner: String): Task
    @aws_subscribe(mutations: ["updateTask"])
  onDeleteTask(owner: String): Task
    @aws_subscribe(mutations: ["deleteTask"])
    
  onCreateProject(owner: String): Project
    @aws_subscribe(mutations: ["createProject"])
  onUpdateProject(owner: String): Project
    @aws_subscribe(mutations: ["updateProject"])
  onDeleteProject(owner: String): Project
    @aws_subscribe(mutations: ["deleteProject"])
}
`);
}

app.synth();