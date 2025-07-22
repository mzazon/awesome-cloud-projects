#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as cloudwatchActions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as athena from 'aws-cdk-lib/aws-athena';
import { Construct } from 'constructs';

/**
 * Stack for Data Lake Ingestion Pipelines with Glue
 * Implements medallion architecture (Bronze, Silver, Gold) for data processing
 */
export class DataLakeIngestionStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // S3 Bucket for Data Lake with medallion architecture
    const dataLakeBucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `datalake-pipeline-${uniqueSuffix}`,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DataLakeLifecycle',
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
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create folder structure for medallion architecture
    const folderStructure = [
      'raw-data/',
      'processed-data/bronze/',
      'processed-data/silver/',
      'processed-data/gold/',
      'scripts/',
      'temp/',
      'athena-results/',
      'queries/',
    ];

    folderStructure.forEach(folder => {
      new s3deploy.BucketDeployment(this, `Deploy${folder.replace(/[\/\-]/g, '')}`, {
        sources: [s3deploy.Source.data(folder, '')],
        destinationBucket: dataLakeBucket,
        destinationKeyPrefix: folder,
      });
    });

    // IAM Role for AWS Glue Service
    const glueServiceRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `GlueDataLakeRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for AWS Glue data lake operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        GlueS3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetBucketLocation',
                's3:ListBucket',
                's3:GetBucketAcl',
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                dataLakeBucket.bucketArn,
                `${dataLakeBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: ['arn:aws:logs:*:*:*'],
            }),
          ],
        }),
      },
    });

    // Glue Database for Data Catalog
    const glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `datalake-catalog-${uniqueSuffix}`,
        description: 'Data lake catalog for analytics pipeline',
      },
    });

    // Glue Crawler for automated schema discovery
    const glueCrawler = new glue.CfnCrawler(this, 'DataLakeCrawler', {
      name: `data-lake-crawler-${uniqueSuffix}`,
      role: glueServiceRole.roleArn,
      databaseName: glueDatabase.ref,
      description: 'Crawler for data lake raw data sources',
      targets: {
        s3Targets: [
          {
            path: `s3://${dataLakeBucket.bucketName}/raw-data/`,
          },
        ],
      },
      tablePrefix: 'raw_',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG',
      },
      recrawlPolicy: {
        recrawlBehavior: 'CRAWL_EVERYTHING',
      },
      lineageConfiguration: {
        crawlerLineageSettings: 'ENABLE',
      },
      configuration: JSON.stringify({
        Version: 1.0,
        CrawlerOutput: {
          Partitions: { AddOrUpdateBehavior: 'InheritFromTable' },
          Tables: { AddOrUpdateBehavior: 'MergeNewColumns' },
        },
      }),
    });

    // ETL Script content for medallion architecture processing
    const etlScriptContent = `
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *
import boto3

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Get job parameters
args = getResolvedOptions(sys.argv, [
    'JOB_NAME', 
    'DATABASE_NAME', 
    'S3_BUCKET_NAME',
    'SOURCE_TABLE_EVENTS',
    'SOURCE_TABLE_CUSTOMERS'
])

job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read data from Data Catalog
    events_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name=args['SOURCE_TABLE_EVENTS']
    ).toDF()
    
    customers_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name=args['SOURCE_TABLE_CUSTOMERS']
    ).toDF()
    
    # Bronze layer: Raw data with basic cleansing
    print("Processing Bronze Layer...")
    
    # Clean and standardize events data
    events_bronze = events_df.withColumn(
        "timestamp", 
        to_timestamp(col("timestamp"))
    ).withColumn(
        "amount", 
        col("amount").cast("double")
    ).filter(
        col("event_id").isNotNull() & 
        col("user_id").isNotNull()
    )
    
    # Add processing metadata
    events_bronze = events_bronze.withColumn(
        "processing_date", 
        current_date()
    ).withColumn(
        "processing_timestamp", 
        current_timestamp()
    )
    
    # Write to Bronze layer
    events_bronze.write.mode("overwrite").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/bronze/events/"
    )
    
    # Silver layer: Business logic and data quality
    print("Processing Silver Layer...")
    
    # Enrich events with customer data
    events_silver = events_bronze.join(
        customers_df,
        events_bronze.user_id == customers_df.customer_id,
        "left"
    ).select(
        events_bronze["*"],
        customers_df["name"].alias("customer_name"),
        customers_df["email"].alias("customer_email"),
        customers_df["country"],
        customers_df["age_group"]
    )
    
    # Add business metrics
    events_silver = events_silver.withColumn(
        "is_purchase", 
        when(col("event_type") == "purchase", 1).otherwise(0)
    ).withColumn(
        "is_high_value", 
        when(col("amount") > 100, 1).otherwise(0)
    ).withColumn(
        "event_date", 
        to_date(col("timestamp"))
    ).withColumn(
        "event_hour", 
        hour(col("timestamp"))
    )
    
    # Write to Silver layer partitioned by date
    events_silver.write.mode("overwrite").partitionBy("event_date").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/silver/events/"
    )
    
    # Gold layer: Analytics-ready aggregated data
    print("Processing Gold Layer...")
    
    # Daily sales summary
    daily_sales = events_silver.filter(
        col("event_type") == "purchase"
    ).groupBy(
        "event_date", "category", "country"
    ).agg(
        count("*").alias("total_purchases"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_order_value"),
        countDistinct("user_id").alias("unique_customers")
    )
    
    # Customer behavior summary
    customer_behavior = events_silver.groupBy(
        "user_id", "customer_name", "country", "age_group"
    ).agg(
        count("*").alias("total_events"),
        sum("is_purchase").alias("total_purchases"),
        sum("amount").alias("total_spent"),
        countDistinct("category").alias("categories_engaged")
    ).withColumn(
        "avg_order_value",
        when(col("total_purchases") > 0, col("total_spent") / col("total_purchases")).otherwise(0)
    )
    
    # Write Gold layer data
    daily_sales.write.mode("overwrite").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/gold/daily_sales/"
    )
    
    customer_behavior.write.mode("overwrite").parquet(
        f"s3://{args['S3_BUCKET_NAME']}/processed-data/gold/customer_behavior/"
    )
    
    print("ETL job completed successfully!")

except Exception as e:
    print(f"Error in ETL job: {str(e)}")
    raise e

finally:
    job.commit()
`;

    // Deploy ETL script to S3
    new s3deploy.BucketDeployment(this, 'DeployETLScript', {
      sources: [s3deploy.Source.data('etl-script.py', etlScriptContent)],
      destinationBucket: dataLakeBucket,
      destinationKeyPrefix: 'scripts/',
    });

    // Glue ETL Job for data processing
    const glueETLJob = new glue.CfnJob(this, 'DataLakeETLJob', {
      name: `data-lake-etl-job-${uniqueSuffix}`,
      description: 'Data lake ETL pipeline for multi-layer architecture',
      role: glueServiceRole.roleArn,
      command: {
        name: 'glueetl',
        scriptLocation: `s3://${dataLakeBucket.bucketName}/scripts/etl-script.py`,
        pythonVersion: '3',
      },
      defaultArguments: {
        '--job-bookmark-option': 'job-bookmark-enable',
        '--enable-metrics': '',
        '--enable-continuous-cloudwatch-log': 'true',
        '--DATABASE_NAME': glueDatabase.ref,
        '--S3_BUCKET_NAME': dataLakeBucket.bucketName,
        '--SOURCE_TABLE_EVENTS': 'raw_events',
        '--SOURCE_TABLE_CUSTOMERS': 'raw_customers',
      },
      maxRetries: 1,
      timeout: 60,
      glueVersion: '3.0',
      maxCapacity: 5,
      workerType: 'G.1X',
      numberOfWorkers: 5,
    });

    // Glue Workflow for pipeline orchestration
    const glueWorkflow = new glue.CfnWorkflow(this, 'DataLakeWorkflow', {
      name: `data-lake-workflow-${uniqueSuffix}`,
      description: 'Data lake ingestion workflow with crawler and ETL',
    });

    // Scheduled trigger for crawler
    const crawlerTrigger = new glue.CfnTrigger(this, 'CrawlerTrigger', {
      name: `${glueWorkflow.name}-crawler-trigger`,
      type: 'SCHEDULED',
      schedule: 'cron(0 6 * * ? *)', // Daily at 6 AM UTC
      workflowName: glueWorkflow.name,
      actions: [
        {
          crawlerName: glueCrawler.name,
        },
      ],
      startOnCreation: true,
    });

    // Conditional trigger for ETL job (depends on crawler completion)
    const etlTrigger = new glue.CfnTrigger(this, 'ETLTrigger', {
      name: `${glueWorkflow.name}-etl-trigger`,
      type: 'CONDITIONAL',
      predicate: {
        conditions: [
          {
            logicalOperator: 'EQUALS',
            crawlerName: glueCrawler.name,
            crawlState: 'SUCCEEDED',
          },
        ],
      },
      workflowName: glueWorkflow.name,
      actions: [
        {
          jobName: glueETLJob.name,
        },
      ],
    });

    // Data Quality Ruleset
    const dataQualityRuleset = new glue.CfnDataQualityRuleset(this, 'DataQualityRuleset', {
      name: 'DataLakeQualityRules',
      description: 'Data quality rules for data lake pipeline',
      ruleset: 'Rules = [ColumnCount > 5, IsComplete "user_id", IsComplete "event_type", IsComplete "timestamp", ColumnValues "amount" >= 0]',
      targetTable: {
        tableName: 'silver_events',
        databaseName: glueDatabase.ref,
      },
    });

    // SNS Topic for alerts
    const alertTopic = new sns.Topic(this, 'DataLakeAlerts', {
      topicName: `DataLakeAlerts-${uniqueSuffix}`,
      displayName: 'Data Lake Pipeline Alerts',
    });

    // CloudWatch Alarms for monitoring
    const jobFailureAlarm = new cloudwatch.Alarm(this, 'GlueJobFailureAlarm', {
      alarmName: `GlueJobFailure-${glueETLJob.name}`,
      alarmDescription: 'Alert when Glue ETL job fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Glue',
        metricName: 'glue.driver.aggregate.numFailedTasks',
        dimensionsMap: {
          JobName: glueETLJob.name!,
          JobRunId: 'ALL',
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
    });

    const crawlerFailureAlarm = new cloudwatch.Alarm(this, 'GlueCrawlerFailureAlarm', {
      alarmName: `GlueCrawlerFailure-${glueCrawler.name}`,
      alarmDescription: 'Alert when Glue crawler fails',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Glue',
        metricName: 'glue.driver.aggregate.numFailedTasks',
        dimensionsMap: {
          CrawlerName: glueCrawler.name!,
        },
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
    });

    // Add SNS actions to alarms
    jobFailureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));
    crawlerFailureAlarm.addAlarmAction(new cloudwatchActions.SnsAction(alertTopic));

    // Athena Workgroup for analytics
    const athenaWorkgroup = new athena.CfnWorkGroup(this, 'DataLakeWorkgroup', {
      name: 'DataLakeWorkgroup',
      description: 'Workgroup for data lake analytics',
      state: 'ENABLED',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${dataLakeBucket.bucketName}/athena-results/`,
          encryptionConfiguration: {
            encryptionOption: 'SSE_S3',
          },
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true,
      },
    });

    // Sample data deployment
    const sampleEventsData = `{"event_id": "evt001", "user_id": "user123", "event_type": "purchase", "product_id": "prod456", "amount": 89.99, "timestamp": "2024-01-15T10:30:00Z", "category": "electronics"}
{"event_id": "evt002", "user_id": "user456", "event_type": "view", "product_id": "prod789", "amount": 0.0, "timestamp": "2024-01-15T10:31:00Z", "category": "books"}
{"event_id": "evt003", "user_id": "user789", "event_type": "cart_add", "product_id": "prod123", "amount": 45.50, "timestamp": "2024-01-15T10:32:00Z", "category": "clothing"}
{"event_id": "evt004", "user_id": "user123", "event_type": "purchase", "product_id": "prod321", "amount": 129.00, "timestamp": "2024-01-15T10:33:00Z", "category": "home"}
{"event_id": "evt005", "user_id": "user654", "event_type": "view", "product_id": "prod555", "amount": 0.0, "timestamp": "2024-01-15T10:34:00Z", "category": "electronics"}`;

    const sampleCustomersData = `customer_id,name,email,registration_date,country,age_group
user123,John Doe,john.doe@example.com,2023-05-15,US,25-34
user456,Jane Smith,jane.smith@example.com,2023-06-20,CA,35-44
user789,Bob Johnson,bob.johnson@example.com,2023-07-10,UK,45-54
user654,Alice Brown,alice.brown@example.com,2023-08-05,US,18-24
user321,Charlie Wilson,charlie.wilson@example.com,2023-09-12,AU,25-34`;

    const sampleQueries = `-- Query 1: Daily sales by category
SELECT 
    event_date,
    category,
    total_purchases,
    total_revenue,
    avg_order_value
FROM "${glueDatabase.ref}"."gold_daily_sales"
WHERE event_date >= date('2024-01-01')
ORDER BY event_date DESC, total_revenue DESC;

-- Query 2: Customer behavior analysis
SELECT 
    age_group,
    country,
    AVG(total_spent) as avg_customer_lifetime_value,
    AVG(total_purchases) as avg_purchases_per_customer,
    COUNT(*) as customer_count
FROM "${glueDatabase.ref}"."gold_customer_behavior"
GROUP BY age_group, country
ORDER BY avg_customer_lifetime_value DESC;

-- Query 3: Real-time event analysis
SELECT 
    event_type,
    category,
    COUNT(*) as event_count,
    SUM(amount) as total_amount
FROM "${glueDatabase.ref}"."silver_events"
WHERE event_date = CURRENT_DATE
GROUP BY event_type, category
ORDER BY event_count DESC;`;

    // Deploy sample data
    new s3deploy.BucketDeployment(this, 'DeploySampleEvents', {
      sources: [s3deploy.Source.data('sample-events.json', sampleEventsData)],
      destinationBucket: dataLakeBucket,
      destinationKeyPrefix: 'raw-data/events/',
    });

    new s3deploy.BucketDeployment(this, 'DeploySampleCustomers', {
      sources: [s3deploy.Source.data('sample-customers.csv', sampleCustomersData)],
      destinationBucket: dataLakeBucket,
      destinationKeyPrefix: 'raw-data/customers/',
    });

    new s3deploy.BucketDeployment(this, 'DeploySampleQueries', {
      sources: [s3deploy.Source.data('sample-queries.sql', sampleQueries)],
      destinationBucket: dataLakeBucket,
      destinationKeyPrefix: 'queries/',
    });

    // Stack Outputs
    new cdk.CfnOutput(this, 'DataLakeBucketName', {
      value: dataLakeBucket.bucketName,
      description: 'Name of the S3 bucket for data lake storage',
      exportName: `${this.stackName}-DataLakeBucketName`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Name of the Glue database for Data Catalog',
      exportName: `${this.stackName}-GlueDatabaseName`,
    });

    new cdk.CfnOutput(this, 'GlueCrawlerName', {
      value: glueCrawler.name!,
      description: 'Name of the Glue crawler for schema discovery',
      exportName: `${this.stackName}-GlueCrawlerName`,
    });

    new cdk.CfnOutput(this, 'GlueETLJobName', {
      value: glueETLJob.name!,
      description: 'Name of the Glue ETL job for data processing',
      exportName: `${this.stackName}-GlueETLJobName`,
    });

    new cdk.CfnOutput(this, 'GlueWorkflowName', {
      value: glueWorkflow.name!,
      description: 'Name of the Glue workflow for pipeline orchestration',
      exportName: `${this.stackName}-GlueWorkflowName`,
    });

    new cdk.CfnOutput(this, 'AthenaWorkgroupName', {
      value: athenaWorkgroup.name!,
      description: 'Name of the Athena workgroup for analytics',
      exportName: `${this.stackName}-AthenaWorkgroupName`,
    });

    new cdk.CfnOutput(this, 'SNSTopicArn', {
      value: alertTopic.topicArn,
      description: 'ARN of the SNS topic for pipeline alerts',
      exportName: `${this.stackName}-SNSTopicArn`,
    });

    new cdk.CfnOutput(this, 'GlueServiceRoleArn', {
      value: glueServiceRole.roleArn,
      description: 'ARN of the IAM role for Glue service operations',
      exportName: `${this.stackName}-GlueServiceRoleArn`,
    });

    // Tags for all resources
    cdk.Tags.of(this).add('Project', 'DataLakeIngestionPipeline');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
  }
}

// CDK App
const app = new cdk.App();

// Get context values with defaults
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
  region: process.env.CDK_DEFAULT_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1',
};

// Create the stack
new DataLakeIngestionStack(app, 'DataLakeIngestionStack', {
  env,
  description: 'Data Lake Ingestion Pipelines with Glue - CDK TypeScript implementation',
  tags: {
    Project: 'DataLakeIngestionPipeline',
    Repository: 'recipes',
    Recipe: 'data-lake-ingestion-pipelines-aws-glue-data-catalog',
  },
});

// Synthesize the app
app.synth();