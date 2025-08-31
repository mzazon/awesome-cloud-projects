#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Properties for the Enterprise Identity Federation Stack
 */
interface EnterpriseIdentityFederationProps extends cdk.StackProps {
  /** The enterprise SAML identity provider metadata URL */
  readonly enterpriseIdpMetadataUrl?: string;
  /** OAuth callback URLs for AgentCore integration */
  readonly oauthCallbackUrls?: string[];
  /** Authorized email domains for AI agent access */
  readonly authorizedEmailDomains?: string[];
}

/**
 * Enterprise Identity Federation with Bedrock AgentCore Stack
 * 
 * This stack implements a comprehensive enterprise identity federation system using
 * Bedrock AgentCore Identity as the foundation for AI agent management, integrated
 * with Cognito User Pools for SAML federation with corporate identity providers.
 */
class EnterpriseIdentityFederationStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly authenticationHandler: lambda.Function;
  public readonly agentCoreRole: iam.Role;
  public readonly integrationConfig: ssm.StringParameter;

  constructor(scope: Construct, id: string, props?: EnterpriseIdentityFederationProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-6);

    // Create Cognito User Pool for Enterprise Federation
    this.userPool = new cognito.UserPool(this, 'EnterpriseUserPool', {
      userPoolName: `enterprise-ai-agents-${uniqueSuffix}`,
      selfSignUpEnabled: false,
      signInAliases: {
        email: true,
      },
      passwordPolicy: {
        minLength: 12,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
      mfa: cognito.Mfa.OPTIONAL,
      mfaSecondFactor: {
        sms: true,
        otp: true,
      },
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For development - use RETAIN in production
    });

    // Add tags to User Pool
    cdk.Tags.of(this.userPool).add('Environment', 'Production');
    cdk.Tags.of(this.userPool).add('Purpose', 'Enterprise-AI-Identity');
    cdk.Tags.of(this.userPool).add('Project', 'BedrockAgentCore');

    // Create IAM role for Lambda authentication handler
    const lambdaRole = new iam.Role(this, 'AuthHandlerRole', {
      roleName: `agent-auth-handler-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        CognitoAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cognito-idp:AdminGetUser',
                'cognito-idp:AdminUpdateUserAttributes',
                'cognito-idp:ListUsers',
              ],
              resources: [this.userPool.userPoolArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ssm:GetParameter',
                'ssm:GetParameters',
              ],
              resources: [
                `arn:aws:ssm:${this.region}:${this.account}:parameter/enterprise/agentcore/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for custom authentication flow
    this.authenticationHandler = new lambda.Function(this, 'AuthenticationHandler', {
      functionName: `agent-auth-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from typing import Dict, Any

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Custom authentication handler for enterprise AI agent identity management.
    Validates enterprise user context and determines agent access permissions.
    """
    try:
        trigger_source = event.get('triggerSource')
        user_attributes = event.get('request', {}).get('userAttributes', {})
        
        logger.info(f"Processing trigger: {trigger_source}")
        logger.info(f"User attributes: {json.dumps(user_attributes, default=str)}")
        
        if trigger_source == 'PostAuthentication_Authentication':
            # Process successful enterprise authentication
            email = user_attributes.get('email', '')
            department = user_attributes.get('custom:department', 'general')
            
            # Determine agent access based on department
            agent_permissions = determine_agent_permissions(department)
            
            # Store user session context for AgentCore access
            response = event
            response['response'] = {
                'agentPermissions': agent_permissions,
                'sessionDuration': 3600  # 1 hour session
            }
            
            logger.info(f"Authentication successful for {email} with permissions: {agent_permissions}")
            return response
            
        elif trigger_source == 'PreAuthentication_Authentication':
            # Validate user eligibility for AI agent access
            email = user_attributes.get('email', '')
            
            # Check if user is authorized for AI agent management
            if not is_authorized_for_ai_agents(email):
                raise Exception("User not authorized for AI agent access")
            
            return event
            
        return event
        
    except Exception as e:
        logger.error(f"Authentication error: {str(e)}")
        raise e

def determine_agent_permissions(department: str) -> Dict[str, Any]:
    """Determine AI agent access permissions based on user department."""
    permission_map = {
        'engineering': {
            'canCreateAgents': True,
            'canDeleteAgents': True,
            'maxAgents': 10,
            'allowedServices': ['bedrock', 's3', 'lambda']
        },
        'security': {
            'canCreateAgents': True,
            'canDeleteAgents': True,
            'maxAgents': 5,
            'allowedServices': ['bedrock', 'iam', 'cloudtrail']
        },
        'general': {
            'canCreateAgents': False,
            'canDeleteAgents': False,
            'maxAgents': 2,
            'allowedServices': ['bedrock']
        }
    }
    
    return permission_map.get(department, permission_map['general'])

def is_authorized_for_ai_agents(email: str) -> bool:
    """Check if user is authorized for AI agent management."""
    # Implement your authorization logic here
    # This could check against DynamoDB, external APIs, etc.
    authorized_domains = ['@company.com', '@enterprise.org']
    return any(domain in email for domain in authorized_domains)
      `),
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      environment: {
        USER_POOL_ID: this.userPool.userPoolId,
        AGENTCORE_IDENTITY_NAME: `enterprise-agent-${uniqueSuffix}`,
      },
      role: lambdaRole,
      logRetention: logs.RetentionDays.ONE_WEEK,
    });

    // Grant Cognito permission to invoke Lambda
    this.authenticationHandler.addPermission('CognitoInvokePermission', {
      principal: new iam.ServicePrincipal('cognito-idp.amazonaws.com'),
      sourceArn: this.userPool.userPoolArn,
    });

    // Configure Lambda triggers in Cognito User Pool
    this.userPool.addTrigger(cognito.UserPoolOperation.PRE_AUTHENTICATION, this.authenticationHandler);
    this.userPool.addTrigger(cognito.UserPoolOperation.POST_AUTHENTICATION, this.authenticationHandler);
    this.userPool.addTrigger(cognito.UserPoolOperation.CUSTOM_MESSAGE, this.authenticationHandler);

    // Create SAML Identity Provider (if metadata URL is provided)
    if (props?.enterpriseIdpMetadataUrl) {
      new cognito.UserPoolIdentityProviderSaml(this, 'EnterpriseIdP', {
        userPool: this.userPool,
        name: 'EnterpriseSSO',
        metadataUrl: props.enterpriseIdpMetadataUrl,
        attributeMapping: {
          email: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'),
          givenName: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname'),
          familyName: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname'),
          custom: {
            department: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/department'),
          },
        },
      });
    }

    // Create IAM policies for AgentCore service access
    const agentCoreAccessPolicy = new iam.ManagedPolicy(this, 'AgentCoreAccessPolicy', {
      managedPolicyName: `AgentCoreAccessPolicy-${uniqueSuffix}`,
      description: 'Access policy for Bedrock AgentCore AI agents',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'bedrock:InvokeModel',
            'bedrock:InvokeModelWithResponseStream',
            'bedrock:ListFoundationModels',
          ],
          resources: ['*'],
          conditions: {
            StringEquals: {
              'aws:RequestedRegion': this.region,
            },
          },
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:PutObject',
          ],
          resources: ['arn:aws:s3:::enterprise-ai-data-*/*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'logs:CreateLogGroup',
            'logs:CreateLogStream',
            'logs:PutLogEvents',
          ],
          resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
        }),
      ],
    });

    // Create IAM role for AI agents
    this.agentCoreRole = new iam.Role(this, 'AgentCoreExecutionRole', {
      roleName: `AgentCoreExecutionRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('bedrock-agentcore.amazonaws.com'),
      managedPolicies: [agentCoreAccessPolicy],
      assumeRolePolicy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('bedrock-agentcore.amazonaws.com')],
            actions: ['sts:AssumeRole'],
            conditions: {
              StringEquals: {
                'aws:SourceAccount': this.account,
              },
            },
          }),
        ],
      }),
    });

    // Create User Pool App Client for OAuth integration
    this.userPoolClient = new cognito.UserPoolClient(this, 'AgentCoreClient', {
      userPool: this.userPool,
      userPoolClientName: 'AgentCore-Enterprise-Client',
      generateSecret: true,
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
        ...(props?.enterpriseIdpMetadataUrl ? [cognito.UserPoolClientIdentityProvider.custom('EnterpriseSSO')] : []),
      ],
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
          implicitCodeGrant: true,
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
          cognito.OAuthScope.COGNITO_ADMIN,
        ],
        callbackUrls: props?.oauthCallbackUrls || ['https://your-app.company.com/oauth/callback'],
        logoutUrls: ['https://your-app.company.com/logout'],
      },
      authFlows: {
        userPassword: true,
        userSrp: true,
      },
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
    });

    // Create integration configuration parameter
    const integrationConfig = {
      enterpriseIntegration: {
        cognitoUserPool: this.userPool.userPoolId,
        agentCoreIdentity: `arn:aws:bedrock-agentcore:${this.region}:${this.account}:workload-identity/enterprise-agent-${uniqueSuffix}`,
        authenticationFlow: 'enterprise-saml-oauth',
        permissionMapping: {
          engineering: {
            maxAgents: 10,
            allowedActions: ['create', 'read', 'update', 'delete'],
            resourceAccess: ['bedrock', 's3', 'lambda'],
          },
          security: {
            maxAgents: 5,
            allowedActions: ['create', 'read', 'update', 'delete', 'audit'],
            resourceAccess: ['bedrock', 'iam', 'cloudtrail'],
          },
          general: {
            maxAgents: 2,
            allowedActions: ['read'],
            resourceAccess: ['bedrock'],
          },
        },
      },
    };

    this.integrationConfig = new ssm.StringParameter(this, 'IntegrationConfig', {
      parameterName: '/enterprise/agentcore/integration-config',
      stringValue: JSON.stringify(integrationConfig, null, 2),
      description: 'Enterprise AI agent integration configuration',
      tier: ssm.ParameterTier.STANDARD,
    });

    // Add tags to integration configuration
    cdk.Tags.of(this.integrationConfig).add('Environment', 'Production');
    cdk.Tags.of(this.integrationConfig).add('Purpose', 'AgentCore-Integration');

    // Create outputs for important resources
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID for enterprise identity federation',
      exportName: `${this.stackName}-UserPoolId`,
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID for OAuth flows',
      exportName: `${this.stackName}-UserPoolClientId`,
    });

    new cdk.CfnOutput(this, 'AuthenticationHandlerArn', {
      value: this.authenticationHandler.functionArn,
      description: 'Lambda function ARN for custom authentication flow',
      exportName: `${this.stackName}-AuthHandlerArn`,
    });

    new cdk.CfnOutput(this, 'AgentCoreRoleArn', {
      value: this.agentCoreRole.roleArn,
      description: 'IAM role ARN for Bedrock AgentCore AI agents',
      exportName: `${this.stackName}-AgentCoreRoleArn`,
    });

    new cdk.CfnOutput(this, 'IntegrationConfigParameter', {
      value: this.integrationConfig.parameterName,
      description: 'SSM parameter name for integration configuration',
      exportName: `${this.stackName}-IntegrationConfig`,
    });

    // Output instructions for Bedrock AgentCore workload identity creation
    new cdk.CfnOutput(this, 'AgentCoreWorkloadIdentityCommand', {
      value: `aws bedrock-agentcore-control create-workload-identity --name enterprise-agent-${uniqueSuffix} --allowed-resource-oauth2-return-urls ${JSON.stringify(props?.oauthCallbackUrls || ['https://your-app.company.com/oauth/callback'])}`,
      description: 'AWS CLI command to create Bedrock AgentCore workload identity',
    });
  }
}

/**
 * CDK Application for Enterprise Identity Federation
 */
class EnterpriseIdentityFederationApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from context or environment variables
    const enterpriseIdpMetadataUrl = this.node.tryGetContext('enterpriseIdpMetadataUrl') || 
                                   process.env.ENTERPRISE_IDP_METADATA_URL;
    
    const oauthCallbackUrls = this.node.tryGetContext('oauthCallbackUrls') || 
                            (process.env.OAUTH_CALLBACK_URLS ? process.env.OAUTH_CALLBACK_URLS.split(',') : undefined);

    const authorizedEmailDomains = this.node.tryGetContext('authorizedEmailDomains') || 
                                 (process.env.AUTHORIZED_EMAIL_DOMAINS ? process.env.AUTHORIZED_EMAIL_DOMAINS.split(',') : undefined);

    // Create the stack
    new EnterpriseIdentityFederationStack(this, 'EnterpriseIdentityFederationStack', {
      description: 'Enterprise Identity Federation with Bedrock AgentCore for secure AI agent management',
      env: {
        account: process.env.CDK_DEFAULT_ACCOUNT,
        region: process.env.CDK_DEFAULT_REGION,
      },
      enterpriseIdpMetadataUrl,
      oauthCallbackUrls,
      authorizedEmailDomains,
      tags: {
        Project: 'EnterpriseIdentityFederation',
        Environment: 'Production',
        Purpose: 'AI-Agent-Management',
        Owner: 'Enterprise-Security-Team',
      },
    });
  }
}

// Create and run the CDK application
new EnterpriseIdentityFederationApp();