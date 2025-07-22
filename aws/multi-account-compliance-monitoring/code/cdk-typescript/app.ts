#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as securityhub from 'aws-cdk-lib/aws-securityhub';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Properties for the Cross-Account Compliance Monitoring Stack
 */
interface CrossAccountComplianceStackProps extends cdk.StackProps {
  /**
   * List of member account IDs to monitor
   */
  memberAccountIds: string[];
  
  /**
   * External ID for cross-account role assumption security
   */
  externalId: string;
  
  /**
   * Whether to enable Security Hub as organization administrator
   * @default true
   */
  enableOrganizationAdmin?: boolean;
  
  /**
   * CloudTrail bucket name prefix
   * @default 'compliance-audit-trail'
   */
  cloudTrailBucketPrefix?: string;
}

/**
 * CDK Stack for implementing cross-account compliance monitoring
 * with AWS Systems Manager and Security Hub
 */
export class CrossAccountComplianceStack extends cdk.Stack {
  public readonly securityHub: securityhub.CfnHub;
  public readonly complianceLambda: lambda.Function;
  public readonly cloudTrail: cloudtrail.Trail;
  public readonly crossAccountRoleName: string;

  constructor(scope: Construct, id: string, props: CrossAccountComplianceStackProps) {
    super(scope, id, props);

    // Generate unique resource names
    const resourceSuffix = this.node.addr.substring(0, 6);
    this.crossAccountRoleName = `SecurityHubComplianceRole-${resourceSuffix}`;

    // Create Security Hub
    this.securityHub = this.createSecurityHub(props.enableOrganizationAdmin);

    // Create CloudTrail for compliance auditing
    this.cloudTrail = this.createCloudTrail(props.cloudTrailBucketPrefix || 'compliance-audit-trail', resourceSuffix);

    // Create Lambda function for compliance processing
    this.complianceLambda = this.createComplianceLambda(props.memberAccountIds, props.externalId, resourceSuffix);

    // Create EventBridge rules for automation
    this.createEventBridgeRules(resourceSuffix);

    // Create Systems Manager document for custom compliance
    this.createCustomComplianceDocument(resourceSuffix);

    // Create cross-account role template for member accounts
    this.createCrossAccountRoleTemplate(props.externalId);

    // Output important values
    this.createOutputs(props.memberAccountIds, props.externalId);
  }

  /**
   * Creates and configures AWS Security Hub
   */
  private createSecurityHub(enableOrganizationAdmin?: boolean): securityhub.CfnHub {
    // Enable Security Hub
    const hub = new securityhub.CfnHub(this, 'SecurityHub', {
      tags: [
        { key: 'Purpose', value: 'ComplianceMonitoring' },
        { key: 'Environment', value: 'Production' }
      ]
    });

    // Enable organization admin account if specified
    if (enableOrganizationAdmin) {
      const organizationAdmin = new securityhub.CfnOrganizationAdminAccount(this, 'SecurityHubOrgAdmin', {
        adminAccountId: this.account
      });
      organizationAdmin.addDependency(hub);
    }

    // Enable Systems Manager integration
    new securityhub.CfnProductSubscription(this, 'SystemsManagerIntegration', {
      productArn: `arn:aws:securityhub:${this.region}::product/aws/systems-manager`
    });

    return hub;
  }

  /**
   * Creates CloudTrail for compliance auditing
   */
  private createCloudTrail(bucketPrefix: string, suffix: string): cloudtrail.Trail {
    // Create S3 bucket for CloudTrail logs
    const cloudTrailBucket = new s3.Bucket(this, 'CloudTrailBucket', {
      bucketName: `${bucketPrefix}-${suffix}-${this.region}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      versioned: true,
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

    // Create CloudTrail
    const trail = new cloudtrail.Trail(this, 'ComplianceAuditTrail', {
      bucket: cloudTrailBucket,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: new logs.LogGroup(this, 'CloudTrailLogGroup', {
        logGroupName: `/aws/cloudtrail/compliance-${suffix}`,
        retention: logs.RetentionDays.THREE_MONTHS,
        removalPolicy: cdk.RemovalPolicy.DESTROY
      })
    });

    // Add tags
    cdk.Tags.of(trail).add('Purpose', 'ComplianceAuditing');

    return trail;
  }

  /**
   * Creates Lambda function for compliance processing
   */
  private createComplianceLambda(memberAccountIds: string[], externalId: string, suffix: string): lambda.Function {
    // Create IAM role for Lambda
    const lambdaRole = new iam.Role(this, 'ComplianceProcessingRole', {
      roleName: `ComplianceProcessingRole-${suffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        ComplianceProcessingPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'sts:AssumeRole',
                'securityhub:BatchImportFindings',
                'ssm:ListComplianceItems',
                'ssm:GetComplianceSummary'
              ],
              resources: ['*']
            }),
            // Allow assuming roles in member accounts
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sts:AssumeRole'],
              resources: memberAccountIds.map(accountId => 
                `arn:aws:iam::${accountId}:role/SecurityHubComplianceRole-*`
              )
            })
          ]
        })
      }
    });

    // Create Lambda function
    const complianceFunction = new lambda.Function(this, 'ComplianceProcessor', {
      functionName: `ComplianceAutomation-${suffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        EXTERNAL_ID: externalId,
        MEMBER_ACCOUNTS: memberAccountIds.join(','),
        CROSS_ACCOUNT_ROLE_NAME: this.crossAccountRoleName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Process Systems Manager compliance events and create Security Hub findings
    """
    
    # Initialize AWS clients
    sts = boto3.client('sts')
    securityhub = boto3.client('securityhub')
    
    # Get environment variables
    external_id = os.environ['EXTERNAL_ID']
    member_accounts = os.environ['MEMBER_ACCOUNTS'].split(',')
    role_name = os.environ['CROSS_ACCOUNT_ROLE_NAME']
    
    # Parse the EventBridge event
    detail = event.get('detail', {})
    account_id = event.get('account')
    region = event.get('region')
    
    print(f"Processing compliance event for account: {account_id}")
    
    # Process compliance change event
    if detail.get('eventName') in ['PutComplianceItems', 'DeleteComplianceItems']:
        findings = []
        
        try:
            # Assume role in member account to get detailed compliance data
            if account_id in member_accounts:
                role_arn = f"arn:aws:iam::{account_id}:role/{role_name}"
                
                try:
                    assumed_role = sts.assume_role(
                        RoleArn=role_arn,
                        RoleSessionName='ComplianceProcessing',
                        ExternalId=external_id
                    )
                    
                    # Create client with assumed role credentials
                    member_ssm = boto3.client(
                        'ssm',
                        aws_access_key_id=assumed_role['Credentials']['AccessKeyId'],
                        aws_secret_access_key=assumed_role['Credentials']['SecretAccessKey'],
                        aws_session_token=assumed_role['Credentials']['SessionToken'],
                        region_name=region
                    )
                    
                    # Get compliance summary
                    compliance_summary = member_ssm.get_compliance_summary()
                    non_compliant_count = compliance_summary.get('NonCompliantSummary', {}).get('NonCompliantCount', 0)
                    
                    if non_compliant_count > 0:
                        # Create Security Hub finding for compliance violation
                        finding = {
                            'SchemaVersion': '2018-10-08',
                            'Id': f"compliance-{account_id}-{uuid.uuid4()}",
                            'ProductArn': f"arn:aws:securityhub:{region}::product/aws/systems-manager",
                            'GeneratorId': 'ComplianceMonitoring',
                            'AwsAccountId': account_id,
                            'Types': ['Software and Configuration Checks/Vulnerabilities/CVE'],
                            'CreatedAt': datetime.utcnow().isoformat() + 'Z',
                            'UpdatedAt': datetime.utcnow().isoformat() + 'Z',
                            'Severity': {
                                'Label': 'HIGH' if non_compliant_count > 10 else 'MEDIUM'
                            },
                            'Title': 'Systems Manager Compliance Violation Detected',
                            'Description': f"Found {non_compliant_count} compliance violations in account {account_id}",
                            'Resources': [
                                {
                                    'Type': 'AwsAccount',
                                    'Id': f"AWS::::Account:{account_id}",
                                    'Region': region
                                }
                            ],
                            'Compliance': {
                                'Status': 'FAILED'
                            },
                            'WorkflowState': 'NEW'
                        }
                        
                        findings.append(finding)
                
                except Exception as role_error:
                    print(f"Error assuming role in account {account_id}: {str(role_error)}")
                    # Create finding for role assumption failure
                    finding = {
                        'SchemaVersion': '2018-10-08',
                        'Id': f"compliance-access-error-{account_id}-{uuid.uuid4()}",
                        'ProductArn': f"arn:aws:securityhub:{region}::product/aws/systems-manager",
                        'GeneratorId': 'ComplianceMonitoring',
                        'AwsAccountId': account_id,
                        'Types': ['Software and Configuration Checks/AWS Security Best Practices'],
                        'CreatedAt': datetime.utcnow().isoformat() + 'Z',
                        'UpdatedAt': datetime.utcnow().isoformat() + 'Z',
                        'Severity': {
                            'Label': 'MEDIUM'
                        },
                        'Title': 'Cross-Account Compliance Access Error',
                        'Description': f"Unable to access compliance data in account {account_id}: {str(role_error)}",
                        'Resources': [
                            {
                                'Type': 'AwsAccount',
                                'Id': f"AWS::::Account:{account_id}",
                                'Region': region
                            }
                        ],
                        'Compliance': {
                            'Status': 'WARNING'
                        },
                        'WorkflowState': 'NEW'
                    }
                    findings.append(finding)
            
            # Import findings into Security Hub
            if findings:
                response = securityhub.batch_import_findings(
                    Findings=findings
                )
                print(f"Imported {len(findings)} findings to Security Hub")
                print(f"Response: {response}")
            
        except Exception as e:
            print(f"Error processing compliance event: {str(e)}")
            raise
    
    return {
        'statusCode': 200,
        'body': json.dumps('Compliance event processed successfully')
    }
      `)
    });

    return complianceFunction;
  }

  /**
   * Creates EventBridge rules for compliance automation
   */
  private createEventBridgeRules(suffix: string): void {
    // Rule for Systems Manager compliance events
    const complianceRule = new events.Rule(this, 'ComplianceMonitoringRule', {
      ruleName: `ComplianceMonitoringRule-${suffix}`,
      description: 'Trigger compliance processing on SSM compliance changes',
      eventPattern: {
        source: ['aws.ssm'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventName: ['PutComplianceItems', 'DeleteComplianceItems']
        }
      },
      enabled: true
    });

    // Add Lambda as target
    complianceRule.addTarget(new targets.LambdaFunction(this.complianceLambda));

    // Rule for Security Hub findings
    const findingsRule = new events.Rule(this, 'SecurityHubFindingsRule', {
      ruleName: `SecurityHubFindingsRule-${suffix}`,
      description: 'Process Security Hub compliance findings',
      eventPattern: {
        source: ['aws.securityhub'],
        detailType: ['Security Hub Findings - Imported'],
        detail: {
          findings: {
            ProductArn: [{ prefix: 'arn:aws:securityhub' }],
            Compliance: {
              Status: ['FAILED']
            }
          }
        }
      },
      enabled: true
    });

    // Add Lambda as target for findings rule
    findingsRule.addTarget(new targets.LambdaFunction(this.complianceLambda));
  }

  /**
   * Creates Systems Manager document for custom compliance checks
   */
  private createCustomComplianceDocument(suffix: string): void {
    new ssm.CfnDocument(this, 'CustomComplianceDocument', {
      name: `CustomComplianceCheck-${suffix}`,
      documentType: 'Command',
      documentFormat: 'YAML',
      content: {
        schemaVersion: '2.2',
        description: 'Custom compliance check for organizational policies',
        parameters: {
          complianceType: {
            type: 'String',
            description: 'Type of compliance check to perform',
            default: 'Custom:OrganizationalPolicy'
          }
        },
        mainSteps: [
          {
            action: 'aws:runShellScript',
            name: 'runComplianceCheck',
            inputs: {
              runCommand: [
                '#!/bin/bash',
                'echo "Running custom compliance check for organizational policies"',
                'INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)',
                'COMPLIANCE_TYPE="{{ complianceType }}"',
                'COMPLIANCE_STATUS="COMPLIANT"',
                'COMPLIANCE_DETAILS=""',
                '',
                '# Check for required tags',
                'REQUIRED_TAGS=("Environment" "Owner" "Project")',
                '',
                'for tag in "${REQUIRED_TAGS[@]}"; do',
                '    TAG_VALUE=$(aws ec2 describe-tags \\',
                '        --filters "Name=resource-id,Values=${INSTANCE_ID}" "Name=key,Values=${tag}" \\',
                '        --query "Tags[0].Value" --output text)',
                '    ',
                '    if [ "$TAG_VALUE" = "None" ] || [ -z "$TAG_VALUE" ]; then',
                '        COMPLIANCE_STATUS="NON_COMPLIANT"',
                '        COMPLIANCE_DETAILS="${COMPLIANCE_DETAILS}Missing required tag: ${tag}; "',
                '    fi',
                'done',
                '',
                '# Report compliance status to Systems Manager',
                'aws ssm put-compliance-items \\',
                '    --resource-id ${INSTANCE_ID} \\',
                '    --resource-type "ManagedInstance" \\',
                '    --compliance-type ${COMPLIANCE_TYPE} \\',
                '    --execution-summary "ExecutionTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\',
                '    --items "Id=TagCompliance,Title=Required Tags Check,Severity=HIGH,Status=${COMPLIANCE_STATUS},Details={\\"Details\\":\\"${COMPLIANCE_DETAILS}\\"}"',
                '',
                'echo "Custom compliance check completed: ${COMPLIANCE_STATUS}"'
              ]
            }
          }
        ]
      },
      tags: [
        { key: 'Purpose', value: 'ComplianceMonitoring' },
        { key: 'Type', value: 'CustomCheck' }
      ]
    });
  }

  /**
   * Creates IAM role template for member accounts
   */
  private createCrossAccountRoleTemplate(externalId: string): void {
    // Create a CloudFormation template for member accounts
    const memberAccountTemplate = {
      AWSTemplateFormatVersion: '2010-09-09',
      Description: 'Cross-account role for Security Hub compliance monitoring',
      Parameters: {
        SecurityAccountId: {
          Type: 'String',
          Description: 'Security Hub administrator account ID',
          Default: this.account
        },
        ExternalId: {
          Type: 'String',
          Description: 'External ID for cross-account access',
          Default: externalId
        },
        RoleName: {
          Type: 'String',
          Description: 'Name of the cross-account role',
          Default: this.crossAccountRoleName
        }
      },
      Resources: {
        CrossAccountRole: {
          Type: 'AWS::IAM::Role',
          Properties: {
            RoleName: { Ref: 'RoleName' },
            AssumeRolePolicyDocument: {
              Version: '2012-10-17',
              Statement: [
                {
                  Effect: 'Allow',
                  Principal: {
                    AWS: { 'Fn::Sub': 'arn:aws:iam::${SecurityAccountId}:root' }
                  },
                  Action: 'sts:AssumeRole',
                  Condition: {
                    StringEquals: {
                      'sts:ExternalId': { Ref: 'ExternalId' }
                    }
                  }
                }
              ]
            },
            Policies: [
              {
                PolicyName: 'ComplianceAccessPolicy',
                PolicyDocument: {
                  Version: '2012-10-17',
                  Statement: [
                    {
                      Effect: 'Allow',
                      Action: [
                        'ssm:ListComplianceItems',
                        'ssm:ListResourceComplianceSummaries',
                        'ssm:GetComplianceSummary',
                        'ssm:DescribeInstanceInformation',
                        'ssm:DescribeInstanceAssociations',
                        'securityhub:BatchImportFindings',
                        'securityhub:BatchUpdateFindings'
                      ],
                      Resource: '*'
                    }
                  ]
                }
              }
            ],
            Tags: [
              { Key: 'Purpose', Value: 'ComplianceMonitoring' },
              { Key: 'CreatedBy', Value: 'CrossAccountComplianceCDK' }
            ]
          }
        }
      },
      Outputs: {
        RoleArn: {
          Description: 'ARN of the cross-account role',
          Value: { 'Fn::GetAtt': ['CrossAccountRole', 'Arn'] }
        }
      }
    };

    // Store template as SSM parameter for easy access
    new ssm.StringParameter(this, 'MemberAccountTemplate', {
      parameterName: `/compliance-monitoring/member-account-template`,
      stringValue: JSON.stringify(memberAccountTemplate, null, 2),
      description: 'CloudFormation template for member account cross-account role setup',
      tier: ssm.ParameterTier.ADVANCED
    });
  }

  /**
   * Creates stack outputs
   */
  private createOutputs(memberAccountIds: string[], externalId: string): void {
    new cdk.CfnOutput(this, 'SecurityHubArn', {
      value: this.securityHub.attrArn,
      description: 'ARN of the Security Hub instance'
    });

    new cdk.CfnOutput(this, 'ComplianceLambdaArn', {
      value: this.complianceLambda.functionArn,
      description: 'ARN of the compliance processing Lambda function'
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.cloudTrail.trailArn,
      description: 'ARN of the compliance audit CloudTrail'
    });

    new cdk.CfnOutput(this, 'CrossAccountRoleName', {
      value: this.crossAccountRoleName,
      description: 'Name of the cross-account role to create in member accounts'
    });

    new cdk.CfnOutput(this, 'ExternalId', {
      value: externalId,
      description: 'External ID for cross-account role assumption'
    });

    new cdk.CfnOutput(this, 'MemberAccountIds', {
      value: memberAccountIds.join(','),
      description: 'List of member account IDs being monitored'
    });

    new cdk.CfnOutput(this, 'MemberAccountTemplateParameter', {
      value: '/compliance-monitoring/member-account-template',
      description: 'SSM parameter containing CloudFormation template for member accounts'
    });

    new cdk.CfnOutput(this, 'DeploymentInstructions', {
      value: [
        '1. Deploy this stack in the Security Hub administrator account',
        '2. Retrieve the member account CloudFormation template from SSM parameter',
        '3. Deploy the template in each member account',
        '4. Configure Security Hub member relationships',
        '5. Enable Systems Manager compliance scanning in member accounts'
      ].join(' | '),
      description: 'High-level deployment instructions'
    });
  }
}

/**
 * CDK App
 */
const app = new cdk.App();

// Get configuration from context or environment variables
const memberAccountIds = app.node.tryGetContext('memberAccountIds') || 
  process.env.MEMBER_ACCOUNT_IDS?.split(',') || 
  ['123456789013', '123456789014']; // Default example account IDs

const externalId = app.node.tryGetContext('externalId') || 
  process.env.EXTERNAL_ID || 
  'ComplianceMonitoring-' + Math.random().toString(36).substring(7);

const enableOrganizationAdmin = app.node.tryGetContext('enableOrganizationAdmin') !== false;

// Create the main stack
new CrossAccountComplianceStack(app, 'CrossAccountComplianceStack', {
  memberAccountIds,
  externalId,
  enableOrganizationAdmin,
  description: 'Cross-account compliance monitoring with Systems Manager and Security Hub',
  tags: {
    Purpose: 'ComplianceMonitoring',
    Solution: 'CrossAccountCompliance',
    ManagedBy: 'CDK'
  }
});

app.synth();