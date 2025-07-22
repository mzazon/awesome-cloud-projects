#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  Stack,
  StackProps,
  CfnOutput,
  RemovalPolicy,
  Duration,
  Tags,
} from 'aws-cdk-lib';
import {
  Function as LambdaFunction,
  Runtime,
  Architecture,
  Code,
  FunctionProps,
} from 'aws-cdk-lib/aws-lambda';
import {
  RestApi,
  LambdaIntegration,
  Resource,
  MethodOptions,
  Cors,
  EndpointType,
  RequestValidator,
  Model,
  JsonSchemaType,
  JsonSchemaVersion,
  RequestValidatorOptions,
} from 'aws-cdk-lib/aws-apigateway';
import {
  Role,
  ServicePrincipal,
  PolicyStatement,
  Effect,
  ManagedPolicy,
  PolicyDocument,
} from 'aws-cdk-lib/aws-iam';
import { 
  CfnCluster as DSQLCluster,
  CfnMultiRegionClusters,
} from 'aws-cdk-lib/aws-dsql';
import {
  LogGroup,
  RetentionDays,
} from 'aws-cdk-lib/aws-logs';

/**
 * Interface defining properties for the multi-region Aurora DSQL stack
 */
interface MultiRegionAuroraDSQLStackProps extends StackProps {
  /** Whether this is the primary region deployment */
  isPrimary: boolean;
  /** Name for the Aurora DSQL cluster */
  clusterName: string;
  /** AWS region that will serve as the witness for multi-region setup */
  witnessRegion: string;
  /** List of peer cluster ARNs for multi-region configuration */
  peerClusterArns?: string[];
  /** Application environment (dev, staging, prod) */
  environment: string;
}

/**
 * AWS CDK Stack for deploying multi-region Aurora DSQL application
 * 
 * This stack creates:
 * - Aurora DSQL cluster with multi-region configuration
 * - Lambda function for database operations
 * - API Gateway for RESTful endpoints
 * - IAM roles with least privilege access
 * - CloudWatch logging for observability
 */
export class MultiRegionAuroraDSQLStack extends Stack {
  /** The Aurora DSQL cluster instance */
  public readonly dsqlCluster: DSQLCluster;
  
  /** The API Gateway instance */
  public readonly api: RestApi;
  
  /** The Lambda function handling database operations */
  public readonly lambdaFunction: LambdaFunction;

  constructor(scope: Construct, id: string, props: MultiRegionAuroraDSQLStackProps) {
    super(scope, id, props);

    // Apply common tags to all resources
    this.applyCommonTags(props);

    // Create Aurora DSQL cluster
    this.dsqlCluster = this.createDSQLCluster(props);

    // Create IAM role for Lambda with Aurora DSQL permissions
    const lambdaRole = this.createLambdaExecutionRole();

    // Create Lambda function for database operations
    this.lambdaFunction = this.createLambdaFunction(lambdaRole, props);

    // Create API Gateway for RESTful endpoints
    this.api = this.createApiGateway(props);

    // Create stack outputs for cross-stack references
    this.createOutputs(props);

    // Add dependencies to ensure proper resource creation order
    this.lambdaFunction.node.addDependency(this.dsqlCluster);
    this.api.node.addDependency(this.lambdaFunction);
  }

  /**
   * Creates Aurora DSQL cluster with multi-region configuration
   */
  private createDSQLCluster(props: MultiRegionAuroraDSQLStackProps): DSQLCluster {
    const cluster = new DSQLCluster(this, 'AuroraDSQLCluster', {
      // Enable deletion protection in production environments
      deletionProtection: props.environment === 'prod',
      
      // Configure multi-region properties for distributed architecture
      ...(props.isPrimary && {
        multiRegionProperties: {
          witnessRegion: props.witnessRegion,
          linkedClusterArns: props.peerClusterArns || [],
        },
      }),
      
      // Apply resource tags for governance and cost allocation
      tags: {
        Name: `${props.clusterName}-${props.isPrimary ? 'primary' : 'secondary'}`,
        Environment: props.environment,
        Region: this.region,
        IsPrimary: props.isPrimary.toString(),
      },
    });

    return cluster;
  }

  /**
   * Creates IAM execution role for Lambda with Aurora DSQL permissions
   */
  private createLambdaExecutionRole(): Role {
    const role = new Role(this, 'DSQLLambdaExecutionRole', {
      assumedBy: new ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Aurora DSQL Lambda functions',
      
      // Attach AWS managed policy for basic Lambda execution
      managedPolicies: [
        ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],

      // Define custom policy for Aurora DSQL access
      inlinePolicies: {
        AuroraDSQLAccess: new PolicyDocument({
          statements: [
            // Aurora DSQL connection and query permissions
            new PolicyStatement({
              effect: Effect.ALLOW,
              actions: [
                'dsql:DbConnect',
                'dsql:DbConnectAdmin',
                'dsql:ExecuteStatement',
                'dsql:BatchExecuteStatement',
              ],
              resources: [this.dsqlCluster.attrArn],
            }),
            
            // CloudWatch Logs permissions for enhanced observability
            new PolicyStatement({
              effect: Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
          ],
        }),
      },
    });

    return role;
  }

  /**
   * Creates Lambda function for handling Aurora DSQL operations
   */
  private createLambdaFunction(role: Role, props: MultiRegionAuroraDSQLStackProps): LambdaFunction {
    // Create CloudWatch Log Group with retention policy
    const logGroup = new LogGroup(this, 'DSQLLambdaLogGroup', {
      logGroupName: `/aws/lambda/dsql-multi-region-${props.environment}`,
      retention: RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const lambdaFunction = new LambdaFunction(this, 'DSQLLambdaFunction', {
      runtime: Runtime.NODEJS_20_X,
      architecture: Architecture.ARM_64, // ARM64 for cost optimization
      handler: 'index.handler',
      
      // Inline Lambda function code for Aurora DSQL operations
      code: Code.fromInline(`
const { DSQLClient, ExecuteStatementCommand, BatchExecuteStatementCommand } = require('@aws-sdk/client-dsql');

// Initialize Aurora DSQL client
const dsqlClient = new DSQLClient({ 
  region: process.env.AWS_REGION,
  maxAttempts: 3,
});

/**
 * Main Lambda handler for Aurora DSQL operations
 */
exports.handler = async (event, context) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    const { httpMethod, path, body, queryStringParameters } = event;
    
    // Route requests based on HTTP method and path
    switch (path) {
      case '/health':
        return await handleHealthCheck();
      
      case '/users':
        if (httpMethod === 'GET') {
          return await handleGetUsers(queryStringParameters);
        } else if (httpMethod === 'POST') {
          return await handleCreateUser(JSON.parse(body || '{}'));
        }
        break;
      
      case '/users/init':
        if (httpMethod === 'POST') {
          return await handleInitializeSchema();
        }
        break;
      
      default:
        return createResponse(404, { error: 'Not Found' });
    }
    
    return createResponse(405, { error: 'Method Not Allowed' });
    
  } catch (error) {
    console.error('Lambda execution error:', error);
    return createResponse(500, {
      error: 'Internal Server Error',
      message: error.message,
      region: process.env.AWS_REGION,
    });
  }
};

/**
 * Health check endpoint
 */
async function handleHealthCheck() {
  try {
    // Test database connectivity
    const result = await dsqlClient.send(new ExecuteStatementCommand({
      Database: 'postgres',
      Sql: 'SELECT 1 as health_check',
    }));
    
    return createResponse(200, {
      status: 'healthy',
      region: process.env.AWS_REGION,
      cluster: process.env.DSQL_CLUSTER_ARN,
      timestamp: new Date().toISOString(),
      dbConnection: 'active',
    });
  } catch (error) {
    console.error('Health check failed:', error);
    return createResponse(503, {
      status: 'unhealthy',
      region: process.env.AWS_REGION,
      error: error.message,
    });
  }
}

/**
 * Get all users from the database
 */
async function handleGetUsers(queryParams) {
  try {
    const limit = queryParams?.limit ? parseInt(queryParams.limit) : 50;
    const offset = queryParams?.offset ? parseInt(queryParams.offset) : 0;
    
    const result = await dsqlClient.send(new ExecuteStatementCommand({
      Database: 'postgres',
      Sql: 'SELECT id, name, email, created_at FROM users ORDER BY created_at DESC LIMIT $1 OFFSET $2',
      Parameters: [
        { Value: { LongValue: limit } },
        { Value: { LongValue: offset } },
      ],
    }));
    
    const users = result.Records?.map(record => ({
      id: record[0]?.LongValue,
      name: record[1]?.StringValue,
      email: record[2]?.StringValue,
      created_at: record[3]?.StringValue,
    })) || [];
    
    return createResponse(200, {
      users,
      count: users.length,
      region: process.env.AWS_REGION,
      pagination: { limit, offset },
    });
  } catch (error) {
    console.error('Get users error:', error);
    return createResponse(500, { error: 'Failed to retrieve users', message: error.message });
  }
}

/**
 * Create a new user
 */
async function handleCreateUser(userData) {
  try {
    const { name, email } = userData;
    
    if (!name || !email) {
      return createResponse(400, { error: 'Name and email are required' });
    }
    
    // Validate email format
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
      return createResponse(400, { error: 'Invalid email format' });
    }
    
    const result = await dsqlClient.send(new ExecuteStatementCommand({
      Database: 'postgres',
      Sql: 'INSERT INTO users (name, email) VALUES ($1, $2) RETURNING id, name, email, created_at',
      Parameters: [
        { Value: { StringValue: name } },
        { Value: { StringValue: email } },
      ],
    }));
    
    const user = {
      id: result.Records[0][0].LongValue,
      name: result.Records[0][1].StringValue,
      email: result.Records[0][2].StringValue,
      created_at: result.Records[0][3].StringValue,
    };
    
    return createResponse(201, {
      user,
      region: process.env.AWS_REGION,
      message: 'User created successfully',
    });
  } catch (error) {
    console.error('Create user error:', error);
    
    // Handle duplicate email constraint
    if (error.message?.includes('duplicate key')) {
      return createResponse(409, { error: 'Email already exists' });
    }
    
    return createResponse(500, { error: 'Failed to create user', message: error.message });
  }
}

/**
 * Initialize database schema
 */
async function handleInitializeSchema() {
  try {
    // Create users table with proper constraints
    await dsqlClient.send(new ExecuteStatementCommand({
      Database: 'postgres',
      Sql: \`
        CREATE TABLE IF NOT EXISTS users (
          id SERIAL PRIMARY KEY,
          name VARCHAR(100) NOT NULL,
          email VARCHAR(255) UNIQUE NOT NULL,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      \`,
    }));
    
    // Create indexes for efficient querying
    await dsqlClient.send(new ExecuteStatementCommand({
      Database: 'postgres',
      Sql: 'CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)',
    }));
    
    await dsqlClient.send(new ExecuteStatementCommand({
      Database: 'postgres',
      Sql: 'CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)',
    }));
    
    // Insert sample data
    await dsqlClient.send(new BatchExecuteStatementCommand({
      Database: 'postgres',
      Sql: 'INSERT INTO users (name, email) VALUES ($1, $2) ON CONFLICT (email) DO NOTHING',
      ParameterSets: [
        [
          { Value: { StringValue: 'John Doe' } },
          { Value: { StringValue: 'john.doe@example.com' } },
        ],
        [
          { Value: { StringValue: 'Jane Smith' } },
          { Value: { StringValue: 'jane.smith@example.com' } },
        ],
        [
          { Value: { StringValue: 'Bob Johnson' } },
          { Value: { StringValue: 'bob.johnson@example.com' } },
        ],
      ],
    }));
    
    return createResponse(200, {
      message: 'Database schema initialized successfully',
      region: process.env.AWS_REGION,
      timestamp: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Schema initialization error:', error);
    return createResponse(500, { error: 'Failed to initialize schema', message: error.message });
  }
}

/**
 * Create standardized API response
 */
function createResponse(statusCode, body) {
  return {
    statusCode,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
    body: JSON.stringify(body),
  };
}
      `),
      
      // Environment variables for Aurora DSQL configuration
      environment: {
        DSQL_CLUSTER_ARN: this.dsqlCluster.attrArn,
        ENVIRONMENT: props.environment,
        REGION: this.region,
      },
      
      // Performance and cost optimization settings
      timeout: Duration.seconds(30),
      memorySize: 512,
      
      // Security and execution configuration
      role: role,
      logGroup: logGroup,
      
      // Enhanced monitoring and tracing
      retryAttempts: 2,
      reservedConcurrentExecutions: props.environment === 'prod' ? 100 : 10,
    });

    return lambdaFunction;
  }

  /**
   * Creates API Gateway with proper CORS and validation
   */
  private createApiGateway(props: MultiRegionAuroraDSQLStackProps): RestApi {
    const api = new RestApi(this, 'DSQLApiGateway', {
      restApiName: `aurora-dsql-api-${props.environment}-${props.isPrimary ? 'primary' : 'secondary'}`,
      description: `Multi-region Aurora DSQL API for ${props.environment} environment`,
      
      // Regional endpoint for optimal performance
      endpointTypes: [EndpointType.REGIONAL],
      
      // CORS configuration for web applications
      defaultCorsPreflightOptions: {
        allowOrigins: Cors.ALL_ORIGINS,
        allowMethods: Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key', 'X-Amz-Security-Token'],
      },
      
      // Deployment configuration
      deploy: true,
      deployOptions: {
        stageName: 'prod',
        throttle: {
          rateLimit: 1000,
          burstLimit: 2000,
        },
        loggingLevel: props.environment === 'prod' ? 
          cdk.aws_apigateway.MethodLoggingLevel.ERROR : 
          cdk.aws_apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: props.environment !== 'prod',
      },
      
      // Cloud Watch role for API Gateway logging
      cloudWatchRole: true,
    });

    // Create Lambda integration
    const lambdaIntegration = new LambdaIntegration(this.lambdaFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' },
      proxy: true,
    });

    // Create request validator for POST requests
    const requestValidator = api.addRequestValidator('RequestValidator', {
      validateRequestBody: true,
      validateRequestParameters: true,
    });

    // Create user model for request validation
    const userModel = api.addModel('UserModel', {
      contentType: 'application/json',
      modelName: 'User',
      schema: {
        schema: JsonSchemaVersion.DRAFT4,
        title: 'User',
        type: JsonSchemaType.OBJECT,
        properties: {
          name: { 
            type: JsonSchemaType.STRING,
            minLength: 1,
            maxLength: 100,
          },
          email: { 
            type: JsonSchemaType.STRING,
            pattern: '^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$',
          },
        },
        required: ['name', 'email'],
      },
    });

    // Health check endpoint
    const healthResource = api.root.addResource('health');
    healthResource.addMethod('GET', lambdaIntegration, {
      operationName: 'GetHealthStatus',
    });

    // Users resource endpoints
    const usersResource = api.root.addResource('users');
    
    // GET /users - List users
    usersResource.addMethod('GET', lambdaIntegration, {
      operationName: 'GetUsers',
      requestParameters: {
        'method.request.querystring.limit': false,
        'method.request.querystring.offset': false,
      },
    });

    // POST /users - Create user
    usersResource.addMethod('POST', lambdaIntegration, {
      operationName: 'CreateUser',
      requestValidator: requestValidator,
      requestModels: {
        'application/json': userModel,
      },
    });

    // Schema initialization endpoint
    const initResource = usersResource.addResource('init');
    initResource.addMethod('POST', lambdaIntegration, {
      operationName: 'InitializeSchema',
    });

    return api;
  }

  /**
   * Creates CloudFormation outputs for cross-stack references
   */
  private createOutputs(props: MultiRegionAuroraDSQLStackProps): void {
    // Aurora DSQL cluster ARN for cross-region references
    new CfnOutput(this, 'DSQLClusterArn', {
      value: this.dsqlCluster.attrArn,
      description: 'Aurora DSQL Cluster ARN',
      exportName: `${this.stackName}-DSQLClusterArn`,
    });

    // Aurora DSQL cluster endpoint
    new CfnOutput(this, 'DSQLClusterEndpoint', {
      value: this.dsqlCluster.attrEndpoint,
      description: 'Aurora DSQL Cluster Endpoint',
      exportName: `${this.stackName}-DSQLClusterEndpoint`,
    });

    // API Gateway URL
    new CfnOutput(this, 'ApiGatewayUrl', {
      value: this.api.url,
      description: 'API Gateway URL',
      exportName: `${this.stackName}-ApiGatewayUrl`,
    });

    // Lambda function ARN
    new CfnOutput(this, 'LambdaFunctionArn', {
      value: this.lambdaFunction.functionArn,
      description: 'Lambda Function ARN',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    // Region identifier
    new CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
      exportName: `${this.stackName}-Region`,
    });
  }

  /**
   * Applies common tags to all resources in the stack
   */
  private applyCommonTags(props: MultiRegionAuroraDSQLStackProps): void {
    Tags.of(this).add('Project', 'MultiRegionAuroraDSQL');
    Tags.of(this).add('Environment', props.environment);
    Tags.of(this).add('Region', this.region);
    Tags.of(this).add('IsPrimary', props.isPrimary.toString());
    Tags.of(this).add('CreatedBy', 'CDK');
    Tags.of(this).add('Repository', 'aws-recipes');
  }
}

/**
 * CDK Application definition and multi-region deployment configuration
 */
const app = new cdk.App();

// Configuration parameters
const clusterName = app.node.tryGetContext('clusterName') || 'multi-region-aurora-dsql';
const environment = app.node.tryGetContext('environment') || 'dev';
const witnessRegion = app.node.tryGetContext('witnessRegion') || 'us-west-2';

// AWS account and regions configuration
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const primaryRegion = app.node.tryGetContext('primaryRegion') || 'us-east-1';
const secondaryRegion = app.node.tryGetContext('secondaryRegion') || 'us-east-2';

// Deploy primary stack
const primaryStack = new MultiRegionAuroraDSQLStack(app, 'MultiRegionAuroraDSQLPrimary', {
  env: {
    account: account,
    region: primaryRegion,
  },
  isPrimary: true,
  clusterName: clusterName,
  witnessRegion: witnessRegion,
  environment: environment,
  description: `Primary Aurora DSQL stack in ${primaryRegion}`,
});

// Deploy secondary stack
const secondaryStack = new MultiRegionAuroraDSQLStack(app, 'MultiRegionAuroraDSQLSecondary', {
  env: {
    account: account,
    region: secondaryRegion,
  },
  isPrimary: false,
  clusterName: clusterName,
  witnessRegion: witnessRegion,
  peerClusterArns: [primaryStack.dsqlCluster.attrArn],
  environment: environment,
  description: `Secondary Aurora DSQL stack in ${secondaryRegion}`,
});

// Add dependency to ensure primary stack is deployed first
secondaryStack.addDependency(primaryStack);

// Synthesize CloudFormation templates
app.synth();