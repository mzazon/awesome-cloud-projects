#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as stepfunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as stepfunctionsTasks from 'aws-cdk-lib/aws-stepfunctions-tasks';
import * as logs from 'aws-cdk-lib/aws-logs';
import { RemovalPolicy } from 'aws-cdk-lib';

/**
 * CDK Stack for Document Analysis with Amazon Textract
 * 
 * This stack implements an intelligent document processing pipeline using:
 * - Amazon Textract for OCR and document analysis
 * - Step Functions for workflow orchestration
 * - Lambda functions for processing logic
 * - S3 for document storage and results
 * - DynamoDB for metadata tracking
 * - SNS for notifications
 */
export class DocumentAnalysisTextractStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Fn.select(2, cdk.Fn.split('-', cdk.Fn.select(2, cdk.Fn.split('/', this.stackId))));

    // Create S3 buckets for document input and output
    const inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `textract-input-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldObjects',
          enabled: true,
          expiration: cdk.Duration.days(30)
        }
      ]
    });

    const outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `textract-output-${uniqueSuffix}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldResults',
          enabled: true,
          expiration: cdk.Duration.days(90)
        }
      ]
    });

    // Create DynamoDB table for document metadata
    const metadataTable = new dynamodb.Table(this, 'MetadataTable', {
      tableName: `textract-metadata-${uniqueSuffix}`,
      partitionKey: {
        name: 'documentId',
        type: dynamodb.AttributeType.STRING
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: RemovalPolicy.DESTROY,
      pointInTimeRecovery: false,
      encryption: dynamodb.TableEncryption.AWS_MANAGED
    });

    // Create SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `textract-notifications-${uniqueSuffix}`,
      displayName: 'Textract Document Processing Notifications'
    });

    // Create IAM role for Lambda functions and Step Functions
    const executionRole = new iam.Role(this, 'TextractExecutionRole', {
      roleName: `textract-execution-role-${uniqueSuffix}`,
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('states.amazonaws.com')
      ),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        TextractPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'textract:AnalyzeDocument',
                'textract:DetectDocumentText',
                'textract:StartDocumentAnalysis',
                'textract:GetDocumentAnalysis'
              ],
              resources: ['*']
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:PutObject',
                's3:DeleteObject'
              ],
              resources: [
                inputBucket.bucketArn + '/*',
                outputBucket.bucketArn + '/*'
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:ListBucket'
              ],
              resources: [
                inputBucket.bucketArn,
                outputBucket.bucketArn
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:Scan',
                'dynamodb:Query'
              ],
              resources: [metadataTable.tableArn]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish'
              ],
              resources: [notificationTopic.topicArn]
            })
          ]
        })
      }
    });

    // Create CloudWatch Log Groups for Lambda functions
    const classifierLogGroup = new logs.LogGroup(this, 'ClassifierLogGroup', {
      logGroupName: `/aws/lambda/textract-classifier-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const processorLogGroup = new logs.LogGroup(this, 'ProcessorLogGroup', {
      logGroupName: `/aws/lambda/textract-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const asyncResultsLogGroup = new logs.LogGroup(this, 'AsyncResultsLogGroup', {
      logGroupName: `/aws/lambda/textract-async-results-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const queryLogGroup = new logs.LogGroup(this, 'QueryLogGroup', {
      logGroupName: `/aws/lambda/textract-query-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    // Document Classifier Lambda Function
    const documentClassifierFunction = new lambda.Function(this, 'DocumentClassifierFunction', {
      functionName: `textract-classifier-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: executionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logGroup: classifierLogGroup,
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName,
        METADATA_TABLE: metadataTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from urllib.parse import unquote_plus

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse S3 event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        # Get object metadata
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        # Determine processing type based on file size and type
        # Files under 5MB for synchronous, larger for asynchronous
        processing_type = 'sync' if file_size < 5 * 1024 * 1024 else 'async'
        
        # Determine document type based on filename
        doc_type = 'invoice' if 'invoice' in key.lower() else 'form' if 'form' in key.lower() else 'general'
        
        return {
            'statusCode': 200,
            'body': {
                'bucket': bucket,
                'key': key,
                'processingType': processing_type,
                'documentType': doc_type,
                'fileSize': file_size
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Textract Processor Lambda Function
    const textractProcessorFunction = new lambda.Function(this, 'TextractProcessorFunction', {
      functionName: `textract-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: executionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      logGroup: processorLogGroup,
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName,
        METADATA_TABLE: metadataTable.tableName,
        SNS_TOPIC_ARN: notificationTopic.topicArn,
        EXECUTION_ROLE_ARN: executionRole.roleArn
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

def lambda_handler(event, context):
    try:
        # Get input parameters
        bucket = event['bucket']
        key = event['key']
        processing_type = event['processingType']
        document_type = event['documentType']
        
        document_id = str(uuid.uuid4())
        
        # Process document based on type
        if processing_type == 'sync':
            result = process_sync_document(bucket, key, document_type)
        else:
            result = process_async_document(bucket, key, document_type)
        
        # Store metadata in DynamoDB
        store_metadata(document_id, bucket, key, document_type, result)
        
        # Send notification
        send_notification(document_id, document_type, result.get('status', 'completed'))
        
        return {
            'statusCode': 200,
            'body': {
                'documentId': document_id,
                'processingType': processing_type,
                'result': result
            }
        }
    except Exception as e:
        print(f"Error: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_sync_document(bucket, key, document_type):
    """Process single-page document synchronously"""
    try:
        # Determine features based on document type
        features = ['TABLES', 'FORMS'] if document_type in ['invoice', 'form'] else ['TABLES']
        
        response = textract.analyze_document(
            Document={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features
        )
        
        # Extract and structure data
        extracted_data = extract_structured_data(response)
        
        # Save results to S3
        output_key = f"results/{key.split('/')[-1]}-analysis.json"
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(extracted_data, indent=2),
            ContentType='application/json'
        )
        
        return {
            'status': 'completed',
            'outputLocation': f"s3://{os.environ['OUTPUT_BUCKET']}/{output_key}",
            'extractedData': extracted_data
        }
    except Exception as e:
        print(f"Sync processing error: {str(e)}")
        raise

def process_async_document(bucket, key, document_type):
    """Start asynchronous document processing"""
    try:
        features = ['TABLES', 'FORMS'] if document_type in ['invoice', 'form'] else ['TABLES']
        
        response = textract.start_document_analysis(
            DocumentLocation={'S3Object': {'Bucket': bucket, 'Name': key}},
            FeatureTypes=features,
            NotificationChannel={
                'SNSTopicArn': os.environ['SNS_TOPIC_ARN'],
                'RoleArn': os.environ['EXECUTION_ROLE_ARN']
            }
        )
        
        return {
            'status': 'in_progress',
            'jobId': response['JobId']
        }
    except Exception as e:
        print(f"Async processing error: {str(e)}")
        raise

def extract_structured_data(response):
    """Extract structured data from Textract response"""
    blocks = response['Blocks']
    
    # Extract text lines
    lines = []
    tables = []
    forms = []
    
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'TABLE':
            tables.append(extract_table_data(block, blocks))
        elif block['BlockType'] == 'KEY_VALUE_SET':
            forms.append(extract_form_data(block, blocks))
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {})
    }

def extract_table_data(table_block, all_blocks):
    """Extract table structure and data"""
    return {
        'id': table_block['Id'],
        'confidence': table_block.get('Confidence', 0),
        'geometry': table_block.get('Geometry', {})
    }

def extract_form_data(form_block, all_blocks):
    """Extract form key-value pairs"""
    return {
        'id': form_block['Id'],
        'confidence': form_block.get('Confidence', 0),
        'entity_types': form_block.get('EntityTypes', [])
    }

def store_metadata(document_id, bucket, key, document_type, result):
    """Store document metadata in DynamoDB"""
    table = dynamodb.Table(os.environ['METADATA_TABLE'])
    
    table.put_item(
        Item={
            'documentId': document_id,
            'bucket': bucket,
            'key': key,
            'documentType': document_type,
            'processingStatus': result.get('status', 'completed'),
            'jobId': result.get('jobId'),
            'outputLocation': result.get('outputLocation'),
            'timestamp': datetime.utcnow().isoformat(),
            'extractedData': result.get('extractedData')
        }
    )

def send_notification(document_id, document_type, status):
    """Send processing notification"""
    message = {
        'documentId': document_id,
        'documentType': document_type,
        'status': status,
        'timestamp': datetime.utcnow().isoformat()
    }
    
    sns.publish(
        TopicArn=os.environ['SNS_TOPIC_ARN'],
        Message=json.dumps(message),
        Subject=f'Document Processing {status.title()}'
    )
      `)
    });

    // Async Results Processor Lambda Function
    const asyncResultsProcessorFunction = new lambda.Function(this, 'AsyncResultsProcessorFunction', {
      functionName: `textract-async-results-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: executionRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      logGroup: asyncResultsLogGroup,
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName,
        METADATA_TABLE: metadataTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from datetime import datetime

textract = boto3.client('textract')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        # Parse SNS message
        sns_message = json.loads(event['Records'][0]['Sns']['Message'])
        job_id = sns_message['JobId']
        status = sns_message['Status']
        
        if status == 'SUCCEEDED':
            # Get results from Textract
            response = textract.get_document_analysis(JobId=job_id)
            
            # Process results
            extracted_data = extract_structured_data(response)
            
            # Save to S3
            output_key = f"async-results/{job_id}-analysis.json"
            s3.put_object(
                Bucket=os.environ['OUTPUT_BUCKET'],
                Key=output_key,
                Body=json.dumps(extracted_data, indent=2),
                ContentType='application/json'
            )
            
            # Update DynamoDB
            update_document_metadata(job_id, 'completed', output_key)
            
            print(f"Successfully processed job {job_id}")
        else:
            # Update DynamoDB with failed status
            update_document_metadata(job_id, 'failed', None)
            print(f"Job {job_id} failed")
            
        return {'statusCode': 200}
    except Exception as e:
        print(f"Error: {str(e)}")
        return {'statusCode': 500}

def extract_structured_data(response):
    """Extract structured data from Textract response"""
    blocks = response['Blocks']
    
    lines = []
    tables = []
    forms = []
    
    for block in blocks:
        if block['BlockType'] == 'LINE':
            lines.append({
                'text': block.get('Text', ''),
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'TABLE':
            tables.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
        elif block['BlockType'] == 'KEY_VALUE_SET':
            forms.append({
                'id': block['Id'],
                'confidence': block.get('Confidence', 0)
            })
    
    return {
        'text_lines': lines,
        'tables': tables,
        'forms': forms,
        'document_metadata': response.get('DocumentMetadata', {})
    }

def update_document_metadata(job_id, status, output_location):
    """Update document metadata in DynamoDB"""
    table = dynamodb.Table(os.environ['METADATA_TABLE'])
    
    # Find document by job ID
    response = table.scan(
        FilterExpression='jobId = :jid',
        ExpressionAttributeValues={':jid': job_id}
    )
    
    if response['Items']:
        document_id = response['Items'][0]['documentId']
        
        table.update_item(
            Key={'documentId': document_id},
            UpdateExpression='SET processingStatus = :status, outputLocation = :location, completedAt = :timestamp',
            ExpressionAttributeValues={
                ':status': status,
                ':location': output_location,
                ':timestamp': datetime.utcnow().isoformat()
            }
        )
      `)
    });

    // Document Query Lambda Function
    const documentQueryFunction = new lambda.Function(this, 'DocumentQueryFunction', {
      functionName: `textract-query-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: executionRole,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256,
      logGroup: queryLogGroup,
      environment: {
        METADATA_TABLE: metadataTable.tableName
      },
      code: lambda.Code.fromInline(`
import json
import boto3
from datetime import datetime

dynamodb = boto3.resource('dynamodb')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Get query parameters
        document_id = event.get('documentId')
        document_type = event.get('documentType')
        
        table = dynamodb.Table(os.environ['METADATA_TABLE'])
        
        if document_id:
            # Query specific document
            response = table.get_item(Key={'documentId': document_id})
            if 'Item' in response:
                return {
                    'statusCode': 200,
                    'body': json.dumps(response['Item'], default=str)
                }
            else:
                return {
                    'statusCode': 404,
                    'body': json.dumps({'error': 'Document not found'})
                }
        
        elif document_type:
            # Query by document type
            response = table.scan(
                FilterExpression='documentType = :dt',
                ExpressionAttributeValues={':dt': document_type}
            )
            return {
                'statusCode': 200,
                'body': json.dumps(response['Items'], default=str)
            }
        
        else:
            # Return all documents
            response = table.scan()
            return {
                'statusCode': 200,
                'body': json.dumps(response['Items'], default=str)
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
      `)
    });

    // Subscribe async results processor to SNS topic
    notificationTopic.addSubscription(
      new snsSubscriptions.LambdaSubscription(asyncResultsProcessorFunction)
    );

    // Create Step Functions State Machine
    const classifyDocumentTask = new stepfunctionsTasks.LambdaInvoke(this, 'ClassifyDocumentTask', {
      lambdaFunction: documentClassifierFunction,
      outputPath: '$.Payload'
    });

    const processDocumentTask = new stepfunctionsTasks.LambdaInvoke(this, 'ProcessDocumentTask', {
      lambdaFunction: textractProcessorFunction,
      outputPath: '$.Payload'
    });

    const waitForAsyncCompletion = new stepfunctions.Wait(this, 'WaitForAsyncCompletion', {
      time: stepfunctions.WaitTime.duration(cdk.Duration.seconds(30))
    });

    const checkAsyncStatusTask = new stepfunctionsTasks.CallAwsService(this, 'CheckAsyncStatusTask', {
      service: 'textract',
      action: 'getDocumentAnalysis',
      parameters: {
        'JobId.$': '$.body.result.jobId'
      },
      iamResources: ['*']
    });

    const processingComplete = new stepfunctions.Pass(this, 'ProcessingComplete', {
      result: stepfunctions.Result.fromString('Document processing completed successfully')
    });

    const processingFailed = new stepfunctions.Fail(this, 'ProcessingFailed', {
      error: 'DocumentProcessingFailed',
      cause: 'Textract processing failed'
    });

    // Choice state for processing type
    const checkProcessingType = new stepfunctions.Choice(this, 'CheckProcessingType')
      .when(
        stepfunctions.Condition.stringEquals('$.body.processingType', 'async'),
        waitForAsyncCompletion
      )
      .otherwise(processingComplete);

    // Choice state for async completion
    const isAsyncComplete = new stepfunctions.Choice(this, 'IsAsyncComplete')
      .when(
        stepfunctions.Condition.stringEquals('$.JobStatus', 'SUCCEEDED'),
        processingComplete
      )
      .when(
        stepfunctions.Condition.stringEquals('$.JobStatus', 'FAILED'),
        processingFailed
      )
      .otherwise(waitForAsyncCompletion);

    // Chain the workflow
    waitForAsyncCompletion.next(checkAsyncStatusTask);
    checkAsyncStatusTask.next(isAsyncComplete);

    const definition = classifyDocumentTask
      .next(processDocumentTask)
      .next(checkProcessingType);

    // Create Step Functions State Machine
    const stepFunctionsLogGroup = new logs.LogGroup(this, 'StepFunctionsLogGroup', {
      logGroupName: `/aws/stepfunctions/textract-workflow-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: RemovalPolicy.DESTROY
    });

    const stateMachine = new stepfunctions.StateMachine(this, 'TextractWorkflow', {
      stateMachineName: `textract-workflow-${uniqueSuffix}`,
      definition,
      role: executionRole,
      logs: {
        destination: stepFunctionsLogGroup,
        level: stepfunctions.LogLevel.ALL
      }
    });

    // Configure S3 event notification to trigger the classifier
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(documentClassifierFunction),
      {
        prefix: 'documents/',
        suffix: '.pdf'
      }
    );

    // Output important values
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'S3 bucket for document uploads'
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'S3 bucket for processing results'
    });

    new cdk.CfnOutput(this, 'MetadataTableName', {
      value: metadataTable.tableName,
      description: 'DynamoDB table for document metadata'
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for processing notifications'
    });

    new cdk.CfnOutput(this, 'StateMachineArn', {
      value: stateMachine.stateMachineArn,
      description: 'Step Functions state machine ARN'
    });

    new cdk.CfnOutput(this, 'DocumentQueryFunctionArn', {
      value: documentQueryFunction.functionArn,
      description: 'Lambda function for querying document results'
    });

    // Tag all resources
    cdk.Tags.of(this).add('Project', 'DocumentAnalysisTextract');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'CDK');
  }
}

/**
 * CDK Application entry point
 */
const app = new cdk.App();

// Get deployment configuration from context or environment
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

new DocumentAnalysisTextractStack(app, 'DocumentAnalysisTextractStack', {
  env: {
    account,
    region
  },
  description: 'Document Analysis with Amazon Textract - CDK TypeScript Implementation'
});