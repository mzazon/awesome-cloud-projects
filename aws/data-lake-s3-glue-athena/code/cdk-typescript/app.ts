#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for building a serverless data lake architecture using S3, Glue, and Athena
 * This stack creates:
 * - S3 buckets for data storage (raw, processed, archive zones) and Athena query results
 * - Glue Data Catalog database for metadata management
 * - Glue crawlers for automated schema discovery
 * - Glue ETL job for data transformation
 * - Athena workgroup for query execution
 * - IAM roles and policies for secure access
 */
class DataLakeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ======================
    // S3 Buckets
    // ======================

    // Main data lake bucket with zone-based folder structure
    const dataLakeBucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `data-lake-${uniqueSuffix}`,
      versioned: true, // Enable versioning for data protection
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          // Raw zone lifecycle - transition to cheaper storage classes over time
          id: 'RawZoneLifecycle',
          prefix: 'raw-zone/',
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
        {
          // Processed zone lifecycle - keep in Standard longer for analytics
          id: 'ProcessedZoneLifecycle',
          prefix: 'processed-zone/',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(90),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(180),
            },
          ],
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes - use RETAIN in production
      autoDeleteObjects: true, // For demo purposes - remove in production
    });

    // Athena query results bucket
    const athenaResultsBucket = new s3.Bucket(this, 'AthenaResultsBucket', {
      bucketName: `athena-results-${uniqueSuffix}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'QueryResultsCleanup',
          enabled: true,
          expiration: cdk.Duration.days(30), // Clean up old query results
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ======================
    // IAM Roles and Policies
    // ======================

    // IAM role for AWS Glue with necessary permissions
    const glueRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `GlueServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for AWS Glue to access S3 and manage data catalog',
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
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
              ],
              resources: [
                dataLakeBucket.bucketArn,
                `${dataLakeBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        // CloudWatch Logs permissions for Glue job logging
        CloudWatchLogs: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });

    // ======================
    // Glue Data Catalog
    // ======================

    // Glue database for organizing tables and metadata
    const glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `datalake_db_${uniqueSuffix}`,
        description: 'Data lake database for analytics and ETL operations',
      },
    });

    // ======================
    // Glue Crawlers
    // ======================

    // Crawler for sales data (CSV format)
    const salesDataCrawler = new glue.CfnCrawler(this, 'SalesDataCrawler', {
      name: `sales-data-crawler-${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      description: 'Crawler for sales data in CSV format',
      targets: {
        s3Targets: [
          {
            path: `s3://${dataLakeBucket.bucketName}/raw-zone/sales-data/`,
          },
        ],
      },
      // Run crawler weekly to detect schema changes
      schedule: {
        scheduleExpression: 'cron(0 12 ? * SUN *)',
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'DEPRECATE_IN_DATABASE',
      },
    });

    // Crawler for web logs (JSON format)
    const webLogsCrawler = new glue.CfnCrawler(this, 'WebLogsCrawler', {
      name: `web-logs-crawler-${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      description: 'Crawler for web logs in JSON format',
      targets: {
        s3Targets: [
          {
            path: `s3://${dataLakeBucket.bucketName}/raw-zone/web-logs/`,
          },
        ],
      },
      schedule: {
        scheduleExpression: 'cron(0 12 ? * SUN *)',
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'DEPRECATE_IN_DATABASE',
      },
    });

    // ======================
    // Glue ETL Job
    // ======================

    // CloudWatch Log Group for Glue ETL job
    const glueEtlLogGroup = new logs.LogGroup(this, 'GlueEtlLogGroup', {
      logGroupName: `/aws-glue/jobs/sales-data-etl-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ETL job for transforming raw data to optimized Parquet format
    const etlJob = new glue.CfnJob(this, 'SalesDataETLJob', {
      name: `sales-data-etl-${uniqueSuffix}`,
      role: glueRole.roleArn,
      description: 'ETL job to transform raw sales data to optimized Parquet format',
      command: {
        name: 'glueetl',
        scriptLocation: `s3://${dataLakeBucket.bucketName}/scripts/glue-etl-script.py`,
        pythonVersion: '3',
      },
      defaultArguments: {
        '--job-language': 'python',
        '--DATABASE_NAME': glueDatabase.ref,
        '--TABLE_NAME': 'sales_data',
        '--OUTPUT_PATH': `s3://${dataLakeBucket.bucketName}/processed-zone/sales-data-processed/`,
        '--enable-metrics': '',
        '--enable-continuous-cloudwatch-log': 'true',
        '--enable-spark-ui': 'true',
        '--spark-event-logs-path': `s3://${dataLakeBucket.bucketName}/spark-logs/`,
        '--job-bookmark-option': 'job-bookmark-enable',
        '--TempDir': `s3://${dataLakeBucket.bucketName}/temp/`,
      },
      maxCapacity: 2, // Use 2 DPUs for small to medium workloads
      timeout: 60, // 60 minutes timeout
      maxRetries: 1,
      glueVersion: '4.0', // Latest Glue version for better performance
    });

    // ======================
    // Athena Configuration
    // ======================

    // Athena workgroup for query execution and cost control
    const athenaWorkgroup = new athena.CfnWorkGroup(this, 'AthenaWorkgroup', {
      name: `DataLakeWorkgroup-${uniqueSuffix}`,
      description: 'Workgroup for data lake analytics queries',
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${athenaResultsBucket.bucketName}/query-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetricsEnabled: true,
        bytesScannedCutoffPerQuery: 1000000000, // 1GB query limit for cost control
        requesterPaysEnabled: false,
      },
    });

    // ======================
    // Sample Data Deployment
    // ======================

    // Custom resource to deploy sample data (using AWS CLI commands)
    const sampleDataDeployment = new cdk.CustomResource(this, 'SampleDataDeployment', {
      serviceToken: this.node.tryGetContext('sampleDataServiceToken') || 'arn:aws:lambda:' + this.region + ':' + this.account + ':function:sample-data-deployer',
      properties: {
        BucketName: dataLakeBucket.bucketName,
        SampleFiles: [
          {
            key: 'raw-zone/sales-data/year=2024/month=01/sample-sales-data.csv',
            content: 'order_id,customer_id,product_name,category,quantity,price,order_date,region\\n1001,C001,Laptop,Electronics,1,999.99,2024-01-15,North\\n1002,C002,Coffee Maker,Appliances,2,79.99,2024-01-15,South\\n1003,C003,Book Set,Books,3,45.50,2024-01-16,East'
          },
          {
            key: 'raw-zone/web-logs/year=2024/month=01/sample-web-logs.json',
            content: '{"timestamp":"2024-01-15T10:30:00Z","user_id":"U001","page":"/home","action":"view","duration":45,"ip":"192.168.1.100"}\\n{"timestamp":"2024-01-15T10:31:00Z","user_id":"U002","page":"/products","action":"view","duration":120,"ip":"192.168.1.101"}'
          },
          {
            key: 'scripts/glue-etl-script.py',
            content: this.getGlueETLScript()
          }
        ]
      }
    });

    // ======================
    // CloudFormation Outputs
    // ======================

    // Output important resource information for reference
    new cdk.CfnOutput(this, 'DataLakeBucketName', {
      value: dataLakeBucket.bucketName,
      description: 'Name of the main data lake S3 bucket',
      exportName: `DataLakeBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'AthenaResultsBucketName', {
      value: athenaResultsBucket.bucketName,
      description: 'Name of the Athena query results S3 bucket',
      exportName: `AthenaResultsBucket-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Name of the Glue database',
      exportName: `GlueDatabase-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkgroupName', {
      value: athenaWorkgroup.ref,
      description: 'Name of the Athena workgroup',
      exportName: `AthenaWorkgroup-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'GlueRoleArn', {
      value: glueRole.roleArn,
      description: 'ARN of the Glue service role',
      exportName: `GlueRole-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'SalesDataCrawlerName', {
      value: salesDataCrawler.ref,
      description: 'Name of the sales data crawler',
      exportName: `SalesDataCrawler-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'WebLogsCrawlerName', {
      value: webLogsCrawler.ref,
      description: 'Name of the web logs crawler',
      exportName: `WebLogsCrawler-${uniqueSuffix}`,
    });

    new cdk.CfnOutput(this, 'ETLJobName', {
      value: etlJob.ref,
      description: 'Name of the Glue ETL job',
      exportName: `ETLJob-${uniqueSuffix}`,
    });

    // Sample Athena queries for testing
    new cdk.CfnOutput(this, 'SampleAthenaQueries', {
      value: [
        `SELECT region, COUNT(*) as total_orders, SUM(quantity * price) as total_revenue FROM ${glueDatabase.ref}.sales_data GROUP BY region ORDER BY total_revenue DESC;`,
        `SELECT product_name, category, SUM(quantity * price) as revenue FROM ${glueDatabase.ref}.sales_data GROUP BY product_name, category ORDER BY revenue DESC LIMIT 10;`,
        `SELECT order_date, COUNT(*) as orders, SUM(quantity * price) as daily_revenue FROM ${glueDatabase.ref}.sales_data GROUP BY order_date ORDER BY order_date;`
      ].join(' | '),
      description: 'Sample Athena queries for testing the data lake',
    });
  }

  /**
   * Returns the Glue ETL script content for transforming raw data to Parquet format
   */
  private getGlueETLScript(): string {
    return `
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'TABLE_NAME', 'OUTPUT_PATH'])

# Initialize Spark and Glue contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read data from Glue catalog
    datasource = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name=args['TABLE_NAME'],
        transformation_ctx="datasource"
    )
    
    # Convert to Spark DataFrame for transformations
    df = datasource.toDF()
    
    # Add processing metadata
    df_processed = df.withColumn("processed_timestamp", F.current_timestamp()) \\
                    .withColumn("processing_date", F.current_date())
    
    # Data quality checks and transformations
    df_cleaned = df_processed.filter(F.col("price") > 0) \\
                           .filter(F.col("quantity") > 0) \\
                           .withColumn("total_amount", F.col("quantity") * F.col("price"))
    
    # Convert back to DynamicFrame
    processed_dynamic_frame = DynamicFrame.fromDF(df_cleaned, glueContext, "processed_data")
    
    # Write to S3 in Parquet format with partitioning
    glueContext.write_dynamic_frame.from_options(
        frame=processed_dynamic_frame,
        connection_type="s3",
        connection_options={
            "path": args['OUTPUT_PATH'],
            "partitionKeys": ["year", "month"]
        },
        format="parquet",
        transformation_ctx="write_parquet"
    )
    
    print("ETL job completed successfully")
    
except Exception as e:
    print(f"ETL job failed with error: {str(e)}")
    raise e
    
finally:
    job.commit()
`.trim();
  }
}

// CDK App
const app = new cdk.App();

// Create the data lake stack
new DataLakeStack(app, 'DataLakeStack', {
  description: 'AWS CDK stack for building serverless data lake architectures with S3, Glue, and Athena',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'DataLake',
    Environment: 'Demo',
    Owner: 'CDK',
    CostCenter: 'Analytics',
  },
});

// Synthesize the CloudFormation template
app.synth();