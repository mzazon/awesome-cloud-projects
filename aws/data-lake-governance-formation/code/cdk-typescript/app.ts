#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as lakeformation from 'aws-cdk-lib/aws-lakeformation';
import * as datazone from 'aws-cdk-lib/aws-datazone';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';

/**
 * Properties for the Advanced Data Lake Governance Stack
 */
interface DataLakeGovernanceStackProps extends cdk.StackProps {
  /**
   * The name for the DataZone domain
   * @default 'enterprise-data-governance'
   */
  readonly domainName?: string;
  
  /**
   * The name for the Glue database
   * @default 'enterprise_data_catalog'
   */
  readonly glueDatabaseName?: string;
  
  /**
   * Environment for tagging and naming
   * @default 'production'
   */
  readonly environment?: string;
  
  /**
   * Email address for alert notifications
   */
  readonly alertEmail?: string;
}

/**
 * Advanced Data Lake Governance Stack with Lake Formation and DataZone
 * 
 * This stack implements a comprehensive data lake governance platform using:
 * - AWS Lake Formation for fine-grained access control
 * - Amazon DataZone for data discovery and cataloging
 * - AWS Glue for ETL operations and data catalog
 * - S3 for tiered data lake storage (raw, curated, analytics)
 * - CloudWatch for monitoring and alerting
 */
export class DataLakeGovernanceStack extends cdk.Stack {
  public readonly dataLakeBucket: s3.Bucket;
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly dataZoneDomain: datazone.CfnDomain;
  public readonly lakeFormationServiceRole: iam.Role;
  public readonly dataAnalystRole: iam.Role;

  constructor(scope: Construct, id: string, props: DataLakeGovernanceStackProps = {}) {
    super(scope, id, props);

    const domainName = props.domainName ?? 'enterprise-data-governance';
    const glueDatabaseName = props.glueDatabaseName ?? 'enterprise_data_catalog';
    const environment = props.environment ?? 'production';

    // Generate a unique suffix for global resources
    const randomSuffix = new secretsmanager.Secret(this, 'RandomSuffix', {
      generateSecretString: {
        excludePunctuation: true,
        excludeUppercase: true,
        passwordLength: 6,
        requireEachIncludedType: true,
      },
    });

    // Create S3 bucket for data lake with proper governance configuration
    this.dataLakeBucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `enterprise-datalake-${cdk.Aws.ACCOUNT_ID}-${cdk.Aws.REGION}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'raw-data-lifecycle',
          prefix: 'raw-data/',
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
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
    });

    // Add bucket notification configuration for governance events
    this.dataLakeBucket.addToResourcePolicy(
      new iam.PolicyStatement({
        sid: 'DenyInsecureConnections',
        effect: iam.Effect.DENY,
        principals: [new iam.AnyPrincipal()],
        actions: ['s3:*'],
        resources: [
          this.dataLakeBucket.bucketArn,
          this.dataLakeBucket.arnForObjects('*'),
        ],
        conditions: {
          Bool: {
            'aws:SecureTransport': 'false',
          },
        },
      })
    );

    // Create IAM role for Lake Formation service
    this.lakeFormationServiceRole = new iam.Role(this, 'LakeFormationServiceRole', {
      roleName: 'LakeFormationServiceRole',
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lakeformation.amazonaws.com'),
        new iam.ServicePrincipal('glue.amazonaws.com')
      ),
      description: 'Service role for AWS Lake Formation and Glue integration',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/LakeFormationDataAccessServiceRolePolicy'),
      ],
    });

    // Add comprehensive policies for Lake Formation service role
    this.lakeFormationServiceRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:GetObjectVersion',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
          's3:ListBucketMultipartUploads',
          's3:ListMultipartUploadParts',
          's3:AbortMultipartUpload',
        ],
        resources: [
          this.dataLakeBucket.bucketArn,
          this.dataLakeBucket.arnForObjects('*'),
        ],
      })
    );

    this.lakeFormationServiceRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'glue:GetDatabase',
          'glue:GetDatabases',
          'glue:CreateDatabase',
          'glue:GetTable',
          'glue:GetTables',
          'glue:CreateTable',
          'glue:UpdateTable',
          'glue:DeleteTable',
          'glue:GetPartition',
          'glue:GetPartitions',
          'glue:CreatePartition',
          'glue:UpdatePartition',
          'glue:DeletePartition',
          'glue:BatchCreatePartition',
          'glue:BatchDeletePartition',
          'glue:BatchUpdatePartition',
        ],
        resources: ['*'],
      })
    );

    this.lakeFormationServiceRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'lakeformation:GetDataAccess',
          'lakeformation:GrantPermissions',
          'lakeformation:RevokePermissions',
          'lakeformation:BatchGrantPermissions',
          'lakeformation:BatchRevokePermissions',
          'lakeformation:ListPermissions',
        ],
        resources: ['*'],
      })
    );

    // Create data analyst role
    this.dataAnalystRole = new iam.Role(this, 'DataAnalystRole', {
      roleName: 'DataAnalystRole',
      assumedBy: new iam.AccountRootPrincipal(),
      description: 'Role for data analysts with restricted data access through Lake Formation',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonAthenaFullAccess'),
      ],
    });

    // Create AWS Glue database for enterprise data catalog
    this.glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseInput: {
        name: glueDatabaseName,
        description: 'Enterprise data catalog for governed data lake',
        locationUri: `s3://${this.dataLakeBucket.bucketName}/curated-data/`,
        parameters: {
          classification: 'curated',
          environment: environment,
        },
      },
    });

    // Create customer data table with PII classification
    const customerDataTable = new glue.CfnTable(this, 'CustomerDataTable', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseName: this.glueDatabase.ref,
      tableInput: {
        name: 'customer_data',
        description: 'Customer information with PII protection',
        storageDescriptor: {
          columns: [
            { name: 'customer_id', type: 'bigint', comment: 'Unique customer identifier' },
            { name: 'first_name', type: 'string', comment: 'Customer first name - PII' },
            { name: 'last_name', type: 'string', comment: 'Customer last name - PII' },
            { name: 'email', type: 'string', comment: 'Customer email - PII' },
            { name: 'phone', type: 'string', comment: 'Customer phone - PII' },
            { name: 'registration_date', type: 'date', comment: 'Account registration date' },
            { name: 'customer_segment', type: 'string', comment: 'Business customer segment' },
            { name: 'lifetime_value', type: 'double', comment: 'Customer lifetime value' },
            { name: 'region', type: 'string', comment: 'Customer geographic region' },
          ],
          location: `s3://${this.dataLakeBucket.bucketName}/curated-data/customer_data/`,
          inputFormat: 'org.apache.hadoop.mapred.TextInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.apache.hadoop.hive.serde2.lazy.LazySimpleSerDe',
            parameters: {
              'field.delim': ',',
              'skip.header.line.count': '1',
            },
          },
        },
        partitionKeys: [
          { name: 'year', type: 'string' },
          { name: 'month', type: 'string' },
        ],
        parameters: {
          classification: 'csv',
          delimiter: ',',
          has_encrypted_data: 'false',
          data_classification: 'confidential',
        },
      },
    });

    // Create transaction data table
    const transactionDataTable = new glue.CfnTable(this, 'TransactionDataTable', {
      catalogId: cdk.Aws.ACCOUNT_ID,
      databaseName: this.glueDatabase.ref,
      tableInput: {
        name: 'transaction_data',
        description: 'Customer transaction records',
        storageDescriptor: {
          columns: [
            { name: 'transaction_id', type: 'string', comment: 'Unique transaction identifier' },
            { name: 'customer_id', type: 'bigint', comment: 'Associated customer ID' },
            { name: 'transaction_date', type: 'timestamp', comment: 'Transaction timestamp' },
            { name: 'amount', type: 'double', comment: 'Transaction amount' },
            { name: 'currency', type: 'string', comment: 'Transaction currency' },
            { name: 'merchant_category', type: 'string', comment: 'Merchant category code' },
            { name: 'payment_method', type: 'string', comment: 'Payment method used' },
            { name: 'status', type: 'string', comment: 'Transaction status' },
          ],
          location: `s3://${this.dataLakeBucket.bucketName}/curated-data/transaction_data/`,
          inputFormat: 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe',
          },
        },
        partitionKeys: [
          { name: 'year', type: 'string' },
          { name: 'month', type: 'string' },
          { name: 'day', type: 'string' },
        ],
        parameters: {
          classification: 'parquet',
          data_classification: 'internal',
        },
      },
    });

    // Register S3 location with Lake Formation
    const lakeFormationResource = new lakeformation.CfnResource(this, 'LakeFormationResource', {
      resourceArn: this.dataLakeBucket.bucketArn,
      useServiceLinkedRole: true,
    });

    // Create Lake Formation data lake settings
    const dataLakeSettings = new lakeformation.CfnDataLakeSettings(this, 'DataLakeSettings', {
      admins: [
        {
          dataLakePrincipalIdentifier: cdk.Stack.of(this).formatArn({
            service: 'iam',
            resource: 'root',
            region: '',
          }),
        },
      ],
      createDatabaseDefaultPermissions: [],
      createTableDefaultPermissions: [],
      parameters: {
        CROSS_ACCOUNT_VERSION: '3',
      },
      trustedResourceOwners: [cdk.Aws.ACCOUNT_ID],
      allowExternalDataFiltering: true,
      externalDataFilteringAllowList: [cdk.Aws.ACCOUNT_ID],
    });

    // Create DataZone domain for data governance
    this.dataZoneDomain = new datazone.CfnDomain(this, 'DataZoneDomain', {
      name: domainName,
      description: 'Enterprise data governance domain with Lake Formation integration',
      domainExecutionRole: this.lakeFormationServiceRole.roleArn,
      kmsKeyIdentifier: 'alias/aws/datazone',
    });

    // Create business glossary for DataZone
    const businessGlossary = new datazone.CfnGlossary(this, 'BusinessGlossary', {
      domainIdentifier: this.dataZoneDomain.attrId,
      name: 'Enterprise Business Glossary',
      description: 'Standardized business terms and definitions',
      status: 'ENABLED',
    });

    // Create sample glossary terms
    const customerLifetimeValueTerm = new datazone.CfnGlossaryTerm(this, 'CustomerLifetimeValueTerm', {
      domainIdentifier: this.dataZoneDomain.attrId,
      glossaryIdentifier: businessGlossary.attrId,
      name: 'Customer Lifetime Value',
      shortDescription: 'The predicted revenue that a customer will generate during their relationship with the company',
      longDescription: 'Customer Lifetime Value (CLV) is calculated using historical transaction data, customer behavior patterns, and predictive analytics to estimate the total economic value a customer represents over their entire relationship with the organization.',
    });

    const customerSegmentTerm = new datazone.CfnGlossaryTerm(this, 'CustomerSegmentTerm', {
      domainIdentifier: this.dataZoneDomain.attrId,
      glossaryIdentifier: businessGlossary.attrId,
      name: 'Customer Segment',
      shortDescription: 'Business classification of customers based on value, behavior, and characteristics',
      longDescription: 'Customer segments include Premium (high-value customers), Standard (regular customers), and Basic (low-engagement customers). Segmentation drives personalized marketing and service strategies.',
    });

    // Create data project for analytics team
    const analyticsProject = new datazone.CfnProject(this, 'AnalyticsProject', {
      domainIdentifier: this.dataZoneDomain.attrId,
      name: 'Customer Analytics Project',
      description: 'Analytics project for customer behavior and transaction analysis',
    });

    // Create Glue ETL job for data processing with lineage tracking
    const etlJobScript = `
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F
from pyspark.sql.types import *
import datetime

# Initialize Glue context
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATA_LAKE_BUCKET'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Enable lineage tracking
spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", f"s3://{args['DATA_LAKE_BUCKET']}/analytics-data/")

# Read raw customer data
raw_customer_df = spark.read.option("header", "true").csv(f"s3://{args['DATA_LAKE_BUCKET']}/raw-data/customer_data/")

# Data quality transformations
curated_customer_df = raw_customer_df \\
    .filter(F.col("customer_id").isNotNull()) \\
    .filter(F.col("email").contains("@")) \\
    .withColumn("registration_year", F.year(F.col("registration_date"))) \\
    .withColumn("registration_month", F.month(F.col("registration_date"))) \\
    .withColumn("data_quality_score", F.lit(95.0)) \\
    .withColumn("processed_timestamp", F.current_timestamp())

# Add data lineage metadata
curated_customer_df = curated_customer_df.withColumn("source_system", F.lit("CRM"))
curated_customer_df = curated_customer_df.withColumn("etl_job_id", F.lit(args['JOB_NAME']))
curated_customer_df = curated_customer_df.withColumn("data_classification", F.lit("confidential"))

# Write to curated zone with partitioning
curated_customer_df.write \\
    .partitionBy("registration_year", "registration_month") \\
    .mode("overwrite") \\
    .parquet(f"s3://{args['DATA_LAKE_BUCKET']}/curated-data/customer_data/")

# Create aggregated analytics data
analytics_df = curated_customer_df \\
    .groupBy("customer_segment", "region", "registration_year") \\
    .agg(
        F.count("customer_id").alias("customer_count"),
        F.avg("lifetime_value").alias("avg_lifetime_value"),
        F.sum("lifetime_value").alias("total_lifetime_value")
    )

# Write analytics data
analytics_df.write \\
    .mode("overwrite") \\
    .parquet(f"s3://{args['DATA_LAKE_BUCKET']}/analytics-data/customer_analytics/")

job.commit()
`;

    // Store ETL script in S3
    const etlScriptDeployment = new s3.BucketDeployment(this, 'ETLScriptDeployment', {
      sources: [s3.Source.data('customer_data_etl.py', etlJobScript)],
      destinationBucket: this.dataLakeBucket,
      destinationKeyPrefix: 'scripts/',
    });

    // Create Glue ETL job with enhanced configuration
    const etlJob = new glue.CfnJob(this, 'CustomerDataETLJob', {
      name: 'CustomerDataETLWithLineage',
      role: this.lakeFormationServiceRole.roleArn,
      command: {
        name: 'glueetl',
        scriptLocation: `s3://${this.dataLakeBucket.bucketName}/scripts/customer_data_etl.py`,
        pythonVersion: '3',
      },
      defaultArguments: {
        '--job-language': 'python',
        '--job-bookmark-option': 'job-bookmark-enable',
        '--enable-metrics': 'true',
        '--enable-continuous-cloudwatch-log': 'true',
        '--enable-spark-ui': 'true',
        '--spark-event-logs-path': `s3://${this.dataLakeBucket.bucketName}/spark-logs/`,
        '--enable-glue-datacatalog': 'true',
        '--DATA_LAKE_BUCKET': this.dataLakeBucket.bucketName,
      },
      maxRetries: 1,
      timeout: 60,
      maxCapacity: 2.0,
      glueVersion: '4.0',
      description: 'ETL job for customer data processing with lineage tracking',
    });

    // Create CloudWatch log group for data quality monitoring
    const dataQualityLogGroup = new logs.LogGroup(this, 'DataQualityLogGroup', {
      logGroupName: '/aws/datazone/data-quality',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create SNS topic for data quality alerts
    const alertTopic = new sns.Topic(this, 'DataQualityAlerts', {
      topicName: 'DataQualityAlerts',
      displayName: 'Data Lake Governance Alerts',
      description: 'SNS topic for data quality and governance alerts',
    });

    // Add email subscription if provided
    if (props.alertEmail) {
      alertTopic.addSubscription(new sns.EmailSubscription(props.alertEmail));
    }

    // Create CloudWatch alarm for failed ETL jobs
    const etlFailureAlarm = new cloudwatch.Alarm(this, 'ETLFailureAlarm', {
      alarmName: 'DataLakeETLFailures',
      alarmDescription: 'Alert when ETL jobs fail',
      metric: new cloudwatch.Metric({
        namespace: 'AWS/Glue',
        metricName: 'glue.ALL.job.failure',
        statistic: 'Sum',
        period: cdk.Duration.minutes(5),
      }),
      threshold: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      evaluationPeriods: 1,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    etlFailureAlarm.addAlarmAction(new cloudwatch.SnsAction(alertTopic));

    // Add resource dependencies
    customerDataTable.addDependency(this.glueDatabase);
    transactionDataTable.addDependency(this.glueDatabase);
    etlJob.addDependency(etlScriptDeployment.node.defaultChild as cdk.CfnResource);
    businessGlossary.addDependency(this.dataZoneDomain);
    customerLifetimeValueTerm.addDependency(businessGlossary);
    customerSegmentTerm.addDependency(businessGlossary);
    analyticsProject.addDependency(this.dataZoneDomain);

    // Add tags to all resources
    const tags = {
      Project: 'DataLakeGovernance',
      Environment: environment,
      Owner: 'DataEngineering',
      CostCenter: 'Analytics',
      Compliance: 'PII-Sensitive',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });

    // Output important resource information
    new cdk.CfnOutput(this, 'DataLakeBucketName', {
      value: this.dataLakeBucket.bucketName,
      description: 'Name of the S3 bucket for the data lake',
      exportName: `${this.stackName}-DataLakeBucket`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'Name of the Glue database for the data catalog',
      exportName: `${this.stackName}-GlueDatabase`,
    });

    new cdk.CfnOutput(this, 'DataZoneDomainId', {
      value: this.dataZoneDomain.attrId,
      description: 'ID of the DataZone domain',
      exportName: `${this.stackName}-DataZoneDomain`,
    });

    new cdk.CfnOutput(this, 'LakeFormationServiceRoleArn', {
      value: this.lakeFormationServiceRole.roleArn,
      description: 'ARN of the Lake Formation service role',
      exportName: `${this.stackName}-LakeFormationRole`,
    });

    new cdk.CfnOutput(this, 'DataAnalystRoleArn', {
      value: this.dataAnalystRole.roleArn,
      description: 'ARN of the data analyst role',
      exportName: `${this.stackName}-DataAnalystRole`,
    });

    new cdk.CfnOutput(this, 'AlertTopicArn', {
      value: alertTopic.topicArn,
      description: 'ARN of the SNS topic for data quality alerts',
      exportName: `${this.stackName}-AlertTopic`,
    });

    new cdk.CfnOutput(this, 'ETLJobName', {
      value: etlJob.ref,
      description: 'Name of the Glue ETL job for data processing',
      exportName: `${this.stackName}-ETLJob`,
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get configuration from CDK context or environment variables
const domainName = app.node.tryGetContext('domainName') || process.env.DOMAIN_NAME || 'enterprise-data-governance';
const environment = app.node.tryGetContext('environment') || process.env.ENVIRONMENT || 'production';
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;

// Create the stack
new DataLakeGovernanceStack(app, 'DataLakeGovernanceStack', {
  domainName,
  environment,
  alertEmail,
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Advanced Data Lake Governance with Lake Formation and DataZone (uksb-1tupboc58)',
});

// Synthesize the app
app.synth();