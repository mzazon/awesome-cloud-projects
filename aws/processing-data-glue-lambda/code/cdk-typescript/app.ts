#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { Construct } from 'constructs';

/**
 * CDK Stack for Serverless ETL Pipelines with AWS Glue and Lambda
 * 
 * This stack creates a complete serverless ETL pipeline including:
 * - S3 bucket for data storage with lifecycle policies
 * - IAM roles with least privilege access
 * - Glue database and crawler for data catalog
 * - Glue ETL job for data transformation
 * - Lambda function for pipeline orchestration
 * - EventBridge rules for scheduled execution
 * - S3 event notifications for real-time processing
 * - CloudWatch logging and monitoring
 */
export class ServerlessEtlPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 6).toLowerCase();

    // =============================================================================
    // S3 BUCKET FOR DATA LAKE STORAGE
    // =============================================================================

    /**
     * S3 bucket serves as the foundation for our data lake architecture
     * Configured with versioning, lifecycle policies, and security best practices
     */
    const dataLakeBucket = new s3.Bucket(this, 'DataLakeBucket', {
      bucketName: `serverless-etl-pipeline-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            }
          ]
        }
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes only
      autoDeleteObjects: true, // For demo purposes only
    });

    // =============================================================================
    // IAM ROLES AND POLICIES
    // =============================================================================

    /**
     * IAM role for AWS Glue service with permissions for S3 access and Data Catalog operations
     * Follows principle of least privilege with specific resource ARNs
     */
    const glueRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `GlueETLRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      description: 'IAM role for AWS Glue ETL jobs with S3 and Data Catalog access',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        GlueS3AccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetBucketLocation',
                's3:ListBucketMultipartUploads',
                's3:ListMultipartUploadParts',
                's3:AbortMultipartUpload'
              ],
              resources: [
                dataLakeBucket.bucketArn,
                `${dataLakeBucket.bucketArn}/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:log-group:/aws-glue/*`]
            })
          ]
        })
      }
    });

    /**
     * IAM role for Lambda function with permissions to trigger Glue jobs and access S3
     * Includes CloudWatch Logs permissions for monitoring and debugging
     */
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `LambdaETLRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Lambda function to orchestrate ETL pipeline',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        LambdaGlueAccessPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:StartJobRun',
                'glue:GetJobRun',
                'glue:GetJobRuns',
                'glue:BatchStopJobRun',
                'glue:StartCrawler',
                'glue:GetCrawler',
                'glue:GetCrawlerMetrics',
                'glue:StartWorkflowRun',
                'glue:GetWorkflowRun'
              ],
              resources: [
                `arn:aws:glue:${this.region}:${this.account}:job/*`,
                `arn:aws:glue:${this.region}:${this.account}:crawler/*`,
                `arn:aws:glue:${this.region}:${this.account}:workflow/*`
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:ListBucket'
              ],
              resources: [
                dataLakeBucket.bucketArn,
                `${dataLakeBucket.bucketArn}/*`
              ]
            })
          ]
        })
      }
    });

    // =============================================================================
    // GLUE DATABASE AND DATA CATALOG
    // =============================================================================

    /**
     * Glue database serves as the logical container for table metadata
     * Provides centralized schema registry for the data lake
     */
    const glueDatabase = new glue.CfnDatabase(this, 'EtlDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `etl_database_${uniqueSuffix}`,
        description: 'Database for serverless ETL pipeline data catalog'
      }
    });

    /**
     * Glue crawler automatically discovers and catalogs data in S3
     * Runs on-demand to update schema information when data structure changes
     */
    const glueCrawler = new glue.CfnCrawler(this, 'EtlCrawler', {
      name: `etl_crawler_${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      description: 'Crawler for discovering and cataloging raw data schemas',
      targets: {
        s3Targets: [
          {
            path: `s3://${dataLakeBucket.bucketName}/raw-data/`
          }
        ]
      },
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'LOG'
      },
      configuration: JSON.stringify({
        Version: 1.0,
        CrawlerOutput: {
          Partitions: { AddOrUpdateBehavior: 'InheritFromTable' },
          Tables: { AddOrUpdateBehavior: 'MergeNewColumns' }
        }
      })
    });

    // =============================================================================
    // GLUE ETL JOB AND SCRIPT
    // =============================================================================

    /**
     * ETL script content for data transformation using PySpark
     * Performs joins, aggregations, and data type conversions
     */
    const etlScriptContent = `import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *

# Parse job arguments
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'database_name',
    'table_prefix',
    'output_path'
])

# Initialize contexts
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read data from Glue Data Catalog with error handling
    sales_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['database_name'],
        table_name=f"{args['table_prefix']}_sales_data_csv"
    ).toDF()
    
    customer_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['database_name'],
        table_name=f"{args['table_prefix']}_customer_data_csv"
    ).toDF()
    
    # Data quality checks
    print(f"Sales data count: {sales_df.count()}")
    print(f"Customer data count: {customer_df.count()}")
    
    # Data transformations with proper error handling
    # 1. Convert price to numeric and calculate total
    sales_df = sales_df.withColumn("price", F.col("price").cast("double"))
    sales_df = sales_df.withColumn("total_amount", 
        F.col("quantity") * F.col("price"))
    
    # 2. Convert order_date to proper date format
    sales_df = sales_df.withColumn("order_date", 
        F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    
    # 3. Join sales with customer data
    enriched_df = sales_df.join(customer_df, "customer_id", "inner")
    
    # 4. Calculate aggregated metrics
    daily_sales = enriched_df.groupBy("order_date", "region").agg(
        F.sum("total_amount").alias("daily_revenue"),
        F.count("order_id").alias("daily_orders"),
        F.countDistinct("customer_id").alias("unique_customers")
    )
    
    # 5. Calculate customer metrics
    customer_metrics = enriched_df.groupBy("customer_id", "name", "status").agg(
        F.sum("total_amount").alias("total_spent"),
        F.count("order_id").alias("total_orders"),
        F.avg("total_amount").alias("avg_order_value")
    )
    
    # Convert back to DynamicFrame for optimized writing
    daily_sales_df = DynamicFrame.fromDF(daily_sales, glueContext, "daily_sales")
    customer_metrics_df = DynamicFrame.fromDF(customer_metrics, glueContext, "customer_metrics")
    
    # Write processed data to S3 in Parquet format with partitioning
    glueContext.write_dynamic_frame.from_options(
        frame=daily_sales_df,
        connection_type="s3",
        connection_options={
            "path": f"{args['output_path']}/daily_sales/",
            "partitionKeys": ["order_date"]
        },
        format="parquet",
        format_options={
            "compression": "snappy"
        }
    )
    
    glueContext.write_dynamic_frame.from_options(
        frame=customer_metrics_df,
        connection_type="s3",
        connection_options={
            "path": f"{args['output_path']}/customer_metrics/"
        },
        format="parquet",
        format_options={
            "compression": "snappy"
        }
    )
    
    # Log processing statistics
    print(f"Processed {enriched_df.count()} enriched records")
    print(f"Generated {daily_sales.count()} daily sales records")
    print(f"Generated {customer_metrics.count()} customer metric records")
    
    job.commit()
    
except Exception as e:
    print(f"Job failed with error: {str(e)}")
    job.commit()
    raise e`;

    /**
     * Upload ETL script to S3 for Glue job execution
     * Creates the script object in the scripts/ prefix
     */
    const etlScriptObject = new s3.BucketDeployment(this, 'EtlScriptDeployment', {
      sources: [
        s3deploy.Source.data('glue_etl_script.py', etlScriptContent)
      ],
      destinationBucket: dataLakeBucket,
      destinationKeyPrefix: 'scripts/',
    });

    /**
     * Glue ETL job configuration with optimized settings
     * Uses Glue 4.0 with G.1X worker type for balanced compute and memory
     */
    const glueEtlJob = new glue.CfnJob(this, 'EtlJob', {
      name: `etl_job_${uniqueSuffix}`,
      role: glueRole.roleArn,
      command: {
        name: 'glueetl',
        scriptLocation: `s3://${dataLakeBucket.bucketName}/scripts/glue_etl_script.py`,
        pythonVersion: '3'
      },
      description: 'Serverless ETL job for data transformation and analytics',
      defaultArguments: {
        '--database_name': glueDatabase.ref,
        '--table_prefix': 'raw_data',
        '--output_path': `s3://${dataLakeBucket.bucketName}/processed-data`,
        '--TempDir': `s3://${dataLakeBucket.bucketName}/temp/`,
        '--enable-metrics': '',
        '--enable-continuous-cloudwatch-log': 'true',
        '--job-language': 'python',
        '--job-bookmark-option': 'job-bookmark-enable'
      },
      executionProperty: {
        maxConcurrentRuns: 1
      },
      maxRetries: 1,
      timeout: 60,
      glueVersion: '4.0',
      workerType: 'G.1X',
      numberOfWorkers: 2
    });

    // =============================================================================
    // LAMBDA FUNCTION FOR PIPELINE ORCHESTRATION
    // =============================================================================

    /**
     * Lambda function code for orchestrating the ETL pipeline
     * Handles job triggering, status monitoring, and error handling
     */
    const lambdaCode = `import json
import boto3
import logging
from datetime import datetime
import os

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
glue_client = boto3.client('glue')
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to orchestrate ETL pipeline
    Supports both scheduled and event-driven execution
    """
    try:
        # Extract configuration from environment variables and event
        job_name = os.environ.get('GLUE_JOB_NAME')
        database_name = os.environ.get('GLUE_DATABASE_NAME')
        output_path = os.environ.get('OUTPUT_PATH')
        
        if not job_name:
            raise ValueError("GLUE_JOB_NAME environment variable is required")
        
        # Handle S3 event trigger
        if 'Records' in event:
            for record in event['Records']:
                if record.get('eventSource') == 'aws:s3':
                    bucket = record['s3']['bucket']['name']
                    key = record['s3']['object']['key']
                    logger.info(f"Processing S3 event for object: s3://{bucket}/{key}")
        
        # Start Glue job with enhanced error handling
        response = glue_client.start_job_run(
            JobName=job_name,
            Arguments={
                '--database_name': database_name,
                '--table_prefix': 'raw_data',
                '--output_path': output_path
            }
        )
        
        job_run_id = response['JobRunId']
        logger.info(f"Started Glue job {job_name} with run ID: {job_run_id}")
        
        # Return success response
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'ETL pipeline initiated successfully',
                'job_name': job_name,
                'job_run_id': job_run_id,
                'timestamp': datetime.now().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error in ETL pipeline: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }

def check_job_status(job_name, job_run_id):
    """
    Check the status of a Glue job run
    """
    try:
        response = glue_client.get_job_run(
            JobName=job_name,
            RunId=job_run_id
        )
        
        job_run = response['JobRun']
        status = job_run['JobRunState']
        
        return {
            'status': status,
            'started_on': job_run.get('StartedOn'),
            'completed_on': job_run.get('CompletedOn'),
            'execution_time': job_run.get('ExecutionTime'),
            'error_message': job_run.get('ErrorMessage')
        }
        
    except Exception as e:
        logger.error(f"Error checking job status: {str(e)}")
        return {'error': str(e)}`;

    /**
     * CloudWatch Log Group for Lambda function with retention policy
     * Provides centralized logging with cost-effective retention
     */
    const lambdaLogGroup = new logs.LogGroup(this, 'LambdaLogGroup', {
      logGroupName: `/aws/lambda/etl-orchestrator-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    /**
     * Lambda function for ETL pipeline orchestration
     * Configured with environment variables and appropriate timeout
     */
    const etlOrchestratorFunction = new lambda.Function(this, 'EtlOrchestratorFunction', {
      functionName: `etl-orchestrator-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(lambdaCode),
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Orchestrates serverless ETL pipeline execution',
      environment: {
        GLUE_JOB_NAME: glueEtlJob.ref,
        GLUE_DATABASE_NAME: glueDatabase.ref,
        OUTPUT_PATH: `s3://${dataLakeBucket.bucketName}/processed-data`
      },
      logGroup: lambdaLogGroup
    });

    // =============================================================================
    // EVENT-DRIVEN PROCESSING
    // =============================================================================

    /**
     * S3 event notification to trigger Lambda on new data arrival
     * Filters for CSV files in the raw-data/ prefix for automatic processing
     */
    dataLakeBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(etlOrchestratorFunction),
      {
        prefix: 'raw-data/',
        suffix: '.csv'
      }
    );

    /**
     * EventBridge rule for scheduled ETL job execution
     * Runs daily at 2 AM UTC for regular batch processing
     */
    const scheduledRule = new events.Rule(this, 'ScheduledEtlRule', {
      ruleName: `scheduled-etl-rule-${uniqueSuffix}`,
      description: 'Triggers ETL pipeline on a scheduled basis',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '2',
        day: '*',
        month: '*',
        year: '*'
      }),
      enabled: true
    });

    // Add Lambda function as target for scheduled rule
    scheduledRule.addTarget(new targets.LambdaFunction(etlOrchestratorFunction, {
      event: events.RuleTargetInput.fromObject({
        trigger: 'scheduled',
        timestamp: events.EventField.fromPath('$.time')
      })
    }));

    // =============================================================================
    // GLUE WORKFLOW FOR ADVANCED ORCHESTRATION
    // =============================================================================

    /**
     * Glue workflow provides visual pipeline representation and dependency management
     * Enables complex multi-step ETL processes with conditional logic
     */
    const glueWorkflow = new glue.CfnWorkflow(this, 'EtlWorkflow', {
      name: `etl_workflow_${uniqueSuffix}`,
      description: 'Serverless ETL Pipeline Workflow with dependency management'
    });

    /**
     * Glue trigger for workflow-based job execution
     * Can be extended to include multiple jobs with dependencies
     */
    const workflowTrigger = new glue.CfnTrigger(this, 'WorkflowTrigger', {
      name: `start-etl-trigger-${uniqueSuffix}`,
      workflowName: glueWorkflow.ref,
      type: 'ON_DEMAND',
      description: 'On-demand trigger for ETL workflow execution',
      actions: [
        {
          jobName: glueEtlJob.ref
        }
      ]
    });

    // =============================================================================
    // OUTPUTS FOR VALIDATION AND INTEGRATION
    // =============================================================================

    new cdk.CfnOutput(this, 'DataLakeBucketName', {
      value: dataLakeBucket.bucketName,
      description: 'S3 bucket name for data lake storage',
      exportName: `${this.stackName}-DataLakeBucket`
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Glue database name for data catalog',
      exportName: `${this.stackName}-GlueDatabase`
    });

    new cdk.CfnOutput(this, 'GlueJobName', {
      value: glueEtlJob.ref,
      description: 'Glue ETL job name for data processing',
      exportName: `${this.stackName}-GlueJob`
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: etlOrchestratorFunction.functionName,
      description: 'Lambda function name for pipeline orchestration',
      exportName: `${this.stackName}-LambdaFunction`
    });

    new cdk.CfnOutput(this, 'GlueWorkflowName', {
      value: glueWorkflow.ref,
      description: 'Glue workflow name for advanced orchestration',
      exportName: `${this.stackName}-GlueWorkflow`
    });

    new cdk.CfnOutput(this, 'RawDataPath', {
      value: `s3://${dataLakeBucket.bucketName}/raw-data/`,
      description: 'S3 path for uploading raw data files',
      exportName: `${this.stackName}-RawDataPath`
    });

    new cdk.CfnOutput(this, 'ProcessedDataPath', {
      value: `s3://${dataLakeBucket.bucketName}/processed-data/`,
      description: 'S3 path for processed analytics-ready data',
      exportName: `${this.stackName}-ProcessedDataPath`
    });
  }
}

// =============================================================================
// CDK APPLICATION INITIALIZATION
// =============================================================================

/**
 * Initialize CDK application and deploy the serverless ETL pipeline stack
 * Includes environment configuration and stack tags for resource management
 */
const app = new cdk.App();

new ServerlessEtlPipelineStack(app, 'ServerlessEtlPipelineStack', {
  description: 'Serverless ETL Pipeline with AWS Glue and Lambda (qs-1234567890123)',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'ServerlessETLPipeline',
    Environment: 'Development',
    ManagedBy: 'CDK',
    CostCenter: 'Analytics',
    Owner: 'DataEngineering'
  }
});

// Enable CDK Nag for security and best practice validation
// Uncomment the following lines to enable CDK Nag checks
/*
import { AwsSolutionsChecks } from 'cdk-nag';
cdk.Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }));
*/

app.synth();