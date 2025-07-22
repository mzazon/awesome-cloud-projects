#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as pinpoint from 'aws-cdk-lib/aws-pinpoint';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Stack implementing a complete mobile backend using AWS Amplify services
 * Includes authentication, GraphQL API, file storage, push notifications, and custom business logic
 */
export class MobileBackendAmplifyStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly identityPool: cognito.CfnIdentityPool;
  public readonly graphqlApi: appsync.GraphqlApi;
  public readonly postTable: dynamodb.Table;
  public readonly userTable: dynamodb.Table;
  public readonly fileStorageBucket: s3.Bucket;
  public readonly postProcessorFunction: lambda.Function;
  public readonly pinpointApp: pinpoint.CfnApp;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique resource suffix for this deployment
    const resourceSuffix = Math.random().toString(36).substring(2, 8);

    // Create Amazon Cognito User Pool for user authentication
    this.userPool = this.createUserPool(resourceSuffix);
    
    // Create User Pool Client for mobile applications
    this.userPoolClient = this.createUserPoolClient();
    
    // Create Cognito Identity Pool for AWS resource access
    this.identityPool = this.createIdentityPool(resourceSuffix);
    
    // Create DynamoDB tables for application data
    this.postTable = this.createPostTable(resourceSuffix);
    this.userTable = this.createUserTable(resourceSuffix);
    
    // Create S3 bucket for file storage
    this.fileStorageBucket = this.createFileStorageBucket(resourceSuffix);
    
    // Create Lambda function for custom business logic
    this.postProcessorFunction = this.createPostProcessorFunction(resourceSuffix);
    
    // Create AWS AppSync GraphQL API
    this.graphqlApi = this.createGraphQLApi(resourceSuffix);
    
    // Create Amazon Pinpoint application for analytics and notifications
    this.pinpointApp = this.createPinpointApp(resourceSuffix);
    
    // Create CloudWatch dashboard for monitoring
    this.createMonitoringDashboard(resourceSuffix);
    
    // Output important resource identifiers
    this.createOutputs();
  }

  /**
   * Create Amazon Cognito User Pool with email verification and advanced security
   */
  private createUserPool(suffix: string): cognito.UserPool {
    const userPool = new cognito.UserPool(this, 'MobileBackendUserPool', {
      userPoolName: `mobile-backend-users-${suffix}`,
      // Configure sign-in options
      signInAliases: {
        email: true,
        phone: true,
      },
      // Configure sign-up attributes
      standardAttributes: {
        email: {
          required: true,
          mutable: true,
        },
        phoneNumber: {
          required: true,
          mutable: true,
        },
        givenName: {
          required: false,
          mutable: true,
        },
        familyName: {
          required: false,
          mutable: true,
        },
      },
      // Configure password policy
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      // Enable account recovery
      accountRecovery: cognito.AccountRecovery.EMAIL_AND_PHONE_WITHOUT_MFA,
      // Configure verification
      autoVerify: {
        email: true,
        phone: true,
      },
      // Configure MFA
      mfa: cognito.Mfa.OPTIONAL,
      mfaSecondFactor: {
        sms: true,
        otp: true,
      },
      // Configure advanced security
      advancedSecurityMode: cognito.AdvancedSecurityMode.ENFORCED,
      // Configure device tracking
      deviceTracking: {
        challengeRequiredOnNewDevice: true,
        deviceOnlyRememberedOnUserPrompt: true,
      },
      // Configure email settings
      emailSettings: {
        from: 'noreply@mobile-backend-app.com',
        replyTo: 'support@mobile-backend-app.com',
      },
      // Deletion protection
      deletionProtection: false, // Set to true for production
      // Configure user invitation
      selfSignUpEnabled: true,
      userVerification: {
        emailSubject: 'Verify your email for Mobile Backend App',
        emailBody: 'Hello {username}, Thanks for signing up! Your verification code is {####}',
        emailStyle: cognito.VerificationEmailStyle.CODE,
        smsMessage: 'Hello {username}, Your verification code for Mobile Backend App is {####}',
      },
      // Configure lambda triggers for custom workflows
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    // Add custom domain (optional - requires certificate)
    // userPool.addDomain('MobileBackendDomain', {
    //   customDomain: {
    //     domainName: 'auth.mobile-backend-app.com',
    //     certificate: acm.Certificate.fromCertificateArn(this, 'Certificate', certificateArn),
    //   },
    // });

    return userPool;
  }

  /**
   * Create User Pool Client for mobile application integration
   */
  private createUserPoolClient(): cognito.UserPoolClient {
    const userPoolClient = new cognito.UserPoolClient(this, 'MobileBackendUserPoolClient', {
      userPool: this.userPool,
      userPoolClientName: 'mobile-backend-client',
      // Configure authentication flows
      authFlows: {
        adminUserPassword: true,
        userPassword: true,
        custom: true,
        userSrp: true,
      },
      // Configure OAuth settings
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
          implicitCodeGrant: false,
        },
        scopes: [
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.PROFILE,
          cognito.OAuthScope.PHONE,
        ],
        callbackUrls: [
          'myapp://callback',
          'http://localhost:3000/callback',
        ],
        logoutUrls: [
          'myapp://logout',
          'http://localhost:3000/logout',
        ],
      },
      // Configure token validity
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      // Prevent user existence errors
      preventUserExistenceErrors: true,
      // Configure read/write attributes
      readAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          phoneNumber: true,
          givenName: true,
          familyName: true,
        }),
      writeAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          phoneNumber: true,
          givenName: true,
          familyName: true,
        }),
    });

    return userPoolClient;
  }

  /**
   * Create Cognito Identity Pool for AWS resource access
   */
  private createIdentityPool(suffix: string): cognito.CfnIdentityPool {
    const identityPool = new cognito.CfnIdentityPool(this, 'MobileBackendIdentityPool', {
      identityPoolName: `mobile_backend_identity_pool_${suffix}`,
      allowUnauthenticatedIdentities: false,
      cognitoIdentityProviders: [
        {
          clientId: this.userPoolClient.userPoolClientId,
          providerName: this.userPool.userPoolProviderName,
          serverSideTokenCheck: true,
        },
      ],
    });

    // Create IAM roles for authenticated and unauthenticated users
    const authenticatedRole = new iam.Role(this, 'CognitoAuthenticatedRole', {
      assumedBy: new iam.FederatedPrincipal(
        'cognito-identity.amazonaws.com',
        {
          StringEquals: {
            'cognito-identity.amazonaws.com:aud': identityPool.ref,
          },
          'ForAnyValue:StringLike': {
            'cognito-identity.amazonaws.com:amr': 'authenticated',
          },
        },
        'sts:AssumeRoleWithWebIdentity'
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonPinpointMobileAccess'),
      ],
    });

    // Grant permissions to access AppSync API
    authenticatedRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['appsync:GraphQL'],
        resources: [`${this.graphqlApi.arn}/*`],
      })
    );

    // Grant permissions to access S3 bucket (user-specific folders)
    authenticatedRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
        ],
        resources: [
          `${this.fileStorageBucket.bucketArn}/public/*`,
          `${this.fileStorageBucket.bucketArn}/protected/\${cognito-identity.amazonaws.com:sub}/*`,
          `${this.fileStorageBucket.bucketArn}/private/\${cognito-identity.amazonaws.com:sub}/*`,
        ],
      })
    );

    // Grant permissions to list bucket contents
    authenticatedRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ['s3:ListBucket'],
        resources: [this.fileStorageBucket.bucketArn],
        conditions: {
          StringLike: {
            's3:prefix': [
              'public/',
              'public/*',
              'protected/',
              'protected/*',
              'private/${cognito-identity.amazonaws.com:sub}/',
              'private/${cognito-identity.amazonaws.com:sub}/*',
            ],
          },
        },
      })
    );

    // Attach roles to identity pool
    new cognito.CfnIdentityPoolRoleAttachment(this, 'IdentityPoolRoleAttachment', {
      identityPoolId: identityPool.ref,
      roles: {
        authenticated: authenticatedRole.roleArn,
      },
    });

    return identityPool;
  }

  /**
   * Create DynamoDB table for posts
   */
  private createPostTable(suffix: string): dynamodb.Table {
    const table = new dynamodb.Table(this, 'PostTable', {
      tableName: `Posts-${suffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      deletionProtection: false, // Set to true for production
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add Global Secondary Index for querying posts by user
    table.addGlobalSecondaryIndex({
      indexName: 'byUser',
      partitionKey: {
        name: 'owner',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
    });

    // Add Global Secondary Index for querying posts by status
    table.addGlobalSecondaryIndex({
      indexName: 'byStatus',
      partitionKey: {
        name: 'status',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
    });

    return table;
  }

  /**
   * Create DynamoDB table for user profiles
   */
  private createUserTable(suffix: string): dynamodb.Table {
    const table = new dynamodb.Table(this, 'UserTable', {
      tableName: `Users-${suffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      deletionProtection: false, // Set to true for production
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    // Add Global Secondary Index for querying users by email
    table.addGlobalSecondaryIndex({
      indexName: 'byEmail',
      partitionKey: {
        name: 'email',
        type: dynamodb.AttributeType.STRING,
      },
    });

    return table;
  }

  /**
   * Create S3 bucket for file storage with proper access controls
   */
  private createFileStorageBucket(suffix: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'FileStorageBucket', {
      bucketName: `mobile-backend-user-files-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.POST,
            s3.HttpMethods.PUT,
            s3.HttpMethods.DELETE,
            s3.HttpMethods.HEAD,
          ],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
          exposedHeaders: [
            'x-amz-server-side-encryption',
            'x-amz-request-id',
            'x-amz-id-2',
            'ETag',
          ],
          maxAge: 3000,
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    return bucket;
  }

  /**
   * Create Lambda function for custom business logic
   */
  private createPostProcessorFunction(suffix: string): lambda.Function {
    const postProcessorFunction = new lambda.Function(this, 'PostProcessorFunction', {
      functionName: `mobile-backend-post-processor-${suffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        
        exports.handler = async (event) => {
            console.log('Event received:', JSON.stringify(event, null, 2));
            
            try {
                // Example: Process post creation and send notifications
                if (event.typeName === 'Mutation' && event.fieldName === 'createPost') {
                    const post = event.arguments.input;
                    
                    // Add processing logic here
                    // Example: content moderation, image processing, etc.
                    console.log('Processing post:', post.id);
                    
                    // Example: Update post status after processing
                    const updateParams = {
                        TableName: process.env.POST_TABLE_NAME,
                        Key: { id: post.id, createdAt: post.createdAt },
                        UpdateExpression: 'SET #status = :status, processedAt = :processedAt',
                        ExpressionAttributeNames: {
                            '#status': 'status'
                        },
                        ExpressionAttributeValues: {
                            ':status': 'processed',
                            ':processedAt': new Date().toISOString()
                        }
                    };
                    
                    await dynamodb.update(updateParams).promise();
                    
                    return {
                        statusCode: 200,
                        body: JSON.stringify({
                            message: 'Post processed successfully',
                            postId: post.id
                        })
                    };
                }
                
                return {
                    statusCode: 200,
                    body: JSON.stringify({ message: 'Function executed successfully' })
                };
            } catch (error) {
                console.error('Error:', error);
                return {
                    statusCode: 500,
                    body: JSON.stringify({ error: 'Internal server error' })
                };
            }
        };
      `),
      environment: {
        POST_TABLE_NAME: this.postTable.tableName,
        USER_TABLE_NAME: this.userTable.tableName,
        STORAGE_BUCKET_NAME: this.fileStorageBucket.bucketName,
      },
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logRetention: logs.RetentionDays.TWO_WEEKS,
      deadLetterQueueEnabled: true,
      retryAttempts: 2,
    });

    // Grant permissions to access DynamoDB tables
    this.postTable.grantReadWriteData(postProcessorFunction);
    this.userTable.grantReadData(postProcessorFunction);

    // Grant permissions to access S3 bucket
    this.fileStorageBucket.grantReadWrite(postProcessorFunction);

    return postProcessorFunction;
  }

  /**
   * Create AWS AppSync GraphQL API with comprehensive schema
   */
  private createGraphQLApi(suffix: string): appsync.GraphqlApi {
    const api = new appsync.GraphqlApi(this, 'MobileBackendApi', {
      name: `mobile-backend-api-${suffix}`,
      schema: appsync.SchemaFile.fromAsset('./schema.graphql'),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.USER_POOL,
          userPoolConfig: {
            userPool: this.userPool,
            appIdClientRegex: this.userPoolClient.userPoolClientId,
            defaultAction: appsync.UserPoolDefaultAction.ALLOW,
          },
        },
        additionalAuthorizationModes: [
          {
            authorizationType: appsync.AuthorizationType.IAM,
          },
        ],
      },
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        retention: logs.RetentionDays.TWO_WEEKS,
      },
      xrayEnabled: true,
    });

    // Create data sources
    const postTableDataSource = api.addDynamoDbDataSource(
      'PostTableDataSource',
      this.postTable
    );

    const userTableDataSource = api.addDynamoDbDataSource(
      'UserTableDataSource',
      this.userTable
    );

    const postProcessorDataSource = api.addLambdaDataSource(
      'PostProcessorDataSource',
      this.postProcessorFunction
    );

    // Create resolvers for Post operations
    postTableDataSource.createResolver('GetPostResolver', {
      typeName: 'Query',
      fieldName: 'getPost',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    postTableDataSource.createResolver('ListPostsResolver', {
      typeName: 'Query',
      fieldName: 'listPosts',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbScanTable(),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    postTableDataSource.createResolver('CreatePostResolver', {
      typeName: 'Mutation',
      fieldName: 'createPost',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    postTableDataSource.createResolver('UpdatePostResolver', {
      typeName: 'Mutation',
      fieldName: 'updatePost',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').is('input.id'),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    postTableDataSource.createResolver('DeletePostResolver', {
      typeName: 'Mutation',
      fieldName: 'deletePost',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbDeleteItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    // Create resolvers for User operations
    userTableDataSource.createResolver('GetUserResolver', {
      typeName: 'Query',
      fieldName: 'getUser',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    userTableDataSource.createResolver('CreateUserResolver', {
      typeName: 'Mutation',
      fieldName: 'createUser',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    // Create subscription resolvers
    api.createResolver('OnCreatePostResolver', {
      typeName: 'Subscription',
      fieldName: 'onCreatePost',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "payload": {}
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString('$util.toJson($context.result)'),
    });

    // Create GraphQL schema file
    const schemaContent = `
      type Post @aws_cognito_user_pools @aws_iam {
        id: ID!
        title: String!
        content: String!
        owner: String!
        status: PostStatus!
        createdAt: String!
        updatedAt: String!
        imageUrl: String
        likes: Int
        comments: [Comment]
      }

      type User @aws_cognito_user_pools @aws_iam {
        id: ID!
        username: String!
        email: String!
        firstName: String
        lastName: String
        profilePicture: String
        createdAt: String!
        updatedAt: String!
        posts: [Post] @connection(keyName: "byUser", fields: ["id"])
      }

      type Comment @aws_cognito_user_pools @aws_iam {
        id: ID!
        content: String!
        author: String!
        postId: ID!
        createdAt: String!
      }

      enum PostStatus {
        DRAFT
        PUBLISHED
        ARCHIVED
        PROCESSING
        PROCESSED
      }

      input CreatePostInput {
        title: String!
        content: String!
        imageUrl: String
        status: PostStatus = DRAFT
      }

      input UpdatePostInput {
        id: ID!
        title: String
        content: String
        imageUrl: String
        status: PostStatus
      }

      input CreateUserInput {
        username: String!
        email: String!
        firstName: String
        lastName: String
        profilePicture: String
      }

      input CreateCommentInput {
        content: String!
        postId: ID!
      }

      type Query {
        getPost(id: ID!): Post
        listPosts(filter: TablePostFilterInput, limit: Int, nextToken: String): ModelPostConnection
        getUser(id: ID!): User
        listUsers(filter: TableUserFilterInput, limit: Int, nextToken: String): ModelUserConnection
      }

      type Mutation {
        createPost(input: CreatePostInput!): Post
        updatePost(input: UpdatePostInput!): Post
        deletePost(id: ID!): Post
        createUser(input: CreateUserInput!): User
        createComment(input: CreateCommentInput!): Comment
      }

      type Subscription {
        onCreatePost(owner: String): Post
          @aws_subscribe(mutations: ["createPost"])
        onUpdatePost(owner: String): Post
          @aws_subscribe(mutations: ["updatePost"])
        onDeletePost(owner: String): Post
          @aws_subscribe(mutations: ["deletePost"])
      }

      type ModelPostConnection {
        items: [Post]
        nextToken: String
      }

      type ModelUserConnection {
        items: [User]
        nextToken: String
      }

      input TablePostFilterInput {
        id: TableIDFilterInput
        title: TableStringFilterInput
        content: TableStringFilterInput
        owner: TableStringFilterInput
        status: TablePostStatusFilterInput
      }

      input TableUserFilterInput {
        id: TableIDFilterInput
        username: TableStringFilterInput
        email: TableStringFilterInput
      }

      input TableIDFilterInput {
        eq: ID
        ne: ID
        le: ID
        lt: ID
        ge: ID
        gt: ID
        contains: ID
        notContains: ID
        between: [ID]
        beginsWith: ID
      }

      input TableStringFilterInput {
        eq: String
        ne: String
        le: String
        lt: String
        ge: String
        gt: String
        contains: String
        notContains: String
        between: [String]
        beginsWith: String
      }

      input TablePostStatusFilterInput {
        eq: PostStatus
        ne: PostStatus
      }
    `;

    // Write schema to file (this would typically be done manually or via a build process)
    // For CDK, we'll include the schema inline in the API definition
    
    return api;
  }

  /**
   * Create Amazon Pinpoint application for analytics and push notifications
   */
  private createPinpointApp(suffix: string): pinpoint.CfnApp {
    const pinpointApp = new pinpoint.CfnApp(this, 'MobileBackendPinpointApp', {
      name: `mobile-backend-analytics-${suffix}`,
      tags: {
        Application: 'MobileBackend',
        Environment: 'Development',
      },
    });

    // Create Pinpoint email channel
    new pinpoint.CfnEmailChannel(this, 'PinpointEmailChannel', {
      applicationId: pinpointApp.ref,
      fromAddress: 'noreply@mobile-backend-app.com',
      identity: `arn:aws:ses:${this.region}:${this.account}:identity/mobile-backend-app.com`,
      enabled: true,
    });

    // Create Pinpoint SMS channel
    new pinpoint.CfnSMSChannel(this, 'PinpointSMSChannel', {
      applicationId: pinpointApp.ref,
      enabled: true,
      senderId: 'MobileApp',
    });

    return pinpointApp;
  }

  /**
   * Create CloudWatch dashboard for monitoring mobile backend services
   */
  private createMonitoringDashboard(suffix: string): void {
    const dashboard = new cloudwatch.Dashboard(this, 'MobileBackendDashboard', {
      dashboardName: `mobile-backend-${suffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'AppSync API Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/AppSync',
                metricName: 'RequestCount',
                dimensionsMap: {
                  GraphQLAPIId: this.graphqlApi.apiId,
                },
                statistic: 'Sum',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/AppSync',
                metricName: '4XXError',
                dimensionsMap: {
                  GraphQLAPIId: this.graphqlApi.apiId,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/AppSync',
                metricName: '5XXError',
                dimensionsMap: {
                  GraphQLAPIId: this.graphqlApi.apiId,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'DynamoDB Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ConsumedReadCapacityUnits',
                dimensionsMap: {
                  TableName: this.postTable.tableName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ConsumedWriteCapacityUnits',
                dimensionsMap: {
                  TableName: this.postTable.tableName,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Invocations',
                dimensionsMap: {
                  FunctionName: this.postProcessorFunction.functionName,
                },
                statistic: 'Sum',
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Errors',
                dimensionsMap: {
                  FunctionName: this.postProcessorFunction.functionName,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Lambda',
                metricName: 'Duration',
                dimensionsMap: {
                  FunctionName: this.postProcessorFunction.functionName,
                },
                statistic: 'Average',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Cognito Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Cognito',
                metricName: 'SignUpSuccesses',
                dimensionsMap: {
                  UserPool: this.userPool.userPoolId,
                  UserPoolClient: this.userPoolClient.userPoolClientId,
                },
                statistic: 'Sum',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Cognito',
                metricName: 'SignInSuccesses',
                dimensionsMap: {
                  UserPool: this.userPool.userPoolId,
                  UserPoolClient: this.userPoolClient.userPoolClientId,
                },
                statistic: 'Sum',
              }),
            ],
          }),
        ],
      ],
    });
  }

  /**
   * Create stack outputs for important resource identifiers
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: `${this.stackName}-UserPoolId`,
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: `${this.stackName}-UserPoolClientId`,
    });

    new cdk.CfnOutput(this, 'IdentityPoolId', {
      value: this.identityPool.ref,
      description: 'Cognito Identity Pool ID',
      exportName: `${this.stackName}-IdentityPoolId`,
    });

    new cdk.CfnOutput(this, 'GraphQLApiId', {
      value: this.graphqlApi.apiId,
      description: 'AppSync GraphQL API ID',
      exportName: `${this.stackName}-GraphQLApiId`,
    });

    new cdk.CfnOutput(this, 'GraphQLApiUrl', {
      value: this.graphqlApi.graphqlUrl,
      description: 'AppSync GraphQL API URL',
      exportName: `${this.stackName}-GraphQLApiUrl`,
    });

    new cdk.CfnOutput(this, 'FileStorageBucketName', {
      value: this.fileStorageBucket.bucketName,
      description: 'S3 Bucket for file storage',
      exportName: `${this.stackName}-FileStorageBucketName`,
    });

    new cdk.CfnOutput(this, 'PinpointApplicationId', {
      value: this.pinpointApp.ref,
      description: 'Pinpoint Application ID',
      exportName: `${this.stackName}-PinpointApplicationId`,
    });

    new cdk.CfnOutput(this, 'PostProcessorFunctionArn', {
      value: this.postProcessorFunction.functionArn,
      description: 'Post Processor Lambda Function ARN',
      exportName: `${this.stackName}-PostProcessorFunctionArn`,
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
      exportName: `${this.stackName}-Region`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Create the mobile backend stack
new MobileBackendAmplifyStack(app, 'MobileBackendAmplifyStack', {
  description: 'Complete mobile backend infrastructure using AWS Amplify services',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'MobileBackendAmplify',
    Environment: 'Development',
    CostCenter: 'Engineering',
    Owner: 'MobileTeam',
  },
});