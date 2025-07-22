#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as amplify from 'aws-cdk-lib/aws-amplify';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ssm from 'aws-cdk-lib/aws-ssm';

/**
 * Stack for Enterprise Authentication with Amplify
 * 
 * This stack creates:
 * - Amazon Cognito User Pool with federation support
 * - SAML Identity Provider configuration
 * - Cognito User Pool Domain
 * - AWS Amplify application with authentication
 * - IAM roles for Amplify service
 * - SSM parameters for configuration values
 */
export class EnterpriseAuthenticationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);

    // === COGNITO USER POOL ===
    
    // Create Cognito User Pool for enterprise authentication
    const userPool = new cognito.UserPool(this, 'EnterpriseUserPool', {
      userPoolName: `EnterprisePool-${uniqueSuffix}`,
      // Configure sign-in options
      signInAliases: {
        username: true,
        email: true,
      },
      // Self sign-up configuration
      selfSignUpEnabled: true,
      userVerification: {
        emailSubject: 'Verify your email for Enterprise App',
        emailBody: 'Hello, Your verification code is {####}',
        emailStyle: cognito.VerificationEmailStyle.CODE,
      },
      // Password policy for direct Cognito users
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
      },
      // Account recovery settings
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      // Standard attributes required for enterprise integration
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
      // Enable advanced security features
      advancedSecurityMode: cognito.AdvancedSecurityMode.ENFORCED,
      // Remove default Cognito messages for cleaner UX
      deviceTracking: {
        challengeRequiredOnNewDevice: true,
        deviceOnlyRememberedOnUserPrompt: false,
      },
      // Deletion protection for production environments
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Change to RETAIN for production
    });

    // === COGNITO USER POOL DOMAIN ===
    
    // Create a domain for hosted authentication UI
    const cognitoDomain = new cognito.UserPoolDomain(this, 'EnterpriseAuthDomain', {
      userPool: userPool,
      cognitoDomain: {
        domainPrefix: `enterprise-auth-${uniqueSuffix}`,
      },
    });

    // === USER POOL CLIENT (APP CLIENT) ===
    
    // Create User Pool Client for web applications
    const userPoolClient = new cognito.UserPoolClient(this, 'EnterpriseAppClient', {
      userPool: userPool,
      userPoolClientName: `EnterpriseAppClient-${uniqueSuffix}`,
      // OAuth flows for federation
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE,
        ],
        callbackUrls: [
          'http://localhost:3000/auth/callback',
          'https://localhost:3000/auth/callback',
        ],
        logoutUrls: [
          'http://localhost:3000/auth/logout',
          'https://localhost:3000/auth/logout',
        ],
      },
      // Supported identity providers (will include SAML provider)
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO,
      ],
      // Security settings
      generateSecret: false, // Web clients don't use secrets
      preventUserExistenceErrors: true,
      // Token validity periods
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      // Enable token revocation
      enableTokenRevocation: true,
    });

    // === SAML IDENTITY PROVIDER ===
    
    // Create SAML Identity Provider
    // Note: In production, replace the metadata URL with your actual IdP metadata
    const samlProvider = new cognito.UserPoolIdentityProviderSaml(this, 'EnterpriseADProvider', {
      userPool: userPool,
      name: 'EnterpriseAD',
      // Metadata configuration - replace with your IdP metadata URL
      metadata: cognito.UserPoolIdentityProviderSamlMetadata.url(
        // Placeholder URL - replace with your actual SAML metadata URL
        'https://your-idp.example.com/metadata'
      ),
      // Alternative: Use file-based metadata
      // metadata: cognito.UserPoolIdentityProviderSamlMetadata.file('path/to/metadata.xml'),
      
      // Attribute mapping from SAML attributes to Cognito attributes
      attributeMapping: {
        email: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress'),
        givenName: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/givenname'),
        familyName: cognito.ProviderAttribute.other('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/surname'),
      },
      // IdP identifiers
      idpIdentifiers: ['EnterpriseAD'],
    });

    // Update the User Pool Client to include the SAML provider
    const cfnUserPoolClient = userPoolClient.node.defaultChild as cognito.CfnUserPoolClient;
    cfnUserPoolClient.supportedIdentityProviders = [
      'COGNITO',
      samlProvider.providerName,
    ];

    // Add dependency to ensure SAML provider is created first
    userPoolClient.node.addDependency(samlProvider);

    // === AMPLIFY APPLICATION ===
    
    // Create IAM role for Amplify service
    const amplifyRole = new iam.Role(this, 'AmplifyServiceRole', {
      roleName: `AmplifyServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('amplify.amazonaws.com'),
      description: 'Service role for AWS Amplify to access other AWS services',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AdministratorAccess-Amplify'),
      ],
      // Additional permissions for Cognito integration
      inlinePolicies: {
        CognitoAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cognito-idp:DescribeUserPool',
                'cognito-idp:DescribeUserPoolClient',
                'cognito-idp:ListUserPools',
                'cognito-idp:ListUserPoolClients',
              ],
              resources: [userPool.userPoolArn],
            }),
          ],
        }),
      },
    });

    // Create Amplify application
    const amplifyApp = new amplify.App(this, 'EnterpriseAuthApp', {
      appName: `enterprise-auth-app-${uniqueSuffix}`,
      description: 'Enterprise Authentication Demo Application with Amplify and Cognito',
      role: amplifyRole,
      // Environment variables for the Amplify app
      environmentVariables: {
        REACT_APP_AWS_REGION: this.region,
        REACT_APP_USER_POOL_ID: userPool.userPoolId,
        REACT_APP_USER_POOL_WEB_CLIENT_ID: userPoolClient.userPoolClientId,
        REACT_APP_OAUTH_DOMAIN: cognitoDomain.domainName,
        // Custom domain will be set after domain creation
        REACT_APP_COGNITO_DOMAIN: `${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com`,
      },
      // Custom build settings for React application
      buildSpec: cdk.aws_amplify.BuildSpec.fromObjectToYaml({
        version: '1.0',
        frontend: {
          phases: {
            preBuild: {
              commands: [
                'npm ci',
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
      }),
    });

    // Create main branch for the application
    const mainBranch = amplifyApp.addBranch('main', {
      branchName: 'main',
      description: 'Main branch for enterprise authentication app',
      // Auto-build configuration
      autoBuild: true,
      // Environment variables specific to this branch
      environmentVariables: {
        AMPLIFY_BRANCH: 'main',
      },
    });

    // === SSM PARAMETERS FOR EASY ACCESS ===
    
    // Store configuration values in Systems Manager Parameter Store
    new ssm.StringParameter(this, 'UserPoolIdParameter', {
      parameterName: `/enterprise-auth/${uniqueSuffix}/user-pool-id`,
      stringValue: userPool.userPoolId,
      description: 'Cognito User Pool ID for enterprise authentication',
    });

    new ssm.StringParameter(this, 'UserPoolClientIdParameter', {
      parameterName: `/enterprise-auth/${uniqueSuffix}/user-pool-client-id`,
      stringValue: userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID for enterprise authentication',
    });

    new ssm.StringParameter(this, 'CognitoDomainParameter', {
      parameterName: `/enterprise-auth/${uniqueSuffix}/cognito-domain`,
      stringValue: `${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com`,
      description: 'Cognito hosted UI domain for enterprise authentication',
    });

    new ssm.StringParameter(this, 'AmplifyAppIdParameter', {
      parameterName: `/enterprise-auth/${uniqueSuffix}/amplify-app-id`,
      stringValue: amplifyApp.appId,
      description: 'Amplify Application ID for enterprise authentication',
    });

    // === OUTPUTS ===
    
    // CloudFormation outputs for easy reference
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

    new cdk.CfnOutput(this, 'CognitoDomain', {
      value: `${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com`,
      description: 'Cognito hosted UI domain',
      exportName: `${this.stackName}-CognitoDomain`,
    });

    new cdk.CfnOutput(this, 'AmplifyAppId', {
      value: amplifyApp.appId,
      description: 'Amplify Application ID',
      exportName: `${this.stackName}-AmplifyAppId`,
    });

    new cdk.CfnOutput(this, 'AmplifyAppUrl', {
      value: `https://main.${amplifyApp.appId}.amplifyapp.com`,
      description: 'Amplify Application URL',
      exportName: `${this.stackName}-AmplifyAppUrl`,
    });

    new cdk.CfnOutput(this, 'SAMLProviderName', {
      value: samlProvider.providerName,
      description: 'SAML Identity Provider Name',
      exportName: `${this.stackName}-SAMLProviderName`,
    });

    // Configuration details for Identity Provider setup
    new cdk.CfnOutput(this, 'SAMLEntityId', {
      value: `urn:amazon:cognito:sp:${userPool.userPoolId}`,
      description: 'SAML Entity ID for Identity Provider configuration',
      exportName: `${this.stackName}-SAMLEntityId`,
    });

    new cdk.CfnOutput(this, 'SAMLReplyUrl', {
      value: `https://${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com/saml2/idpresponse`,
      description: 'SAML Reply URL for Identity Provider configuration',
      exportName: `${this.stackName}-SAMLReplyUrl`,
    });

    new cdk.CfnOutput(this, 'SAMLSignOnUrl', {
      value: `https://${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com/login?response_type=code&client_id=${userPoolClient.userPoolClientId}&redirect_uri=http://localhost:3000/auth/callback`,
      description: 'SAML Sign-On URL for Identity Provider configuration',
      exportName: `${this.stackName}-SAMLSignOnUrl`,
    });

    // AWS Amplify configuration object for frontend applications
    new cdk.CfnOutput(this, 'AmplifyConfig', {
      value: JSON.stringify({
        Auth: {
          region: this.region,
          userPoolId: userPool.userPoolId,
          userPoolWebClientId: userPoolClient.userPoolClientId,
          oauth: {
            domain: `${cognitoDomain.domainName}.auth.${this.region}.amazoncognito.com`,
            scope: ['openid', 'email', 'profile'],
            redirectSignIn: 'http://localhost:3000/auth/callback',
            redirectSignOut: 'http://localhost:3000/auth/logout',
            responseType: 'code',
          },
        },
      }, null, 2),
      description: 'Complete Amplify configuration object for frontend applications',
    });
  }
}

// === CDK APP INSTANTIATION ===

const app = new cdk.App();

// Create the stack with appropriate naming and configuration
new EnterpriseAuthenticationStack(app, 'EnterpriseAuthenticationStack', {
  description: 'Enterprise Authentication with AWS Amplify and External Identity Providers (uksb-1tupboc45)',
  env: {
    // Use environment variables or default to us-east-1
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  // Stack tags for resource management and cost tracking
  tags: {
    Project: 'EnterpriseAuthentication',
    Environment: 'Development',
    Owner: 'DevOps',
    CostCenter: 'IT',
    Recipe: 'enterprise-authentication-amplify-external-identity-providers',
  },
});

// Synthesize the CloudFormation template
app.synth();