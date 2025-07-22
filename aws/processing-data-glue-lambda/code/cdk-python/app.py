#!/usr/bin/env python3
"""
AWS CDK Python application for Serverless ETL Pipelines with AWS Glue and Lambda.

This CDK app creates a complete serverless ETL pipeline including:
- S3 bucket for data storage with organized prefixes
- IAM roles for Glue and Lambda with least privilege permissions
- AWS Glue database and crawler for data cataloging
- AWS Glue ETL job for data transformation
- Lambda function for pipeline orchestration
- Glue workflow with scheduled triggers
- S3 event notifications for real-time processing
- CloudWatch monitoring and logging
"""

import aws_cdk as cdk
from aws_cdk import (
    App,
    Stack,
    Environment,
    aws_s3 as s3,
    aws_iam as iam,
    aws_glue as glue,
    aws_lambda as lambda_,
    aws_s3_notifications as s3n,
    aws_events as events,
    aws_events_targets as targets,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy
)
from constructs import Construct
import json


class ServerlessETLStack(Stack):
    """
    CDK Stack for Serverless ETL Pipeline with AWS Glue and Lambda.
    
    This stack creates a complete serverless ETL solution that processes data
    using AWS Glue for heavy transformations and Lambda for orchestration.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Get stack parameters
        random_suffix = self.node.try_get_context("random_suffix") or "dev"
        
        # Create S3 bucket for data storage
        self.data_bucket = self._create_s3_bucket(random_suffix)
        
        # Create IAM roles
        self.glue_role = self._create_glue_role(random_suffix)
        self.lambda_role = self._create_lambda_role(random_suffix)
        
        # Create Glue database
        self.glue_database = self._create_glue_database(random_suffix)
        
        # Create Glue crawler
        self.glue_crawler = self._create_glue_crawler(random_suffix)
        
        # Upload ETL script and create Glue job
        self.glue_job = self._create_glue_job(random_suffix)
        
        # Create Lambda function for orchestration
        self.lambda_function = self._create_lambda_function(random_suffix)
        
        # Create Glue workflow
        self.glue_workflow = self._create_glue_workflow(random_suffix)
        
        # Configure S3 event notifications
        self._configure_s3_notifications()
        
        # Create CloudWatch Log Groups
        self._create_log_groups(random_suffix)
        
        # Create outputs
        self._create_outputs()

    def _create_s3_bucket(self, random_suffix: str) -> s3.Bucket:
        """Create S3 bucket with organized directory structure for ETL pipeline."""
        bucket = s3.Bucket(
            self,
            "ETLDataBucket",
            bucket_name=f"serverless-etl-pipeline-{random_suffix}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ]
        )
        
        return bucket

    def _create_glue_role(self, random_suffix: str) -> iam.Role:
        """Create IAM role for AWS Glue with necessary permissions."""
        glue_role = iam.Role(
            self,
            "GlueETLRole",
            role_name=f"GlueETLRole-{random_suffix}",
            assumed_by=iam.ServicePrincipal("glue.amazonaws.com"),
            description="IAM role for AWS Glue ETL jobs with S3 and catalog access",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSGlueServiceRole")
            ]
        )
        
        # Add custom policy for S3 access
        glue_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket",
                    "s3:GetBucketLocation"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )
        
        # Add CloudWatch Logs permissions
        glue_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                resources=[f"arn:aws:logs:{self.region}:{self.account}:*"]
            )
        )
        
        return glue_role

    def _create_lambda_role(self, random_suffix: str) -> iam.Role:
        """Create IAM role for Lambda with Glue orchestration permissions."""
        lambda_role = iam.Role(
            self,
            "LambdaETLRole",
            role_name=f"LambdaETLRole-{random_suffix}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Lambda ETL orchestration with Glue access",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name("service-role/AWSLambdaBasicExecutionRole")
            ]
        )
        
        # Add Glue permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "glue:StartJobRun",
                    "glue:GetJobRun",
                    "glue:GetJobRuns",
                    "glue:StartCrawler",
                    "glue:GetCrawler",
                    "glue:StartWorkflowRun",
                    "glue:GetWorkflowRun"
                ],
                resources=["*"]
            )
        )
        
        # Add S3 permissions
        lambda_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.data_bucket.bucket_arn,
                    f"{self.data_bucket.bucket_arn}/*"
                ]
            )
        )
        
        return lambda_role

    def _create_glue_database(self, random_suffix: str) -> glue.CfnDatabase:
        """Create Glue database for data catalog."""
        glue_database = glue.CfnDatabase(
            self,
            "GlueDatabase",
            catalog_id=self.account,
            database_input=glue.CfnDatabase.DatabaseInputProperty(
                name=f"etl_database_{random_suffix}",
                description="Database for serverless ETL pipeline data catalog"
            )
        )
        
        return glue_database

    def _create_glue_crawler(self, random_suffix: str) -> glue.CfnCrawler:
        """Create Glue crawler to catalog raw data."""
        glue_crawler = glue.CfnCrawler(
            self,
            "GlueCrawler",
            name=f"etl_crawler_{random_suffix}",
            role=self.glue_role.role_arn,
            database_name=self.glue_database.ref,
            description="Crawler for cataloging raw data in S3",
            targets=glue.CfnCrawler.TargetsProperty(
                s3_targets=[
                    glue.CfnCrawler.S3TargetProperty(
                        path=f"s3://{self.data_bucket.bucket_name}/raw-data/"
                    )
                ]
            ),
            schema_change_policy=glue.CfnCrawler.SchemaChangePolicyProperty(
                update_behavior="UPDATE_IN_DATABASE",
                delete_behavior="LOG"
            )
        )
        
        glue_crawler.add_dependency(self.glue_database)
        
        return glue_crawler

    def _create_glue_job(self, random_suffix: str) -> glue.CfnJob:
        """Create Glue ETL job with embedded script."""
        
        # ETL script content
        etl_script_content = '''import sys
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
    # Read data from Glue Data Catalog
    sales_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['database_name'],
        table_name=f"{args['table_prefix']}_sales_data_csv"
    ).toDF()
    
    customer_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['database_name'],
        table_name=f"{args['table_prefix']}_customer_data_csv"
    ).toDF()
    
    # Data transformations
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
    
    # Write processed data to S3
    # Convert back to DynamicFrame for writing
    daily_sales_df = DynamicFrame.fromDF(daily_sales, glueContext, "daily_sales")
    customer_metrics_df = DynamicFrame.fromDF(customer_metrics, glueContext, "customer_metrics")
    
    # Write daily sales data
    glueContext.write_dynamic_frame.from_options(
        frame=daily_sales_df,
        connection_type="s3",
        connection_options={
            "path": f"{args['output_path']}/daily_sales/",
            "partitionKeys": ["order_date"]
        },
        format="parquet"
    )
    
    # Write customer metrics
    glueContext.write_dynamic_frame.from_options(
        frame=customer_metrics_df,
        connection_type="s3",
        connection_options={
            "path": f"{args['output_path']}/customer_metrics/"
        },
        format="parquet"
    )
    
    # Log processing statistics
    print(f"Processed {sales_df.count()} sales records")
    print(f"Processed {customer_df.count()} customer records")
    print(f"Generated {daily_sales.count()} daily sales records")
    print(f"Generated {customer_metrics.count()} customer metric records")
    
except Exception as e:
    print(f"Error in ETL job: {str(e)}")
    raise e

job.commit()
'''
        
        # Create Glue job
        glue_job = glue.CfnJob(
            self,
            "GlueETLJob",
            name=f"etl_job_{random_suffix}",
            role=self.glue_role.role_arn,
            command=glue.CfnJob.JobCommandProperty(
                name="glueetl",
                python_version="3",
                script_location=f"s3://{self.data_bucket.bucket_name}/scripts/glue_etl_script.py"
            ),
            default_arguments={
                "--database_name": self.glue_database.ref,
                "--table_prefix": "raw_data",
                "--output_path": f"s3://{self.data_bucket.bucket_name}/processed-data",
                "--TempDir": f"s3://{self.data_bucket.bucket_name}/temp/",
                "--enable-metrics": "",
                "--enable-continuous-cloudwatch-log": "true",
                "--job-language": "python"
            },
            max_retries=1,
            timeout=60,
            glue_version="4.0",
            worker_type="G.1X",
            number_of_workers=2,
            description="ETL job for processing sales and customer data"
        )
        
        # Upload ETL script to S3
        s3.BucketDeployment(
            self,
            "ETLScriptDeployment",
            sources=[s3.Source.data("glue_etl_script.py", etl_script_content)],
            destination_bucket=self.data_bucket,
            destination_key_prefix="scripts/"
        )
        
        return glue_job

    def _create_lambda_function(self, random_suffix: str) -> lambda_.Function:
        """Create Lambda function for ETL orchestration."""
        
        # Lambda function code
        lambda_code = '''import json
import boto3
import logging
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
glue_client = boto3.client('glue')
s3_client = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to orchestrate ETL pipeline
    """
    try:
        # Extract configuration from event
        job_name = event.get('job_name')
        database_name = event.get('database_name')
        
        if not job_name:
            raise ValueError("job_name is required in event")
        
        # Start Glue job
        response = glue_client.start_job_run(
            JobName=job_name,
            Arguments={
                '--database_name': database_name,
                '--table_prefix': 'raw_data',
                '--output_path': event.get('output_path', 's3://default-bucket/processed-data')
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
        return {'error': str(e)}
'''
        
        lambda_function = lambda_.Function(
            self,
            "ETLOrchestrator",
            function_name=f"etl-orchestrator-{random_suffix}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(lambda_code),
            role=self.lambda_role,
            timeout=Duration.seconds(300),
            memory_size=256,
            description="Lambda function for orchestrating ETL pipeline",
            environment={
                "GLUE_DATABASE": self.glue_database.ref,
                "GLUE_JOB": self.glue_job.ref,
                "S3_BUCKET": self.data_bucket.bucket_name
            }
        )
        
        return lambda_function

    def _create_glue_workflow(self, random_suffix: str) -> glue.CfnWorkflow:
        """Create Glue workflow for pipeline orchestration."""
        glue_workflow = glue.CfnWorkflow(
            self,
            "GlueWorkflow",
            name=f"etl_workflow_{random_suffix}",
            description="Serverless ETL Pipeline Workflow"
        )
        
        # Create workflow trigger
        glue_trigger = glue.CfnTrigger(
            self,
            "WorkflowTrigger",
            name=f"start-etl-trigger-{random_suffix}",
            workflow_name=glue_workflow.ref,
            type="SCHEDULED",
            schedule="cron(0 2 * * ? *)",  # Daily at 2 AM UTC
            actions=[
                glue.CfnTrigger.ActionProperty(
                    job_name=self.glue_job.ref
                )
            ],
            description="Scheduled trigger for ETL pipeline"
        )
        
        glue_trigger.add_dependency(glue_workflow)
        glue_trigger.add_dependency(self.glue_job)
        
        return glue_workflow

    def _configure_s3_notifications(self) -> None:
        """Configure S3 event notifications to trigger Lambda."""
        self.data_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.lambda_function),
            s3.NotificationKeyFilter(
                prefix="raw-data/",
                suffix=".csv"
            )
        )

    def _create_log_groups(self, random_suffix: str) -> None:
        """Create CloudWatch log groups for monitoring."""
        # Log group for Glue jobs
        logs.LogGroup(
            self,
            "GlueJobLogGroup",
            log_group_name=f"/aws-glue/jobs/{self.glue_job.ref}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )
        
        # Log group for Lambda function (created automatically by Lambda service)
        # We just ensure it has proper retention
        logs.LogGroup(
            self,
            "LambdaLogGroup",
            log_group_name=f"/aws/lambda/{self.lambda_function.function_name}",
            retention=logs.RetentionDays.TWO_WEEKS,
            removal_policy=RemovalPolicy.DESTROY
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        CfnOutput(
            self,
            "S3BucketName",
            value=self.data_bucket.bucket_name,
            description="S3 bucket for ETL data storage",
            export_name=f"{self.stack_name}-S3Bucket"
        )
        
        CfnOutput(
            self,
            "GlueDatabaseName",
            value=self.glue_database.ref,
            description="Glue database for data catalog",
            export_name=f"{self.stack_name}-GlueDatabase"
        )
        
        CfnOutput(
            self,
            "GlueJobName",
            value=self.glue_job.ref,
            description="Glue ETL job name",
            export_name=f"{self.stack_name}-GlueJob"
        )
        
        CfnOutput(
            self,
            "LambdaFunctionName",
            value=self.lambda_function.function_name,
            description="Lambda function for ETL orchestration",
            export_name=f"{self.stack_name}-LambdaFunction"
        )
        
        CfnOutput(
            self,
            "GlueWorkflowName",
            value=self.glue_workflow.ref,
            description="Glue workflow for pipeline orchestration",
            export_name=f"{self.stack_name}-GlueWorkflow"
        )


def main():
    """Main function to create and deploy the CDK app."""
    app = App()
    
    # Get environment configuration
    env = Environment(
        account=app.node.try_get_context("account") or "123456789012",
        region=app.node.try_get_context("region") or "us-east-1"
    )
    
    # Create the stack
    ServerlessETLStack(
        app,
        "ServerlessETLStack",
        env=env,
        description="Serverless ETL Pipeline with AWS Glue and Lambda"
    )
    
    app.synth()


if __name__ == "__main__":
    main()