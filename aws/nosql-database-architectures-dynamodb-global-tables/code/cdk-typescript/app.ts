#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as backup from 'aws-cdk-lib/aws-backup';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';

/**
 * Configuration interface for the DynamoDB Global Tables stack
 */
interface DynamoDBGlobalTablesConfig {
  /** Primary AWS region for the Global Table */
  readonly primaryRegion: string;
  /** Secondary AWS regions for Global Table replicas */
  readonly replicaRegions: string[];
  /** Base name for the DynamoDB table */
  readonly tableName: string;
  /** Environment name (e.g., 'dev', 'staging', 'prod') */
  readonly environment: string;
  /** Whether to enable point-in-time recovery */
  readonly enablePointInTimeRecovery: boolean;
  /** Whether to enable automated backups */
  readonly enableBackups: boolean;
  /** Whether to enable enhanced monitoring */
  readonly enableEnhancedMonitoring: boolean;
}

/**
 * Stack for creating DynamoDB Global Tables with comprehensive monitoring,
 * security, and backup capabilities across multiple AWS regions
 */
class DynamoDBGlobalTablesStack extends cdk.Stack {
  /** The primary DynamoDB table */
  public readonly table: dynamodb.Table;
  /** IAM role for applications to access DynamoDB */
  public readonly applicationRole: iam.Role;
  /** KMS key for encryption */
  public readonly encryptionKey: kms.Key;
  /** Lambda function for testing Global Tables functionality */
  public readonly testFunction?: lambda.Function;
  /** Backup vault for automated backups */
  public readonly backupVault?: backup.BackupVault;

  constructor(scope: Construct, id: string, config: DynamoDBGlobalTablesConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    // Create KMS key for encryption with automatic key rotation
    this.encryptionKey = new kms.Key(this, 'DynamoDBEncryptionKey', {
      description: `DynamoDB Global Tables encryption key for ${config.tableName}`,
      enableKeyRotation: true,
      keySpec: kms.KeySpec.SYMMETRIC_DEFAULT,
      keyUsage: kms.KeyUsage.ENCRYPT_DECRYPT,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // Use RETAIN for production
    });

    // Create alias for easier key reference
    new kms.Alias(this, 'DynamoDBEncryptionKeyAlias', {
      aliasName: `alias/dynamodb-global-${config.tableName}-${config.environment}`,
      targetKey: this.encryptionKey,
    });

    // Create IAM role for applications to access DynamoDB
    this.applicationRole = new iam.Role(this, 'ApplicationRole', {
      roleName: `DynamoDBGlobalTable-${config.tableName}-${config.environment}`,
      description: 'IAM role for applications to access DynamoDB Global Tables',
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('ec2.amazonaws.com')
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Create the primary DynamoDB table with Global Tables support
    this.table = new dynamodb.Table(this, 'GlobalTable', {
      tableName: `${config.tableName}-${config.environment}`,
      partitionKey: {
        name: 'PK',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'SK',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 10,
      writeCapacity: 10,
      // Enable DynamoDB Streams for Global Tables replication
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      // Enable encryption at rest with customer-managed KMS key
      encryption: dynamodb.TableEncryption.CUSTOMER_MANAGED,
      encryptionKey: this.encryptionKey,
      // Enable point-in-time recovery for data protection
      pointInTimeRecovery: config.enablePointInTimeRecovery,
      // Enable deletion protection for production environments
      deletionProtection: config.environment === 'prod',
      // Configure replica regions for Global Tables
      replicationRegions: config.replicaRegions,
      // Add comprehensive resource tags
      tags: [
        { key: 'Environment', value: config.environment },
        { key: 'Application', value: 'GlobalApp' },
        { key: 'Component', value: 'Database' },
        { key: 'ManagedBy', value: 'CDK' },
      ],
      removalPolicy: config.environment === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    // Add Global Secondary Index for flexible querying
    this.table.addGlobalSecondaryIndex({
      indexName: 'GSI1',
      partitionKey: {
        name: 'GSI1PK',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'GSI1SK',
        type: dynamodb.AttributeType.STRING,
      },
      readCapacity: 5,
      writeCapacity: 5,
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // Grant comprehensive DynamoDB permissions to the application role
    this.table.grantReadWriteData(this.applicationRole);
    this.table.grantStreamRead(this.applicationRole);

    // Add additional IAM permissions for Global Tables operations
    this.applicationRole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:DescribeTable',
        'dynamodb:DescribeStream',
        'dynamodb:ListStreams',
        'dynamodb:DescribeGlobalTable',
        'dynamodb:ListGlobalTables',
      ],
      resources: ['*'],
    }));

    // Create Lambda function for testing Global Tables functionality
    if (config.enableEnhancedMonitoring) {
      this.testFunction = new lambda.Function(this, 'GlobalTableTestFunction', {
        functionName: `global-table-test-${config.tableName}-${config.environment}`,
        runtime: lambda.Runtime.PYTHON_3_9,
        handler: 'index.handler',
        role: this.applicationRole,
        timeout: cdk.Duration.seconds(60),
        environment: {
          TABLE_NAME: this.table.tableName,
          REGIONS: [config.primaryRegion, ...config.replicaRegions].join(','),
        },
        code: lambda.Code.fromInline(`
import json
import boto3
import os
import uuid
from datetime import datetime, timezone

def handler(event, context):
    table_name = os.environ['TABLE_NAME']
    regions = os.environ['REGIONS'].split(',')
    
    results = {}
    
    for region in regions:
        try:
            dynamodb = boto3.resource('dynamodb', region_name=region)
            table = dynamodb.Table(table_name)
            
            # Test write operation
            test_item = {
                'PK': f'TEST#{uuid.uuid4()}',
                'SK': 'LAMBDA_TEST',
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'region': region,
                'test_data': f'Test from Lambda in {region}'
            }
            
            table.put_item(Item=test_item)
            
            # Test read operation
            response = table.scan(
                FilterExpression='attribute_exists(#r)',
                ExpressionAttributeNames={'#r': 'region'},
                Limit=5
            )
            
            results[region] = {
                'write_success': True,
                'items_count': response['Count'],
                'sample_items': response['Items'][:2]
            }
            
        except Exception as e:
            results[region] = {
                'error': str(e),
                'write_success': False
            }
    
    return {
        'statusCode': 200,
        'body': json.dumps(results, default=str)
    }
        `),
      });
    }

    // Create CloudWatch monitoring and alarms
    this.createMonitoringAlarms(config);

    // Create backup configuration if enabled
    if (config.enableBackups) {
      this.createBackupConfiguration(config);
    }

    // Output important resource information
    new cdk.CfnOutput(this, 'TableName', {
      value: this.table.tableName,
      description: 'Name of the DynamoDB Global Table',
    });

    new cdk.CfnOutput(this, 'TableArn', {
      value: this.table.tableArn,
      description: 'ARN of the DynamoDB Global Table',
    });

    new cdk.CfnOutput(this, 'ApplicationRoleArn', {
      value: this.applicationRole.roleArn,
      description: 'ARN of the IAM role for applications',
    });

    new cdk.CfnOutput(this, 'EncryptionKeyArn', {
      value: this.encryptionKey.keyArn,
      description: 'ARN of the KMS encryption key',
    });

    if (this.testFunction) {
      new cdk.CfnOutput(this, 'TestFunctionName', {
        value: this.testFunction.functionName,
        description: 'Name of the Lambda test function',
      });
    }
  }

  /**
   * Creates comprehensive CloudWatch monitoring and alarms for the Global Table
   */
  private createMonitoringAlarms(config: DynamoDBGlobalTablesConfig): void {
    // Create alarms for read throttling
    new cloudwatch.Alarm(this, 'ReadThrottleAlarm', {
      alarmName: `${config.tableName}-ReadThrottles-${config.environment}`,
      alarmDescription: `High read throttling on ${config.tableName}`,
      metric: this.table.metricThrottledRequestsForOperation('ReadThrottledEvents'),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create alarms for write throttling
    new cloudwatch.Alarm(this, 'WriteThrottleAlarm', {
      alarmName: `${config.tableName}-WriteThrottles-${config.environment}`,
      alarmDescription: `High write throttling on ${config.tableName}`,
      metric: this.table.metricThrottledRequestsForOperation('WriteThrottledEvents'),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create custom metric for replication lag monitoring
    const replicationLagMetric = new cloudwatch.Metric({
      namespace: 'AWS/DynamoDB',
      metricName: 'ReplicationDelay',
      dimensionsMap: {
        'TableName': this.table.tableName,
        'ReceivingRegion': config.primaryRegion,
      },
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    new cloudwatch.Alarm(this, 'ReplicationLagAlarm', {
      alarmName: `${config.tableName}-ReplicationLag-${config.environment}`,
      alarmDescription: `High replication lag on ${config.tableName}`,
      metric: replicationLagMetric,
      threshold: 1000, // 1 second
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Create CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'GlobalTableDashboard', {
      dashboardName: `DynamoDB-GlobalTable-${config.tableName}-${config.environment}`,
    });

    // Add widgets to the dashboard
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Read/Write Capacity Utilization',
        left: [
          this.table.metricConsumedReadCapacityUnits(),
          this.table.metricConsumedWriteCapacityUnits(),
        ],
        right: [
          this.table.metricReadCapacityUtilization(),
          this.table.metricWriteCapacityUtilization(),
        ],
        width: 12,
      }),
      new cloudwatch.GraphWidget({
        title: 'Throttled Requests',
        left: [
          this.table.metricThrottledRequestsForOperation('ReadThrottledEvents'),
          this.table.metricThrottledRequestsForOperation('WriteThrottledEvents'),
        ],
        width: 12,
      })
    );
  }

  /**
   * Creates automated backup configuration for the Global Table
   */
  private createBackupConfiguration(config: DynamoDBGlobalTablesConfig): void {
    // Create backup vault with encryption
    this.backupVault = new backup.BackupVault(this, 'BackupVault', {
      backupVaultName: `DynamoDB-Global-Backup-${config.tableName}-${config.environment}`,
      encryptionKey: this.encryptionKey,
      accessPolicy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('backup.amazonaws.com')],
            actions: ['backup:*'],
            resources: ['*'],
          }),
        ],
      }),
    });

    // Create backup plan with automated daily backups
    const backupPlan = new backup.BackupPlan(this, 'BackupPlan', {
      backupPlanName: `DynamoDB-Global-Backup-Plan-${config.tableName}-${config.environment}`,
      backupVault: this.backupVault,
      backupPlanRules: [
        {
          ruleName: 'DailyBackups',
          scheduleExpression: events.Schedule.cron({ hour: '2', minute: '0' }),
          startWindow: cdk.Duration.hours(1),
          completionWindow: cdk.Duration.hours(2),
          deleteAfter: cdk.Duration.days(30),
          recoveryPointTags: {
            'Environment': config.environment,
            'Application': 'GlobalApp',
            'BackupType': 'Daily',
          },
        },
      ],
    });

    // Create backup selection to specify which resources to backup
    new backup.BackupSelection(this, 'BackupSelection', {
      backupPlan: backupPlan,
      selectionName: `DynamoDB-Global-Selection-${config.environment}`,
      resources: [
        backup.BackupResource.fromDynamoDbTable(this.table),
      ],
      conditions: {
        stringEquals: {
          'aws:ResourceTag/Environment': [config.environment],
        },
      },
    });
  }
}

/**
 * CDK Application for DynamoDB Global Tables
 */
class DynamoDBGlobalTablesApp extends cdk.App {
  constructor() {
    super();

    // Configuration for the Global Tables deployment
    const config: DynamoDBGlobalTablesConfig = {
      primaryRegion: this.node.tryGetContext('primaryRegion') || 'us-east-1',
      replicaRegions: this.node.tryGetContext('replicaRegions') || ['eu-west-1', 'ap-southeast-1'],
      tableName: this.node.tryGetContext('tableName') || 'global-app-data',
      environment: this.node.tryGetContext('environment') || 'dev',
      enablePointInTimeRecovery: this.node.tryGetContext('enablePointInTimeRecovery') !== 'false',
      enableBackups: this.node.tryGetContext('enableBackups') !== 'false',
      enableEnhancedMonitoring: this.node.tryGetContext('enableEnhancedMonitoring') !== 'false',
    };

    // Create the primary stack in the primary region
    new DynamoDBGlobalTablesStack(this, 'DynamoDBGlobalTablesStack', config, {
      env: {
        region: config.primaryRegion,
        account: process.env.CDK_DEFAULT_ACCOUNT,
      },
      description: `DynamoDB Global Tables stack for ${config.tableName} in ${config.environment} environment`,
      tags: {
        Environment: config.environment,
        Application: 'GlobalApp',
        Component: 'Database',
        ManagedBy: 'CDK',
      },
    });
  }
}

// Initialize and run the CDK application
const app = new DynamoDBGlobalTablesApp();