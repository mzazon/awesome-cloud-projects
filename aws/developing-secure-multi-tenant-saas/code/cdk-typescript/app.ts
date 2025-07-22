#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as appsync from 'aws-cdk-lib/aws-appsync';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Multi-Tenant SaaS Application Stack
 * 
 * This CDK stack implements a comprehensive multi-tenant SaaS architecture
 * with fine-grained authorization using AWS Amplify, AppSync, Cognito,
 * DynamoDB, and Lambda functions.
 * 
 * Key Features:
 * - Tenant isolation and data partitioning
 * - Fine-grained authorization with AppSync
 * - Cognito-based authentication with custom claims
 * - Lambda triggers for tenant management
 * - Multi-tenant data model with DynamoDB
 * - Comprehensive monitoring and logging
 */
export class MultiTenantSaaSStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly identityPool: cognito.CfnIdentityPool;
  public readonly graphQLApi: appsync.GraphqlApi;
  public readonly tenantTable: dynamodb.Table;
  public readonly userTable: dynamodb.Table;
  public readonly projectTable: dynamodb.Table;
  public readonly taskTable: dynamodb.Table;
  public readonly tenantResolver: lambda.Function;
  public readonly authTriggers: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create DynamoDB tables for multi-tenant data
    this.createDynamoDBTables();

    // Create Lambda functions for tenant management
    this.createLambdaFunctions();

    // Create Cognito User Pool with multi-tenant support
    this.createCognitoResources();

    // Create AppSync GraphQL API with fine-grained authorization
    this.createAppSyncAPI();

    // Create S3 buckets for tenant-specific storage
    this.createS3Resources();

    // Create monitoring and logging resources
    this.createMonitoringResources();

    // Output important resource information
    this.createOutputs();
  }

  /**
   * Creates DynamoDB tables with tenant-aware partitioning and indexes
   */
  private createDynamoDBTables(): void {
    // Tenant table - stores tenant configuration and settings
    this.tenantTable = new dynamodb.Table(this, 'TenantTable', {
      tableName: 'MultiTenantSaaS-Tenants',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add GSI for subdomain lookups
    this.tenantTable.addGlobalSecondaryIndex({
      indexName: 'SubdomainIndex',
      partitionKey: { name: 'subdomain', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // User table - stores user information with tenant association
    this.userTable = new dynamodb.Table(this, 'UserTable', {
      tableName: 'MultiTenantSaaS-Users',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
    });

    // Add GSI for tenant-based queries
    this.userTable.addGlobalSecondaryIndex({
      indexName: 'byTenant',
      partitionKey: { name: 'tenantId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Add GSI for userId lookups
    this.userTable.addGlobalSecondaryIndex({
      indexName: 'byUserId',
      partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Project table - stores project information with tenant isolation
    this.projectTable = new dynamodb.Table(this, 'ProjectTable', {
      tableName: 'MultiTenantSaaS-Projects',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add GSI for tenant-based project queries
    this.projectTable.addGlobalSecondaryIndex({
      indexName: 'byTenant',
      partitionKey: { name: 'tenantId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Task table - stores task information with project and tenant association
    this.taskTable = new dynamodb.Table(this, 'TaskTable', {
      tableName: 'MultiTenantSaaS-Tasks',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Add GSI for tenant and status-based queries
    this.taskTable.addGlobalSecondaryIndex({
      indexName: 'byTenantAndStatus',
      partitionKey: { name: 'tenantId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'status', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Add GSI for project-based queries
    this.taskTable.addGlobalSecondaryIndex({
      indexName: 'byProject',
      partitionKey: { name: 'projectId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Additional tables for comprehensive SaaS functionality
    
    // Billing information table
    const billingTable = new dynamodb.Table(this, 'BillingTable', {
      tableName: 'MultiTenantSaaS-Billing',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Usage tracking table
    const usageTable = new dynamodb.Table(this, 'UsageTable', {
      tableName: 'MultiTenantSaaS-Usage',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Activity log table for audit trails
    const activityLogTable = new dynamodb.Table(this, 'ActivityLogTable', {
      tableName: 'MultiTenantSaaS-ActivityLogs',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      // Short retention for activity logs to manage costs
      timeToLiveAttribute: 'ttl',
    });

    // Add GSI for tenant-based activity queries
    activityLogTable.addGlobalSecondaryIndex({
      indexName: 'byTenantAndAction',
      partitionKey: { name: 'tenantId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'action', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Add GSI for user-based activity queries
    activityLogTable.addGlobalSecondaryIndex({
      indexName: 'byUser',
      partitionKey: { name: 'userId', type: dynamodb.AttributeType.STRING },
      sortKey: { name: 'createdAt', type: dynamodb.AttributeType.STRING },
      projectionType: dynamodb.ProjectionType.ALL,
    });
  }

  /**
   * Creates Lambda functions for tenant management and authentication triggers
   */
  private createLambdaFunctions(): void {
    // Tenant resolver function for complex tenant operations
    this.tenantResolver = new lambda.Function(this, 'TenantResolverFunction', {
      functionName: 'MultiTenantSaaS-TenantResolver',
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        
        exports.handler = async (event) => {
          console.log('Tenant resolver event:', JSON.stringify(event, null, 2));
          
          const { field, arguments: args, identity } = event;
          
          try {
            switch (field) {
              case 'createTenant':
                return await createTenant(args.input, identity);
              case 'updateTenantSettings':
                return await updateTenantSettings(args.tenantId, args.settings, identity);
              case 'provisionTenantUser':
                return await provisionTenantUser(args.input, identity);
              default:
                throw new Error(\`Unknown field: \${field}\`);
            }
          } catch (error) {
            console.error('Tenant resolver error:', error);
            throw new Error(\`Tenant operation failed: \${error.message}\`);
          }
        };
        
        async function createTenant(input, identity) {
          // Validate super admin permissions
          if (!hasRole(identity, 'SuperAdmins')) {
            throw new Error('Unauthorized: Only super admins can create tenants');
          }
          
          const tenantId = generateTenantId();
          const timestamp = new Date().toISOString();
          
          const tenant = {
            id: tenantId,
            name: input.name,
            domain: input.domain,
            subdomain: input.subdomain,
            status: 'TRIAL',
            plan: input.plan,
            settings: getDefaultTenantSettings(input.plan),
            createdAt: timestamp,
            updatedAt: timestamp
          };
          
          await dynamodb.put({
            TableName: process.env.TENANT_TABLE,
            Item: tenant
          }).promise();
          
          return tenant;
        }
        
        async function updateTenantSettings(tenantId, settingsInput, identity) {
          // Implementation for updating tenant settings
          const tenant = await getTenantById(tenantId);
          if (!tenant) {
            throw new Error('Tenant not found');
          }
          
          const updatedTenant = {
            ...tenant,
            settings: { ...tenant.settings, ...settingsInput },
            updatedAt: new Date().toISOString()
          };
          
          await dynamodb.put({
            TableName: process.env.TENANT_TABLE,
            Item: updatedTenant
          }).promise();
          
          return updatedTenant;
        }
        
        async function provisionTenantUser(input, identity) {
          // Implementation for provisioning tenant users
          console.log('Provisioning user:', input);
          return { message: 'User provisioned successfully' };
        }
        
        function hasRole(identity, role) {
          const groups = identity.groups || [];
          return groups.includes(role);
        }
        
        function generateTenantId() {
          return \`tenant_\${Date.now()}_\${Math.random().toString(36).substr(2, 9)}\`;
        }
        
        function getDefaultTenantSettings(plan) {
          const settingsMap = {
            TRIAL: { maxUsers: 5, maxProjects: 3, maxStorageGB: 1.0 },
            BASIC: { maxUsers: 25, maxProjects: 10, maxStorageGB: 5.0 },
            PROFESSIONAL: { maxUsers: 100, maxProjects: 50, maxStorageGB: 25.0 },
            ENTERPRISE: { maxUsers: 1000, maxProjects: 500, maxStorageGB: 100.0 }
          };
          return settingsMap[plan] || settingsMap.TRIAL;
        }
        
        async function getTenantById(tenantId) {
          const result = await dynamodb.get({
            TableName: process.env.TENANT_TABLE,
            Key: { id: tenantId }
          }).promise();
          return result.Item;
        }
      `),
      environment: {
        TENANT_TABLE: this.tenantTable.tableName,
        USER_TABLE: this.userTable.tableName,
        PROJECT_TABLE: this.projectTable.tableName,
        TASK_TABLE: this.taskTable.tableName,
      },
      timeout: cdk.Duration.minutes(5),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant DynamoDB permissions to tenant resolver
    this.tenantTable.grantReadWriteData(this.tenantResolver);
    this.userTable.grantReadWriteData(this.tenantResolver);
    this.projectTable.grantReadWriteData(this.tenantResolver);
    this.taskTable.grantReadWriteData(this.tenantResolver);

    // Authentication triggers function for Cognito
    this.authTriggers = new lambda.Function(this, 'AuthTriggersFunction', {
      functionName: 'MultiTenantSaaS-AuthTriggers',
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
        const AWS = require('aws-sdk');
        const dynamodb = new AWS.DynamoDB.DocumentClient();
        const cognito = new AWS.CognitoIdentityServiceProvider();
        
        exports.handler = async (event) => {
          console.log('Auth trigger event:', JSON.stringify(event, null, 2));
          
          try {
            switch (event.triggerSource) {
              case 'PreSignUp_SignUp':
              case 'PreSignUp_ExternalProvider':
                return await handlePreSignUp(event);
              case 'PostConfirmation_ConfirmSignUp':
              case 'PostConfirmation_ConfirmForgotPassword':
                return await handlePostConfirmation(event);
              case 'PreAuthentication_Authentication':
                return await handlePreAuthentication(event);
              case 'TokenGeneration_HostedAuth':
              case 'TokenGeneration_Authentication':
              case 'TokenGeneration_NewPasswordChallenge':
              case 'TokenGeneration_AuthenticateDevice':
                return await handleTokenGeneration(event);
              default:
                console.log('Unhandled trigger source:', event.triggerSource);
                return event;
            }
          } catch (error) {
            console.error('Auth trigger error:', error);
            throw error;
          }
        };
        
        async function handlePreSignUp(event) {
          const { userAttributes } = event.request;
          const tenantId = userAttributes['custom:tenant_id'];
          
          if (tenantId) {
            const tenant = await getTenantById(tenantId);
            if (!tenant || tenant.status !== 'ACTIVE') {
              throw new Error('Tenant is not active or does not exist');
            }
            
            const userCount = await getUserCountForTenant(tenantId);
            if (userCount >= tenant.settings.maxUsers) {
              throw new Error('User limit exceeded for this tenant');
            }
          }
          
          return event;
        }
        
        async function handlePostConfirmation(event) {
          const { userName, userAttributes } = event.request;
          const tenantId = userAttributes['custom:tenant_id'];
          
          if (tenantId) {
            const user = {
              id: generateUserId(),
              userId: userName,
              tenantId: tenantId,
              email: userAttributes.email,
              firstName: userAttributes.given_name || '',
              lastName: userAttributes.family_name || '',
              role: 'VIEWER',
              permissions: ['tasks:read'],
              isActive: true,
              createdAt: new Date().toISOString(),
              updatedAt: new Date().toISOString()
            };
            
            await dynamodb.put({
              TableName: process.env.USER_TABLE,
              Item: user
            }).promise();
          }
          
          return event;
        }
        
        async function handlePreAuthentication(event) {
          const { userName, userAttributes } = event.request;
          const tenantId = userAttributes['custom:tenant_id'];
          
          if (tenantId) {
            const tenant = await getTenantById(tenantId);
            if (!tenant) {
              throw new Error('Tenant not found');
            }
            
            if (tenant.status === 'SUSPENDED') {
              throw new Error('Tenant account is suspended');
            }
            
            if (tenant.status === 'EXPIRED') {
              throw new Error('Tenant subscription has expired');
            }
          }
          
          return event;
        }
        
        async function handleTokenGeneration(event) {
          const { userName, userAttributes } = event.request;
          const tenantId = userAttributes['custom:tenant_id'];
          
          if (tenantId) {
            const user = await getUserByUserId(userName);
            const tenant = await getTenantById(tenantId);
            
            if (user && tenant) {
              event.response = {
                claimsOverrideDetails: {
                  claimsToAddOrOverride: {
                    'custom:tenant_id': tenantId,
                    'custom:tenant_name': tenant.name,
                    'custom:tenant_plan': tenant.plan,
                    'custom:user_role': user.role,
                    'custom:permissions': user.permissions.join(','),
                    'custom:features': tenant.settings.allowedFeatures?.join(',') || '',
                    'custom:last_login': new Date().toISOString()
                  }
                }
              };
            }
          }
          
          return event;
        }
        
        function generateUserId() {
          return \`user_\${Date.now()}_\${Math.random().toString(36).substr(2, 9)}\`;
        }
        
        async function getTenantById(tenantId) {
          const result = await dynamodb.get({
            TableName: process.env.TENANT_TABLE,
            Key: { id: tenantId }
          }).promise();
          return result.Item;
        }
        
        async function getUserByUserId(userId) {
          const result = await dynamodb.scan({
            TableName: process.env.USER_TABLE,
            FilterExpression: 'userId = :userId',
            ExpressionAttributeValues: { ':userId': userId }
          }).promise();
          return result.Items.length > 0 ? result.Items[0] : null;
        }
        
        async function getUserCountForTenant(tenantId) {
          const result = await dynamodb.query({
            TableName: process.env.USER_TABLE,
            IndexName: 'byTenant',
            KeyConditionExpression: 'tenantId = :tenantId',
            ExpressionAttributeValues: { ':tenantId': tenantId },
            Select: 'COUNT'
          }).promise();
          return result.Count;
        }
      `),
      environment: {
        TENANT_TABLE: this.tenantTable.tableName,
        USER_TABLE: this.userTable.tableName,
      },
      timeout: cdk.Duration.minutes(2),
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant DynamoDB permissions to auth triggers
    this.tenantTable.grantReadData(this.authTriggers);
    this.userTable.grantReadWriteData(this.authTriggers);

    // Grant Cognito permissions to auth triggers
    this.authTriggers.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'cognito-idp:AdminAddUserToGroup',
        'cognito-idp:AdminRemoveUserFromGroup',
        'cognito-idp:AdminListGroupsForUser',
        'cognito-idp:ListUsersInGroup',
        'cognito-idp:AdminGetUser',
        'cognito-idp:AdminUpdateUserAttributes',
      ],
      resources: ['*'],
    }));
  }

  /**
   * Creates Cognito User Pool with multi-tenant support and Lambda triggers
   */
  private createCognitoResources(): void {
    // Create User Pool with advanced security features
    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: 'MultiTenantSaaS-UserPool',
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
        givenName: {
          required: true,
          mutable: true,
        },
        familyName: {
          required: true,
          mutable: true,
        },
      },
      customAttributes: {
        tenant_id: new cognito.StringAttribute({ mutable: true }),
        user_role: new cognito.StringAttribute({ mutable: true }),
        permissions: new cognito.StringAttribute({ mutable: true }),
      },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      lambdaTriggers: {
        preSignUp: this.authTriggers,
        postConfirmation: this.authTriggers,
        preAuthentication: this.authTriggers,
        preTokenGeneration: this.authTriggers,
      },
      deviceTracking: {
        challengeRequiredOnNewDevice: true,
        deviceOnlyRememberedOnUserPrompt: false,
      },
      advancedSecurityMode: cognito.AdvancedSecurityMode.ENFORCED,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create User Pool Client
    this.userPoolClient = new cognito.UserPoolClient(this, 'UserPoolClient', {
      userPool: this.userPool,
      userPoolClientName: 'MultiTenantSaaS-WebClient',
      generateSecret: false,
      authFlows: {
        userSrp: true,
        userPassword: false,
        adminUserPassword: true,
        custom: false,
      },
      preventUserExistenceErrors: true,
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
      ],
      readAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          givenName: true,
          familyName: true,
        })
        .withCustomAttributes('tenant_id', 'user_role', 'permissions'),
      writeAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          givenName: true,
          familyName: true,
        })
        .withCustomAttributes('tenant_id', 'user_role', 'permissions'),
      tokenValidityDuration: {
        accessToken: cdk.Duration.hours(1),
        idToken: cdk.Duration.hours(1),
        refreshToken: cdk.Duration.days(30),
      },
    });

    // Create Identity Pool for federated identities
    this.identityPool = new cognito.CfnIdentityPool(this, 'IdentityPool', {
      identityPoolName: 'MultiTenantSaaS-IdentityPool',
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
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSAppSyncInvokeFullAccess'),
      ],
    });

    // Attach identity pool roles
    new cognito.CfnIdentityPoolRoleAttachment(this, 'IdentityPoolRoleAttachment', {
      identityPoolId: this.identityPool.ref,
      roles: {
        authenticated: authenticatedRole.roleArn,
      },
    });

    // Create Cognito groups for different user roles
    const superAdminGroup = new cognito.CfnUserPoolGroup(this, 'SuperAdminGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'SuperAdmins',
      description: 'Super administrators with platform-wide access',
      precedence: 1,
    });

    const tenantAdminGroup = new cognito.CfnUserPoolGroup(this, 'TenantAdminGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'TenantAdmins',
      description: 'Tenant administrators with tenant-specific access',
      precedence: 2,
    });

    const projectManagerGroup = new cognito.CfnUserPoolGroup(this, 'ProjectManagerGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'ProjectManagers',
      description: 'Project managers with project management access',
      precedence: 3,
    });

    const developerGroup = new cognito.CfnUserPoolGroup(this, 'DeveloperGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'Developers',
      description: 'Developers with limited access to projects and tasks',
      precedence: 4,
    });
  }

  /**
   * Creates AppSync GraphQL API with comprehensive multi-tenant schema and authorization
   */
  private createAppSyncAPI(): void {
    // Create GraphQL API
    this.graphQLApi = new appsync.GraphqlApi(this, 'GraphQLApi', {
      name: 'MultiTenantSaaS-API',
      schema: appsync.SchemaFile.fromAsset('./schema.graphql'),
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
      logConfig: {
        level: appsync.FieldLogLevel.ALL,
        retention: logs.RetentionDays.ONE_WEEK,
      },
      xrayEnabled: true,
    });

    // Create data sources
    const tenantDataSource = this.graphQLApi.addDynamoDbDataSource(
      'TenantDataSource',
      this.tenantTable
    );

    const userDataSource = this.graphQLApi.addDynamoDbDataSource(
      'UserDataSource',
      this.userTable
    );

    const projectDataSource = this.graphQLApi.addDynamoDbDataSource(
      'ProjectDataSource',
      this.projectTable
    );

    const taskDataSource = this.graphQLApi.addDynamoDbDataSource(
      'TaskDataSource',
      this.taskTable
    );

    const tenantResolverDataSource = this.graphQLApi.addLambdaDataSource(
      'TenantResolverDataSource',
      this.tenantResolver
    );

    // Create resolvers for tenant operations
    tenantResolverDataSource.createResolver('CreateTenantResolver', {
      typeName: 'Mutation',
      fieldName: 'createTenant',
    });

    tenantResolverDataSource.createResolver('UpdateTenantSettingsResolver', {
      typeName: 'Mutation',
      fieldName: 'updateTenantSettings',
    });

    tenantResolverDataSource.createResolver('ProvisionTenantUserResolver', {
      typeName: 'Mutation',
      fieldName: 'provisionTenantUser',
    });

    // Create basic CRUD resolvers for main entities
    tenantDataSource.createResolver('GetTenantResolver', {
      typeName: 'Query',
      fieldName: 'getTenant',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    tenantDataSource.createResolver('ListTenantsResolver', {
      typeName: 'Query',
      fieldName: 'listTenants',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbScanTable(),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    userDataSource.createResolver('GetUserResolver', {
      typeName: 'Query',
      fieldName: 'getUser',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    userDataSource.createResolver('ListUsersByTenantResolver', {
      typeName: 'Query',
      fieldName: 'listUsersByTenant',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbQuery('byTenant', 'tenantId'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    projectDataSource.createResolver('GetProjectResolver', {
      typeName: 'Query',
      fieldName: 'getProject',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    projectDataSource.createResolver('ListProjectsByTenantResolver', {
      typeName: 'Query',
      fieldName: 'listProjectsByTenant',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbQuery('byTenant', 'tenantId'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    taskDataSource.createResolver('GetTaskResolver', {
      typeName: 'Query',
      fieldName: 'getTask',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbGetItem('id', 'id'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    taskDataSource.createResolver('ListTasksByProjectResolver', {
      typeName: 'Query',
      fieldName: 'listTasksByProject',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbQuery('byProject', 'projectId'),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultList(),
    });

    // Create mutation resolvers
    tenantDataSource.createResolver('CreateTenantMutationResolver', {
      typeName: 'Mutation',
      fieldName: 'createTenantDirect',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    userDataSource.createResolver('CreateUserResolver', {
      typeName: 'Mutation',
      fieldName: 'createUser',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    projectDataSource.createResolver('CreateProjectResolver', {
      typeName: 'Mutation',
      fieldName: 'createProject',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });

    taskDataSource.createResolver('CreateTaskResolver', {
      typeName: 'Mutation',
      fieldName: 'createTask',
      requestMappingTemplate: appsync.MappingTemplate.dynamoDbPutItem(
        appsync.PrimaryKey.partition('id').auto(),
        appsync.Values.projecting('input')
      ),
      responseMappingTemplate: appsync.MappingTemplate.dynamoDbResultItem(),
    });
  }

  /**
   * Creates S3 buckets for tenant-specific storage with proper isolation
   */
  private createS3Resources(): void {
    // Main storage bucket for tenant files
    const tenantStorageBucket = new s3.Bucket(this, 'TenantStorageBucket', {
      bucketName: `multi-tenant-saas-storage-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
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
    });

    // Shared assets bucket for common resources
    const sharedAssetsBucket = new s3.Bucket(this, 'SharedAssetsBucket', {
      bucketName: `multi-tenant-saas-shared-${this.account}-${this.region}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Grant appropriate permissions to Lambda functions
    tenantStorageBucket.grantRead(this.tenantResolver);
    sharedAssetsBucket.grantRead(this.tenantResolver);
  }

  /**
   * Creates comprehensive monitoring and logging resources
   */
  private createMonitoringResources(): void {
    // CloudWatch dashboard for multi-tenant metrics
    const dashboard = new cloudwatch.Dashboard(this, 'MultiTenantDashboard', {
      dashboardName: 'MultiTenantSaaS-Operations',
    });

    // Add widgets for key metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'GraphQL API Requests',
        left: [
          this.graphQLApi.metricRequests(),
          this.graphQLApi.metric4XXError(),
          this.graphQLApi.metric5XXError(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Function Invocations',
        left: [
          this.tenantResolver.metricInvocations(),
          this.tenantResolver.metricErrors(),
          this.tenantResolver.metricDuration(),
        ],
        width: 12,
      })
    );

    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'DynamoDB Read/Write Capacity',
        left: [
          this.tenantTable.metricConsumedReadCapacityUnits(),
          this.tenantTable.metricConsumedWriteCapacityUnits(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Cognito User Pool Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Cognito',
            metricName: 'SignInSuccesses',
            dimensionsMap: {
              UserPool: this.userPool.userPoolId,
            },
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Cognito',
            metricName: 'SignInThrottles',
            dimensionsMap: {
              UserPool: this.userPool.userPoolId,
            },
          }),
        ],
        width: 12,
      })
    );

    // Create alarms for critical metrics
    new cloudwatch.Alarm(this, 'HighErrorRateAlarm', {
      alarmName: 'MultiTenantSaaS-HighErrorRate',
      metric: this.graphQLApi.metric4XXError(),
      threshold: 10,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    new cloudwatch.Alarm(this, 'HighLambdaErrorRateAlarm', {
      alarmName: 'MultiTenantSaaS-HighLambdaErrorRate',
      metric: this.tenantResolver.metricErrors(),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Log groups for centralized logging
    new logs.LogGroup(this, 'ApplicationLogGroup', {
      logGroupName: '/aws/multiTenantSaaS/application',
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });
  }

  /**
   * Creates stack outputs for important resource identifiers
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID',
      exportName: 'MultiTenantSaaS-UserPoolId',
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
      exportName: 'MultiTenantSaaS-UserPoolClientId',
    });

    new cdk.CfnOutput(this, 'IdentityPoolId', {
      value: this.identityPool.ref,
      description: 'Cognito Identity Pool ID',
      exportName: 'MultiTenantSaaS-IdentityPoolId',
    });

    new cdk.CfnOutput(this, 'GraphQLApiId', {
      value: this.graphQLApi.apiId,
      description: 'AppSync GraphQL API ID',
      exportName: 'MultiTenantSaaS-GraphQLApiId',
    });

    new cdk.CfnOutput(this, 'GraphQLApiUrl', {
      value: this.graphQLApi.graphqlUrl,
      description: 'AppSync GraphQL API URL',
      exportName: 'MultiTenantSaaS-GraphQLApiUrl',
    });

    new cdk.CfnOutput(this, 'TenantTableName', {
      value: this.tenantTable.tableName,
      description: 'DynamoDB Tenant Table Name',
      exportName: 'MultiTenantSaaS-TenantTableName',
    });

    new cdk.CfnOutput(this, 'UserTableName', {
      value: this.userTable.tableName,
      description: 'DynamoDB User Table Name',
      exportName: 'MultiTenantSaaS-UserTableName',
    });

    new cdk.CfnOutput(this, 'ProjectTableName', {
      value: this.projectTable.tableName,
      description: 'DynamoDB Project Table Name',
      exportName: 'MultiTenantSaaS-ProjectTableName',
    });

    new cdk.CfnOutput(this, 'TaskTableName', {
      value: this.taskTable.tableName,
      description: 'DynamoDB Task Table Name',
      exportName: 'MultiTenantSaaS-TaskTableName',
    });

    new cdk.CfnOutput(this, 'TenantResolverFunctionName', {
      value: this.tenantResolver.functionName,
      description: 'Tenant Resolver Lambda Function Name',
      exportName: 'MultiTenantSaaS-TenantResolverFunctionName',
    });

    new cdk.CfnOutput(this, 'AuthTriggersFunctionName', {
      value: this.authTriggers.functionName,
      description: 'Auth Triggers Lambda Function Name',
      exportName: 'MultiTenantSaaS-AuthTriggersFunctionName',
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS Region',
      exportName: 'MultiTenantSaaS-Region',
    });
  }
}

// Create and deploy the stack
const app = new cdk.App();

new MultiTenantSaaSStack(app, 'MultiTenantSaaSStack', {
  description: 'Multi-Tenant SaaS Application with Amplify and Fine-Grained Authorization',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  tags: {
    Project: 'MultiTenantSaaS',
    Environment: 'Development',
    Owner: 'SaaS-Team',
    CostCenter: 'Platform',
  },
});

app.synth();