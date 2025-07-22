import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

/**
 * CDK Stack for Amazon Comprehend Natural Language Processing Pipeline
 * 
 * This stack creates a complete NLP infrastructure including:
 * - S3 buckets for input and output data storage
 * - Lambda function for real-time text processing with Comprehend
 * - IAM roles with least privilege access for security
 * - CloudWatch logs for monitoring and debugging
 * - S3 event notifications for automated processing
 */
export class ComprehendNlpPipelineStack extends cdk.Stack {
  public readonly inputBucket: s3.Bucket;
  public readonly outputBucket: s3.Bucket;
  public readonly processingFunction: lambda.Function;
  public readonly comprehendRole: iam.Role;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource naming
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Create S3 bucket for input data (customer feedback, reviews, etc.)
    this.inputBucket = new s3.Bucket(this, 'ComprehendInputBucket', {
      bucketName: `comprehend-nlp-input-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      eventBridgeEnabled: true,
      lifecycleRules: [{
        id: 'DeleteOldInputFiles',
        enabled: true,
        expiration: cdk.Duration.days(30),
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(1)
      }]
    });

    // Create S3 bucket for processed output data
    this.outputBucket = new s3.Bucket(this, 'ComprehendOutputBucket', {
      bucketName: `comprehend-nlp-output-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
      eventBridgeEnabled: true,
      lifecycleRules: [{
        id: 'DeleteOldOutputFiles',
        enabled: true,
        expiration: cdk.Duration.days(90),
        noncurrentVersionExpiration: cdk.Duration.days(30),
        abortIncompleteMultipartUploadAfter: cdk.Duration.days(1)
      }]
    });

    // Create IAM role for Amazon Comprehend batch processing
    this.comprehendRole = new iam.Role(this, 'ComprehendServiceRole', {
      roleName: `ComprehendServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('comprehend.amazonaws.com'),
      description: 'Service role for Amazon Comprehend batch processing jobs',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonComprehendServiceRole-AnalysisJob')
      ],
      inlinePolicies: {
        ComprehendS3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket'
              ],
              resources: [
                this.inputBucket.bucketArn,
                this.inputBucket.arnForObjects('*')
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject'
              ],
              resources: [
                this.outputBucket.arnForObjects('*')
              ]
            })
          ]
        })
      }
    });

    // Create CloudWatch Log Group for Lambda function
    const lambdaLogGroup = new logs.LogGroup(this, 'ComprehendProcessorLogGroup', {
      logGroupName: `/aws/lambda/comprehend-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.TWO_WEEKS,
      removalPolicy: cdk.RemovalPolicy.DESTROY
    });

    // Create IAM role for Lambda function with Comprehend permissions
    const lambdaRole = new iam.Role(this, 'ComprehendLambdaRole', {
      roleName: `ComprehendLambdaRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Execution role for Comprehend text processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole')
      ],
      inlinePolicies: {
        ComprehendAnalysisPolicy: new iam.PolicyDocument({
          statements: [
            // Comprehend permissions for real-time analysis
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'comprehend:DetectSentiment',
                'comprehend:DetectEntities',
                'comprehend:DetectKeyPhrases',
                'comprehend:DetectLanguage',
                'comprehend:DetectSyntax',
                'comprehend:DetectTargetedSentiment',
                'comprehend:ClassifyDocument'
              ],
              resources: ['*']
            }),
            // Comprehend batch job permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'comprehend:StartDocumentClassificationJob',
                'comprehend:StartEntitiesDetectionJob',
                'comprehend:StartKeyPhrasesDetectionJob',
                'comprehend:StartSentimentDetectionJob',
                'comprehend:DescribeDocumentClassificationJob',
                'comprehend:DescribeEntitiesDetectionJob',
                'comprehend:DescribeKeyPhrasesDetectionJob',
                'comprehend:DescribeSentimentDetectionJob'
              ],
              resources: ['*']
            }),
            // S3 permissions for data access
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket'
              ],
              resources: [
                this.inputBucket.bucketArn,
                this.inputBucket.arnForObjects('*')
              ]
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:DeleteObject'
              ],
              resources: [
                this.outputBucket.arnForObjects('*')
              ]
            }),
            // CloudWatch Logs permissions
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'logs:CreateLogGroup',
                'logs:CreateLogStream',
                'logs:PutLogEvents'
              ],
              resources: [lambdaLogGroup.logGroupArn]
            })
          ]
        })
      }
    });

    // Create Lambda function for real-time text processing
    this.processingFunction = new lambda.Function(this, 'ComprehendProcessor', {
      functionName: `comprehend-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'lambda_function.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      reservedConcurrentExecutions: 10,
      logGroup: lambdaLogGroup,
      environment: {
        INPUT_BUCKET: this.inputBucket.bucketName,
        OUTPUT_BUCKET: this.outputBucket.bucketName,
        COMPREHEND_ROLE_ARN: this.comprehendRole.roleArn,
        LOG_LEVEL: 'INFO'
      },
      description: 'Processes text using Amazon Comprehend for sentiment analysis, entity detection, and key phrase extraction',
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
import logging
from datetime import datetime
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda handler for processing text with Amazon Comprehend.
    
    Supports both S3 event triggers and direct API invocations.
    Performs comprehensive NLP analysis including sentiment, entities, and key phrases.
    
    Args:
        event: Lambda event data (S3 event or direct invocation)
        context: Lambda context object
        
    Returns:
        Dict containing analysis results or error information
    """
    try:
        logger.info(f"Processing event: {json.dumps(event, default=str)}")
        
        # Extract text and bucket information from event
        text, output_bucket = extract_text_from_event(event)
        
        if not text:
            logger.error("No text provided for processing")
            return create_error_response(400, 'No text provided')
        
        logger.info(f"Processing text of length: {len(text)}")
        
        # Perform comprehensive NLP analysis
        results = analyze_text_with_comprehend(text)
        
        # Save results to S3 if output bucket specified
        if output_bucket:
            save_results_to_s3(results, output_bucket)
        
        logger.info("Text processing completed successfully")
        return create_success_response(results)
        
    except Exception as e:
        logger.error(f"Error processing text: {str(e)}", exc_info=True)
        return create_error_response(500, str(e))

def extract_text_from_event(event: Dict[str, Any]) -> tuple[str, str]:
    """Extract text and output bucket from Lambda event."""
    if 'Records' in event:
        # S3 event trigger
        record = event['Records'][0]
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        logger.info(f"Processing S3 object: s3://{bucket}/{key}")
        
        response = s3.get_object(Bucket=bucket, Key=key)
        text = response['Body'].read().decode('utf-8')
        output_bucket = os.environ.get('OUTPUT_BUCKET', '')
        
    else:
        # Direct invocation
        text = event.get('text', '')
        output_bucket = event.get('output_bucket', os.environ.get('OUTPUT_BUCKET', ''))
    
    return text, output_bucket

def analyze_text_with_comprehend(text: str) -> Dict[str, Any]:
    """Perform comprehensive text analysis using Amazon Comprehend."""
    # Detect language first
    logger.info("Detecting text language")
    language_response = comprehend.detect_dominant_language(Text=text)
    language_code = language_response['Languages'][0]['LanguageCode']
    confidence = language_response['Languages'][0]['Score']
    
    logger.info(f"Detected language: {language_code} (confidence: {confidence:.3f})")
    
    # Perform sentiment analysis
    logger.info("Analyzing sentiment")
    sentiment_response = comprehend.detect_sentiment(
        Text=text,
        LanguageCode=language_code
    )
    
    # Extract named entities
    logger.info("Extracting entities")
    entities_response = comprehend.detect_entities(
        Text=text,
        LanguageCode=language_code
    )
    
    # Extract key phrases
    logger.info("Extracting key phrases")
    keyphrases_response = comprehend.detect_key_phrases(
        Text=text,
        LanguageCode=language_code
    )
    
    # Compile comprehensive results
    results = {
        'timestamp': datetime.now().isoformat(),
        'text': text,
        'text_length': len(text),
        'language': {
            'code': language_code,
            'confidence': confidence
        },
        'sentiment': {
            'sentiment': sentiment_response['Sentiment'],
            'scores': sentiment_response['SentimentScore']
        },
        'entities': entities_response['Entities'],
        'key_phrases': keyphrases_response['KeyPhrases'],
        'processing_info': {
            'function_name': os.environ.get('AWS_LAMBDA_FUNCTION_NAME'),
            'request_id': context.aws_request_id if 'context' in locals() else 'unknown'
        }
    }
    
    logger.info(f"Analysis complete - Sentiment: {results['sentiment']['sentiment']}, "
               f"Entities: {len(results['entities'])}, Key Phrases: {len(results['key_phrases'])}")
    
    return results

def save_results_to_s3(results: Dict[str, Any], bucket: str) -> None:
    """Save analysis results to S3 bucket."""
    output_key = f"processed/{datetime.now().strftime('%Y/%m/%d')}/{uuid.uuid4()}.json"
    
    logger.info(f"Saving results to s3://{bucket}/{output_key}")
    
    s3.put_object(
        Bucket=bucket,
        Key=output_key,
        Body=json.dumps(results, indent=2, default=str),
        ContentType='application/json',
        Metadata={
            'processing-timestamp': results['timestamp'],
            'sentiment': results['sentiment']['sentiment'],
            'language': results['language']['code']
        }
    )

def create_success_response(results: Dict[str, Any]) -> Dict[str, Any]:
    """Create successful Lambda response."""
    return {
        'statusCode': 200,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps(results, default=str)
    }

def create_error_response(status_code: int, error_message: str) -> Dict[str, Any]:
    """Create error Lambda response."""
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': error_message,
            'timestamp': datetime.now().isoformat()
        })
    }
      `)
    });

    // Configure S3 event notification to trigger Lambda processing
    this.inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.processingFunction),
      {
        prefix: 'input/',
        suffix: '.txt'
      }
    );

    // Create CloudFormation outputs for easy reference
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: this.inputBucket.bucketName,
      description: 'Name of the S3 bucket for input text files',
      exportName: `${this.stackName}-InputBucket`
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: this.outputBucket.bucketName,
      description: 'Name of the S3 bucket for processed results',
      exportName: `${this.stackName}-OutputBucket`
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Name of the Lambda function for text processing',
      exportName: `${this.stackName}-ProcessingFunction`
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionArn', {
      value: this.processingFunction.functionArn,
      description: 'ARN of the Lambda function for integration purposes',
      exportName: `${this.stackName}-ProcessingFunctionArn`
    });

    new cdk.CfnOutput(this, 'ComprehendRoleArn', {
      value: this.comprehendRole.roleArn,
      description: 'ARN of the IAM role for Comprehend batch processing',
      exportName: `${this.stackName}-ComprehendRole`
    });

    // Add tags to all resources in the stack
    cdk.Tags.of(this).add('Project', 'ComprehendNlpPipeline');
    cdk.Tags.of(this).add('Component', 'NaturalLanguageProcessing');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
  }
}