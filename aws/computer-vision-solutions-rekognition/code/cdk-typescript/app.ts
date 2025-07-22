#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import * as logs from 'aws-cdk-lib/aws-logs';

/**
 * CDK Stack for Computer Vision Solutions using Amazon Rekognition
 * 
 * This stack creates a comprehensive computer vision system that can:
 * - Detect and analyze faces with demographics and emotions
 * - Recognize objects, scenes, and activities in images
 * - Extract text from images using OCR
 * - Moderate content for inappropriate material
 * - Store analysis results for future reference
 */
export class ComputerVisionRekognitionStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = cdk.Names.uniqueId(this).toLowerCase().slice(-8);

    // =====================================================
    // S3 Buckets for Image Storage and Results
    // =====================================================

    // Primary bucket for storing uploaded images
    const imageBucket = new s3.Bucket(this, 'ImageBucket', {
      bucketName: `rekognition-images-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      cors: [
        {
          allowedHeaders: ['*'],
          allowedMethods: [s3.HttpMethods.GET, s3.HttpMethods.PUT, s3.HttpMethods.POST],
          allowedOrigins: ['*'],
          exposedHeaders: ['ETag'],
          maxAge: 3000,
        },
      ],
    });

    // Bucket for storing analysis results and processed data
    const resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `rekognition-results-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: false,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          id: 'DeleteOldResults',
          enabled: true,
          expiration: cdk.Duration.days(90),
        },
      ],
    });

    // =====================================================
    // DynamoDB Table for Analysis Metadata
    // =====================================================

    // Table to store analysis results and metadata
    const analysisTable = new dynamodb.Table(this, 'AnalysisTable', {
      tableName: `rekognition-analysis-${uniqueSuffix}`,
      partitionKey: {
        name: 'imageId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'analysisType',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      // Global Secondary Index for querying by analysis timestamp
      globalSecondaryIndexes: [
        {
          indexName: 'TimestampIndex',
          partitionKey: {
            name: 'analysisType',
            type: dynamodb.AttributeType.STRING,
          },
          sortKey: {
            name: 'timestamp',
            type: dynamodb.AttributeType.STRING,
          },
        },
      ],
    });

    // Add GSI for content moderation status queries
    analysisTable.addGlobalSecondaryIndex({
      indexName: 'ModerationStatusIndex',
      partitionKey: {
        name: 'moderationStatus',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'timestamp',
        type: dynamodb.AttributeType.STRING,
      },
    });

    // =====================================================
    // IAM Role for Lambda Functions
    // =====================================================

    // Comprehensive IAM role for Lambda functions with Rekognition permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      roleName: `rekognition-lambda-role-${uniqueSuffix}`,
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        RekognitionPolicy: new iam.PolicyDocument({
          statements: [
            // Rekognition permissions for all analysis operations
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'rekognition:DetectFaces',
                'rekognition:DetectLabels',
                'rekognition:DetectText',
                'rekognition:DetectModerationLabels',
                'rekognition:RecognizeCelebrities',
                'rekognition:SearchFacesByImage',
                'rekognition:IndexFaces',
                'rekognition:CreateCollection',
                'rekognition:DeleteCollection',
                'rekognition:ListCollections',
                'rekognition:DescribeCollection',
                'rekognition:ListFaces',
                'rekognition:DeleteFaces',
                'rekognition:CompareFaces',
              ],
              resources: ['*'],
            }),
            // S3 permissions for reading images and writing results
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:GetObject',
                's3:GetObjectVersion',
                's3:PutObject',
                's3:PutObjectAcl',
                's3:DeleteObject',
              ],
              resources: [
                imageBucket.bucketArn,
                `${imageBucket.bucketArn}/*`,
                resultsBucket.bucketArn,
                `${resultsBucket.bucketArn}/*`,
              ],
            }),
            // DynamoDB permissions for storing analysis results
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'dynamodb:PutItem',
                'dynamodb:GetItem',
                'dynamodb:UpdateItem',
                'dynamodb:DeleteItem',
                'dynamodb:Query',
                'dynamodb:Scan',
              ],
              resources: [
                analysisTable.tableArn,
                `${analysisTable.tableArn}/index/*`,
              ],
            }),
          ],
        }),
      },
    });

    // =====================================================
    // Lambda Functions for Image Analysis
    // =====================================================

    // Create CloudWatch Log Group for better log management
    const imageProcessorLogGroup = new logs.LogGroup(this, 'ImageProcessorLogGroup', {
      logGroupName: `/aws/lambda/rekognition-image-processor-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Main image processing Lambda function
    const imageProcessorFunction = new lambda.Function(this, 'ImageProcessorFunction', {
      functionName: `rekognition-image-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(5),
      memorySize: 1024,
      environment: {
        IMAGE_BUCKET: imageBucket.bucketName,
        RESULTS_BUCKET: resultsBucket.bucketName,
        ANALYSIS_TABLE: analysisTable.tableName,
        FACE_COLLECTION_ID: `face-collection-${uniqueSuffix}`,
      },
      logGroup: imageProcessorLogGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

# Initialize AWS service clients
rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
IMAGE_BUCKET = os.environ['IMAGE_BUCKET']
RESULTS_BUCKET = os.environ['RESULTS_BUCKET']
ANALYSIS_TABLE = os.environ['ANALYSIS_TABLE']
FACE_COLLECTION_ID = os.environ['FACE_COLLECTION_ID']

# DynamoDB table
table = dynamodb.Table(ANALYSIS_TABLE)

def lambda_handler(event, context):
    """
    Main Lambda handler for processing images with Amazon Rekognition
    """
    try:
        # Handle different event sources (S3, API Gateway, direct invocation)
        if 'Records' in event:
            # S3 Event
            for record in event['Records']:
                bucket = record['s3']['bucket']['name']
                key = record['s3']['object']['key']
                process_image(bucket, key)
        elif 'body' in event:
            # API Gateway Event
            body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']
            bucket = body.get('bucket', IMAGE_BUCKET)
            key = body['key']
            return process_image(bucket, key, return_results=True)
        else:
            # Direct invocation
            bucket = event.get('bucket', IMAGE_BUCKET)
            key = event['key']
            return process_image(bucket, key, return_results=True)
            
    except Exception as e:
        print(f"Error processing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def process_image(bucket, key, return_results=False):
    """
    Process a single image through all Rekognition analysis types
    """
    image_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()
    
    # Image reference for Rekognition API calls
    image = {'S3Object': {'Bucket': bucket, 'Name': key}}
    
    results = {
        'imageId': image_id,
        'bucket': bucket,
        'key': key,
        'timestamp': timestamp,
        'analyses': {}
    }
    
    try:
        # 1. Face Detection and Analysis
        face_results = analyze_faces(image, image_id, timestamp)
        results['analyses']['faces'] = face_results
        
        # 2. Object and Scene Detection  
        label_results = analyze_labels(image, image_id, timestamp)
        results['analyses']['labels'] = label_results
        
        # 3. Text Detection
        text_results = analyze_text(image, image_id, timestamp)
        results['analyses']['text'] = text_results
        
        # 4. Content Moderation
        moderation_results = analyze_moderation(image, image_id, timestamp)
        results['analyses']['moderation'] = moderation_results
        
        # 5. Celebrity Recognition
        celebrity_results = analyze_celebrities(image, image_id, timestamp)
        results['analyses']['celebrities'] = celebrity_results
        
        # Store comprehensive results in S3
        store_results_in_s3(results, image_id)
        
        # Store summary in DynamoDB
        store_summary_in_dynamodb(results)
        
        if return_results:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps(results, default=decimal_default)
            }
            
    except Exception as e:
        print(f"Error in process_image: {str(e)}")
        if return_results:
            return {
                'statusCode': 500,
                'body': json.dumps({'error': str(e)})
            }

def analyze_faces(image, image_id, timestamp):
    """
    Detect and analyze faces in the image
    """
    try:
        response = rekognition.detect_faces(
            Image=image,
            Attributes=['ALL']
        )
        
        face_data = {
            'faceCount': len(response['FaceDetails']),
            'faces': response['FaceDetails']
        }
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'imageId': image_id,
                'analysisType': 'FACE_DETECTION',
                'timestamp': timestamp,
                'faceCount': face_data['faceCount'],
                'confidence': Decimal(str(response['FaceDetails'][0]['Confidence'])) if response['FaceDetails'] else Decimal('0'),
                'rawResults': json.loads(json.dumps(response, default=decimal_default))
            }
        )
        
        return face_data
        
    except Exception as e:
        print(f"Error in face analysis: {str(e)}")
        return {'error': str(e)}

def analyze_labels(image, image_id, timestamp):
    """
    Detect objects, scenes, and activities in the image
    """
    try:
        response = rekognition.detect_labels(
            Image=image,
            MaxLabels=20,
            MinConfidence=75
        )
        
        label_data = {
            'labelCount': len(response['Labels']),
            'labels': response['Labels']
        }
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'imageId': image_id,
                'analysisType': 'LABEL_DETECTION',
                'timestamp': timestamp,
                'labelCount': label_data['labelCount'],
                'confidence': Decimal(str(response['Labels'][0]['Confidence'])) if response['Labels'] else Decimal('0'),
                'topLabels': [label['Name'] for label in response['Labels'][:5]],
                'rawResults': json.loads(json.dumps(response, default=decimal_default))
            }
        )
        
        return label_data
        
    except Exception as e:
        print(f"Error in label analysis: {str(e)}")
        return {'error': str(e)}

def analyze_text(image, image_id, timestamp):
    """
    Extract text from the image using OCR
    """
    try:
        response = rekognition.detect_text(Image=image)
        
        # Extract only LINE level text for readability
        lines = [detection for detection in response['TextDetections'] if detection['Type'] == 'LINE']
        
        text_data = {
            'textCount': len(lines),
            'extractedText': ' '.join([line['DetectedText'] for line in lines]),
            'textDetails': lines
        }
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'imageId': image_id,
                'analysisType': 'TEXT_DETECTION',
                'timestamp': timestamp,
                'textCount': text_data['textCount'],
                'extractedText': text_data['extractedText'][:1000],  # Limit for DynamoDB
                'confidence': Decimal(str(lines[0]['Confidence'])) if lines else Decimal('0'),
                'rawResults': json.loads(json.dumps(response, default=decimal_default))
            }
        )
        
        return text_data
        
    except Exception as e:
        print(f"Error in text analysis: {str(e)}")
        return {'error': str(e)}

def analyze_moderation(image, image_id, timestamp):
    """
    Analyze content for inappropriate material
    """
    try:
        response = rekognition.detect_moderation_labels(
            Image=image,
            MinConfidence=60
        )
        
        moderation_data = {
            'moderationLabelCount': len(response['ModerationLabels']),
            'isInappropriate': len(response['ModerationLabels']) > 0,
            'moderationLabels': response['ModerationLabels']
        }
        
        # Determine moderation status
        moderation_status = 'APPROVED'
        if len(response['ModerationLabels']) > 0:
            moderation_status = 'FLAGGED'
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'imageId': image_id,
                'analysisType': 'CONTENT_MODERATION',
                'timestamp': timestamp,
                'moderationStatus': moderation_status,
                'moderationLabelCount': moderation_data['moderationLabelCount'],
                'isInappropriate': moderation_data['isInappropriate'],
                'confidence': Decimal(str(response['ModerationLabels'][0]['Confidence'])) if response['ModerationLabels'] else Decimal('0'),
                'rawResults': json.loads(json.dumps(response, default=decimal_default))
            }
        )
        
        return moderation_data
        
    except Exception as e:
        print(f"Error in moderation analysis: {str(e)}")
        return {'error': str(e)}

def analyze_celebrities(image, image_id, timestamp):
    """
    Recognize celebrities in the image
    """
    try:
        response = rekognition.recognize_celebrities(Image=image)
        
        celebrity_data = {
            'celebrityCount': len(response['CelebrityFaces']),
            'celebrities': response['CelebrityFaces'],
            'unrecognizedFaces': response['UnrecognizedFaces']
        }
        
        # Store in DynamoDB
        table.put_item(
            Item={
                'imageId': image_id,
                'analysisType': 'CELEBRITY_RECOGNITION',
                'timestamp': timestamp,
                'celebrityCount': celebrity_data['celebrityCount'],
                'celebrityNames': [celeb['Name'] for celeb in response['CelebrityFaces']],
                'confidence': Decimal(str(response['CelebrityFaces'][0]['Face']['Confidence'])) if response['CelebrityFaces'] else Decimal('0'),
                'rawResults': json.loads(json.dumps(response, default=decimal_default))
            }
        )
        
        return celebrity_data
        
    except Exception as e:
        print(f"Error in celebrity analysis: {str(e)}")
        return {'error': str(e)}

def store_results_in_s3(results, image_id):
    """
    Store comprehensive analysis results in S3
    """
    try:
        key = f"analysis-results/{image_id}.json"
        s3.put_object(
            Bucket=RESULTS_BUCKET,
            Key=key,
            Body=json.dumps(results, indent=2, default=decimal_default),
            ContentType='application/json'
        )
        print(f"Stored results in S3: {key}")
    except Exception as e:
        print(f"Error storing results in S3: {str(e)}")

def store_summary_in_dynamodb(results):
    """
    Store analysis summary in DynamoDB
    """
    try:
        # Create a summary record
        table.put_item(
            Item={
                'imageId': results['imageId'],
                'analysisType': 'SUMMARY',
                'timestamp': results['timestamp'],
                'bucket': results['bucket'],
                'key': results['key'],
                'faceCount': results['analyses'].get('faces', {}).get('faceCount', 0),
                'labelCount': results['analyses'].get('labels', {}).get('labelCount', 0),
                'textCount': results['analyses'].get('text', {}).get('textCount', 0),
                'celebrityCount': results['analyses'].get('celebrities', {}).get('celebrityCount', 0),
                'moderationStatus': 'FLAGGED' if results['analyses'].get('moderation', {}).get('isInappropriate', False) else 'APPROVED'
            }
        )
    except Exception as e:
        print(f"Error storing summary in DynamoDB: {str(e)}")

def decimal_default(obj):
    """
    JSON serializer for Decimal objects
    """
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
      `),
    });

    // =====================================================
    // Face Collection Management Lambda
    // =====================================================

    const faceCollectionLogGroup = new logs.LogGroup(this, 'FaceCollectionLogGroup', {
      logGroupName: `/aws/lambda/rekognition-face-collection-${uniqueSuffix}`,
      retention: logs.RetentionDays.ONE_WEEK,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    const faceCollectionFunction = new lambda.Function(this, 'FaceCollectionFunction', {
      functionName: `rekognition-face-collection-${uniqueSuffix}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.lambda_handler',
      role: lambdaRole,
      timeout: cdk.Duration.minutes(3),
      memorySize: 512,
      environment: {
        FACE_COLLECTION_ID: `face-collection-${uniqueSuffix}`,
        ANALYSIS_TABLE: analysisTable.tableName,
      },
      logGroup: faceCollectionLogGroup,
      code: lambda.Code.fromInline(`
import json
import boto3
import os
from decimal import Decimal

# Initialize AWS clients
rekognition = boto3.client('rekognition')
dynamodb = boto3.resource('dynamodb')

# Environment variables
FACE_COLLECTION_ID = os.environ['FACE_COLLECTION_ID']
ANALYSIS_TABLE = os.environ['ANALYSIS_TABLE']

table = dynamodb.Table(ANALYSIS_TABLE)

def lambda_handler(event, context):
    """
    Handle face collection operations: create, delete, search, index
    """
    try:
        action = event.get('action', 'list')
        
        if action == 'create':
            return create_collection()
        elif action == 'delete':
            return delete_collection()
        elif action == 'list':
            return list_collections()
        elif action == 'describe':
            return describe_collection()
        elif action == 'index_face':
            return index_face(event)
        elif action == 'search_face':
            return search_face(event)
        elif action == 'list_faces':
            return list_faces()
        else:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': f'Unknown action: {action}'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def create_collection():
    """Create a new face collection"""
    try:
        response = rekognition.create_collection(CollectionId=FACE_COLLECTION_ID)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Collection created successfully',
                'collectionId': FACE_COLLECTION_ID,
                'collectionArn': response['CollectionArn']
            })
        }
    except rekognition.exceptions.ResourceAlreadyExistsException:
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Collection already exists',
                'collectionId': FACE_COLLECTION_ID
            })
        }

def delete_collection():
    """Delete the face collection"""
    try:
        rekognition.delete_collection(CollectionId=FACE_COLLECTION_ID)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Collection deleted successfully',
                'collectionId': FACE_COLLECTION_ID
            })
        }
    except rekognition.exceptions.ResourceNotFoundException:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Collection not found'})
        }

def list_collections():
    """List all face collections"""
    try:
        response = rekognition.list_collections()
        return {
            'statusCode': 200,
            'body': json.dumps({
                'collections': response['CollectionIds'],
                'currentCollection': FACE_COLLECTION_ID
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def describe_collection():
    """Get collection details"""
    try:
        response = rekognition.describe_collection(CollectionId=FACE_COLLECTION_ID)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'collectionId': FACE_COLLECTION_ID,
                'faceCount': response['FaceCount'],
                'collectionArn': response['CollectionARN'],
                'creationTimestamp': response['CreationTimestamp'].isoformat()
            }, default=str)
        }
    except rekognition.exceptions.ResourceNotFoundException:
        return {
            'statusCode': 404,
            'body': json.dumps({'error': 'Collection not found'})
        }

def index_face(event):
    """Index a face in the collection"""
    try:
        bucket = event['bucket']
        key = event['key']
        external_image_id = event.get('externalImageId', key)
        
        response = rekognition.index_faces(
            CollectionId=FACE_COLLECTION_ID,
            Image={'S3Object': {'Bucket': bucket, 'Name': key}},
            ExternalImageId=external_image_id,
            DetectionAttributes=['ALL']
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Face indexed successfully',
                'faceRecords': response['FaceRecords'],
                'unindexedFaces': response['UnindexedFaces']
            }, default=decimal_default)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def search_face(event):
    """Search for faces in the collection"""
    try:
        bucket = event['bucket']
        key = event['key']
        max_faces = event.get('maxFaces', 10)
        threshold = event.get('threshold', 80)
        
        response = rekognition.search_faces_by_image(
            CollectionId=FACE_COLLECTION_ID,
            Image={'S3Object': {'Bucket': bucket, 'Name': key}},
            MaxFaces=max_faces,
            FaceMatchThreshold=threshold
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'faceMatches': response['FaceMatches'],
                'searchedFaceBoundingBox': response['SearchedFaceBoundingBox'],
                'searchedFaceConfidence': response['SearchedFaceConfidence']
            }, default=decimal_default)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def list_faces():
    """List all faces in the collection"""
    try:
        response = rekognition.list_faces(CollectionId=FACE_COLLECTION_ID)
        return {
            'statusCode': 200,
            'body': json.dumps({
                'faces': response['Faces'],
                'nextToken': response.get('NextToken')
            }, default=decimal_default)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }

def decimal_default(obj):
    """JSON serializer for Decimal objects"""
    if isinstance(obj, Decimal):
        return float(obj)
    raise TypeError
      `),
    });

    // =====================================================
    // API Gateway for External Access
    // =====================================================

    // REST API for external access to computer vision capabilities
    const api = new apigateway.RestApi(this, 'ComputerVisionApi', {
      restApiName: `rekognition-api-${uniqueSuffix}`,
      description: 'API for Amazon Rekognition Computer Vision Solutions',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key', 'X-Amz-Security-Token'],
      },
      endpointConfiguration: {
        types: [apigateway.EndpointType.REGIONAL],
      },
    });

    // Lambda integrations
    const imageProcessorIntegration = new apigateway.LambdaIntegration(imageProcessorFunction, {
      requestTemplates: {
        'application/json': '{ "statusCode": "200" }',
      },
    });

    const faceCollectionIntegration = new apigateway.LambdaIntegration(faceCollectionFunction, {
      requestTemplates: {
        'application/json': '{ "statusCode": "200" }',
      },
    });

    // API Resources and Methods
    const analyzeResource = api.root.addResource('analyze');
    analyzeResource.addMethod('POST', imageProcessorIntegration, {
      methodResponses: [
        {
          statusCode: '200',
          responseHeaders: {
            'Access-Control-Allow-Origin': true,
            'Access-Control-Allow-Headers': true,
            'Access-Control-Allow-Methods': true,
          },
        },
      ],
    });

    const facesResource = api.root.addResource('faces');
    facesResource.addMethod('POST', faceCollectionIntegration);
    facesResource.addMethod('GET', faceCollectionIntegration);

    // =====================================================
    // S3 Event Trigger for Automatic Processing
    // =====================================================

    // Automatically process images when uploaded to the S3 bucket
    imageBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(imageProcessorFunction),
      {
        prefix: 'images/',
        suffix: '.jpg',
      }
    );

    imageBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(imageProcessorFunction),
      {
        prefix: 'images/',
        suffix: '.jpeg',
      }
    );

    imageBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(imageProcessorFunction),
      {
        prefix: 'images/',
        suffix: '.png',
      }
    );

    // =====================================================
    // CloudFormation Outputs
    // =====================================================

    // Output important resource information
    new cdk.CfnOutput(this, 'ImageBucketName', {
      value: imageBucket.bucketName,
      description: 'S3 bucket for uploading images to analyze',
      exportName: `${this.stackName}-ImageBucket`,
    });

    new cdk.CfnOutput(this, 'ResultsBucketName', {
      value: resultsBucket.bucketName,
      description: 'S3 bucket containing analysis results',
      exportName: `${this.stackName}-ResultsBucket`,
    });

    new cdk.CfnOutput(this, 'AnalysisTableName', {
      value: analysisTable.tableName,
      description: 'DynamoDB table containing analysis metadata',
      exportName: `${this.stackName}-AnalysisTable`,
    });

    new cdk.CfnOutput(this, 'FaceCollectionId', {
      value: `face-collection-${uniqueSuffix}`,
      description: 'Rekognition face collection ID for face recognition',
      exportName: `${this.stackName}-FaceCollection`,
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint for computer vision operations',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'ImageProcessorFunctionName', {
      value: imageProcessorFunction.functionName,
      description: 'Lambda function for image processing',
      exportName: `${this.stackName}-ImageProcessor`,
    });

    new cdk.CfnOutput(this, 'FaceCollectionFunctionName', {
      value: faceCollectionFunction.functionName,
      description: 'Lambda function for face collection management',
      exportName: `${this.stackName}-FaceCollectionManager`,
    });

    // Output CLI commands for testing
    new cdk.CfnOutput(this, 'TestCommands', {
      value: JSON.stringify({
        uploadImage: `aws s3 cp your-image.jpg s3://${imageBucket.bucketName}/images/`,
        analyzeViaApi: `curl -X POST ${api.url}analyze -H "Content-Type: application/json" -d '{"bucket":"${imageBucket.bucketName}","key":"images/your-image.jpg"}'`,
        createFaceCollection: `aws lambda invoke --function-name ${faceCollectionFunction.functionName} --payload '{"action":"create"}' response.json`,
        queryResults: `aws dynamodb scan --table-name ${analysisTable.tableName}`,
      }),
      description: 'CLI commands for testing the computer vision system',
    });
  }
}

// =====================================================
// CDK App Definition
// =====================================================

const app = new cdk.App();

// Create the stack with comprehensive computer vision capabilities
new ComputerVisionRekognitionStack(app, 'ComputerVisionRekognitionStack', {
  description: 'Computer Vision Solutions using Amazon Rekognition - Face detection, object recognition, text extraction, and content moderation',
  
  // Stack-level tags for resource management
  tags: {
    Project: 'ComputerVisionSolutions',
    Technology: 'AmazonRekognition',
    Environment: 'Demo',
    CostCenter: 'Research',
    Owner: 'CloudEngineering',
  },

  // Enhanced termination protection for production environments
  terminationProtection: false,

  // Environment-specific configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
});

// Add global tags to all resources in the app
cdk.Tags.of(app).add('Application', 'ComputerVisionRekognition');
cdk.Tags.of(app).add('Repository', 'aws-recipes');
cdk.Tags.of(app).add('RecipeId', 'bba7810a');