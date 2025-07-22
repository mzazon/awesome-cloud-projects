#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as datasync from 'aws-cdk-lib/aws-datasync';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';

/**
 * Properties for the DataSync Stack
 */
interface DataSyncStackProps extends cdk.StackProps {
  /**
   * Optional prefix for resource names
   */
  readonly resourcePrefix?: string;
  
  /**
   * Schedule expression for automated transfers (default: daily at 2 AM UTC)
   */
  readonly scheduleExpression?: string;
  
  /**
   * Enable automated scheduling of DataSync tasks
   */
  readonly enableScheduling?: boolean;
  
  /**
   * S3 storage class for destination objects
   */
  readonly destinationStorageClass?: string;
}

/**
 * AWS CDK Stack for DataSync Data Transfer Automation
 * 
 * This stack creates a complete DataSync solution for automating data transfers
 * between S3 buckets with monitoring, scheduling, and reporting capabilities.
 */
export class DataSyncStack extends cdk.Stack {
  /**
   * The source S3 bucket for data transfers
   */
  public readonly sourceBucket: s3.Bucket;
  
  /**
   * The destination S3 bucket for data transfers
   */
  public readonly destinationBucket: s3.Bucket;
  
  /**
   * The DataSync task for transferring data
   */
  public readonly dataSyncTask: datasync.CfnTask;
  
  /**
   * CloudWatch log group for DataSync logs
   */
  public readonly logGroup: logs.LogGroup;
  
  /**
   * CloudWatch dashboard for monitoring
   */
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: DataSyncStackProps = {}) {
    super(scope, id, props);

    const resourcePrefix = props.resourcePrefix || 'datasync';
    const enableScheduling = props.enableScheduling ?? true;
    const scheduleExpression = props.scheduleExpression || 'rate(1 day)';

    // Create source S3 bucket with versioning and lifecycle policies
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${resourcePrefix}-source-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create destination S3 bucket with cross-region replication configuration
    this.destinationBucket = new s3.Bucket(this, 'DestinationBucket', {
      bucketName: `${resourcePrefix}-destination-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          enabled: true,
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(7),
        },
        {
          id: 'OptimizeStorage',
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

    // Create IAM role for DataSync with comprehensive S3 permissions
    const dataSyncServiceRole = new iam.Role(this, 'DataSyncServiceRole', {
      roleName: `${resourcePrefix}-datasync-service-role`,
      assumedBy: new iam.ServicePrincipal('datasync.amazonaws.com'),
      description: 'Service role for DataSync to access S3 buckets and CloudWatch',
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
          statements: [
            // Bucket-level permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketLocation',
                's3:ListBucket',
                's3:ListBucketMultipartUploads',
                's3:GetBucketVersioning',
              ],
              resources: [
                this.sourceBucket.bucketArn,
                this.destinationBucket.bucketArn,
              ],
            }),
            // Object-level permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectTagging',
                's3:GetObjectVersion',
                's3:GetObjectVersionTagging',
                's3:PutObject',
                's3:PutObjectTagging',
                's3:DeleteObject',
                's3:AbortMultipartUpload',
                's3:ListMultipartUploadParts',
              ],
              resources: [
                `${this.sourceBucket.bucketArn}/*`,
                `${this.destinationBucket.bucketArn}/*`,
              ],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws/datasync/*`],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch log group for DataSync with retention policy
    this.logGroup = new logs.LogGroup(this, 'DataSyncLogGroup', {
      logGroupName: `/aws/datasync/${resourcePrefix}-task`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create DataSync source location for S3
    const sourceLocation = new datasync.CfnLocationS3(this, 'SourceLocation', {
      s3BucketArn: this.sourceBucket.bucketArn,
      s3Config: {
        bucketAccessRoleArn: dataSyncServiceRole.roleArn,
      },
      subdirectory: '/',
      tags: [
        {
          key: 'Name',
          value: `${resourcePrefix}-source-location`,
        },
        {
          key: 'Purpose',
          value: 'DataSync source location for automated transfers',
        },
      ],
    });

    // Create DataSync destination location for S3
    const destinationLocation = new datasync.CfnLocationS3(this, 'DestinationLocation', {
      s3BucketArn: this.destinationBucket.bucketArn,
      s3Config: {
        bucketAccessRoleArn: dataSyncServiceRole.roleArn,
      },
      subdirectory: '/',
      s3StorageClass: props.destinationStorageClass || 'STANDARD',
      tags: [
        {
          key: 'Name',
          value: `${resourcePrefix}-destination-location`,
        },
        {
          key: 'Purpose',
          value: 'DataSync destination location for automated transfers',
        },
      ],
    });

    // Create DataSync task with comprehensive options
    this.dataSyncTask = new datasync.CfnTask(this, 'DataSyncTask', {
      sourceLocationArn: sourceLocation.attrLocationArn,
      destinationLocationArn: destinationLocation.attrLocationArn,
      name: `${resourcePrefix}-transfer-task`,
      cloudWatchLogGroupArn: this.logGroup.logGroupArn,
      options: {
        // Data verification and integrity
        verifyMode: 'POINT_IN_TIME_CONSISTENT',
        overwriteMode: 'ALWAYS',
        preserveDeletedFiles: 'PRESERVE',
        preserveDevices: 'NONE',
        posixPermissions: 'NONE',
        
        // Transfer optimization
        bytesPerSecond: -1, // No bandwidth limit
        taskQueueing: 'ENABLED',
        transferMode: 'CHANGED', // Only transfer changed files
        
        // Logging and monitoring
        logLevel: 'TRANSFER',
      },
      includes: [
        {
          filterType: 'SIMPLE_PATTERN',
          value: '*', // Include all files by default
        },
      ],
      tags: [
        {
          key: 'Name',
          value: `${resourcePrefix}-task`,
        },
        {
          key: 'Purpose',
          value: 'Automated data transfer between S3 buckets',
        },
        {
          key: 'Schedule',
          value: enableScheduling ? scheduleExpression : 'Manual',
        },
      ],
    });

    // Configure task reporting to destination bucket
    const taskReportConfig = new datasync.CfnTask(this, 'TaskReportConfig', {
      sourceLocationArn: sourceLocation.attrLocationArn,
      destinationLocationArn: destinationLocation.attrLocationArn,
      name: `${resourcePrefix}-report-task`,
      reportConfig: {
        destination: {
          s3: {
            bucketArn: this.destinationBucket.bucketArn,
            subdirectory: 'datasync-reports',
            bucketAccessRoleArn: dataSyncServiceRole.roleArn,
          },
        },
        outputType: 'SUMMARY_ONLY',
        reportLevel: 'ERRORS_ONLY',
        overrides: {
          transferred: {
            reportLevel: 'ERRORS_ONLY',
          },
          verified: {
            reportLevel: 'ERRORS_ONLY',
          },
          deleted: {
            reportLevel: 'ERRORS_ONLY',
          },
          skipped: {
            reportLevel: 'ERRORS_ONLY',
          },
        },
      },
    });

    // Create EventBridge rule for scheduled execution (if enabled)
    if (enableScheduling) {
      // Create IAM role for EventBridge to invoke DataSync
      const eventBridgeRole = new iam.Role(this, 'EventBridgeRole', {
        roleName: `${resourcePrefix}-eventbridge-role`,
        assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
        description: 'Role for EventBridge to trigger DataSync task execution',
        inlinePolicies: {
          DataSyncExecutionPolicy: new iam.PolicyDocument({
            statements: [
              new iam.PolicyStatement({
                effect: iam.Effect.ALLOW,
                actions: ['datasync:StartTaskExecution'],
                resources: [this.dataSyncTask.attrTaskArn],
              }),
            ],
          }),
        },
      });

      // Create EventBridge rule for scheduled execution
      const scheduledRule = new events.Rule(this, 'ScheduledExecutionRule', {
        ruleName: `${resourcePrefix}-scheduled-execution`,
        description: 'Scheduled execution of DataSync task',
        schedule: events.Schedule.expression(scheduleExpression),
        enabled: true,
      });

      // Add DataSync task as target
      scheduledRule.addTarget(
        new targets.AwsApi({
          service: 'DataSync',
          action: 'startTaskExecution',
          parameters: {
            TaskArn: this.dataSyncTask.attrTaskArn,
          },
          role: eventBridgeRole,
        })
      );
    }

    // Create CloudWatch dashboard for monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'DataSyncDashboard', {
      dashboardName: `${resourcePrefix}-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'DataSync Transfer Metrics',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/DataSync',
                metricName: 'BytesTransferred',
                dimensionsMap: {
                  TaskArn: this.dataSyncTask.attrTaskArn,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
            right: [
              new cloudwatch.Metric({
                namespace: 'AWS/DataSync',
                metricName: 'FilesTransferred',
                dimensionsMap: {
                  TaskArn: this.dataSyncTask.attrTaskArn,
                },
                statistic: 'Sum',
                period: cdk.Duration.minutes(5),
              }),
            ],
          }),
          new cloudwatch.SingleValueWidget({
            title: 'Latest Transfer Status',
            width: 12,
            height: 6,
            metrics: [
              new cloudwatch.Metric({
                namespace: 'AWS/DataSync',
                metricName: 'TaskExecutionResult',
                dimensionsMap: {
                  TaskArn: this.dataSyncTask.attrTaskArn,
                },
                statistic: 'Maximum',
                period: cdk.Duration.hours(1),
              }),
            ],
          }),
        ],
        [
          new cloudwatch.LogQueryWidget({
            title: 'Recent DataSync Logs',
            width: 24,
            height: 6,
            logGroups: [this.logGroup],
            queryLines: [
              'fields @timestamp, @message',
              'filter @message like /ERROR/ or @message like /WARN/',
              'sort @timestamp desc',
              'limit 20',
            ],
          }),
        ],
      ],
    });

    // CloudWatch alarms for monitoring task failures
    const taskFailureAlarm = new cloudwatch.Alarm(this, 'TaskFailureAlarm', {
      alarmName: `${resourcePrefix}-task-failure`,
      alarmDescription: 'DataSync task execution failure',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/DataSync',
        metricName: 'TaskExecutionResult',
        dimensionsMap: {
          TaskArn: this.dataSyncTask.attrTaskArn,
        },
        statistic: 'Maximum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1, // 1 indicates failure
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Outputs for reference and integration
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'Name of the source S3 bucket',
      exportName: `${this.stackName}-SourceBucketName`,
    });

    new cdk.CfnOutput(this, 'DestinationBucketName', {
      value: this.destinationBucket.bucketName,
      description: 'Name of the destination S3 bucket',
      exportName: `${this.stackName}-DestinationBucketName`,
    });

    new cdk.CfnOutput(this, 'DataSyncTaskArn', {
      value: this.dataSyncTask.attrTaskArn,
      description: 'ARN of the DataSync task',
      exportName: `${this.stackName}-DataSyncTaskArn`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: this.logGroup.logGroupName,
      description: 'Name of the CloudWatch log group',
      exportName: `${this.stackName}-LogGroupName`,
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard',
    });

    // Add comprehensive tagging to all resources
    cdk.Tags.of(this).add('Project', 'DataSync-Automation');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'Infrastructure-Team');
    cdk.Tags.of(this).add('CostCenter', 'DataManagement');
  }

  /**
   * Method to manually trigger a DataSync task execution
   * This can be called from other constructs or scripts
   */
  public createManualExecutionLambda(): void {
    // This method could be extended to create a Lambda function
    // that can manually trigger DataSync task executions
    // Implementation would include Lambda function creation and IAM permissions
  }

  /**
   * Method to add custom filters to the DataSync task
   * @param filters Array of filter patterns to include or exclude
   */
  public addTaskFilters(filters: { filterType: string; value: string }[]): void {
    // This method could be used to add additional filters to the task
    // Implementation would update the task configuration with new filters
  }
}

// Create the CDK app
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const resourcePrefix = app.node.tryGetContext('resourcePrefix') || process.env.RESOURCE_PREFIX || 'datasync';
const enableScheduling = app.node.tryGetContext('enableScheduling') ?? true;
const scheduleExpression = app.node.tryGetContext('scheduleExpression') || 'rate(1 day)';
const destinationStorageClass = app.node.tryGetContext('destinationStorageClass') || 'STANDARD';

// Create the DataSync stack
new DataSyncStack(app, 'DataSyncAutomationStack', {
  resourcePrefix,
  enableScheduling,
  scheduleExpression,
  destinationStorageClass,
  description: 'AWS DataSync automation stack for reliable data transfer between S3 buckets with monitoring and scheduling',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Application: 'DataSync-Automation',
    Version: '1.0.0',
    ManagedBy: 'AWS-CDK',
  },
});