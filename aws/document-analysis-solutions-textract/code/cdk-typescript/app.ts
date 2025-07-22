#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import {
  Stack,
  StackProps,
  Duration,
  RemovalPolicy,
  CfnOutput,
  aws_s3 as s3,
  aws_lambda as lambda,
  aws_sns as sns,
  aws_iam as iam,
  aws_logs as logs,
  aws_s3_notifications as s3n,
} from 'aws-cdk-lib';

/**
 * Properties for the Document Analysis Stack
 */
export interface DocumentAnalysisStackProps extends StackProps {
  /**
   * Environment prefix for resource naming
   * @default 'textract-analysis'
   */
  readonly environmentPrefix?: string;
  
  /**
   * Retention period for CloudWatch logs
   * @default logs.RetentionDays.ONE_WEEK
   */
  readonly logRetention?: logs.RetentionDays;
  
  /**
   * Lambda function timeout
   * @default Duration.minutes(5)
   */
  readonly lambdaTimeout?: Duration;
  
  /**
   * Lambda function memory size
   * @default 512
   */
  readonly lambdaMemorySize?: number;
  
  /**
   * Enable SNS email notifications
   * @default false
   */
  readonly enableEmailNotifications?: boolean;
  
  /**
   * Email address for SNS notifications (required if enableEmailNotifications is true)
   */
  readonly notificationEmail?: string;
}

/**
 * CDK Stack for Amazon Textract Document Analysis Solution
 * 
 * This stack creates a complete document processing pipeline using:
 * - S3 buckets for input and output storage
 * - Lambda function for document processing with Amazon Textract
 * - SNS topic for notifications
 * - IAM roles and policies with least privilege access
 * - CloudWatch logs for monitoring and debugging
 */
export class DocumentAnalysisStack extends Stack {
  
  public readonly inputBucket: s3.Bucket;
  public readonly outputBucket: s3.Bucket;
  public readonly processingFunction: lambda.Function;
  public readonly notificationTopic: sns.Topic;
  
  constructor(scope: Construct, id: string, props: DocumentAnalysisStackProps = {}) {
    super(scope, id, props);
    
    // Extract configuration with defaults
    const environmentPrefix = props.environmentPrefix || 'textract-analysis';
    const logRetention = props.logRetention || logs.RetentionDays.ONE_WEEK;
    const lambdaTimeout = props.lambdaTimeout || Duration.minutes(5);
    const lambdaMemorySize = props.lambdaMemorySize || 512;
    const enableEmailNotifications = props.enableEmailNotifications || false;
    
    // Validate email configuration
    if (enableEmailNotifications && !props.notificationEmail) {
      throw new Error('notificationEmail must be provided when enableEmailNotifications is true');
    }
    
    // Create input S3 bucket for document uploads
    this.inputBucket = new s3.Bucket(this, 'InputBucket', {
      bucketName: `${environmentPrefix}-input-${this.account}-${this.region}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: Duration.days(7),
          enabled: true,
        },
        {
          id: 'DeleteOldObjects',
          expiration: Duration.days(90),
          enabled: true,
        },
      ],
    });
    
    // Create output S3 bucket for processed results
    this.outputBucket = new s3.Bucket(this, 'OutputBucket', {
      bucketName: `${environmentPrefix}-output-${this.account}-${this.region}`,
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldResults',
          expiration: Duration.days(365),
          enabled: true,
        },
      ],
    });
    
    // Create SNS topic for notifications
    this.notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `${environmentPrefix}-notifications`,
      displayName: 'Document Analysis Notifications',
      fifo: false,
    });
    
    // Add email subscription if enabled
    if (enableEmailNotifications && props.notificationEmail) {
      this.notificationTopic.addSubscription(
        new sns.EmailSubscription(props.notificationEmail)
      );
    }
    
    // Create CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'ProcessingFunctionLogGroup', {
      logGroupName: `/aws/lambda/${environmentPrefix}-processor`,
      retention: logRetention,
      removalPolicy: RemovalPolicy.DESTROY,
    });
    
    // Create IAM role for Lambda function with least privilege permissions
    const lambdaRole = new iam.Role(this, 'ProcessingFunctionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      roleName: `${environmentPrefix}-lambda-role`,
      description: 'IAM role for Textract document processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        TextractProcessingPolicy: new iam.PolicyDocument({
          statements: [
            // Amazon Textract permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'textract:AnalyzeDocument',
                'textract:DetectDocumentText',
                'textract:AnalyzeExpense',
                'textract:AnalyzeID',
              ],
              resources: ['*'],
            }),
            // S3 bucket permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
              ],
              resources: [this.inputBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
              ],
              resources: [this.outputBucket.arnForObjects('*')],
            }),
            // SNS permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: ['sns:Publish'],
              resources: [this.notificationTopic.topicArn],
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogStream',
                'logs:PutLogEvents',
              ],
              resources: [logGroup.logGroupArn],
            }),
          ],
        }),
      },
    });
    
    // Create Lambda function for document processing
    this.processingFunction = new lambda.Function(this, 'ProcessingFunction', {
      functionName: `${environmentPrefix}-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: lambdaTimeout,
      memorySize: lambdaMemorySize,
      logGroup: logGroup,
      description: 'Processes documents using Amazon Textract and stores results in S3',
      environment: {
        OUTPUT_BUCKET: this.outputBucket.bucketName,
        SNS_TOPIC_ARN: this.notificationTopic.topicArn,
        LOG_LEVEL: 'INFO',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List
from botocore.exceptions import ClientError

# Configure logging
log_level = os.environ.get('LOG_LEVEL', 'INFO')
logging.basicConfig(level=getattr(logging, log_level))
logger = logging.getLogger(__name__)

# Initialize AWS clients
textract = boto3.client('textract')
s3 = boto3.client('s3')
sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing documents with Amazon Textract
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Dict with status code and response body
    """
    try:
        # Parse S3 event
        s3_event = event['Records'][0]['s3']
        bucket_name = s3_event['bucket']['name']
        object_key = s3_event['object']['key']
        
        logger.info(f"Processing document: {object_key} from bucket: {bucket_name}")
        
        # Validate file type
        if not is_supported_file_type(object_key):
            logger.warning(f"Unsupported file type: {object_key}")
            return create_response(400, f"Unsupported file type: {object_key}")
        
        # Process document with Textract
        extracted_data = process_document(bucket_name, object_key)
        
        # Save results to output bucket
        output_key = f"processed/{object_key.split('/')[-1]}.json"
        save_results(extracted_data, output_key)
        
        # Send success notification
        send_notification(
            f"Document processed successfully: {object_key}",
            "Document Processing Success"
        )
        
        logger.info(f"Successfully processed document: {object_key}")
        
        return create_response(200, {
            'message': 'Document processed successfully',
            'input_document': object_key,
            'output_location': f"s3://{os.environ['OUTPUT_BUCKET']}/{output_key}",
            'processing_time': datetime.now().isoformat()
        })
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}", exc_info=True)
        
        # Send error notification
        send_notification(
            f"Error processing document {object_key if 'object_key' in locals() else 'unknown'}: {str(e)}",
            "Document Processing Error"
        )
        
        return create_response(500, {'error': str(e)})

def is_supported_file_type(object_key: str) -> bool:
    """Check if file type is supported by Textract"""
    supported_extensions = ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.tif']
    return any(object_key.lower().endswith(ext) for ext in supported_extensions)

def process_document(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """
    Process document using Amazon Textract
    
    Args:
        bucket_name: S3 bucket name
        object_key: S3 object key
        
    Returns:
        Extracted document data
    """
    try:
        # Analyze document with multiple features
        response = textract.analyze_document(
            Document={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            },
            FeatureTypes=['TABLES', 'FORMS', 'QUERIES'],
            QueriesConfig={
                'Queries': [
                    {'Text': 'What is the document type?'},
                    {'Text': 'What is the total amount?'},
                    {'Text': 'What is the date?'},
                    {'Text': 'What is the invoice number?'},
                    {'Text': 'Who is the customer?'}
                ]
            }
        )
        
        # Extract structured data
        extracted_data = {
            'document_name': object_key,
            'processed_at': datetime.now().isoformat(),
            'document_metadata': response.get('DocumentMetadata', {}),
            'blocks': response.get('Blocks', []),
            'analyzed_features': ['TABLES', 'FORMS', 'QUERIES'],
            'extraction_summary': create_extraction_summary(response.get('Blocks', []))
        }
        
        logger.info(f"Successfully extracted data from document: {object_key}")
        return extracted_data
        
    except ClientError as e:
        logger.error(f"AWS service error during document processing: {e}")
        raise Exception(f"Textract processing failed: {e}")

def create_extraction_summary(blocks: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Create a summary of extracted data"""
    summary = {
        'total_blocks': len(blocks),
        'text_blocks': 0,
        'key_value_pairs': 0,
        'tables': 0,
        'queries': 0,
        'average_confidence': 0.0
    }
    
    confidences = []
    
    for block in blocks:
        block_type = block.get('BlockType', '')
        
        if block_type == 'LINE':
            summary['text_blocks'] += 1
        elif block_type == 'KEY_VALUE_SET':
            summary['key_value_pairs'] += 1
        elif block_type == 'TABLE':
            summary['tables'] += 1
        elif block_type == 'QUERY':
            summary['queries'] += 1
        
        # Collect confidence scores
        if 'Confidence' in block:
            confidences.append(block['Confidence'])
    
    # Calculate average confidence
    if confidences:
        summary['average_confidence'] = sum(confidences) / len(confidences)
    
    return summary

def save_results(data: Dict[str, Any], output_key: str) -> None:
    """Save processing results to S3"""
    try:
        s3.put_object(
            Bucket=os.environ['OUTPUT_BUCKET'],
            Key=output_key,
            Body=json.dumps(data, indent=2, default=str),
            ContentType='application/json',
            ServerSideEncryption='AES256'
        )
        logger.info(f"Results saved to: s3://{os.environ['OUTPUT_BUCKET']}/{output_key}")
        
    except ClientError as e:
        logger.error(f"Error saving results to S3: {e}")
        raise Exception(f"Failed to save results: {e}")

def send_notification(message: str, subject: str) -> None:
    """Send notification via SNS"""
    try:
        sns.publish(
            TopicArn=os.environ['SNS_TOPIC_ARN'],
            Message=message,
            Subject=subject
        )
        logger.info(f"Notification sent: {subject}")
        
    except ClientError as e:
        logger.warning(f"Failed to send notification: {e}")
        # Don't raise exception as this is not critical

def create_response(status_code: int, body: Any) -> Dict[str, Any]:
    """Create standardized Lambda response"""
    return {
        'statusCode': status_code,
        'body': json.dumps(body, default=str) if not isinstance(body, str) else body,
        'headers': {
            'Content-Type': 'application/json',
            'X-Processed-By': 'Amazon-Textract-Document-Analysis'
        }
    }
      `),
    });
    
    // Configure S3 event notification to trigger Lambda
    this.inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.processingFunction),
      {
        prefix: '',
        suffix: ''
      }
    );
    
    // Create CloudFormation outputs for easy access to resources
    new CfnOutput(this, 'InputBucketName', {
      value: this.inputBucket.bucketName,
      description: 'Name of the S3 bucket for document uploads',
      exportName: `${environmentPrefix}-input-bucket`,
    });
    
    new CfnOutput(this, 'OutputBucketName', {
      value: this.outputBucket.bucketName,
      description: 'Name of the S3 bucket for processed results',
      exportName: `${environmentPrefix}-output-bucket`,
    });
    
    new CfnOutput(this, 'ProcessingFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Name of the Lambda function for document processing',
      exportName: `${environmentPrefix}-lambda-function`,
    });
    
    new CfnOutput(this, 'NotificationTopicArn', {
      value: this.notificationTopic.topicArn,
      description: 'ARN of the SNS topic for notifications',
      exportName: `${environmentPrefix}-sns-topic`,
    });
    
    new CfnOutput(this, 'DeploymentInstructions', {
      value: 'Upload PDF, PNG, JPG, or TIFF files to the input bucket to trigger processing',
      description: 'Instructions for using the document analysis solution',
    });
  }
}

// CDK App
const app = new cdk.App();

// Get deployment configuration from context or environment
const environmentPrefix = app.node.tryGetContext('environmentPrefix') || 'textract-analysis';
const enableEmailNotifications = app.node.tryGetContext('enableEmailNotifications') === 'true';
const notificationEmail = app.node.tryGetContext('notificationEmail');

// Create the stack
new DocumentAnalysisStack(app, 'DocumentAnalysisStack', {
  environmentPrefix,
  enableEmailNotifications,
  notificationEmail,
  description: 'Amazon Textract Document Analysis Solution - Complete document processing pipeline',
  tags: {
    Project: 'DocumentAnalysis',
    Environment: 'Development',
    Service: 'Textract',
    Owner: 'DevOps',
    CostCenter: 'Engineering',
  },
});

// Synthesize the CloudFormation template
app.synth();