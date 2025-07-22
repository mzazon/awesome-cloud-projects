#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';

/**
 * Configuration interface for cross-account IAM role federation
 */
interface CrossAccountFederationConfig {
  /** Security account ID where master roles are created */
  securityAccountId: string;
  /** Production account ID for production resources */
  productionAccountId: string;
  /** Development account ID for development resources */
  developmentAccountId: string;
  /** External ID for production account access (should be stored in Secrets Manager) */
  productionExternalId: string;
  /** External ID for development account access (should be stored in Secrets Manager) */
  developmentExternalId: string;
  /** SAML provider ARN for federated identity */
  samlProviderArn?: string;
  /** Allowed IP ranges for development account access */
  allowedIpRanges?: string[];
}

/**
 * Stack for Security Account - Master cross-account roles and audit infrastructure
 */
class SecurityAccountStack extends cdk.Stack {
  public readonly masterRole: iam.Role;
  public readonly auditTrail: cloudtrail.Trail;
  public readonly roleValidator: lambda.Function;

  constructor(scope: Construct, id: string, config: CrossAccountFederationConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create S3 bucket for CloudTrail logs
    const auditBucket = new s3.Bucket(this, 'AuditBucket', {
      bucketName: `cross-account-audit-trail-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          expiration: cdk.Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(60),
            },
          ],
        },
      ],
    });

    // Create CloudTrail for cross-account activity monitoring
    this.auditTrail = new cloudtrail.Trail(this, 'CrossAccountAuditTrail', {
      trailName: `CrossAccountAuditTrail-${uniqueSuffix}`,
      bucket: auditBucket,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      eventRuleTargets: [],
    });

    // Add data events for IAM role operations
    this.auditTrail.addEventSelector({
      readWriteType: cloudtrail.ReadWriteType.ALL,
      includeManagementEvents: true,
      dataResourceType: cloudtrail.DataResourceType.IAM_ROLE,
      dataResourceValues: [`arn:aws:iam::*:role/CrossAccount-*`],
    });

    // Create trust policy for master role
    const masterRoleTrustPolicy = new iam.PolicyDocument({
      statements: [
        // SAML Federation trust (if SAML provider is configured)
        ...(config.samlProviderArn ? [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.FederatedPrincipal(config.samlProviderArn, {
              'StringEquals': {
                'SAML:aud': 'https://signin.aws.amazon.com/saml',
              },
              'ForAllValues:StringLike': {
                'SAML:department': ['Engineering', 'Security', 'DevOps'],
              },
            }, 'sts:AssumeRoleWithSAML')],
          })
        ] : []),
        // Direct role assumption with MFA
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [new iam.AccountRootPrincipal()],
          actions: ['sts:AssumeRole'],
          conditions: {
            'Bool': {
              'aws:MultiFactorAuthPresent': 'true',
            },
            'NumericLessThan': {
              'aws:MultiFactorAuthAge': '3600',
            },
          },
        }),
      ],
    });

    // Create master cross-account role
    this.masterRole = new iam.Role(this, 'MasterCrossAccountRole', {
      roleName: `MasterCrossAccountRole-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(),
      inlinePolicies: {
        CrossAccountAssumePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sts:AssumeRole', 'sts:TagSession'],
              resources: [
                `arn:aws:iam::${config.productionAccountId}:role/CrossAccount-*`,
                `arn:aws:iam::${config.developmentAccountId}:role/CrossAccount-*`,
              ],
              conditions: {
                'StringEquals': {
                  'sts:ExternalId': [config.productionExternalId, config.developmentExternalId],
                  'aws:RequestedRegion': this.region,
                },
                'ForAllValues:StringEquals': {
                  'sts:TransitiveTagKeys': ['Department', 'Project', 'Environment'],
                },
              },
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'iam:ListRoles',
                'iam:GetRole',
                'sts:GetCallerIdentity',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
      maxSessionDuration: cdk.Duration.hours(2),
      description: 'Master role for federated cross-account access',
    });

    // Override the assume role policy to use our custom trust policy
    const cfnMasterRole = this.masterRole.node.defaultChild as iam.CfnRole;
    cfnMasterRole.assumeRolePolicyDocument = masterRoleTrustPolicy;

    // Create Lambda function for role validation
    this.roleValidator = new lambda.Function(this, 'RoleValidator', {
      functionName: `CrossAccountRoleValidator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Validates cross-account role configurations',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

iam = boto3.client('iam')

def lambda_handler(event, context):
    """
    Validate cross-account role configurations and trust policies
    """
    try:
        # Get all cross-account roles
        paginator = iam.get_paginator('list_roles')
        
        validation_results = []
        
        for page in paginator.paginate():
            for role in page['Roles']:
                if 'CrossAccount-' in role['RoleName']:
                    validation_result = validate_role(role)
                    validation_results.append(validation_result)
        
        # Log findings
        for result in validation_results:
            if not result['compliant']:
                logger.warning(f"Non-compliant role found: {result}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'validated_roles': len(validation_results),
                'compliant_roles': sum(1 for r in validation_results if r['compliant'])
            })
        }
        
    except Exception as e:
        logger.error(f"Error validating roles: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def validate_role(role):
    """
    Validate individual role configuration
    """
    role_name = role['RoleName']
    
    try:
        # Get role details
        role_details = iam.get_role(RoleName=role_name)
        assume_role_policy = role_details['Role']['AssumeRolePolicyDocument']
        
        validation_checks = {
            'has_external_id': check_external_id(assume_role_policy),
            'has_mfa_condition': check_mfa_condition(assume_role_policy),
            'max_session_duration_ok': role['MaxSessionDuration'] <= 7200
        }
        
        compliant = all(validation_checks.values())
        
        return {
            'role_name': role_name,
            'compliant': compliant,
            'checks': validation_checks
        }
        
    except Exception as e:
        logger.error(f"Error validating role {role_name}: {str(e)}")
        return {
            'role_name': role_name,
            'compliant': False,
            'error': str(e)
        }

def check_external_id(policy):
    """Check if policy requires ExternalId"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'StringEquals' in conditions and 'sts:ExternalId' in conditions['StringEquals']:
            return True
    return False

def check_mfa_condition(policy):
    """Check if policy requires MFA"""
    for statement in policy.get('Statement', []):
        conditions = statement.get('Condition', {})
        if 'Bool' in conditions and 'aws:MultiFactorAuthPresent' in conditions['Bool']:
            return True
    return False
      `),
    });

    // Grant IAM read permissions to the validator function
    this.roleValidator.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'iam:ListRoles',
          'iam:GetRole',
          'iam:GetRolePolicy',
          'iam:ListRolePolicies',
        ],
        resources: ['*'],
      })
    );

    // Create EventBridge rule to trigger validation periodically
    const validationRule = new events.Rule(this, 'ValidationRule', {
      ruleName: `CrossAccountRoleValidation-${uniqueSuffix}`,
      description: 'Periodic validation of cross-account role configurations',
      schedule: events.Schedule.rate(cdk.Duration.hours(24)),
    });

    validationRule.addTarget(new targets.LambdaFunction(this.roleValidator));

    // Output important ARNs and identifiers
    new cdk.CfnOutput(this, 'MasterRoleArn', {
      value: this.masterRole.roleArn,
      description: 'ARN of the master cross-account role',
      exportName: `MasterCrossAccountRole-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'AuditTrailArn', {
      value: this.auditTrail.trailArn,
      description: 'ARN of the cross-account audit trail',
    });

    new cdk.CfnOutput(this, 'RoleValidatorArn', {
      value: this.roleValidator.functionArn,
      description: 'ARN of the role validator Lambda function',
    });

    new cdk.CfnOutput(this, 'UniqueSuffix', {
      value: uniqueSuffix,
      description: 'Unique suffix used for resource naming',
      exportName: `CrossAccountUniqueSuffix-${uniqueSuffix}`,
    });

    // Tag all resources
    cdk.Tags.of(this).add('Purpose', 'CrossAccountFederation');
    cdk.Tags.of(this).add('Environment', 'Security');
    cdk.Tags.of(this).add('Owner', 'SecurityTeam');
  }
}

/**
 * Stack for Production Account - Production-specific cross-account roles
 */
class ProductionAccountStack extends cdk.Stack {
  public readonly productionRole: iam.Role;

  constructor(scope: Construct, id: string, config: CrossAccountFederationConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create trust policy for production account role
    const productionTrustPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [
            new iam.ArnPrincipal(`arn:aws:iam::${config.securityAccountId}:role/MasterCrossAccountRole-*`)
          ],
          actions: ['sts:AssumeRole'],
          conditions: {
            'StringEquals': {
              'sts:ExternalId': config.productionExternalId,
            },
            'Bool': {
              'aws:MultiFactorAuthPresent': 'true',
            },
            'StringLike': {
              'aws:userid': `*:${config.securityAccountId}:*`,
            },
          },
        }),
      ],
    });

    // Create production S3 bucket for demonstration
    const prodDataBucket = new s3.Bucket(this, 'ProductionDataBucket', {
      bucketName: `prod-shared-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
    });

    // Create production cross-account role
    this.productionRole = new iam.Role(this, 'ProductionCrossAccountRole', {
      roleName: `CrossAccount-ProductionAccess-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(),
      inlinePolicies: {
        ProductionResourceAccess: new iam.PolicyDocument({
          statements: [
            // S3 access for production data
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:ListBucket',
              ],
              resources: [
                prodDataBucket.bucketArn,
                prodDataBucket.arnForObjects('*'),
              ],
            }),
            // CloudWatch logs access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
            // CloudWatch metrics access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
      maxSessionDuration: cdk.Duration.hours(1),
      description: 'Cross-account role for production resource access',
    });

    // Override the assume role policy
    const cfnProductionRole = this.productionRole.node.defaultChild as iam.CfnRole;
    cfnProductionRole.assumeRolePolicyDocument = productionTrustPolicy;

    // Output role ARN
    new cdk.CfnOutput(this, 'ProductionRoleArn', {
      value: this.productionRole.roleArn,
      description: 'ARN of the production cross-account role',
    });

    new cdk.CfnOutput(this, 'ProductionDataBucketName', {
      value: prodDataBucket.bucketName,
      description: 'Name of the production data bucket',
    });

    // Tag all resources
    cdk.Tags.of(this).add('Purpose', 'CrossAccountFederation');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'ProductionTeam');
  }
}

/**
 * Stack for Development Account - Development-specific cross-account roles
 */
class DevelopmentAccountStack extends cdk.Stack {
  public readonly developmentRole: iam.Role;

  constructor(scope: Construct, id: string, config: CrossAccountFederationConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create trust policy for development account role
    const developmentTrustPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          principals: [
            new iam.ArnPrincipal(`arn:aws:iam::${config.securityAccountId}:role/MasterCrossAccountRole-*`)
          ],
          actions: ['sts:AssumeRole'],
          conditions: {
            'StringEquals': {
              'sts:ExternalId': config.developmentExternalId,
            },
            'StringLike': {
              'aws:userid': `*:${config.securityAccountId}:*`,
            },
            // Optional IP restrictions for development access
            ...(config.allowedIpRanges && config.allowedIpRanges.length > 0 ? {
              'IpAddress': {
                'aws:SourceIp': config.allowedIpRanges,
              },
            } : {}),
          },
        }),
      ],
    });

    // Create development S3 bucket for demonstration
    const devDataBucket = new s3.Bucket(this, 'DevelopmentDataBucket', {
      bucketName: `dev-shared-data-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      autoDeleteObjects: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create development cross-account role with broader permissions
    this.developmentRole = new iam.Role(this, 'DevelopmentCrossAccountRole', {
      roleName: `CrossAccount-DevelopmentAccess-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(),
      inlinePolicies: {
        DevelopmentResourceAccess: new iam.PolicyDocument({
          statements: [
            // Broader S3 access for development
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:*'],
              resources: [
                devDataBucket.bucketArn,
                devDataBucket.arnForObjects('*'),
              ],
            }),
            // EC2 read access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ec2:DescribeInstances',
                'ec2:DescribeSecurityGroups',
                'ec2:DescribeVpcs',
                'ec2:DescribeSubnets',
              ],
              resources: ['*'],
            }),
            // Lambda access for development functions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'lambda:InvokeFunction',
                'lambda:GetFunction',
                'lambda:ListFunctions',
              ],
              resources: [`arn:aws:lambda:${this.region}:${this.account}:function:dev-*`],
            }),
            // Full CloudWatch logs access for development
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['logs:*'],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
          ],
        }),
      },
      maxSessionDuration: cdk.Duration.hours(2),
      description: 'Cross-account role for development resource access',
    });

    // Override the assume role policy
    const cfnDevelopmentRole = this.developmentRole.node.defaultChild as iam.CfnRole;
    cfnDevelopmentRole.assumeRolePolicyDocument = developmentTrustPolicy;

    // Output role ARN
    new cdk.CfnOutput(this, 'DevelopmentRoleArn', {
      value: this.developmentRole.roleArn,
      description: 'ARN of the development cross-account role',
    });

    new cdk.CfnOutput(this, 'DevelopmentDataBucketName', {
      value: devDataBucket.bucketName,
      description: 'Name of the development data bucket',
    });

    // Tag all resources
    cdk.Tags.of(this).add('Purpose', 'CrossAccountFederation');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'DevelopmentTeam');
  }
}

/**
 * Main CDK Application
 */
class CrossAccountFederationApp extends cdk.App {
  constructor() {
    super();

    // Configuration - These should be provided via CDK context or environment variables
    const config: CrossAccountFederationConfig = {
      securityAccountId: this.node.tryGetContext('securityAccountId') || process.env.SECURITY_ACCOUNT_ID || '111111111111',
      productionAccountId: this.node.tryGetContext('productionAccountId') || process.env.PRODUCTION_ACCOUNT_ID || '222222222222',
      developmentAccountId: this.node.tryGetContext('developmentAccountId') || process.env.DEVELOPMENT_ACCOUNT_ID || '333333333333',
      productionExternalId: this.node.tryGetContext('productionExternalId') || process.env.PRODUCTION_EXTERNAL_ID || 'prod-external-id-change-me',
      developmentExternalId: this.node.tryGetContext('developmentExternalId') || process.env.DEVELOPMENT_EXTERNAL_ID || 'dev-external-id-change-me',
      samlProviderArn: this.node.tryGetContext('samlProviderArn') || process.env.SAML_PROVIDER_ARN,
      allowedIpRanges: this.node.tryGetContext('allowedIpRanges') || (process.env.ALLOWED_IP_RANGES ? process.env.ALLOWED_IP_RANGES.split(',') : ['203.0.113.0/24', '198.51.100.0/24']),
    };

    // Validate configuration
    if (config.securityAccountId === config.productionAccountId || 
        config.securityAccountId === config.developmentAccountId || 
        config.productionAccountId === config.developmentAccountId) {
      throw new Error('All account IDs must be different');
    }

    if (config.productionExternalId === 'prod-external-id-change-me' || 
        config.developmentExternalId === 'dev-external-id-change-me') {
      console.warn('WARNING: Default external IDs detected. Change these for production use!');
    }

    // Create stacks for each account
    const securityStack = new SecurityAccountStack(this, 'SecurityAccountStack', config, {
      env: {
        account: config.securityAccountId,
        region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
      },
      description: 'Security account stack for cross-account IAM role federation',
    });

    const productionStack = new ProductionAccountStack(this, 'ProductionAccountStack', config, {
      env: {
        account: config.productionAccountId,
        region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
      },
      description: 'Production account stack for cross-account IAM role federation',
    });

    const developmentStack = new DevelopmentAccountStack(this, 'DevelopmentAccountStack', config, {
      env: {
        account: config.developmentAccountId,
        region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
      },
      description: 'Development account stack for cross-account IAM role federation',
    });

    // Add dependencies if needed (though these stacks are designed to be independent)
    // productionStack.addDependency(securityStack);
    // developmentStack.addDependency(securityStack);
  }
}

// Create and run the app
new CrossAccountFederationApp();