#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as athena from 'aws-cdk-lib/aws-athena';
import * as quicksight from 'aws-cdk-lib/aws-quicksight';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Duration, RemovalPolicy, CfnOutput } from 'aws-cdk-lib';

/**
 * Interface for stack configuration properties
 */
interface FinancialAnalyticsStackProps extends cdk.StackProps {
  readonly bucketNameSuffix?: string;
  readonly enableQuickSightAutoSetup?: boolean;
  readonly costDataRetentionDays?: number;
  readonly enableDetailedMonitoring?: boolean;
}

/**
 * Advanced Financial Analytics Dashboard Stack
 * 
 * This stack creates a comprehensive financial analytics platform using:
 * - Amazon QuickSight for interactive dashboards and business intelligence
 * - AWS Cost Explorer APIs for cost data collection
 * - Lambda functions for automated data processing and transformation
 * - S3 data lake for scalable storage
 * - Athena for ad-hoc SQL analytics
 * - Glue Data Catalog for metadata management
 * - EventBridge for automated scheduling
 */
class FinancialAnalyticsStack extends cdk.Stack {
  
  // Core infrastructure properties
  private readonly rawDataBucket: s3.Bucket;
  private readonly processedDataBucket: s3.Bucket;
  private readonly reportsBucket: s3.Bucket;
  private readonly analyticsBucket: s3.Bucket;
  
  // Lambda function references
  private readonly costDataCollectorFunction: lambda.Function;
  private readonly dataTransformerFunction: lambda.Function;
  private readonly reportGeneratorFunction: lambda.Function;
  
  // IAM roles and policies
  private readonly lambdaExecutionRole: iam.Role;
  
  // Analytics infrastructure
  private readonly glueDatabase: glue.CfnDatabase;
  private readonly athenaWorkGroup: athena.CfnWorkGroup;

  constructor(scope: Construct, id: string, props?: FinancialAnalyticsStackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const suffix = props?.bucketNameSuffix || 
      Math.random().toString(36).substring(2, 8);

    // Create foundational S3 buckets for data pipeline
    this.createDataStorageBuckets(suffix, props?.costDataRetentionDays);
    
    // Set up IAM roles and policies for secure service integration
    this.createIAMRoles();
    
    // Deploy Lambda functions for cost data processing
    this.createLambdaFunctions();
    
    // Configure automated scheduling with EventBridge
    this.createEventBridgeSchedules();
    
    // Set up analytics infrastructure (Glue, Athena)
    this.createAnalyticsInfrastructure();
    
    // Configure QuickSight integration
    if (props?.enableQuickSightAutoSetup !== false) {
      this.createQuickSightResources();
    }
    
    // Add monitoring and alerting
    if (props?.enableDetailedMonitoring) {
      this.createMonitoringResources();
    }
    
    // Generate stack outputs for external integration
    this.createStackOutputs();
  }

  /**
   * Creates S3 buckets for the data pipeline with lifecycle policies
   * and appropriate security configurations
   */
  private createDataStorageBuckets(suffix: string, retentionDays?: number): void {
    // Raw cost data bucket - stores unprocessed Cost Explorer API responses
    this.rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `cost-raw-data-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'RawDataLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90)
            },
            {
              storageClass: s3.StorageClass.DEEP_ARCHIVE,
              transitionAfter: Duration.days(365)
            }
          ],
          expiration: retentionDays ? Duration.days(retentionDays) : undefined
        }
      ],
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Processed data bucket - stores transformed analytics-ready data
    this.processedDataBucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `cost-processed-data-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'ProcessedDataLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(90)
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(180)
            }
          ]
        }
      ],
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Reports bucket - stores generated reports and dashboards
    this.reportsBucket = new s3.Bucket(this, 'ReportsBucket', {
      bucketName: `financial-reports-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Analytics bucket - stores Athena query results and working data
    this.analyticsBucket = new s3.Bucket(this, 'AnalyticsBucket', {
      bucketName: `financial-analytics-${suffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Add bucket notifications for data processing automation
    this.rawDataBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new targets.LambdaFunction(this.dataTransformerFunction),
      { prefix: 'raw-cost-data/' }
    );
  }

  /**
   * Creates IAM roles and policies for Lambda functions and service integration
   */
  private createIAMRoles(): void {
    // Comprehensive IAM role for Lambda functions with least privilege access
    this.lambdaExecutionRole = new iam.Role(this, 'FinancialAnalyticsLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for financial analytics Lambda functions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        'CostExplorerAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'ce:GetCostAndUsage',
                'ce:GetUsageReport',
                'ce:GetRightsizingRecommendation',
                'ce:GetReservationCoverage',
                'ce:GetReservationPurchaseRecommendation',
                'ce:GetReservationUtilization',
                'ce:GetSavingsPlansUtilization',
                'ce:GetDimensionValues',
                'ce:ListCostCategoryDefinitions'
              ],
              resources: ['*']
            })
          ]
        }),
        'OrganizationsAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'organizations:ListAccounts',
                'organizations:DescribeOrganization',
                'organizations:ListOrganizationalUnitsForParent',
                'organizations:ListParents'
              ],
              resources: ['*']
            })
          ]
        }),
        'S3DataAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket'
              ],
              resources: [
                this.rawDataBucket.bucketArn,
                `${this.rawDataBucket.bucketArn}/*`,
                this.processedDataBucket.bucketArn,
                `${this.processedDataBucket.bucketArn}/*`,
                this.reportsBucket.bucketArn,
                `${this.reportsBucket.bucketArn}/*`,
                this.analyticsBucket.bucketArn,
                `${this.analyticsBucket.bucketArn}/*`
              ]
            })
          ]
        }),
        'GlueAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:CreateTable',
                'glue:UpdateTable',
                'glue:GetTable',
                'glue:GetDatabase',
                'glue:CreateDatabase',
                'glue:CreatePartition',
                'glue:BatchCreatePartition',
                'glue:GetPartitions'
              ],
              resources: ['*']
            })
          ]
        }),
        'QuickSightAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'quicksight:CreateDataSet',
                'quicksight:UpdateDataSet',
                'quicksight:DescribeDataSet',
                'quicksight:CreateAnalysis',
                'quicksight:UpdateAnalysis',
                'quicksight:CreateDataSource',
                'quicksight:UpdateDataSource'
              ],
              resources: ['*']
            })
          ]
        })
      }
    });
  }

  /**
   * Creates Lambda functions for cost data collection, transformation, and reporting
   */
  private createLambdaFunctions(): void {
    // Cost Data Collector - interfaces with Cost Explorer APIs
    this.costDataCollectorFunction = new lambda.Function(this, 'CostDataCollector', {
      functionName: 'CostDataCollector',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'cost_data_collector.lambda_handler',
      timeout: Duration.minutes(15),
      memorySize: 1024,
      role: this.lambdaExecutionRole,
      environment: {
        RAW_DATA_BUCKET: this.rawDataBucket.bucketName,
        LOG_LEVEL: 'INFO'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime, timedelta, date
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Collects comprehensive cost data from AWS Cost Explorer APIs
    and stores raw data in S3 for downstream processing.
    """
    ce = boto3.client('ce')
    s3 = boto3.client('s3')
    
    # Calculate date ranges for data collection
    end_date = date.today()
    start_date = end_date - timedelta(days=90)  # Last 90 days
    
    try:
        # Collect comprehensive cost and usage data
        collections = {}
        
        # 1. Daily cost by service and account
        daily_cost_response = ce.get_cost_and_usage(
            TimePeriod={
                'Start': start_date.strftime('%Y-%m-%d'),
                'End': end_date.strftime('%Y-%m-%d')
            },
            Granularity='DAILY',
            Metrics=['BlendedCost', 'UnblendedCost', 'UsageQuantity'],
            GroupBy=[
                {'Type': 'DIMENSION', 'Key': 'SERVICE'},
                {'Type': 'DIMENSION', 'Key': 'LINKED_ACCOUNT'}
            ]
        )
        collections['daily_costs'] = daily_cost_response
        
        # 2. Monthly cost by department (tag-based)
        try:
            monthly_dept_response = ce.get_cost_and_usage(
                TimePeriod={
                    'Start': (start_date.replace(day=1)).strftime('%Y-%m-%d'),
                    'End': end_date.strftime('%Y-%m-%d')
                },
                Granularity='MONTHLY',
                Metrics=['BlendedCost'],
                GroupBy=[
                    {'Type': 'TAG', 'Key': 'Department'},
                    {'Type': 'TAG', 'Key': 'Project'},
                    {'Type': 'TAG', 'Key': 'Environment'}
                ]
            )
            collections['monthly_department_costs'] = monthly_dept_response
        except Exception as e:
            logger.warning(f"Could not collect tag-based costs: {e}")
        
        # 3. Reserved Instance utilization
        try:
            ri_utilization_response = ce.get_reservation_utilization(
                TimePeriod={
                    'Start': start_date.strftime('%Y-%m-%d'),
                    'End': end_date.strftime('%Y-%m-%d')
                },
                Granularity='MONTHLY'
            )
            collections['ri_utilization'] = ri_utilization_response
        except Exception as e:
            logger.warning(f"Could not collect RI utilization: {e}")
        
        # 4. Rightsizing recommendations
        try:
            rightsizing_response = ce.get_rightsizing_recommendation(
                Service='AmazonEC2'
            )
            collections['rightsizing_recommendations'] = rightsizing_response
        except Exception as e:
            logger.warning(f"Could not collect rightsizing recommendations: {e}")
        
        # Add collection metadata
        collections.update({
            'collection_timestamp': datetime.utcnow().isoformat(),
            'data_period': {
                'start_date': start_date.strftime('%Y-%m-%d'),
                'end_date': end_date.strftime('%Y-%m-%d')
            }
        })
        
        # Store in S3 with organized structure
        collection_id = str(uuid.uuid4())
        s3_key = f"raw-cost-data/{datetime.utcnow().strftime('%Y/%m/%d')}/cost-collection-{collection_id}.json"
        
        s3.put_object(
            Bucket=os.environ['RAW_DATA_BUCKET'],
            Key=s3_key,
            Body=json.dumps(collections, default=str, indent=2),
            ContentType='application/json',
            Metadata={
                'collection-date': datetime.utcnow().strftime('%Y-%m-%d'),
                'data-type': 'cost-explorer-raw',
                'collection-id': collection_id
            }
        )
        
        logger.info(f"Cost data collected and stored: s3://{os.environ['RAW_DATA_BUCKET']}/{s3_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Cost data collection completed successfully',
                'collection_id': collection_id,
                's3_location': f"s3://{os.environ['RAW_DATA_BUCKET']}/{s3_key}"
            })
        }
        
    except Exception as e:
        logger.error(f"Error collecting cost data: {str(e)}")
        raise
      `),
      logRetention: logs.RetentionDays.ONE_WEEK
    });

    // Data Transformer - processes raw data into analytics-ready formats
    this.dataTransformerFunction = new lambda.Function(this, 'DataTransformer', {
      functionName: 'DataTransformer',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'data_transformer.lambda_handler',
      timeout: Duration.minutes(15),
      memorySize: 2048,
      role: this.lambdaExecutionRole,
      environment: {
        RAW_DATA_BUCKET: this.rawDataBucket.bucketName,
        PROCESSED_DATA_BUCKET: this.processedDataBucket.bucketName,
        GLUE_DATABASE_NAME: 'financial_analytics'
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
import uuid

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Transforms raw cost data into analytics-ready formats
    and updates Glue Data Catalog for Athena queries.
    """
    s3 = boto3.client('s3')
    glue = boto3.client('glue')
    
    try:
        # Process S3 event or manual trigger
        if 'Records' in event:
            # Triggered by S3 event
            bucket = event['Records'][0]['s3']['bucket']['name']
            key = event['Records'][0]['s3']['object']['key']
        else:
            # Manual trigger - find latest file
            bucket = os.environ['RAW_DATA_BUCKET']
            response = s3.list_objects_v2(
                Bucket=bucket,
                Prefix='raw-cost-data/',
                MaxKeys=1000
            )
            
            if 'Contents' not in response:
                return {'statusCode': 200, 'body': 'No data to process'}
            
            # Get latest file
            latest_file = sorted(response['Contents'], key=lambda x: x['LastModified'], reverse=True)[0]
            key = latest_file['Key']
        
        logger.info(f"Processing file: s3://{bucket}/{key}")
        
        # Read and parse raw data
        obj = s3.get_object(Bucket=bucket, Key=key)
        raw_data = json.loads(obj['Body'].read())
        
        # Transform data into structured format
        transformed_data = transform_cost_data(raw_data)
        
        # Store transformed data
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        processed_bucket = os.environ['PROCESSED_DATA_BUCKET']
        
        for data_type, data in transformed_data.items():
            if data:  # Only process non-empty datasets
                json_key = f"processed-data/{data_type}/{datetime.utcnow().strftime('%Y/%m/%d')}/{data_type}_{timestamp}.json"
                
                s3.put_object(
                    Bucket=processed_bucket,
                    Key=json_key,
                    Body=json.dumps(data, default=str, indent=2),
                    ContentType='application/json'
                )
                
                logger.info(f"Stored transformed data: s3://{processed_bucket}/{json_key}")
        
        # Update Glue Data Catalog
        create_glue_tables(glue, processed_bucket)
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Data transformation completed successfully',
                'processed_files': list(transformed_data.keys()),
                'output_bucket': processed_bucket
            })
        }
        
    except Exception as e:
        logger.error(f"Error in data transformation: {str(e)}")
        raise

def transform_cost_data(raw_data):
    """Transform raw cost data into analytics-friendly structures"""
    transformed = {}
    
    # Transform daily costs
    if 'daily_costs' in raw_data:
        daily_costs = []
        for time_period in raw_data['daily_costs'].get('ResultsByTime', []):
            date = time_period['TimePeriod']['Start']
            
            for group in time_period.get('Groups', []):
                service = group['Keys'][0] if len(group['Keys']) > 0 else 'Unknown'
                account = group['Keys'][1] if len(group['Keys']) > 1 else 'Unknown'
                
                daily_costs.append({
                    'date': date,
                    'service': service,
                    'account_id': account,
                    'blended_cost': float(group['Metrics']['BlendedCost']['Amount']),
                    'unblended_cost': float(group['Metrics']['UnblendedCost']['Amount']),
                    'usage_quantity': float(group['Metrics']['UsageQuantity']['Amount']),
                    'currency': group['Metrics']['BlendedCost']['Unit']
                })
        
        transformed['daily_costs'] = daily_costs
    
    # Transform department costs if available
    if 'monthly_department_costs' in raw_data:
        dept_costs = []
        for time_period in raw_data['monthly_department_costs'].get('ResultsByTime', []):
            start_date = time_period['TimePeriod']['Start']
            
            for group in time_period.get('Groups', []):
                keys = group.get('Keys', [])
                department = keys[0] if len(keys) > 0 else 'Untagged'
                project = keys[1] if len(keys) > 1 else 'Untagged'
                environment = keys[2] if len(keys) > 2 else 'Untagged'
                
                dept_costs.append({
                    'month': start_date,
                    'department': department,
                    'project': project,
                    'environment': environment,
                    'cost': float(group['Metrics']['BlendedCost']['Amount']),
                    'currency': group['Metrics']['BlendedCost']['Unit']
                })
        
        transformed['department_costs'] = dept_costs
    
    return transformed

def create_glue_tables(glue_client, bucket):
    """Create or update Glue tables for analytics"""
    database_name = 'financial_analytics'
    
    # Create database if needed
    try:
        glue_client.create_database(
            DatabaseInput={
                'Name': database_name,
                'Description': 'Financial analytics database for cost data'
            }
        )
        logger.info(f"Created Glue database: {database_name}")
    except glue_client.exceptions.AlreadyExistsException:
        logger.info(f"Glue database already exists: {database_name}")
      `),
      logRetention: logs.RetentionDays.ONE_WEEK
    });

    // Report Generator - creates automated reports and summaries
    this.reportGeneratorFunction = new lambda.Function(this, 'ReportGenerator', {
      functionName: 'ReportGenerator',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'report_generator.lambda_handler',
      timeout: Duration.minutes(10),
      memorySize: 1024,
      role: this.lambdaExecutionRole,
      environment: {
        PROCESSED_DATA_BUCKET: this.processedDataBucket.bucketName,
        REPORTS_BUCKET: this.reportsBucket.bucketName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    """
    Generates automated financial reports and executive summaries
    based on processed cost data.
    """
    s3 = boto3.client('s3')
    
    try:
        # Generate different types of reports
        reports = {
            'executive_summary': generate_executive_summary(s3),
            'department_breakdown': generate_department_breakdown(s3),
            'cost_optimization': generate_optimization_report(s3)
        }
        
        # Store reports in S3
        timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
        
        for report_type, report_data in reports.items():
            if report_data:
                report_key = f"reports/{report_type}/{datetime.utcnow().strftime('%Y/%m')}/{report_type}_{timestamp}.json"
                
                s3.put_object(
                    Bucket=os.environ['REPORTS_BUCKET'],
                    Key=report_key,
                    Body=json.dumps(report_data, default=str, indent=2),
                    ContentType='application/json'
                )
                
                logger.info(f"Generated report: s3://{os.environ['REPORTS_BUCKET']}/{report_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Reports generated successfully',
                'reports': list(reports.keys())
            })
        }
        
    except Exception as e:
        logger.error(f"Error generating reports: {str(e)}")
        raise

def generate_executive_summary(s3_client):
    """Generate high-level executive summary"""
    # Implementation would analyze processed data and create summary
    return {
        'report_type': 'executive_summary',
        'generation_time': datetime.utcnow().isoformat(),
        'summary': 'Executive cost summary would be generated here'
    }

def generate_department_breakdown(s3_client):
    """Generate department-level cost breakdown"""
    return {
        'report_type': 'department_breakdown',
        'generation_time': datetime.utcnow().isoformat(),
        'breakdown': 'Department cost breakdown would be generated here'
    }

def generate_optimization_report(s3_client):
    """Generate cost optimization recommendations"""
    return {
        'report_type': 'cost_optimization',
        'generation_time': datetime.utcnow().isoformat(),
        'recommendations': 'Cost optimization recommendations would be generated here'
    }
      `),
      logRetention: logs.RetentionDays.ONE_WEEK
    });
  }

  /**
   * Creates EventBridge rules for automated data collection and processing
   */
  private createEventBridgeSchedules(): void {
    // Daily cost data collection schedule
    const dailyCollectionRule = new events.Rule(this, 'DailyCostDataCollection', {
      ruleName: 'DailyCostDataCollection',
      description: 'Daily collection of cost data for analytics',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '6',  // 6 AM UTC daily
        day: '*',
        month: '*',
        year: '*'
      }),
      enabled: true
    });

    dailyCollectionRule.addTarget(new targets.LambdaFunction(this.costDataCollectorFunction, {
      event: events.RuleTargetInput.fromObject({
        source: 'scheduled-daily',
        trigger_time: events.EventField.fromPath('$.time')
      })
    }));

    // Weekly data transformation and report generation
    const weeklyProcessingRule = new events.Rule(this, 'WeeklyDataProcessing', {
      ruleName: 'WeeklyDataProcessing',
      description: 'Weekly transformation and report generation',
      schedule: events.Schedule.cron({
        minute: '0',
        hour: '7',  // 7 AM UTC on Sundays
        day: '?',
        month: '*',
        year: '*',
        weekDay: 'SUN'
      }),
      enabled: true
    });

    weeklyProcessingRule.addTarget(new targets.LambdaFunction(this.dataTransformerFunction, {
      event: events.RuleTargetInput.fromObject({
        source: 'scheduled-weekly',
        trigger_time: events.EventField.fromPath('$.time')
      })
    }));

    weeklyProcessingRule.addTarget(new targets.LambdaFunction(this.reportGeneratorFunction, {
      event: events.RuleTargetInput.fromObject({
        source: 'scheduled-weekly',
        trigger_time: events.EventField.fromPath('$.time')
      })
    }));
  }

  /**
   * Creates analytics infrastructure including Glue Data Catalog and Athena
   */
  private createAnalyticsInfrastructure(): void {
    // Glue Database for cost analytics
    this.glueDatabase = new glue.CfnDatabase(this, 'FinancialAnalyticsDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: 'financial_analytics',
        description: 'Database for financial analytics and cost optimization data'
      }
    });

    // Athena WorkGroup for financial analytics queries
    this.athenaWorkGroup = new athena.CfnWorkGroup(this, 'FinancialAnalyticsWorkGroup', {
      name: 'FinancialAnalytics',
      description: 'Workgroup for financial analytics and cost optimization queries',
      workGroupConfiguration: {
        resultConfiguration: {
          outputLocation: `s3://${this.analyticsBucket.bucketName}/athena-results/`
        },
        enforceWorkGroupConfiguration: true,
        publishCloudWatchMetrics: true
      }
    });

    // Create sample Glue tables for common cost analysis patterns
    new glue.CfnTable(this, 'DailyCostsTable', {
      catalogId: this.account,
      databaseName: this.glueDatabase.ref,
      tableInput: {
        name: 'daily_costs',
        description: 'Daily cost data by service and account',
        tableType: 'EXTERNAL_TABLE',
        storageDescriptor: {
          location: `s3://${this.processedDataBucket.bucketName}/processed-data/daily_costs/`,
          inputFormat: 'org.apache.hadoop.mapred.TextInputFormat',
          outputFormat: 'org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat',
          serdeInfo: {
            serializationLibrary: 'org.openx.data.jsonserde.JsonSerDe'
          },
          columns: [
            { name: 'date', type: 'string' },
            { name: 'service', type: 'string' },
            { name: 'account_id', type: 'string' },
            { name: 'blended_cost', type: 'double' },
            { name: 'unblended_cost', type: 'double' },
            { name: 'usage_quantity', type: 'double' },
            { name: 'currency', type: 'string' }
          ]
        }
      }
    });
  }

  /**
   * Creates QuickSight resources for business intelligence dashboards
   */
  private createQuickSightResources(): void {
    // Note: QuickSight resources often require manual setup due to user management
    // This creates the foundation that can be extended through the console
    
    // QuickSight service role for S3 access
    const quickSightRole = new iam.Role(this, 'QuickSightServiceRole', {
      assumedBy: new iam.ServicePrincipal('quicksight.amazonaws.com'),
      description: 'Service role for QuickSight to access financial analytics data',
      inlinePolicies: {
        'S3DataAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:ListBucket'],
              resources: [
                this.processedDataBucket.bucketArn,
                `${this.processedDataBucket.bucketArn}/*`
              ]
            })
          ]
        }),
        'AthenaAccess': new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'athena:GetQueryExecution',
                'athena:GetQueryResults',
                'athena:StartQueryExecution',
                'athena:GetWorkGroup'
              ],
              resources: [this.athenaWorkGroup.attrArn]
            })
          ]
        })
      }
    });

    // Output QuickSight setup instructions
    new CfnOutput(this, 'QuickSightSetupInstructions', {
      description: 'Instructions for completing QuickSight setup',
      value: `
        1. Navigate to QuickSight console: https://quicksight.aws.amazon.com/
        2. Sign up for QuickSight Enterprise Edition
        3. Grant permissions to S3 bucket: ${this.processedDataBucket.bucketName}
        4. Create data sources pointing to Athena WorkGroup: ${this.athenaWorkGroup.name}
        5. Use IAM role: ${quickSightRole.roleArn}
      `.trim()
    });
  }

  /**
   * Creates monitoring and alerting resources for the financial analytics pipeline
   */
  private createMonitoringResources(): void {
    // CloudWatch Log Groups for centralized logging
    const logGroup = new logs.LogGroup(this, 'FinancialAnalyticsLogGroup', {
      logGroupName: '/aws/financial-analytics',
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Custom metrics and alarms would be added here for production monitoring
    // Examples: Lambda function errors, data processing failures, cost anomalies
  }

  /**
   * Creates stack outputs for integration with external systems
   */
  private createStackOutputs(): void {
    new CfnOutput(this, 'RawDataBucketName', {
      description: 'Name of the S3 bucket storing raw cost data',
      value: this.rawDataBucket.bucketName,
      exportName: `${this.stackName}-RawDataBucket`
    });

    new CfnOutput(this, 'ProcessedDataBucketName', {
      description: 'Name of the S3 bucket storing processed analytics data',
      value: this.processedDataBucket.bucketName,
      exportName: `${this.stackName}-ProcessedDataBucket`
    });

    new CfnOutput(this, 'ReportsBucketName', {
      description: 'Name of the S3 bucket storing generated reports',
      value: this.reportsBucket.bucketName,
      exportName: `${this.stackName}-ReportsBucket`
    });

    new CfnOutput(this, 'AnalyticsBucketName', {
      description: 'Name of the S3 bucket for Athena query results',
      value: this.analyticsBucket.bucketName,
      exportName: `${this.stackName}-AnalyticsBucket`
    });

    new CfnOutput(this, 'AthenaWorkGroupName', {
      description: 'Name of the Athena WorkGroup for financial analytics',
      value: this.athenaWorkGroup.name!,
      exportName: `${this.stackName}-AthenaWorkGroup`
    });

    new CfnOutput(this, 'GlueDatabaseName', {
      description: 'Name of the Glue database for cost analytics',
      value: this.glueDatabase.ref,
      exportName: `${this.stackName}-GlueDatabase`
    });

    new CfnOutput(this, 'CostDataCollectorFunctionName', {
      description: 'Name of the Lambda function for cost data collection',
      value: this.costDataCollectorFunction.functionName,
      exportName: `${this.stackName}-CostDataCollector`
    });

    new CfnOutput(this, 'DataTransformerFunctionName', {
      description: 'Name of the Lambda function for data transformation',
      value: this.dataTransformerFunction.functionName,
      exportName: `${this.stackName}-DataTransformer`
    });
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Deploy the financial analytics stack with configurable properties
new FinancialAnalyticsStack(app, 'FinancialAnalyticsStack', {
  description: 'Advanced Financial Analytics Dashboard with QuickSight and Cost Explorer',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION
  },
  
  // Stack configuration
  bucketNameSuffix: process.env.BUCKET_SUFFIX,
  enableQuickSightAutoSetup: process.env.ENABLE_QUICKSIGHT !== 'false',
  costDataRetentionDays: process.env.COST_DATA_RETENTION_DAYS ? 
    parseInt(process.env.COST_DATA_RETENTION_DAYS) : undefined,
  enableDetailedMonitoring: process.env.ENABLE_MONITORING === 'true',
  
  // Resource tagging for cost allocation and governance
  tags: {
    'Project': 'FinancialAnalytics',
    'Environment': process.env.ENVIRONMENT || 'development',
    'Owner': 'FinanceTeam',
    'CostCenter': 'Analytics',
    'CreatedBy': 'CDK'
  }
});

// Synthesize the CloudFormation templates
app.synth();