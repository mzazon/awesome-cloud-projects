#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import { Construct } from 'constructs';

/**
 * Stack for Automated Image Analysis with ML
 * This stack creates:
 * - S3 bucket for storing images
 * - IAM roles and policies for Rekognition access
 * - Lambda function for processing images (optional)
 * - S3 event notifications for automatic processing
 */
export class ImageAnalysisRekognitionStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for bucket name to avoid conflicts
    const uniqueSuffix = this.node.addr.slice(-8).toLowerCase();

    // Create S3 bucket for storing images
    const imagesBucket = new s3.Bucket(this, 'ImagesBucket', {
      bucketName: `rekognition-images-${uniqueSuffix}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'delete-old-images',
          enabled: true,
          expiration: cdk.Duration.days(90), // Automatically delete images after 90 days
        },
      ],
    });

    // Create S3 bucket for storing analysis results
    const resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `rekognition-results-${uniqueSuffix}`,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      publicReadAccess: false,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      lifecycleRules: [
        {
          id: 'delete-old-results',
          enabled: true,
          expiration: cdk.Duration.days(30), // Keep results for 30 days
        },
      ],
    });

    // IAM role for Lambda function with Rekognition permissions
    const lambdaRole = new iam.Role(this, 'ImageAnalysisLambdaRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      description: 'Role for Lambda function to analyze images with Rekognition',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        RekognitionPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rekognition:DetectLabels',
                'rekognition:DetectText',
                'rekognition:DetectModerationLabels',
                'rekognition:DetectFaces',
                'rekognition:RecognizeCelebrities',
              ],
              resources: ['*'], // Rekognition doesn't support resource-level permissions
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
              ],
              resources: [imagesBucket.arnForObjects('*')],
            }),
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:PutObjectAcl',
              ],
              resources: [resultsBucket.arnForObjects('*')],
            }),
          ],
        }),
      },
    });

    // Lambda function for processing images with Rekognition
    const imageProcessorFunction = new lambda.Function(this, 'ImageProcessorFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Processes images using Amazon Rekognition for analysis',
      environment: {
        RESULTS_BUCKET: resultsBucket.bucketName,
        AWS_REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib.parse
from datetime import datetime

rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to analyze images using Amazon Rekognition
    Triggered by S3 events when new images are uploaded
    """
    
    results_bucket = os.environ['RESULTS_BUCKET']
    
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')
            
            print(f"Processing image: {key} from bucket: {bucket}")
            
            # Skip if not an image file
            if not key.lower().endswith(('.jpg', '.jpeg', '.png')):
                print(f"Skipping non-image file: {key}")
                continue
            
            # Perform image analysis
            analysis_results = analyze_image(bucket, key)
            
            # Save results to S3
            save_results(results_bucket, key, analysis_results)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Image analysis completed successfully')
        }
        
    except Exception as e:
        print(f"Error processing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def analyze_image(bucket, key):
    """Analyze image using multiple Rekognition services"""
    
    image = {'S3Object': {'Bucket': bucket, 'Name': key}}
    results = {
        'image': key,
        'timestamp': datetime.utcnow().isoformat(),
        'analysis': {}
    }
    
    try:
        # Detect labels (objects and scenes)
        labels_response = rekognition.detect_labels(
            Image=image,
            Features=['GENERAL_LABELS'],
            Settings={
                'GeneralLabels': {
                    'LabelInclusionFilters': [],
                    'LabelExclusionFilters': [],
                    'LabelCategoryInclusionFilters': [],
                    'LabelCategoryExclusionFilters': []
                }
            }
        )
        results['analysis']['labels'] = labels_response.get('Labels', [])
        
        # Detect text
        text_response = rekognition.detect_text(Image=image)
        results['analysis']['text'] = text_response.get('TextDetections', [])
        
        # Content moderation
        moderation_response = rekognition.detect_moderation_labels(Image=image)
        results['analysis']['moderation'] = moderation_response.get('ModerationLabels', [])
        
        # Detect faces (basic attributes)
        faces_response = rekognition.detect_faces(
            Image=image,
            Attributes=['ALL']
        )
        results['analysis']['faces'] = faces_response.get('FaceDetails', [])
        
    except Exception as e:
        results['error'] = str(e)
        print(f"Error analyzing image {key}: {str(e)}")
    
    return results

def save_results(results_bucket, image_key, results):
    """Save analysis results to S3"""
    
    # Create results key based on image key
    results_key = f"results/{image_key.replace('/', '_')}.json"
    
    try:
        s3.put_object(
            Bucket=results_bucket,
            Key=results_key,
            Body=json.dumps(results, indent=2, default=str),
            ContentType='application/json'
        )
        print(f"Results saved to: {results_bucket}/{results_key}")
        
    except Exception as e:
        print(f"Error saving results for {image_key}: {str(e)}")
        raise e
`),
    });

    // Add missing import for os module
    const functionCodeWithImport = imageProcessorFunction.code.bind(imageProcessorFunction);
    
    // Update the Lambda function code to include the missing import
    const updatedLambdaFunction = new lambda.Function(this, 'UpdatedImageProcessorFunction', {
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 256,
      description: 'Processes images using Amazon Rekognition for analysis',
      environment: {
        RESULTS_BUCKET: resultsBucket.bucketName,
        AWS_REGION: this.region,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import urllib.parse
import os
from datetime import datetime

rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')

def lambda_handler(event, context):
    """
    Lambda function to analyze images using Amazon Rekognition
    Triggered by S3 events when new images are uploaded
    """
    
    results_bucket = os.environ['RESULTS_BUCKET']
    
    try:
        # Parse S3 event
        for record in event['Records']:
            bucket = record['s3']['bucket']['name']
            key = urllib.parse.unquote_plus(record['s3']['object']['key'], encoding='utf-8')
            
            print(f"Processing image: {key} from bucket: {bucket}")
            
            # Skip if not an image file
            if not key.lower().endswith(('.jpg', '.jpeg', '.png')):
                print(f"Skipping non-image file: {key}")
                continue
            
            # Perform image analysis
            analysis_results = analyze_image(bucket, key)
            
            # Save results to S3
            save_results(results_bucket, key, analysis_results)
            
        return {
            'statusCode': 200,
            'body': json.dumps('Image analysis completed successfully')
        }
        
    except Exception as e:
        print(f"Error processing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps(f'Error: {str(e)}')
        }

def analyze_image(bucket, key):
    """Analyze image using multiple Rekognition services"""
    
    image = {'S3Object': {'Bucket': bucket, 'Name': key}}
    results = {
        'image': key,
        'timestamp': datetime.utcnow().isoformat(),
        'analysis': {}
    }
    
    try:
        # Detect labels (objects and scenes)
        labels_response = rekognition.detect_labels(
            Image=image,
            Features=['GENERAL_LABELS'],
            Settings={
                'GeneralLabels': {
                    'LabelInclusionFilters': [],
                    'LabelExclusionFilters': [],
                    'LabelCategoryInclusionFilters': [],
                    'LabelCategoryExclusionFilters': []
                }
            }
        )
        results['analysis']['labels'] = labels_response.get('Labels', [])
        
        # Detect text
        text_response = rekognition.detect_text(Image=image)
        results['analysis']['text'] = text_response.get('TextDetections', [])
        
        # Content moderation
        moderation_response = rekognition.detect_moderation_labels(Image=image)
        results['analysis']['moderation'] = moderation_response.get('ModerationLabels', [])
        
        # Detect faces (basic attributes)
        faces_response = rekognition.detect_faces(
            Image=image,
            Attributes=['ALL']
        )
        results['analysis']['faces'] = faces_response.get('FaceDetails', [])
        
    except Exception as e:
        results['error'] = str(e)
        print(f"Error analyzing image {key}: {str(e)}")
    
    return results

def save_results(results_bucket, image_key, results):
    """Save analysis results to S3"""
    
    # Create results key based on image key
    results_key = f"results/{image_key.replace('/', '_')}.json"
    
    try:
        s3.put_object(
            Bucket=results_bucket,
            Key=results_key,
            Body=json.dumps(results, indent=2, default=str),
            ContentType='application/json'
        )
        print(f"Results saved to: {results_bucket}/{results_key}")
        
    except Exception as e:
        print(f"Error saving results for {image_key}: {str(e)}")
        raise e
`),
    });

    // Remove the duplicate function and use the updated one
    this.node.tryRemoveChild('ImageProcessorFunction');

    // Add S3 event notification to trigger Lambda when images are uploaded
    imagesBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(updatedLambdaFunction),
      { prefix: 'images/', suffix: '.jpg' }
    );

    imagesBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(updatedLambdaFunction),
      { prefix: 'images/', suffix: '.jpeg' }
    );

    imagesBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(updatedLambdaFunction),
      { prefix: 'images/', suffix: '.png' }
    );

    // Create IAM user for CLI access (optional for testing)
    const rekognitionUser = new iam.User(this, 'RekognitionUser', {
      userName: `rekognition-user-${uniqueSuffix}`,
    });

    // Attach policy to the user for Rekognition and S3 access
    rekognitionUser.attachInlinePolicy(
      new iam.Policy(this, 'RekognitionUserPolicy', {
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
              'rekognition:DetectLabels',
              'rekognition:DetectText',
              'rekognition:DetectModerationLabels',
              'rekognition:DetectFaces',
              'rekognition:RecognizeCelebrities',
            ],
            resources: ['*'],
          }),
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
              's3:GetObject',
              's3:PutObject',
              's3:ListBucket',
            ],
            resources: [
              imagesBucket.bucketArn,
              imagesBucket.arnForObjects('*'),
              resultsBucket.bucketArn,
              resultsBucket.arnForObjects('*'),
            ],
          }),
        ],
      })
    );

    // Outputs for easy reference
    new cdk.CfnOutput(this, 'ImagesBucketName', {
      value: imagesBucket.bucketName,
      description: 'Name of the S3 bucket for storing images',
      exportName: `${this.stackName}-ImagesBucket`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'Name of the S3 bucket for storing analysis results',
      exportName: `${this.stackName}-ResultsBucket`,
    });

    new cdk.CfnOutput(this, 'LambdaFunctionName', {
      value: updatedLambdaFunction.functionName,
      description: 'Name of the Lambda function for image processing',
      exportName: `${this.stackName}-LambdaFunction`,
    });

    new cdk.CfnOutput(this, 'RekognitionUserName', {
      value: rekognitionUser.userName,
      description: 'IAM user name for CLI access',
      exportName: `${this.stackName}-RekognitionUser`,
    });

    new cdk.CfnOutput(this, 'Region', {
      value: this.region,
      description: 'AWS region where resources are deployed',
      exportName: `${this.stackName}-Region`,
    });

    // Tag all resources for cost tracking and identification
    cdk.Tags.of(this).add('Application', 'ImageAnalysisRekognition');
    cdk.Tags.of(this).add('Environment', 'Development');
    cdk.Tags.of(this).add('Owner', 'MarketingTeam');
    cdk.Tags.of(this).add('CostCenter', 'ML-Analytics');
  }
}

// CDK App instantiation
const app = new cdk.App();

// Get deployment configuration from context or environment
const account = app.node.tryGetContext('account') || process.env.CDK_DEFAULT_ACCOUNT;
const region = app.node.tryGetContext('region') || process.env.CDK_DEFAULT_REGION || 'us-east-1';

// Create the stack
new ImageAnalysisRekognitionStack(app, 'ImageAnalysisRekognitionStack', {
  env: {
    account: account,
    region: region,
  },
  description: 'CDK Stack for Image Analysis Application with Amazon Rekognition',
  tags: {
    Project: 'ImageAnalysis',
    CreatedBy: 'CDK',
    Purpose: 'MachineLearning',
  },
});

// Synthesize the CloudFormation template
app.synth();