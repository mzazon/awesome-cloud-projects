#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as appsync from '@aws-cdk/aws-appsync-alpha';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3Deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';

/**
 * Stack for deploying a full-stack real-time chat application using AWS Amplify and AppSync
 * This stack includes:
 * - Cognito User Pool for authentication
 * - AppSync GraphQL API with real-time subscriptions
 * - DynamoDB tables for data storage
 * - Lambda functions for custom business logic
 * - S3 and CloudFront for static web hosting
 * - Comprehensive monitoring and logging
 */
export class RealtimeChatAppStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly graphqlApi: appsync.GraphqlApi;
  public readonly webDistribution: cloudfront.Distribution;
  public readonly websiteBucket: s3.Bucket;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create Cognito User Pool for authentication
    this.userPool = this.createUserPool();
    this.userPoolClient = this.createUserPoolClient();

    // Create DynamoDB tables for data storage
    const chatRoomTable = this.createChatRoomTable();
    const messageTable = this.createMessageTable();
    const reactionTable = this.createReactionTable();
    const userPresenceTable = this.createUserPresenceTable();
    const notificationTable = this.createNotificationTable();

    // Create Lambda functions for custom business logic
    const realtimeHandlerFunction = this.createRealtimeHandlerFunction({
      chatRoomTable,
      messageTable,
      reactionTable,
      userPresenceTable,
      notificationTable,
    });

    // Create AppSync GraphQL API with real-time subscriptions
    this.graphqlApi = this.createGraphQLApi(realtimeHandlerFunction);

    // Create data sources and resolvers
    this.createDataSources({
      chatRoomTable,
      messageTable,
      reactionTable,
      userPresenceTable,
      notificationTable,
      realtimeHandlerFunction,
    });

    // Create S3 bucket and CloudFront distribution for web hosting
    this.websiteBucket = this.createWebsiteBucket();
    this.webDistribution = this.createCloudFrontDistribution();

    // Create monitoring and alarms
    this.createMonitoring();

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates a Cognito User Pool with advanced security features
   */
  private createUserPool(): cognito.UserPool {
    const userPool = new cognito.UserPool(this, 'RealtimeChatUserPool', {
      userPoolName: 'realtime-chat-users',
      selfSignUpEnabled: true,
      userVerification: {
        emailSubject: 'Verify your email for Real-time Chat',
        emailBody: 'Hello {username}, Thanks for signing up! Your verification code is {####}',
        emailStyle: cognito.VerificationEmailStyle.CODE,
      },
      signInAliases: {
        email: true,
        username: true,
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
          required: false,
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
      advancedSecurityMode: cognito.AdvancedSecurityMode.ENFORCED,
      deviceTracking: {
        challengeRequiredOnNewDevice: true,
        deviceOnlyRememberedOnUserPrompt: true,
      },
      mfa: cognito.Mfa.OPTIONAL,
      mfaSecondFactor: {
        sms: true,
        otp: true,
      },
    });

    // Create user groups for role-based access control
    new cognito.CfnUserPoolGroup(this, 'AdminGroup', {
      userPoolId: userPool.userPoolId,
      groupName: 'Admins',
      description: 'Administrator users with full access',
      precedence: 1,
    });

    new cognito.CfnUserPoolGroup(this, 'ModeratorGroup', {
      userPoolId: userPool.userPoolId,
      groupName: 'Moderators',
      description: 'Moderator users with room management access',
      precedence: 2,
    });

    new cognito.CfnUserPoolGroup(this, 'UserGroup', {
      userPoolId: userPool.userPoolId,
      groupName: 'Users',
      description: 'Regular users with standard access',
      precedence: 3,
    });

    return userPool;
  }

  /**
   * Creates a Cognito User Pool Client with proper security settings
   */
  private createUserPoolClient(): cognito.UserPoolClient {
    return new cognito.UserPoolClient(this, 'RealtimeChatUserPoolClient', {
      userPool: this.userPool,
      userPoolClientName: 'realtime-chat-client',
      generateSecret: false,
      authFlows: {
        adminUserPassword: true,
        custom: true,
        userSrp: true,
      },
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
      ],
      readAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          givenName: true,
          familyName: true,
        }),
      writeAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          givenName: true,
          familyName: true,
        }),
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
          implicitCodeGrant: true,
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
      },
      preventUserExistenceErrors: true,
      enableTokenRevocation: true,
      accessTokenValidity: cdk.Duration.minutes(60),
      idTokenValidity: cdk.Duration.minutes(60),
      refreshTokenValidity: cdk.Duration.days(30),
    });
  }

  /**
   * Creates DynamoDB table for chat rooms
   */
  private createChatRoomTable(): dynamodb.Table {
    return new dynamodb.Table(this, 'ChatRoomTable', {
      tableName: 'realtime-chat-rooms',
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'ttl',
      globalSecondaryIndexes: [
        {
          indexName: 'byCreatedBy',
          partitionKey: {
            name: 'createdBy',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
        {
          indexName: 'byLastActivity',
          partitionKey: {
            name: 'isPrivate',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'lastActivity',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
    });
  }

  /**
   * Creates DynamoDB table for messages
   */
  private createMessageTable(): dynamodb.Table {
    return new dynamodb.Table(this, 'MessageTable', {
      tableName: 'realtime-chat-messages',
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'ttl',
      globalSecondaryIndexes: [
        {
          indexName: 'byRoom',
          partitionKey: {
            name: 'chatRoomId',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
        {
          indexName: 'byAuthor',
          partitionKey: {
            name: 'author',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
        {
          indexName: 'byReply',
          partitionKey: {
            name: 'replyToId',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
    });
  }

  /**
   * Creates DynamoDB table for message reactions
   */
  private createReactionTable(): dynamodb.Table {
    return new dynamodb.Table(this, 'ReactionTable', {
      tableName: 'realtime-chat-reactions',
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'ttl',
      globalSecondaryIndexes: [
        {
          indexName: 'byMessage',
          partitionKey: {
            name: 'messageId',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
        {
          indexName: 'byAuthor',
          partitionKey: {
            name: 'author',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
    });
  }

  /**
   * Creates DynamoDB table for user presence tracking
   */
  private createUserPresenceTable(): dynamodb.Table {
    return new dynamodb.Table(this, 'UserPresenceTable', {
      tableName: 'realtime-user-presence',
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'ttl',
      globalSecondaryIndexes: [
        {
          indexName: 'byStatus',
          partitionKey: {
            name: 'status',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'lastSeen',
            type: dynamodb.AttributeType.STRING,
          },
        },
        {
          indexName: 'byRoom',
          partitionKey: {
            name: 'currentRoom',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'lastSeen',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
    });
  }

  /**
   * Creates DynamoDB table for notifications
   */
  private createNotificationTable(): dynamodb.Table {
    return new dynamodb.Table(this, 'NotificationTable', {
      tableName: 'realtime-notifications',
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      timeToLiveAttribute: 'ttl',
      globalSecondaryIndexes: [
        {
          indexName: 'byUser',
          partitionKey: {
            name: 'userId',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
        {
          indexName: 'byType',
          partitionKey: {
            name: 'type',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
    });
  }

  /**
   * Creates Lambda function for real-time operations
   */
  private createRealtimeHandlerFunction(tables: {
    chatRoomTable: dynamodb.Table;
    messageTable: dynamodb.Table;
    reactionTable: dynamodb.Table;
    userPresenceTable: dynamodb.Table;
    notificationTable: dynamodb.Table;
  }): NodejsFunction {
    const realtimeHandlerFunction = new NodejsFunction(this, 'RealtimeHandlerFunction', {
      functionName: 'realtime-chat-handler',
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const { v4: uuidv4 } = require('uuid');
        
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        const appsync = new AWS.AppSync();
        
        exports.handler = async (event) => {
          console.log('Real-time event received:', JSON.stringify(event, null, 2));
          
          const { field, source, arguments: args, identity } = event;
          const userId = identity.claims.sub;
          const userName = identity.claims['cognito:username'];
          
          try {
            switch (field) {
              case 'startTyping':
                return await handleTypingStart(args.chatRoomId, userId, userName);
              
              case 'stopTyping':
                return await handleTypingStop(args.chatRoomId, userId, userName);
              
              case 'updatePresence':
                return await updateUserPresence(userId, userName, args.status, args.currentRoom);
              
              case 'joinRoom':
                return await joinChatRoom(args.roomId, userId, userName);
              
              case 'leaveRoom':
                return await leaveChatRoom(args.roomId, userId, userName);
              
              default:
                throw new Error(\`Unknown field: \${field}\`);
            }
          } catch (error) {
            console.error('Error processing real-time operation:', error);
            throw new Error(\`Failed to process \${field}: \${error.message}\`);
          }
        };
        
        async function handleTypingStart(chatRoomId, userId, userName) {
          const typingIndicator = {
            userId,
            userName,
            chatRoomId,
            timestamp: new Date().toISOString()
          };
          
          console.log('Publishing typing start event:', typingIndicator);
          return typingIndicator;
        }
        
        async function handleTypingStop(chatRoomId, userId, userName) {
          const typingIndicator = {
            userId,
            userName,
            chatRoomId,
            timestamp: new Date().toISOString()
          };
          
          console.log('Publishing typing stop event:', typingIndicator);
          return typingIndicator;
        }
        
        async function updateUserPresence(userId, userName, status, currentRoom) {
          const presence = {
            id: userId,
            userId,
            userName,
            status,
            lastSeen: new Date().toISOString(),
            currentRoom: currentRoom || null,
            deviceInfo: 'Web',
            updatedAt: new Date().toISOString(),
            ttl: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours
          };
          
          await dynamodb.put({
            TableName: process.env.PRESENCE_TABLE,
            Item: presence
          }).promise();
          
          console.log('Updated user presence:', presence);
          return presence;
        }
        
        async function joinChatRoom(roomId, userId, userName) {
          try {
            // Add user to room members list
            await dynamodb.update({
              TableName: process.env.CHATROOM_TABLE,
              Key: { id: roomId },
              UpdateExpression: 'ADD members :userId SET lastActivity = :timestamp',
              ExpressionAttributeValues: {
                ':userId': dynamodb.createSet([userId]),
                ':timestamp': new Date().toISOString()
              }
            }).promise();
            
            // Update user presence to show current room
            await updateUserPresence(userId, userName, 'ONLINE', roomId);
            
            // Get updated room data
            const room = await dynamodb.get({
              TableName: process.env.CHATROOM_TABLE,
              Key: { id: roomId }
            }).promise();
            
            return room.Item;
          } catch (error) {
            console.error('Error joining room:', error);
            throw error;
          }
        }
        
        async function leaveChatRoom(roomId, userId, userName) {
          try {
            // Remove user from room members list
            await dynamodb.update({
              TableName: process.env.CHATROOM_TABLE,
              Key: { id: roomId },
              UpdateExpression: 'DELETE members :userId SET lastActivity = :timestamp',
              ExpressionAttributeValues: {
                ':userId': dynamodb.createSet([userId]),
                ':timestamp': new Date().toISOString()
              }
            }).promise();
            
            // Update user presence to clear current room
            await updateUserPresence(userId, userName, 'ONLINE', null);
            
            // Get updated room data
            const room = await dynamodb.get({
              TableName: process.env.CHATROOM_TABLE,
              Key: { id: roomId }
            }).promise();
            
            return room.Item;
          } catch (error) {
            console.error('Error leaving room:', error);
            throw error;
          }
        }
      `),
      environment: {
        CHATROOM_TABLE: tables.chatRoomTable.tableName,
        MESSAGE_TABLE: tables.messageTable.tableName,
        REACTION_TABLE: tables.reactionTable.tableName,
        PRESENCE_TABLE: tables.userPresenceTable.tableName,
        NOTIFICATION_TABLE: tables.notificationTable.tableName,
      },
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logRetention: logs.RetentionDays.ONE_WEEK,
      bundling: {
        externalModules: ['aws-sdk'],
        nodeModules: ['uuid'],
      },
    });

    // Grant DynamoDB permissions
    tables.chatRoomTable.grantReadWriteData(realtimeHandlerFunction);
    tables.messageTable.grantReadWriteData(realtimeHandlerFunction);
    tables.reactionTable.grantReadWriteData(realtimeHandlerFunction);
    tables.userPresenceTable.grantReadWriteData(realtimeHandlerFunction);
    tables.notificationTable.grantReadWriteData(realtimeHandlerFunction);

    return realtimeHandlerFunction;
  }

  /**
   * Creates AppSync GraphQL API with real-time subscriptions
   */
  private createGraphQLApi(realtimeHandlerFunction: NodejsFunction): appsync.GraphqlApi {
    const api = new appsync.GraphqlApi(this, 'RealtimeChatApi', {
      name: 'realtime-chat-api',
      schema: appsync.SchemaFile.fromAsset('schema.graphql'),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.USER_POOL,
          userPoolConfig: {
            userPool: this.userPool,
            appIdClientRegex: this.userPoolClient.userPoolClientId,
          },
        },
        additionalAuthorizationModes: [
          {
            authorizationType: appsync.AuthorizationType.API_KEY,
            apiKeyConfig: {
              expires: cdk.Expiration.after(cdk.Duration.days(365)),
              description: 'API Key for public read access',
            },
          },
        ],
      },
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        retentionTime: logs.RetentionDays.ONE_WEEK,
      },
      xrayEnabled: true,
    });

    // Create the schema file inline since we can't reference external files
    const schemaContent = `
      type ChatRoom @aws_api_key @aws_cognito_user_pools {
        id: ID!
        name: String!
        description: String
        isPrivate: Boolean!
        createdBy: String!
        members: [String]
        lastActivity: AWSDateTime
        messageCount: Int
        messages: [Message]
        createdAt: AWSDateTime!
        updatedAt: AWSDateTime!
      }
      
      type Message @aws_api_key @aws_cognito_user_pools {
        id: ID!
        content: String!
        messageType: MessageType!
        author: String!
        authorName: String!
        chatRoomId: ID!
        chatRoom: ChatRoom
        replyToId: ID
        replyTo: Message
        replies: [Message]
        reactions: [Reaction]
        attachments: [String]
        editedAt: AWSDateTime
        isEdited: Boolean
        createdAt: AWSDateTime!
        updatedAt: AWSDateTime!
      }
      
      type Reaction @aws_api_key @aws_cognito_user_pools {
        id: ID!
        emoji: String!
        author: String!
        authorName: String!
        messageId: ID!
        message: Message
        createdAt: AWSDateTime!
        updatedAt: AWSDateTime!
      }
      
      type UserPresence @aws_api_key @aws_cognito_user_pools {
        id: ID!
        userId: String!
        userName: String!
        status: PresenceStatus!
        lastSeen: AWSDateTime!
        currentRoom: String
        deviceInfo: String
        createdAt: AWSDateTime!
        updatedAt: AWSDateTime!
      }
      
      type Notification @aws_cognito_user_pools {
        id: ID!
        type: NotificationType!
        title: String!
        message: String!
        userId: String!
        isRead: Boolean
        relatedId: String
        actionUrl: String
        createdAt: AWSDateTime!
        updatedAt: AWSDateTime!
      }
      
      enum MessageType {
        TEXT
        IMAGE
        FILE
        SYSTEM
        TYPING
      }
      
      enum PresenceStatus {
        ONLINE
        AWAY
        BUSY
        OFFLINE
      }
      
      enum NotificationType {
        MESSAGE
        MENTION
        ROOM_INVITE
        SYSTEM
      }
      
      type TypingIndicator {
        userId: String!
        userName: String!
        chatRoomId: ID!
        timestamp: AWSDateTime!
      }
      
      input CreateChatRoomInput {
        name: String!
        description: String
        isPrivate: Boolean!
      }
      
      input CreateMessageInput {
        content: String!
        messageType: MessageType!
        chatRoomId: ID!
        replyToId: ID
      }
      
      input CreateReactionInput {
        emoji: String!
        messageId: ID!
      }
      
      input CreateNotificationInput {
        type: NotificationType!
        title: String!
        message: String!
        userId: String!
        relatedId: String
        actionUrl: String
      }
      
      type Query {
        listChatRooms(limit: Int, nextToken: String): [ChatRoom]
        getChatRoom(id: ID!): ChatRoom
        messagesByRoom(chatRoomId: ID!, limit: Int, nextToken: String): [Message]
        getMessage(id: ID!): Message
        reactionsByMessage(messageId: ID!, limit: Int, nextToken: String): [Reaction]
        listUserPresence(limit: Int, nextToken: String): [UserPresence]
        notificationsByUser(userId: String!, limit: Int, nextToken: String): [Notification]
      }
      
      type Mutation {
        createChatRoom(input: CreateChatRoomInput!): ChatRoom
        updateChatRoom(id: ID!, input: CreateChatRoomInput!): ChatRoom
        deleteChatRoom(id: ID!): ChatRoom
        
        createMessage(input: CreateMessageInput!): Message
        updateMessage(id: ID!, input: CreateMessageInput!): Message
        deleteMessage(id: ID!): Message
        
        createReaction(input: CreateReactionInput!): Reaction
        deleteReaction(id: ID!): Reaction
        
        createNotification(input: CreateNotificationInput!): Notification
        updateNotification(id: ID!, isRead: Boolean!): Notification
        deleteNotification(id: ID!): Notification
        
        startTyping(chatRoomId: ID!): TypingIndicator
        stopTyping(chatRoomId: ID!): TypingIndicator
        updatePresence(status: PresenceStatus!, currentRoom: String): UserPresence
        joinRoom(roomId: ID!): ChatRoom
        leaveRoom(roomId: ID!): ChatRoom
      }
      
      type Subscription {
        onMessageCreated(chatRoomId: ID!): Message
          @aws_subscribe(mutations: ["createMessage"])
        
        onMessageUpdated(chatRoomId: ID!): Message
          @aws_subscribe(mutations: ["updateMessage"])
        
        onMessageDeleted(chatRoomId: ID!): Message
          @aws_subscribe(mutations: ["deleteMessage"])
        
        onReactionAdded(messageId: ID!): Reaction
          @aws_subscribe(mutations: ["createReaction"])
        
        onReactionRemoved(messageId: ID!): Reaction
          @aws_subscribe(mutations: ["deleteReaction"])
        
        onUserPresenceChanged: UserPresence
          @aws_subscribe(mutations: ["updatePresence"])
        
        onNotificationReceived(userId: String!): Notification
          @aws_subscribe(mutations: ["createNotification"])
        
        onTypingStarted(chatRoomId: ID!): TypingIndicator
          @aws_subscribe(mutations: ["startTyping"])
        
        onTypingEnded(chatRoomId: ID!): TypingIndicator
          @aws_subscribe(mutations: ["stopTyping"])
        
        onRoomJoined(roomId: ID!): ChatRoom
          @aws_subscribe(mutations: ["joinRoom"])
        
        onRoomLeft(roomId: ID!): ChatRoom
          @aws_subscribe(mutations: ["leaveRoom"])
      }
    `;

    // Write the schema to a file that can be referenced
    new cdk.CfnOutput(this, 'SchemaContent', {
      value: schemaContent,
      description: 'GraphQL Schema for the real-time chat application',
    });

    return api;
  }

  /**
   * Creates data sources and resolvers for the GraphQL API
   */
  private createDataSources(resources: {
    chatRoomTable: dynamodb.Table;
    messageTable: dynamodb.Table;
    reactionTable: dynamodb.Table;
    userPresenceTable: dynamodb.Table;
    notificationTable: dynamodb.Table;
    realtimeHandlerFunction: NodejsFunction;
  }): void {
    // Create DynamoDB data sources
    const chatRoomDataSource = this.graphqlApi.addDynamoDbDataSource('ChatRoomDataSource', resources.chatRoomTable);
    const messageDataSource = this.graphqlApi.addDynamoDbDataSource('MessageDataSource', resources.messageTable);
    const reactionDataSource = this.graphqlApi.addDynamoDbDataSource('ReactionDataSource', resources.reactionTable);
    const userPresenceDataSource = this.graphqlApi.addDynamoDbDataSource('UserPresenceDataSource', resources.userPresenceTable);
    const notificationDataSource = this.graphqlApi.addDynamoDbDataSource('NotificationDataSource', resources.notificationTable);

    // Create Lambda data source
    const lambdaDataSource = this.graphqlApi.addLambdaDataSource('RealtimeHandlerDataSource', resources.realtimeHandlerFunction);

    // Create resolvers for ChatRoom operations
    chatRoomDataSource.createResolver('listChatRoomsResolver', {
      typeName: 'Query',
      fieldName: 'listChatRooms',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbScanTable(),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    chatRoomDataSource.createResolver('getChatRoomResolver', {
      typeName: 'Query',
      fieldName: 'getChatRoom',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    chatRoomDataSource.createResolver('createChatRoomResolver', {
      typeName: 'Mutation',
      fieldName: 'createChatRoom',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    // Create resolvers for Message operations
    messageDataSource.createResolver('messagesByRoomResolver', {
      typeName: 'Query',
      fieldName: 'messagesByRoom',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbQuery(
        appsync.KeyCondition.eq('chatRoomId', 'chatRoomId'),
        'byRoom'
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    messageDataSource.createResolver('createMessageResolver', {
      typeName: 'Mutation',
      fieldName: 'createMessage',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    // Create resolvers for Reaction operations
    reactionDataSource.createResolver('reactionsByMessageResolver', {
      typeName: 'Query',
      fieldName: 'reactionsByMessage',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbQuery(
        appsync.KeyCondition.eq('messageId', 'messageId'),
        'byMessage'
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    reactionDataSource.createResolver('createReactionResolver', {
      typeName: 'Mutation',
      fieldName: 'createReaction',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    // Create resolvers for UserPresence operations
    userPresenceDataSource.createResolver('listUserPresenceResolver', {
      typeName: 'Query',
      fieldName: 'listUserPresence',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbScanTable(),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    // Create resolvers for Notification operations
    notificationDataSource.createResolver('notificationsByUserResolver', {
      typeName: 'Query',
      fieldName: 'notificationsByUser',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbQuery(
        appsync.KeyCondition.eq('userId', 'userId'),
        'byUser'
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    notificationDataSource.createResolver('createNotificationResolver', {
      typeName: 'Mutation',
      fieldName: 'createNotification',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    // Create Lambda resolvers for real-time operations
    lambdaDataSource.createResolver('startTypingResolver', {
      typeName: 'Mutation',
      fieldName: 'startTyping',
    });

    lambdaDataSource.createResolver('stopTypingResolver', {
      typeName: 'Mutation',
      fieldName: 'stopTyping',
    });

    lambdaDataSource.createResolver('updatePresenceResolver', {
      typeName: 'Mutation',
      fieldName: 'updatePresence',
    });

    lambdaDataSource.createResolver('joinRoomResolver', {
      typeName: 'Mutation',
      fieldName: 'joinRoom',
    });

    lambdaDataSource.createResolver('leaveRoomResolver', {
      typeName: 'Mutation',
      fieldName: 'leaveRoom',
    });
  }

  /**
   * Creates S3 bucket for static website hosting
   */
  private createWebsiteBucket(): s3.Bucket {
    const websiteBucket = new s3.Bucket(this, 'WebsiteBucket', {
      bucketName: `realtime-chat-website-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      cors: [
        {
          allowedOrigins: ['*'],
          allowedMethods: [s3.HttpMethods.GET],
          allowedHeaders: ['*'],
        },
      ],
    });

    // Create Origin Access Control for CloudFront
    const originAccessControl = new cloudfront.S3OriginAccessControl(this, 'OriginAccessControl', {
      description: 'Origin Access Control for real-time chat website',
    });

    // Grant CloudFront access to the bucket
    websiteBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudfront.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [websiteBucket.arnForObjects('*')],
        conditions: {
          StringEquals: {
            'AWS:SourceArn': `arn:aws:cloudfront::${cdk.Aws.ACCOUNT_ID}:distribution/*`,
          },
        },
      })
    );

    return websiteBucket;
  }

  /**
   * Creates CloudFront distribution for global content delivery
   */
  private createCloudFrontDistribution(): cloudfront.Distribution {
    const distribution = new cloudfront.Distribution(this, 'WebsiteDistribution', {
      defaultRootObject: 'index.html',
      minimumProtocolVersion: cloudfront.SecurityPolicyProtocol.TLS_V1_2_2021,
      defaultBehavior: {
        origin: new origins.S3Origin(this.websiteBucket, {
          originAccessIdentity: undefined, // Use OAC instead
        }),
        allowedMethods: cloudfront.AllowedMethods.ALLOW_GET_HEAD_OPTIONS,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        compress: true,
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
      },
      additionalBehaviors: {
        '/api/*': {
          origin: new origins.HttpOrigin(`${this.graphqlApi.graphqlUrl.split('://')[1]}`),
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.HTTPS_ONLY,
        },
      },
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.minutes(30),
        },
        {
          httpStatus: 403,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
          ttl: cdk.Duration.minutes(30),
        },
      ],
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
      enabled: true,
      comment: 'Real-time chat application distribution',
    });

    return distribution;
  }

  /**
   * Creates monitoring and alerting for the application
   */
  private createMonitoring(): void {
    // Create CloudWatch dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'RealtimeChatDashboard', {
      dashboardName: 'realtime-chat-app-dashboard',
    });

    // Add AppSync metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'AppSync API Requests',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/AppSync',
            metricName: 'Requests',
            dimensionsMap: {
              GraphQLAPIId: this.graphqlApi.apiId,
            },
            statistic: 'Sum',
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/AppSync',
            metricName: 'Errors',
            dimensionsMap: {
              GraphQLAPIId: this.graphqlApi.apiId,
            },
            statistic: 'Sum',
          }),
        ],
      }),
      new cloudwatch.GraphWidget({
        title: 'AppSync Latency',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/AppSync',
            metricName: 'Latency',
            dimensionsMap: {
              GraphQLAPIId: this.graphqlApi.apiId,
            },
            statistic: 'Average',
          }),
        ],
      }),
      new cloudwatch.GraphWidget({
        title: 'Connected Clients',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/AppSync',
            metricName: 'ConnectedClients',
            dimensionsMap: {
              GraphQLAPIId: this.graphqlApi.apiId,
            },
            statistic: 'Maximum',
          }),
        ],
      }),
      new cloudwatch.GraphWidget({
        title: 'CloudFront Requests',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/CloudFront',
            metricName: 'Requests',
            dimensionsMap: {
              DistributionId: this.webDistribution.distributionId,
            },
            statistic: 'Sum',
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/CloudFront',
            metricName: 'BytesDownloaded',
            dimensionsMap: {
              DistributionId: this.webDistribution.distributionId,
            },
            statistic: 'Sum',
          }),
        ],
      }),
    );

    // Create alarms for high error rates
    new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: 'realtime-chat-high-error-rate',
      alarmDescription: 'High error rate in AppSync API',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/AppSync',
        metricName: 'Errors',
        dimensionsMap: {
          GraphQLAPIId: this.graphqlApi.apiId,
        },
        statistic: 'Sum',
      }),
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarm for high latency
    new cloudwatch.Alarm(this, 'HighLatencyAlarm', {
      alarmName: 'realtime-chat-high-latency',
      alarmDescription: 'High latency in AppSync API',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/AppSync',
        metricName: 'Latency',
        dimensionsMap: {
          GraphQLAPIId: this.graphqlApi.apiId,
        },
        statistic: 'Average',
      }),
      threshold: 5000, // 5 seconds
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
  }

  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: 'RealtimeChatUserPoolId',
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: 'RealtimeChatUserPoolClientId',
    });

    new cdk.CfnOutput(this, 'GraphQLApiId', {
      value: this.graphqlApi.apiId,
      description: 'AppSync GraphQL API ID',
      exportName: 'RealtimeChatGraphQLApiId',
    });

    new cdk.CfnOutput(this, 'GraphQLApiUrl', {
      value: this.graphqlApi.graphqlUrl,
      description: 'AppSync GraphQL API URL',
      exportName: 'RealtimeChatGraphQLApiUrl',
    });

    new cdk.CfnOutput(this, 'GraphQLApiKey', {
      value: this.graphqlApi.apiKey || 'Not available',
      description: 'AppSync GraphQL API Key',
      exportName: 'RealtimeChatGraphQLApiKey',
    });

    new cdk.CfnOutput(this, 'WebsiteBucketName', {
      value: this.websiteBucket.bucketName,
      description: 'S3 bucket name for website hosting',
      exportName: 'RealtimeChatWebsiteBucketName',
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionId', {
      value: this.webDistribution.distributionId,
      description: 'CloudFront distribution ID',
      exportName: 'RealtimeChatCloudFrontDistributionId',
    });

    new cdk.CfnOutput(this, 'CloudFrontDistributionDomainName', {
      value: this.webDistribution.distributionDomainName,
      description: 'CloudFront distribution domain name',
      exportName: 'RealtimeChatCloudFrontDistributionDomainName',
    });

    new cdk.CfnOutput(this, 'WebsiteUrl', {
      value: `https://${this.webDistribution.distributionDomainName}`,
      description: 'Website URL',
      exportName: 'RealtimeChatWebsiteUrl',
    });

    new cdk.CfnOutput(this, 'AWSRegion', {
      value: cdk.Aws.REGION,
      description: 'AWS Region',
      exportName: 'RealtimeChatAWSRegion',
    });
  }
}

/**
 * Main CDK application entry point
 */
const app = new cdk.App();

// Create the main stack
new RealtimeChatAppStack(app, 'RealtimeChatAppStack', {
  description: 'Full-stack real-time chat application with AWS Amplify and AppSync GraphQL subscriptions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'RealtimeChatApp',
    Environment: 'Development',
    Owner: 'CDK',
    CostCenter: 'Engineering',
  },
});

// Add stack-level tags
cdk.Tags.of(app).add('Application', 'RealtimeChatApp');
cdk.Tags.of(app).add('ManagedBy', 'CDK');