import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Construct } from 'constructs';

export interface S3InventoryStorageAnalyticsStackProps extends cdk.StackProps {
  readonly stackName?: string;
}

export class S3InventoryStorageAnalyticsStack extends cdk.Stack {
  public readonly sourceBucket: s3.Bucket;
  public readonly destinationBucket: s3.Bucket;
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly athenaWorkGroup: athena.CfnWorkGroup;
  public readonly analyticsFunction: lambda.Function;
  public readonly dashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props?: S3InventoryStorageAnalyticsStackProps) {
    super(scope, id, props);

    // Parameters for customization
    const bucketPrefix = new cdk.CfnParameter(this, 'BucketPrefix', {
      type: 'String',
      default: 'storage-analytics',
      description: 'Prefix for S3 bucket names',
      allowedPattern: '^[a-z0-9-]+$',
      constraintDescription: 'Bucket prefix must contain only lowercase letters, numbers, and hyphens',
    });

    const inventorySchedule = new cdk.CfnParameter(this, 'InventorySchedule', {
      type: 'String',
      default: 'Daily',
      allowedValues: ['Daily', 'Weekly'],
      description: 'S3 Inventory report generation frequency',
    });

    const analysisPrefix = new cdk.CfnParameter(this, 'AnalysisPrefix', {
      type: 'String',
      default: 'data/',
      description: 'Prefix filter for Storage Class Analysis',
    });

    // Generate unique suffix for resource names
    const randomSuffix = cdk.Fn.select(0, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', this.stackId))));

    // Create source S3 bucket for data storage
    this.sourceBucket = new s3.Bucket(this, 'SourceBucket', {
      bucketName: `${bucketPrefix.valueAsString}-source-${randomSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'sample-lifecycle-rule',
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
    });

    // Create destination S3 bucket for inventory reports and analytics data
    this.destinationBucket = new s3.Bucket(this, 'DestinationBucket', {
      bucketName: `${bucketPrefix.valueAsString}-reports-${randomSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
    });

    // Create bucket policy for S3 Inventory service access
    const inventoryBucketPolicy = new iam.PolicyDocument({
      statements: [
        new iam.PolicyStatement({
          sid: 'InventoryDestinationBucketPolicy',
          effect: iam.Effect.ALLOW,
          principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
          actions: ['s3:PutObject'],
          resources: [`${this.destinationBucket.bucketArn}/*`],
          conditions: {
            ArnLike: {
              'aws:SourceArn': this.sourceBucket.bucketArn,
            },
            StringEquals: {
              'aws:SourceAccount': this.account,
              's3:x-amz-acl': 'bucket-owner-full-control',
            },
          },
        }),
        new iam.PolicyStatement({
          sid: 'InventoryDestinationBucketGetLocation',
          effect: iam.Effect.ALLOW,
          principals: [new iam.ServicePrincipal('s3.amazonaws.com')],
          actions: ['s3:GetBucketLocation'],
          resources: [this.destinationBucket.bucketArn],
          conditions: {
            StringEquals: {
              'aws:SourceAccount': this.account,
            },
          },
        }),
      ],
    });

    // Apply the bucket policy to destination bucket
    this.destinationBucket.addToResourcePolicy(inventoryBucketPolicy.statements[0]);
    this.destinationBucket.addToResourcePolicy(inventoryBucketPolicy.statements[1]);

    // Configure S3 Inventory on source bucket
    const inventoryConfiguration = new s3.CfnBucket.InventoryConfigurationProperty({
      id: 'daily-inventory-config',
      enabled: true,
      includedObjectVersions: 'Current',
      scheduleFrequency: inventorySchedule.valueAsString,
      optionalFields: [
        'Size',
        'LastModifiedDate',
        'StorageClass',
        'ETag',
        'ReplicationStatus',
        'EncryptionStatus',
      ],
      destination: {
        bucketArn: this.destinationBucket.bucketArn,
        format: 'CSV',
        prefix: 'inventory-reports/',
        bucketAccountId: this.account,
      },
    });

    // Add inventory configuration to source bucket
    const sourceBucketCfn = this.sourceBucket.node.defaultChild as s3.CfnBucket;
    sourceBucketCfn.inventoryConfigurations = [inventoryConfiguration];

    // Configure Storage Class Analysis on source bucket
    const analyticsConfiguration = new s3.CfnBucket.AnalyticsConfigurationProperty({
      id: 'storage-class-analysis',
      prefix: analysisPrefix.valueAsString,
      storageClassAnalysis: {
        dataExport: {
          outputSchemaVersion: 'V_1',
          destination: {
            format: 'CSV',
            bucketArn: this.destinationBucket.bucketArn,
            prefix: 'analytics-reports/',
            bucketAccountId: this.account,
          },
        },
      },
    });

    // Add analytics configuration to source bucket
    sourceBucketCfn.analyticsConfigurations = [analyticsConfiguration];

    // Create AWS Glue Database for Athena queries
    this.glueDatabase = new glue.CfnDatabase(this, 'InventoryDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 's3-inventory-db',
        description: 'Database for S3 inventory analysis',
      },
    });

    // Create Athena WorkGroup for query organization and cost control
    this.athenaWorkGroup = new athena.CfnWorkGroup(this, 'InventoryWorkGroup', {
      name: 'storage-analytics-workgroup',
      description: 'WorkGroup for S3 storage analytics queries',
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${this.destinationBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
        bytesScannedCutoffPerQuery: 1000000000, // 1GB limit per query
      },
    });

    // Create IAM role for Lambda function
    const lambdaRole = new iam.Role(this, 'AnalyticsLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for S3 storage analytics Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        StorageAnalyticsPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'athena:StartQueryExecution',
                'athena:GetQueryExecution',
                'athena:GetQueryResults',
                'athena:GetWorkGroup',
              ],
              resources: [
                this.athenaWorkGroup.attrWorkGroupConfigurationResultConfigurationOutputLocation || '*',
                `arn:aws:athena:${this.region}:${this.account}:workgroup/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:ListBucket',
              ],
              resources: [
                this.destinationBucket.bucketArn,
                `${this.destinationBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:GetDatabase',
                'glue:GetTable',
                'glue:GetPartitions',
              ],
              resources: [
                `arn:aws:glue:${this.region}:${this.account}:catalog`,
                `arn:aws:glue:${this.region}:${this.account}:database/${this.glueDatabase.ref}`,
                `arn:aws:glue:${this.region}:${this.account}:table/${this.glueDatabase.ref}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for automated storage analytics
    this.analyticsFunction = new lambda.Function(this, 'StorageAnalyticsFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Automated S3 storage analytics and reporting function',
      environment: {
        ATHENA_DATABASE: this.glueDatabase.ref,
        ATHENA_TABLE: 'inventory_table',
        DEST_BUCKET: this.destinationBucket.bucketName,
        WORKGROUP_NAME: this.athenaWorkGroup.ref,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Lambda function to execute storage analytics queries using Amazon Athena.
    
    This function performs automated analysis of S3 inventory data to generate
    storage optimization insights and cost analysis reports.
    """
    
    athena = boto3.client('athena')
    s3 = boto3.client('s3')
    
    # Configuration from environment variables
    database = os.environ['ATHENA_DATABASE']
    table = os.environ['ATHENA_TABLE']
    output_bucket = os.environ['DEST_BUCKET']
    workgroup = os.environ['WORKGROUP_NAME']
    
    # SQL query for storage class distribution analysis
    query = f"""
    -- Storage class distribution analysis query
    -- This query analyzes the distribution of objects across storage classes
    -- and calculates total storage consumption and average object sizes
    
    SELECT 
        storage_class,
        COUNT(*) as object_count,
        SUM(size) as total_size_bytes,
        ROUND(SUM(size) / 1024.0 / 1024.0 / 1024.0, 2) as total_size_gb,
        ROUND(AVG(size) / 1024.0 / 1024.0, 2) as avg_size_mb,
        ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) as percentage_of_objects
    FROM {database}.{table}
    WHERE storage_class IS NOT NULL
    GROUP BY storage_class
    ORDER BY total_size_bytes DESC;
    """
    
    try:
        # Execute the Athena query
        response = athena.start_query_execution(
            QueryString=query,
            ResultConfiguration={{
                'OutputLocation': f's3://{output_bucket}/athena-results/',
                'EncryptionConfiguration': {{
                    'EncryptionOption': 'SSE_S3'
                }}
            }},
            WorkGroup=workgroup
        )
        
        query_execution_id = response['QueryExecutionId']
        
        # Log the successful execution
        print(f"Storage analytics query executed successfully. Query ID: {query_execution_id}")
        
        return {{
            'statusCode': 200,
            'body': json.dumps({{
                'message': 'Storage analytics query executed successfully',
                'queryExecutionId': query_execution_id,
                'timestamp': datetime.utcnow().isoformat(),
                'database': database,
                'table': table
            }})
        }}
        
    except Exception as e:
        error_message = f"Error executing storage analytics query: {str(e)}"
        print(error_message)
        
        return {{
            'statusCode': 500,
            'body': json.dumps({{
                'error': error_message,
                'timestamp': datetime.utcnow().isoformat()
            }})
        }}
`),
    });

    // Create EventBridge rule for daily automated reports
    const analyticsScheduleRule = new events.Rule(this, 'AnalyticsScheduleRule', {
      ruleName: 'storage-analytics-daily-schedule',
      description: 'Daily schedule for automated S3 storage analytics reporting',
      schedule: events.Schedule.rate(cdk.Duration.days(1)),
      enabled: true,
    });

    // Add Lambda function as target for the EventBridge rule
    analyticsScheduleRule.addTarget(new targets.LambdaFunction(this.analyticsFunction));

    // Create CloudWatch Dashboard for storage metrics monitoring
    this.dashboard = new cloudwatch.Dashboard(this, 'StorageAnalyticsDashboard', {
      dashboardName: `S3-Storage-Analytics-${randomSuffix}`,
      defaultInterval: cdk.Duration.hours(24),
    });

    // Add storage metrics widgets to dashboard
    const storageMetricsWidget = new cloudwatch.GraphWidget({
      title: 'S3 Storage Metrics',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytes',
          dimensionsMap: {
            BucketName: this.sourceBucket.bucketName,
            StorageType: 'StandardStorage',
          },
          statistic: 'Average',
          period: cdk.Duration.days(1),
        }),
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'BucketSizeBytes',
          dimensionsMap: {
            BucketName: this.sourceBucket.bucketName,
            StorageType: 'StandardIAStorage',
          },
          statistic: 'Average',
          period: cdk.Duration.days(1),
        }),
      ],
      right: [
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'NumberOfObjects',
          dimensionsMap: {
            BucketName: this.sourceBucket.bucketName,
            StorageType: 'AllStorageTypes',
          },
          statistic: 'Average',
          period: cdk.Duration.days(1),
        }),
      ],
    });

    // Add request metrics widget to dashboard
    const requestMetricsWidget = new cloudwatch.GraphWidget({
      title: 'S3 Request Metrics',
      width: 12,
      height: 6,
      left: [
        new cloudwatch.Metric({
          namespace: 'AWS/S3',
          metricName: 'AllRequests',
          dimensionsMap: {
            BucketName: this.sourceBucket.bucketName,
            FilterId: 'EntireBucket',
          },
          statistic: 'Sum',
          period: cdk.Duration.hours(1),
        }),
      ],
    });

    // Add Lambda function metrics widget
    const lambdaMetricsWidget = new cloudwatch.GraphWidget({
      title: 'Analytics Function Metrics',
      width: 12,
      height: 6,
      left: [
        this.analyticsFunction.metricInvocations({
          period: cdk.Duration.hours(1),
        }),
        this.analyticsFunction.metricErrors({
          period: cdk.Duration.hours(1),
        }),
      ],
      right: [
        this.analyticsFunction.metricDuration({
          period: cdk.Duration.hours(1),
        }),
      ],
    });

    // Add widgets to dashboard
    this.dashboard.addWidgets(storageMetricsWidget);
    this.dashboard.addWidgets(requestMetricsWidget);
    this.dashboard.addWidgets(lambdaMetricsWidget);

    // Output important resource information
    new cdk.CfnOutput(this, 'SourceBucketName', {
      value: this.sourceBucket.bucketName,
      description: 'Name of the source S3 bucket for data storage',
      exportName: `${this.stackName}-SourceBucket`,
    });

    new cdk.CfnOutput(this, 'DestinationBucketName', {
      value: this.destinationBucket.bucketName,
      description: 'Name of the destination S3 bucket for reports',
      exportName: `${this.stackName}-DestinationBucket`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'Name of the AWS Glue database for Athena queries',
      exportName: `${this.stackName}-GlueDatabase`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkGroupName', {
      value: this.athenaWorkGroup.ref,
      description: 'Name of the Athena WorkGroup for analytics queries',
      exportName: `${this.stackName}-AthenaWorkGroup`,
    });

    new cdk.CfnOutput(this, 'AnalyticsFunctionName', {
      value: this.analyticsFunction.functionName,
      description: 'Name of the Lambda function for automated analytics',
      exportName: `${this.stackName}-AnalyticsFunction`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${this.dashboard.dashboardName}`,
      description: 'URL to access the CloudWatch dashboard',
      exportName: `${this.stackName}-DashboardURL`,
    });

    new cdk.CfnOutput(this, 'SampleDataCommands', {
      value: [
        `echo "Sample data for storage analytics" > sample-file.txt`,
        `aws s3 cp sample-file.txt s3://${this.sourceBucket.bucketName}/data/sample-file.txt`,
        `aws s3 cp sample-file.txt s3://${this.sourceBucket.bucketName}/logs/access-log.txt`,
        `aws s3 cp sample-file.txt s3://${this.sourceBucket.bucketName}/archive/old-data.txt`,
      ].join(' && '),
      description: 'Commands to upload sample data for testing',
      exportName: `${this.stackName}-SampleDataCommands`,
    });
  }
}