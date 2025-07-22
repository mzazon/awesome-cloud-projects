import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as organizations from 'aws-cdk-lib/aws-organizations';
import * as cloudformation from 'aws-cdk-lib/aws-cloudformation';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';

export interface StackSetsMultiAccountStackProps extends cdk.StackProps {
  managementAccountId: string;
  organizationId?: string;
  stackSetName: string;
  targetRegions: string[];
  targetAccounts: string[];
  complianceLevel: string;
  environment: string;
  templateBucket?: string;
}

/**
 * Main stack for CloudFormation StackSets multi-account multi-region management
 * 
 * This stack creates:
 * - StackSet administrator role and permissions
 * - S3 bucket for CloudFormation templates
 * - CloudFormation StackSets for governance policies
 * - Organization trusted access enablement
 * - Custom resources for StackSet operations
 */
export class StackSetsMultiAccountStack extends cdk.Stack {
  public readonly stackSetAdministratorRole: iam.Role;
  public readonly templateBucket: s3.Bucket;
  public readonly governanceStackSet: cloudformation.CfnStackSet;
  public readonly executionRoleStackSet: cloudformation.CfnStackSet;

  constructor(scope: Construct, id: string, props: StackSetsMultiAccountStackProps) {
    super(scope, id, props);

    // Create S3 bucket for templates if not provided
    this.templateBucket = this.createTemplateBucket(props.templateBucket);

    // Create StackSet administrator role
    this.stackSetAdministratorRole = this.createStackSetAdministratorRole(props.managementAccountId);

    // Enable trusted access for CloudFormation StackSets
    this.enableTrustedAccess();

    // Create execution role StackSet
    this.executionRoleStackSet = this.createExecutionRoleStackSet(props);

    // Create governance StackSet
    this.governanceStackSet = this.createGovernanceStackSet(props);

    // Deploy execution roles to target accounts
    this.deployExecutionRoles(props);

    // Deploy governance policies
    this.deployGovernancePolicies(props);

    // Output important values
    this.createOutputs();
  }

  /**
   * Create S3 bucket for storing CloudFormation templates
   */
  private createTemplateBucket(bucketName?: string): s3.Bucket {
    const bucket = new s3.Bucket(this, 'TemplatesBucket', {
      bucketName: bucketName,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Add bucket policy for CloudFormation access
    bucket.addToResourcePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudformation.amazonaws.com')],
        actions: ['s3:GetObject'],
        resources: [bucket.arnForObjects('*')],
      })
    );

    cdk.Tags.of(bucket).add('Purpose', 'StackSetTemplates');

    return bucket;
  }

  /**
   * Create IAM role for StackSet administration
   */
  private createStackSetAdministratorRole(managementAccountId: string): iam.Role {
    const role = new iam.Role(this, 'StackSetAdministratorRole', {
      roleName: 'AWSCloudFormationStackSetAdministrator',
      assumedBy: new iam.ServicePrincipal('cloudformation.amazonaws.com'),
      description: 'CloudFormation StackSet Administrator Role',
    });

    // Create custom policy for StackSet administration
    const policy = new iam.Policy(this, 'StackSetAdministratorPolicy', {
      policyName: 'AWSCloudFormationStackSetAdministratorPolicy',
      statements: [
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sts:AssumeRole'],
          resources: [`arn:aws:iam::*:role/AWSCloudFormationStackSetExecutionRole`],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'cloudformation:*',
            'organizations:ListAccounts',
            'organizations:DescribeOrganization',
            'organizations:ListOrganizationalUnitsForParent',
            'organizations:DescribeAccount',
            'organizations:ListParents',
            'organizations:ListChildren',
          ],
          resources: ['*'],
        }),
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetObject',
            's3:GetObjectVersion',
            's3:ListBucket',
          ],
          resources: [
            this.templateBucket.bucketArn,
            this.templateBucket.arnForObjects('*'),
          ],
        }),
      ],
    });

    role.attachInlinePolicy(policy);

    cdk.Tags.of(role).add('Purpose', 'StackSetAdministration');

    return role;
  }

  /**
   * Enable trusted access for CloudFormation StackSets in Organizations
   */
  private enableTrustedAccess(): void {
    new cr.AwsCustomResource(this, 'EnableTrustedAccess', {
      onCreate: {
        service: 'Organizations',
        action: 'enableAWSServiceAccess',
        parameters: {
          ServicePrincipal: 'stacksets.cloudformation.amazonaws.com',
        },
        physicalResourceId: cr.PhysicalResourceId.of('enable-trusted-access'),
      },
      onDelete: {
        service: 'Organizations',
        action: 'disableAWSServiceAccess',
        parameters: {
          ServicePrincipal: 'stacksets.cloudformation.amazonaws.com',
        },
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });
  }

  /**
   * Create StackSet for deploying execution roles
   */
  private createExecutionRoleStackSet(props: StackSetsMultiAccountStackProps): cloudformation.CfnStackSet {
    const executionRoleTemplate = {
      AWSTemplateFormatVersion: '2010-09-09',
      Description: 'StackSet execution role for target accounts',
      Parameters: {
        AdministratorAccountId: {
          Type: 'String',
          Description: 'AWS account ID of the StackSet administrator account',
        },
      },
      Resources: {
        ExecutionRole: {
          Type: 'AWS::IAM::Role',
          Properties: {
            RoleName: 'AWSCloudFormationStackSetExecutionRole',
            AssumeRolePolicyDocument: {
              Version: '2012-10-17',
              Statement: [
                {
                  Effect: 'Allow',
                  Principal: {
                    AWS: {
                      'Fn::Sub': 'arn:aws:iam::${AdministratorAccountId}:role/AWSCloudFormationStackSetAdministrator',
                    },
                  },
                  Action: 'sts:AssumeRole',
                },
              ],
            },
            Path: '/',
            Policies: [
              {
                PolicyName: 'StackSetExecutionPolicy',
                PolicyDocument: {
                  Version: '2012-10-17',
                  Statement: [
                    {
                      Effect: 'Allow',
                      Action: '*',
                      Resource: '*',
                    },
                  ],
                },
              },
            ],
            Tags: [
              {
                Key: 'Purpose',
                Value: 'StackSetExecution',
              },
              {
                Key: 'ManagedBy',
                Value: 'CloudFormationStackSets',
              },
            ],
          },
        },
      },
      Outputs: {
        ExecutionRoleArn: {
          Description: 'ARN of the execution role',
          Value: {
            'Fn::GetAtt': ['ExecutionRole', 'Arn'],
          },
          Export: {
            Name: {
              'Fn::Sub': '${AWS::StackName}-ExecutionRoleArn',
            },
          },
        },
      },
    };

    const stackSet = new cloudformation.CfnStackSet(this, 'ExecutionRoleStackSet', {
      stackSetName: `${props.stackSetName}-execution-roles`,
      description: 'Deploy StackSet execution roles to target accounts',
      templateBody: JSON.stringify(executionRoleTemplate, null, 2),
      parameters: [
        {
          parameterKey: 'AdministratorAccountId',
          parameterValue: props.managementAccountId,
        },
      ],
      capabilities: ['CAPABILITY_NAMED_IAM'],
      permissionModel: 'SELF_MANAGED',
      tags: [
        {
          key: 'Purpose',
          value: 'ExecutionRoles',
        },
        {
          key: 'ManagedBy',
          value: 'CDK',
        },
      ],
    });

    return stackSet;
  }

  /**
   * Create StackSet for governance policies
   */
  private createGovernanceStackSet(props: StackSetsMultiAccountStackProps): cloudformation.CfnStackSet {
    const governanceTemplate = this.createGovernanceTemplate(props);

    const stackSet = new cloudformation.CfnStackSet(this, 'GovernanceStackSet', {
      stackSetName: props.stackSetName,
      description: 'Organization-wide governance and security policies',
      templateBody: JSON.stringify(governanceTemplate, null, 2),
      parameters: [
        {
          parameterKey: 'Environment',
          parameterValue: props.environment,
        },
        {
          parameterKey: 'OrganizationId',
          parameterValue: props.organizationId || 'not-configured',
        },
        {
          parameterKey: 'ComplianceLevel',
          parameterValue: props.complianceLevel,
        },
      ],
      capabilities: ['CAPABILITY_IAM'],
      permissionModel: 'SERVICE_MANAGED',
      autoDeployment: {
        enabled: true,
        retainStacksOnAccountRemoval: false,
      },
      operationPreferences: {
        regionConcurrencyType: 'PARALLEL',
        maxConcurrentPercentage: 100,
      },
      tags: [
        {
          key: 'Purpose',
          value: 'GovernancePolicies',
        },
        {
          key: 'ManagedBy',
          value: 'CDK',
        },
      ],
    });

    return stackSet;
  }

  /**
   * Create governance template for StackSet
   */
  private createGovernanceTemplate(props: StackSetsMultiAccountStackProps): any {
    return {
      AWSTemplateFormatVersion: '2010-09-09',
      Description: 'Organization-wide governance and security policies',
      Parameters: {
        Environment: {
          Type: 'String',
          Default: 'all',
          AllowedValues: ['development', 'staging', 'production', 'all'],
          Description: 'Environment for which policies apply',
        },
        OrganizationId: {
          Type: 'String',
          Description: 'AWS Organizations ID',
        },
        ComplianceLevel: {
          Type: 'String',
          Default: 'standard',
          AllowedValues: ['basic', 'standard', 'strict'],
          Description: 'Compliance level for security policies',
        },
      },
      Mappings: {
        ComplianceConfig: {
          basic: {
            PasswordMinLength: 8,
            RequireMFA: false,
            S3PublicReadBlock: true,
            S3PublicWriteBlock: true,
          },
          standard: {
            PasswordMinLength: 12,
            RequireMFA: true,
            S3PublicReadBlock: true,
            S3PublicWriteBlock: true,
          },
          strict: {
            PasswordMinLength: 16,
            RequireMFA: true,
            S3PublicReadBlock: true,
            S3PublicWriteBlock: true,
          },
        },
      },
      Resources: {
        // IAM Password Policy
        PasswordPolicy: {
          Type: 'AWS::IAM::AccountPasswordPolicy',
          Properties: {
            MinimumPasswordLength: {
              'Fn::FindInMap': ['ComplianceConfig', { Ref: 'ComplianceLevel' }, 'PasswordMinLength'],
            },
            RequireUppercaseCharacters: true,
            RequireLowercaseCharacters: true,
            RequireNumbers: true,
            RequireSymbols: true,
            MaxPasswordAge: 90,
            PasswordReusePrevention: 12,
            HardExpiry: false,
            AllowUsersToChangePassword: true,
          },
        },
        // CloudTrail for auditing
        OrganizationCloudTrail: {
          Type: 'AWS::CloudTrail::Trail',
          Properties: {
            TrailName: {
              'Fn::Sub': 'organization-audit-trail-${AWS::AccountId}-${AWS::Region}',
            },
            S3BucketName: { Ref: 'AuditBucket' },
            S3KeyPrefix: {
              'Fn::Sub': 'cloudtrail-logs/${AWS::AccountId}/',
            },
            IncludeGlobalServiceEvents: true,
            IsMultiRegionTrail: true,
            EnableLogFileValidation: true,
            EventSelectors: [
              {
                ReadWriteType: 'All',
                IncludeManagementEvents: true,
                DataResources: [
                  {
                    Type: 'AWS::S3::Object',
                    Values: ['arn:aws:s3:::*/*'],
                  },
                ],
              },
            ],
            Tags: [
              {
                Key: 'Purpose',
                Value: 'OrganizationAudit',
              },
              {
                Key: 'Environment',
                Value: { Ref: 'Environment' },
              },
            ],
          },
        },
        // S3 bucket for CloudTrail logs
        AuditBucket: {
          Type: 'AWS::S3::Bucket',
          Properties: {
            BucketName: {
              'Fn::Sub': 'org-audit-logs-${AWS::AccountId}-${AWS::Region}-${OrganizationId}',
            },
            PublicAccessBlockConfiguration: {
              BlockPublicAcls: {
                'Fn::FindInMap': ['ComplianceConfig', { Ref: 'ComplianceLevel' }, 'S3PublicReadBlock'],
              },
              BlockPublicPolicy: {
                'Fn::FindInMap': ['ComplianceConfig', { Ref: 'ComplianceLevel' }, 'S3PublicWriteBlock'],
              },
              IgnorePublicAcls: {
                'Fn::FindInMap': ['ComplianceConfig', { Ref: 'ComplianceLevel' }, 'S3PublicReadBlock'],
              },
              RestrictPublicBuckets: {
                'Fn::FindInMap': ['ComplianceConfig', { Ref: 'ComplianceLevel' }, 'S3PublicWriteBlock'],
              },
            },
            BucketEncryption: {
              ServerSideEncryptionConfiguration: [
                {
                  ServerSideEncryptionByDefault: {
                    SSEAlgorithm: 'AES256',
                  },
                },
              ],
            },
            VersioningConfiguration: {
              Status: 'Enabled',
            },
            LifecycleConfiguration: {
              Rules: [
                {
                  Id: 'DeleteOldLogs',
                  Status: 'Enabled',
                  ExpirationInDays: 2555, // 7 years
                  NoncurrentVersionExpirationInDays: 365,
                },
              ],
            },
            Tags: [
              {
                Key: 'Purpose',
                Value: 'AuditLogs',
              },
              {
                Key: 'Environment',
                Value: { Ref: 'Environment' },
              },
            ],
          },
        },
        // CloudTrail bucket policy
        AuditBucketPolicy: {
          Type: 'AWS::S3::BucketPolicy',
          Properties: {
            Bucket: { Ref: 'AuditBucket' },
            PolicyDocument: {
              Version: '2012-10-17',
              Statement: [
                {
                  Sid: 'AWSCloudTrailAclCheck',
                  Effect: 'Allow',
                  Principal: {
                    Service: 'cloudtrail.amazonaws.com',
                  },
                  Action: 's3:GetBucketAcl',
                  Resource: {
                    'Fn::GetAtt': ['AuditBucket', 'Arn'],
                  },
                },
                {
                  Sid: 'AWSCloudTrailWrite',
                  Effect: 'Allow',
                  Principal: {
                    Service: 'cloudtrail.amazonaws.com',
                  },
                  Action: 's3:PutObject',
                  Resource: {
                    'Fn::Sub': '${AuditBucket.Arn}/*',
                  },
                  Condition: {
                    StringEquals: {
                      's3:x-amz-acl': 'bucket-owner-full-control',
                    },
                  },
                },
              ],
            },
          },
        },
        // GuardDuty Detector
        GuardDutyDetector: {
          Type: 'AWS::GuardDuty::Detector',
          Properties: {
            Enable: true,
            FindingPublishingFrequency: 'FIFTEEN_MINUTES',
            Tags: [
              {
                Key: 'Purpose',
                Value: 'SecurityMonitoring',
              },
              {
                Key: 'Environment',
                Value: { Ref: 'Environment' },
              },
            ],
          },
        },
      },
      Outputs: {
        CloudTrailArn: {
          Description: 'CloudTrail ARN',
          Value: {
            'Fn::GetAtt': ['OrganizationCloudTrail', 'Arn'],
          },
          Export: {
            Name: {
              'Fn::Sub': '${AWS::StackName}-CloudTrailArn',
            },
          },
        },
        AuditBucketName: {
          Description: 'Audit bucket name',
          Value: { Ref: 'AuditBucket' },
          Export: {
            Name: {
              'Fn::Sub': '${AWS::StackName}-AuditBucketName',
            },
          },
        },
        GuardDutyDetectorId: {
          Description: 'GuardDuty detector ID',
          Value: { Ref: 'GuardDutyDetector' },
          Export: {
            Name: {
              'Fn::Sub': '${AWS::StackName}-GuardDutyDetectorId',
            },
          },
        },
      },
    };
  }

  /**
   * Deploy execution roles to target accounts
   */
  private deployExecutionRoles(props: StackSetsMultiAccountStackProps): void {
    if (props.targetAccounts.length === 0) {
      console.log('No target accounts specified. Skipping execution role deployment.');
      return;
    }

    new cr.AwsCustomResource(this, 'DeployExecutionRoles', {
      onCreate: {
        service: 'CloudFormation',
        action: 'createStackInstances',
        parameters: {
          StackSetName: this.executionRoleStackSet.stackSetName,
          Accounts: props.targetAccounts,
          Regions: [this.region],
        },
        physicalResourceId: cr.PhysicalResourceId.of('deploy-execution-roles'),
      },
      onDelete: {
        service: 'CloudFormation',
        action: 'deleteStackInstances',
        parameters: {
          StackSetName: this.executionRoleStackSet.stackSetName,
          Accounts: props.targetAccounts,
          Regions: [this.region],
          RetainStacks: false,
        },
      },
      policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
        resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
      }),
    });
  }

  /**
   * Deploy governance policies to organizational units or accounts
   */
  private deployGovernancePolicies(props: StackSetsMultiAccountStackProps): void {
    // Deploy to organizational units if organization is configured
    if (props.organizationId) {
      new cr.AwsCustomResource(this, 'DeployToOrganizationalUnits', {
        onCreate: {
          service: 'CloudFormation',
          action: 'createStackInstances',
          parameters: {
            StackSetName: this.governanceStackSet.stackSetName,
            DeploymentTargets: {
              OrganizationalUnitIds: ['r-' + props.organizationId.substring(2)], // Root OU
            },
            Regions: props.targetRegions,
            OperationPreferences: {
              RegionConcurrencyType: 'PARALLEL',
              MaxConcurrentPercentage: 100,
            },
          },
          physicalResourceId: cr.PhysicalResourceId.of('deploy-governance-policies'),
        },
        onDelete: {
          service: 'CloudFormation',
          action: 'deleteStackInstances',
          parameters: {
            StackSetName: this.governanceStackSet.stackSetName,
            DeploymentTargets: {
              OrganizationalUnitIds: ['r-' + props.organizationId.substring(2)], // Root OU
            },
            Regions: props.targetRegions,
            RetainStacks: false,
          },
        },
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
          resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
        }),
      });
    } else if (props.targetAccounts.length > 0) {
      // Deploy to specific accounts if no organization
      new cr.AwsCustomResource(this, 'DeployToAccounts', {
        onCreate: {
          service: 'CloudFormation',
          action: 'createStackInstances',
          parameters: {
            StackSetName: this.governanceStackSet.stackSetName,
            Accounts: props.targetAccounts,
            Regions: props.targetRegions,
            OperationPreferences: {
              RegionConcurrencyType: 'PARALLEL',
              MaxConcurrentPercentage: 50,
            },
          },
          physicalResourceId: cr.PhysicalResourceId.of('deploy-governance-policies'),
        },
        onDelete: {
          service: 'CloudFormation',
          action: 'deleteStackInstances',
          parameters: {
            StackSetName: this.governanceStackSet.stackSetName,
            Accounts: props.targetAccounts,
            Regions: props.targetRegions,
            RetainStacks: false,
          },
        },
        policy: cr.AwsCustomResourcePolicy.fromSdkCalls({
          resources: cr.AwsCustomResourcePolicy.ANY_RESOURCE,
        }),
      });
    }
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'StackSetAdministratorRoleArn', {
      description: 'ARN of the StackSet administrator role',
      value: this.stackSetAdministratorRole.roleArn,
      exportName: `${this.stackName}-StackSetAdministratorRoleArn`,
    });

    new cdk.CfnOutput(this, 'TemplateBucketName', {
      description: 'Name of the S3 bucket for templates',
      value: this.templateBucket.bucketName,
      exportName: `${this.stackName}-TemplateBucketName`,
    });

    new cdk.CfnOutput(this, 'GovernanceStackSetName', {
      description: 'Name of the governance StackSet',
      value: this.governanceStackSet.stackSetName!,
      exportName: `${this.stackName}-GovernanceStackSetName`,
    });

    new cdk.CfnOutput(this, 'ExecutionRoleStackSetName', {
      description: 'Name of the execution role StackSet',
      value: this.executionRoleStackSet.stackSetName!,
      exportName: `${this.stackName}-ExecutionRoleStackSetName`,
    });
  }
}