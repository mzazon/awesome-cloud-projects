import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as cloudformation from 'aws-cdk-lib/aws-cloudformation';
import * as cr from 'aws-cdk-lib/custom-resources';
import { Construct } from 'constructs';

export interface ExecutionRoleStackProps extends cdk.StackProps {
  managementAccountId: string;
  stackSetName: string;
  templateBucket?: string;
  targetAccounts: string[];
}

/**
 * Stack for managing CloudFormation StackSet execution roles
 * 
 * This stack creates:
 * - CloudFormation template for execution roles
 * - StackSet for deploying execution roles to target accounts
 * - Template storage and management
 */
export class ExecutionRoleStack extends cdk.Stack {
  public readonly executionRoleTemplate: string;
  public readonly executionRoleStackSet: cloudformation.CfnStackSet;
  public readonly templateBucket?: s3.Bucket;

  constructor(scope: Construct, id: string, props: ExecutionRoleStackProps) {
    super(scope, id, props);

    // Create execution role template
    this.executionRoleTemplate = this.createExecutionRoleTemplate();

    // Create or get template bucket
    if (props.templateBucket) {
      this.templateBucket = s3.Bucket.fromBucketName(this, 'TemplateBucket', props.templateBucket);
    } else {
      this.templateBucket = this.createTemplateBucket();
    }

    // Deploy template to S3
    this.deployTemplateToS3();

    // Create StackSet for execution roles
    this.executionRoleStackSet = this.createExecutionRoleStackSet(props);

    // Create outputs
    this.createOutputs();
  }

  /**
   * Create CloudFormation template for execution roles
   */
  private createExecutionRoleTemplate(): string {
    const template = {
      AWSTemplateFormatVersion: '2010-09-09',
      Description: 'StackSet execution role for target accounts',
      
      Metadata: {
        'AWS::CloudFormation::Interface': {
          ParameterGroups: [
            {
              Label: { default: 'StackSet Configuration' },
              Parameters: ['AdministratorAccountId'],
            },
          ],
          ParameterLabels: {
            AdministratorAccountId: { default: 'Administrator Account ID' },
          },
        },
      },

      Parameters: {
        AdministratorAccountId: {
          Type: 'String',
          Description: 'AWS account ID of the StackSet administrator account',
          AllowedPattern: '^[0-9]{12}$',
          ConstraintDescription: 'Must be a valid 12-digit AWS account ID',
        },
      },

      Resources: {
        ExecutionRole: {
          Type: 'AWS::IAM::Role',
          Properties: {
            RoleName: 'AWSCloudFormationStackSetExecutionRole',
            Description: 'Execution role for CloudFormation StackSets',
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
                  Condition: {
                    StringEquals: {
                      'aws:SourceAccount': { Ref: 'AdministratorAccountId' },
                    },
                  },
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
                      Action: [
                        // CloudFormation permissions
                        'cloudformation:*',
                        // IAM permissions for role and policy management
                        'iam:*',
                        // S3 permissions for audit logging
                        's3:*',
                        // CloudTrail permissions
                        'cloudtrail:*',
                        // GuardDuty permissions
                        'guardduty:*',
                        // AWS Config permissions
                        'config:*',
                        // CloudWatch permissions
                        'logs:*',
                        'cloudwatch:*',
                        // KMS permissions for encryption
                        'kms:*',
                        // SNS permissions for notifications
                        'sns:*',
                        // Organizations permissions (read-only)
                        'organizations:Describe*',
                        'organizations:List*',
                        // EC2 permissions for VPC resources
                        'ec2:Describe*',
                        'ec2:CreateTags',
                        'ec2:DeleteTags',
                        // Additional permissions for comprehensive governance
                        'events:*',
                        'lambda:*',
                        'apigateway:*',
                        'application-autoscaling:*',
                        'autoscaling:*',
                        'backup:*',
                        'rds:*',
                        'dynamodb:*',
                        'elasticloadbalancing:*',
                        'route53:*',
                        'acm:*',
                        'secretsmanager:*',
                        'ssm:*',
                        'support:*',
                        'trustedadvisor:*',
                        'wellarchitected:*',
                      ],
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
              {
                Key: 'CreatedBy',
                Value: 'CDK',
              },
            ],
          },
        },

        // CloudWatch Log Group for execution role activities
        ExecutionRoleLogGroup: {
          Type: 'AWS::Logs::LogGroup',
          Properties: {
            LogGroupName: '/aws/iam/stackset-execution-role',
            RetentionInDays: 30,
            Tags: [
              {
                Key: 'Purpose',
                Value: 'StackSetExecution',
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
        ExecutionRoleName: {
          Description: 'Name of the execution role',
          Value: { Ref: 'ExecutionRole' },
          Export: {
            Name: {
              'Fn::Sub': '${AWS::StackName}-ExecutionRoleName',
            },
          },
        },
        LogGroupArn: {
          Description: 'ARN of the CloudWatch Log Group',
          Value: {
            'Fn::GetAtt': ['ExecutionRoleLogGroup', 'Arn'],
          },
          Export: {
            Name: {
              'Fn::Sub': '${AWS::StackName}-LogGroupArn',
            },
          },
        },
      },
    };

    return JSON.stringify(template, null, 2);
  }

  /**
   * Create S3 bucket for templates
   */
  private createTemplateBucket(): s3.Bucket {
    const bucket = new s3.Bucket(this, 'ExecutionRoleTemplateBucket', {
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

    cdk.Tags.of(bucket).add('Purpose', 'ExecutionRoleTemplates');

    return bucket;
  }

  /**
   * Deploy template to S3
   */
  private deployTemplateToS3(): void {
    if (!this.templateBucket) return;

    // Create the template file locally and deploy to S3
    const deployment = new s3deploy.BucketDeployment(this, 'DeployExecutionRoleTemplate', {
      sources: [
        s3deploy.Source.data(
          'stackset-execution-role-template.yaml',
          this.executionRoleTemplate
        ),
      ],
      destinationBucket: this.templateBucket,
      destinationKeyPrefix: 'execution-roles/',
      retainOnDelete: false,
    });

    cdk.Tags.of(deployment).add('Purpose', 'TemplateDeployment');
  }

  /**
   * Create StackSet for execution roles
   */
  private createExecutionRoleStackSet(props: ExecutionRoleStackProps): cloudformation.CfnStackSet {
    const stackSet = new cloudformation.CfnStackSet(this, 'ExecutionRoleStackSet', {
      stackSetName: props.stackSetName,
      description: 'Deploy StackSet execution roles to target accounts',
      templateBody: this.executionRoleTemplate,
      parameters: [
        {
          parameterKey: 'AdministratorAccountId',
          parameterValue: props.managementAccountId,
        },
      ],
      capabilities: ['CAPABILITY_NAMED_IAM'],
      permissionModel: 'SELF_MANAGED',
      operationPreferences: {
        regionConcurrencyType: 'PARALLEL',
        maxConcurrentPercentage: 100,
        failureTolerancePercentage: 0,
      },
      tags: [
        {
          key: 'Purpose',
          value: 'ExecutionRoles',
        },
        {
          key: 'ManagedBy',
          value: 'CDK',
        },
        {
          key: 'StackSetType',
          value: 'ExecutionRoles',
        },
      ],
    });

    return stackSet;
  }

  /**
   * Create stack outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'ExecutionRoleStackSetName', {
      description: 'Name of the execution role StackSet',
      value: this.executionRoleStackSet.stackSetName!,
      exportName: `${this.stackName}-ExecutionRoleStackSetName`,
    });

    new cdk.CfnOutput(this, 'ExecutionRoleStackSetArn', {
      description: 'ARN of the execution role StackSet',
      value: this.executionRoleStackSet.attrStackSetId,
      exportName: `${this.stackName}-ExecutionRoleStackSetArn`,
    });

    if (this.templateBucket) {
      new cdk.CfnOutput(this, 'ExecutionRoleTemplateBucket', {
        description: 'S3 bucket containing execution role templates',
        value: this.templateBucket.bucketName,
        exportName: `${this.stackName}-ExecutionRoleTemplateBucket`,
      });

      new cdk.CfnOutput(this, 'ExecutionRoleTemplateUrl', {
        description: 'S3 URL of the execution role template',
        value: `https://${this.templateBucket.bucketName}.s3.${this.region}.amazonaws.com/execution-roles/stackset-execution-role-template.yaml`,
        exportName: `${this.stackName}-ExecutionRoleTemplateUrl`,
      });
    }

    new cdk.CfnOutput(this, 'ExecutionRoleTemplate', {
      description: 'CloudFormation template for execution roles (JSON format)',
      value: this.executionRoleTemplate,
    });
  }
}