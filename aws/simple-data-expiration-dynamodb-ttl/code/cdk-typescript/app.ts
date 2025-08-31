#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * CDK Stack for Data Expiration Automation with DynamoDB TTL
 * 
 * This stack creates a DynamoDB table with Time-To-Live (TTL) feature enabled
 * for automated data lifecycle management. The solution demonstrates cost-effective
 * data expiration for session data, cache entries, and other time-sensitive information.
 */
export class DataExpirationStack extends cdk.Stack {
  public readonly sessionTable: dynamodb.Table;
  public readonly ttlDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate a unique suffix for resource naming
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create DynamoDB table for session data with TTL enabled
    this.sessionTable = new dynamodb.Table(this, 'SessionDataTable', {
      tableName: `session-data-${uniqueSuffix}`,
      partitionKey: {
        name: 'user_id',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'session_id',
        type: dynamodb.AttributeType.STRING,
      },
      // Use ON_DEMAND billing mode for cost efficiency with variable workloads
      billingMode: dynamodb.BillingMode.ON_DEMAND,
      // Enable TTL on the 'expires_at' attribute
      timeToLiveAttribute: 'expires_at',
      // Enable point-in-time recovery for data protection
      pointInTimeRecovery: true,
      // Configure removal policy for development/testing environments
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      // Add tags for cost tracking and resource management
      tags: {
        Purpose: 'SessionManagement',
        DataLifecycle: 'TTLEnabled',
        CostOptimization: 'AutoExpiration',
      },
    });

    // Create CloudWatch Dashboard for TTL monitoring
    this.ttlDashboard = new cloudwatch.Dashboard(this, 'TTLMonitoringDashboard', {
      dashboardName: `ttl-monitoring-${uniqueSuffix}`,
      widgets: [
        [
          // TTL Deletion Count Widget
          new cloudwatch.GraphWidget({
            title: 'DynamoDB TTL Deletions',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'TimeToLiveDeletedItemCount',
                dimensionsMap: {
                  TableName: this.sessionTable.tableName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          // Table Size and Item Count Widgets
          new cloudwatch.GraphWidget({
            title: 'Table Metrics',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ItemCount',
                dimensionsMap: {
                  TableName: this.sessionTable.tableName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'TableSizeBytes',
                dimensionsMap: {
                  TableName: this.sessionTable.tableName,
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
        [
          // Read and Write Capacity Widgets
          new cloudwatch.GraphWidget({
            title: 'Read/Write Capacity Units',
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ConsumedReadCapacityUnits',
                dimensionsMap: {
                  TableName: this.sessionTable.tableName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/DynamoDB',
                metricName: 'ConsumedWriteCapacityUnits',
                dimensionsMap: {
                  TableName: this.sessionTable.tableName,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            width: 12,
            height: 6,
          }),
        ],
      ],
    });

    // Create CloudWatch Alarms for monitoring TTL operations
    const ttlDeletionAlarm = new cloudwatch.Alarm(this, 'TTLDeletionAlarm', {
      alarmName: `ttl-deletion-alarm-${uniqueSuffix}`,
      alarmDescription: 'Alarm when TTL deletions exceed expected threshold',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DynamoDB',
        metricName: 'TimeToLiveDeletedItemCount',
        dimensionsMap: {
          TableName: this.sessionTable.tableName,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1000, // Adjust based on expected deletion volume
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Output important information for application integration
    new cdk.CfnOutput(this, 'TableName', {
      value: this.sessionTable.tableName,
      description: 'DynamoDB Table Name for session data with TTL enabled',
      exportName: `${this.stackName}-TableName`,
    });

    new cdk.CfnOutput(this, 'TableArn', {
      value: this.sessionTable.tableArn,
      description: 'DynamoDB Table ARN for IAM policy configuration',
      exportName: `${this.stackName}-TableArn`,
    });

    new cdk.CfnOutput(this, 'TTLAttribute', {
      value: 'expires_at',
      description: 'TTL attribute name for timestamp values (Unix epoch format)',
      exportName: `${this.stackName}-TTLAttribute`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.ttlDashboard.dashboardName}`,
      description: 'CloudWatch Dashboard URL for TTL monitoring',
    });

    new cdk.CfnOutput(this, 'SampleQueries', {
      value: JSON.stringify({
        scanActiveItems: `aws dynamodb scan --table-name ${this.sessionTable.tableName} --filter-expression "#ttl > :current_time" --expression-attribute-names '{"#ttl": "expires_at"}' --expression-attribute-values '{":current_time": {"N": "UNIX_TIMESTAMP"}}'`,
        putItemWithTTL: `aws dynamodb put-item --table-name ${this.sessionTable.tableName} --item '{"user_id": {"S": "user123"}, "session_id": {"S": "session123"}, "expires_at": {"N": "UNIX_TIMESTAMP"}}'`,
      }),
      description: 'Sample CLI commands for TTL operations (replace UNIX_TIMESTAMP with actual values)',
    });
  }
}

/**
 * Main CDK Application
 * 
 * This application creates a complete data expiration solution using DynamoDB TTL.
 * The solution includes monitoring, alerting, and follows AWS Well-Architected principles.
 */
const app = new cdk.App();

// Create the main stack with appropriate naming and environment configuration
const dataExpirationStack = new DataExpirationStack(app, 'DataExpirationStack', {
  stackName: 'data-expiration-dynamodb-ttl',
  description: 'Data Expiration Automation with DynamoDB TTL - Cost-effective data lifecycle management',
  
  // Use CDK environment variables or specify explicitly
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add stack-level tags for resource management
  tags: {
    Project: 'DataExpirationAutomation',
    Environment: process.env.NODE_ENV || 'development',
    CostCenter: 'Engineering',
    Application: 'SessionManagement',
  },
});

// Add metadata to help with stack identification and documentation
cdk.Tags.of(dataExpirationStack).add('CDKVersion', cdk.VERSION);
cdk.Tags.of(dataExpirationStack).add('Recipe', 'simple-data-expiration-dynamodb-ttl');
cdk.Tags.of(dataExpirationStack).add('Documentation', 'https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/TTL.html');