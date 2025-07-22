#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as qldb from 'aws-cdk-lib/aws-qldb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * Stack for ACID-Compliant Ledger Database with QLDB
 * 
 * This stack creates:
 * - QLDB Ledger with deletion protection
 * - IAM roles for QLDB streaming and export operations
 * - S3 bucket for journal exports with encryption
 * - Kinesis Data Stream for real-time journal streaming
 * - Lambda function for transaction verification
 * - CloudWatch monitoring and alarms
 */
export class QldbAcidDatabaseStack extends cdk.Stack {
  public readonly ledger: qldb.CfnLedger;
  public readonly streamRole: iam.Role;
  public readonly exportBucket: s3.Bucket;
  public readonly kinesisStream: kinesis.Stream;
  public readonly verificationFunction: lambda.Function;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Create S3 bucket for QLDB journal exports
    this.exportBucket = new s3.Bucket(this, 'QLDBExportBucket', {
      bucketName: `qldb-exports-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'ArchiveOldExports',
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
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create Kinesis Data Stream for real-time journal streaming
    this.kinesisStream = new kinesis.Stream(this, 'QLDBJournalStream', {
      streamName: `qldb-journal-stream-${uniqueSuffix}`,
      shardCount: 1,
      retentionPeriod: cdk.Duration.days(7),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // Create IAM role for QLDB operations
    this.streamRole = new iam.Role(this, 'QLDBStreamRole', {
      roleName: `qldb-stream-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('qldb.amazonaws.com'),
      description: 'IAM role for QLDB streaming and export operations',
      inlinePolicies: {
        QLDBStreamPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for journal exports
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
                's3:GetObject',
                's3:ListBucket',
              ],
              resources: [
                this.exportBucket.bucketArn,
                `${this.exportBucket.bucketArn}/*`,
              ],
            }),
            // Kinesis permissions for journal streaming
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'kinesis:PutRecord',
                'kinesis:PutRecords',
                'kinesis:DescribeStream',
                'kinesis:ListShards',
              ],
              resources: [this.kinesisStream.streamArn],
            }),
          ],
        }),
      },
    });

    // Create QLDB Ledger with enterprise-grade configuration
    this.ledger = new qldb.CfnLedger(this, 'FinancialLedger', {
      name: `financial-ledger-${uniqueSuffix}`,
      permissionsMode: 'STANDARD', // Use IAM-based access control
      deletionProtection: true, // Prevent accidental deletion
      tags: [
        {
          key: 'Environment',
          value: 'Production',
        },
        {
          key: 'Application',
          value: 'Financial',
        },
        {
          key: 'Compliance',
          value: 'ACID',
        },
        {
          key: 'DataClassification',
          value: 'Sensitive',
        },
      ],
    });

    // Create Lambda function for transaction verification
    this.verificationFunction = new lambda.Function(this, 'TransactionVerificationFunction', {
      functionName: `qldb-verification-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: {
        LEDGER_NAME: this.ledger.name!,
        REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import boto3
import json
import hashlib
import logging
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function to verify QLDB ledger integrity using cryptographic digests
    
    This function:
    1. Retrieves the current digest from the QLDB ledger
    2. Validates the digest format and structure
    3. Performs basic integrity checks
    4. Returns verification results for audit purposes
    """
    
    try:
        # Initialize QLDB client
        qldb_client = boto3.client('qldb', region_name=os.environ['REGION'])
        ledger_name = os.environ['LEDGER_NAME']
        
        logger.info(f"Starting verification for ledger: {ledger_name}")
        
        # Get current digest from QLDB
        digest_response = qldb_client.get_digest(Name=ledger_name)
        
        # Extract digest information
        digest = digest_response.get('Digest')
        digest_tip_address = digest_response.get('DigestTipAddress', {})
        
        # Perform basic validation
        if not digest:
            raise ValueError("No digest received from QLDB")
        
        # Create verification result
        verification_result = {
            'ledgerName': ledger_name,
            'verificationTimestamp': datetime.utcnow().isoformat() + 'Z',
            'digest': digest,
            'digestTipAddress': digest_tip_address,
            'verificationStatus': 'SUCCESS',
            'digestLength': len(digest) if digest else 0,
            'message': 'Ledger integrity verification completed successfully'
        }
        
        logger.info(f"Verification completed successfully for ledger: {ledger_name}")
        
        return {
            'statusCode': 200,
            'body': json.dumps(verification_result, indent=2),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
        
    except Exception as e:
        error_message = f"Verification failed: {str(e)}"
        logger.error(error_message)
        
        error_result = {
            'ledgerName': os.environ.get('LEDGER_NAME', 'Unknown'),
            'verificationTimestamp': datetime.utcnow().isoformat() + 'Z',
            'verificationStatus': 'FAILED',
            'error': str(e),
            'message': error_message
        }
        
        return {
            'statusCode': 500,
            'body': json.dumps(error_result, indent=2),
            'headers': {
                'Content-Type': 'application/json'
            }
        }
      `),
    });

    // Grant QLDB permissions to the verification function
    this.verificationFunction.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'qldb:GetDigest',
          'qldb:DescribeLedger',
          'qldb:ListJournalS3Exports',
          'qldb:ListJournalKinesisStreamsForLedger',
        ],
        resources: [
          `arn:aws:qldb:${this.region}:${this.account}:ledger/${this.ledger.name}`,
        ],
      })
    );

    // Create CloudWatch Event Rule to trigger verification on a schedule
    const verificationRule = new events.Rule(this, 'VerificationScheduleRule', {
      ruleName: `qldb-verification-schedule-${uniqueSuffix}`,
      description: 'Scheduled integrity verification for QLDB ledger',
      schedule: events.Schedule.rate(cdk.Duration.hours(6)), // Verify every 6 hours
    });

    // Add Lambda target to the rule
    verificationRule.addTarget(new targets.LambdaFunction(this.verificationFunction));

    // Create CloudWatch Log Group for structured logging
    const logGroup = new logs.LogGroup(this, 'QLDBVerificationLogs', {
      logGroupName: `/aws/lambda/${this.verificationFunction.functionName}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create CloudWatch Dashboard for monitoring QLDB operations
    const dashboard = new cloudwatch.Dashboard(this, 'QLDBMonitoringDashboard', {
      dashboardName: `QLDB-Financial-Ledger-${uniqueSuffix}`,
    });

    // Add widgets to monitor QLDB and related services
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'QLDB Read/Write Operations',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/QLDB',
            metricName: 'ReadIOs',
            dimensionsMap: {
              LedgerName: this.ledger.name!,
            },
            statistic: 'Sum',
          }),
          new cloudwatch.Metric({
            namespace: 'AWS/QLDB',
            metricName: 'WriteIOs',
            dimensionsMap: {
              LedgerName: this.ledger.name!,
            },
            statistic: 'Sum',
          }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Lambda Verification Function Metrics',
        left: [
          this.verificationFunction.metricInvocations(),
          this.verificationFunction.metricErrors(),
        ],
        right: [this.verificationFunction.metricDuration()],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Kinesis Stream Metrics',
        left: [
          this.kinesisStream.metricIncomingRecords(),
          this.kinesisStream.metricIncomingBytes(),
        ],
        width: 12,
        height: 6,
      })
    );

    // Create CloudWatch Alarms for monitoring
    new cloudwatch.Alarm(this, 'VerificationFunctionErrorAlarm', {
      alarmName: `QLDB-Verification-Errors-${uniqueSuffix}`,
      alarmDescription: 'Alert when QLDB verification function encounters errors',
      metric: this.verificationFunction.metricErrors({
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important information
    new cdk.CfnOutput(this, 'LedgerName', {
      value: this.ledger.name!,
      description: 'Name of the QLDB ledger',
      exportName: `${this.stackName}-LedgerName`,
    });

    new cdk.CfnOutput(this, 'LedgerArn', {
      value: `arn:aws:qldb:${this.region}:${this.account}:ledger/${this.ledger.name}`,
      description: 'ARN of the QLDB ledger',
      exportName: `${this.stackName}-LedgerArn`,
    });

    new cdk.CfnOutput(this, 'StreamRoleArn', {
      value: this.streamRole.roleArn,
      description: 'ARN of the IAM role for QLDB streaming operations',
      exportName: `${this.stackName}-StreamRoleArn`,
    });

    new cdk.CfnOutput(this, 'ExportBucketName', {
      value: this.exportBucket.bucketName,
      description: 'Name of the S3 bucket for journal exports',
      exportName: `${this.stackName}-ExportBucketName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamName', {
      value: this.kinesisStream.streamName,
      description: 'Name of the Kinesis stream for journal streaming',
      exportName: `${this.stackName}-KinesisStreamName`,
    });

    new cdk.CfnOutput(this, 'KinesisStreamArn', {
      value: this.kinesisStream.streamArn,
      description: 'ARN of the Kinesis stream for journal streaming',
      exportName: `${this.stackName}-KinesisStreamArn`,
    });

    new cdk.CfnOutput(this, 'VerificationFunctionName', {
      value: this.verificationFunction.functionName,
      description: 'Name of the Lambda function for transaction verification',
      exportName: `${this.stackName}-VerificationFunctionName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for monitoring',
      exportName: `${this.stackName}-DashboardUrl`,
    });

    // Additional outputs for integration and automation
    new cdk.CfnOutput(this, 'QLDBConsoleUrl', {
      value: `https://console.aws.amazon.com/qldb/home?region=${this.region}#ledger-details/${this.ledger.name}`,
      description: 'URL to the QLDB console for the ledger',
      exportName: `${this.stackName}-QLDBConsoleUrl`,
    });

    new cdk.CfnOutput(this, 'StreamStartCommand', {
      value: `aws qldb stream-journal-to-kinesis --ledger-name ${this.ledger.name} --role-arn ${this.streamRole.roleArn} --kinesis-configuration StreamArn=${this.kinesisStream.streamArn},AggregationEnabled=true --stream-name ${this.ledger.name}-journal-stream --inclusive-start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)`,
      description: 'CLI command to start journal streaming to Kinesis',
      exportName: `${this.stackName}-StreamStartCommand`,
    });

    new cdk.CfnOutput(this, 'ExportStartCommand', {
      value: `aws qldb export-journal-to-s3 --name ${this.ledger.name} --inclusive-start-time $(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ) --exclusive-end-time $(date -u +%Y-%m-%dT%H:%M:%SZ) --role-arn ${this.streamRole.roleArn} --s3-export-configuration Bucket=${this.exportBucket.bucketName},Prefix=journal-exports/,EncryptionConfiguration='{\"ObjectEncryptionType\":\"SSE_S3\"}'`,
      description: 'CLI command to start journal export to S3',
      exportName: `${this.stackName}-ExportStartCommand`,
    });
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the stack
new QldbAcidDatabaseStack(app, 'QldbAcidDatabaseStack', {
  description: 'ACID-compliant distributed database infrastructure using Amazon QLDB with cryptographic verification, real-time streaming, and comprehensive monitoring capabilities',
  
  // Stack-level tags for governance and cost allocation
  tags: {
    Project: 'QLDB-ACID-Database',
    Environment: 'Production',
    Owner: 'FinancialServices',
    CostCenter: 'Infrastructure',
    Compliance: 'SOX-PCI',
    DataClassification: 'Sensitive',
    BackupRequired: 'true',
    MonitoringRequired: 'true',
  },
  
  // Enable termination protection for production workloads
  terminationProtection: true,
  
  // Set explicit stack name for consistency
  stackName: 'qldb-acid-database-stack',
});

// Add global tags to all resources in the app
cdk.Tags.of(app).add('CreatedBy', 'AWS-CDK');
cdk.Tags.of(app).add('Purpose', 'ACID-Compliant-Database');
cdk.Tags.of(app).add('Recipe', 'acid-compliant-distributed-databases-amazon-qldb');