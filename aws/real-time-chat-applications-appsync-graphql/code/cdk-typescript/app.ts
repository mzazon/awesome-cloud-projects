#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';

/**
 * Real-Time Chat Application Stack using AWS AppSync and GraphQL
 * 
 * This stack creates a complete serverless real-time chat application infrastructure including:
 * - Amazon Cognito User Pool for authentication
 * - DynamoDB tables for storing messages, conversations, and user data
 * - AWS AppSync GraphQL API with real-time subscriptions
 * - VTL resolvers for direct DynamoDB integration
 */
export class RealTimeChatStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 10);
    const appName = `realtime-chat-${uniqueSuffix}`;

    // ====================================
    // Amazon Cognito User Pool
    // ====================================
    
    // Create Cognito User Pool for user authentication
    const userPool = new cognito.UserPool(this, 'ChatUserPool', {
      userPoolName: `${appName}-users`,
      selfSignUpEnabled: true,
      signInAliases: {
        email: true,
        username: false,
      },
      autoVerify: {
        email: true,
      },
      standardAttributes: {
        email: {
          required: true,
          mutable: true,
        },
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development/testing
    });

    // Create User Pool Client for application authentication
    const userPoolClient = new cognito.UserPoolClient(this, 'ChatUserPoolClient', {
      userPool,
      userPoolClientName: `${appName}-client`,
      authFlows: {
        userPassword: true,
        userSrp: true,
        custom: true,
        adminUserPassword: true,
      },
      generateSecret: false, // Set to false for web/mobile apps
      preventUserExistenceErrors: true,
    });

    // ====================================
    // DynamoDB Tables
    // ====================================

    // Messages table with GSI for chronological queries
    const messagesTable = new dynamodb.Table(this, 'MessagesTable', {
      tableName: `${appName}-messages`,
      partitionKey: {
        name: 'conversationId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'messageId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development/testing
      pointInTimeRecovery: true,
    });

    // Add GSI for time-based message queries
    messagesTable.addGlobalSecondaryIndex({
      indexName: 'MessagesByTime',
      partitionKey: {
        name: 'conversationId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
    });

    // Conversations table with GSI for user-conversation mapping
    const conversationsTable = new dynamodb.Table(this, 'ConversationsTable', {
      tableName: `${appName}-conversations`,
      partitionKey: {
        name: 'conversationId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development/testing
      pointInTimeRecovery: true,
    });

    // Add GSI for user conversations lookup
    conversationsTable.addGlobalSecondaryIndex({
      indexName: 'UserConversations',
      partitionKey: {
        name: 'userId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'conversationId',
        type: dynamodb.AttributeType.STRING,
      },
    });

    // Users table for user profile and presence data
    const usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: `${appName}-users`,
      partitionKey: {
        name: 'userId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development/testing
      pointInTimeRecovery: true,
    });

    // ====================================
    // GraphQL Schema Definition
    // ====================================

    const schema = `
      type Message {
          messageId: ID!
          conversationId: ID!
          userId: ID!
          content: String!
          messageType: MessageType!
          createdAt: AWSDateTime!
          updatedAt: AWSDateTime
          author: User
      }
      
      type Conversation {
          conversationId: ID!
          name: String
          participants: [ID!]!
          lastMessageAt: AWSDateTime
          lastMessage: String
          createdAt: AWSDateTime!
          updatedAt: AWSDateTime
          createdBy: ID!
          messageCount: Int
      }
      
      type User {
          userId: ID!
          username: String!
          email: AWSEmail!
          displayName: String
          avatarUrl: String
          lastSeen: AWSDateTime
          isOnline: Boolean
          createdAt: AWSDateTime!
          updatedAt: AWSDateTime
      }
      
      enum MessageType {
          TEXT
          IMAGE
          FILE
          SYSTEM
      }
      
      type Query {
          getMessage(conversationId: ID!, messageId: ID!): Message
          getConversation(conversationId: ID!): Conversation
          getUser(userId: ID!): User
          listMessages(conversationId: ID!, limit: Int, nextToken: String): MessageConnection
          listConversations(userId: ID!, limit: Int, nextToken: String): ConversationConnection
          searchMessages(conversationId: ID!, searchTerm: String!, limit: Int): [Message]
      }
      
      type Mutation {
          sendMessage(input: SendMessageInput!): Message
          createConversation(input: CreateConversationInput!): Conversation
          updateConversation(input: UpdateConversationInput!): Conversation
          deleteMessage(conversationId: ID!, messageId: ID!): Message
          updateUserPresence(userId: ID!, isOnline: Boolean!): User
          updateUserProfile(input: UpdateUserProfileInput!): User
      }
      
      type Subscription {
          onMessageSent(conversationId: ID!): Message
              @aws_subscribe(mutations: ["sendMessage"])
          onConversationUpdated(userId: ID!): Conversation
              @aws_subscribe(mutations: ["createConversation", "updateConversation"])
          onUserPresenceUpdated(conversationId: ID!): User
              @aws_subscribe(mutations: ["updateUserPresence"])
      }
      
      input SendMessageInput {
          conversationId: ID!
          content: String!
          messageType: MessageType = TEXT
      }
      
      input CreateConversationInput {
          name: String
          participants: [ID!]!
      }
      
      input UpdateConversationInput {
          conversationId: ID!
          name: String
      }
      
      input UpdateUserProfileInput {
          userId: ID!
          displayName: String
          avatarUrl: String
      }
      
      type MessageConnection {
          items: [Message]
          nextToken: String
      }
      
      type ConversationConnection {
          items: [Conversation]
          nextToken: String
      }
      
      schema {
          query: Query
          mutation: Mutation
          subscription: Subscription
      }
    `;

    // ====================================
    // AWS AppSync GraphQL API
    // ====================================

    // Create AppSync GraphQL API
    const api = new appsync.GraphqlApi(this, 'ChatApi', {
      name: `${appName}-api`,
      definition: appsync.Definition.fromString(schema),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.USER_POOL,
          userPoolConfig: {
            userPool,
            defaultAction: appsync.UserPoolDefaultAction.ALLOW,
          },
        },
      },
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        retainLogOnDelete: false,
      },
    });

    // ====================================
    // DynamoDB Data Sources
    // ====================================

    // Create data sources for each DynamoDB table
    const messagesDataSource = api.addDynamoDbDataSource('MessagesDataSource', messagesTable);
    const conversationsDataSource = api.addDynamoDbDataSource('ConversationsDataSource', conversationsTable);
    const usersDataSource = api.addDynamoDbDataSource('UsersDataSource', usersTable);

    // ====================================
    // VTL Resolvers
    // ====================================

    // SendMessage Mutation Resolver
    messagesDataSource.createResolver('SendMessageResolver', {
      typeName: 'Mutation',
      fieldName: 'sendMessage',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "PutItem",
            "key": {
                "conversationId": $util.dynamodb.toDynamoDBJson($ctx.args.input.conversationId),
                "messageId": $util.dynamodb.toDynamoDBJson($util.autoId())
            },
            "attributeValues": {
                "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
                "content": $util.dynamodb.toDynamoDBJson($ctx.args.input.content),
                "messageType": $util.dynamodb.toDynamoDBJson($ctx.args.input.messageType),
                "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // ListMessages Query Resolver
    messagesDataSource.createResolver('ListMessagesResolver', {
      typeName: 'Query',
      fieldName: 'listMessages',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "Query",
            "index": "MessagesByTime",
            "query": {
                "expression": "conversationId = :conversationId",
                "expressionValues": {
                    ":conversationId": $util.dynamodb.toDynamoDBJson($ctx.args.conversationId)
                }
            },
            "scanIndexForward": false,
            "limit": #if($ctx.args.limit) $ctx.args.limit #else 50 #end
            #if($ctx.args.nextToken)
            ,"nextToken": "$ctx.args.nextToken"
            #end
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "items": $util.toJson($ctx.result.items),
            "nextToken": #if($ctx.result.nextToken) "$ctx.result.nextToken" #else null #end
        }
      `),
    });

    // GetMessage Query Resolver
    messagesDataSource.createResolver('GetMessageResolver', {
      typeName: 'Query',
      fieldName: 'getMessage',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "GetItem",
            "key": {
                "conversationId": $util.dynamodb.toDynamoDBJson($ctx.args.conversationId),
                "messageId": $util.dynamodb.toDynamoDBJson($ctx.args.messageId)
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // CreateConversation Mutation Resolver
    conversationsDataSource.createResolver('CreateConversationResolver', {
      typeName: 'Mutation',
      fieldName: 'createConversation',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "PutItem",
            "key": {
                "conversationId": $util.dynamodb.toDynamoDBJson($util.autoId())
            },
            "attributeValues": {
                "name": $util.dynamodb.toDynamoDBJson($ctx.args.input.name),
                "participants": $util.dynamodb.toDynamoDBJson($ctx.args.input.participants),
                "createdBy": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
                "createdAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                "updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                "messageCount": $util.dynamodb.toDynamoDBJson(0)
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // GetConversation Query Resolver
    conversationsDataSource.createResolver('GetConversationResolver', {
      typeName: 'Query',
      fieldName: 'getConversation',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "GetItem",
            "key": {
                "conversationId": $util.dynamodb.toDynamoDBJson($ctx.args.conversationId)
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // UpdateUserPresence Mutation Resolver
    usersDataSource.createResolver('UpdateUserPresenceResolver', {
      typeName: 'Mutation',
      fieldName: 'updateUserPresence',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "UpdateItem",
            "key": {
                "userId": $util.dynamodb.toDynamoDBJson($ctx.args.userId)
            },
            "update": {
                "expression": "SET isOnline = :isOnline, lastSeen = :lastSeen, updatedAt = :updatedAt",
                "expressionValues": {
                    ":isOnline": $util.dynamodb.toDynamoDBJson($ctx.args.isOnline),
                    ":lastSeen": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601()),
                    ":updatedAt": $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())
                }
            },
            "condition": {
                "expression": "attribute_exists(userId) OR attribute_not_exists(userId)"
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // GetUser Query Resolver
    usersDataSource.createResolver('GetUserResolver', {
      typeName: 'Query',
      fieldName: 'getUser',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "version": "2017-02-28",
            "operation": "GetItem",
            "key": {
                "userId": $util.dynamodb.toDynamoDBJson($ctx.args.userId)
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // UpdateUserProfile Mutation Resolver
    usersDataSource.createResolver('UpdateUserProfileResolver', {
      typeName: 'Mutation',
      fieldName: 'updateUserProfile',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($expNames = {})
        #set($expValues = {})
        #set($expSet = [])
        
        #if($ctx.args.input.displayName)
          #set($void = $expNames.put("#displayName", "displayName"))
          #set($void = $expValues.put(":displayName", $util.dynamodb.toDynamoDBJson($ctx.args.input.displayName)))
          #set($void = $expSet.add("#displayName = :displayName"))
        #end
        
        #if($ctx.args.input.avatarUrl)
          #set($void = $expNames.put("#avatarUrl", "avatarUrl"))
          #set($void = $expValues.put(":avatarUrl", $util.dynamodb.toDynamoDBJson($ctx.args.input.avatarUrl)))
          #set($void = $expSet.add("#avatarUrl = :avatarUrl"))
        #end
        
        #set($void = $expNames.put("#updatedAt", "updatedAt"))
        #set($void = $expValues.put(":updatedAt", $util.dynamodb.toDynamoDBJson($util.time.nowISO8601())))
        #set($void = $expSet.add("#updatedAt = :updatedAt"))
        
        {
            "version": "2017-02-28",
            "operation": "UpdateItem",
            "key": {
                "userId": $util.dynamodb.toDynamoDBJson($ctx.args.input.userId)
            },
            "update": {
                "expression": "SET $util.toJson($expSet.toString().replace('[','').replace(']',''))",
                "expressionNames": $util.toJson($expNames),
                "expressionValues": $util.toJson($expValues)
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($ctx.result)'),
    });

    // ====================================
    // Stack Outputs
    // ====================================

    // Output important resource identifiers and endpoints
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: userPool.userPoolId,
      description: 'Cognito User Pool ID for authentication',
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID for authentication',
    });

    new cdk.CfnOutput(this, 'GraphQLApiUrl', {
      value: api.graphqlUrl,
      description: 'GraphQL API endpoint URL',
    });

    new cdk.CfnOutput(this, 'GraphQLApiId', {
      value: api.apiId,
      description: 'GraphQL API ID',
    });

    new cdk.CfnOutput(this, 'MessagesTableName', {
      value: messagesTable.tableName,
      description: 'DynamoDB Messages table name',
    });

    new cdk.CfnOutput(this, 'ConversationsTableName', {
      value: conversationsTable.tableName,
      description: 'DynamoDB Conversations table name',
    });

    new cdk.CfnOutput(this, 'UsersTableName', {
      value: usersTable.tableName,
      description: 'DynamoDB Users table name',
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
    });

    // Output for client application configuration
    new cdk.CfnOutput(this, 'ClientConfig', {
      value: JSON.stringify({
        region: this.region,
        userPoolId: userPool.userPoolId,
        userPoolClientId: userPoolClient.userPoolClientId,
        graphqlEndpoint: api.graphqlUrl,
        apiId: api.apiId,
      }),
      description: 'Client configuration for connecting to the chat application',
    });
  }
}

// ====================================
// CDK App and Stack Instantiation
// ====================================

const app = new cdk.App();

// Create the stack with environment configuration
new RealTimeChatStack(app, 'RealTimeChatStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Real-time chat application using AWS AppSync, DynamoDB, and Cognito',
  tags: {
    Project: 'RealTimeChat',
    Environment: 'Development',
    Owner: 'CDK',
  },
});