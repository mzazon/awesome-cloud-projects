import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Props for the TextractDocumentProcessingStack
 */
export interface TextractDocumentProcessingStackProps extends cdk.StackProps {
  /**
   * The name prefix for all resources
   * @default 'textract-processing'
   */
  readonly resourcePrefix?: string;
  
  /**
   * Whether to enable S3 bucket versioning
   * @default true
   */
  readonly enableVersioning?: boolean;
  
  /**
   * Lambda function timeout in seconds
   * @default 60
   */
  readonly lambdaTimeout?: number;
  
  /**
   * Lambda function memory size in MB
   * @default 256
   */
  readonly lambdaMemorySize?: number;
  
  /**
   * CloudWatch log retention period
   * @default logs.RetentionDays.ONE_WEEK
   */
  readonly logRetention?: logs.RetentionDays;
}

/**
 * CDK Stack for Intelligent Document Processing with Amazon Textract
 * 
 * This stack creates:
 * - S3 bucket for document storage with versioning enabled
 * - Lambda function for processing documents with Textract
 * - IAM roles and policies with least privilege access
 * - S3 event notifications to trigger Lambda processing
 * - CloudWatch log groups for monitoring
 */
export class TextractDocumentProcessingStack extends cdk.Stack {
  /**
   * The S3 bucket for storing documents and results
   */
  public readonly documentBucket: s3.Bucket;
  
  /**
   * The Lambda function for document processing
   */
  public readonly processingFunction: lambda.Function;
  
  /**
   * The IAM role for the Lambda function
   */
  public readonly lambdaRole: iam.Role;

  constructor(scope: Construct, id: string, props: TextractDocumentProcessingStackProps = {}) {
    super(scope, id, props);

    const {
      resourcePrefix = 'textract-processing',
      enableVersioning = true,
      lambdaTimeout = 60,
      lambdaMemorySize = 256,
      logRetention = logs.RetentionDays.ONE_WEEK
    } = props;

    // Create S3 bucket for document storage
    this.documentBucket = new s3.Bucket(this, 'DocumentBucket', {
      bucketName: `${resourcePrefix}-documents-${this.account}-${this.region}`,
      versioned: enableVersioning,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: cdk.Duration.days(1),
          enabled: true,
        },
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
    });

    // Create IAM role for Lambda function with least privilege access
    this.lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `${resourcePrefix}-lambda-role-${this.region}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'IAM role for Textract document processing Lambda function',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
    });

    // Add S3 permissions to Lambda role
    this.lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'S3DocumentAccess',
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:ListBucket',
        ],
        resources: [
          this.documentBucket.bucketArn,
          this.documentBucket.arnForObjects('*'),
        ],
      })
    );

    // Add Textract permissions to Lambda role
    this.lambdaRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'TextractAnalysisAccess',
        effect: iam.Effect.ALLOW,
        actions: [
          'textract:DetectDocumentText',
          'textract:AnalyzeDocument',
          'textract:GetDocumentAnalysis',
          'textract:GetDocumentTextDetection',
        ],
        resources: ['*'],
      })
    );

    // Create CloudWatch log group for Lambda function
    const logGroup = new logs.LogGroup(this, 'ProcessingFunctionLogGroup', {
      logGroupName: `/aws/lambda/${resourcePrefix}-processor`,
      retention: logRetention,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for document processing
    this.processingFunction = new lambda.Function(this, 'ProcessingFunction', {
      functionName: `${resourcePrefix}-processor`,
      description: 'Processes documents using Amazon Textract for text extraction',
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: 'lambda_function.lambda_handler',
      role: this.lambdaRole,
      timeout: cdk.Duration.seconds(lambdaTimeout),
      memorySize: lambdaMemorySize,
      logGroup: logGroup,
      environment: {
        BUCKET_NAME: this.documentBucket.bucketName,
        LOG_LEVEL: 'INFO',
        RESULTS_PREFIX: 'results/',
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib.parse
import logging
from typing import Dict, Any, List
from botocore.exceptions import ClientError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process documents uploaded to S3 using Amazon Textract
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Response with processing status and results location
    """
    # Initialize AWS clients
    s3_client = boto3.client('s3')
    textract_client = boto3.client('textract')
    
    try:
        # Get the S3 bucket and object key from the event
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(
            event['Records'][0]['s3']['object']['key'], 
            encoding='utf-8'
        )
        
        logger.info(f"Processing document: {key} from bucket: {bucket}")
        
        # Validate file type (basic check)
        valid_extensions = ['.pdf', '.png', '.jpg', '.jpeg', '.tiff', '.tif']
        if not any(key.lower().endswith(ext) for ext in valid_extensions):
            logger.warning(f"Unsupported file type: {key}")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Unsupported file type',
                    'message': f'File {key} is not a supported document type'
                })
            }
        
        # Call Textract to analyze the document
        response = textract_client.detect_document_text(
            Document={
                'S3Object': {
                    'Bucket': bucket,
                    'Name': key
                }
            }
        )
        
        # Extract text and metadata from the response
        extracted_text = ""
        confidence_scores = []
        line_count = 0
        word_count = 0
        
        for block in response['Blocks']:
            if block['BlockType'] == 'LINE':
                extracted_text += block['Text'] + '\\n'
                confidence_scores.append(block['Confidence'])
                line_count += 1
            elif block['BlockType'] == 'WORD':
                word_count += 1
        
        # Calculate average confidence
        avg_confidence = sum(confidence_scores) / len(confidence_scores) if confidence_scores else 0
        
        # Prepare comprehensive results
        results = {
            'document_info': {
                'filename': key.split('/')[-1],
                'full_path': key,
                'bucket': bucket,
                'processing_timestamp': context.aws_request_id,
                'function_version': context.function_version
            },
            'extraction_results': {
                'extracted_text': extracted_text.strip(),
                'statistics': {
                    'total_blocks': len(response['Blocks']),
                    'line_count': line_count,
                    'word_count': word_count,
                    'character_count': len(extracted_text.strip())
                },
                'confidence_metrics': {
                    'average_confidence': round(avg_confidence, 2),
                    'min_confidence': round(min(confidence_scores), 2) if confidence_scores else 0,
                    'max_confidence': round(max(confidence_scores), 2) if confidence_scores else 0
                }
            },
            'processing_status': 'completed',
            'metadata': {
                'textract_job_id': response.get('JobId'),
                'processing_time_ms': context.get_remaining_time_in_millis()
            }
        }
        
        # Save results back to S3 in results/ folder
        results_key = f"results/{key.split('/')[-1]}_results.json"
        s3_client.put_object(
            Bucket=bucket,
            Key=results_key,
            Body=json.dumps(results, indent=2, ensure_ascii=False),
            ContentType='application/json',
            Metadata={
                'source-document': key,
                'confidence-score': str(avg_confidence),
                'processing-status': 'completed'
            }
        )
        
        logger.info(f"Results saved to: {results_key}")
        logger.info(f"Average confidence: {avg_confidence:.2f}%")
        logger.info(f"Extracted {word_count} words from {line_count} lines")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Document processed successfully',
                'results_location': f"s3://{bucket}/{results_key}",
                'statistics': {
                    'confidence': avg_confidence,
                    'lines': line_count,
                    'words': word_count
                },
                'document': key
            })
        }
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        error_message = e.response['Error']['Message']
        logger.error(f"AWS service error: {error_code} - {error_message}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': f"AWS service error: {error_code}",
                'message': error_message,
                'document': key if 'key' in locals() else 'unknown'
            })
        }
        
    except Exception as e:
        logger.error(f"Unexpected error processing document: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Unexpected processing error',
                'message': str(e),
                'document': key if 'key' in locals() else 'unknown'
            })
        }
      `),
    });

    // Configure S3 event notification to trigger Lambda
    this.documentBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.processingFunction),
      {
        prefix: 'documents/',
        suffix: undefined, // Accept all file types, validation happens in Lambda
      }
    );

    // Add outputs for easy access to resource information
    new cdk.CfnOutput(this, 'DocumentBucketName', {
      value: this.documentBucket.bucketName,
      description: 'Name of the S3 bucket for document storage',
      exportName: `${this.stackName}-DocumentBucket`,
    });

    new cdk.CfnOutput(this, 'DocumentBucketArn', {
      value: this.documentBucket.bucketArn,
      description: 'ARN of the S3 bucket for document storage',
      exportName: `${this.stackName}-DocumentBucketArn`,
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionName', {
      value: this.processingFunction.functionName,
      description: 'Name of the Lambda function for document processing',
      exportName: `${this.stackName}-ProcessingFunction`,
    });

    new cdk.CfnOutput(this, 'ProcessingFunctionArn', {
      value: this.processingFunction.functionArn,
      description: 'ARN of the Lambda function for document processing',
      exportName: `${this.stackName}-ProcessingFunctionArn`,
    });

    new cdk.CfnOutput(this, 'LambdaRoleArn', {
      value: this.lambdaRole.roleArn,
      description: 'ARN of the IAM role for the Lambda function',
      exportName: `${this.stackName}-LambdaRole`,
    });

    new cdk.CfnOutput(this, 'LogGroupName', {
      value: logGroup.logGroupName,
      description: 'Name of the CloudWatch log group for the Lambda function',
      exportName: `${this.stackName}-LogGroup`,
    });

    // Add tags to all resources for better organization
    cdk.Tags.of(this).add('Project', 'IntelligentDocumentProcessing');
    cdk.Tags.of(this).add('Service', 'Textract');
    cdk.Tags.of(this).add('ManagedBy', 'CDK');
    cdk.Tags.of(this).add('Environment', 'Development');
  }
}