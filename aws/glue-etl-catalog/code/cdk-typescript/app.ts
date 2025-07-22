#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for AWS Glue ETL Pipeline with Data Catalog Management
 * 
 * This stack creates:
 * - S3 buckets for raw and processed data
 * - IAM role for Glue service
 * - Glue database for Data Catalog
 * - Glue crawlers for data discovery
 * - Glue ETL job for data transformation
 * - Sample data for testing
 */
export class GlueEtlPipelineStack extends cdk.Stack {
  // Public properties for stack outputs
  public readonly rawDataBucket: s3.Bucket;
  public readonly processedDataBucket: s3.Bucket;
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly glueRole: iam.Role;
  public readonly rawDataCrawler: glue.CfnCrawler;
  public readonly processedDataCrawler: glue.CfnCrawler;
  public readonly etlJob: glue.CfnJob;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ==============================================
    // S3 BUCKETS FOR DATA STORAGE
    // ==============================================
    
    // Raw data bucket - stores incoming data files
    this.rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `raw-data-${uniqueSuffix}`,
      // Enable versioning for data protection
      versioned: true,
      // Block public access for security
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      // Lifecycle rules for cost optimization
      lifecycleRules: [
        {
          id: 'ArchiveOldVersions',
          enabled: true,
          noncurrentVersionTransitions: [
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
      // Remove bucket on stack deletion (for demo purposes)
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Processed data bucket - stores transformed data
    this.processedDataBucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `processed-data-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'OptimizeStorage',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ==============================================
    // IAM ROLE FOR GLUE SERVICE
    // ==============================================
    
    // Service role for AWS Glue with appropriate permissions
    this.glueRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `GlueServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'Service role for AWS Glue ETL jobs and crawlers',
      managedPolicies: [
        // AWS managed policy for Glue service
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        // Custom policy for S3 access to our specific buckets
        GlueS3Access: new iam.PolicyDocument({
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
                this.rawDataBucket.bucketArn,
                `${this.rawDataBucket.bucketArn}/*`,
                this.processedDataBucket.bucketArn,
                `${this.processedDataBucket.bucketArn}/*`,
              ],
            }),
            // CloudWatch Logs permissions for job monitoring
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [
                `arn:aws:logs:${this.region}:${this.account}:log-group:/aws-glue/*`,
              ],
            }),
          ],
        }),
      },
    });

    // ==============================================
    // GLUE DATABASE FOR DATA CATALOG
    // ==============================================
    
    // Glue database to organize table metadata
    this.glueDatabase = new glue.CfnDatabase(this, 'AnalyticsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `analytics-database-${uniqueSuffix}`,
        description: 'Analytics database for ETL pipeline data catalog',
        // Organize tables with location-based structure
        locationUri: this.rawDataBucket.s3UrlForObject(),
      },
    });

    // ==============================================
    // SAMPLE DATA DEPLOYMENT
    // ==============================================
    
    // Deploy sample CSV data for sales
    new s3deploy.BucketDeployment(this, 'SampleSalesData', {
      sources: [
        s3deploy.Source.data(
          'sales/sample-sales.csv',
          'order_id,customer_id,product_name,quantity,price,order_date\n' +
          '1001,C001,Laptop,1,999.99,2024-01-15\n' +
          '1002,C002,Mouse,2,25.50,2024-01-15\n' +
          '1003,C001,Keyboard,1,75.00,2024-01-16\n' +
          '1004,C003,Monitor,1,299.99,2024-01-16\n' +
          '1005,C002,Headphones,1,149.99,2024-01-17'
        ),
      ],
      destinationBucket: this.rawDataBucket,
      retainOnDelete: false,
    });

    // Deploy sample JSON data for customers
    new s3deploy.BucketDeployment(this, 'SampleCustomerData', {
      sources: [
        s3deploy.Source.data(
          'customers/sample-customers.json',
          '{"customer_id": "C001", "name": "John Smith", "email": "john@email.com", "region": "North"}\n' +
          '{"customer_id": "C002", "name": "Jane Doe", "email": "jane@email.com", "region": "South"}\n' +
          '{"customer_id": "C003", "name": "Bob Johnson", "email": "bob@email.com", "region": "East"}'
        ),
      ],
      destinationBucket: this.rawDataBucket,
      retainOnDelete: false,
    });

    // ==============================================
    // GLUE ETL JOB SCRIPT
    // ==============================================
    
    // Deploy ETL script to S3 for Glue job
    new s3deploy.BucketDeployment(this, 'EtlScript', {
      sources: [
        s3deploy.Source.data(
          'scripts/etl-script.py',
          `import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame

# Parse job arguments
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read sales data from Data Catalog
    sales_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name="sales"
    )
    
    # Read customer data from Data Catalog
    customers_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name="customers"
    )
    
    # Convert to DataFrames for complex operations
    sales_df = sales_dynamic_frame.toDF()
    customers_df = customers_dynamic_frame.toDF()
    
    # Perform left join on customer_id
    enriched_sales = sales_df.join(customers_df, "customer_id", "left")
    
    # Add calculated column for total amount
    from pyspark.sql.functions import col
    enriched_sales = enriched_sales.withColumn("total_amount", 
                                             col("quantity") * col("price"))
    
    # Convert back to DynamicFrame for Glue operations
    enriched_dynamic_frame = DynamicFrame.fromDF(enriched_sales, glueContext, "enriched_sales")
    
    # Write to S3 in Parquet format for analytics
    glueContext.write_dynamic_frame.from_options(
        frame=enriched_dynamic_frame,
        connection_type="s3",
        connection_options={"path": f"s3://{args['OUTPUT_BUCKET']}/enriched-sales/"},
        format="parquet"
    )
    
    print("ETL job completed successfully")
    
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise e
    
finally:
    job.commit()
`
        ),
      ],
      destinationBucket: this.processedDataBucket,
      retainOnDelete: false,
    });

    // ==============================================
    // GLUE CRAWLERS FOR DATA DISCOVERY
    // ==============================================
    
    // Crawler for raw data discovery
    this.rawDataCrawler = new glue.CfnCrawler(this, 'RawDataCrawler', {
      name: `raw-data-crawler-${uniqueSuffix}`,
      role: this.glueRole.roleArn,
      databaseName: this.glueDatabase.ref,
      description: 'Crawler to discover schemas in raw data bucket',
      targets: {
        s3Targets: [
          {
            path: this.rawDataBucket.s3UrlForObject(),
            // Exclude the scripts folder from crawling
            exclusions: ['scripts/**'],
          },
        ],
      },
      // Configure crawler behavior
      configuration: JSON.stringify({
        Version: 1.0,
        // Group files with similar schemas into single tables
        Grouping: {
          TableGroupingPolicy: 'CombineCompatibleSchemas',
        },
        // Configure crawler output
        CrawlerOutput: {
          Partitions: { AddOrUpdateBehavior: 'InheritFromTable' },
          Tables: { AddOrUpdateBehavior: 'MergeNewColumns' },
        },
      }),
      // Schedule crawler to run weekly (optional)
      schedule: {
        scheduleExpression: 'cron(0 2 ? * SUN *)', // 2 AM every Sunday
      },
    });

    // Ensure crawler depends on database creation
    this.rawDataCrawler.addDependency(this.glueDatabase);

    // Crawler for processed data discovery
    this.processedDataCrawler = new glue.CfnCrawler(this, 'ProcessedDataCrawler', {
      name: `processed-data-crawler-${uniqueSuffix}`,
      role: this.glueRole.roleArn,
      databaseName: this.glueDatabase.ref,
      description: 'Crawler to discover schemas in processed data bucket',
      targets: {
        s3Targets: [
          {
            path: `${this.processedDataBucket.s3UrlForObject()}/enriched-sales/`,
          },
        ],
      },
      configuration: JSON.stringify({
        Version: 1.0,
        Grouping: {
          TableGroupingPolicy: 'CombineCompatibleSchemas',
        },
        CrawlerOutput: {
          Partitions: { AddOrUpdateBehavior: 'InheritFromTable' },
          Tables: { AddOrUpdateBehavior: 'MergeNewColumns' },
        },
      }),
    });

    this.processedDataCrawler.addDependency(this.glueDatabase);

    // ==============================================
    // GLUE ETL JOB
    // ==============================================
    
    // ETL job for data transformation
    this.etlJob = new glue.CfnJob(this, 'EtlTransformationJob', {
      name: `etl-transformation-job-${uniqueSuffix}`,
      role: this.glueRole.roleArn,
      description: 'ETL job to transform and enrich sales data',
      // Use Glue 4.0 for latest features and performance
      glueVersion: '4.0',
      command: {
        name: 'glueetl',
        scriptLocation: this.processedDataBucket.s3UrlForObject('scripts/etl-script.py'),
        pythonVersion: '3',
      },
      // Job configuration for optimal performance
      defaultArguments: {
        '--job-language': 'python',
        '--DATABASE_NAME': this.glueDatabase.ref,
        '--OUTPUT_BUCKET': this.processedDataBucket.bucketName,
        // Enable job bookmarking for incremental processing
        '--job-bookmark-option': 'job-bookmark-enable',
        // Enable CloudWatch metrics
        '--enable-metrics': 'true',
        // Continuous logging for debugging
        '--enable-continuous-cloudwatch-log': 'true',
        // Optimize for performance
        '--enable-glue-datacatalog': 'true',
        '--enable-spark-ui': 'true',
        // Set Spark configuration for better performance
        '--conf': 'spark.sql.adaptive.enabled=true --conf spark.sql.adaptive.coalescePartitions.enabled=true',
      },
      // Resource allocation
      maxRetries: 1,
      timeout: 60, // 60 minutes timeout
      // Use G.1X worker type for cost efficiency with small datasets
      workerType: 'G.1X',
      numberOfWorkers: 2,
      // Security configuration (optional)
      securityConfiguration: undefined, // Can be added if encryption is needed
    });

    // Ensure job depends on database and role creation
    this.etlJob.addDependency(this.glueDatabase);

    // ==============================================
    // STACK OUTPUTS
    // ==============================================
    
    // Output important resource information
    new cdk.CfnOutput(this, 'RawDataBucketName', {
      value: this.rawDataBucket.bucketName,
      description: 'Name of the S3 bucket for raw data',
      exportName: `${this.stackName}-RawDataBucket`,
    });

    new cdk.CfnOutput(this, 'ProcessedDataBucketName', {
      value: this.processedDataBucket.bucketName,
      description: 'Name of the S3 bucket for processed data',
      exportName: `${this.stackName}-ProcessedDataBucket`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'Name of the Glue database',
      exportName: `${this.stackName}-GlueDatabase`,
    });

    new cdk.CfnOutput(this, 'GlueRoleArn', {
      value: this.glueRole.roleArn,
      description: 'ARN of the Glue service role',
      exportName: `${this.stackName}-GlueRole`,
    });

    new cdk.CfnOutput(this, 'RawDataCrawlerName', {
      value: this.rawDataCrawler.name!,
      description: 'Name of the raw data crawler',
      exportName: `${this.stackName}-RawDataCrawler`,
    });

    new cdk.CfnOutput(this, 'ProcessedDataCrawlerName', {
      value: this.processedDataCrawler.name!,
      description: 'Name of the processed data crawler',
      exportName: `${this.stackName}-ProcessedDataCrawler`,
    });

    new cdk.CfnOutput(this, 'EtlJobName', {
      value: this.etlJob.name!,
      description: 'Name of the ETL job',
      exportName: `${this.stackName}-EtlJob`,
    });

    // Output AWS CLI commands for manual testing
    new cdk.CfnOutput(this, 'StartRawDataCrawlerCommand', {
      value: `aws glue start-crawler --name ${this.rawDataCrawler.name}`,
      description: 'Command to start the raw data crawler',
    });

    new cdk.CfnOutput(this, 'StartEtlJobCommand', {
      value: `aws glue start-job-run --job-name ${this.etlJob.name}`,
      description: 'Command to start the ETL job',
    });

    new cdk.CfnOutput(this, 'QueryDataCommand', {
      value: `aws athena start-query-execution --query-string "SELECT * FROM ${this.glueDatabase.ref}.enriched_sales LIMIT 10" --result-configuration OutputLocation=s3://${this.processedDataBucket.bucketName}/athena-results/`,
      description: 'Command to query processed data with Athena',
    });
  }
}

// ==============================================
// CDK APP DEFINITION
// ==============================================

// Create CDK app
const app = new cdk.App();

// Create the stack with default configuration
new GlueEtlPipelineStack(app, 'GlueEtlPipelineStack', {
  description: 'AWS Glue ETL Pipeline with Data Catalog Management (Recipe: etl-pipelines-aws-glue-data-catalog-management)',
  
  // Configure stack properties
  env: {
    // Use environment variables or default to us-east-1
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1',
  },
  
  // Add tags for resource management
  tags: {
    Project: 'GlueEtlPipeline',
    Environment: 'Demo',
    Recipe: 'etl-pipelines-aws-glue-data-catalog-management',
    ManagedBy: 'CDK',
  },
  
  // Enable termination protection for production use
  terminationProtection: false, // Set to true for production
});

// Synthesize the CDK app
app.synth();