#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as sfnTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for automated document processing pipeline using Amazon Textract and Step Functions
 * 
 * This stack creates:
 * - S3 buckets for input, output, and archive storage
 * - Lambda functions for document processing and results handling
 * - Step Functions state machine for workflow orchestration
 * - CloudWatch monitoring and logging
 * - S3 event notifications for automatic pipeline triggering
 */
export class TextractStepFunctionsPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();
    const projectName = `textract-pipeline-${uniqueSuffix}`;

    // Create S3 buckets for document processing pipeline
    const inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `${projectName}-input`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: Duration.days(30),
        },
      ],
    });

    const outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `${projectName}-output`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
          ],
        },
      ],
    });

    const archiveBucket = new s3.Bucket(this, 'ArchiveBucket', {
      bucketName: `${projectName}-archive`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'TransitionToGlacier',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: Duration.days(90),
            },
          ],
        },
      ],
    });

    // Create CloudWatch log groups for Lambda functions
    const documentProcessorLogGroup = new logs.LogGroup(this, 'DocumentProcessorLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-document-processor`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const resultsProcessorLogGroup = new logs.LogGroup(this, 'ResultsProcessorLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-results-processor`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    const s3TriggerLogGroup = new logs.LogGroup(this, 'S3TriggerLogGroup', {
      logGroupName: `/aws/lambda/${projectName}-s3-trigger`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // Create IAM role for Lambda functions with comprehensive permissions
    const lambdaExecutionRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${projectName}-lambda-role`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        TextractPermissions: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'textract:StartDocumentAnalysis',
                'textract:StartDocumentTextDetection',
                'textract:GetDocumentAnalysis',
                'textract:GetDocumentTextDetection',
              ],
              resources: ['*'],
            }),
          ],
        }),
        S3Permissions: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                `${inputBucket.bucketArn}/*`,
                `${outputBucket.bucketArn}/*`,
                `${archiveBucket.bucketArn}/*`,
              ],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['s3:ListBucket'],
              resources: [
                inputBucket.bucketArn,
                outputBucket.bucketArn,
                archiveBucket.bucketArn,
              ],
            }),
          ],
        }),
      },
    });

    // Create Lambda function for document processing initiation
    const documentProcessorFunction = new lambda.Function(this, 'DocumentProcessorFunction', {
      functionName: `${projectName}-document-processor`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      description: 'Initiates Textract document processing',
      logGroup: documentProcessorLogGroup,
      environment: {
        LOG_LEVEL: 'INFO',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Extract S3 information from event
        bucket = event['bucket']
        key = unquote_plus(event['key'])
        
        logger.info(f"Processing document: s3://{bucket}/{key}")
        
        # Determine document type and processing method
        file_extension = key.lower().split('.')[-1]
        
        # Configure Textract parameters based on document type
        if file_extension in ['pdf', 'png', 'jpg', 'jpeg', 'tiff']:
            # Start document analysis for complex documents
            response = textract.start_document_analysis(
                DocumentLocation={
                    'S3Object': {
                        'Bucket': bucket,
                        'Name': key
                    }
                },
                FeatureTypes=['TABLES', 'FORMS', 'SIGNATURES']
            )
            
            job_id = response['JobId']
            
            return {
                'statusCode': 200,
                'jobId': job_id,
                'jobType': 'ANALYSIS',
                'bucket': bucket,
                'key': key,
                'documentType': file_extension
            }
        else:
            raise ValueError(f"Unsupported file type: {file_extension}")
            
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
      `),
    });

    // Create Lambda function for results processing
    const resultsProcessorFunction = new lambda.Function(this, 'ResultsProcessorFunction', {
      functionName: `${projectName}-results-processor`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(300),
      memorySize: 512,
      description: 'Processes and formats Textract extraction results',
      logGroup: resultsProcessorLogGroup,
      environment: {
        LOG_LEVEL: 'INFO',
        OUTPUT_BUCKET: outputBucket.bucketName,
        ARCHIVE_BUCKET: archiveBucket.bucketName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime

logger = logging.getLogger()
logger.setLevel(logging.INFO)

textract = boto3.client('textract')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        job_id = event['jobId']
        job_type = event['jobType']
        bucket = event['bucket']
        key = event['key']
        output_bucket = event.get('outputBucket', os.environ.get('OUTPUT_BUCKET'))
        archive_bucket = event.get('archiveBucket', os.environ.get('ARCHIVE_BUCKET'))
        
        logger.info(f"Processing results for job: {job_id}")
        
        # Get Textract results based on job type
        if job_type == 'ANALYSIS':
            response = textract.get_document_analysis(JobId=job_id)
        else:
            response = textract.get_document_text_detection(JobId=job_id)
        
        # Check job status
        job_status = response['JobStatus']
        
        if job_status == 'SUCCEEDED':
            # Process and structure the results
            processed_data = {
                'timestamp': datetime.utcnow().isoformat(),
                'sourceDocument': f"s3://{bucket}/{key}",
                'jobId': job_id,
                'jobType': job_type,
                'documentMetadata': response.get('DocumentMetadata', {}),
                'extractedData': {
                    'text': [],
                    'tables': [],
                    'forms': []
                }
            }
            
            # Parse blocks and extract meaningful data
            blocks = response.get('Blocks', [])
            
            for block in blocks:
                if block['BlockType'] == 'LINE':
                    processed_data['extractedData']['text'].append({
                        'text': block.get('Text', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {})
                    })
                elif block['BlockType'] == 'TABLE':
                    # Process table data with enhanced metadata
                    table_data = {
                        'id': block.get('Id', ''),
                        'confidence': block.get('Confidence', 0),
                        'geometry': block.get('Geometry', {}),
                        'rowCount': block.get('RowCount', 0),
                        'columnCount': block.get('ColumnCount', 0)
                    }
                    processed_data['extractedData']['tables'].append(table_data)
                elif block['BlockType'] == 'KEY_VALUE_SET':
                    # Process form data
                    if block.get('EntityTypes') and 'KEY' in block['EntityTypes']:
                        form_data = {
                            'id': block.get('Id', ''),
                            'confidence': block.get('Confidence', 0),
                            'geometry': block.get('Geometry', {}),
                            'text': block.get('Text', '')
                        }
                        processed_data['extractedData']['forms'].append(form_data)
            
            # Save processed results to S3 output bucket
            output_key = f"processed/{key.replace('.', '_')}_results.json"
            
            s3.put_object(
                Bucket=output_bucket,
                Key=output_key,
                Body=json.dumps(processed_data, indent=2),
                ContentType='application/json',
                Metadata={
                    'source-bucket': bucket,
                    'source-key': key,
                    'processing-timestamp': datetime.utcnow().isoformat()
                }
            )
            
            # Archive original document with date-based organization
            if archive_bucket:
                archive_key = f"archive/{datetime.utcnow().strftime('%Y/%m/%d')}/{key}"
                s3.copy_object(
                    CopySource={'Bucket': bucket, 'Key': key},
                    Bucket=archive_bucket,
                    Key=archive_key
                )
            
            return {
                'statusCode': 200,
                'status': 'COMPLETED',
                'outputLocation': f"s3://{output_bucket}/{output_key}",
                'extractedItems': {
                    'textLines': len(processed_data['extractedData']['text']),
                    'tables': len(processed_data['extractedData']['tables']),
                    'forms': len(processed_data['extractedData']['forms'])
                }
            }
            
        elif job_status == 'FAILED':
            logger.error(f"Textract job failed: {job_id}")
            return {
                'statusCode': 500,
                'status': 'FAILED',
                'error': 'Textract job failed'
            }
        else:
            # Job still in progress
            return {
                'statusCode': 202,
                'status': 'IN_PROGRESS',
                'message': f"Job status: {job_status}"
            }
            
    except Exception as e:
        logger.error(f"Error processing results: {str(e)}")
        return {
            'statusCode': 500,
            'status': 'ERROR',
            'error': str(e)
        }
      `),
    });

    // Create Step Functions state machine definition
    const processDocumentTask = new sfnTasks.LambdaInvoke(this, 'ProcessDocumentTask', {
      lambdaFunction: documentProcessorFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'bucket.$': '$.bucket',
        'key.$': '$.key',
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    const waitForCompletion = new stepfunctions.Wait(this, 'WaitForTextractCompletion', {
      time: stepfunctions.WaitTime.duration(Duration.seconds(30)),
    });

    const checkStatusTask = new sfnTasks.LambdaInvoke(this, 'CheckTextractStatusTask', {
      lambdaFunction: resultsProcessorFunction,
      payload: stepfunctions.TaskInput.fromObject({
        'jobId.$': '$.jobId',
        'jobType.$': '$.jobType',
        'bucket.$': '$.bucket',
        'key.$': '$.key',
        'outputBucket': outputBucket.bucketName,
        'archiveBucket': archiveBucket.bucketName,
      }),
      outputPath: '$.Payload',
      retryOnServiceExceptions: true,
    });

    const processingCompleted = new stepfunctions.Succeed(this, 'ProcessingCompleted', {
      comment: 'Document processing completed successfully',
    });

    const processingFailed = new stepfunctions.Fail(this, 'ProcessingFailed', {
      cause: 'Document processing failed',
    });

    // Create choice state for status evaluation
    const evaluateStatus = new stepfunctions.Choice(this, 'EvaluateStatus');

    // Define state machine flow
    const definition = processDocumentTask
      .addCatch(processingFailed, {
        errors: ['States.ALL'],
      })
      .next(waitForCompletion)
      .next(checkStatusTask)
      .next(
        evaluateStatus
          .when(
            stepfunctions.Condition.stringEquals('$.status', 'COMPLETED'),
            processingCompleted
          )
          .when(
            stepfunctions.Condition.stringEquals('$.status', 'IN_PROGRESS'),
            waitForCompletion
          )
          .when(
            stepfunctions.Condition.stringEquals('$.status', 'FAILED'),
            processingFailed
          )
          .otherwise(processingFailed)
      );

    // Create Step Functions state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'DocumentProcessingStateMachine', {
      stateMachineName: `${projectName}-document-pipeline`,
      definition,
      timeout: Duration.minutes(30),
      logs: {
        destination: new logs.LogGroup(this, 'StateMachineLogGroup', {
          logGroupName: `/aws/stepfunctions/${projectName}-document-pipeline`,
          retention: logs.RetentionDays.ONE_MONTH,
          removalPolicy: RemovalPolicy.DESTROY,
        }),
        level: stepfunctions.LogLevel.ALL,
      },
    });

    // Create Lambda function for S3 event handling
    const s3TriggerFunction = new lambda.Function(this, 'S3TriggerFunction', {
      functionName: `${projectName}-s3-trigger`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaExecutionRole,
      timeout: Duration.seconds(60),
      memorySize: 256,
      description: 'Triggers document processing pipeline from S3 events',
      logGroup: s3TriggerLogGroup,
      environment: {
        STATE_MACHINE_ARN: stateMachine.stateMachineArn,
        LOG_LEVEL: 'INFO',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from urllib.parse import unquote_plus

logger = logging.getLogger()
logger.setLevel(logging.INFO)

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    try:
        state_machine_arn = os.environ['STATE_MACHINE_ARN']
        
        # Process S3 event records
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            logger.info(f"New document uploaded: s3://{bucket}/{key}")
            
            # Start Step Functions execution
            execution_input = {
                'bucket': bucket,
                'key': key,
                'eventTime': record['eventTime']
            }
            
            execution_name = f"doc-processing-{key.replace('/', '-').replace('.', '-')}-{context.aws_request_id[:8]}"
            
            response = stepfunctions.start_execution(
                stateMachineArn=state_machine_arn,
                name=execution_name,
                input=json.dumps(execution_input)
            )
            
            logger.info(f"Started execution: {response['executionArn']}")
            
        return {
            'statusCode': 200,
            'message': f"Processed {len(event['Records'])} document(s)"
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'statusCode': 500,
            'error': str(e)
        }
      `),
    });

    // Grant Step Functions execution permissions to S3 trigger Lambda
    stateMachine.grantStartExecution(s3TriggerFunction);

    // Configure S3 bucket notification for automatic processing
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(s3TriggerFunction),
      {
        suffix: '.pdf',
      }
    );

    // Create CloudWatch dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'PipelineDashboard', {
      dashboardName: `${projectName}-pipeline-monitoring`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Invocations',
            width: 12,
            height: 6,
            left: [
              documentProcessorFunction.metricInvocations({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              resultsProcessorFunction.metricInvocations({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              s3TriggerFunction.metricInvocations({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
            ],
          }),
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Errors',
            width: 12,
            height: 6,
            left: [
              documentProcessorFunction.metricErrors({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              resultsProcessorFunction.metricErrors({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              s3TriggerFunction.metricErrors({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'Step Functions Executions',
            width: 12,
            height: 6,
            left: [
              stateMachine.metricStarted({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              stateMachine.metricSucceeded({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              stateMachine.metricFailed({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
            ],
          }),
          new cloudwatch.GraphWidget({
            title: 'Step Functions Execution Duration',
            width: 12,
            height: 6,
            left: [
              stateMachine.metricTime({
                statistic: 'Average',
                period: Duration.minutes(5),
              }),
            ],
          }),
        ],
      ],
    });

    // Stack outputs for easy access to resource information
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'Name of the S3 input bucket for documents',
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'Name of the S3 output bucket for processed results',
    });

    new cdk.CfnOutput(this, 'ArchiveBucketName', {
      value: archiveBucket.bucketName,
      description: 'Name of the S3 archive bucket for processed documents',
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'ARN of the Step Functions state machine',
    });

    new cdk.CfnOutput(this, 'DashboardUrl', {
      value: `https://console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${projectName}-pipeline-monitoring`,
      description: 'URL to the CloudWatch dashboard',
    });

    // Add tags to all resources for cost tracking and management
    cdk.Tags.of(this).add('Project', 'TextractStepFunctionsPipeline');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('Owner', 'CloudEngineering');
    cdk.Tags.of(this).add('CostCenter', 'Analytics');
  }
}

// CDK App instantiation
const app = new cdk.App();
new TextractStepFunctionsPipelineStack(app, 'TextractStepFunctionsPipelineStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Automated document processing pipeline using Amazon Textract and Step Functions',
  tags: {
    Project: 'TextractStepFunctionsPipeline',
    Environment: 'Production',
    Repository: 'aws-recipes',
  },
});