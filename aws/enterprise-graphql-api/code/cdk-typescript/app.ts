#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as opensearch from 'aws-cdk-lib/aws-opensearchservice';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';

/**
 * Props for the GraphQL API Stack
 */
interface GraphQLApiStackProps extends cdk.StackProps {
  /** Environment prefix for resource naming */
  envPrefix?: string;
  /** Whether to enable X-Ray tracing */
  enableXRay?: boolean;
  /** Whether to enable enhanced monitoring */
  enableEnhancedMonitoring?: boolean;
  /** OpenSearch instance type */
  openSearchInstanceType?: string;
  /** DynamoDB billing mode */
  dynamoDbBillingMode?: dynamodb.BillingMode;
}

/**
 * Advanced GraphQL API Stack with AppSync, DynamoDB, OpenSearch, and Lambda
 * 
 * This stack creates a comprehensive GraphQL API ecosystem including:
 * - AppSync GraphQL API with multiple authentication methods
 * - Multiple DynamoDB tables for different data types
 * - OpenSearch domain for advanced search capabilities
 * - Lambda functions for custom business logic
 * - Cognito User Pool for authentication
 * - Comprehensive monitoring and logging
 */
export class GraphQLApiStack extends cdk.Stack {
  public readonly api: appsync.GraphqlApi;
  public readonly userPool: cognito.UserPool;
  public readonly productsTable: dynamodb.Table;
  public readonly usersTable: dynamodb.Table;
  public readonly analyticsTable: dynamodb.Table;
  public readonly openSearchDomain: opensearch.Domain;
  public readonly businessLogicFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: GraphQLApiStackProps = {}) {
    super(scope, id, props);

    const envPrefix = props.envPrefix || 'ecommerce';
    const enableXRay = props.enableXRay ?? true;
    const enableEnhancedMonitoring = props.enableEnhancedMonitoring ?? true;
    const openSearchInstanceType = props.openSearchInstanceType || 't3.small.search';
    const dynamoDbBillingMode = props.dynamoDbBillingMode || dynamodb.BillingMode.PAY_PER_REQUEST;

    // Create Cognito User Pool for authentication
    this.userPool = this.createUserPool(envPrefix);

    // Create DynamoDB tables
    const tables = this.createDynamoDBTables(envPrefix, dynamoDbBillingMode);
    this.productsTable = tables.productsTable;
    this.usersTable = tables.usersTable;
    this.analyticsTable = tables.analyticsTable;

    // Create OpenSearch domain for advanced search
    this.openSearchDomain = this.createOpenSearchDomain(envPrefix, openSearchInstanceType);

    // Create Lambda function for business logic
    this.businessLogicFunction = this.createBusinessLogicFunction(envPrefix);

    // Create AppSync GraphQL API
    this.api = this.createGraphQLApi(envPrefix, enableXRay, enableEnhancedMonitoring);

    // Configure data sources and resolvers
    this.configureDataSourcesAndResolvers();

    // Add sample data
    this.addSampleData();

    // Create outputs
    this.createOutputs();

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', `${envPrefix}-graphql-api`);
    cdk.Tags.of(this).add('Environment', 'development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }

  /**
   * Create Cognito User Pool with advanced configuration
   */
  private createUserPool(envPrefix: string): cognito.UserPool {
    // Create User Pool
    const userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `${envPrefix}-users`,
      selfSignUpEnabled: true,
      signInAliases: {
        email: true,
      },
      autoVerify: {
        email: true,
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      customAttributes: {
        userType: new cognito.StringAttribute({ mutable: true }),
        company: new cognito.StringAttribute({ mutable: true }),
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development only
    });

    // Create User Pool Client
    const userPoolClient = new cognito.UserPoolClient(this, 'UserPoolClient', {
      userPool,
      userPoolClientName: `${envPrefix}-client`,
      authFlows: {
        adminUserPassword: true,
        userPassword: true,
        custom: true,
        userSrp: true,
      },
      preventUserExistenceErrors: true,
      tokenValidity: {
        accessToken: cdk.Duration.minutes(60),
        idToken: cdk.Duration.minutes(60),
        refreshToken: cdk.Duration.days(30),
      },
    });

    // Create User Pool Groups
    const adminGroup = new cognito.CfnUserPoolGroup(this, 'AdminGroup', {
      userPoolId: userPool.userPoolId,
      groupName: 'admin',
      description: 'Administrator users with full access',
    });

    const sellerGroup = new cognito.CfnUserPoolGroup(this, 'SellerGroup', {
      userPoolId: userPool.userPoolId,
      groupName: 'seller',
      description: 'Seller users with product management access',
    });

    const customerGroup = new cognito.CfnUserPoolGroup(this, 'CustomerGroup', {
      userPoolId: userPool.userPoolId,
      groupName: 'customer',
      description: 'Customer users with read-only access',
    });

    return userPool;
  }

  /**
   * Create DynamoDB tables with advanced configuration
   */
  private createDynamoDBTables(envPrefix: string, billingMode: dynamodb.BillingMode) {
    // Products table with GSI for category-based queries
    const productsTable = new dynamodb.Table(this, 'ProductsTable', {
      tableName: `${envPrefix}-products`,
      partitionKey: { name: 'productId', type: dynamodb.AttributeType.STRING },
      billingMode,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development only
    });

    // Add GSI for category-based queries
    productsTable.addGlobalSecondaryIndex({
      indexName: 'CategoryIndex',
      partitionKey: { name: 'category', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Add GSI for price range queries
    productsTable.addGlobalSecondaryIndex({
      indexName: 'PriceRangeIndex',
      partitionKey: { name: 'priceRange', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Users table with GSI for user type queries
    const usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: `${envPrefix}-users`,
      partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
      billingMode,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development only
    });

    // Add GSI for user type queries
    usersTable.addGlobalSecondaryIndex({
      indexName: 'UserTypeIndex',
      partitionKey: { name: 'userType', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Analytics table for real-time metrics
    const analyticsTable = new dynamodb.Table(this, 'AnalyticsTable', {
      tableName: `${envPrefix}-analytics`,
      partitionKey: { name: 'metricId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'timestamp', type: dynamodb.AttributeType.STRING },
      billingMode,
      timeToLiveAttribute: 'ttl',
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development only
    });

    return { productsTable, usersTable, analyticsTable };
  }

  /**
   * Create OpenSearch domain for advanced search capabilities
   */
  private createOpenSearchDomain(envPrefix: string, instanceType: string): opensearch.Domain {
    const domain = new opensearch.Domain(this, 'OpenSearchDomain', {
      domainName: `${envPrefix}-search`,
      version: opensearch.EngineVersion.OPENSEARCH_2_3,
      capacity: {
        dataNodes: 1,
        dataNodeInstanceType: instanceType,
      },
      ebs: {
        volumeSize: 20,
        volumeType: opensearch.EbsDeviceVolumeType.GP3,
      },
      nodeToNodeEncryption: true,
      encryptionAtRest: {
        enabled: true,
      },
      enforceHttps: true,
      tlsSecurityPolicy: opensearch.TLSSecurityPolicy.TLS_1_2,
      accessPolicies: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['es:*'],
          resources: ['*'],
        }),
      ],
      logging: {
        slowSearchLogEnabled: true,
        appLogEnabled: true,
        slowIndexLogEnabled: true,
      },
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development only
    });

    return domain;
  }

  /**
   * Create Lambda function for advanced business logic
   */
  private createBusinessLogicFunction(envPrefix: string): lambda.Function {
    // Create Lambda execution role
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add permissions for DynamoDB and OpenSearch
    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'dynamodb:GetItem',
          'dynamodb:PutItem',
          'dynamodb:UpdateItem',
          'dynamodb:Query',
          'dynamodb:Scan',
        ],
        resources: [
          this.productsTable.tableArn,
          `${this.productsTable.tableArn}/*`,
          this.usersTable.tableArn,
          this.analyticsTable.tableArn,
        ],
      })
    );

    lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'es:ESHttpGet',
          'es:ESHttpPost',
          'es:ESHttpPut',
          'es:ESHttpDelete',
        ],
        resources: [`${this.openSearchDomain.domainArn}/*`],
      })
    );

    // Create the Lambda function
    const businessLogicFunction = new lambda.Function(this, 'BusinessLogicFunction', {
      functionName: `${envPrefix}-business-logic`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      role: lambdaRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      environment: {
        PRODUCTS_TABLE: this.productsTable.tableName,
        USERS_TABLE: this.usersTable.tableName,
        ANALYTICS_TABLE: this.analyticsTable.tableName,
        OPENSEARCH_ENDPOINT: this.openSearchDomain.domainEndpoint,
      },
      code: lambda.Code.fromInline(`
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
                throw new Error(\`Unknown field: \${field}\`);
        }
    } catch (error) {
        console.error('Error:', error);
        throw error;
    }
};

async function calculateProductScore(productId) {
    const product = await dynamodb.get({
        TableName: process.env.PRODUCTS_TABLE,
        Key: { productId }
    }).promise();
    
    if (!product.Item) {
        throw new Error('Product not found');
    }
    
    const { rating = 0, reviewCount = 0, price = 0 } = product.Item;
    
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
    
    const recommendations = result.Items.map(item => ({
        ...item,
        recommendationScore: Math.random() * 0.3 + 0.7
    })).sort((a, b) => b.recommendationScore - a.recommendationScore);
    
    return recommendations.slice(0, 5);
}

async function updateProductSearchIndex(productData) {
    // Simplified implementation - in production, would integrate with OpenSearch
    return { success: true, productId: productData.productId };
}

async function processAnalytics(eventData, identity) {
    const analyticsRecord = {
        metricId: \`\${eventData.type}-\${Date.now()}\`,
        timestamp: new Date().toISOString(),
        eventType: eventData.type,
        userId: identity.sub,
        data: eventData.data,
        ttl: Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60) // 30 days TTL
    };
    
    await dynamodb.put({
        TableName: process.env.ANALYTICS_TABLE,
        Item: analyticsRecord
    }).promise();
    
    return { success: true, eventId: analyticsRecord.metricId };
}
      `),
    });

    return businessLogicFunction;
  }

  /**
   * Create AppSync GraphQL API with enhanced configuration
   */
  private createGraphQLApi(envPrefix: string, enableXRay: boolean, enableEnhancedMonitoring: boolean): appsync.GraphqlApi {
    // Create CloudWatch log group for AppSync
    const logGroup = new logs.LogGroup(this, 'AppSyncLogGroup', {
      logGroupName: `/aws/appsync/apis/${envPrefix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create AppSync service role for CloudWatch logging
    const appSyncLogsRole = new iam.Role(this, 'AppSyncLogsRole', {
      assumedBy: new iam.ServicePrincipal('appsync.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AppSyncPushToCloudWatchLogs'),
      ],
    });

    // Define the GraphQL schema
    const schema = appsync.SchemaFile.fromAsset(path.join(__dirname, 'schema.graphql'));

    // Create the GraphQL API
    const api = new appsync.GraphqlApi(this, 'GraphQLApi', {
      name: `${envPrefix}-api`,
      schema,
      authorizationConfig: {
        defaultAuthorization: {
          authorizationType: appsync.AuthorizationType.USER_POOL,
          userPoolConfig: {
            userPool: this.userPool,
            defaultAction: appsync.UserPoolDefaultAction.ALLOW,
          },
        },
        additionalAuthorizationModes: [
          {
            authorizationType: appsync.AuthorizationType.API_KEY,
            apiKeyConfig: {
              name: 'dev-api-key',
              description: 'API Key for development testing',
              expires: cdk.Expiration.after(cdk.Duration.days(30)),
            },
          },
          {
            authorizationType: appsync.AuthorizationType.IAM,
          },
        ],
      },
      logConfig: enableEnhancedMonitoring ? {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        role: appSyncLogsRole,
      } : undefined,
      xrayEnabled: enableXRay,
    });

    return api;
  }

  /**
   * Configure data sources and resolvers
   */
  private configureDataSourcesAndResolvers(): void {
    // Create DynamoDB data source
    const productsDataSource = this.api.addDynamoDbDataSource(
      'ProductsDataSource',
      this.productsTable
    );

    const usersDataSource = this.api.addDynamoDbDataSource(
      'UsersDataSource',
      this.usersTable
    );

    const analyticsDataSource = this.api.addDynamoDbDataSource(
      'AnalyticsDataSource',
      this.analyticsTable
    );

    // Create Lambda data source
    const lambdaDataSource = this.api.addLambdaDataSource(
      'BusinessLogicDataSource',
      this.businessLogicFunction
    );

    // Create resolvers for product operations
    this.createProductResolvers(productsDataSource);
    this.createUserResolvers(usersDataSource);
    this.createAnalyticsResolvers(analyticsDataSource);
    this.createLambdaResolvers(lambdaDataSource);
  }

  /**
   * Create resolvers for product operations
   */
  private createProductResolvers(dataSource: appsync.DynamoDbDataSource): void {
    // Query resolvers
    dataSource.createResolver('GetProductResolver', {
      typeName: 'Query',
      fieldName: 'getProduct',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('productId', 'productId'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    dataSource.createResolver('ListProductsResolver', {
      typeName: 'Query',
      fieldName: 'listProducts',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
                
                #if($filterExpressions.size() > 0)
                "expression": "$util.join(" AND ", $filterExpressions)",
                "expressionValues": $util.toJson($expressionValues)
                #end
            }
            #end
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "items": $util.toJson($ctx.result.items),
            #if($ctx.result.nextToken)
            "nextToken": "$ctx.result.nextToken",
            #end
            "scannedCount": $ctx.result.scannedCount
        }
      `),
    });

    dataSource.createResolver('ListProductsByCategoryResolver', {
      typeName: 'Query',
      fieldName: 'listProductsByCategory',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "items": $util.toJson($ctx.result.items),
            #if($ctx.result.nextToken)
            "nextToken": "$ctx.result.nextToken",
            #end
            "scannedCount": $ctx.result.scannedCount
        }
      `),
    });

    // Mutation resolvers
    dataSource.createResolver('CreateProductResolver', {
      typeName: 'Mutation',
      fieldName: 'createProduct',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    dataSource.createResolver('UpdateProductResolver', {
      typeName: 'Mutation',
      fieldName: 'updateProduct',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($now = $util.time.nowISO8601())
        #set($updateExpressions = [])
        #set($expressionNames = {})
        #set($expressionValues = {})
        
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
      `),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    dataSource.createResolver('DeleteProductResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteProduct',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbDeleteItem('productId', 'productId'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
  }

  /**
   * Create resolvers for user operations
   */
  private createUserResolvers(dataSource: appsync.DynamoDbDataSource): void {
    dataSource.createResolver('GetUserResolver', {
      typeName: 'Query',
      fieldName: 'getUser',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('userId', 'userId'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    dataSource.createResolver('CreateUserResolver', {
      typeName: 'Mutation',
      fieldName: 'createUser',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($userId = $util.autoId())
        #set($now = $util.time.nowISO8601())
        
        {
            "version": "2017-02-28",
            "operation": "PutItem",
            "key": {
                "userId": $util.dynamodb.toDynamoDBJson($userId)
            },
            "attributeValues": {
                "email": $util.dynamodb.toDynamoDBJson($ctx.args.input.email),
                "userType": $util.dynamodb.toDynamoDBJson($ctx.args.input.userType),
                "createdAt": $util.dynamodb.toDynamoDBJson($now),
                #if($ctx.args.input.company)
                "company": $util.dynamodb.toDynamoDBJson($ctx.args.input.company),
                #end
                #if($ctx.args.input.preferences)
                "preferences": $util.dynamodb.toDynamoDBJson($ctx.args.input.preferences)
                #end
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
  }

  /**
   * Create resolvers for analytics operations
   */
  private createAnalyticsResolvers(dataSource: appsync.DynamoDbDataSource): void {
    dataSource.createResolver('TrackEventResolver', {
      typeName: 'Mutation',
      fieldName: 'trackEvent',
      requestMappingTemplate: appsync.MappingTemplate.fromString(`
        #set($eventId = $util.autoId())
        #set($now = $util.time.nowISO8601())
        #set($ttl = $util.time.nowEpochSeconds() + 2592000)
        
        {
            "version": "2017-02-28",
            "operation": "PutItem",
            "key": {
                "metricId": $util.dynamodb.toDynamoDBJson($eventId),
                "timestamp": $util.dynamodb.toDynamoDBJson($now)
            },
            "attributeValues": {
                "eventType": $util.dynamodb.toDynamoDBJson($ctx.args.input.eventType),
                "userId": $util.dynamodb.toDynamoDBJson($ctx.identity.sub),
                "data": $util.dynamodb.toDynamoDBJson($ctx.args.input.data),
                "processed": $util.dynamodb.toDynamoDBJson(false),
                "ttl": $util.dynamodb.toDynamoDBJson($ttl)
            }
        }
      `),
      responseMappingTemplate: appsync.MappingTemplate.fromString(`
        {
            "eventId": "$ctx.result.metricId",
            "eventType": "$ctx.result.eventType",
            "userId": "$ctx.result.userId",
            "timestamp": "$ctx.result.timestamp",
            "data": $ctx.result.data,
            "processed": $ctx.result.processed
        }
      `),
    });
  }

  /**
   * Create resolvers for Lambda-powered operations
   */
  private createLambdaResolvers(dataSource: appsync.LambdaDataSource): void {
    dataSource.createResolver('GetProductScoreResolver', {
      typeName: 'Query',
      fieldName: 'getProductScore',
      requestMappingTemplate: appsync.MappingTemplate.lambdaRequest(),
      responseMappingTemplate: appsync.MappingTemplate.lambdaResult(),
    });

    dataSource.createResolver('GetProductRecommendationsResolver', {
      typeName: 'Query',
      fieldName: 'getProductRecommendations',
      requestMappingTemplate: appsync.MappingTemplate.lambdaRequest(),
      responseMappingTemplate: appsync.MappingTemplate.lambdaResult(),
    });
  }

  /**
   * Add sample data to DynamoDB tables
   */
  private addSampleData(): void {
    // Create custom resource to add sample data
    const sampleDataProvider = new cdk.CustomResource(this, 'SampleDataProvider', {
      serviceToken: new lambda.Function(this, 'SampleDataFunction', {
        runtime: lambda.Runtime.NODEJS_18_X,
        handler: 'index.handler',
        timeout: cdk.Duration.minutes(5),
        code: lambda.Code.fromInline(`
          const AWS = require('aws-sdk');
          const dynamodb = new AWS.DynamoDB.DocumentClient();
          
          exports.handler = async (event) => {
            if (event.RequestType === 'Create') {
              await addSampleProducts();
            }
            
            const response = {
              Status: 'SUCCESS',
              PhysicalResourceId: 'sample-data-' + Date.now(),
            };
            
            await sendResponse(event, response);
          };
          
          async function addSampleProducts() {
            const products = [
              {
                productId: 'prod-001',
                name: 'Wireless Headphones',
                description: 'High-quality bluetooth headphones with noise cancellation',
                price: 299.99,
                category: 'electronics',
                priceRange: 'HIGH',
                inStock: true,
                createdAt: new Date().toISOString(),
                tags: ['wireless', 'bluetooth', 'audio'],
                rating: 4.5,
                reviewCount: 156
              },
              {
                productId: 'prod-002',
                name: 'Smartphone Case',
                description: 'Durable protective case for smartphones',
                price: 24.99,
                category: 'electronics',
                priceRange: 'LOW',
                inStock: true,
                createdAt: new Date().toISOString(),
                tags: ['protection', 'mobile'],
                rating: 4.2,
                reviewCount: 89
              }
            ];
            
            for (const product of products) {
              await dynamodb.put({
                TableName: process.env.PRODUCTS_TABLE,
                Item: product
              }).promise();
            }
          }
          
          async function sendResponse(event, response) {
            const https = require('https');
            const url = require('url');
            
            const parsedUrl = url.parse(event.ResponseURL);
            const options = {
              hostname: parsedUrl.hostname,
              port: 443,
              path: parsedUrl.path,
              method: 'PUT',
              headers: {
                'content-type': '',
                'content-length': JSON.stringify(response).length
              }
            };
            
            return new Promise((resolve, reject) => {
              const request = https.request(options, resolve);
              request.on('error', reject);
              request.write(JSON.stringify(response));
              request.end();
            });
          }
        `),
        environment: {
          PRODUCTS_TABLE: this.productsTable.tableName,
        },
        initialPolicy: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: ['dynamodb:PutItem'],
            resources: [this.productsTable.tableArn],
          }),
        ],
      }).functionArn,
    });

    sampleDataProvider.node.addDependency(this.productsTable);
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'GraphQLApiId', {
      value: this.api.apiId,
      description: 'AppSync GraphQL API ID',
      exportName: `${this.stackName}-api-id`,
    });

    new cdk.CfnOutput(this, 'GraphQLApiUrl', {
      value: this.api.graphqlUrl,
      description: 'AppSync GraphQL API URL',
      exportName: `${this.stackName}-api-url`,
    });

    new cdk.CfnOutput(this, 'GraphQLApiKey', {
      value: this.api.apiKey || 'No API Key',
      description: 'AppSync API Key for development',
    });

    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: `${this.stackName}-user-pool-id`,
    });

    new cdk.CfnOutput(this, 'ProductsTableName', {
      value: this.productsTable.tableName,
      description: 'DynamoDB Products Table Name',
      exportName: `${this.stackName}-products-table`,
    });

    new cdk.CfnOutput(this, 'OpenSearchDomainEndpoint', {
      value: this.openSearchDomain.domainEndpoint,
      description: 'OpenSearch Domain Endpoint',
      exportName: `${this.stackName}-opensearch-endpoint`,
    });

    new cdk.CfnOutput(this, 'BusinessLogicFunctionName', {
      value: this.businessLogicFunction.functionName,
      description: 'Lambda Business Logic Function Name',
      exportName: `${this.stackName}-lambda-function`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const envPrefix = app.node.tryGetContext('envPrefix') || process.env.ENV_PREFIX || 'ecommerce';
const enableXRay = app.node.tryGetContext('enableXRay') ?? true;
const enableEnhancedMonitoring = app.node.tryGetContext('enableEnhancedMonitoring') ?? true;
const openSearchInstanceType = app.node.tryGetContext('openSearchInstanceType') || 't3.small.search';

// Create the stack
new GraphQLApiStack(app, 'GraphQLApiStack', {
  description: 'Advanced GraphQL API with AppSync, DynamoDB, OpenSearch, and Lambda',
  envPrefix,
  enableXRay,
  enableEnhancedMonitoring,
  openSearchInstanceType,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'GraphQL-API-Recipe',
    Environment: 'Development',
    Repository: 'recipes',
    ManagedBy: 'CDK',
  },
});

// Synthesize the CloudFormation template
app.synth();