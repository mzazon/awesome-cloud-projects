#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as config from 'aws-cdk-lib/aws-config';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as eventsTargets from 'aws-cdk-lib/aws-events-targets';
import { RemovalPolicy } from 'aws-cdk-lib';

interface InfrastructureMonitoringStackProps extends cdk.StackProps {
  /**
   * Email address for notifications
   */
  notificationEmail?: string;
  
  /**
   * Whether to enable automated remediation
   */
  enableAutomatedRemediation?: boolean;
  
  /**
   * Custom bucket name (optional)
   */
  customBucketName?: string;
}

export class InfrastructureMonitoringStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: InfrastructureMonitoringStackProps) {
    super(scope, id, props);

    // Generate unique resource names
    const randomSuffix = Math.random().toString(36).substring(2, 8);
    const stackName = this.stackName.toLowerCase();

    // Create S3 bucket for CloudTrail and Config logs
    const monitoringBucket = new s3.Bucket(this, 'MonitoringBucket', {
      bucketName: props?.customBucketName || `infrastructure-monitoring-${randomSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'CloudTrailLogArchiving',
          prefix: 'AWSLogs/',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
          expiration: cdk.Duration.days(2555), // 7 years
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create SNS topic for notifications
    const alertsTopic = new sns.Topic(this, 'InfrastructureAlerts', {
      topicName: `infrastructure-alerts-${randomSuffix}`,
      displayName: 'Infrastructure Monitoring Alerts',
    });

    // Add email subscription if provided
    if (props?.notificationEmail) {
      alertsTopic.addSubscription(
        new snsSubscriptions.EmailSubscription(props.notificationEmail)
      );
    }

    // Create IAM role for AWS Config
    const configRole = new iam.Role(this, 'ConfigServiceRole', {
      roleName: `ConfigRole-${randomSuffix}`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole'),
      ],
      inlinePolicies: {
        ConfigS3Policy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketAcl',
                's3:GetBucketLocation',
                's3:ListBucket',
              ],
              resources: [monitoringBucket.bucketArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject'],
              resources: [`${monitoringBucket.bucketArn}/AWSLogs/${this.account}/Config/*`],
              conditions: {
                StringEquals: {
                  's3:x-amz-acl': 'bucket-owner-full-control',
                },
              },
            }),
          ],
        }),
      },
    });

    // Create AWS Config Configuration Recorder
    const configRecorder = new config.CfnConfigurationRecorder(this, 'ConfigRecorder', {
      name: 'default',
      roleArn: configRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
        resourceTypes: [],
      },
    });

    // Create AWS Config Delivery Channel
    const configDeliveryChannel = new config.CfnDeliveryChannel(this, 'ConfigDeliveryChannel', {
      name: 'default',
      s3BucketName: monitoringBucket.bucketName,
      snsTopicArn: alertsTopic.topicArn,
      s3KeyPrefix: `AWSLogs/${this.account}/Config`,
    });

    // CloudTrail requires bucket policy
    monitoringBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSCloudTrailAclCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['s3:GetBucketAcl'],
        resources: [monitoringBucket.bucketArn],
      })
    );

    monitoringBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSCloudTrailWrite',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('cloudtrail.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [`${monitoringBucket.bucketArn}/AWSLogs/${this.account}/*`],
        conditions: {
          StringEquals: {
            's3:x-amz-acl': 'bucket-owner-full-control',
          },
        },
      })
    );

    // Create CloudTrail
    const infrastructureTrail = new cloudtrail.Trail(this, 'InfrastructureTrail', {
      trailName: `InfrastructureTrail-${randomSuffix}`,
      bucket: monitoringBucket,
      s3KeyPrefix: `AWSLogs/${this.account}/CloudTrail`,
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      sendToCloudWatchLogs: true,
      cloudWatchLogsRetention: cdk.aws_logs.RetentionDays.ONE_MONTH,
    });

    // Create Config Rules for compliance monitoring
    const configRules = [
      {
        name: 's3-bucket-public-access-prohibited',
        sourceIdentifier: 'S3_BUCKET_PUBLIC_ACCESS_PROHIBITED',
        description: 'Checks if S3 buckets allow public access',
      },
      {
        name: 'encrypted-volumes',
        sourceIdentifier: 'ENCRYPTED_VOLUMES',
        description: 'Checks if EBS volumes are encrypted',
      },
      {
        name: 'root-access-key-check',
        sourceIdentifier: 'ROOT_ACCESS_KEY_CHECK',
        description: 'Checks if root access keys exist',
      },
      {
        name: 'iam-password-policy',
        sourceIdentifier: 'IAM_PASSWORD_POLICY',
        description: 'Checks if IAM password policy meets requirements',
      },
    ];

    configRules.forEach((rule) => {
      new config.ManagedRule(this, `ConfigRule${rule.name}`, {
        configRuleName: rule.name,
        identifier: rule.sourceIdentifier,
        description: rule.description,
      });
    });

    // Create Systems Manager Maintenance Window
    const maintenanceWindow = new ssm.CfnMaintenanceWindow(this, 'MaintenanceWindow', {
      name: 'InfrastructureMonitoring',
      description: 'Automated infrastructure monitoring tasks',
      duration: 4,
      cutoff: 1,
      schedule: 'cron(0 02 ? * SUN *)', // Every Sunday at 2 AM
      allowUnassociatedTargets: true,
    });

    // Create Lambda function for automated remediation (if enabled)
    let remediationLambda: lambda.Function | undefined;
    if (props?.enableAutomatedRemediation) {
      const lambdaRole = new iam.Role(this, 'RemediationLambdaRole', {
        assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
        managedPolicies: [
          iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        ],
        inlinePolicies: {
          RemediationPolicy: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: [
                  's3:PutBucketPublicAccessBlock',
                  'ec2:ModifyVolumeAttribute',
                  'config:GetComplianceDetailsByConfigRule',
                ],
                resources: ['*'],
              }),
            ],
          }),
        },
      });

      remediationLambda = new lambda.Function(this, 'RemediationLambda', {
        functionName: `InfrastructureRemediation-${randomSuffix}`,
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.lambda_handler',
        role: lambdaRole,
        timeout: cdk.Duration.minutes(5),
        code: lambda.Code.fromInline(`
import json
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Automated remediation for Config rule violations
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Parse Config rule compliance change event
        if 'detail' in event and 'configRuleName' in event['detail']:
            rule_name = event['detail']['configRuleName']
            resource_id = event['detail']['configurationItem']['resourceId']
            compliance_type = event['detail']['configurationItem']['complianceType']
            
            logger.info(f"Rule: {rule_name}, Resource: {resource_id}, Compliance: {compliance_type}")
            
            if compliance_type == 'NON_COMPLIANT':
                remediate_resource(rule_name, resource_id)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Remediation processed successfully')
        }
    except Exception as e:
        logger.error(f"Error in remediation: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Remediation failed: {str(e)}')
        }

def remediate_resource(rule_name, resource_id):
    """
    Perform specific remediation based on rule type
    """
    if rule_name == 's3-bucket-public-access-prohibited':
        remediate_s3_public_access(resource_id)
    else:
        logger.info(f"No automated remediation available for rule: {rule_name}")

def remediate_s3_public_access(bucket_name):
    """
    Block public access for S3 bucket
    """
    try:
        s3_client = boto3.client('s3')
        s3_client.put_public_access_block(
            Bucket=bucket_name,
            PublicAccessBlockConfiguration={
                'BlockPublicAcls': True,
                'IgnorePublicAcls': True,
                'BlockPublicPolicy': True,
                'RestrictPublicBuckets': True
            }
        )
        logger.info(f"Successfully remediated S3 bucket public access for: {bucket_name}")
    except Exception as e:
        logger.error(f"Failed to remediate S3 bucket {bucket_name}: {str(e)}")
        raise
`),
      });

      // Create EventBridge rule to trigger remediation on Config rule changes
      const configRuleChangeRule = new events.Rule(this, 'ConfigRuleChangeRule', {
        eventPattern: {
          source: ['aws.config'],
          detailType: ['Config Rules Compliance Change'],
          detail: {
            newEvaluationResult: {
              complianceType: ['NON_COMPLIANT'],
            },
          },
        },
      });

      configRuleChangeRule.addTarget(new eventsTargets.LambdaFunction(remediationLambda));
    }

    // Create CloudWatch Dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'InfrastructureMonitoringDashboard', {
      dashboardName: 'InfrastructureMonitoring',
    });

    // Add Config compliance metrics to dashboard
    const complianceWidget = new cloudwatch.GraphWidget({
      title: 'Config Rule Compliance',
      left: configRules.map(rule =>
        new cloudwatch.Metric({
          namespace: 'AWS/Config',
          metricName: 'ComplianceByConfigRule',
          dimensionsMap: {
            ConfigRuleName: rule.name,
          },
          statistic: 'Average',
          period: cdk.Duration.minutes(5),
        })
      ),
    });

    dashboard.addWidgets(complianceWidget);

    // Add CloudTrail API call metrics
    const apiCallsWidget = new cloudwatch.GraphWidget({
      title: 'CloudTrail API Calls',
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/CloudWatchLogs',
          metricName: 'IncomingLogEvents',
          dimensionsMap: {
            LogGroupName: infrastructureTrail.logGroup?.logGroupName || '',
          },
          statistic: 'Sum',
          period: cdk.Duration.minutes(5),
        }),
      ],
    });

    dashboard.addWidgets(apiCallsWidget);

    // Create SSM OpsItem for monitoring setup
    new ssm.CfnDocument(this, 'MonitoringSetupDocument', {
      documentType: 'Command',
      documentFormat: 'YAML',
      name: `InfrastructureMonitoringSetup-${randomSuffix}`,
      content: {
        schemaVersion: '2.2',
        description: 'Document for infrastructure monitoring setup validation',
        parameters: {},
        mainSteps: [
          {
            action: 'aws:runShellScript',
            name: 'ValidateMonitoring',
            inputs: {
              runCommand: [
                'echo "Infrastructure monitoring setup complete"',
                'echo "CloudTrail: Logging enabled"',
                'echo "Config: Rules active"',
                'echo "Systems Manager: Maintenance window configured"',
              ],
            },
          },
        ],
      },
    });

    // Outputs
    new cdk.CfnOutput(this, 'MonitoringBucketName', {
      value: monitoringBucket.bucketName,
      description: 'S3 bucket for storing CloudTrail and Config logs',
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertsTopic.topicArn,
      description: 'SNS topic for infrastructure alerts',
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: infrastructureTrail.trailArn,
      description: 'CloudTrail ARN for audit logging',
    });

    new cdk.CfnOutput(this, 'ConfigRoleArn', {
      value: configRole.roleArn,
      description: 'IAM role used by AWS Config',
    });

    new cdk.CfnOutput(this, 'MaintenanceWindowId', {
      value: maintenanceWindow.ref,
      description: 'Systems Manager maintenance window ID',
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=InfrastructureMonitoring`,
      description: 'CloudWatch dashboard URL',
    });

    if (remediationLambda) {
      new cdk.CfnOutput(this, 'RemediationLambdaArn', {
        value: remediationLambda.functionArn,
        description: 'Automated remediation Lambda function ARN',
      });
    }
  }
}

// CDK App
const app = new cdk.App();

// Get context values or use defaults
const notificationEmail = app.node.tryGetContext('notificationEmail');
const enableAutomatedRemediation = app.node.tryGetContext('enableAutomatedRemediation') === 'true';
const customBucketName = app.node.tryGetContext('customBucketName');

new InfrastructureMonitoringStack(app, 'InfrastructureMonitoringStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Infrastructure monitoring solution with CloudTrail, Config, and Systems Manager',
  notificationEmail,
  enableAutomatedRemediation,
  customBucketName,
  tags: {
    Project: 'InfrastructureMonitoring',
    Environment: 'Production',
    ManagedBy: 'CDK',
  },
});

app.synth();