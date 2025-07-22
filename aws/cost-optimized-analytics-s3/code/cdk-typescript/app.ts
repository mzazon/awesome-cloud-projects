#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as ce from 'aws-cdk-lib/aws-ce';
import * as iam from 'aws-cdk-lib/aws-iam';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for Cost-Optimized Analytics with S3 Tiering
 * 
 * This stack creates infrastructure for automated storage cost optimization
 * while maintaining analytics capabilities through S3 Intelligent-Tiering,
 * AWS Glue Data Catalog, and Amazon Athena.
 */
export class CostOptimizedAnalyticsStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // S3 Bucket with Intelligent-Tiering and encryption
    const analyticsBucket = new s3.Bucket(this, 'AnalyticsBucket', {
      bucketName: `cost-optimized-analytics-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY, // For demo purposes
      autoDeleteObjects: true, // For demo purposes
      intelligentTieringConfigurations: [
        {
          id: 'cost-optimization-config',
          status: s3.IntelligentTieringStatus.ENABLED,
          prefix: 'analytics-data/',
          archiveAccessTierTime: cdk.Duration.days(90),
          deepArchiveAccessTierTime: cdk.Duration.days(180),
        },
      ],
      lifecycleRules: [
        {
          id: 'intelligent-tiering-transition',
          enabled: true,
          prefix: 'analytics-data/',
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(0), // Immediate enrollment
            },
          ],
        },
      ],
    });

    // Add bucket policy for secure access
    analyticsBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyInsecureConnections',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          analyticsBucket.bucketArn,
          analyticsBucket.arnForObjects('*'),
        ],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    // IAM Role for AWS Glue
    const glueRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `glue-service-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:ListBucket',
                's3:GetBucketLocation',
              ],
              resources: [
                analyticsBucket.bucketArn,
                analyticsBucket.arnForObjects('*'),
              ],
            }),
          ],
        }),
      },
    });

    // AWS Glue Database
    const glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `analytics-database-${uniqueSuffix}`,
        description: 'Cost-optimized analytics database for transaction logs',
      },
    });

    // AWS Glue Table for transaction logs
    const glueTable = new glue.CfnTable(this, 'GlueTable', {
      catalogId: this.account,
      databaseName: glueDatabase.ref,
      tableInput: {
        name: 'transaction_logs',
        description: 'Transaction logs for fraud detection analytics',
        tableType: 'EXTERNAL_TABLE',
        parameters: {
          'classification': 'csv',
          'delimiter': ',',
          'skip.header.line.count': '0',
        },
        storageDescriptor: {
          columns: [
            { name: 'timestamp', type: 'string' },
            { name: 'user_id', type: 'string' },
            { name: 'transaction_id', type: 'string' },
            { name: 'amount', type: 'string' },
          ],
          location: `s3://${analyticsBucket.bucketName}/analytics-data/`,
          inputFormat: 'org.apache.hadoop.mapred.TextInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
            parameters: {
              'field.delim': ',',
            },
          },
        },
      },
    });

    // Amazon Athena Workgroup with cost controls
    const athenaWorkgroup = new athena.CfnWorkGroup(this, 'AthenaWorkgroup', {
      name: `cost-optimized-workgroup-${uniqueSuffix}`,
      description: 'Cost-optimized workgroup for analytics queries',
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${analyticsBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
        bytesScannedCutoffPerQuery: 1073741824, // 1GB limit
      },
    });

    // CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'CostOptimizationDashboard', {
      dashboardName: `S3-Cost-Optimization-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'S3 Intelligent-Tiering Storage Distribution',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: analyticsBucket.bucketName,
                  StorageType: 'IntelligentTieringFAStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Frequent Access Tier',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: analyticsBucket.bucketName,
                  StorageType: 'IntelligentTieringIAStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Infrequent Access Tier',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: analyticsBucket.bucketName,
                  StorageType: 'IntelligentTieringAAStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Archive Access Tier',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: analyticsBucket.bucketName,
                  StorageType: 'IntelligentTieringAIAStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Archive Instant Access',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/S3',
                metricName: 'BucketSizeBytes',
                dimensionsMap: {
                  BucketName: analyticsBucket.bucketName,
                  StorageType: 'IntelligentTieringDAAStorage',
                },
                statistic: 'Average',
                period: cdk.Duration.minutes(5),
                label: 'Deep Archive Access',
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Athena Query Performance',
            width: 12,
            height: 6,
            left: [
              new cloudwatch.Metric({
                namespace: 'AWS/Athena',
                metricName: 'DataScannedInBytes',
                dimensionsMap: {
                  WorkGroup: athenaWorkgroup.name!,
                },
                statistic: 'Sum',
                period: cdk.Duration.hours(1),
                label: 'Data Scanned (Bytes)',
              }),
              new cloudwatch.Metric({
                namespace: 'AWS/Athena',
                metricName: 'QueryExecutionTime',
                dimensionsMap: {
                  WorkGroup: athenaWorkgroup.name!,
                },
                statistic: 'Average',
                period: cdk.Duration.hours(1),
                label: 'Query Execution Time (ms)',
              }),
            ],
          }),
        ],
      ],
    });

    // Cost Anomaly Detector for S3 costs
    const costAnomalyDetector = new ce.CfnAnomalyDetector(this, 'S3CostAnomalyDetector', {
      detectorName: `S3-Cost-Anomaly-${uniqueSuffix}`,
      monitorType: 'DIMENSIONAL',
      dimensionSpecification: {
        dimension: 'SERVICE',
        values: ['Amazon Simple Storage Service'],
      },
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'S3BucketName', {
      value: analyticsBucket.bucketName,
      description: 'Name of the S3 bucket with Intelligent-Tiering',
      exportName: `${this.stackName}-S3BucketName`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Name of the AWS Glue database',
      exportName: `${this.stackName}-GlueDatabaseName`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkgroupName', {
      value: athenaWorkgroup.name!,
      description: 'Name of the Amazon Athena workgroup',
      exportName: `${this.stackName}-AthenaWorkgroupName`,
    });

    new cdk.CfnOutput(this, 'CloudWatchDashboardURL', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for cost monitoring',
    });

    new cdk.CfnOutput(this, 'S3IntelligentTieringConfiguration', {
      value: 'Analytics data automatically transitions: FA->IA (30d) -> Archive (90d) -> Deep Archive (180d)',
      description: 'S3 Intelligent-Tiering transition schedule',
    });

    new cdk.CfnOutput(this, 'AthenaQueryCostLimit', {
      value: '1GB data scan limit per query',
      description: 'Athena workgroup cost control setting',
    });

    // Tags for cost allocation and management
    cdk.Tags.of(this).add('Project', 'CostOptimizedAnalytics');
    cdk.Tags.of(this).add('Environment', 'Demo');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
    cdk.Tags.of(this).add('Owner', 'DataEngineering');
  }
}

// CDK App
const app = new cdk.App();

// Get deployment environment from context or use defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
};

new CostOptimizedAnalyticsStack(app, 'CostOptimizedAnalyticsStack', {
  env,
  description: 'Cost-Optimized Analytics with S3 Tiering, AWS Glue, and Amazon Athena',
  stackName: 'cost-optimized-analytics',
  tags: {
    Project: 'CostOptimizedAnalytics',
    Recipe: 'cost-optimized-analytics-s3-intelligent-tiering',
  },
});

app.synth();