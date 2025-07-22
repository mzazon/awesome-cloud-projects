#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * Stack for Amazon Comprehend Natural Language Processing Solution
 * 
 * This stack creates:
 * - S3 buckets for input and output data
 * - IAM roles for Comprehend service and Lambda execution
 * - Lambda function for real-time text processing
 * - EventBridge rules for automated processing
 * - CloudWatch log groups for monitoring
 */
export class ComprehendNlpStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = Math.random().toString(36).substring(2, 8);

    // Create S3 bucket for input data
    const inputBucket = new s3.Bucket(this, 'ComprehendInputBucket', {
      bucketName: `comprehend-nlp-input-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create S3 bucket for output data
    const outputBucket = new s3.Bucket(this, 'ComprehendOutputBucket', {
      bucketName: `comprehend-nlp-output-${uniqueSuffix}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldVersions',
          enabled: true,
          noncurrentVersionExpiration: cdk.Duration.days(30),
        },
      ],
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Amazon Comprehend service
    const comprehendServiceRole = new iam.Role(this, 'ComprehendServiceRole', {
      roleName: `ComprehendServiceRole-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('comprehend.amazonaws.com'),
      description: 'Service role for Amazon Comprehend to access S3 buckets',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('ComprehendFullAccess'),
      ],
      inlinePolicies: {
        S3Access: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:ListBucket',
                's3:PutObject',
                's3:DeleteObject',
              ],
              resources: [
                inputBucket.bucketArn,
                `${inputBucket.bucketArn}/*`,
                outputBucket.bucketArn,
                `${outputBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
      },
    });

    // Create CloudWatch log group for Lambda function
    const lambdaLogGroup = new logs.LogGroup(this, 'ComprehendProcessorLogGroup', {
      logGroupName: `/aws/lambda/comprehend-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Create Lambda function for real-time text processing
    const comprehendProcessor = new lambda.Function(this, 'ComprehendProcessor', {
      functionName: `comprehend-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.minutes(5),
      memorySize: 512,
      environment: {
        INPUT_BUCKET: inputBucket.bucketName,
        OUTPUT_BUCKET: outputBucket.bucketName,
        LOG_LEVEL: 'INFO',
      },
      logGroup: lambdaLogGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(os.environ.get('LOG_LEVEL', 'INFO'))

# Initialize AWS clients
comprehend = boto3.client('comprehend')
s3 = boto3.client('s3')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Lambda function handler for real-time text processing with Amazon Comprehend.
    
    Processes text input through multiple Comprehend APIs:
    - Sentiment analysis
    - Entity detection
    - Key phrase extraction
    - Language detection
    
    Args:
        event: Lambda event containing text input
        context: Lambda context object
        
    Returns:
        Dictionary containing analysis results
    """
    try:
        logger.info(f"Processing event: {json.dumps(event)}")
        
        # Extract text from event
        text = event.get('text', '')
        if not text:
            logger.error("No text provided in event")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'No text provided',
                    'message': 'Please provide text in the event payload'
                })
            }
        
        # Validate text length (Comprehend real-time limit is 5,000 UTF-8 characters)
        if len(text.encode('utf-8')) > 5000:
            logger.error(f"Text too long: {len(text.encode('utf-8'))} bytes")
            return {
                'statusCode': 400,
                'body': json.dumps({
                    'error': 'Text too long',
                    'message': 'Text must be less than 5,000 UTF-8 characters'
                })
            }
        
        logger.info(f"Processing text of length: {len(text)} characters")
        
        # Detect dominant language
        language_response = comprehend.detect_dominant_language(Text=text)
        dominant_language = language_response['Languages'][0]['LanguageCode']
        language_score = language_response['Languages'][0]['Score']
        
        logger.info(f"Detected language: {dominant_language} (confidence: {language_score:.2f})")
        
        # Perform sentiment analysis
        sentiment_response = comprehend.detect_sentiment(
            Text=text,
            LanguageCode=dominant_language
        )
        
        # Perform entity detection
        entities_response = comprehend.detect_entities(
            Text=text,
            LanguageCode=dominant_language
        )
        
        # Perform key phrase extraction
        key_phrases_response = comprehend.detect_key_phrases(
            Text=text,
            LanguageCode=dominant_language
        )
        
        # Compile comprehensive results
        result = {
            'timestamp': context.aws_request_id,
            'language': {
                'code': dominant_language,
                'confidence': language_score,
                'all_languages': language_response['Languages']
            },
            'sentiment': {
                'overall': sentiment_response['Sentiment'],
                'scores': sentiment_response['SentimentScore']
            },
            'entities': [
                {
                    'text': entity['Text'],
                    'type': entity['Type'],
                    'score': entity['Score'],
                    'begin_offset': entity['BeginOffset'],
                    'end_offset': entity['EndOffset']
                }
                for entity in entities_response['Entities']
            ],
            'key_phrases': [
                {
                    'text': phrase['Text'],
                    'score': phrase['Score'],
                    'begin_offset': phrase['BeginOffset'],
                    'end_offset': phrase['EndOffset']
                }
                for phrase in key_phrases_response['KeyPhrases']
            ],
            'statistics': {
                'character_count': len(text),
                'word_count': len(text.split()),
                'entity_count': len(entities_response['Entities']),
                'key_phrase_count': len(key_phrases_response['KeyPhrases'])
            }
        }
        
        logger.info(f"Analysis complete: {result['statistics']}")
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(result, default=str)
        }
        
    except Exception as e:
        logger.error(f"Error processing text: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }

def process_s3_event(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Process S3 event for batch text analysis.
    
    Args:
        event: S3 event notification
        context: Lambda context object
        
    Returns:
        Dictionary containing processing results
    """
    try:
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            logger.info(f"Processing S3 object: s3://{bucket}/{key}")
            
            # Get object from S3
            response = s3.get_object(Bucket=bucket, Key=key)
            text = response['Body'].read().decode('utf-8')
            
            # Process text through Comprehend
            analysis_result = lambda_handler({'text': text}, context)
            
            # Store results in output bucket
            output_key = f"processed/{key.replace('.txt', '.json')}"
            s3.put_object(
                Bucket=os.environ['OUTPUT_BUCKET'],
                Key=output_key,
                Body=analysis_result['body'],
                ContentType='application/json'
            )
            
            logger.info(f"Stored results: s3://{os.environ['OUTPUT_BUCKET']}/{output_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Processing complete'})
        }
        
    except Exception as e:
        logger.error(f"Error processing S3 event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`),
    });

    // Grant Lambda function permissions to use Comprehend
    comprehendProcessor.addToRolePolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'comprehend:DetectSentiment',
          'comprehend:DetectEntities',
          'comprehend:DetectKeyPhrases',
          'comprehend:DetectDominantLanguage',
          'comprehend:DetectPiiEntities',
          'comprehend:DetectSyntax',
        ],
        resources: ['*'],
      })
    );

    // Grant Lambda function permissions to access S3 buckets
    inputBucket.grantRead(comprehendProcessor);
    outputBucket.grantReadWrite(comprehendProcessor);

    // Create EventBridge rule for S3 events
    const s3ProcessingRule = new events.Rule(this, 'S3ProcessingRule', {
      ruleName: `comprehend-s3-processing-${uniqueSuffix}`,
      description: 'Trigger Comprehend processing when files are uploaded to S3',
      eventPattern: {
        source: ['aws.s3'],
        detailType: ['Object Created'],
        detail: {
          bucket: {
            name: [inputBucket.bucketName],
          },
          object: {
            key: [{ prefix: 'input/' }],
          },
        },
      },
    });

    // Add Lambda function as target for EventBridge rule
    s3ProcessingRule.addTarget(new targets.LambdaFunction(comprehendProcessor));

    // Add S3 notification to trigger Lambda directly for immediate processing
    inputBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(comprehendProcessor),
      { prefix: 'realtime/' }
    );

    // Create sample files for testing
    const sampleFilesDeployment = new cdk.CustomResource(this, 'SampleFilesDeployment', {
      serviceToken: new lambda.Function(this, 'SampleFilesDeploymentFunction', {
        functionName: `sample-files-deployment-${uniqueSuffix}`,
        runtime: lambda.Runtime.PYTHON_3_11,
        handler: 'index.handler',
        timeout: cdk.Duration.minutes(5),
        code: lambda.Code.fromInline(`
import boto3
import json
import urllib3

s3 = boto3.client('s3')

def handler(event, context):
    try:
        request_type = event['RequestType']
        bucket_name = event['ResourceProperties']['BucketName']
        
        if request_type == 'Create':
            # Create sample text files
            sample_files = {
                'input/sample-review-positive.txt': 'This product is absolutely amazing! The quality exceeded my expectations and the customer service was outstanding.',
                'input/sample-review-negative.txt': 'The device stopped working after just two weeks. Very disappointed with the build quality.',
                'input/sample-support-ticket.txt': 'Customer John Smith from TechCorp reported login issues with the mobile app on iPhone 12.',
                'input/sample-feedback.txt': 'The new software update improved performance significantly, but the user interface could be more intuitive.',
                'realtime/sample-realtime.txt': 'Real-time processing test: This message will trigger immediate analysis.',
            }
            
            for key, content in sample_files.items():
                s3.put_object(
                    Bucket=bucket_name,
                    Key=key,
                    Body=content.encode('utf-8'),
                    ContentType='text/plain'
                )
            
            send_response(event, context, 'SUCCESS', {'Message': 'Sample files created successfully'})
            
        elif request_type == 'Delete':
            # Clean up sample files
            try:
                objects = s3.list_objects_v2(Bucket=bucket_name, Prefix='input/')
                if 'Contents' in objects:
                    delete_keys = [{'Key': obj['Key']} for obj in objects['Contents']]
                    s3.delete_objects(Bucket=bucket_name, Delete={'Objects': delete_keys})
                
                objects = s3.list_objects_v2(Bucket=bucket_name, Prefix='realtime/')
                if 'Contents' in objects:
                    delete_keys = [{'Key': obj['Key']} for obj in objects['Contents']]
                    s3.delete_objects(Bucket=bucket_name, Delete={'Objects': delete_keys})
                    
            except Exception as e:
                print(f"Error cleaning up files: {str(e)}")
            
            send_response(event, context, 'SUCCESS', {'Message': 'Sample files cleaned up'})
            
        else:
            send_response(event, context, 'SUCCESS', {'Message': 'No action required'})
            
    except Exception as e:
        print(f"Error: {str(e)}")
        send_response(event, context, 'FAILED', {'Error': str(e)})

def send_response(event, context, status, data):
    response_body = {
        'Status': status,
        'Reason': f'See CloudWatch Log Stream: {context.log_stream_name}',
        'PhysicalResourceId': context.log_stream_name,
        'StackId': event['StackId'],
        'RequestId': event['RequestId'],
        'LogicalResourceId': event['LogicalResourceId'],
        'Data': data
    }
    
    http = urllib3.PoolManager()
    response = http.request('PUT', event['ResponseURL'], 
                          body=json.dumps(response_body),
                          headers={'Content-Type': 'application/json'})
`),
      }).functionArn,
      properties: {
        BucketName: inputBucket.bucketName,
      },
    });

    // Grant the sample files deployment function access to S3
    inputBucket.grantReadWrite(
      iam.Role.fromRoleArn(this, 'SampleFilesRole', 
        sampleFilesDeployment.getAtt('ServiceToken').toString().replace('arn:aws:lambda:', 'arn:aws:iam:').replace(':function:', ':role/').replace(/:[^:]*$/, '')
      )
    );

    // Stack outputs
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: inputBucket.bucketName,
      description: 'Name of the S3 bucket for input text files',
      exportName: `${this.stackName}-InputBucket`,
    });

    new cdk.CfnOutput(this, 'OutputBucketName', {
      value: outputBucket.bucketName,
      description: 'Name of the S3 bucket for processed results',
      exportName: `${this.stackName}-OutputBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: comprehendProcessor.functionName,
      description: 'Name of the Lambda function for text processing',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionArn', {
      value: comprehendProcessor.functionArn,
      description: 'ARN of the Lambda function for text processing',
      exportName: `${this.stackName}-LambdaFunctionArn`,
    });

    new cdk.CfnOutput(this, 'ComprehendServiceRoleArn', {
      value: comprehendServiceRole.roleArn,
      description: 'ARN of the IAM role for Comprehend service',
      exportName: `${this.stackName}-ComprehendServiceRole`,
    });

    new cdk.CfnOutput(this, 'EventBridgeRuleName', {
      value: s3ProcessingRule.ruleName,
      description: 'Name of the EventBridge rule for S3 processing',
      exportName: `${this.stackName}-EventBridgeRule`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Project', 'ComprehendNLP');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'MLTeam');
    cdk.Tags.of(this).add('Purpose', 'NaturalLanguageProcessing');
  }
}

// Create the CDK app
const app = new cdk.App();

// Deploy the stack
new ComprehendNlpStack(app, 'ComprehendNlpStack', {
  description: 'Amazon Comprehend Natural Language Processing Solution',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Synthesize the app
app.synth();