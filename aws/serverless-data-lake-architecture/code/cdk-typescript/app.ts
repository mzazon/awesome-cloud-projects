#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as glue from 'aws-cdk-lib/aws-glue';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as path from 'path';

/**
 * Props for the Advanced Serverless Data Lake Stack
 */
export interface AdvancedServerlessDataLakeProps extends cdk.StackProps {
  /**
   * Project name for resource naming
   * @default 'advanced-serverless-datalake'
   */
  readonly projectName?: string;
  
  /**
   * Environment suffix for unique resource names
   * @default Random 6 character string
   */
  readonly environmentSuffix?: string;
  
  /**
   * Enable detailed monitoring and tracing
   * @default true
   */
  readonly enableMonitoring?: boolean;
  
  /**
   * Enable automatic scaling configurations
   * @default true
   */
  readonly enableAutoScaling?: boolean;
}

/**
 * Advanced Serverless Data Lake Architecture Stack
 * 
 * This stack implements a comprehensive serverless data lake solution using:
 * - Lambda Layers for shared code and dependencies
 * - EventBridge for event-driven orchestration
 * - AWS Glue for ETL processing and catalog management
 * - S3 for data storage with intelligent tiering
 * - DynamoDB for metadata storage
 * - CloudWatch for monitoring and alerting
 */
export class AdvancedServerlessDataLakeStack extends cdk.Stack {
  
  // Core storage resources
  public readonly rawDataBucket: s3.Bucket;
  public readonly processedDataBucket: s3.Bucket;
  public readonly quarantineDataBucket: s3.Bucket;
  public readonly metadataTable: dynamodb.Table;
  
  // Event orchestration
  public readonly customEventBus: events.EventBus;
  public readonly dataIngestionRule: events.Rule;
  public readonly dataValidationRule: events.Rule;
  public readonly dataQualityRule: events.Rule;
  
  // Lambda layer and functions
  public readonly sharedLayer: lambda.LayerVersion;
  public readonly dataIngestionFunction: lambda.Function;
  public readonly dataValidationFunction: lambda.Function;
  public readonly qualityMonitoringFunction: lambda.Function;
  
  // Glue components
  public readonly glueDatabase: glue.CfnDatabase;
  public readonly glueCrawler: glue.CfnCrawler;
  public readonly glueRole: iam.Role;
  
  // IAM roles
  public readonly lambdaExecutionRole: iam.Role;
  
  constructor(scope: Construct, id: string, props?: AdvancedServerlessDataLakeProps) {
    super(scope, id, props);
    
    // Extract configuration from props
    const projectName = props?.projectName || 'advanced-serverless-datalake';
    const environmentSuffix = props?.environmentSuffix || this.generateRandomSuffix();
    const enableMonitoring = props?.enableMonitoring ?? true;
    const enableAutoScaling = props?.enableAutoScaling ?? true;
    
    // Resource naming convention
    const resourcePrefix = `${projectName}-${environmentSuffix}`;
    
    // Create storage infrastructure
    this.createStorageInfrastructure(resourcePrefix);
    
    // Create IAM roles
    this.createIamRoles(resourcePrefix);
    
    // Create Lambda layer with shared utilities
    this.createLambdaLayer(resourcePrefix);
    
    // Create event orchestration infrastructure
    this.createEventInfrastructure(resourcePrefix);
    
    // Create Lambda functions
    this.createLambdaFunctions(resourcePrefix);
    
    // Create Glue components
    this.createGlueInfrastructure(resourcePrefix);
    
    // Configure event-driven integrations
    this.configureEventIntegrations();
    
    // Setup monitoring if enabled
    if (enableMonitoring) {
      this.setupMonitoring(resourcePrefix);
    }
    
    // Output important resource information
    this.createOutputs();
  }
  
  /**
   * Creates S3 buckets and DynamoDB table for data storage
   */
  private createStorageInfrastructure(resourcePrefix: string): void {
    // Raw data bucket with lifecycle policies
    this.rawDataBucket = new s3.Bucket(this, 'RawDataBucket', {
      bucketName: `${resourcePrefix}-raw-data`,
      versioned: true,
      lifecycleRules: [
        {
          id: 'IntelligentTieringRule',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INTELLIGENT_TIERING,
              transitionAfter: cdk.Duration.days(1),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      eventBridgeEnabled: true,
    });
    
    // Processed data bucket with optimized storage
    this.processedDataBucket = new s3.Bucket(this, 'ProcessedDataBucket', {
      bucketName: `${resourcePrefix}-processed-data`,
      versioned: true,
      lifecycleRules: [
        {
          id: 'ProcessedDataLifecycle',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.STANDARD_INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(365),
            },
          ],
        },
      ],
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    });
    
    // Quarantine bucket for failed data
    this.quarantineDataBucket = new s3.Bucket(this, 'QuarantineDataBucket', {
      bucketName: `${resourcePrefix}-quarantine-data`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    });
    
    // DynamoDB table for metadata storage
    this.metadataTable = new dynamodb.Table(this, 'MetadataTable', {
      tableName: `${resourcePrefix}-metadata`,
      partitionKey: {
        name: 'ProcessId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      stream: dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
    });
    
    // Add tags to storage resources
    cdk.Tags.of(this.rawDataBucket).add('Component', 'DataLake-Storage');
    cdk.Tags.of(this.processedDataBucket).add('Component', 'DataLake-Storage');
    cdk.Tags.of(this.quarantineDataBucket).add('Component', 'DataLake-Storage');
    cdk.Tags.of(this.metadataTable).add('Component', 'DataLake-Metadata');
  }
  
  /**
   * Creates IAM roles for Lambda and Glue services
   */
  private createIamRoles(resourcePrefix: string): void {
    // Lambda execution role with comprehensive permissions
    this.lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AWSXRayDaemonWriteAccess'),
      ],
      inlinePolicies: {
        DataLakePolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for all data lake buckets
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:ListBucket',
                's3:GetObjectVersion',
              ],
              resources: [
                this.rawDataBucket.bucketArn,
                `${this.rawDataBucket.bucketArn}/*`,
                this.processedDataBucket.bucketArn,
                `${this.processedDataBucket.bucketArn}/*`,
                this.quarantineDataBucket.bucketArn,
                `${this.quarantineDataBucket.bucketArn}/*`,
              ],
            }),
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Query',
                'dynamodb:Scan',
                'dynamodb:DeleteItem',
              ],
              resources: [this.metadataTable.tableArn],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents',
                'logs:DescribeLogGroups',
                'logs:DescribeLogStreams',
              ],
              resources: [`arn:aws:logs:${this.region}:${this.account}:*`],
            }),
            // CloudWatch Metrics permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'cloudwatch:PutMetricData',
                'cloudwatch:GetMetricStatistics',
                'cloudwatch:ListMetrics',
              ],
              resources: ['*'],
            }),
            // Glue permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'glue:StartJobRun',
                'glue:GetJobRun',
                'glue:StartWorkflowRun',
                'glue:GetWorkflowRun',
                'glue:StartCrawler',
                'glue:GetCrawler',
              ],
              resources: ['*'],
            }),
          ],
        }),
      },
    });
    
    // Glue service role
    this.glueRole = new iam.Role(this, 'GlueServiceRole', {
      roleName: `${resourcePrefix}-glue-role`,
      assumedBy: new iam.ServicePrincipal('glue.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSGlueServiceRole'),
      ],
      inlinePolicies: {
        GlueS3Policy: new iam.PolicyDocument({
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
                this.processedDataBucket.bucketArn,
                `${this.processedDataBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });
  }
  
  /**
   * Creates Lambda layer with shared utilities and dependencies
   */
  private createLambdaLayer(resourcePrefix: string): void {
    this.sharedLayer = new lambda.LayerVersion(this, 'SharedLayer', {
      layerVersionName: `${resourcePrefix}-shared-layer`,
      description: 'Shared utilities and dependencies for data lake processing',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import hashlib
from datetime import datetime
from typing import Dict, Any, List, Optional

class DataProcessor:
    def __init__(self):
        self.s3_client = boto3.client('s3')
        self.dynamodb = boto3.resource('dynamodb')
        self.events_client = boto3.client('events')

    def generate_process_id(self, source: str, timestamp: str) -> str:
        """Generate unique process ID"""
        data = f"{source}-{timestamp}-{uuid.uuid4()}"
        return hashlib.md5(data.encode()).hexdigest()

    def validate_json_structure(self, data: Dict[str, Any], 
                              required_fields: List[str]) -> bool:
        """Validate JSON data structure"""
        return all(field in data for field in required_fields)

    def calculate_data_quality_score(self, data: Dict[str, Any]) -> float:
        """Calculate data quality score based on completeness"""
        total_fields = len(data)
        non_null_fields = sum(1 for v in data.values() if v is not None and v != "")
        return (non_null_fields / total_fields) * 100 if total_fields > 0 else 0

    def publish_custom_event(self, event_bus: str, source: str, 
                           detail_type: str, detail: Dict[str, Any]):
        """Publish custom event to EventBridge"""
        self.events_client.put_events(
            Entries=[
                {
                    'Source': source,
                    'DetailType': detail_type,
                    'Detail': json.dumps(detail),
                    'EventBusName': event_bus
                }
            ]
        )

    def store_metadata(self, table_name: str, process_id: str, metadata: Dict[str, Any]):
        """Store processing metadata in DynamoDB"""
        table = self.dynamodb.Table(table_name)
        item = {
            'ProcessId': process_id,
            'Timestamp': datetime.utcnow().isoformat(),
            **metadata
        }
        table.put_item(Item=item)

class DataValidator:
    @staticmethod
    def is_valid_email(email: str) -> bool:
        import re
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None

    @staticmethod
    def is_valid_phone(phone: str) -> bool:
        import re
        pattern = r'^\\+?1?[2-9]\\d{2}[2-9]\\d{2}\\d{4}$'
        return re.match(pattern, phone.replace('-', '').replace(' ', '')) is not None

    @staticmethod
    def is_valid_date_format(date_str: str, format: str = '%Y-%m-%d') -> bool:
        try:
            datetime.strptime(date_str, format)
            return True
        except ValueError:
            return False
      `),
      compatibleRuntimes: [
        lambda.Runtime.PYTHON_3_9,
        lambda.Runtime.PYTHON_3_10,
        lambda.Runtime.PYTHON_3_11,
      ],
      compatibleArchitectures: [lambda.Architecture.X86_64, lambda.Architecture.ARM_64],
    });
  }
  
  /**
   * Creates EventBridge custom bus and rules for event orchestration
   */
  private createEventInfrastructure(resourcePrefix: string): void {
    // Custom EventBridge bus for data lake events
    this.customEventBus = new events.EventBus(this, 'CustomEventBus', {
      eventBusName: `${resourcePrefix}-event-bus`,
      description: 'Custom event bus for data lake processing orchestration',
    });
    
    // Event rule for data ingestion events
    this.dataIngestionRule = new events.Rule(this, 'DataIngestionRule', {
      ruleName: `${resourcePrefix}-data-ingestion-rule`,
      eventBus: this.customEventBus,
      eventPattern: {
        source: ['datalake.ingestion'],
        detailType: ['Data Received'],
      },
      description: 'Routes data ingestion events to validation functions',
    });
    
    // Event rule for data validation events
    this.dataValidationRule = new events.Rule(this, 'DataValidationRule', {
      ruleName: `${resourcePrefix}-data-validation-rule`,
      eventBus: this.customEventBus,
      eventPattern: {
        source: ['datalake.validation'],
        detailType: ['Data Validated'],
      },
      description: 'Routes data validation events to quality monitoring',
    });
    
    // Event rule for data quality events
    this.dataQualityRule = new events.Rule(this, 'DataQualityRule', {
      ruleName: `${resourcePrefix}-data-quality-rule`,
      eventBus: this.customEventBus,
      eventPattern: {
        source: ['datalake.quality'],
        detailType: ['Quality Check Complete'],
      },
      description: 'Routes quality check events to downstream processes',
    });
  }
  
  /**
   * Creates Lambda functions for data processing pipeline
   */
  private createLambdaFunctions(resourcePrefix: string): void {
    // Environment variables common to all functions
    const commonEnvironment = {
      METADATA_TABLE: this.metadataTable.tableName,
      CUSTOM_EVENT_BUS: this.customEventBus.eventBusName,
      PROCESSED_BUCKET: this.processedDataBucket.bucketName,
      QUARANTINE_BUCKET: this.quarantineDataBucket.bucketName,
      PROJECT_NAME: resourcePrefix,
    };
    
    // Data ingestion Lambda function
    this.dataIngestionFunction = new lambda.Function(this, 'DataIngestionFunction', {
      functionName: `${resourcePrefix}-data-ingestion`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime
from data_utils import DataProcessor

def lambda_handler(event, context):
    processor = DataProcessor()
    
    # Extract event information
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = event['Records'][0]['s3']['object']['key']
    
    # Generate process ID
    process_id = processor.generate_process_id(bucket, datetime.utcnow().isoformat())
    
    try:
        # Download and process the file
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        # Determine file type and process accordingly
        if key.endswith('.json'):
            data = json.loads(file_content)
            data_type = 'json'
        elif key.endswith('.csv'):
            data = {'raw_content': file_content, 'type': 'csv'}
            data_type = 'csv'
        else:
            data = {'raw_content': file_content, 'type': 'unknown'}
            data_type = 'unknown'
        
        # Store metadata
        metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'FileSize': len(file_content),
            'DataType': data_type,
            'Status': 'ingested',
            'ProcessingStage': 'ingestion'
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish ingestion event
        event_detail = {
            'processId': process_id,
            'bucket': bucket,
            'key': key,
            'dataType': data_type,
            'fileSize': len(file_content)
        }
        
        processor.publish_custom_event(
            event_bus=os.environ['CUSTOM_EVENT_BUS'],
            source='datalake.ingestion',
            detail_type='Data Received',
            detail=event_detail
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'processId': process_id,
                'message': 'Data ingested successfully'
            })
        }
        
    except Exception as e:
        print(f"Error processing file: {str(e)}")
        
        # Store error metadata
        error_metadata = {
            'SourceBucket': bucket,
            'SourceKey': key,
            'Status': 'failed',
            'ProcessingStage': 'ingestion',
            'ErrorMessage': str(e)
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=error_metadata
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      handler: 'index.lambda_handler',
      role: this.lambdaExecutionRole,
      layers: [this.sharedLayer],
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: commonEnvironment,
      tracing: lambda.Tracing.ACTIVE,
      description: 'Processes incoming data files and initiates validation workflow',
    });
    
    // Data validation Lambda function
    this.dataValidationFunction = new lambda.Function(this, 'DataValidationFunction', {
      functionName: `${resourcePrefix}-data-validation`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from data_utils import DataProcessor, DataValidator

def lambda_handler(event, context):
    processor = DataProcessor()
    validator = DataValidator()
    
    # Parse EventBridge event
    detail = event['detail']
    process_id = detail['processId']
    bucket = detail['bucket']
    key = detail['key']
    data_type = detail['dataType']
    
    try:
        # Download the file for validation
        s3_response = processor.s3_client.get_object(Bucket=bucket, Key=key)
        file_content = s3_response['Body'].read().decode('utf-8')
        
        validation_results = {
            'processId': process_id,
            'validationPassed': True,
            'validationErrors': [],
            'qualityScore': 0
        }
        
        if data_type == 'json':
            try:
                data = json.loads(file_content)
                
                # Validate required fields (example schema)
                required_fields = ['id', 'timestamp', 'data']
                if not processor.validate_json_structure(data, required_fields):
                    validation_results['validationPassed'] = False
                    validation_results['validationErrors'].append('Missing required fields')
                
                # Calculate quality score
                validation_results['qualityScore'] = processor.calculate_data_quality_score(data)
                
                # Additional field validations
                if 'email' in data and not validator.is_valid_email(data['email']):
                    validation_results['validationErrors'].append('Invalid email format')
                
                if 'phone' in data and not validator.is_valid_phone(data['phone']):
                    validation_results['validationErrors'].append('Invalid phone format')
                
            except json.JSONDecodeError:
                validation_results['validationPassed'] = False
                validation_results['validationErrors'].append('Invalid JSON format')
        
        elif data_type == 'csv':
            # Basic CSV validation
            lines = file_content.strip().split('\\n')
            if len(lines) < 2:  # Header + at least one data row
                validation_results['validationPassed'] = False
                validation_results['validationErrors'].append('CSV file must have header and data rows')
            else:
                validation_results['qualityScore'] = 85.0  # Default score for valid CSV
        
        # Determine destination based on validation
        if validation_results['validationPassed'] and validation_results['qualityScore'] >= 70:
            destination_bucket = os.environ['PROCESSED_BUCKET']
            destination_prefix = 'validated/'
            status = 'validated'
        else:
            destination_bucket = os.environ['QUARANTINE_BUCKET']
            destination_prefix = 'quarantine/'
            status = 'quarantined'
        
        # Copy file to appropriate destination
        destination_key = f"{destination_prefix}{key}"
        processor.s3_client.copy_object(
            CopySource={'Bucket': bucket, 'Key': key},
            Bucket=destination_bucket,
            Key=destination_key
        )
        
        # Update metadata
        metadata = {
            'Status': status,
            'ProcessingStage': 'validation',
            'ValidationPassed': validation_results['validationPassed'],
            'QualityScore': validation_results['qualityScore'],
            'ValidationErrors': validation_results['validationErrors'],
            'DestinationBucket': destination_bucket,
            'DestinationKey': destination_key
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=process_id,
            metadata=metadata
        )
        
        # Publish validation event
        processor.publish_custom_event(
            event_bus=os.environ['CUSTOM_EVENT_BUS'],
            source='datalake.validation',
            detail_type='Data Validated',
            detail=validation_results
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps(validation_results)
        }
        
    except Exception as e:
        print(f"Error validating data: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      handler: 'index.lambda_handler',
      role: this.lambdaExecutionRole,
      layers: [this.sharedLayer],
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: commonEnvironment,
      tracing: lambda.Tracing.ACTIVE,
      description: 'Validates data quality and routes to appropriate storage location',
    });
    
    // Quality monitoring Lambda function
    this.qualityMonitoringFunction = new lambda.Function(this, 'QualityMonitoringFunction', {
      functionName: `${resourcePrefix}-quality-monitoring`,
      runtime: lambda.Runtime.PYTHON_3_9,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from data_utils import DataProcessor
from datetime import datetime, timedelta

def lambda_handler(event, context):
    processor = DataProcessor()
    cloudwatch = boto3.client('cloudwatch')
    
    # Parse EventBridge event
    detail = event['detail']
    process_id = detail['processId']
    quality_score = detail.get('qualityScore', 0)
    validation_passed = detail.get('validationPassed', False)
    
    try:
        # Calculate quality metrics over time
        end_time = datetime.utcnow()
        start_time = end_time - timedelta(hours=1)
        
        # Query recent processing metadata
        dynamodb = boto3.resource('dynamodb')
        table = dynamodb.Table(os.environ['METADATA_TABLE'])
        
        # Scan for recent records (in production, use GSI for better performance)
        response = table.scan(
            FilterExpression='ProcessingStage = :stage',
            ExpressionAttributeValues={':stage': 'validation'}
        )
        
        # Calculate aggregate metrics
        total_records = len(response['Items'])
        passed_records = sum(1 for item in response['Items'] 
                           if item.get('ValidationPassed', False))
        avg_quality_score = sum(float(item.get('QualityScore', 0)) 
                              for item in response['Items']) / max(total_records, 1)
        
        # Publish CloudWatch metrics
        cloudwatch.put_metric_data(
            Namespace='DataLake/Quality',
            MetricData=[
                {
                    'MetricName': 'ValidationSuccessRate',
                    'Value': (passed_records / max(total_records, 1)) * 100,
                    'Unit': 'Percent',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'AverageQualityScore',
                    'Value': avg_quality_score,
                    'Unit': 'None',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                },
                {
                    'MetricName': 'ProcessedRecords',
                    'Value': total_records,
                    'Unit': 'Count',
                    'Dimensions': [
                        {
                            'Name': 'Pipeline',
                            'Value': os.environ.get('PROJECT_NAME', 'unknown')
                        }
                    ]
                }
            ]
        )
        
        # Store aggregated quality metadata
        quality_metadata = {
            'TotalRecords': total_records,
            'PassedRecords': passed_records,
            'SuccessRate': (passed_records / max(total_records, 1)) * 100,
            'AverageQualityScore': avg_quality_score,
            'ProcessingStage': 'quality_monitoring'
        }
        
        processor.store_metadata(
            table_name=os.environ['METADATA_TABLE'],
            process_id=f"quality-{datetime.utcnow().isoformat()}",
            metadata=quality_metadata
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Quality metrics updated',
                'metrics': quality_metadata
            })
        }
        
    except Exception as e:
        print(f"Error monitoring quality: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `),
      handler: 'index.lambda_handler',
      role: this.lambdaExecutionRole,
      layers: [this.sharedLayer],
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      environment: commonEnvironment,
      tracing: lambda.Tracing.ACTIVE,
      description: 'Monitors data quality metrics and publishes to CloudWatch',
    });
    
    // Grant EventBridge permission to publish events
    this.customEventBus.grantPutEventsTo(this.lambdaExecutionRole);
  }
  
  /**
   * Creates AWS Glue components for ETL processing and catalog management
   */
  private createGlueInfrastructure(resourcePrefix: string): void {
    // Glue database for data catalog
    this.glueDatabase = new glue.CfnDatabase(this, 'GlueDatabase', {
      catalogId: this.account,
      databaseInput: {
        name: `${resourcePrefix.replace(/-/g, '_')}_catalog`,
        description: 'Data lake catalog database for processed data',
      },
    });
    
    // Glue crawler for automatic schema discovery
    this.glueCrawler = new glue.CfnCrawler(this, 'GlueCrawler', {
      name: `${resourcePrefix}-crawler`,
      role: this.glueRole.roleArn,
      databaseName: this.glueDatabase.ref,
      targets: {
        s3Targets: [
          {
            path: `s3://${this.processedDataBucket.bucketName}/validated/`,
          },
        ],
      },
      schedule: {
        scheduleExpression: 'cron(0 */6 * * ? *)', // Run every 6 hours
      },
      description: 'Crawls processed data to maintain data catalog',
      configuration: JSON.stringify({
        Version: 1.0,
        CrawlerOutput: {
          Partitions: { AddOrUpdateBehavior: 'InheritFromTable' },
          Tables: { AddOrUpdateBehavior: 'MergeNewColumns' },
        },
      }),
    });
    
    // Add dependency to ensure database exists before crawler
    this.glueCrawler.addDependency(this.glueDatabase);
  }
  
  /**
   * Configures event-driven integrations between services
   */
  private configureEventIntegrations(): void {
    // S3 event notification to trigger data ingestion
    this.rawDataBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.dataIngestionFunction),
      { prefix: 'input/' }
    );
    
    // EventBridge targets for data processing pipeline
    this.dataIngestionRule.addTarget(
      new targets.LambdaFunction(this.dataValidationFunction)
    );
    
    this.dataValidationRule.addTarget(
      new targets.LambdaFunction(this.qualityMonitoringFunction)
    );
  }
  
  /**
   * Sets up CloudWatch monitoring and alerting
   */
  private setupMonitoring(resourcePrefix: string): void {
    // Lambda function error alarms
    const functions = [
      this.dataIngestionFunction,
      this.dataValidationFunction,
      this.qualityMonitoringFunction,
    ];
    
    functions.forEach((func, index) => {
      new cloudwatch.Alarm(this, `LambdaErrorAlarm${index}`, {
        alarmName: `${resourcePrefix}-${func.functionName}-errors`,
        metric: func.metricErrors({
          period: cdk.Duration.minutes(5),
        }),
        threshold: 1,
        evaluationPeriods: 1,
        treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
        alarmDescription: `Alarm for errors in ${func.functionName}`,
      });
    });
    
    // Data quality monitoring dashboard
    const dashboard = new cloudwatch.Dashboard(this, 'DataLakeDashboard', {
      dashboardName: `${resourcePrefix}-data-lake-dashboard`,
    });
    
    // Add widgets for key metrics
    dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Data Processing Volume',
        left: [
          new cloudwatch.Metric({
            namespace: 'DataLake/Quality',
            metricName: 'ProcessedRecords',
            dimensionsMap: {
              Pipeline: resourcePrefix,
            },
            statistic: 'Sum',
          }),
        ],
        width: 12,
        height: 6,
      }),
      new cloudwatch.GraphWidget({
        title: 'Data Quality Metrics',
        left: [
          new cloudwatch.Metric({
            namespace: 'DataLake/Quality',
            metricName: 'ValidationSuccessRate',
            dimensionsMap: {
              Pipeline: resourcePrefix,
            },
            statistic: 'Average',
          }),
          new cloudwatch.Metric({
            namespace: 'DataLake/Quality',
            metricName: 'AverageQualityScore',
            dimensionsMap: {
              Pipeline: resourcePrefix,
            },
            statistic: 'Average',
          }),
        ],
        width: 12,
        height: 6,
      })
    );
  }
  
  /**
   * Creates CloudFormation outputs for important resources
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'RawDataBucketName', {
      value: this.rawDataBucket.bucketName,
      description: 'Name of the raw data S3 bucket',
      exportName: `${this.stackName}-RawDataBucket`,
    });
    
    new cdk.CfnOutput(this, 'ProcessedDataBucketName', {
      value: this.processedDataBucket.bucketName,
      description: 'Name of the processed data S3 bucket',
      exportName: `${this.stackName}-ProcessedDataBucket`,
    });
    
    new cdk.CfnOutput(this, 'QuarantineDataBucketName', {
      value: this.quarantineDataBucket.bucketName,
      description: 'Name of the quarantine data S3 bucket',
      exportName: `${this.stackName}-QuarantineDataBucket`,
    });
    
    new cdk.CfnOutput(this, 'MetadataTableName', {
      value: this.metadataTable.tableName,
      description: 'Name of the metadata DynamoDB table',
      exportName: `${this.stackName}-MetadataTable`,
    });
    
    new cdk.CfnOutput(this, 'CustomEventBusName', {
      value: this.customEventBus.eventBusName,
      description: 'Name of the custom EventBridge bus',
      exportName: `${this.stackName}-CustomEventBus`,
    });
    
    new cdk.CfnOutput(this, 'GlueDatabaseName', {
      value: this.glueDatabase.ref,
      description: 'Name of the Glue database',
      exportName: `${this.stackName}-GlueDatabase`,
    });
    
    new cdk.CfnOutput(this, 'DataIngestionFunctionName', {
      value: this.dataIngestionFunction.functionName,
      description: 'Name of the data ingestion Lambda function',
      exportName: `${this.stackName}-DataIngestionFunction`,
    });
  }
  
  /**
   * Generates a random suffix for resource naming
   */
  private generateRandomSuffix(): string {
    return Math.random().toString(36).substring(2, 8);
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Deploy the Advanced Serverless Data Lake Stack
new AdvancedServerlessDataLakeStack(app, 'AdvancedServerlessDataLakeStack', {
  description: 'Advanced Serverless Data Lake Architecture with Lambda Layers, Glue, and EventBridge',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  // Customize these properties as needed
  projectName: process.env.PROJECT_NAME || 'advanced-serverless-datalake',
  enableMonitoring: true,
  enableAutoScaling: true,
  tags: {
    Project: 'AdvancedServerlessDataLake',
    Environment: process.env.ENVIRONMENT || 'development',
    Owner: process.env.OWNER || 'data-engineering-team',
    CostCenter: process.env.COST_CENTER || 'analytics',
  },
});

// Synthesize the CDK app
app.synth();