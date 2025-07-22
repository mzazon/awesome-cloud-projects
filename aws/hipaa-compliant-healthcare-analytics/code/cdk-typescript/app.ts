#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as healthlake from 'aws-cdk-lib/aws-healthlake';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kms from 'aws-cdk-lib/aws-kms';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Annotations } from 'aws-cdk-lib';

/**
 * Properties for the Healthcare Data Processing Pipeline Stack
 */
interface HealthcareDataPipelineStackProps extends cdk.StackProps {
  readonly environment: 'dev' | 'staging' | 'prod';
  readonly hipaaCompliant: boolean;
  readonly retentionPeriod: cdk.Duration;
  readonly datastoreName?: string;
}

/**
 * Healthcare Data Processing Pipeline Stack
 * 
 * This stack creates a HIPAA-compliant healthcare data processing pipeline using:
 * - AWS HealthLake for FHIR data storage and management
 * - Lambda functions for data processing and analytics
 * - S3 buckets for data input/output with encryption
 * - EventBridge for event-driven architecture
 * - CloudWatch for monitoring and logging
 */
class HealthcareDataPipelineStack extends cdk.Stack {
  public readonly dataStore: healthlake.CfnFHIRDatastore;
  public readonly inputBucket: s3.Bucket;
  public readonly outputBucket: s3.Bucket;
  public readonly processingFunction: lambda.Function;
  public readonly analyticsFunction: lambda.Function;

  constructor(scope: Construct, id: string, props: HealthcareDataPipelineStackProps) {
    super(scope, id, props);

    // Validate HIPAA compliance requirements
    this.validateHipaaCompliance(props);

    // Create KMS key for encryption (required for HIPAA compliance)
    const encryptionKey = this.createKmsKey();

    // Create S3 buckets for data storage
    const { inputBucket, outputBucket } = this.createS3Buckets(encryptionKey, props.retentionPeriod);
    this.inputBucket = inputBucket;
    this.outputBucket = outputBucket;

    // Create IAM role for HealthLake service
    const healthLakeServiceRole = this.createHealthLakeServiceRole(inputBucket, outputBucket);

    // Create HealthLake FHIR data store
    this.dataStore = this.createHealthLakeDataStore(encryptionKey, props.datastoreName, healthLakeServiceRole);

    // Create Lambda functions for data processing
    const { processingFunction, analyticsFunction } = this.createLambdaFunctions(
      this.dataStore,
      outputBucket,
      encryptionKey
    );
    this.processingFunction = processingFunction;
    this.analyticsFunction = analyticsFunction;

    // Create EventBridge rules for event-driven processing
    this.createEventBridgeRules(processingFunction, analyticsFunction);

    // Add stack outputs
    this.createOutputs();

    // Add tags for compliance and cost management
    this.addComplianceTags();
  }

  /**
   * Validates HIPAA compliance requirements
   */
  private validateHipaaCompliance(props: HealthcareDataPipelineStackProps): void {
    if (!props.hipaaCompliant) {
      Annotations.of(this).addError(
        'HIPAA compliance must be enabled for healthcare data processing'
      );
    }

    if (props.retentionPeriod.toDays() < 2555) {
      Annotations.of(this).addWarning(
        'Healthcare data retention should be at least 7 years (2555 days) for compliance'
      );
    }

    if (props.environment === 'prod' && !props.hipaaCompliant) {
      Annotations.of(this).addError(
        'Production environment must have HIPAA compliance enabled'
      );
    }
  }

  /**
   * Creates a customer-managed KMS key for encryption
   */
  private createKmsKey(): kms.Key {
    return new kms.Key(this, 'HealthcareEncryptionKey', {
      description: 'KMS key for encrypting healthcare data (HIPAA compliant)',
      enableKeyRotation: true,
      keyPolicy: new iam.PolicyDocument({
        statements: [
          new iam.PolicyStatement({
            sid: 'EnableRootAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.AccountRootPrincipal()],
            actions: ['kms:*'],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            sid: 'AllowHealthLakeAccess',
            effect: iam.Effect.ALLOW,
            principals: [new iam.ServicePrincipal('healthlake.amazonaws.com')],
            actions: [
              'kms:Decrypt',
              'kms:DescribeKey',
              'kms:Encrypt',
              'kms:GenerateDataKey',
              'kms:ReEncrypt*',
            ],
            resources: ['*'],
          }),
        ],
      }),
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });
  }

  /**
   * Creates S3 buckets for input and output data with HIPAA compliance
   */
  private createS3Buckets(encryptionKey: kms.Key, retentionPeriod: cdk.Duration): {
    inputBucket: s3.Bucket;
    outputBucket: s3.Bucket;
  } {
    const inputBucket = new s3.Bucket(this, 'HealthcareInputBucket', {
      bucketName: `healthcare-input-${this.account}-${this.region}`,
      enforceSSL: true,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: encryptionKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'healthcare-input-retention',
          enabled: true,
          expiration: retentionPeriod,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      serverAccessLogsPrefix: 'access-logs/',
      eventBridgeEnabled: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    const outputBucket = new s3.Bucket(this, 'HealthcareOutputBucket', {
      bucketName: `healthcare-output-${this.account}-${this.region}`,
      enforceSSL: true,
      encryption: s3.BucketEncryption.KMS,
      encryptionKey: encryptionKey,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      versioned: true,
      lifecycleRules: [
        {
          id: 'healthcare-output-retention',
          enabled: true,
          expiration: retentionPeriod,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      serverAccessLogsPrefix: 'access-logs/',
      eventBridgeEnabled: true,
      removalPolicy: cdk.RemovalPolicy.RETAIN,
    });

    return { inputBucket, outputBucket };
  }

  /**
   * Creates IAM role for HealthLake service
   */
  private createHealthLakeServiceRole(inputBucket: s3.Bucket, outputBucket: s3.Bucket): iam.Role {
    const healthLakeRole = new iam.Role(this, 'HealthLakeServiceRole', {
      assumedBy: new iam.ServicePrincipal('healthlake.amazonaws.com'),
      description: 'Service role for AWS HealthLake to access S3 buckets',
      inlinePolicies: {
        HealthLakeS3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
                's3:GetObjectVersion',
              ],
              resources: [
                `${inputBucket.bucketArn}/*`,
                `${outputBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [inputBucket.bucketArn, outputBucket.bucketArn],
            }),
          ],
        }),
      },
    });

    return healthLakeRole;
  }

  /**
   * Creates HealthLake FHIR data store
   */
  private createHealthLakeDataStore(
    encryptionKey: kms.Key,
    datastoreName?: string,
    serviceRole?: iam.Role
  ): healthlake.CfnFHIRDatastore {
    const dataStore = new healthlake.CfnFHIRDatastore(this, 'HealthLakeFHIRDataStore', {
      datastoreName: datastoreName || 'healthcare-fhir-datastore',
      datastoreTypeVersion: 'R4',
      sseConfiguration: {
        kmsEncryptionConfig: {
          cmkType: 'CUSTOMER_MANAGED_KMS_KEY',
          kmsKeyId: encryptionKey.keyArn,
        },
      },
      preloadDataConfig: {
        preloadDataType: 'SYNTHEA',
      },
      tags: [
        {
          key: 'Environment',
          value: this.node.tryGetContext('environment') || 'dev',
        },
        {
          key: 'HIPAA-Compliant',
          value: 'true',
        },
        {
          key: 'DataClassification',
          value: 'PHI',
        },
      ],
    });

    return dataStore;
  }

  /**
   * Creates Lambda functions for data processing and analytics
   */
  private createLambdaFunctions(
    dataStore: healthlake.CfnFHIRDatastore,
    outputBucket: s3.Bucket,
    encryptionKey: kms.Key
  ): {
    processingFunction: lambda.Function;
    analyticsFunction: lambda.Function;
  } {
    // Create dead letter queue for error handling
    const deadLetterQueue = new sqs.Queue(this, 'HealthcareProcessingDLQ', {
      queueName: 'healthcare-processing-dlq',
      encryption: sqs.QueueEncryption.KMS,
      encryptionMasterKey: encryptionKey,
      retentionPeriod: cdk.Duration.days(14),
    });

    // Create Lambda execution role with minimal permissions
    const lambdaRole = new iam.Role(this, 'HealthcareLambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        HealthLakeAccess: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'healthlake:ReadResource',
                'healthlake:SearchWithGet',
                'healthlake:SearchWithPost',
              ],
              resources: [dataStore.attrDatastoreArn],
            }),
          ],
        }),
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:GetObject', 's3:PutObject'],
              resources: [`${outputBucket.bucketArn}/*`],
              conditions: {
                StringEquals: {
                  's3:x-amz-server-side-encryption': 'aws:kms',
                },
              },
            }),
          ],
        }),
      },
    });

    // Create processing function
    const processingFunction = new lambda.Function(this, 'HealthcareDataProcessor', {
      functionName: 'healthcare-data-processor',
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

healthlake = boto3.client('healthlake')

def lambda_handler(event, context):
    """
    Process HealthLake events from EventBridge
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract event details
        event_source = event.get('source')
        event_type = event.get('detail-type')
        event_detail = event.get('detail', {})
        
        if event_source == 'aws.healthlake':
            if 'Import Job' in event_type:
                process_import_job_event(event_detail)
            elif 'Export Job' in event_type:
                process_export_job_event(event_detail)
            elif 'Data Store' in event_type:
                process_datastore_event(event_detail)
        
        return {
            'statusCode': 200,
            'body': json.dumps('Event processed successfully')
        }
        
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def process_import_job_event(event_detail):
    """Process import job status changes"""
    job_status = event_detail.get('jobStatus')
    job_id = event_detail.get('jobId')
    
    logger.info(f"Import job {job_id} status: {job_status}")
    
    if job_status == 'COMPLETED':
        logger.info(f"Import job {job_id} completed successfully")
    elif job_status == 'FAILED':
        logger.error(f"Import job {job_id} failed")

def process_export_job_event(event_detail):
    """Process export job status changes"""
    job_status = event_detail.get('jobStatus')
    job_id = event_detail.get('jobId')
    
    logger.info(f"Export job {job_id} status: {job_status}")

def process_datastore_event(event_detail):
    """Process datastore status changes"""
    datastore_status = event_detail.get('datastoreStatus')
    datastore_id = event_detail.get('datastoreId')
    
    logger.info(f"Datastore {datastore_id} status: {datastore_status}")
      `),
      environment: {
        DATASTORE_ID: dataStore.attrDatastoreId,
        OUTPUT_BUCKET: outputBucket.bucketName,
        POWERTOOLS_SERVICE_NAME: 'healthcare-processor',
        POWERTOOLS_METRICS_NAMESPACE: 'Healthcare/DataProcessing',
        LOG_LEVEL: 'INFO',
      },
      timeout: cdk.Duration.minutes(5),
      memorySize: 1024,
      role: lambdaRole,
      deadLetterQueue: deadLetterQueue,
      logRetention: logs.RetentionDays.ONE_YEAR,
    });

    // Create analytics function
    const analyticsFunction = new lambda.Function(this, 'HealthcareAnalytics', {
      functionName: 'healthcare-analytics',
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime, timedelta

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Generate analytics reports from HealthLake data
    """
    try:
        logger.info("Starting analytics processing")
        
        # Generate sample analytics report
        report = generate_patient_analytics()
        
        # Save report to S3
        report_key = f"analytics/patient-report-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
        
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=report_key,
            Body=json.dumps(report, indent=2),
            ContentType='application/json',
            ServerSideEncryption='aws:kms'
        )
        
        logger.info(f"Analytics report saved to s3://{os.environ['OUTPUT_BUCKET']}/{report_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps('Analytics processing completed')
        }
        
    except Exception as e:
        logger.error(f"Error in analytics processing: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def generate_patient_analytics():
    """Generate sample patient analytics"""
    return {
        'report_type': 'patient_summary',
        'generated_at': datetime.now().isoformat(),
        'metrics': {
            'total_patients': 1,
            'active_patients': 1,
            'recent_visits': 0,
            'avg_age': 39
        },
        'demographics': {
            'gender_distribution': {
                'male': 1,
                'female': 0,
                'other': 0
            },
            'age_groups': {
                '0-17': 0,
                '18-64': 1,
                '65+': 0
            }
        }
    }
      `),
      environment: {
        DATASTORE_ID: dataStore.attrDatastoreId,
        OUTPUT_BUCKET: outputBucket.bucketName,
        POWERTOOLS_SERVICE_NAME: 'healthcare-analytics',
        POWERTOOLS_METRICS_NAMESPACE: 'Healthcare/Analytics',
        LOG_LEVEL: 'INFO',
      },
      timeout: cdk.Duration.minutes(5),
      memorySize: 1024,
      role: lambdaRole,
      deadLetterQueue: deadLetterQueue,
      logRetention: logs.RetentionDays.ONE_YEAR,
    });

    // Grant additional permissions to analytics function
    outputBucket.grantWrite(analyticsFunction);

    return { processingFunction, analyticsFunction };
  }

  /**
   * Creates EventBridge rules for event-driven processing
   */
  private createEventBridgeRules(
    processingFunction: lambda.Function,
    analyticsFunction: lambda.Function
  ): void {
    // Create rule for HealthLake events
    const healthLakeProcessorRule = new events.Rule(this, 'HealthLakeProcessorRule', {
      ruleName: 'healthcare-processor-rule',
      description: 'Route HealthLake events to processing function',
      eventPattern: {
        source: ['aws.healthlake'],
        detailType: [
          'HealthLake Import Job State Change',
          'HealthLake Export Job State Change',
          'HealthLake Data Store State Change',
        ],
      },
    });

    // Add Lambda processor as target with error handling
    healthLakeProcessorRule.addTarget(
      new targets.LambdaFunction(processingFunction, {
        maxEventAge: cdk.Duration.minutes(1),
        retryAttempts: 3,
      })
    );

    // Create rule for analytics trigger (on successful imports)
    const analyticsRule = new events.Rule(this, 'HealthLakeAnalyticsRule', {
      ruleName: 'healthcare-analytics-rule',
      description: 'Trigger analytics on successful data imports',
      eventPattern: {
        source: ['aws.healthlake'],
        detailType: ['HealthLake Import Job State Change'],
        detail: {
          jobStatus: ['COMPLETED'],
        },
      },
    });

    // Add Lambda analytics as target
    analyticsRule.addTarget(
      new targets.LambdaFunction(analyticsFunction, {
        maxEventAge: cdk.Duration.minutes(1),
        retryAttempts: 3,
      })
    );
  }

  /**
   * Creates CloudFormation outputs
   */
  private createOutputs(): void {
    new cdk.CfnOutput(this, 'DataStoreId', {
      value: this.dataStore.attrDatastoreId,
      description: 'HealthLake FHIR Data Store ID',
      exportName: `${this.stackName}-DataStoreId`,
    });

    new cdk.CfnOutput(this, 'DataStoreEndpoint', {
      value: this.dataStore.attrDatastoreEndpoint,
      description: 'HealthLake FHIR Data Store Endpoint',
      exportName: `${this.stackName}-DataStoreEndpoint`,
    });

    new cdk.CfnOutput(this, 'InputBucketName', {
      value: this.inputBucket.bucketName,
      description: 'S3 Input Bucket Name',
      exportName: `${this.stackName}-InputBucket`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: this.outputBucket.bucketName,
      description: 'S3 Output Bucket Name',
      exportName: `${this.stackName}-OutputBucket`,
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Healthcare Data Processing Lambda Function Name',
      exportName: `${this.stackName}-ProcessingFunction`,
    });

    new cdk.CfnOutput(this, 'AnalyticsFunctionName', {
      value: this.analyticsFunction.functionName,
      description: 'Healthcare Analytics Lambda Function Name',
      exportName: `${this.stackName}-AnalyticsFunction`,
    });
  }

  /**
   * Adds compliance and governance tags
   */
  private addComplianceTags(): void {
    const tags = {
      Environment: this.node.tryGetContext('environment') || 'dev',
      'HIPAA-Compliant': 'true',
      'Data-Classification': 'PHI',
      Project: 'Healthcare-Data-Pipeline',
      'Cost-Center': 'Healthcare-IT',
      'Backup-Required': 'true',
      'Monitoring-Required': 'true',
    };

    Object.entries(tags).forEach(([key, value]) => {
      cdk.Tags.of(this).add(key, value);
    });
  }
}

/**
 * CDK Application Entry Point
 */
const app = new cdk.App();

// Get configuration from context
const environment = app.node.tryGetContext('environment') || 'dev';
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION;

// Create the healthcare data pipeline stack
new HealthcareDataPipelineStack(app, 'HealthcareDataPipelineStack', {
  stackName: `healthcare-data-pipeline-${environment}`,
  environment,
  hipaaCompliant: true,
  retentionPeriod: cdk.Duration.days(2555), // 7 years for healthcare compliance
  datastoreName: `healthcare-fhir-datastore-${environment}`,
  env: {
    account,
    region,
  },
  description: 'HIPAA-compliant healthcare data processing pipeline using AWS HealthLake',
  tags: {
    Environment: environment,
    'HIPAA-Compliant': 'true',
    'Data-Classification': 'PHI',
  },
});

// Add metadata
app.node.setContext('@aws-cdk/core:enableStackNameDuplicates', false);
app.node.setContext('@aws-cdk/core:stackRelativeExports', true);