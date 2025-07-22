#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import { Duration, RemovalPolicy } from 'aws-cdk-lib';

/**
 * Stack for intelligent document summarization using Amazon Bedrock and Lambda
 * 
 * This stack creates:
 * - S3 buckets for input documents and output summaries
 * - Lambda function for document processing with Textract and Bedrock integration
 * - IAM roles with least privilege permissions
 * - S3 event notifications to trigger processing
 * - CloudWatch monitoring and logging
 * - SNS notifications for processing completion
 */
export class IntelligentDocumentSummarizationStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8).toLowerCase();

    // S3 Bucket for input documents
    const inputBucket = new s3.Bucket(this, 'DocumentInputBucket', {
      bucketName: `documents-input-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'InputDocumentCleanup',
          enabled: true,
          expiration: Duration.days(30), // Clean up input documents after 30 days
          noncurrentVersionExpiration: Duration.days(7),
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // S3 Bucket for output summaries
    const outputBucket = new s3.Bucket(this, 'SummaryOutputBucket', {
      bucketName: `summaries-output-${uniqueSuffix}`,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      lifecycleRules: [
        {
          id: 'SummaryRetention',
          enabled: true,
          expiration: Duration.days(365), // Keep summaries for 1 year
          noncurrentVersionExpiration: Duration.days(30),
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // SNS Topic for notifications
    const notificationTopic = new sns.Topic(this, 'ProcessingNotificationTopic', {
      topicName: `doc-summarization-notifications-${uniqueSuffix}`,
      displayName: 'Document Summarization Notifications',
    });

    // CloudWatch Log Group for Lambda function
    const logGroup = new logs.LogGroup(this, 'DocumentProcessorLogGroup', {
      logGroupName: `/aws/lambda/doc-summarizer-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_MONTH,
      removalPolicy: RemovalPolicy.DESTROY,
    });

    // IAM Role for Lambda function with least privilege permissions
    const lambdaRole = new iam.Role(this, 'DocumentProcessorRole', {
      roleName: `DocumentProcessorRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for document processing Lambda function with Bedrock and Textract access',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        DocumentProcessingPolicy: new iam.PolicyDocument({
          statements: [
            // S3 permissions for input and output buckets
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
              ],
              resources: [inputBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
              ],
              resources: [outputBucket.arnForObjects('*')],
            }),
            // Textract permissions for document text extraction
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'textract:DetectDocumentText',
                'textract:AnalyzeDocument',
              ],
              resources: ['*'],
              conditions: {
                StringEquals: {
                  'aws:RequestedRegion': this.region,
                },
              },
            }),
            // Bedrock permissions for AI model inference
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'bedrock:InvokeModel',
              ],
              resources: [
                `arn:aws:bedrock:${this.region}::foundation-model/anthropic.claude-3-sonnet-20240229-v1:0`,
                `arn:aws:bedrock:${this.region}::foundation-model/anthropic.claude-3-haiku-20240307-v1:0`,
              ],
            }),
            // SNS permissions for notifications
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
              ],
              resources: [notificationTopic.topicArn],
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

    // Lambda function for document processing
    const documentProcessor = new lambda.Function(this, 'DocumentProcessorFunction', {
      functionName: `doc-summarizer-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from urllib.parse import unquote_plus
import logging
from typing import Dict, Any, Optional
import uuid
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
textract = boto3.client('textract')
bedrock = boto3.client('bedrock-runtime')
sns = boto3.client('sns')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for document processing
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Response dictionary with processing status
    """
    try:
        # Parse S3 event
        if 'Records' not in event or not event['Records']:
            raise ValueError("No S3 records found in event")
            
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        key = unquote_plus(record['s3']['object']['key'])
        
        logger.info(f"Processing document: {key} from bucket: {bucket}")
        
        # Validate file format
        if not _is_supported_format(key):
            logger.warning(f"Unsupported file format: {key}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'message': 'Unsupported file format',
                    'document': key
                })
            }
        
        # Extract text from document
        text_content = extract_text(bucket, key)
        
        if not text_content or len(text_content.strip()) < 50:
            logger.warning(f"Insufficient text content extracted from {key}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'message': 'Insufficient text content for summarization',
                    'document': key
                })
            }
        
        # Generate summary using Bedrock
        summary = generate_summary(text_content, key)
        
        # Store summary and metadata
        summary_location = store_summary(key, summary, text_content)
        
        # Send notification
        send_notification(key, summary_location, len(text_content), len(summary))
        
        logger.info(f"Successfully processed document: {key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'document': key,
                'summary_location': summary_location,
                'original_length': len(text_content),
                'summary_length': len(summary),
                'processing_id': str(uuid.uuid4())
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing document: {str(e)}", exc_info=True)
        
        # Send error notification if we have document info
        try:
            if 'key' in locals():
                send_error_notification(key, str(e))
        except:
            pass
            
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Internal processing error',
                'error': str(e)
            })
        }

def _is_supported_format(filename: str) -> bool:
    """Check if file format is supported by Textract"""
    supported_extensions = {'.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.tif'}
    return any(filename.lower().endswith(ext) for ext in supported_extensions)

def extract_text(bucket: str, key: str) -> str:
    """
    Extract text from document using Amazon Textract
    
    Args:
        bucket: S3 bucket name
        key: S3 object key
        
    Returns:
        Extracted text content
    """
    try:
        logger.info(f"Extracting text from {bucket}/{key}")
        
        # Check file size (Textract has limits)
        response = s3.head_object(Bucket=bucket, Key=key)
        file_size = response['ContentLength']
        
        if file_size > 10 * 1024 * 1024:  # 10MB limit for synchronous processing
            raise ValueError(f"File too large for processing: {file_size} bytes")
        
        # Extract text using Textract
        response = textract.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )
        
        # Combine text blocks
        text_blocks = []
        for block in response.get('Blocks', []):
            if block['BlockType'] == 'LINE':
                text_blocks.append(block['Text'])
        
        extracted_text = '\\n'.join(text_blocks)
        logger.info(f"Extracted {len(extracted_text)} characters from {key}")
        
        return extracted_text
        
    except Exception as e:
        logger.error(f"Text extraction failed for {key}: {str(e)}")
        raise

def generate_summary(text_content: str, document_name: str) -> str:
    """
    Generate summary using Amazon Bedrock Claude model
    
    Args:
        text_content: Text to summarize
        document_name: Original document name for context
        
    Returns:
        Generated summary
    """
    try:
        logger.info(f"Generating summary for document: {document_name}")
        
        # Truncate text if too long (Claude has token limits)
        max_chars = 15000
        if len(text_content) > max_chars:
            text_content = text_content[:max_chars] + "..."
            logger.info(f"Text truncated to {max_chars} characters for processing")
        
        # Construct prompt for summarization
        prompt = f\"\"\"You are an expert document analyst. Please provide a comprehensive summary of the following document.

Document: {document_name}

Please include in your summary:
1. **Main Topics**: The primary subjects and themes discussed
2. **Key Points**: The most important facts, findings, and conclusions
3. **Important Details**: Specific data, figures, dates, and quantitative information
4. **Actionable Items**: Any recommendations, next steps, or action items mentioned
5. **Critical Information**: Deadlines, compliance requirements, or urgent matters

Keep the summary detailed enough to be useful while being concise and well-organized.

Document Content:
{text_content}

Summary:\"\"\"
        
        # Call Bedrock Claude model
        response = bedrock.invoke_model(
            modelId='anthropic.claude-3-sonnet-20240229-v1:0',
            body=json.dumps({
                'anthropic_version': 'bedrock-2023-05-31',
                'max_tokens': 2000,
                'temperature': 0.1,
                'messages': [
                    {
                        'role': 'user',
                        'content': prompt
                    }
                ]
            })
        )
        
        # Parse response
        response_body = json.loads(response['body'].read())
        summary = response_body['content'][0]['text']
        
        logger.info(f"Generated summary of {len(summary)} characters")
        return summary
        
    except Exception as e:
        logger.error(f"Summary generation failed: {str(e)}")
        raise

def store_summary(original_key: str, summary: str, full_text: str) -> str:
    """
    Store summary and metadata in S3
    
    Args:
        original_key: Original document S3 key
        summary: Generated summary
        full_text: Original extracted text
        
    Returns:
        S3 location of stored summary
    """
    try:
        output_bucket = os.environ['OUTPUT_BUCKET']
        timestamp = datetime.utcnow().isoformat()
        
        # Create summary filename
        base_name = original_key.split('/')[-1]
        summary_key = f"summaries/{timestamp[:10]}/{base_name}.summary.txt"
        
        # Prepare summary with metadata
        summary_content = f\"\"\"DOCUMENT SUMMARY
================

Original Document: {original_key}
Processing Date: {timestamp}
Original Text Length: {len(full_text)} characters
Summary Length: {len(summary)} characters
Compression Ratio: {len(summary)/len(full_text)*100:.1f}%

SUMMARY
=======

{summary}

---
Generated by AWS Document Summarization Service
\"\"\"
        
        # Store summary in S3
        s3.put_object(
            Bucket=output_bucket,
            Key=summary_key,
            Body=summary_content,
            ContentType='text/plain',
            Metadata={
                'original-document': original_key,
                'processing-timestamp': timestamp,
                'original-length': str(len(full_text)),
                'summary-length': str(len(summary)),
                'compression-ratio': f"{len(summary)/len(full_text)*100:.1f}%"
            },
            ServerSideEncryption='AES256'
        )
        
        summary_location = f"s3://{output_bucket}/{summary_key}"
        logger.info(f"Summary stored at: {summary_location}")
        
        return summary_location
        
    except Exception as e:
        logger.error(f"Failed to store summary: {str(e)}")
        raise

def send_notification(document_key: str, summary_location: str, 
                     original_length: int, summary_length: int) -> None:
    """Send success notification via SNS"""
    try:
        topic_arn = os.environ['NOTIFICATION_TOPIC_ARN']
        
        message = {
            'status': 'SUCCESS',
            'document': document_key,
            'summary_location': summary_location,
            'original_length': original_length,
            'summary_length': summary_length,
            'compression_ratio': f"{summary_length/original_length*100:.1f}%",
            'timestamp': datetime.utcnow().isoformat()
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message, indent=2),
            Subject=f"Document Processing Complete: {document_key.split('/')[-1]}"
        )
        
        logger.info(f"Success notification sent for {document_key}")
        
    except Exception as e:
        logger.warning(f"Failed to send notification: {str(e)}")

def send_error_notification(document_key: str, error_message: str) -> None:
    """Send error notification via SNS"""
    try:
        topic_arn = os.environ['NOTIFICATION_TOPIC_ARN']
        
        message = {
            'status': 'ERROR',
            'document': document_key,
            'error': error_message,
            'timestamp': datetime.utcnow().isoformat()
        }
        
        sns.publish(
            TopicArn=topic_arn,
            Message=json.dumps(message, indent=2),
            Subject=f"Document Processing Failed: {document_key.split('/')[-1]}"
        )
        
        logger.info(f"Error notification sent for {document_key}")
        
    except Exception as e:
        logger.warning(f"Failed to send error notification: {str(e)}")
      `),
      timeout: Duration.minutes(5),
      memorySize: 1024,
      reservedConcurrentExecutions: 10, // Limit concurrent executions to control costs
      environment: {
        OUTPUT_BUCKET: outputBucket.bucketName,
        NOTIFICATION_TOPIC_ARN: notificationTopic.topicArn,
        LOG_LEVEL: 'INFO',
      },
      logGroup: logGroup,
      deadLetterQueue: new sqs.Queue(this, 'DocumentProcessorDLQ', {
        queueName: `doc-processor-dlq-${uniqueSuffix}`,
        retentionPeriod: Duration.days(14),
      }),
      retryAttempts: 2,
    });

    // Configure S3 event notification to trigger Lambda
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(documentProcessor),
      {
        prefix: 'documents/', // Only process files in the documents/ prefix
        suffix: '.pdf', // Process PDF files
      }
    );

    // Also handle other supported formats
    const supportedFormats = ['.png', '.jpg', '.jpeg', '.tiff', '.tif'];
    supportedFormats.forEach(format => {
      inputBucket.addEventNotification(
        s3.EventType.OBJECT_CREATED,
        new s3n.LambdaDestination(documentProcessor),
        {
          prefix: 'documents/',
          suffix: format,
        }
      );
    });

    // CloudWatch Dashboard for monitoring
    const dashboard = new cloudwatch.Dashboard(this, 'DocumentProcessingDashboard', {
      dashboardName: `document-summarization-${uniqueSuffix}`,
      widgets: [
        [
          new cloudwatch.GraphWidget({
            title: 'Lambda Function Metrics',
            left: [
              documentProcessor.metricInvocations({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
              documentProcessor.metricErrors({
                statistic: 'Sum',
                period: Duration.minutes(5),
              }),
            ],
            right: [
              documentProcessor.metricDuration({
                statistic: 'Average',
                period: Duration.minutes(5),
              }),
            ],
          }),
        ],
        [
          new cloudwatch.GraphWidget({
            title: 'S3 Bucket Objects',
            left: [
              inputBucket.metricNumberOfObjects({
                statistic: 'Average',
                period: Duration.hours(1),
              }),
              outputBucket.metricNumberOfObjects({
                statistic: 'Average',
                period: Duration.hours(1),
              }),
            ],
          }),
        ],
      ],
    });

    // CloudWatch Alarms for monitoring
    const errorAlarm = new cloudwatch.Alarm(this, 'DocumentProcessingErrorAlarm', {
      alarmName: `document-processing-errors-${uniqueSuffix}`,
      alarmDescription: 'Alert when document processing has high error rate',
      metric: documentProcessor.metricErrors({
        statistic: 'Sum',
        period: Duration.minutes(5),
      }),
      threshold: 5,
      evaluationPeriods: 2,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });

    // Add alarm action to SNS topic
    errorAlarm.addAlarmAction(new cw_actions.SnsAction(notificationTopic));

    // Outputs for easy access to resources
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'S3 bucket for uploading documents to be processed',
      exportName: `${this.stackName}-InputBucket`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'S3 bucket containing generated summaries',
      exportName: `${this.stackName}-OutputBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: documentProcessor.functionName,
      description: 'Lambda function processing documents',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'SNS topic for processing notifications',
      exportName: `${this.stackName}-NotificationTopic`,
    });

    new cdk.CfnOutput(this, 'DashboardURL', {
      value: `https://${this.region}.console.aws.amazon.com/cloudwatch/home?region=${this.region}#dashboards:name=${dashboard.dashboardName}`,
      description: 'CloudWatch dashboard for monitoring document processing',
    });

    // Tags for resource management
    cdk.Tags.of(this).add('Project', 'IntelligentDocumentSummarization');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('CostCenter', 'DocumentProcessing');
  }
}

// Create the CDK App
const app = new cdk.App();

// Deploy the stack
new IntelligentDocumentSummarizationStack(app, 'IntelligentDocumentSummarizationStack', {
  description: 'Intelligent document summarization using Amazon Bedrock and Lambda (uksb-1tupboc58)',
  
  // Environment configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Stack-level tags
  tags: {
    Application: 'DocumentSummarization',
    CreatedBy: 'AWS-CDK',
    Repository: 'intelligent-document-summarization-recipe',
  },
});