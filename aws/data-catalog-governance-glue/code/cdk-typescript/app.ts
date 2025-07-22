#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lakeformation from 'aws-cdk-lib/aws-lakeformation';
import * as cloudtrail from 'aws-cdk-lib/aws-cloudtrail';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as cr from 'aws-cdk-lib/custom-resources';

/**
 * Properties for the Data Catalog Governance Stack
 */
export interface DataCatalogGovernanceStackProps extends cdk.StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'governance'
   */
  readonly environmentPrefix?: string;
  
  /**
   * Whether to enable PII detection
   * @default true
   */
  readonly enablePiiDetection?: boolean;
  
  /**
   * Whether to enable CloudTrail audit logging
   * @default true
   */
  readonly enableAuditLogging?: boolean;
  
  /**
   * Lake Formation administrators
   * @default Current account root
   */
  readonly dataLakeAdministrators?: string[];
}

/**
 * AWS CDK Stack for Data Catalog Governance with AWS Glue
 * 
 * This stack creates:
 * - S3 buckets for data storage and audit logs
 * - AWS Glue Data Catalog with database and crawler
 * - IAM roles and policies for data governance
 * - Lake Formation configuration for fine-grained access control
 * - CloudTrail for audit logging
 * - CloudWatch dashboard for monitoring
 * - Custom PII classifier for data classification
 */
export class DataCatalogGovernanceStack extends cdk.Stack {
  public readonly dataBucket: s3.Bucket;
  public readonly auditBucket: s3.Bucket;
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly glueCrawler: glue.CfnCrawler;
  public readonly cloudTrail: cloudtrail.Trail;
  public readonly governanceDashboard: cloudwatch.Dashboard;

  constructor(scope: Construct, id: string, props: DataCatalogGovernanceStackProps = {}) {
    super(scope, id, props);

    const environmentPrefix = props.environmentPrefix ?? 'governance';
    const enablePiiDetection = props.enablePiiDetection ?? true;
    const enableAuditLogging = props.enableAuditLogging ?? true;
    const accountId = cdk.Stack.of(this).account;
    const region = cdk.Stack.of(this).region;

    // Generate unique suffix for resources
    const uniqueSuffix = cdk.Names.uniqueId(this).slice(-8).toLowerCase();

    // Create S3 bucket for data storage
    this.dataBucket = new s3.Bucket(this, 'DataBucket', {
      bucketName: `${environmentPrefix}-data-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
    });

    // Create S3 bucket for audit logs
    this.auditBucket = new s3.Bucket(this, 'AuditBucket', {
      bucketName: `${environmentPrefix}-audit-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'ArchiveOldLogs',
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

    // Create IAM role for Glue crawler
    const crawlerRole = new iam.Role(this, 'GlueCrawlerRole', {
      roleName: `${environmentPrefix}-glue-crawler-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for AWS Glue crawler with data governance capabilities',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
    });

    // Add S3 permissions to crawler role
    crawlerRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
        ],
        resources: [
          this.dataBucket.bucketArn,
          `${this.dataBucket.bucketArn}/*`,
        ],
      })
    );

    // Create Glue database
    this.glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: accountId,
      databaseInput: {
        name: `${environmentPrefix}_catalog_${uniqueSuffix}`,
        description: 'Data governance catalog database for PII detection and classification',
        parameters: {
          'classification': 'governance',
          'environment': environmentPrefix,
          'created_by': 'cdk',
        },
      },
    });

    // Create custom PII classifier if enabled
    let piiClassifier: glue.CfnClassifier | undefined;
    if (enablePiiDetection) {
      piiClassifier = new glue.CfnClassifier(this, 'PiiClassifier', {
        csvClassifier: {
          name: `${environmentPrefix}-pii-classifier-${uniqueSuffix}`,
          delimiter: ',',
          quoteSymbol: '"',
          containsHeader: 'PRESENT',
          header: [
            'customer_id',
            'first_name',
            'last_name',
            'email',
            'ssn',
            'phone',
            'address',
            'city',
            'state',
            'zip',
          ],
          disableValueTrimming: false,
          allowSingleColumn: false,
        },
      });
    }

    // Create Glue crawler
    this.glueCrawler = new glue.CfnCrawler(this, 'GlueCrawler', {
      name: `${environmentPrefix}-crawler-${uniqueSuffix}`,
      role: crawlerRole.roleArn,
      databaseName: this.glueDatabase.ref,
      description: 'Governance crawler with PII classification capabilities',
      targets: {
        s3Targets: [
          {
            path: `s3://${this.dataBucket.bucketName}/data/`,
          },
        ],
      },
      classifiers: piiClassifier ? [piiClassifier.ref] : undefined,
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
      configuration: JSON.stringify({
        Version: 1.0,
        CrawlerOutput: {
          Partitions: {
            AddOrUpdateBehavior: 'InheritFromTable',
          },
        },
      }),
    });

    // Create IAM role for data analysts
    const dataAnalystRole = new iam.Role(this, 'DataAnalystRole', {
      roleName: `${environmentPrefix}-data-analyst-role-${uniqueSuffix}`,
      assumedBy: new iam.AccountRootPrincipal(),
      description: 'IAM role for data analysts with governed access to data catalog',
    });

    // Add data analyst permissions
    dataAnalystRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'glue:GetDatabase',
          'glue:GetTable',
          'glue:GetTables',
          'glue:GetPartition',
          'glue:GetPartitions',
          'lakeformation:GetDataAccess',
        ],
        resources: ['*'],
      })
    );

    dataAnalystRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:ListBucket',
        ],
        resources: [
          this.dataBucket.bucketArn,
          `${this.dataBucket.bucketArn}/*`,
        ],
      })
    );

    // Configure Lake Formation
    const lakeFormationSettings = new lakeformation.CfnDataLakeSettings(this, 'LakeFormationSettings', {
      admins: props.dataLakeAdministrators ?? [
        {
          dataLakePrincipalIdentifier: `arn:aws:iam::${accountId}:root`,
        },
      ],
      createDatabaseDefaultPermissions: [],
      createTableDefaultPermissions: [],
      parameters: {
        'CROSS_ACCOUNT_VERSION': '3',
      },
    });

    // Register S3 location with Lake Formation
    const lakeFormationResource = new lakeformation.CfnResource(this, 'LakeFormationResource', {
      resourceArn: `${this.dataBucket.bucketArn}/data/`,
      useServiceLinkedRole: true,
    });

    // Create CloudTrail for audit logging if enabled
    if (enableAuditLogging) {
      this.cloudTrail = new cloudtrail.Trail(this, 'DataCatalogAuditTrail', {
        trailName: `${environmentPrefix}-data-catalog-trail-${uniqueSuffix}`,
        bucket: this.auditBucket,
        includeGlobalServiceEvents: true,
        isMultiRegionTrail: true,
        enableFileValidation: true,
        sendToCloudWatchLogs: true,
        cloudWatchLogGroup: new logs.LogGroup(this, 'CloudTrailLogGroup', {
          logGroupName: `/aws/cloudtrail/${environmentPrefix}-data-catalog-${uniqueSuffix}`,
          retention: logs.RetentionDays.THREE_MONTHS,
          removalPolicy: cdk.RemovalPolicy.DESTROY,
        }),
        cloudWatchLogsRole: new iam.Role(this, 'CloudTrailLogsRole', {
          assumedBy: new iam.ServicePrincipal('cloudtrail.amazonaws.com'),
          managedPolicies: [
            iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchLogsFullAccess'),
          ],
        }),
      });

      // Add data events for Glue tables
      this.cloudTrail.addEventRule('GlueDataEvents', {
        eventPattern: {
          source: ['aws.glue'],
          detailType: ['AWS API Call via CloudTrail'],
          detail: {
            eventSource: ['glue.amazonaws.com'],
            eventName: [
              'GetTable',
              'GetTables',
              'GetPartition',
              'GetPartitions',
              'CreateTable',
              'UpdateTable',
              'DeleteTable',
            ],
          },
        },
      });
    }

    // Create CloudWatch dashboard for governance monitoring
    this.governanceDashboard = new cloudwatch.Dashboard(this, 'GovernanceDashboard', {
      dashboardName: `${environmentPrefix}-data-governance-${uniqueSuffix}`,
      defaultInterval: cdk.Duration.hours(1),
    });

    // Add crawler metrics to dashboard
    this.governanceDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Glue Crawler Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/Glue',
            metricName: 'glue.driver.aggregate.numCompletedTasks',
            dimensionsMap: {
              JobName: this.glueCrawler.name!,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/Glue',
            metricName: 'glue.driver.aggregate.numFailedTasks',
            dimensionsMap: {
              JobName: this.glueCrawler.name!,
            },
            statistic: 'Sum',
            period: cdk.Duration.minutes(5),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Add S3 bucket metrics to dashboard
    this.governanceDashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Data Bucket Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'AWS/S3',
            metricName: 'NumberOfObjects',
            dimensionsMap: {
              BucketName: this.dataBucket.bucketName,
              StorageType: 'AllStorageTypes',
            },
            statistic: 'Average',
            period: cdk.Duration.hours(1),
          }),
        ],
        right: [
          new cloudwatch.Metric({
            namespace: 'AWS/S3',
            metricName: 'BucketSizeBytes',
            dimensionsMap: {
              BucketName: this.dataBucket.bucketName,
              StorageType: 'StandardStorage',
            },
            statistic: 'Average',
            period: cdk.Duration.hours(1),
          }),
        ],
        width: 12,
        height: 6,
      })
    );

    // Create Lambda function for sample data upload
    const sampleDataFunction = new lambda.Function(this, 'SampleDataFunction', {
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
import boto3
import json
import csv
import io

def handler(event, context):
    s3 = boto3.client('s3')
    bucket_name = event['BucketName']
    
    # Sample customer data with PII
    sample_data = [
        ['customer_id', 'first_name', 'last_name', 'email', 'ssn', 'phone', 'address', 'city', 'state', 'zip'],
        ['1', 'John', 'Doe', 'john.doe@email.com', '123-45-6789', '555-123-4567', '123 Main St', 'Anytown', 'NY', '12345'],
        ['2', 'Jane', 'Smith', 'jane.smith@email.com', '987-65-4321', '555-987-6543', '456 Oak Ave', 'Somewhere', 'CA', '67890'],
        ['3', 'Bob', 'Johnson', 'bob.johnson@email.com', '456-78-9012', '555-456-7890', '789 Pine Rd', 'Nowhere', 'TX', '54321']
    ]
    
    # Create CSV content
    csv_buffer = io.StringIO()
    writer = csv.writer(csv_buffer)
    writer.writerows(sample_data)
    csv_content = csv_buffer.getvalue()
    
    # Upload to S3
    try:
        s3.put_object(
            Bucket=bucket_name,
            Key='data/sample_customer_data.csv',
            Body=csv_content,
            ContentType='text/csv'
        )
        return {
            'statusCode': 200,
            'body': json.dumps('Sample data uploaded successfully')
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error uploading sample data: {str(e)}')
        }
      `),
      timeout: cdk.Duration.minutes(5),
      description: 'Function to upload sample customer data for testing',
    });

    // Grant S3 permissions to Lambda function
    this.dataBucket.grantWrite(sampleDataFunction);

    // Create custom resource to upload sample data
    const sampleDataProvider = new cr.Provider(this, 'SampleDataProvider', {
      onEventHandler: sampleDataFunction,
    });

    new cdk.CustomResource(this, 'SampleDataCustomResource', {
      serviceToken: sampleDataProvider.serviceToken,
      properties: {
        BucketName: this.dataBucket.bucketName,
        Timestamp: Date.now(), // Force update on every deployment
      },
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'DataBucketName', {
      value: this.dataBucket.bucketName,
      description: 'Name of the S3 bucket containing data to be governed',
      exportName: `${environmentPrefix}-data-bucket-name`,
    });

    new cdk.CfnOutput(this, 'AuditBucketName', {
      value: this.auditBucket.bucketName,
      description: 'Name of the S3 bucket containing audit logs',
      exportName: `${environmentPrefix}-audit-bucket-name`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'Name of the Glue database for data catalog',
      exportName: `${environmentPrefix}-glue-database-name`,
    });

    new cdk.CfnOutput(this, 'GlueCrawlerName', {
      value: this.glueCrawler.name!,
      description: 'Name of the Glue crawler for data discovery',
      exportName: `${environmentPrefix}-glue-crawler-name`,
    });

    new cdk.CfnOutput(this, 'DataAnalystRoleArn', {
      value: dataAnalystRole.roleArn,
      description: 'ARN of the IAM role for data analysts',
      exportName: `${environmentPrefix}-data-analyst-role-arn`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${region}.console.aws.amazon.com/cloudwatch/home?region=${region}#dashboards:name=${this.governanceDashboard.dashboardName}`,
      description: 'URL to the CloudWatch dashboard for governance monitoring',
    });

    if (enableAuditLogging && this.cloudTrail) {
      new cdk.CfnOutput(this, 'CloudTrailArn', {
        value: this.cloudTrail.trailArn,
        description: 'ARN of the CloudTrail for audit logging',
        exportName: `${environmentPrefix}-cloudtrail-arn`,
      });
    }

    // Add tags to all resources
    cdk.Tags.of(this).add('Environment', environmentPrefix);
    cdk.Tags.of(this).add('Application', 'DataCatalogGovernance');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Purpose', 'DataGovernance');
  }
}

// Create the CDK app
const app = new cdk.App();

// Get environment configuration from context or use defaults
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || 'governance';
const enablePiiDetection = app.node.tryGetContext('enablePiiDetection') !== 'false';
const enableAuditLogging = app.node.tryGetContext('enableAuditLogging') !== 'false';

// Create the stack
new DataCatalogGovernanceStack(app, 'DataCatalogGovernanceStack', {
  environmentPrefix,
  enablePiiDetection,
  enableAuditLogging,
  description: 'CDK Stack for AWS Data Catalog Governance with Glue, Lake Formation, and CloudTrail',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the app
app.synth();