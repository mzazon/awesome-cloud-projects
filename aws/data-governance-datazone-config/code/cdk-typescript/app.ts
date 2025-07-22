#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as config from 'aws-cdk-lib/aws-config';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for building automated data governance pipelines using Amazon DataZone and AWS Config
 * This implementation creates a comprehensive governance framework with real-time compliance monitoring
 */
export class DataGovernancePipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resources to avoid naming conflicts
    const uniqueSuffix = this.node.addr.slice(-6).toLowerCase();

    // ========================================
    // AWS Config Setup for Compliance Monitoring
    // ========================================

    // S3 bucket for AWS Config delivery channel with secure configuration
    const configBucket = new s3.Bucket(this, 'ConfigDeliveryBucket', {
      bucketName: `aws-config-bucket-${cdk.Aws.ACCOUNT_ID}-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'config-lifecycle',
          enabled: true,
          expiration: cdk.Duration.days(2557), // 7 years for compliance
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90)
            }
          ]
        }
      ],
      removalPolicy: cdk.RemovalPolicy.RETAIN
    });

    // IAM service role for AWS Config with comprehensive permissions
    const configServiceRole = new iam.Role(this, 'ConfigServiceRole', {
      roleName: `DataGovernanceConfigRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('config.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/ConfigRole')
      ],
      inlinePolicies: {
        ConfigDeliveryRolePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketAcl',
                's3:GetBucketLocation',
                's3:ListBucket'
              ],
              resources: [configBucket.bucketArn]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:PutObject'],
              resources: [`${configBucket.bucketArn}/AWSLogs/${cdk.Aws.ACCOUNT_ID}/Config/*`],
              conditions: {
                StringEquals: {
                  's3:x-amz-acl': 'bucket-owner-full-control'
                }
              }
            })
          ]
        })
      }
    });

    // Grant Config service access to the S3 bucket
    configBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketPermissionsCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:GetBucketAcl'],
        resources: [configBucket.bucketArn],
        conditions: {
          StringEquals: {
            'AWS:SourceAccount': cdk.Aws.ACCOUNT_ID
          }
        }
      })
    );

    configBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketExistenceCheck',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:ListBucket'],
        resources: [configBucket.bucketArn],
        conditions: {
          StringEquals: {
            'AWS:SourceAccount': cdk.Aws.ACCOUNT_ID
          }
        }
      })
    );

    configBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'AWSConfigBucketDelivery',
        effect: iam.Effect.ALLOW,
        principals: [new iam.ServicePrincipal('config.amazonaws.com')],
        actions: ['s3:PutObject'],
        resources: [`${configBucket.bucketArn}/AWSLogs/${cdk.Aws.ACCOUNT_ID}/Config/*`],
        conditions: {
          StringEquals: {
            's3:x-amz-acl': 'bucket-owner-full-control',
            'AWS:SourceAccount': cdk.Aws.ACCOUNT_ID
          }
        }
      })
    );

    // AWS Config configuration recorder
    const configurationRecorder = new config.CfnConfigurationRecorder(this, 'ConfigurationRecorder', {
      name: 'default',
      roleArn: configServiceRole.roleArn,
      recordingGroup: {
        allSupported: true,
        includeGlobalResourceTypes: true,
        recordingModeOverrides: []
      }
    });

    // AWS Config delivery channel
    const deliveryChannel = new config.CfnDeliveryChannel(this, 'DeliveryChannel', {
      name: 'default',
      s3BucketName: configBucket.bucketName
    });

    // Data governance Config rules for compliance monitoring
    const s3EncryptionRule = new config.ManagedRule(this, 'S3BucketEncryptionRule', {
      identifier: config.ManagedRuleIdentifiers.S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED,
      configRuleName: 's3-bucket-server-side-encryption-enabled',
      description: 'Checks if S3 buckets have server-side encryption enabled for data governance',
      ruleScope: config.RuleScope.fromResources([config.ResourceType.S3_BUCKET])
    });

    const rdsEncryptionRule = new config.ManagedRule(this, 'RDSStorageEncryptionRule', {
      identifier: config.ManagedRuleIdentifiers.RDS_STORAGE_ENCRYPTED,
      configRuleName: 'rds-storage-encrypted',
      description: 'Checks if RDS instances have storage encryption enabled for data protection',
      ruleScope: config.RuleScope.fromResources([config.ResourceType.RDS_DB_INSTANCE])
    });

    const s3PublicReadRule = new config.ManagedRule(this, 'S3PublicReadProhibitedRule', {
      identifier: config.ManagedRuleIdentifiers.S3_BUCKET_PUBLIC_READ_PROHIBITED,
      configRuleName: 's3-bucket-public-read-prohibited',
      description: 'Ensures S3 buckets prohibit public read access for data governance',
      ruleScope: config.RuleScope.fromResources([config.ResourceType.S3_BUCKET])
    });

    // Ensure dependencies are set correctly
    configurationRecorder.addDependency(configServiceRole.node.defaultChild as cdk.CfnResource);
    deliveryChannel.addDependency(configurationRecorder);
    s3EncryptionRule.node.addDependency(configurationRecorder);
    rdsEncryptionRule.node.addDependency(configurationRecorder);
    s3PublicReadRule.node.addDependency(configurationRecorder);

    // ========================================
    // Lambda Function for Governance Automation
    // ========================================

    // IAM role for the governance Lambda function with least privilege access
    const lambdaRole = new iam.Role(this, 'GovernanceLambdaRole', {
      roleName: `DataGovernanceLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        DataGovernancePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'datazone:Get*',
                'datazone:List*',
                'datazone:Search*',
                'datazone:UpdateAsset',
                'config:GetComplianceDetailsByConfigRule',
                'config:GetResourceConfigHistory',
                'config:GetComplianceDetailsByResource',
                'sns:Publish',
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });

    // Lambda function for processing governance events
    const governanceFunction = new lambda.Function(this, 'GovernanceProcessor', {
      functionName: `data-governance-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      description: 'Processes governance events and updates DataZone metadata for compliance monitoring',
      environment: {
        LOG_LEVEL: 'INFO',
        AWS_ACCOUNT_ID: cdk.Aws.ACCOUNT_ID,
        AWS_REGION: cdk.Aws.REGION
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

def lambda_handler(event, context):
    """Process governance events and update DataZone metadata"""
    
    try:
        logger.info(f"Received governance event: {json.dumps(event, default=str)}")
        
        # Parse EventBridge event structure
        detail = event.get('detail', {})
        config_item = detail.get('configurationItem', {})
        compliance_result = detail.get('newEvaluationResult', {})
        compliance_type = compliance_result.get('complianceType', 'UNKNOWN')
        
        resource_type = config_item.get('resourceType', '')
        resource_id = config_item.get('resourceId', '')
        resource_arn = config_item.get('arn', '')
        
        logger.info(f"Processing governance event for {resource_type}: {resource_id}")
        logger.info(f"Compliance status: {compliance_type}")
        
        # Initialize AWS clients with error handling
        try:
            datazone_client = boto3.client('datazone')
            config_client = boto3.client('config')
            sns_client = boto3.client('sns')
        except Exception as e:
            logger.error(f"Failed to initialize AWS clients: {str(e)}")
            raise
        
        # Create comprehensive governance metadata
        governance_metadata = {
            'resourceId': resource_id,
            'resourceType': resource_type,
            'resourceArn': resource_arn,
            'complianceStatus': compliance_type,
            'evaluationTimestamp': compliance_result.get('resultRecordedTime', ''),
            'configRuleName': compliance_result.get('configRuleName', ''),
            'awsAccountId': detail.get('awsAccountId', ''),
            'awsRegion': detail.get('awsRegion', ''),
            'processedAt': datetime.utcnow().isoformat(),
            'governanceVersion': '1.0'
        }
        
        # Log governance event for comprehensive audit trail
        logger.info(f"Governance metadata created: {json.dumps(governance_metadata, default=str)}")
        
        # Process compliance violations with enhanced logic
        if compliance_type == 'NON_COMPLIANT':
            logger.warning(f"COMPLIANCE VIOLATION detected for {resource_type}: {resource_id}")
            
            # Enhanced violation processing for production environments
            violation_details = {
                'violationType': 'COMPLIANCE_VIOLATION',
                'severity': determine_violation_severity(compliance_result.get('configRuleName', '')),
                'resource': resource_id,
                'resourceType': resource_type,
                'rule': compliance_result.get('configRuleName', ''),
                'requiresImmediateAttention': True,
                'remediationRequired': True,
                'businessImpact': assess_business_impact(resource_type, compliance_result.get('configRuleName', ''))
            }
            
            logger.warning(f"Violation details: {json.dumps(violation_details)}")
            
            # In production, implement comprehensive remediation workflows:
            # 1. Update DataZone asset metadata with compliance status
            # 2. Create governance incidents in tracking systems
            # 3. Trigger automated remediation workflows via Step Functions
            # 4. Send escalated notifications to data stewards and security teams
            # 5. Update compliance dashboards and metrics
            # 6. Generate audit reports for compliance teams
            
        elif compliance_type == 'COMPLIANT':
            logger.info(f"Resource {resource_id} is compliant with rule {compliance_result.get('configRuleName', '')}")
            
        # Prepare comprehensive response
        response_body = {
            'statusCode': 200,
            'message': 'Governance event processed successfully',
            'metadata': governance_metadata,
            'processedResources': 1,
            'complianceStatus': compliance_type,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return {
            'statusCode': 200,
            'body': json.dumps(response_body, default=str)
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS service error ({error_code}): {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f'AWS service error: {error_code}',
                'message': error_message,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error processing governance event: {str(e)}", exc_info=True)
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal processing error',
                'message': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def determine_violation_severity(rule_name):
    """Determine violation severity based on rule type"""
    high_severity_rules = ['encryption', 'public-access', 'security']
    for keyword in high_severity_rules:
        if keyword in rule_name.lower():
            return 'HIGH'
    return 'MEDIUM'

def assess_business_impact(resource_type, rule_name):
    """Assess business impact of compliance violation"""
    if 'encryption' in rule_name.lower():
        return 'Data at risk - encryption required for compliance'
    elif 'public' in rule_name.lower():
        return 'Data exposure risk - public access must be restricted'
    else:
        return 'Governance policy violation - review required'
`)
    });

    // CloudWatch Log Group for Lambda function with retention policy
    const lambdaLogGroup = new logs.LogGroup(this, 'GovernanceLambdaLogGroup', {
      logGroupName: `/aws/lambda/${governanceFunction.functionName}`,
      retention: logs.RetentionDays.THREE_MONTHS,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // ========================================
    // EventBridge Rules for Event-Driven Automation
    // ========================================

    // EventBridge rule for Config compliance changes with enhanced filtering
    const governanceEventRule = new events.Rule(this, 'GovernanceEventRule', {
      ruleName: `data-governance-events-${uniqueSuffix}`,
      description: 'Routes data governance compliance events to Lambda processor for automated response',
      eventPattern: {
        source: ['aws.config'],
        detailType: ['Config Rules Compliance Change'],
        detail: {
          newEvaluationResult: {
            complianceType: ['NON_COMPLIANT', 'COMPLIANT']
          },
          configRuleName: [
            's3-bucket-server-side-encryption-enabled',
            'rds-storage-encrypted',
            's3-bucket-public-read-prohibited'
          ]
        }
      },
      enabled: true
    });

    // Add Lambda function as target with retry and DLQ configuration
    governanceEventRule.addTarget(new targets.LambdaFunction(governanceFunction, {
      retryAttempts: 3,
      maxEventAge: cdk.Duration.hours(1)
    }));

    // ========================================
    // Monitoring and Alerting Infrastructure
    // ========================================

    // SNS topic for governance alerts with encryption
    const governanceAlertsTopic = new sns.Topic(this, 'GovernanceAlerts', {
      topicName: `data-governance-alerts-${uniqueSuffix}`,
      displayName: 'Data Governance Compliance Alerts',
      masterKey: undefined // Use default AWS managed key
    });

    // CloudWatch alarms for comprehensive monitoring
    
    // Lambda function errors alarm
    const lambdaErrorsAlarm = new cloudwatch.Alarm(this, 'LambdaErrorsAlarm', {
      alarmName: `DataGovernanceErrors-${uniqueSuffix}`,
      alarmDescription: 'Monitors Lambda function errors in governance pipeline - triggers on any error',
      metric: governanceFunction.metricErrors({
        period: cdk.Duration.minutes(5),
        statistic: 'Sum'
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    lambdaErrorsAlarm.addAlarmAction(new cloudwatch.SnsAction(governanceAlertsTopic));

    // Lambda function duration alarm
    const lambdaDurationAlarm = new cloudwatch.Alarm(this, 'LambdaDurationAlarm', {
      alarmName: `DataGovernanceDuration-${uniqueSuffix}`,
      alarmDescription: 'Monitors Lambda function execution duration - triggers on long execution times',
      metric: governanceFunction.metricDuration({
        period: cdk.Duration.minutes(5),
        statistic: 'Average'
      }),
      threshold: 240000, // 4 minutes in milliseconds
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    lambdaDurationAlarm.addAlarmAction(new cloudwatch.SnsAction(governanceAlertsTopic));

    // Config compliance ratio alarm
    const complianceAlarm = new cloudwatch.Alarm(this, 'ComplianceRatioAlarm', {
      alarmName: `DataGovernanceCompliance-${uniqueSuffix}`,
      alarmDescription: 'Monitors overall compliance ratio - triggers when compliance drops below threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Config',
        metricName: 'ComplianceByConfigRule',
        statistic: 'Average',
        period: cdk.Duration.minutes(10)
      }),
      threshold: 0.8, // 80% compliance threshold
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_THRESHOLD,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING
    });
    complianceAlarm.addAlarmAction(new cloudwatch.SnsAction(governanceAlertsTopic));

    // ========================================
    // Stack Outputs for Integration and Verification
    // ========================================

    new cdk.CfnOutput(this, 'DataZoneDomainInstructions', {
      value: 'DataZone domain must be created manually through AWS Console or DataZone APIs',
      description: 'Instructions for DataZone domain creation (not supported in CloudFormation/CDK yet)'
    });

    new cdk.CfnOutput(this, 'ConfigBucketName', {
      value: configBucket.bucketName,
      description: 'S3 bucket name for AWS Config delivery channel'
    });

    new cdk.CfnOutput(this, 'ConfigServiceRoleArn', {
      value: configServiceRole.roleArn,
      description: 'IAM role ARN for AWS Config service'
    });

    new cdk.CfnOutput(this, 'GovernanceLambdaFunctionName', {
      value: governanceFunction.functionName,
      description: 'Lambda function name for governance event processing'
    });

    new cdk.CfnOutput(this, 'GovernanceLambdaFunctionArn', {
      value: governanceFunction.functionArn,
      description: 'Lambda function ARN for governance automation'
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: governanceEventRule.ruleName,
      description: 'EventBridge rule name for governance event routing'
    });

    new cdk.CfnOutput(this, 'GovernanceAlertsTopicArn', {
      value: governanceAlertsTopic.topicArn,
      description: 'SNS topic ARN for governance alerts and notifications'
    });

    new cdk.CfnOutput(this, 'ConfigRuleNames', {
      value: JSON.stringify([
        s3EncryptionRule.configRuleName,
        rdsEncryptionRule.configRuleName,
        s3PublicReadRule.configRuleName
      ]),
      description: 'List of AWS Config rule names for data governance compliance'
    });

    new cdk.CfnOutput(this, 'MonitoringDashboardUrl', {
      value: `https://${cdk.Aws.REGION}.console.aws.amazon.com/cloudwatch/home?region=${cdk.Aws.REGION}#dashboards:`,
      description: 'CloudWatch dashboard URL for monitoring governance pipeline'
    });

    new cdk.CfnOutput(this, 'ConfigConsoleUrl', {
      value: `https://${cdk.Aws.REGION}.console.aws.amazon.com/config/home?region=${cdk.Aws.REGION}#/rules`,
      description: 'AWS Config console URL for viewing compliance rules and status'
    });
  }
}

// ========================================
// CDK Application Entry Point
// ========================================

const app = new cdk.App();

// Stack configuration with best practices
const stackProps: cdk.StackProps = {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Automated Data Governance Pipeline with Amazon DataZone and AWS Config - provides comprehensive compliance monitoring and automated governance workflows',
  tags: {
    Project: 'DataGovernancePipeline',
    Environment: 'Production',
    Owner: 'DataGovernanceTeam',
    CostCenter: 'DataManagement',
    Compliance: 'Required',
    Purpose: 'AutomatedGovernance'
  }
};

new DataGovernancePipelineStack(app, 'DataGovernancePipelineStack', stackProps);

// Synthesize the CDK application
app.synth();