#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as tasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for Document Processing Pipelines with Amazon Textract and Step Functions
 * 
 * This stack implements an automated document processing pipeline that:
 * - Processes documents uploaded to S3
 * - Uses Amazon Textract for intelligent document analysis
 * - Orchestrates workflows with AWS Step Functions
 * - Stores results and tracks job status
 * - Sends notifications upon completion
 */
class DocumentProcessingPipelineStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names to avoid conflicts
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // ========================================
    // S3 Buckets for Document Storage
    // ========================================

    /**
     * S3 bucket for storing input documents
     * Configured with versioning and lifecycle policies for cost optimization
     */
    const documentBucket = new s3.Bucket(this, 'DocumentBucket', {
      bucketName: `document-processing-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          noncurrentVersionExpiration: cdk.Duration.days(30),
          enabled: true,
        },
      ],
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    /**
     * S3 bucket for storing processing results
     * Separate bucket for clean organization and different access patterns
     */
    const resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `processing-results-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      lifecycleRules: [
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
          enabled: true,
        },
      ],
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
    });

    // ========================================
    // DynamoDB Table for Job Tracking
    // ========================================

    /**
     * DynamoDB table for tracking document processing jobs
     * Uses pay-per-request billing for cost optimization
     */
    const jobTable = new dynamodb.Table(this, 'DocumentProcessingJobsTable', {
      tableName: 'DocumentProcessingJobs',
      partitionKey: {
        name: 'JobId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // ========================================
    // SNS Topic for Notifications
    // ========================================

    /**
     * SNS topic for sending processing notifications
     * Supports both success and failure notifications
     */
    const notificationTopic = new sns.Topic(this, 'DocumentProcessingNotifications', {
      topicName: 'DocumentProcessingNotifications',
      displayName: 'Document Processing Pipeline Notifications',
    });

    // ========================================
    // IAM Roles and Policies
    // ========================================

    /**
     * IAM role for Step Functions state machine execution
     * Includes permissions for Textract, S3, DynamoDB, and SNS
     */
    const stepFunctionsRole = new iam.Role(this, 'StepFunctionsExecutionRole', {
      assumedBy: new iam.ServicePrincipal('states.amazonaws.com'),
      description: 'Role for Step Functions to execute document processing workflow',
      inlinePolicies: {
        DocumentProcessingPolicy: new iam.PolicyDocument({
          statements: [
            // Textract permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'textract:AnalyzeDocument',
                'textract:DetectDocumentText',
                'textract:GetDocumentAnalysis',
                'textract:GetDocumentTextDetection',
                'textract:StartDocumentAnalysis',
                'textract:StartDocumentTextDetection',
              ],
              resources: ['*'],
            }),
            // S3 permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
              ],
              resources: [
                documentBucket.arnForObjects('*'),
                resultsBucket.arnForObjects('*'),
              ],
            }),
            // DynamoDB permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:UpdateItem',
                'dynamodb:GetItem',
              ],
              resources: [jobTable.tableArn],
            }),
            // SNS permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [notificationTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // ========================================
    // Step Functions State Machine
    // ========================================

    /**
     * Step Functions workflow definition
     * Implements intelligent document routing and error handling
     */
    const processDocumentChoice = new stepfunctions.Choice(this, 'ProcessDocumentChoice', {
      comment: 'Determine processing type based on document characteristics',
    });

    // Textract Analyze Document task for forms and tables
    const analyzeDocumentTask = new tasks.CallAwsService(this, 'AnalyzeDocument', {
      service: 'textract',
      action: 'analyzeDocument',
      parameters: {
        'Document': {
          'S3Object': {
            'Bucket': stepfunctions.JsonPath.stringAt('$.bucket'),
            'Name': stepfunctions.JsonPath.stringAt('$.key'),
          },
        },
        'FeatureTypes': ['TABLES', 'FORMS', 'SIGNATURES'],
      },
      resultPath: '$.textractResult',
      comment: 'Analyze document for forms, tables, and signatures',
    });

    // Textract Detect Document Text task for simple text extraction
    const detectTextTask = new tasks.CallAwsService(this, 'DetectText', {
      service: 'textract',
      action: 'detectDocumentText',
      parameters: {
        'Document': {
          'S3Object': {
            'Bucket': stepfunctions.JsonPath.stringAt('$.bucket'),
            'Name': stepfunctions.JsonPath.stringAt('$.key'),
          },
        },
      },
      resultPath: '$.textractResult',
      comment: 'Extract text from document',
    });

    // Store results in S3
    const storeResultsTask = new tasks.CallAwsService(this, 'StoreResults', {
      service: 's3',
      action: 'putObject',
      parameters: {
        'Bucket': resultsBucket.bucketName,
        'Key': stepfunctions.JsonPath.format('{}/results.json', stepfunctions.JsonPath.stringAt('$.jobId')),
        'Body': stepfunctions.JsonPath.entirePayload,
      },
      comment: 'Store processing results in S3',
    });

    // Update job status to completed
    const updateJobStatusTask = new tasks.CallAwsService(this, 'UpdateJobStatus', {
      service: 'dynamodb',
      action: 'putItem',
      parameters: {
        'TableName': jobTable.tableName,
        'Item': {
          'JobId': {
            'S': stepfunctions.JsonPath.stringAt('$.jobId'),
          },
          'Status': {
            'S': 'COMPLETED',
          },
          'ProcessedAt': {
            'S': stepfunctions.JsonPath.stringAt('$$.State.EnteredTime'),
          },
          'ResultsLocation': {
            'S': stepfunctions.JsonPath.format(
              's3://{}/{}/results.json',
              resultsBucket.bucketName,
              stepfunctions.JsonPath.stringAt('$.jobId')
            ),
          },
        },
      },
      comment: 'Update job status to completed',
    });

    // Send success notification
    const sendNotificationTask = new tasks.CallAwsService(this, 'SendNotification', {
      service: 'sns',
      action: 'publish',
      parameters: {
        'TopicArn': notificationTopic.topicArn,
        'Message': stepfunctions.JsonPath.format(
          'Document processing completed for job {}',
          stepfunctions.JsonPath.stringAt('$.jobId')
        ),
        'Subject': 'Document Processing Complete',
      },
      comment: 'Send completion notification',
    });

    // Handle processing failures
    const processingFailedTask = new tasks.CallAwsService(this, 'ProcessingFailed', {
      service: 'dynamodb',
      action: 'putItem',
      parameters: {
        'TableName': jobTable.tableName,
        'Item': {
          'JobId': {
            'S': stepfunctions.JsonPath.stringAt('$.jobId'),
          },
          'Status': {
            'S': 'FAILED',
          },
          'FailedAt': {
            'S': stepfunctions.JsonPath.stringAt('$$.State.EnteredTime'),
          },
          'Error': {
            'S': stepfunctions.JsonPath.stringAt('$.Error'),
          },
        },
      },
      comment: 'Update job status to failed',
    });

    // Send failure notification
    const notifyFailureTask = new tasks.CallAwsService(this, 'NotifyFailure', {
      service: 'sns',
      action: 'publish',
      parameters: {
        'TopicArn': notificationTopic.topicArn,
        'Message': stepfunctions.JsonPath.format(
          'Document processing failed for job {}',
          stepfunctions.JsonPath.stringAt('$.jobId')
        ),
        'Subject': 'Document Processing Failed',
      },
      comment: 'Send failure notification',
    });

    // Add retry logic to Textract tasks
    analyzeDocumentTask.addRetry({
      errors: ['States.TaskFailed'],
      interval: cdk.Duration.seconds(5),
      maxAttempts: 3,
      backoffRate: 2.0,
    });

    detectTextTask.addRetry({
      errors: ['States.TaskFailed'],
      interval: cdk.Duration.seconds(5),
      maxAttempts: 3,
      backoffRate: 2.0,
    });

    // Add error handling to Textract tasks
    analyzeDocumentTask.addCatch(processingFailedTask, {
      errors: ['States.ALL'],
    });

    detectTextTask.addCatch(processingFailedTask, {
      errors: ['States.ALL'],
    });

    // Define the workflow
    const definition = processDocumentChoice
      .when(
        stepfunctions.Condition.booleanEquals('$.requiresAnalysis', true),
        analyzeDocumentTask
          .next(storeResultsTask)
          .next(updateJobStatusTask)
          .next(sendNotificationTask)
      )
      .otherwise(
        detectTextTask
          .next(storeResultsTask)
          .next(updateJobStatusTask)
          .next(sendNotificationTask)
      );

    // Chain failure handling
    processingFailedTask.next(notifyFailureTask);

    // Create CloudWatch log group for Step Functions
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: '/aws/stepfunctions/DocumentProcessingPipeline',
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create the Step Functions state machine
    const stateMachine = new stepfunctions.StateMachine(this, 'DocumentProcessingStateMachine', {
      stateMachineName: 'DocumentProcessingPipeline',
      definitionBody: stepfunctions.DefinitionBody.fromChainable(definition),
      role: stepFunctionsRole,
      timeout: cdk.Duration.minutes(30),
      comment: 'Automated document processing pipeline using Textract and Step Functions',
      logs: {
        destination: stepFunctionsLogGroup,
        level: stepfunctions.LogLevel.ALL,
        includeExecutionData: true,
      },
    });

    // ========================================
    // Lambda Function for Workflow Triggering
    // ========================================

    /**
     * Lambda function to trigger Step Functions workflow
     * Analyzes document characteristics and starts appropriate processing
     */
    const triggerFunction = new lambda.Function(this, 'DocumentProcessingTrigger', {
      functionName: 'DocumentProcessingTrigger',
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from urllib.parse import unquote_plus

stepfunctions = boto3.client('stepfunctions')

def lambda_handler(event, context):
    """
    Lambda function to trigger document processing workflow
    Analyzes document characteristics and starts Step Functions execution
    """
    
    state_machine_arn = os.environ['STATE_MACHINE_ARN']
    
    for record in event['Records']:
        try:
            # Extract S3 event information
            bucket = record['s3']['bucket']['name']
            key = unquote_plus(record['s3']['object']['key'])
            
            # Determine if document requires advanced analysis
            # PDFs and TIFFs typically contain forms/tables
            # Files with 'form' in name likely need analysis
            requires_analysis = (
                key.lower().endswith(('.pdf', '.tiff', '.tif')) or 
                'form' in key.lower() or 
                'invoice' in key.lower() or 
                'receipt' in key.lower()
            )
            
            # Generate unique job ID
            job_id = str(uuid.uuid4())
            
            # Prepare input for Step Functions
            input_data = {
                'bucket': bucket,
                'key': key,
                'jobId': job_id,
                'requiresAnalysis': requires_analysis,
                'timestamp': context.aws_request_id
            }
            
            # Start Step Functions execution
            response = stepfunctions.start_execution(
                stateMachineArn=state_machine_arn,
                name=f'doc-processing-{job_id}',
                input=json.dumps(input_data)
            )
            
            print(f'Started processing job {job_id} for document {key}')
            print(f'Execution ARN: {response["executionArn"]}')
            
        except Exception as e:
            print(f'Error processing record: {str(e)}')
            raise e
    
    return {
        'statusCode': 200,
        'body': json.dumps('Document processing triggered successfully')
    }
`),
      environment: {
        STATE_MACHINE_ARN: stateMachine.stateMachineArn,
      },
      timeout: cdk.Duration.minutes(5),
      description: 'Triggers document processing workflow when documents are uploaded to S3',
    });

    // Grant permissions to Lambda function
    stateMachine.grantStartExecution(triggerFunction);
    documentBucket.grantRead(triggerFunction);

    // ========================================
    // S3 Event Notification
    // ========================================

    /**
     * Configure S3 to trigger Lambda function on object creation
     * Filters for common document formats
     */
    documentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(triggerFunction),
      {
        suffix: '.pdf',
      }
    );

    // Add additional event notifications for other document types
    documentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(triggerFunction),
      {
        suffix: '.png',
      }
    );

    documentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(triggerFunction),
      {
        suffix: '.jpg',
      }
    );

    documentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(triggerFunction),
      {
        suffix: '.jpeg',
      }
    );

    documentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(triggerFunction),
      {
        suffix: '.tiff',
      }
    );

    // ========================================
    // Stack Outputs
    // ========================================

    /**
     * Output key information for verification and integration
     */
    new cdk.CfnOutput(this, 'DocumentBucketName', {
      value: documentBucket.bucketName,
      description: 'Name of the S3 bucket for document uploads',
      exportName: 'DocumentBucketName',
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'Name of the S3 bucket for processing results',
      exportName: 'ResultsBucketName',
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'ARN of the Step Functions state machine',
      exportName: 'StateMachineArn',
    });

    new cdk.CfnOutput(this, 'JobTableName', {
      value: jobTable.tableName,
      description: 'Name of the DynamoDB table for job tracking',
      exportName: 'JobTableName',
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS topic for notifications',
      exportName: 'NotificationTopicArn',
    });

    new cdk.CfnOutput(this, 'TriggerFunctionName', {
      value: triggerFunction.functionName,
      description: 'Name of the Lambda function that triggers processing',
      exportName: 'TriggerFunctionName',
    });

    // ========================================
    // Tags for Cost Allocation and Management
    // ========================================

    /**
     * Apply consistent tags across all resources
     */
    cdk.Tags.of(this).add('Application', 'DocumentProcessingPipeline');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'CDK');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
    cdk.Tags.of(this).add('Project', 'TextractStepFunctions');
  }
}

// ========================================
// CDK Application
// ========================================

/**
 * Main CDK Application
 * Creates and deploys the Document Processing Pipeline stack
 */
const app = new cdk.App();

// Create the stack with default configuration
new DocumentProcessingPipelineStack(app, 'DocumentProcessingPipelineStack', {
  description: 'Document Processing Pipeline with Amazon Textract and Step Functions',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  terminationProtection: false, // Set to true for production
});

// Synthesize the CloudFormation template
app.synth();