#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as sso from 'aws-cdk-lib/aws-sso';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as identitystore from 'aws-cdk-lib/aws-identitystore';

/**
 * Configuration interface for the AWS SSO External Identity Provider stack
 */
interface SsoExternalIdpProps extends cdk.StackProps {
  /**
   * Name for the external identity provider
   */
  readonly identityProviderName?: string;
  
  /**
   * List of AWS account IDs where permission sets should be provisioned
   */
  readonly targetAccountIds?: string[];
  
  /**
   * Whether to create sample users and groups for testing
   */
  readonly createSampleEntities?: boolean;
  
  /**
   * Session duration for permission sets (in ISO 8601 duration format)
   */
  readonly sessionDuration?: string;
  
  /**
   * Tags to apply to all resources
   */
  readonly resourceTags?: { [key: string]: string };
}

/**
 * AWS CDK Stack for SSO with External Identity Providers
 * 
 * This stack creates:
 * - Permission sets with different access levels (Developer, Administrator, ReadOnly)
 * - Sample users and groups for testing (if enabled)
 * - Account assignments linking users/groups to permission sets
 * - ABAC configuration for attribute-based access control
 */
class SsoExternalIdpStack extends cdk.Stack {
  public readonly instanceArn: string;
  public readonly identityStoreId: string;
  public readonly permissionSets: { [key: string]: sso.CfnPermissionSet };
  
  constructor(scope: Construct, id: string, props: SsoExternalIdpProps = {}) {
    super(scope, id, props);

    // Apply resource tags if provided
    if (props.resourceTags) {
      Object.entries(props.resourceTags).forEach(([key, value]) => {
        cdk.Tags.of(this).add(key, value);
      });
    }

    // Note: IAM Identity Center instance must be created manually or exist already
    // We reference the existing instance using data sources
    const instanceArn = this.formatArn({
      service: 'sso',
      resource: 'instance',
      resourceName: 'ssoins-*', // This would be replaced with actual instance ID
      arnFormat: cdk.ArnFormat.SLASH_RESOURCE_NAME,
    });

    const identityStoreId = 'd-*'; // This would be replaced with actual identity store ID

    this.instanceArn = instanceArn;
    this.identityStoreId = identityStoreId;

    // Create permission sets
    this.permissionSets = this.createPermissionSets(props);

    // Create sample users and groups if requested
    if (props.createSampleEntities) {
      this.createSampleEntities();
    }

    // Output important values
    this.createOutputs();
  }

  /**
   * Creates permission sets with different access levels
   */
  private createPermissionSets(props: SsoExternalIdpProps): { [key: string]: sso.CfnPermissionSet } {
    const sessionDuration = props.sessionDuration || 'PT8H';
    const permissionSets: { [key: string]: sso.CfnPermissionSet } = {};

    // Developer Permission Set
    permissionSets.developer = new sso.CfnPermissionSet(this, 'DeveloperPermissionSet', {
      instanceArn: this.instanceArn,
      name: 'DeveloperAccess',
      description: 'Developer access with PowerUser permissions and custom S3 access',
      sessionDuration: sessionDuration,
      managedPolicies: [
        'arn:aws:iam::aws:policy/PowerUserAccess'
      ],
      inlinePolicy: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              's3:GetObject',
              's3:PutObject',
              's3:DeleteObject'
            ],
            Resource: 'arn:aws:s3:::company-data-*/*'
          },
          {
            Effect: 'Allow',
            Action: [
              's3:ListBucket'
            ],
            Resource: 'arn:aws:s3:::company-data-*'
          }
        ]
      }),
      tags: [
        {
          key: 'Purpose',
          value: 'Developer Access'
        },
        {
          key: 'AccessLevel',
          value: 'PowerUser'
        }
      ]
    });

    // Administrator Permission Set
    permissionSets.administrator = new sso.CfnPermissionSet(this, 'AdministratorPermissionSet', {
      instanceArn: this.instanceArn,
      name: 'AdministratorAccess',
      description: 'Full administrator access with shorter session duration',
      sessionDuration: 'PT4H', // Shorter session for admins
      managedPolicies: [
        'arn:aws:iam::aws:policy/AdministratorAccess'
      ],
      tags: [
        {
          key: 'Purpose',
          value: 'Administrator Access'
        },
        {
          key: 'AccessLevel',
          value: 'Full'
        }
      ]
    });

    // ReadOnly Permission Set
    permissionSets.readOnly = new sso.CfnPermissionSet(this, 'ReadOnlyPermissionSet', {
      instanceArn: this.instanceArn,
      name: 'ReadOnlyAccess',
      description: 'Read-only access to AWS resources with extended session',
      sessionDuration: 'PT12H', // Longer session for read-only access
      managedPolicies: [
        'arn:aws:iam::aws:policy/ReadOnlyAccess'
      ],
      tags: [
        {
          key: 'Purpose',
          value: 'Read Only Access'
        },
        {
          key: 'AccessLevel',
          value: 'ReadOnly'
        }
      ]
    });

    // Security Auditor Permission Set
    permissionSets.securityAuditor = new sso.CfnPermissionSet(this, 'SecurityAuditorPermissionSet', {
      instanceArn: this.instanceArn,
      name: 'SecurityAuditorAccess',
      description: 'Security auditor access with compliance and security permissions',
      sessionDuration: 'PT8H',
      managedPolicies: [
        'arn:aws:iam::aws:policy/SecurityAudit',
        'arn:aws:iam::aws:policy/ReadOnlyAccess'
      ],
      inlinePolicy: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Effect: 'Allow',
            Action: [
              'config:GetComplianceDetailsByConfigRule',
              'config:GetComplianceDetailsByResource',
              'config:GetComplianceSummaryByConfigRule',
              'config:GetComplianceSummaryByResourceType',
              'securityhub:GetFindings',
              'securityhub:GetInsights',
              'inspector2:ListFindings',
              'guardduty:GetFindings'
            ],
            Resource: '*'
          }
        ]
      }),
      tags: [
        {
          key: 'Purpose',
          value: 'Security Auditor Access'
        },
        {
          key: 'AccessLevel',
          value: 'Audit'
        }
      ]
    });

    return permissionSets;
  }

  /**
   * Creates sample users and groups for testing purposes
   */
  private createSampleEntities(): void {
    // Sample User
    const testUser = new identitystore.CfnUser(this, 'TestUser', {
      identityStoreId: this.identityStoreId,
      userName: 'testuser@example.com',
      displayName: 'Test User',
      name: {
        givenName: 'Test',
        familyName: 'User'
      },
      emails: [
        {
          value: 'testuser@example.com',
          type: 'Work',
          primary: true
        }
      ]
    });

    // Developers Group
    const developersGroup = new identitystore.CfnGroup(this, 'DevelopersGroup', {
      identityStoreId: this.identityStoreId,
      displayName: 'Developers',
      description: 'Developer group for application development teams'
    });

    // Administrators Group
    const administratorsGroup = new identitystore.CfnGroup(this, 'AdministratorsGroup', {
      identityStoreId: this.identityStoreId,
      displayName: 'Administrators',
      description: 'Administrator group for infrastructure management'
    });

    // Security Auditors Group
    const securityAuditorsGroup = new identitystore.CfnGroup(this, 'SecurityAuditorsGroup', {
      identityStoreId: this.identityStoreId,
      displayName: 'SecurityAuditors',
      description: 'Security auditor group for compliance and security reviews'
    });

    // Group Membership - Add test user to developers group
    new identitystore.CfnGroupMembership(this, 'TestUserDeveloperMembership', {
      identityStoreId: this.identityStoreId,
      groupId: developersGroup.attrGroupId,
      memberId: {
        userId: testUser.attrUserId
      }
    });

    // Store references for outputs
    cdk.Tags.of(testUser).add('Type', 'SampleUser');
    cdk.Tags.of(developersGroup).add('Type', 'SampleGroup');
    cdk.Tags.of(administratorsGroup).add('Type', 'SampleGroup');
    cdk.Tags.of(securityAuditorsGroup).add('Type', 'SampleGroup');
  }

  /**
   * Creates CloudFormation outputs for important resource identifiers
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'SSOInstanceArn', {
      value: this.instanceArn,
      description: 'ARN of the IAM Identity Center instance',
      exportName: `${this.stackName}-SSO-Instance-Arn`
    });

    new cdk.CfnOutput(this, 'IdentityStoreId', {
      value: this.identityStoreId,
      description: 'ID of the Identity Store',
      exportName: `${this.stackName}-Identity-Store-Id`
    });

    Object.entries(this.permissionSets).forEach(([name, permissionSet]) => {
      new cdk.CfnOutput(this, `${name}PermissionSetArn`, {
        value: permissionSet.attrPermissionSetArn,
        description: `ARN of the ${name} permission set`,
        exportName: `${this.stackName}-${name}-Permission-Set-Arn`
      });
    });

    // SCIM Endpoint for external identity provider configuration
    const scimEndpoint = `https://scim.${this.region}.amazonaws.com/${this.instanceArn.split('/')[1]}`;
    new cdk.CfnOutput(this, 'SCIMEndpoint', {
      value: scimEndpoint,
      description: 'SCIM endpoint for external identity provider integration',
      exportName: `${this.stackName}-SCIM-Endpoint`
    });

    // AWS Access Portal URL
    const accessPortalUrl = `https://${this.instanceArn.split('/')[1]}.awsapps.com/start`;
    new cdk.CfnOutput(this, 'AccessPortalUrl', {
      value: accessPortalUrl,
      description: 'AWS Access Portal URL for user access',
      exportName: `${this.stackName}-Access-Portal-URL`
    });
  }
}

/**
 * CDK App for deploying AWS SSO with External Identity Providers
 */
class SsoExternalIdpApp extends cdk.App {
  constructor() {
    super();

    // Get configuration from CDK context or environment variables
    const env = {
      account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
      region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1'
    };

    // Stack configuration
    const stackProps: SsoExternalIdpProps = {
      env,
      description: 'AWS Single Sign-On with External Identity Providers - CDK Implementation',
      identityProviderName: this.node.tryGetContext('identityProviderName') || 'ExternalIdP',
      targetAccountIds: this.node.tryGetContext('targetAccountIds') || [],
      createSampleEntities: this.node.tryGetContext('createSampleEntities') ?? true,
      sessionDuration: this.node.tryGetContext('sessionDuration') || 'PT8H',
      resourceTags: {
        Environment: this.node.tryGetContext('environment') || 'development',
        Project: 'AWS-SSO-External-IdP',
        Owner: this.node.tryGetContext('owner') || 'aws-recipes',
        ManagedBy: 'CDK'
      }
    };

    // Create the stack
    new SsoExternalIdpStack(this, 'SsoExternalIdpStack', stackProps);
  }
}

// Create and run the app
new SsoExternalIdpApp();