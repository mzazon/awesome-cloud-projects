#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as organizations from 'aws-cdk-lib/aws-organizations';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as budgets from 'aws-cdk-lib/aws-budgets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as costexplorer from 'aws-cdk-lib/aws-ce';

/**
 * Properties for the Multi-Account Governance Stack
 */
interface MultiAccountGovernanceStackProps extends cdk.StackProps {
  /**
   * The organization name prefix for resource naming
   */
  organizationName?: string;
  
  /**
   * Monthly budget limit in USD for the organization
   */
  budgetLimit?: number;
  
  /**
   * List of approved regions for the region restriction SCP
   */
  approvedRegions?: string[];
  
  /**
   * List of expensive instance types to restrict
   */
  restrictedInstanceTypes?: string[];
}

/**
 * CDK Stack for Organizations Multi-Account Governance with SCPs
 * 
 * This stack creates:
 * - AWS Organization with organizational units
 * - Service Control Policies for cost control, security, and compliance
 * - Organization-wide CloudTrail for audit logging
 * - Consolidated billing and cost allocation setup
 * - Governance monitoring dashboard
 */
export class MultiAccountGovernanceStack extends cdk.Stack {
  public readonly organization: organizations.CfnOrganization;
  public readonly productionOu: organizations.CfnOrganizationalUnit;
  public readonly developmentOu: organizations.CfnOrganizationalUnit;
  public readonly sandboxOu: organizations.CfnOrganizationalUnit;
  public readonly securityOu: organizations.CfnOrganizationalUnit;
  public readonly cloudTrailBucket: s3.Bucket;
  public readonly organizationTrail: cloudtrail.Trail;

  constructor(scope: Construct, id: string, props?: MultiAccountGovernanceStackProps) {
    super(scope, id, props);

    // Default values for optional properties
    const organizationName = props?.organizationName || 'enterprise-org';
    const budgetLimit = props?.budgetLimit || 5000;
    const approvedRegions = props?.approvedRegions || ['us-east-1', 'us-west-2', 'eu-west-1'];
    const restrictedInstanceTypes = props?.restrictedInstanceTypes || [
      '*.8xlarge', '*.12xlarge', '*.16xlarge', '*.24xlarge',
      'p3.*', 'p4.*', 'x1e.*', 'r5.*large', 'r6i.*large'
    ];

    // Create AWS Organization with all features enabled
    this.organization = new organizations.CfnOrganization(this, 'Organization', {
      featureSet: 'ALL'
    });

    // Enable Service Control Policy type for the organization
    const scpPolicyType = new organizations.CfnPolicyType(this, 'SCPPolicyType', {
      rootId: this.organization.attrRootId,
      type: 'SERVICE_CONTROL_POLICY'
    });

    // Create Organizational Units
    this.productionOu = new organizations.CfnOrganizationalUnit(this, 'ProductionOU', {
      name: 'Production',
      parentId: this.organization.attrRootId
    });

    this.developmentOu = new organizations.CfnOrganizationalUnit(this, 'DevelopmentOU', {
      name: 'Development',
      parentId: this.organization.attrRootId
    });

    this.sandboxOu = new organizations.CfnOrganizationalUnit(this, 'SandboxOU', {
      name: 'Sandbox',
      parentId: this.organization.attrRootId
    });

    this.securityOu = new organizations.CfnOrganizationalUnit(this, 'SecurityOU', {
      name: 'Security',
      parentId: this.organization.attrRootId
    });

    // Create Cost Control Service Control Policy
    const costControlScp = new organizations.CfnPolicy(this, 'CostControlSCP', {
      name: 'CostControlPolicy',
      description: 'Policy to control costs and enforce tagging',
      type: 'SERVICE_CONTROL_POLICY',
      content: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'DenyExpensiveInstances',
            Effect: 'Deny',
            Action: ['ec2:RunInstances'],
            Resource: 'arn:aws:ec2:*:*:instance/*',
            Condition: {
              'ForAnyValue:StringLike': {
                'ec2:InstanceType': restrictedInstanceTypes
              }
            }
          },
          {
            Sid: 'DenyExpensiveRDSInstances',
            Effect: 'Deny',
            Action: ['rds:CreateDBInstance', 'rds:CreateDBCluster'],
            Resource: '*',
            Condition: {
              'ForAnyValue:StringLike': {
                'rds:db-instance-class': [
                  '*.8xlarge', '*.12xlarge', '*.16xlarge', '*.24xlarge'
                ]
              }
            }
          },
          {
            Sid: 'RequireCostAllocationTags',
            Effect: 'Deny',
            Action: ['ec2:RunInstances', 'rds:CreateDBInstance', 's3:CreateBucket'],
            Resource: '*',
            Condition: {
              Null: {
                'aws:RequestedRegion': 'false'
              },
              'ForAllValues:StringNotEquals': {
                'aws:TagKeys': ['Department', 'Project', 'Environment', 'Owner']
              }
            }
          }
        ]
      })
    });

    // Create Security Baseline Service Control Policy
    const securityBaselineScp = new organizations.CfnPolicy(this, 'SecurityBaselineSCP', {
      name: 'SecurityBaselinePolicy',
      description: 'Baseline security controls for all accounts',
      type: 'SERVICE_CONTROL_POLICY',
      content: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'DenyRootUserActions',
            Effect: 'Deny',
            Action: '*',
            Resource: '*',
            Condition: {
              StringEquals: {
                'aws:PrincipalType': 'Root'
              }
            }
          },
          {
            Sid: 'DenyCloudTrailDisable',
            Effect: 'Deny',
            Action: [
              'cloudtrail:StopLogging',
              'cloudtrail:DeleteTrail',
              'cloudtrail:PutEventSelectors',
              'cloudtrail:UpdateTrail'
            ],
            Resource: '*'
          },
          {
            Sid: 'DenyConfigDisable',
            Effect: 'Deny',
            Action: [
              'config:DeleteConfigRule',
              'config:DeleteConfigurationRecorder',
              'config:DeleteDeliveryChannel',
              'config:StopConfigurationRecorder'
            ],
            Resource: '*'
          },
          {
            Sid: 'DenyUnencryptedS3Objects',
            Effect: 'Deny',
            Action: 's3:PutObject',
            Resource: '*',
            Condition: {
              StringNotEquals: {
                's3:x-amz-server-side-encryption': 'AES256'
              },
              Null: {
                's3:x-amz-server-side-encryption': 'true'
              }
            }
          }
        ]
      })
    });

    // Create Region Restriction Service Control Policy
    const regionRestrictionScp = new organizations.CfnPolicy(this, 'RegionRestrictionSCP', {
      name: 'RegionRestrictionPolicy',
      description: 'Restrict sandbox accounts to approved regions',
      type: 'SERVICE_CONTROL_POLICY',
      content: JSON.stringify({
        Version: '2012-10-17',
        Statement: [
          {
            Sid: 'DenyNonApprovedRegions',
            Effect: 'Deny',
            NotAction: [
              'iam:*',
              'organizations:*',
              'route53:*',
              'cloudfront:*',
              'waf:*',
              'wafv2:*',
              'waf-regional:*',
              'support:*',
              'trustedadvisor:*'
            ],
            Resource: '*',
            Condition: {
              StringNotEquals: {
                'aws:RequestedRegion': approvedRegions
              }
            }
          }
        ]
      })
    });

    // Attach Service Control Policies to Organizational Units
    new organizations.CfnPolicyAttachment(this, 'CostControlToProdOU', {
      policyId: costControlScp.ref,
      targetId: this.productionOu.ref,
      targetType: 'ORGANIZATIONAL_UNIT'
    });

    new organizations.CfnPolicyAttachment(this, 'CostControlToDevOU', {
      policyId: costControlScp.ref,
      targetId: this.developmentOu.ref,
      targetType: 'ORGANIZATIONAL_UNIT'
    });

    new organizations.CfnPolicyAttachment(this, 'SecurityBaselineToProdOU', {
      policyId: securityBaselineScp.ref,
      targetId: this.productionOu.ref,
      targetType: 'ORGANIZATIONAL_UNIT'
    });

    new organizations.CfnPolicyAttachment(this, 'RegionRestrictionToSandboxOU', {
      policyId: regionRestrictionScp.ref,
      targetId: this.sandboxOu.ref,
      targetType: 'ORGANIZATIONAL_UNIT'
    });

    // Create S3 bucket for CloudTrail logs
    this.cloudTrailBucket = new s3.Bucket(this, 'CloudTrailBucket', {
      bucketName: `${organizationName}-cloudtrail-${cdk.Aws.ACCOUNT_ID}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldLogs',
          expiration: cdk.Duration.days(90),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(60)
            }
          ]
        }
      ]
    });

    // Create bucket policy for CloudTrail
    this.cloudTrailBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSCloudTrailAclCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['s3:GetBucketAcl'],
        resources: [this.cloudTrailBucket.bucketArn]
      })
    );

    this.cloudTrailBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSCloudTrailWrite',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [`${this.cloudTrailBucket.bucketArn}/*`],
        conditions: {
          StringEquals: {
            's3:x-amz-acl': 'bucket-owner-full-control'
          }
        }
      })
    );

    // Create organization-wide CloudTrail
    this.organizationTrail = new cloudtrail.Trail(this, 'OrganizationTrail', {
      trailName: 'OrganizationTrail',
      bucket: this.cloudTrailBucket,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      sendToCloudWatchLogs: true,
      cloudWatchLogsRetention: cdk.aws_logs.RetentionDays.ONE_MONTH
    });

    // Enable organization trail for all accounts
    const organizationTrailCfn = this.organizationTrail.node.defaultChild as cloudtrail.CfnTrail;
    organizationTrailCfn.isOrganizationTrail = true;

    // Create organization-wide budget
    const organizationBudget = new budgets.CfnBudget(this, 'OrganizationBudget', {
      budget: {
        budgetName: 'OrganizationMasterBudget',
        budgetLimit: {
          amount: budgetLimit,
          unit: 'USD'
        },
        timeUnit: 'MONTHLY',
        budgetType: 'COST',
        costFilters: {
          LinkedAccount: [cdk.Aws.ACCOUNT_ID]
        }
      },
      notificationsWithSubscribers: [
        {
          notification: {
            notificationType: 'ACTUAL',
            comparisonOperator: 'GREATER_THAN',
            threshold: 80,
            thresholdType: 'PERCENTAGE'
          },
          subscribers: [
            {
              subscriptionType: 'EMAIL',
              address: 'admin@example.com' // Replace with actual email
            }
          ]
        }
      ]
    });

    // Create CloudWatch dashboard for governance monitoring
    const governanceDashboard = new cloudwatch.Dashboard(this, 'GovernanceDashboard', {
      dashboardName: 'OrganizationGovernance',
      widgets: [
        [
          new cloudwatch.TextWidget({
            markdown: '# AWS Organization Governance Dashboard\n\nMonitoring organizational compliance and activity.',
            width: 24,
            height: 2
          })
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Organization API Activity',
            logGroups: [this.organizationTrail.logGroup!],
            queryLines: [
              'fields @timestamp, sourceIPAddress, userIdentity.type, eventName, errorMessage',
              'filter eventName like /organizations/',
              'sort @timestamp desc',
              'limit 100'
            ],
            width: 24,
            height: 6
          })
        ]
      ]
    });

    // Enable cost allocation tags using custom resource
    const costAllocationTags = new cdk.CustomResource(this, 'CostAllocationTags', {
      serviceToken: new cdk.aws_lambda.Function(this, 'CostAllocationTagsFunction', {
        runtime: cdk.aws_lambda.Runtime.PYTHON_3_11,
        handler: 'index.handler',
        code: cdk.aws_lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def handler(event, context):
    try:
        if event['RequestType'] == 'Delete':
            cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
            return
        
        ce_client = boto3.client('ce')
        
        # Enable cost allocation tags
        tags = ['Department', 'Project', 'Environment', 'Owner']
        for tag in tags:
            try:
                ce_client.create_dimension_key(
                    Key=tag,
                    MatchOptions=['EQUALS']
                )
            except Exception as e:
                print(f"Tag {tag} may already exist: {e}")
        
        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {e}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
        `),
        timeout: cdk.Duration.minutes(5)
      }).functionArn
    });

    // Outputs
    new cdk.CfnOutput(this, 'OrganizationId', {
      value: this.organization.attrId,
      description: 'AWS Organization ID'
    });

    new cdk.CfnOutput(this, 'ProductionOUId', {
      value: this.productionOu.ref,
      description: 'Production Organizational Unit ID'
    });

    new cdk.CfnOutput(this, 'DevelopmentOUId', {
      value: this.developmentOu.ref,
      description: 'Development Organizational Unit ID'
    });

    new cdk.CfnOutput(this, 'SandboxOUId', {
      value: this.sandboxOu.ref,
      description: 'Sandbox Organizational Unit ID'
    });

    new cdk.CfnOutput(this, 'SecurityOUId', {
      value: this.securityOu.ref,
      description: 'Security Organizational Unit ID'
    });

    new cdk.CfnOutput(this, 'CloudTrailBucketName', {
      value: this.cloudTrailBucket.bucketName,
      description: 'CloudTrail S3 Bucket Name'
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.organizationTrail.trailArn,
      description: 'Organization CloudTrail ARN'
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=OrganizationGovernance`,
      description: 'CloudWatch Dashboard URL'
    });

    // Apply tags to all resources
    cdk.Tags.of(this).add('Department', 'Security');
    cdk.Tags.of(this).add('Project', 'OrganizationGovernance');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'SecurityTeam');
  }
}

/**
 * CDK App for Multi-Account Governance
 */
const app = new cdk.App();

// Get configuration from context or use defaults
const organizationName = app.node.tryGetContext('organizationName') || 'enterprise-org';
const budgetLimit = app.node.tryGetContext('budgetLimit') || 5000;
const approvedRegions = app.node.tryGetContext('approvedRegions') || ['us-east-1', 'us-west-2', 'eu-west-1'];

new MultiAccountGovernanceStack(app, 'MultiAccountGovernanceStack', {
  description: 'Multi-Account Governance with AWS Organizations and Service Control Policies',
  organizationName,
  budgetLimit,
  approvedRegions,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  },
  tags: {
    Application: 'MultiAccountGovernance',
    Environment: 'Production',
    Owner: 'SecurityTeam'
  }
});

app.synth();