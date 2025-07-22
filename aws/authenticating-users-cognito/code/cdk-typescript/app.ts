#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as cognito from 'aws-cdk-lib/aws-cognito';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as ses from 'aws-cdk-lib/aws-ses';
import { Construct } from 'constructs';

/**
 * Interface for stack properties extending the default stack props
 */
interface UserAuthenticationStackProps extends cdk.StackProps {
  /** Environment prefix for resource naming */
  readonly environmentPrefix?: string;
  /** Domain prefix for Cognito hosted UI */
  readonly domainPrefix?: string;
  /** Email address for SES integration */
  readonly fromEmailAddress?: string;
  /** Callback URLs for OAuth flows */
  readonly callbackUrls?: string[];
  /** Logout URLs for OAuth flows */
  readonly logoutUrls?: string[];
}

/**
 * CDK Stack for implementing comprehensive user authentication with Amazon Cognito User Pools
 * 
 * This stack creates a complete authentication solution including:
 * - User Pool with advanced security features
 * - User Pool Client with OAuth configuration
 * - User Groups for role-based access control
 * - Hosted UI domain for ready-to-use authentication interface
 * - IAM roles for SNS integration
 * - Custom attributes for business logic
 */
export class UserAuthenticationStack extends cdk.Stack {
  public readonly userPool: cognito.UserPool;
  public readonly userPoolClient: cognito.UserPoolClient;
  public readonly userPoolDomain: cognito.UserPoolDomain;
  public readonly adminGroup: cognito.CfnUserPoolGroup;
  public readonly customerGroup: cognito.CfnUserPoolGroup;
  public readonly premiumCustomerGroup: cognito.CfnUserPoolGroup;

  constructor(scope: Construct, id: string, props: UserAuthenticationStackProps = {}) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-6);
    const envPrefix = props.environmentPrefix || 'ecommerce';
    
    // Default configuration values
    const domainPrefix = props.domainPrefix || `${envPrefix}-auth-${uniqueSuffix}`;
    const fromEmail = props.fromEmailAddress || 'noreply@example.com';
    const callbackUrls = props.callbackUrls || [
      'https://localhost:3000/callback',
      'https://example.com/callback'
    ];
    const logoutUrls = props.logoutUrls || [
      'https://localhost:3000/logout',
      'https://example.com/logout'
    ];

    // Create IAM role for Cognito to send SMS messages via SNS
    const cognitoSnsRole = new iam.Role(this, 'CognitoSnsRole', {
      roleName: `CognitoSNSRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('cognito-idp.amazonaws.com'),
      description: 'IAM role for Cognito to send SMS messages through Amazon SNS',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSNSFullAccess')
      ]
    });

    // Create User Pool with comprehensive security configuration
    this.userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `${envPrefix}-users-${uniqueSuffix}`,
      
      // Authentication and sign-in configuration
      signInAliases: {
        email: true,
        username: false,
        phone: false
      },
      
      // Auto-verification settings
      autoVerify: {
        email: true,
        phone: false
      },
      
      // Password policy with strong security requirements
      passwordPolicy: {
        minLength: 12,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: true,
        tempPasswordValidity: cdk.Duration.days(1)
      },
      
      // Multi-factor authentication configuration
      mfa: cognito.Mfa.OPTIONAL,
      mfaSecondFactor: {
        sms: true,
        otp: true
      },
      
      // Advanced security features
      advancedSecurityMode: cognito.AdvancedSecurityMode.ENFORCED,
      
      // Device tracking and management
      deviceTracking: {
        challengeRequiredOnNewDevice: true,
        deviceOnlyRememberedOnUserPrompt: false
      },
      
      // User invitation configuration
      selfSignUpEnabled: true,
      userInvitation: {
        emailSubject: 'Welcome to ECommerce - Verify Your Email',
        emailBody: 'Welcome to our platform! Your username is {username} and temporary password is {####}. Please sign in and change your password.',
        smsMessage: 'Welcome! Your username is {username} and temporary password is {####}'
      },
      
      // User verification messages
      userVerification: {
        emailSubject: 'Welcome to ECommerce - Verify Your Email',
        emailBody: 'Please click the link to verify your email: {##Verify Email##}',
        emailStyle: cognito.VerificationEmailStyle.LINK,
        smsMessage: 'Your verification code is {####}'
      },
      
      // Account recovery configuration
      accountRecovery: cognito.AccountRecovery.EMAIL_ONLY,
      
      // SNS configuration for SMS
      smsRole: cognitoSnsRole,
      smsRoleExternalId: `cognito-${uniqueSuffix}`,
      
      // Lambda trigger configuration (can be extended)
      lambdaTriggers: {
        // Add Lambda triggers here if needed for custom flows
      },
      
      // Standard attributes configuration
      standardAttributes: {
        email: {
          required: true,
          mutable: true
        },
        familyName: {
          required: false,
          mutable: true
        },
        givenName: {
          required: false,
          mutable: true
        },
        phoneNumber: {
          required: false,
          mutable: true
        },
        fullname: {
          required: false,
          mutable: true
        }
      },
      
      // Custom attributes for business logic
      customAttributes: {
        'customer_tier': new cognito.StringAttribute({
          minLen: 1,
          maxLen: 20,
          mutable: true
        }),
        'subscription_status': new cognito.StringAttribute({
          minLen: 1,
          maxLen: 50,
          mutable: true
        }),
        'last_login': new cognito.DateTimeAttribute({
          mutable: true
        })
      },
      
      // Deletion protection
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Change to RETAIN for production
      
      // Email configuration (requires verified SES domain in production)
      email: cognito.UserPoolEmail.withSES({
        fromEmail: fromEmail,
        fromName: 'ECommerce Platform',
        replyTo: 'support@example.com',
        sesRegion: this.region
      })
    });

    // Create User Pool Client with OAuth configuration
    this.userPoolClient = new cognito.UserPoolClient(this, 'UserPoolClient', {
      userPool: this.userPool,
      userPoolClientName: `${envPrefix}-web-client-${uniqueSuffix}`,
      
      // Generate client secret for server-side applications
      generateSecret: true,
      
      // Token validity configuration
      accessTokenValidity: cdk.Duration.minutes(60),
      idTokenValidity: cdk.Duration.minutes(60),
      refreshTokenValidity: cdk.Duration.days(30),
      
      // Authentication flows
      authFlows: {
        userSrp: true,
        userPassword: true,
        custom: false,
        adminUserPassword: true
      },
      
      // OAuth configuration
      oAuth: {
        flows: {
          authorizationCodeGrant: true,
          implicitCodeGrant: true,
          clientCredentials: false
        },
        scopes: [
          cognito.OAuthScope.OPENID,
          cognito.OAuthScope.EMAIL,
          cognito.OAuthScope.PROFILE
        ],
        callbackUrls: callbackUrls,
        logoutUrls: logoutUrls
      },
      
      // Attribute read and write permissions
      readAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          emailVerified: true,
          familyName: true,
          givenName: true,
          phoneNumber: true,
          fullname: true
        })
        .withCustomAttributes('customer_tier', 'subscription_status', 'last_login'),
      
      writeAttributes: new cognito.ClientAttributes()
        .withStandardAttributes({
          email: true,
          familyName: true,
          givenName: true,
          phoneNumber: true,
          fullname: true
        })
        .withCustomAttributes('customer_tier', 'subscription_status', 'last_login'),
      
      // Security settings
      preventUserExistenceErrors: true,
      enableTokenRevocation: true,
      authSessionValidity: cdk.Duration.minutes(3),
      
      // Supported identity providers
      supportedIdentityProviders: [
        cognito.UserPoolClientIdentityProvider.COGNITO
      ]
    });

    // Create User Pool Domain for hosted UI
    this.userPoolDomain = new cognito.UserPoolDomain(this, 'UserPoolDomain', {
      userPool: this.userPool,
      cognitoDomain: {
        domainPrefix: domainPrefix
      }
    });

    // Create user groups for role-based access control
    
    // Administrators group - highest precedence
    this.adminGroup = new cognito.CfnUserPoolGroup(this, 'AdministratorsGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'Administrators',
      description: 'Administrator users with full access to the platform',
      precedence: 1
    });

    // Premium Customers group - medium precedence
    this.premiumCustomerGroup = new cognito.CfnUserPoolGroup(this, 'PremiumCustomersGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'PremiumCustomers',
      description: 'Premium customer users with enhanced features and support',
      precedence: 5
    });

    // Regular Customers group - lowest precedence
    this.customerGroup = new cognito.CfnUserPoolGroup(this, 'CustomersGroup', {
      userPoolId: this.userPool.userPoolId,
      groupName: 'Customers',
      description: 'Regular customer users with standard platform access',
      precedence: 10
    });

    // Create test users for immediate validation (optional - remove in production)
    this.createTestUsers(uniqueSuffix);

    // Output important values for application integration
    this.createOutputs(domainPrefix);
  }

  /**
   * Creates test users for validation purposes
   * Remove this method in production environments
   */
  private createTestUsers(uniqueSuffix: string): void {
    // Admin test user
    new cognito.CfnUserPoolUser(this, 'AdminTestUser', {
      userPoolId: this.userPool.userPoolId,
      username: 'admin@example.com',
      userAttributes: [
        { name: 'email', value: 'admin@example.com' },
        { name: 'name', value: 'Admin User' },
        { name: 'given_name', value: 'Admin' },
        { name: 'family_name', value: 'User' },
        { name: 'email_verified', value: 'true' }
      ],
      messageAction: 'SUPPRESS',
      temporaryPassword: 'TempPass123!'
    });

    // Add admin user to Administrators group
    new cognito.CfnUserPoolUserToGroupAttachment(this, 'AdminUserGroupAttachment', {
      userPoolId: this.userPool.userPoolId,
      username: 'admin@example.com',
      groupName: this.adminGroup.groupName!
    });

    // Customer test user
    new cognito.CfnUserPoolUser(this, 'CustomerTestUser', {
      userPoolId: this.userPool.userPoolId,
      username: 'customer@example.com',
      userAttributes: [
        { name: 'email', value: 'customer@example.com' },
        { name: 'name', value: 'Customer User' },
        { name: 'given_name', value: 'Customer' },
        { name: 'family_name', value: 'User' },
        { name: 'email_verified', value: 'true' }
      ],
      messageAction: 'SUPPRESS',
      temporaryPassword: 'TempPass123!'
    });

    // Add customer user to Customers group
    new cognito.CfnUserPoolUserToGroupAttachment(this, 'CustomerUserGroupAttachment', {
      userPoolId: this.userPool.userPoolId,
      username: 'customer@example.com',
      groupName: this.customerGroup.groupName!
    });
  }

  /**
   * Creates CloudFormation outputs for application integration
   */
  private createOutputs(domainPrefix: string): void {
    // User Pool outputs
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: this.userPool.userPoolId,
      description: 'Cognito User Pool ID for application configuration',
      exportName: `${this.stackName}-UserPoolId`
    });

    new cdk.CfnOutput(this, 'UserPoolArn', {
      value: this.userPool.userPoolArn,
      description: 'Cognito User Pool ARN for IAM permissions',
      exportName: `${this.stackName}-UserPoolArn`
    });

    // User Pool Client outputs
    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: this.userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID for application authentication',
      exportName: `${this.stackName}-UserPoolClientId`
    });

    // Hosted UI outputs
    new cdk.CfnOutput(this, 'HostedUIUrl', {
      value: `https://${domainPrefix}.auth.${this.region}.amazoncognito.com`,
      description: 'Cognito Hosted UI base URL for authentication flows',
      exportName: `${this.stackName}-HostedUIUrl`
    });

    new cdk.CfnOutput(this, 'LoginUrl', {
      value: `https://${domainPrefix}.auth.${this.region}.amazoncognito.com/login?client_id=${this.userPoolClient.userPoolClientId}&response_type=code&scope=openid+email+profile&redirect_uri=https://localhost:3000/callback`,
      description: 'Complete login URL for redirecting users to authentication',
      exportName: `${this.stackName}-LoginUrl`
    });

    new cdk.CfnOutput(this, 'LogoutUrl', {
      value: `https://${domainPrefix}.auth.${this.region}.amazoncognito.com/logout?client_id=${this.userPoolClient.userPoolClientId}&logout_uri=https://localhost:3000/logout`,
      description: 'Complete logout URL for user session termination',
      exportName: `${this.stackName}-LogoutUrl`
    });

    // User Groups outputs
    new cdk.CfnOutput(this, 'AdminGroupName', {
      value: this.adminGroup.groupName!,
      description: 'Administrator group name for role-based access control',
      exportName: `${this.stackName}-AdminGroupName`
    });

    new cdk.CfnOutput(this, 'CustomerGroupName', {
      value: this.customerGroup.groupName!,
      description: 'Customer group name for role-based access control',
      exportName: `${this.stackName}-CustomerGroupName`
    });

    new cdk.CfnOutput(this, 'PremiumCustomerGroupName', {
      value: this.premiumCustomerGroup.groupName!,
      description: 'Premium customer group name for role-based access control',
      exportName: `${this.stackName}-PremiumCustomerGroupName`
    });

    // Test user credentials (remove in production)
    new cdk.CfnOutput(this, 'TestAdminCredentials', {
      value: 'Username: admin@example.com, Password: TempPass123!',
      description: 'Test admin user credentials for validation (remove in production)'
    });

    new cdk.CfnOutput(this, 'TestCustomerCredentials', {
      value: 'Username: customer@example.com, Password: TempPass123!',
      description: 'Test customer user credentials for validation (remove in production)'
    });
  }
}

// CDK App instantiation and stack deployment
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || process.env.ENVIRONMENT_PREFIX || 'ecommerce';
const domainPrefix = app.node.tryGetContext('domainPrefix') || process.env.DOMAIN_PREFIX;
const fromEmailAddress = app.node.tryGetContext('fromEmailAddress') || process.env.FROM_EMAIL_ADDRESS;

// Parse callback and logout URLs from context
const callbackUrls = app.node.tryGetContext('callbackUrls')?.split(',') || 
  process.env.CALLBACK_URLS?.split(',') || undefined;
const logoutUrls = app.node.tryGetContext('logoutUrls')?.split(',') || 
  process.env.LOGOUT_URLS?.split(',') || undefined;

// Create the stack with configuration
new UserAuthenticationStack(app, 'UserAuthenticationStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  description: 'Complete user authentication solution with Amazon Cognito User Pools, including advanced security features, OAuth integration, and role-based access control',
  environmentPrefix,
  domainPrefix,
  fromEmailAddress,
  callbackUrls,
  logoutUrls,
  
  // Stack-level tags for resource management
  tags: {
    Project: 'UserAuthentication',
    Environment: environmentPrefix,
    ManagedBy: 'CDK',
    Recipe: 'user-authentication-cognito-user-pools'
  }
});

// Synthesize the CloudFormation template
app.synth();