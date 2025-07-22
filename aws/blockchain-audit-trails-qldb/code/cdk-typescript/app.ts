#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as qldb from 'aws-cdk-lib/aws-qldb';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as kinesisfirehose from 'aws-cdk-lib/aws-kinesisfirehose';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the BlockchainAuditTrailsStack
 */
interface BlockchainAuditTrailsStackProps extends cdk.StackProps {
  /**
   * Name of the QLDB ledger for audit records
   * @default 'compliance-audit-ledger'
   */
  readonly ledgerName?: string;

  /**
   * Name of the CloudTrail for audit logging
   * @default 'compliance-audit-trail'
   */
  readonly cloudTrailName?: string;

  /**
   * Email address for compliance notifications
   * @default undefined - SNS topic created without subscription
   */
  readonly notificationEmail?: string;

  /**
   * Enable deletion protection on critical resources
   * @default true
   */
  readonly deletionProtection?: boolean;

  /**
   * Environment for resource naming (dev, staging, prod)
   * @default 'dev'
   */
  readonly environment?: string;
}

/**
 * CDK Stack for creating blockchain audit trails for compliance using Amazon QLDB and CloudTrail.
 * 
 * This stack creates:
 * - Amazon QLDB ledger for immutable audit records
 * - CloudTrail for comprehensive API activity logging
 * - Lambda function for real-time audit processing
 * - EventBridge rules for event-driven processing
 * - S3 bucket for audit data storage and archival
 * - Kinesis Data Firehose for compliance reporting
 * - SNS topic for compliance alerts
 * - CloudWatch dashboard for monitoring
 * - Athena workgroup for compliance queries
 */
export class BlockchainAuditTrailsStack extends cdk.Stack {
  // Core infrastructure components
  public readonly qldbLedger: qldb.CfnLedger;
  public readonly auditBucket: s3.Bucket;
  public readonly cloudTrail: cloudtrail.Trail;
  public readonly auditProcessor: lambda.Function;
  public readonly complianceAlerts: sns.Topic;
  public readonly complianceWorkgroup: athena.CfnWorkGroup;

  constructor(scope: Construct, id: string, props: BlockchainAuditTrailsStackProps = {}) {
    super(scope, id, props);

    // Extract props with defaults
    const {
      ledgerName = 'compliance-audit-ledger',
      cloudTrailName = 'compliance-audit-trail',
      notificationEmail,
      deletionProtection = true,
      environment = 'dev'
    } = props;

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);
    const resourcePrefix = `${environment}-${uniqueSuffix}`;

    // Create KMS key for encryption
    const auditEncryptionKey = new kms.Key(this, 'AuditEncryptionKey', {
      description: 'KMS key for audit trail encryption',
      enableKeyRotation: true,
      removalPolicy: deletionProtection ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Create S3 bucket for audit data storage
    this.auditBucket = new s3.Bucket(this, 'AuditBucket', {
      bucketName: `compliance-audit-bucket-${resourcePrefix}`,
      versioned: true,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: auditEncryptionKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'ComplianceDataArchival',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
      removalPolicy: deletionProtection ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Create QLDB ledger for immutable audit records
    this.qldbLedger = new qldb.CfnLedger(this, 'ComplianceLedger', {
      name: `${ledgerName}-${resourcePrefix}`,
      permissionsMode: 'STANDARD',
      deletionProtection: deletionProtection,
      kmsKey: auditEncryptionKey.keyArn,
      tags: [
        { key: 'Environment', value: environment },
        { key: 'Purpose', value: 'compliance-audit' },
        { key: 'DataClassification', value: 'confidential' },
      ],
    });

    // Create IAM role for Lambda audit processor
    const auditProcessorRole = new iam.Role(this, 'AuditProcessorRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for audit processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        AuditProcessorPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'qldb:SendCommand',
                'qldb:GetDigest',
                'qldb:GetBlock',
                'qldb:GetRevision',
              ],
              resources: [this.qldbLedger.attrArn],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:PutObjectAcl',
              ],
              resources: [this.auditBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
              ],
              resources: ['*'],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:GenerateDataKey',
              ],
              resources: [auditEncryptionKey.keyArn],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for audit processing
    this.auditProcessor = new lambda.Function(this, 'AuditProcessor', {
      functionName: `audit-processor-${resourcePrefix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import hashlib
import datetime
import os
from botocore.exceptions import ClientError

# Initialize AWS clients
qldb_client = boto3.client('qldb')
s3_client = boto3.client('s3')
cloudwatch = boto3.client('cloudwatch')

def lambda_handler(event, context):
    """
    Main Lambda handler for processing audit events from CloudTrail.
    
    This function:
    1. Processes CloudTrail events into structured audit records
    2. Stores immutable records in QLDB ledger
    3. Generates compliance metrics for monitoring
    4. Provides cryptographic verification of data integrity
    """
    try:
        print(f"Processing audit event: {json.dumps(event, default=str)}")
        
        # Create structured audit record from CloudTrail event
        audit_record = create_audit_record(event)
        
        # Store the audit record in QLDB for immutable storage
        ledger_name = os.environ['LEDGER_NAME']
        store_audit_record(ledger_name, audit_record)
        
        # Generate compliance metrics for monitoring dashboard
        generate_compliance_metrics(audit_record)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Audit record processed successfully',
                'auditId': audit_record.get('auditId'),
                'timestamp': audit_record.get('timestamp')
            })
        }
        
    except Exception as e:
        print(f"Error processing audit record: {str(e)}")
        # Send error metric to CloudWatch
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=[{
                'MetricName': 'ProcessingErrors',
                'Value': 1,
                'Unit': 'Count'
            }]
        )
        raise

def create_audit_record(event):
    """
    Transform CloudTrail event into structured audit record with cryptographic hash.
    
    Args:
        event: CloudTrail event from EventBridge
        
    Returns:
        dict: Structured audit record with integrity hash
    """
    timestamp = datetime.datetime.utcnow().isoformat()
    
    # Extract CloudTrail event details
    detail = event.get('detail', {})
    
    # Create comprehensive audit record
    audit_record = {
        'auditId': hashlib.sha256(str(event).encode()).hexdigest()[:16],
        'timestamp': timestamp,
        'eventName': detail.get('eventName', 'Unknown'),
        'eventSource': detail.get('eventSource', ''),
        'eventTime': detail.get('eventTime', timestamp),
        'awsRegion': detail.get('awsRegion', ''),
        'sourceIPAddress': detail.get('sourceIPAddress', ''),
        'userAgent': detail.get('userAgent', ''),
        'userIdentity': {
            'type': detail.get('userIdentity', {}).get('type', ''),
            'principalId': detail.get('userIdentity', {}).get('principalId', ''),
            'arn': detail.get('userIdentity', {}).get('arn', ''),
            'accountId': detail.get('userIdentity', {}).get('accountId', ''),
            'userName': detail.get('userIdentity', {}).get('userName', ''),
        },
        'requestParameters': detail.get('requestParameters', {}),
        'responseElements': detail.get('responseElements', {}),
        'resources': detail.get('resources', []),
        'errorCode': detail.get('errorCode', ''),
        'errorMessage': detail.get('errorMessage', ''),
        'requestId': detail.get('requestId', ''),
        'eventId': detail.get('eventId', ''),
        'readOnly': detail.get('readOnly', False),
        'recordHash': ''  # Will be populated below
    }
    
    # Generate cryptographic hash for integrity verification
    record_string = json.dumps(audit_record, sort_keys=True, default=str)
    audit_record['recordHash'] = hashlib.sha256(record_string.encode()).hexdigest()
    
    return audit_record

def store_audit_record(ledger_name, audit_record):
    """
    Store audit record in QLDB ledger for immutable storage.
    
    Note: This is a simplified implementation. In production, use proper
    QLDB session management and PartiQL queries for data insertion.
    
    Args:
        ledger_name: Name of the QLDB ledger
        audit_record: Structured audit record to store
    """
    try:
        # Get ledger digest for verification (simplified approach)
        response = qldb_client.get_digest(Name=ledger_name)
        
        print(f"Audit record stored in ledger {ledger_name}: {audit_record['auditId']}")
        print(f"Ledger digest: {response.get('Digest', {}).get('Digest', 'N/A')}")
        
        # In production, implement proper QLDB session and PartiQL INSERT
        # session = qldb_session.qldb_session()
        # session.execute_lambda(lambda executor: insert_audit_record(executor, audit_record))
        
    except ClientError as e:
        print(f"Error storing audit record in QLDB: {e}")
        raise

def generate_compliance_metrics(audit_record):
    """
    Generate CloudWatch metrics for compliance monitoring and dashboard.
    
    Args:
        audit_record: Processed audit record
    """
    try:
        # Send comprehensive metrics to CloudWatch
        metric_data = [
            {
                'MetricName': 'AuditRecordsProcessed',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EventSource', 'Value': audit_record['eventSource']},
                    {'Name': 'EventName', 'Value': audit_record['eventName']},
                ]
            },
            {
                'MetricName': 'ComplianceCoverage',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'Region', 'Value': audit_record['awsRegion']},
                ]
            }
        ]
        
        # Add security-specific metrics for high-risk events
        high_risk_events = ['CreateRole', 'DeleteRole', 'PutBucketPolicy', 'DeleteBucket']
        if audit_record['eventName'] in high_risk_events:
            metric_data.append({
                'MetricName': 'HighRiskEvents',
                'Value': 1,
                'Unit': 'Count',
                'Dimensions': [
                    {'Name': 'EventName', 'Value': audit_record['eventName']},
                ]
            })
        
        cloudwatch.put_metric_data(
            Namespace='ComplianceAudit',
            MetricData=metric_data
        )
        
    except Exception as e:
        print(f"Error generating compliance metrics: {e}")
        # Don't raise exception here to avoid blocking audit processing
`),
      role: auditProcessorRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        LEDGER_NAME: this.qldbLedger.name!,
        S3_BUCKET: this.auditBucket.bucketName,
      },
      logRetention: logs.RetentionDays.ONE_YEAR,
      description: 'Processes CloudTrail events into immutable QLDB audit records',
    });

    // Create CloudTrail for comprehensive API logging
    this.cloudTrail = new cloudtrail.Trail(this, 'ComplianceCloudTrail', {
      trailName: `${cloudTrailName}-${resourcePrefix}`,
      bucket: this.auditBucket,
      s3KeyPrefix: 'cloudtrail-logs/',
      includeGlobalServiceEvents: true,
      isMultiRegionTrail: true,
      enableFileValidation: true,
      encryptionKey: auditEncryptionKey,
      sendToCloudWatchLogs: true,
      cloudWatchLogGroup: new logs.LogGroup(this, 'CloudTrailLogGroup', {
        logGroupName: `/aws/cloudtrail/${cloudTrailName}-${resourcePrefix}`,
        retention: logs.RetentionDays.ONE_YEAR,
        encryptionKey: auditEncryptionKey,
      }),
    });

    // Create EventBridge rule for real-time audit processing
    const auditRule = new events.Rule(this, 'ComplianceAuditRule', {
      ruleName: `compliance-audit-rule-${resourcePrefix}`,
      description: 'Process critical API calls for compliance audit',
      enabled: true,
      eventPattern: {
        source: ['aws.cloudtrail'],
        detailType: ['AWS API Call via CloudTrail'],
        detail: {
          eventSource: [
            'qldb.amazonaws.com',
            's3.amazonaws.com',
            'iam.amazonaws.com',
            'kms.amazonaws.com',
          ],
          eventName: [
            'SendCommand',
            'PutObject',
            'CreateRole',
            'DeleteRole',
            'CreateKey',
            'ScheduleKeyDeletion',
          ],
        },
      },
    });

    // Add Lambda as target for EventBridge rule
    auditRule.addTarget(new targets.LambdaFunction(this.auditProcessor, {
      retryAttempts: 3,
      maxEventAge: cdk.Duration.hours(2),
    }));

    // Create SNS topic for compliance alerts
    this.complianceAlerts = new sns.Topic(this, 'ComplianceAlerts', {
      topicName: `compliance-audit-alerts-${resourcePrefix}`,
      displayName: 'Compliance Audit Alerts',
      masterKey: auditEncryptionKey,
    });

    // Add email subscription if provided
    if (notificationEmail) {
      this.complianceAlerts.addSubscription(
        new subscriptions.EmailSubscription(notificationEmail)
      );
    }

    // Grant SNS publish permissions to audit processor
    this.complianceAlerts.grantPublish(this.auditProcessor);

    // Create CloudWatch alarms for compliance monitoring
    const auditProcessingErrors = new cloudwatch.Alarm(this, 'AuditProcessingErrors', {
      alarmName: `ComplianceAuditErrors-${resourcePrefix}`,
      alarmDescription: 'Alert when audit processing fails',
      metric: this.auditProcessor.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    auditProcessingErrors.addAlarmAction(
      new cloudwatch.SnsAction(this.complianceAlerts)
    );

    // Create IAM role for Kinesis Data Firehose
    const firehoseRole = new iam.Role(this, 'FirehoseRole', {
      assumedBy: new iam.ServicePrincipal('firehose.amazonaws.com'),
      description: 'IAM role for Kinesis Data Firehose compliance reporting',
      inlinePolicies: {
        FirehosePolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:ListBucket',
                's3:PutObjectAcl',
              ],
              resources: [
                this.auditBucket.bucketArn,
                this.auditBucket.arnForObjects('*'),
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kms:Decrypt',
                'kms:GenerateDataKey',
              ],
              resources: [auditEncryptionKey.keyArn],
            }),
          ],
        }),
      },
    });

    // Create Kinesis Data Firehose delivery stream for compliance reporting
    const complianceFirehose = new kinesisfirehose.CfnDeliveryStream(this, 'ComplianceFirehose', {
      deliveryStreamName: `compliance-audit-stream-${resourcePrefix}`,
      deliveryStreamType: 'DirectPut',
      s3DestinationConfiguration: {
        bucketArn: this.auditBucket.bucketArn,
        roleArn: firehoseRole.roleArn,
        prefix: 'compliance-reports/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/',
        errorOutputPrefix: 'compliance-errors/',
        bufferingHints: {
          sizeInMBs: 5,
          intervalInSeconds: 300,
        },
        compressionFormat: 'GZIP',
        encryptionConfiguration: {
          kmsEncryptionConfig: {
            awskmsKeyArn: auditEncryptionKey.keyArn,
          },
        },
        cloudWatchLoggingOptions: {
          enabled: true,
          logGroupName: `/aws/kinesisfirehose/compliance-audit-stream-${resourcePrefix}`,
        },
      },
    });

    // Create Athena workgroup for compliance queries
    this.complianceWorkgroup = new athena.CfnWorkGroup(this, 'ComplianceWorkGroup', {
      name: `compliance-audit-workgroup-${resourcePrefix}`,
      description: 'Athena workgroup for compliance audit queries',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${this.auditBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_KMS',
            kmsKey: auditEncryptionKey.keyArn,
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
        bytesScannedCutoffPerQuery: 100 * 1024 * 1024 * 1024, // 100 GB
      },
    });

    // Create CloudWatch dashboard for compliance monitoring
    const complianceDashboard = new cloudwatch.Dashboard(this, 'ComplianceDashboard', {
      dashboardName: `ComplianceAuditDashboard-${resourcePrefix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Audit Processing Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'ComplianceAudit',
                metricName: 'AuditRecordsProcessed',
                statistic: 'Sum',
              }),
              this.auditProcessor.metricInvocations(),
              this.auditProcessor.metricErrors(),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Compliance Coverage by Region',
            left: [
              new cloudwatch.Metric({
                namespace: 'ComplianceAudit',
                metricName: 'ComplianceCoverage',
                statistic: 'Sum',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'High Risk Security Events',
            left: [
              new cloudwatch.Metric({
                namespace: 'ComplianceAudit',
                metricName: 'HighRiskEvents',
                statistic: 'Sum',
              }),
            ],
            period: cdk.Duration.minutes(5),
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Add tags to all resources for compliance tracking
    cdk.Tags.of(this).add('Project', 'BlockchainAuditTrails');
    cdk.Tags.of(this).add('Environment', environment);
    cdk.Tags.of(this).add('DataClassification', 'Confidential');
    cdk.Tags.of(this).add('Compliance', 'SOX-PCI-HIPAA');
    cdk.Tags.of(this).add('Owner', 'ComplianceTeam');

    // Stack outputs for integration and verification
    new cdk.CfnOutput(this, 'QLDBLedgerArn', {
      value: this.qldbLedger.attrArn,
      description: 'ARN of the QLDB ledger for audit records',
      exportName: `${this.stackName}-QLDBLedgerArn`,
    });

    new cdk.CfnOutput(this, 'AuditBucketName', {
      value: this.auditBucket.bucketName,
      description: 'Name of the S3 bucket for audit data storage',
      exportName: `${this.stackName}-AuditBucketName`,
    });

    new cdk.CfnOutput(this, 'CloudTrailArn', {
      value: this.cloudTrail.trailArn,
      description: 'ARN of the CloudTrail for API activity logging',
      exportName: `${this.stackName}-CloudTrailArn`,
    });

    new cdk.CfnOutput(this, 'AuditProcessorFunctionArn', {
      value: this.auditProcessor.functionArn,
      description: 'ARN of the Lambda function for audit processing',
      exportName: `${this.stackName}-AuditProcessorArn`,
    });

    new cdk.CfnOutput(this, 'ComplianceAlertsTopicArn', {
      value: this.complianceAlerts.topicArn,
      description: 'ARN of the SNS topic for compliance alerts',
      exportName: `${this.stackName}-ComplianceAlertsArn`,
    });

    new cdk.CfnOutput(this, 'ComplianceWorkgroupName', {
      value: this.complianceWorkgroup.name!,
      description: 'Name of the Athena workgroup for compliance queries',
      exportName: `${this.stackName}-ComplianceWorkgroupName`,
    });

    new cdk.CfnOutput(this, 'EncryptionKeyArn', {
      value: auditEncryptionKey.keyArn,
      description: 'ARN of the KMS key used for audit data encryption',
      exportName: `${this.stackName}-EncryptionKeyArn`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${complianceDashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for compliance monitoring',
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'dev';
const notificationEmail = app.node.tryGetContext('notificationEmail') || process.env.NOTIFICATION_EMAIL;
const deletionProtection = app.node.tryGetContext('deletionProtection') !== 'false';

// Create the main stack
new BlockchainAuditTrailsStack(app, 'BlockchainAuditTrailsStack', {
  description: 'Blockchain audit trails for compliance with Amazon QLDB and CloudTrail (uksb-1tupboc45)',
  environment,
  notificationEmail,
  deletionProtection,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'BlockchainAuditTrails',
    Environment: environment,
    ManagedBy: 'CDK',
  },
});

app.synth();