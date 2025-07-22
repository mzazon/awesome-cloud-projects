import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as amplify from '@aws-cdk/aws-amplify-alpha';
import { Construct } from 'constructs';

export interface ProgressiveWebAppStackProps extends cdk.StackProps {
  config: {
    appName: string;
    environment: string;
    region: string;
    account?: string;
    enableAnalytics?: boolean;
    enableCustomDomain?: boolean;
    customDomainName?: string;
    enableMFA?: boolean;
    passwordPolicy?: {
      minLength: number;
      requireUppercase: boolean;
      requireLowercase: boolean;
      requireNumbers: boolean;
      requireSymbols: boolean;
    };
  };
}

/**
 * Progressive Web Application Stack using AWS Amplify
 * 
 * This stack creates a complete serverless architecture for a Progressive Web App
 * with offline-first capabilities, real-time synchronization, and modern authentication.
 * 
 * Key Features:
 * - Amazon Cognito for secure user authentication
 * - AWS AppSync for GraphQL API with real-time subscriptions
 * - DynamoDB for scalable data storage
 * - S3 for file storage and static hosting
 * - CloudFront for global content delivery
 * - AWS Amplify for hosting and CI/CD
 */
export class ProgressiveWebAppStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly identityPool: cognito.CfnIdentityPool;
  public readonly graphqlApi: appsync.GraphqlApi;
  public readonly taskTable: dynamodb.Table;
  public readonly storageBucket: s3.Bucket;
  public readonly distribution: cloudfront.Distribution;
  public readonly amplifyApp: amplify.App;

  constructor(scope: Construct, id: string, props: ProgressiveWebAppStackProps) {
    super(scope, id, props);

    const { config } = props;

    // Create Amazon Cognito User Pool for authentication
    this.userPool = this.createUserPool(config);
    
    // Create User Pool Client for web applications
    this.userPoolClient = this.createUserPoolClient(this.userPool, config);
    
    // Create Identity Pool for AWS resource access
    this.identityPool = this.createIdentityPool(this.userPool, this.userPoolClient, config);
    
    // Create DynamoDB table for task data
    this.taskTable = this.createTaskTable(config);
    
    // Create S3 bucket for file storage
    this.storageBucket = this.createStorageBucket(config);
    
    // Create AppSync GraphQL API
    this.graphqlApi = this.createGraphQLApi(config);
    
    // Create data sources and resolvers
    this.createDataSources();
    this.createResolvers();
    
    // Create CloudFront distribution for global content delivery
    this.distribution = this.createCloudFrontDistribution(config);
    
    // Create Amplify app for hosting and CI/CD
    this.amplifyApp = this.createAmplifyApp(config);
    
    // Create IAM roles and policies
    this.createIAMRoles();
    
    // Create stack outputs
    this.createOutputs();
  }

  /**
   * Creates Amazon Cognito User Pool with security best practices
   */
  private createUserPool(config: any): cognito.UserPool {
    const userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `${config.appName}-${config.environment}-user-pool`,
      
      // Sign-in configuration
      signInAliases: {
        username: true,
        email: true,
      },
      
      // Auto-verified attributes
      autoVerify: {
        email: true,
      },
      
      // Password policy
      passwordPolicy: {
        minLength: config.passwordPolicy?.minLength || 8,
        requireUppercase: config.passwordPolicy?.requireUppercase || true,
        requireLowercase: config.passwordPolicy?.requireLowercase || true,
        requireDigits: config.passwordPolicy?.requireNumbers || true,
        requireSymbols: config.passwordPolicy?.requireSymbols || true,
      },
      
      // Account recovery
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      
      // MFA configuration
      mfa: config.enableMFA ? cognito.Mfa.REQUIRED : cognito.Mfa.OPTIONAL,
      mfaSecondFactor: {
        sms: true,
        otp: true,
      },
      
      // User attributes
      standardAttributes: {
        email: {
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
      
      // Device tracking
      deviceTracking: {
        challengeRequiredOnNewDevice: true,
        deviceOnlyRememberedOnUserPrompt: true,
      },
      
      // Deletion protection
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    // Add custom attributes if needed
    userPool.addCustomAttributes({
      'custom:role': new cognito.StringAttribute({
        minLen: 1,
        maxLen: 50,
        mutable: true,
      }),
    });

    return userPool;
  }

  /**
   * Creates User Pool Client for web applications
   */
  private createUserPoolClient(userPool: cognito.UserPool, config: any): cognito.UserPoolClient {
    return new cognito.UserPoolClient(this, 'UserPoolClient', {
      userPool,
      userPoolClientName: `${config.appName}-${config.environment}-web-client`,
      
      // Generate secret for server-side authentication
      generateSecret: false,
      
      // OAuth settings
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
          implicitCodeGrant: false,
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: [
          'http://localhost:3000/',
          'https://localhost:3000/',
        ],
        logoutUrls: [
          'http://localhost:3000/',
          'https://localhost:3000/',
        ],
      },
      
      // Supported identity providers
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
      ],
      
      // Token validity
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      
      // Prevent user existence errors
      preventUserExistenceErrors: true,
      
      // Auth flows
      authFlows: {
        userSrp: true,
        userPassword: false,
        adminUserPassword: false,
      },
      
      // Attribute read and write permissions
      readAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          givenName: true,
          familyName: true,
        })
        .withCustomAttributes('custom:role'),
      
      writeAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          givenName: true,
          familyName: true,
        })
        .withCustomAttributes('custom:role'),
    });
  }

  /**
   * Creates Cognito Identity Pool for AWS resource access
   */
  private createIdentityPool(userPool: cognito.UserPool, userPoolClient: cognito.UserPoolClient, config: any): cognito.CfnIdentityPool {
    const identityPool = new cognito.CfnIdentityPool(this, 'IdentityPool', {
      identityPoolName: `${config.appName}-${config.environment}-identity-pool`,
      allowUnauthenticatedIdentities: false,
      
      cognitoIdentityProviders: [
        {
          clientId: userPoolClient.userPoolClientId,
          providerName: userPool.userPoolProviderName,
        },
      ],
    });

    // Create IAM roles for authenticated users
    const authenticatedRole = new iam.Role(this, 'AuthenticatedRole', {
      roleName: `${config.appName}-${config.environment}-authenticated-role`,
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
    });

    // Attach role to identity pool
    new cognito.CfnIdentityPoolRoleAttachment(this, 'IdentityPoolRoleAttachment', {
      identityPoolId: identityPool.ref,
      roles: {
        authenticated: authenticatedRole.roleArn,
      },
    });

    return identityPool;
  }

  /**
   * Creates DynamoDB table for task data with best practices
   */
  private createTaskTable(config: any): dynamodb.Table {
    return new dynamodb.Table(this, 'TaskTable', {
      tableName: `${config.appName}-${config.environment}-tasks`,
      partitionKey: {
        name: 'id',
        type: dynamodb.AttributeType.STRING,
      },
      
      // Billing mode
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      
      // Encryption
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      
      // Point-in-time recovery
      pointInTimeRecovery: true,
      
      // Global secondary index for user queries
      globalSecondaryIndexes: [
        {
          indexName: 'UserIndex',
          partitionKey: {
            name: 'owner',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'createdAt',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
      
      // Stream for real-time updates
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      
      // Deletion protection
      removalPolicy: cdk.RemovalPolicy.RETAIN,
      
      // Tags
      tags: {
        Name: `${config.appName}-${config.environment}-tasks`,
        Environment: config.environment,
        Application: config.appName,
      },
    });
  }

  /**
   * Creates S3 bucket for file storage
   */
  private createStorageBucket(config: any): s3.Bucket {
    return new s3.Bucket(this, 'StorageBucket', {
      bucketName: `${config.appName}-${config.environment}-storage-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      
      // Access control
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      
      // Encryption
      encryption: s3.BucketEncryption.S3_MANAGED,
      
      // Versioning
      versioned: true,
      
      // CORS configuration for web applications
      cors: [
        {
          allowedHeaders: ['*'],
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.PUT,
            s3.HttpMethods.POST,
            s3.HttpMethods.DELETE,
          ],
          allowedOrigins: ['*'],
          exposedHeaders: ['ETag'],
          maxAge: 3000,
        },
      ],
      
      // Lifecycle rules
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
      ],
      
      // Deletion protection
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
  }

  /**
   * Creates AWS AppSync GraphQL API
   */
  private createGraphQLApi(config: any): appsync.GraphqlApi {
    // Create CloudWatch log group for API logging
    const logGroup = new logs.LogGroup(this, 'GraphQLApiLogGroup', {
      logGroupName: `/aws/appsync/${config.appName}-${config.environment}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const api = new appsync.GraphqlApi(this, 'GraphQLApi', {
      name: `${config.appName}-${config.environment}-api`,
      
      // Schema definition
      schema: appsync.SchemaFile.fromAsset('./lib/schema.graphql'),
      
      // Authorization configuration
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
            authorizationType: appsync.AuthorizationType.IAM,
          },
        ],
      },
      
      // Logging configuration
      logConfig: {
        fieldLogLevel: appsync.FieldLogLevel.ALL,
        role: new iam.Role(this, 'GraphQLApiLogRole', {
          assumedBy: new iam.ServicePrincipal('appsync.amazonaws.com'),
          managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSAppSyncPushToCloudWatchLogs'),
          ],
        }),
      },
      
      // X-Ray tracing
      xrayEnabled: true,
    });

    return api;
  }

  /**
   * Creates data sources for the GraphQL API
   */
  private createDataSources(): void {
    // DynamoDB data source
    this.graphqlApi.addDynamoDbDataSource('TaskDataSource', this.taskTable);
    
    // S3 data source for file operations
    this.graphqlApi.addNoneDataSource('S3DataSource', {
      name: 'S3DataSource',
      description: 'Data source for S3 operations',
    });
  }

  /**
   * Creates GraphQL resolvers
   */
  private createResolvers(): void {
    const taskDataSource = this.graphqlApi.getDataSource('TaskDataSource') as appsync.DynamoDbDataSource;
    
    // Query resolvers
    taskDataSource.createResolver('GetTaskResolver', {
      typeName: 'Query',
      fieldName: 'getTask',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
    
    taskDataSource.createResolver('ListTasksResolver', {
      typeName: 'Query',
      fieldName: 'listTasks',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbScanTable(),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });
    
    // Mutation resolvers
    taskDataSource.createResolver('CreateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'createTask',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
    
    taskDataSource.createResolver('UpdateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'updateTask',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').is('input.id'),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
    
    taskDataSource.createResolver('DeleteTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'deleteTask',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbDeleteItem('id', 'input.id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
  }

  /**
   * Creates CloudFront distribution for global content delivery
   */
  private createCloudFrontDistribution(config: any): cloudfront.Distribution {
    return new cloudfront.Distribution(this, 'Distribution', {
      comment: `${config.appName} ${config.environment} CDN`,
      
      defaultBehavior: {
        origin: new origins.S3Origin(this.storageBucket),
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachedMethods: cloudfront.CachedMethods.CACHE_GET_HEAD_OPTIONS,
        compress: true,
        
        // Cache policy
        cachePolicy: cloudfront.CachePolicy.CACHING_OPTIMIZED,
        
        // Origin request policy
        originRequestPolicy: cloudfront.OriginRequestPolicy.CORS_S3_ORIGIN,
      },
      
      // Additional behaviors for API endpoints
      additionalBehaviors: {
        '/api/*': {
          origin: new origins.HttpOrigin(this.graphqlApi.graphqlUrl.replace('https://', '').replace('/graphql', '')),
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
        },
      },
      
      // Error pages
      errorResponses: [
        {
          httpStatus: 404,
          responseHttpStatus: 200,
          responsePagePath: '/index.html',
        },
      ],
      
      // Security headers
      defaultRootObject: 'index.html',
      
      // Enable logging
      enableLogging: true,
      
      // Price class
      priceClass: cloudfront.PriceClass.PRICE_CLASS_100,
    });
  }

  /**
   * Creates AWS Amplify app for hosting and CI/CD
   */
  private createAmplifyApp(config: any): amplify.App {
    const amplifyApp = new amplify.App(this, 'AmplifyApp', {
      appName: `${config.appName}-${config.environment}`,
      description: `Progressive Web App - ${config.appName}`,
      
      // Build settings
      buildSpec: amplify.BuildSpec.fromObjectToYaml({
        version: '1.0',
        applications: [
          {
            frontend: {
              phases: {
                preBuild: {
                  commands: [
                    'npm install',
                  ],
                },
                build: {
                  commands: [
                    'npm run build',
                  ],
                },
              },
              artifacts: {
                baseDirectory: 'build',
                files: ['**/*'],
              },
              cache: {
                paths: ['node_modules/**/*'],
              },
            },
          },
        ],
      }),
      
      // Environment variables
      environmentVariables: {
        AMPLIFY_DIFF_DEPLOY: 'false',
        AMPLIFY_MONOREPO_APP_ROOT: '/',
        _LIVE_UPDATES: '[{"name":"Amplify CLI","pkg":"@aws-amplify/cli","type":"npm","version":"latest"}]',
      },
      
      // Custom rules for SPA routing
      customRules: [
        {
          source: '/<*>',
          target: '/index.html',
          status: amplify.RedirectStatus.NOT_FOUND_REWRITE,
        },
      ],
      
      // Auto branch creation
      autoBranchCreation: {
        patterns: ['main', 'develop'],
        autoBuild: true,
        pullRequestPreview: true,
      },
      
      // Auto branch deletion
      autoBranchDeletion: true,
    });

    // Add main branch
    const mainBranch = amplifyApp.addBranch('main', {
      branchName: 'main',
      autoBuild: true,
      pullRequestPreview: true,
    });

    return amplifyApp;
  }

  /**
   * Creates IAM roles and policies
   */
  private createIAMRoles(): void {
    // Get the authenticated role from the identity pool
    const authenticatedRole = iam.Role.fromRoleArn(
      this,
      'ImportedAuthenticatedRole',
      `arn:aws:iam::${this.account}:role/${this.identityPool.identityPoolName}-authenticated-role`
    );

    // Add policies for S3 access
    authenticatedRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        's3:GetObject',
        's3:PutObject',
        's3:DeleteObject',
      ],
      resources: [
        `${this.storageBucket.bucketArn}/public/*`,
        `${this.storageBucket.bucketArn}/protected/\${cognito-identity.amazonaws.com:sub}/*`,
        `${this.storageBucket.bucketArn}/private/\${cognito-identity.amazonaws.com:sub}/*`,
      ],
    }));

    // Add policies for AppSync access
    authenticatedRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'appsync:GraphQL',
      ],
      resources: [
        `${this.graphqlApi.arn}/*`,
      ],
    }));

    // Add policies for DynamoDB access (through AppSync)
    authenticatedRole.addToPolicy(new iam.PolicyStatement({
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
      ],
      conditions: {
        'ForAllValues:StringEquals': {
          'dynamodb:LeadingKeys': ['${cognito-identity.amazonaws.com:sub}'],
        },
      },
    }));
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    // Cognito outputs
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

    // AppSync outputs
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

    // DynamoDB outputs
    new cdk.CfnOutput(this, 'TaskTableName', {
      value: this.taskTable.tableName,
      description: 'DynamoDB Task Table Name',
      exportName: `${this.stackName}-TaskTableName`,
    });

    new cdk.CfnOutput(this, 'TaskTableArn', {
      value: this.taskTable.tableArn,
      description: 'DynamoDB Task Table ARN',
      exportName: `${this.stackName}-TaskTableArn`,
    });

    // S3 outputs
    new cdk.CfnOutput(this, 'StorageBucketName', {
      value: this.storageBucket.bucketName,
      description: 'S3 Storage Bucket Name',
      exportName: `${this.stackName}-StorageBucketName`,
    });

    new cdk.CfnOutput(this, 'StorageBucketArn', {
      value: this.storageBucket.bucketArn,
      description: 'S3 Storage Bucket ARN',
      exportName: `${this.stackName}-StorageBucketArn`,
    });

    // CloudFront outputs
    new cdk.CfnOutput(this, 'DistributionId', {
      value: this.distribution.distributionId,
      description: 'CloudFront Distribution ID',
      exportName: `${this.stackName}-DistributionId`,
    });

    new cdk.CfnOutput(this, 'DistributionDomainName', {
      value: this.distribution.distributionDomainName,
      description: 'CloudFront Distribution Domain Name',
      exportName: `${this.stackName}-DistributionDomainName`,
    });

    // Amplify outputs
    new cdk.CfnOutput(this, 'AmplifyAppId', {
      value: this.amplifyApp.appId,
      description: 'Amplify App ID',
      exportName: `${this.stackName}-AmplifyAppId`,
    });

    new cdk.CfnOutput(this, 'AmplifyAppArn', {
      value: this.amplifyApp.arn,
      description: 'Amplify App ARN',
      exportName: `${this.stackName}-AmplifyAppArn`,
    });

    // Configuration output for client applications
    new cdk.CfnOutput(this, 'AmplifyConfig', {
      value: JSON.stringify({
        aws_project_region: this.region,
        aws_cognito_region: this.region,
        aws_user_pools_id: this.userPool.userPoolId,
        aws_user_pools_web_client_id: this.userPoolClient.userPoolClientId,
        aws_cognito_identity_pool_id: this.identityPool.ref,
        aws_appsync_graphqlEndpoint: this.graphqlApi.graphqlUrl,
        aws_appsync_region: this.region,
        aws_appsync_authenticationType: 'AMAZON_COGNITO_USER_POOLS',
        aws_content_delivery_bucket: this.storageBucket.bucketName,
        aws_content_delivery_bucket_region: this.region,
        aws_user_files_s3_bucket: this.storageBucket.bucketName,
        aws_user_files_s3_bucket_region: this.region,
      }, null, 2),
      description: 'Amplify configuration for client applications',
    });
  }
}