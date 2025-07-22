#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as config from 'aws-cdk-lib/aws-config';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * CDK Stack for Auto-Remediation with AWS Config and Lambda
 * 
 * This stack implements automated compliance remediation using:
 * - AWS Config for continuous monitoring and evaluation
 * - Lambda functions for custom remediation actions
 * - Systems Manager for standardized automation
 * - SNS for notifications and alerts
 * - CloudWatch for monitoring and dashboards
 */
export class AutoRemediationConfigLambdaStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);

    // =====================================================
    // S3 Bucket for AWS Config
    // =====================================================
    
    const configBucket = new s3.Bucket(this, 'ConfigBucket', {
      bucketName: `aws-config-bucket-${randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
        },
      ],
    });

    // =====================================================
    // IAM Role for AWS Config Service
    // =====================================================
    
    const configServiceRole = new iam.Role(this, 'ConfigServiceRole', {
      roleName: `AWSConfigRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
      description: 'IAM role for AWS Config service to monitor resources',
    });

    // Grant Config service permission to write to S3 bucket
    configBucket.grantReadWrite(configServiceRole);
    configBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketPermissionsCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:GetBucketAcl', 's3:ListBucket'],
        resources: [configBucket.bucketArn],
        conditions: {
          StringEquals: {
            'AWS:SourceAccount': this.account,
          },
        },
      })
    );

    configBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketDelivery',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [configBucket.arnForObjects(`AWSLogs/${this.account}/Config/*`)],
        conditions: {
          StringEquals: {
            's3:x-amz-acl': 'bucket-owner-full-control',
            'AWS:SourceAccount': this.account,
          },
        },
      })
    );

    // =====================================================
    // SNS Topic for Notifications
    // =====================================================
    
    const notificationTopic = new sns.Topic(this, 'ComplianceAlertsTopic', {
      topicName: `config-compliance-alerts-${randomSuffix}`,
      displayName: 'Config Compliance Alerts',
      description: 'SNS topic for AWS Config compliance notifications and remediation alerts',
    });

    // =====================================================
    // IAM Role for Lambda Remediation Functions
    // =====================================================
    
    const lambdaRemediationRole = new iam.Role(this, 'LambdaRemediationRole', {
      roleName: `ConfigRemediationRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      description: 'IAM role for Lambda functions performing automated remediation',
    });

    // Add custom policy for remediation actions
    const remediationPolicy = new iam.Policy(this, 'RemediationPolicy', {
      policyName: `ConfigRemediationPolicy-${randomSuffix}`,
      statements: [
        // EC2 Security Group remediation permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            'ec2:DescribeSecurityGroups',
            'ec2:AuthorizeSecurityGroupIngress',
            'ec2:RevokeSecurityGroupIngress',
            'ec2:AuthorizeSecurityGroupEgress',
            'ec2:RevokeSecurityGroupEgress',
            'ec2:CreateTags',
          ],
          resources: ['*'],
        }),
        // S3 bucket remediation permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: [
            's3:GetBucketAcl',
            's3:GetBucketPolicy',
            's3:PutBucketAcl',
            's3:PutBucketPolicy',
            's3:DeleteBucketPolicy',
            's3:PutPublicAccessBlock',
          ],
          resources: ['*'],
        }),
        // Config service permissions
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['config:PutEvaluations'],
          resources: ['*'],
        }),
        // SNS permissions for notifications
        new iam.PolicyStatement({
          effect: iam.Effect.ALLOW,
          actions: ['sns:Publish'],
          resources: [notificationTopic.topicArn],
        }),
      ],
    });

    lambdaRemediationRole.attachInlinePolicy(remediationPolicy);

    // =====================================================
    // Lambda Function for Security Group Remediation
    // =====================================================
    
    const securityGroupRemediationFunction = new lambda.Function(this, 'SecurityGroupRemediationFunction', {
      functionName: `SecurityGroupRemediation-${randomSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRemediationRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      description: 'Auto-remediate security groups with unrestricted access',
      environment: {
        SNS_TOPIC_ARN: notificationTopic.topicArn,
        LOG_LEVEL: 'INFO',
      },
      logRetention: logs.RetentionDays.ONE_MONTH,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

ec2 = boto3.client('ec2')
sns = boto3.client('sns')

def lambda_handler(event, context):
    """
    Remediate security groups that allow unrestricted access (0.0.0.0/0)
    """
    
    try:
        # Parse the Config rule evaluation
        config_item = event['configurationItem']
        resource_id = config_item['resourceId']
        resource_type = config_item['resourceType']
        
        logger.info(f"Processing remediation for {resource_type}: {resource_id}")
        
        if resource_type != 'AWS::EC2::SecurityGroup':
            return {
                'statusCode': 400,
                'body': json.dumps('This function only handles Security Groups')
            }
        
        # Get security group details
        response = ec2.describe_security_groups(GroupIds=[resource_id])
        security_group = response['SecurityGroups'][0]
        
        remediation_actions = []
        
        # Check inbound rules for unrestricted access
        for rule in security_group['IpPermissions']:
            for ip_range in rule.get('IpRanges', []):
                if ip_range.get('CidrIp') == '0.0.0.0/0':
                    # Remove unrestricted inbound rule
                    try:
                        ec2.revoke_security_group_ingress(
                            GroupId=resource_id,
                            IpPermissions=[rule]
                        )
                        remediation_actions.append(f"Removed unrestricted inbound rule: {rule}")
                        logger.info(f"Removed unrestricted inbound rule from {resource_id}")
                    except Exception as e:
                        logger.error(f"Failed to remove inbound rule: {e}")
        
        # Add tag to indicate remediation
        ec2.create_tags(
            Resources=[resource_id],
            Tags=[
                {
                    'Key': 'AutoRemediated',
                    'Value': 'true'
                },
                {
                    'Key': 'RemediationDate',
                    'Value': datetime.now().isoformat()
                }
            ]
        )
        
        # Send notification if remediation occurred
        if remediation_actions:
            message = {
                'resource_id': resource_id,
                'resource_type': resource_type,
                'remediation_actions': remediation_actions,
                'timestamp': datetime.now().isoformat()
            }
            
            # Publish to SNS topic
            topic_arn = os.environ.get('SNS_TOPIC_ARN')
            if topic_arn:
                sns.publish(
                    TopicArn=topic_arn,
                    Subject=f'Security Group Auto-Remediation: {resource_id}',
                    Message=json.dumps(message, indent=2)
                )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Remediation completed',
                'resource_id': resource_id,
                'actions_taken': len(remediation_actions)
            })
        }
        
    except Exception as e:
        logger.error(f"Error in remediation: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }
`),
    });

    // Grant the function permission to be invoked by Config
    securityGroupRemediationFunction.addPermission('ConfigInvokePermission', {
      principal: new iam.ServicePrincipal('config.amazonaws.com'),
      action: 'lambda:InvokeFunction',
    });

    // =====================================================
    // AWS Config Configuration Recorder
    // =====================================================
    
    const configurationRecorder = new config.CfnConfigurationRecorder(this, 'ConfigurationRecorder', {
      name: 'default',
      roleArn: configServiceRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
        resourceTypes: [],
      },
    });

    // =====================================================
    // AWS Config Delivery Channel
    // =====================================================
    
    const deliveryChannel = new config.CfnDeliveryChannel(this, 'DeliveryChannel', {
      name: 'default',
      s3BucketName: configBucket.bucketName,
    });

    // Ensure delivery channel is created after configuration recorder
    deliveryChannel.addDependency(configurationRecorder);

    // =====================================================
    // Config Rules for Compliance Monitoring
    // =====================================================
    
    // Security Group SSH Rule
    const sshSecurityGroupRule = new config.CfnConfigRule(this, 'SecurityGroupSshRestrictedRule', {
      configRuleName: 'security-group-ssh-restricted',
      description: 'Checks if security groups allow unrestricted SSH access',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'INCOMING_SSH_DISABLED',
      },
      scope: {
        complianceResourceTypes: ['AWS::EC2::SecurityGroup'],
      },
    });

    // Ensure rule is created after configuration recorder
    sshSecurityGroupRule.addDependency(configurationRecorder);

    // S3 Bucket Public Access Rule
    const s3PublicAccessRule = new config.CfnConfigRule(this, 'S3BucketPublicAccessRule', {
      configRuleName: 's3-bucket-public-access-prohibited',
      description: 'Checks if S3 buckets allow public access',
      source: {
        owner: 'AWS',
        sourceIdentifier: 'S3_BUCKET_PUBLIC_ACCESS_PROHIBITED',
      },
      scope: {
        complianceResourceTypes: ['AWS::S3::Bucket'],
      },
    });

    // Ensure rule is created after configuration recorder
    s3PublicAccessRule.addDependency(configurationRecorder);

    // =====================================================
    // Systems Manager Automation Document for S3 Remediation
    // =====================================================
    
    const s3RemediationDocument = new ssm.CfnDocument(this, 'S3RemediationDocument', {
      name: `S3-RemediatePublicAccess-${randomSuffix}`,
      documentType: 'Automation',
      documentFormat: 'JSON',
      content: {
        schemaVersion: '0.3',
        description: 'Remediate S3 bucket public access',
        assumeRole: lambdaRemediationRole.roleArn,
        parameters: {
          BucketName: {
            type: 'String',
            description: 'Name of the S3 bucket to remediate',
          },
        },
        mainSteps: [
          {
            name: 'RemediateS3PublicAccess',
            action: 'aws:executeAwsApi',
            inputs: {
              Service: 's3',
              Api: 'PutPublicAccessBlock',
              BucketName: '{{ BucketName }}',
              PublicAccessBlockConfiguration: {
                BlockPublicAcls: true,
                IgnorePublicAcls: true,
                BlockPublicPolicy: true,
                RestrictPublicBuckets: true,
              },
            },
          },
        ],
      },
    });

    // =====================================================
    // Auto-Remediation Configuration
    // =====================================================
    
    const securityGroupRemediation = new config.CfnRemediationConfiguration(this, 'SecurityGroupRemediationConfig', {
      configRuleName: sshSecurityGroupRule.configRuleName!,
      targetType: 'SSM_DOCUMENT',
      targetId: 'AWSConfigRemediation-RemoveUnrestrictedSourceInSecurityGroup',
      targetVersion: '1',
      parameters: {
        AutomationAssumeRole: {
          StaticValue: {
            Values: [lambdaRemediationRole.roleArn],
          },
        },
        GroupId: {
          ResourceValue: {
            Value: 'RESOURCE_ID',
          },
        },
      },
      automatic: true,
      maximumAutomaticAttempts: 3,
    });

    // Ensure remediation is configured after the rule
    securityGroupRemediation.addDependency(sshSecurityGroupRule);

    // =====================================================
    // CloudWatch Dashboard for Compliance Monitoring
    // =====================================================
    
    const complianceDashboard = new cloudwatch.Dashboard(this, 'ComplianceDashboard', {
      dashboardName: `Config-Compliance-Dashboard-${randomSuffix}`,
    });

    // Add Config Rule Compliance widget
    complianceDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Config Rule Compliance Status',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 'security-group-ssh-restricted',
              ComplianceType: 'COMPLIANT',
            },
            statistic: 'Maximum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 'security-group-ssh-restricted',
              ComplianceType: 'NON_COMPLIANT',
            },
            statistic: 'Maximum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 's3-bucket-public-access-prohibited',
              ComplianceType: 'COMPLIANT',
            },
            statistic: 'Maximum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/Config',
            metricName: 'ComplianceByConfigRule',
            dimensionsMap: {
              ConfigRuleName: 's3-bucket-public-access-prohibited',
              ComplianceType: 'NON_COMPLIANT',
            },
            statistic: 'Maximum',
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add Lambda Function metrics widget
    complianceDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Remediation Function Metrics',
        left: [
          securityGroupRemediationFunction.metricInvocations(),
          securityGroupRemediationFunction.metricErrors(),
        ],
        right: [
          securityGroupRemediationFunction.metricDuration(),
        ],
        width: 12,
        height: 6,
      })
    );

    // =====================================================
    // CloudFormation Outputs
    // =====================================================
    
    new cdk.CfnOutput(this, 'ConfigBucketName', {
      value: configBucket.bucketName,
      description: 'S3 bucket for AWS Config configuration snapshots',
      exportName: `${this.stackName}-ConfigBucket`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for compliance notifications',
      exportName: `${this.stackName}-SNSTopic`,
    });

    new cdk.CfnOutput(this, 'SecurityGroupRemediationFunctionArn', {
      value: securityGroupRemediationFunction.functionArn,
      description: 'Lambda function for security group remediation',
      exportName: `${this.stackName}-SGRemediationFunction`,
    });

    new cdk.CfnOutput(this, 'ComplianceDashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${complianceDashboard.dashboardName}`,
      description: 'CloudWatch dashboard for compliance monitoring',
      exportName: `${this.stackName}-Dashboard`,
    });

    new cdk.CfnOutput(this, 'ConfigServiceRoleArn', {
      value: configServiceRole.roleArn,
      description: 'IAM role for AWS Config service',
      exportName: `${this.stackName}-ConfigRole`,
    });

    new cdk.CfnOutput(this, 'LambdaRemediationRoleArn', {
      value: lambdaRemediationRole.roleArn,
      description: 'IAM role for Lambda remediation functions',
      exportName: `${this.stackName}-LambdaRole`,
    });
  }
}

// =====================================================
// CDK Application
// =====================================================

const app = new cdk.App();

new AutoRemediationConfigLambdaStack(app, 'AutoRemediationConfigLambdaStack', {
  description: 'Auto-remediation with AWS Config and Lambda - Automated compliance remediation system',
  tags: {
    Project: 'AutoRemediation',
    Environment: 'Development',
    Service: 'Config',
    Owner: 'DevOps',
  },
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

app.synth();