#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for AWS Glue Workflows Data Pipeline Orchestration
 * 
 * This stack creates:
 * - S3 buckets for raw and processed data
 * - IAM role for Glue operations
 * - Glue database, crawlers, and ETL jobs
 * - Glue workflow with triggers for orchestration
 * - Sample data deployment
 */
export class DataPipelineOrchestrationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-6);

    // ===== S3 BUCKETS =====
    
    // Raw data bucket
    const rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `raw-data-${uniqueSuffix}`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Processed data bucket
    const processedDataBucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `processed-data-${uniqueSuffix}`,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          expiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // ===== IAM ROLE FOR GLUE =====
    
    // IAM role for Glue operations with appropriate permissions
    const glueRole = new iam.Role(this, 'GlueWorkflowRole', {
      roleName: `GlueWorkflowRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        S3AccessPolicy: new iam.PolicyDocument({
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
                rawDataBucket.bucketArn,
                `${rawDataBucket.bucketArn}/*`,
                processedDataBucket.bucketArn,
                `${processedDataBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        CloudWatchLogsPolicy: new iam.PolicyDocument({
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

    // ===== GLUE DATABASE =====
    
    // Glue database for data catalog
    const glueDatabase = new glue.CfnDatabase(this, 'WorkflowDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `workflow-database-${uniqueSuffix}`,
        description: 'Database for workflow data catalog',
      },
    });

    // ===== ETL SCRIPT DEPLOYMENT =====
    
    // Deploy ETL script to S3
    const etlScriptDeployment = new s3deploy.BucketDeployment(this, 'ETLScriptDeployment', {
      sources: [
        s3deploy.Source.data('etl-script.py', `import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'OUTPUT_BUCKET'])

# Initialize Glue context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read data from the catalog
    datasource0 = glueContext.create_dynamic_frame.from_catalog(
        database=args['DATABASE_NAME'],
        table_name="input"
    )
    
    # Apply transformations
    mapped_data = ApplyMapping.apply(
        frame=datasource0,
        mappings=[
            ("customer_id", "string", "customer_id", "int"),
            ("name", "string", "customer_name", "string"),
            ("email", "string", "email", "string"),
            ("purchase_amount", "string", "purchase_amount", "double"),
            ("purchase_date", "string", "purchase_date", "string")
        ]
    )
    
    # Write to S3 in Parquet format
    glueContext.write_dynamic_frame.from_options(
        frame=mapped_data,
        connection_type="s3",
        connection_options={"path": f"s3://{args['OUTPUT_BUCKET']}/output/"},
        format="parquet"
    )
    
    print("ETL job completed successfully")
    
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise e
finally:
    job.commit()
`),
      ],
      destinationBucket: processedDataBucket,
      destinationKeyPrefix: 'scripts/',
    });

    // Deploy sample data to S3
    const sampleDataDeployment = new s3deploy.BucketDeployment(this, 'SampleDataDeployment', {
      sources: [
        s3deploy.Source.data('sample-data.csv', `customer_id,name,email,purchase_amount,purchase_date
1,John Doe,john@example.com,150.00,2024-01-15
2,Jane Smith,jane@example.com,200.00,2024-01-16
3,Bob Johnson,bob@example.com,75.00,2024-01-17
4,Alice Brown,alice@example.com,300.00,2024-01-18
5,Charlie Wilson,charlie@example.com,125.00,2024-01-19
6,Diana Davis,diana@example.com,250.00,2024-01-20
7,Frank Miller,frank@example.com,100.00,2024-01-21
8,Grace Lee,grace@example.com,175.00,2024-01-22
9,Henry Taylor,henry@example.com,225.00,2024-01-23
10,Ivy Chen,ivy@example.com,350.00,2024-01-24`),
      ],
      destinationBucket: rawDataBucket,
      destinationKeyPrefix: 'input/',
    });

    // ===== GLUE CRAWLERS =====
    
    // Source data crawler
    const sourceCrawler = new glue.CfnCrawler(this, 'SourceCrawler', {
      name: `source-crawler-${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${rawDataBucket.bucketName}/input/`,
          },
        ],
      },
      description: 'Crawler to discover source data schema',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'DEPRECATE_IN_DATABASE',
      },
    });

    // Target data crawler
    const targetCrawler = new glue.CfnCrawler(this, 'TargetCrawler', {
      name: `target-crawler-${uniqueSuffix}`,
      role: glueRole.roleArn,
      databaseName: glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${processedDataBucket.bucketName}/output/`,
          },
        ],
      },
      description: 'Crawler to discover processed data schema',
      schemaChangePolicy: {
        updateBehavior: 'UPDATE_IN_DATABASE',
        deleteBehavior: 'DEPRECATE_IN_DATABASE',
      },
    });

    // ===== GLUE ETL JOB =====
    
    // ETL job for data processing
    const etlJob = new glue.CfnJob(this, 'DataProcessingJob', {
      name: `data-processing-job-${uniqueSuffix}`,
      role: glueRole.roleArn,
      command: {
        name: 'glueetl',
        scriptLocation: `s3://${processedDataBucket.bucketName}/scripts/etl-script.py`,
        pythonVersion: '3',
      },
      defaultArguments: {
        '--DATABASE_NAME': glueDatabase.ref,
        '--OUTPUT_BUCKET': processedDataBucket.bucketName,
        '--enable-continuous-cloudwatch-log': 'true',
        '--enable-metrics': 'true',
        '--enable-spark-ui': 'true',
        '--spark-event-logs-path': `s3://${processedDataBucket.bucketName}/spark-logs/`,
      },
      glueVersion: '4.0',
      maxRetries: 1,
      timeout: 60,
      description: 'ETL job for data processing in workflow',
      executionProperty: {
        maxConcurrentRuns: 1,
      },
    });

    // Ensure ETL job depends on script deployment
    etlJob.addDependency(etlScriptDeployment.node.defaultChild as cdk.CfnResource);

    // ===== GLUE WORKFLOW =====
    
    // Create the workflow
    const workflow = new glue.CfnWorkflow(this, 'DataPipelineWorkflow', {
      name: `data-pipeline-workflow-${uniqueSuffix}`,
      description: 'Data pipeline workflow orchestrating crawlers and ETL jobs',
      maxConcurrentRuns: 1,
      defaultRunProperties: {
        environment: 'production',
        pipeline_version: '1.0',
      },
    });

    // ===== WORKFLOW TRIGGERS =====
    
    // Schedule trigger to start the workflow daily
    const scheduleTrigger = new glue.CfnTrigger(this, 'ScheduleTrigger', {
      name: `schedule-trigger-${uniqueSuffix}`,
      workflowName: workflow.ref,
      type: 'SCHEDULED',
      schedule: 'cron(0 2 * * ? *)', // Daily at 2 AM UTC
      description: 'Daily trigger at 2 AM UTC',
      startOnCreation: true,
      actions: [
        {
          crawlerName: sourceCrawler.ref,
        },
      ],
    });

    // Event trigger for job dependency (starts ETL job after crawler succeeds)
    const crawlerSuccessTrigger = new glue.CfnTrigger(this, 'CrawlerSuccessTrigger', {
      name: `crawler-success-trigger-${uniqueSuffix}`,
      workflowName: workflow.ref,
      type: 'CONDITIONAL',
      predicate: {
        logical: 'AND',
        conditions: [
          {
            logicalOperator: 'EQUALS',
            crawlerName: sourceCrawler.ref,
            crawlState: 'SUCCEEDED',
          },
        ],
      },
      description: 'Trigger ETL job after successful crawler completion',
      startOnCreation: true,
      actions: [
        {
          jobName: etlJob.ref,
        },
      ],
    });

    // Final event trigger for target crawler (starts after ETL job succeeds)
    const jobSuccessTrigger = new glue.CfnTrigger(this, 'JobSuccessTrigger', {
      name: `job-success-trigger-${uniqueSuffix}`,
      workflowName: workflow.ref,
      type: 'CONDITIONAL',
      predicate: {
        logical: 'AND',
        conditions: [
          {
            logicalOperator: 'EQUALS',
            jobName: etlJob.ref,
            state: 'SUCCEEDED',
          },
        ],
      },
      description: 'Trigger target crawler after successful job completion',
      startOnCreation: true,
      actions: [
        {
          crawlerName: targetCrawler.ref,
        },
      ],
    });

    // ===== CLOUDWATCH LOG GROUPS =====
    
    // Log group for Glue jobs
    const glueJobLogGroup = new logs.LogGroup(this, 'GlueJobLogGroup', {
      logGroupName: `/aws-glue/jobs/${etlJob.ref}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Log group for Glue crawlers
    const glueCrawlerLogGroup = new logs.LogGroup(this, 'GlueCrawlerLogGroup', {
      logGroupName: `/aws-glue/crawlers/${sourceCrawler.ref}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // ===== OUTPUTS =====
    
    new cdk.CfnOutput(this, 'RawDataBucketName', {
      value: rawDataBucket.bucketName,
      description: 'Name of the raw data S3 bucket',
      exportName: `${this.stackName}-RawDataBucket`,
    });

    new cdk.CfnOutput(this, 'ProcessedDataBucketName', {
      value: processedDataBucket.bucketName,
      description: 'Name of the processed data S3 bucket',
      exportName: `${this.stackName}-ProcessedDataBucket`,
    });

    new cdk.CfnOutput(this, 'GlueRoleArn', {
      value: glueRole.roleArn,
      description: 'ARN of the Glue IAM role',
      exportName: `${this.stackName}-GlueRoleArn`,
    });

    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: glueDatabase.ref,
      description: 'Name of the Glue database',
      exportName: `${this.stackName}-GlueDatabase`,
    });

    new cdk.CfnOutput(this, 'WorkflowName', {
      value: workflow.ref,
      description: 'Name of the Glue workflow',
      exportName: `${this.stackName}-WorkflowName`,
    });

    new cdk.CfnOutput(this, 'SourceCrawlerName', {
      value: sourceCrawler.ref,
      description: 'Name of the source data crawler',
      exportName: `${this.stackName}-SourceCrawler`,
    });

    new cdk.CfnOutput(this, 'TargetCrawlerName', {
      value: targetCrawler.ref,
      description: 'Name of the target data crawler',
      exportName: `${this.stackName}-TargetCrawler`,
    });

    new cdk.CfnOutput(this, 'ETLJobName', {
      value: etlJob.ref,
      description: 'Name of the ETL job',
      exportName: `${this.stackName}-ETLJob`,
    });

    new cdk.CfnOutput(this, 'WorkflowStartCommand', {
      value: `aws glue start-workflow-run --name ${workflow.ref}`,
      description: 'Command to start the workflow manually',
    });

    new cdk.CfnOutput(this, 'WorkflowStatusCommand', {
      value: `aws glue get-workflow-runs --name ${workflow.ref}`,
      description: 'Command to check workflow status',
    });
  }
}

// ===== CDK APP =====

const app = new cdk.App();

// Create the stack
new DataPipelineOrchestrationStack(app, 'DataPipelineOrchestrationStack', {
  description: 'AWS Glue Workflows for Data Pipeline Orchestration',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  tags: {
    Project: 'DataPipelineOrchestration',
    Environment: 'Production',
    ManagedBy: 'CDK',
  },
});