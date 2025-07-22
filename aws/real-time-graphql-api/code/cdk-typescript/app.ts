#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as iam from 'aws-cdk-lib/aws-iam';

/**
 * CDK Stack for Real-Time GraphQL API with AppSync Recipe
 * 
 * This stack creates:
 * - AWS AppSync GraphQL API with Cognito User Pool authentication
 * - DynamoDB table for blog posts with Global Secondary Index
 * - Cognito User Pool for authentication
 * - GraphQL resolvers for CRUD operations
 * - Real-time subscriptions for live updates
 */
export class GraphQLAppSyncStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // =================
    // DynamoDB Table
    // =================
    
    // Create DynamoDB table for blog posts with GSI for author queries
    const blogPostsTable = new dynamodb.Table(this, 'BlogPostsTable', {
      tableName: `BlogPosts-${uniqueSuffix}`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      pointInTimeRecovery: true, // Enable backup for production use
    });

    // Add Global Secondary Index for querying posts by author
    blogPostsTable.addGlobalSecondaryIndex({
      indexName: 'AuthorIndex',
      partitionKey: {
        name: 'author',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING
      },
      readCapacity: 5,
      writeCapacity: 5,
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // =================
    // Cognito User Pool
    // =================
    
    // Create Cognito User Pool for authentication
    const userPool = new cognito.UserPool(this, 'BlogUserPool', {
      userPoolName: `BlogUserPool-${uniqueSuffix}`,
      selfSignUpEnabled: true,
      autoVerify: {
        email: true,
      },
      signInAliases: {
        email: true,
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });

    // Create User Pool Client for API access
    const userPoolClient = userPool.addClient('BlogUserPoolClient', {
      userPoolClientName: `BlogUserPoolClient-${uniqueSuffix}`,
      generateSecret: true,
      authFlows: {
        adminUserPassword: true,
        userPassword: true,
        custom: true,
        userSrp: true,
      },
    });

    // =================
    // AppSync GraphQL API
    // =================
    
    // Create AppSync GraphQL API with Cognito User Pool authentication
    const api = new appsync.GraphqlApi(this, 'BlogGraphQLApi', {
      name: `blog-api-${uniqueSuffix}`,
      definition: appsync.Definition.fromString(`
        type BlogPost {
          id: ID!
          title: String!
          content: String!
          author: String!
          createdAt: AWSDateTime!
          updatedAt: AWSDateTime!
          tags: [String]
          published: Boolean!
        }

        input CreateBlogPostInput {
          title: String!
          content: String!
          tags: [String]
          published: Boolean = false
        }

        input UpdateBlogPostInput {
          id: ID!
          title: String
          content: String
          tags: [String]
          published: Boolean
        }

        type Query {
          getBlogPost(id: ID!): BlogPost
          listBlogPosts(limit: Int, nextToken: String): BlogPostConnection
          listBlogPostsByAuthor(author: String!, limit: Int, nextToken: String): BlogPostConnection
        }

        type Mutation {
          createBlogPost(input: CreateBlogPostInput!): BlogPost
          updateBlogPost(input: UpdateBlogPostInput!): BlogPost
          deleteBlogPost(id: ID!): BlogPost
        }

        type Subscription {
          onCreateBlogPost: BlogPost
            @aws_subscribe(mutations: ["createBlogPost"])
          onUpdateBlogPost: BlogPost
            @aws_subscribe(mutations: ["updateBlogPost"])
          onDeleteBlogPost: BlogPost
            @aws_subscribe(mutations: ["deleteBlogPost"])
        }

        type BlogPostConnection {
          items: [BlogPost]
          nextToken: String
        }

        schema {
          query: Query
          mutation: Mutation
          subscription: Subscription
        }
      `),
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.USER_POOL,
          userPoolConfig: {
            userPool: userPool,
            defaultAction: appsync.UserPoolDefaultAction.ALLOW,
          },
        },
        additionalAuthorizationModes: [
          {
            authorizationType: appsync.AuthorizationType.API_KEY,
            apiKeyConfig: {
              name: 'TestApiKey',
              description: 'API Key for testing GraphQL operations',
              expires: cdk.Expiration.after(cdk.Duration.days(30)),
            },
          },
        ],
      },
      xrayEnabled: true, // Enable X-Ray tracing for monitoring
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        excludeVerboseContent: false,
      },
    });

    // =================
    // Data Source & Resolvers
    // =================
    
    // Create DynamoDB data source for the API
    const blogPostsDataSource = api.addDynamoDbDataSource('BlogPostsDataSource', blogPostsTable);

    // Create resolver for getBlogPost query
    blogPostsDataSource.createResolver('GetBlogPostResolver', {
      typeName: 'Query',
      fieldName: 'getBlogPost',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
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

    // Create resolver for createBlogPost mutation
    blogPostsDataSource.createResolver('CreateBlogPostResolver', {
      typeName: 'Mutation',
      fieldName: 'createBlogPost',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    // Create resolver for updateBlogPost mutation
    blogPostsDataSource.createResolver('UpdateBlogPostResolver', {
      typeName: 'Mutation',
      fieldName: 'updateBlogPost',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
          }
        }
        #if($ctx.args.input.title)
          #set($update.expression = "$update.expression, title = :title")
          $util.qr($update.expressionValues.put(":title", $util.dynamodb.toDynamoDBJson($ctx.args.input.title)))
        #end
        #if($ctx.args.input.content)
          #set($update.expression = "$update.expression, content = :content")
          $util.qr($update.expressionValues.put(":content", $util.dynamodb.toDynamoDBJson($ctx.args.input.content)))
        #end
        #if($ctx.args.input.tags)
          #set($update.expression = "$update.expression, tags = :tags")
          $util.qr($update.expressionValues.put(":tags", $util.dynamodb.toDynamoDBJson($ctx.args.input.tags)))
        #end
        #if($ctx.args.input.published != null)
          #set($update.expression = "$update.expression, published = :published")
          $util.qr($update.expressionValues.put(":published", $util.dynamodb.toDynamoDBJson($ctx.args.input.published)))
        #end
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        $util.toJson($ctx.result)
      `),
    });

    // Create resolver for deleteBlogPost mutation
    blogPostsDataSource.createResolver('DeleteBlogPostResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteBlogPost',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "operation": "DeleteItem",
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

    // Create resolver for listBlogPosts query
    blogPostsDataSource.createResolver('ListBlogPostsResolver', {
      typeName: 'Query',
      fieldName: 'listBlogPosts',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        {
          "version": "2017-02-28",
          "operation": "Scan",
          #if($ctx.args.limit)
          "limit": $ctx.args.limit,
          #end
          #if($ctx.args.nextToken)
          "nextToken": "$ctx.args.nextToken"
          #end
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        {
          "items": $util.toJson($ctx.result.items),
          #if($ctx.result.nextToken)
          "nextToken": "$ctx.result.nextToken"
          #end
        }
      `),
    });

    // Create resolver for listBlogPostsByAuthor query
    blogPostsDataSource.createResolver('ListBlogPostsByAuthorResolver', {
      typeName: 'Query',
      fieldName: 'listBlogPostsByAuthor',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        #if($ctx.error)
          $util.error($ctx.error.message, $ctx.error.type)
        #end
        {
          "items": $util.toJson($ctx.result.items),
          #if($ctx.result.nextToken)
          "nextToken": "$ctx.result.nextToken"
          #end
        }
      `),
    });

    // =================
    // Outputs
    // =================
    
    // Output important values for testing and integration
    new cdk.CfnOutput(this, 'GraphQLApiId', {
      value: api.apiId,
      description: 'AppSync GraphQL API ID',
      exportName: `${this.stackName}-GraphQLApiId`,
    });

    new cdk.CfnOutput(this, 'GraphQLApiUrl', {
      value: api.graphqlUrl,
      description: 'AppSync GraphQL API URL',
      exportName: `${this.stackName}-GraphQLApiUrl`,
    });

    new cdk.CfnOutput(this, 'GraphQLApiKey', {
      value: api.apiKey || '',
      description: 'AppSync GraphQL API Key for testing',
      exportName: `${this.stackName}-GraphQLApiKey`,
    });

    new cdk.CfnOutput(this, 'UserPoolId', {
      value: userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: `${this.stackName}-UserPoolId`,
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: `${this.stackName}-UserPoolClientId`,
    });

    new cdk.CfnOutput(this, 'DynamoDBTableName', {
      value: blogPostsTable.tableName,
      description: 'DynamoDB Table Name',
      exportName: `${this.stackName}-DynamoDBTableName`,
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
      exportName: `${this.stackName}-Region`,
    });

    // =================
    // Tags
    // =================
    
    // Apply tags to all resources for better organization and cost tracking
    cdk.Tags.of(this).add('Project', 'GraphQL-AppSync-Recipe');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('Owner', 'CDK-Recipe');
    cdk.Tags.of(this).add('Purpose', 'Learning');
  }
}

// =================
// CDK App
// =================

const app = new cdk.App();

// Create the stack with default configuration
new GraphQLAppSyncStack(app, 'GraphQLAppSyncStack', {
  description: 'CDK Stack for Real-Time GraphQL API with AppSync Recipe',
  env: {
    // Use default account and region from CDK context
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Enable termination protection for production deployments
  terminationProtection: false, // Set to true for production
});

// Synthesize the app
app.synth();