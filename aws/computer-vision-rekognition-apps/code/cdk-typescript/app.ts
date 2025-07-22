#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as kinesisVideo from 'aws-cdk-lib/aws-kinesisvideo';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as s3n from 'aws-cdk-lib/aws-s3-notifications';
import { RemovalPolicy, Duration, CfnOutput } from 'aws-cdk-lib';

/**
 * Props for the ComputerVisionStack
 */
interface ComputerVisionStackProps extends cdk.StackProps {
  readonly faceCollectionName?: string;
  readonly streamRetentionHours?: number;
  readonly faceMatchThreshold?: number;
}

/**
 * Computer Vision Applications Stack using Amazon Rekognition
 * 
 * This stack creates a comprehensive computer vision application that includes:
 * - S3 bucket for storing images and videos
 * - IAM roles for Rekognition service access
 * - Kinesis Video Stream for real-time video ingestion
 * - Kinesis Data Stream for streaming results
 * - Lambda functions for processing and analysis
 * - API Gateway for RESTful endpoints
 * - SNS topic for notifications
 * - SQS queue for reliable message processing
 */
export class ComputerVisionStack extends cdk.Stack {
  
  public readonly mediaBucket: s3.Bucket;
  public readonly resultsBucket: s3.Bucket;
  public readonly kinesisVideoStream: kinesisVideo.CfnStream;
  public readonly kinesisDataStream: kinesis.Stream;
  public readonly rekognitionRole: iam.Role;
  public readonly processImageFunction: lambda.Function;
  public readonly processVideoFunction: lambda.Function;
  public readonly api: apigateway.RestApi;

  constructor(scope: Construct, id: string, props: ComputerVisionStackProps = {}) {
    super(scope, id, props);

    // Default configuration values
    const faceCollectionName = props.faceCollectionName || `cv-faces-${this.account}-${this.region}`;
    const streamRetentionHours = props.streamRetentionHours || 24;
    const faceMatchThreshold = props.faceMatchThreshold || 80.0;

    // Create S3 bucket for storing media files (images and videos)
    this.mediaBucket = new s3.Bucket(this, 'MediaBucket', {
      bucketName: `computer-vision-media-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteIncompleteMultipartUploads',
          abortIncompleteMultipartUploadAfter: Duration.days(1),
        },
        {
          id: 'TransitionToIA',
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: Duration.days(30),
            },
          ],
        },
      ],
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.POST,
            s3.HttpMethods.PUT,
            s3.HttpMethods.DELETE,
          ],
          allowedOrigins: ['*'],
          allowedHeaders: ['*'],
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create S3 bucket for storing analysis results
    this.resultsBucket = new s3.Bucket(this, 'ResultsBucket', {
      bucketName: `computer-vision-results-${this.account}-${this.region}`,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      lifecycleRules: [
        {
          id: 'DeleteOldResults',
          expiration: Duration.days(90),
        },
      ],
      removalPolicy: RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
    });

    // Create IAM role for Amazon Rekognition service
    this.rekognitionRole = new iam.Role(this, 'RekognitionServiceRole', {
      roleName: `RekognitionVideoAnalysisRole-${this.region}`,
      assumedBy: new iam.ServicePrincipal('rekognition.amazonaws.com'),
      description: 'IAM role for Amazon Rekognition video analysis operations',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AmazonRekognitionServiceRole'),
      ],
    });

    // Grant Rekognition role access to the media bucket
    this.mediaBucket.grantRead(this.rekognitionRole);

    // Create Kinesis Video Stream for real-time video ingestion
    this.kinesisVideoStream = new kinesisVideo.CfnStream(this, 'VideoStream', {
      name: `computer-vision-video-${this.region}`,
      dataRetentionInHours: streamRetentionHours,
      deviceName: 'security-camera-feed',
      mediaType: 'video/h264',
      tags: [
        {
          key: 'Purpose',
          value: 'ComputerVisionAnalysis',
        },
        {
          key: 'Environment',
          value: 'Production',
        },
      ],
    });

    // Create Kinesis Data Stream for streaming analysis results
    this.kinesisDataStream = new kinesis.Stream(this, 'ResultsStream', {
      streamName: `computer-vision-results-${this.region}`,
      shardCount: 1,
      retentionPeriod: Duration.hours(24),
      encryption: kinesis.StreamEncryption.MANAGED,
    });

    // Grant Rekognition role permission to write to Kinesis Data Stream
    this.kinesisDataStream.grantWrite(this.rekognitionRole);

    // Create SNS topic for notifications
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: `computer-vision-notifications-${this.region}`,
      displayName: 'Computer Vision Analysis Notifications',
    });

    // Create SQS queue for reliable processing
    const processingQueue = new sqs.Queue(this, 'ProcessingQueue', {
      queueName: `computer-vision-processing-${this.region}`,
      visibilityTimeout: Duration.minutes(5),
      messageRetentionPeriod: Duration.days(7),
      deadLetterQueue: {
        queue: new sqs.Queue(this, 'ProcessingDeadLetterQueue', {
          queueName: `computer-vision-dlq-${this.region}`,
        }),
        maxReceiveCount: 3,
      },
    });

    // Create Lambda function for processing images
    this.processImageFunction = new lambda.Function(this, 'ProcessImageFunction', {
      functionName: `process-image-${this.region}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: Duration.minutes(5),
      memorySize: 512,
      environment: {
        FACE_COLLECTION_NAME: faceCollectionName,
        FACE_MATCH_THRESHOLD: faceMatchThreshold.toString(),
        RESULTS_BUCKET: this.resultsBucket.bucketName,
        NOTIFICATION_TOPIC_ARN: notificationTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')
sns = boto3.client('sns')

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Process image using Amazon Rekognition for comprehensive analysis
    
    Performs multiple types of analysis:
    - Object and scene detection
    - Facial analysis with demographics
    - Face search against collections
    - Text detection
    - Content moderation
    """
    try:
        # Parse S3 event
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        object_key = event['Records'][0]['s3']['object']['key']
        
        logger.info(f"Processing image: s3://{bucket_name}/{object_key}")
        
        # Skip non-image files
        if not object_key.lower().endswith(('.jpg', '.jpeg', '.png')):
            logger.info(f"Skipping non-image file: {object_key}")
            return {'statusCode': 200, 'body': 'Skipped non-image file'}
        
        # Prepare image reference for Rekognition
        image = {
            'S3Object': {
                'Bucket': bucket_name,
                'Name': object_key
            }
        }
        
        # Perform comprehensive image analysis
        analysis_results = {}
        
        # 1. Detect labels (objects, scenes, activities)
        try:
            labels_response = rekognition.detect_labels(
                Image=image,
                Features=['GENERAL_LABELS', 'IMAGE_PROPERTIES'],
                Settings={
                    'GeneralLabels': {
                        'MaxLabels': 20
                    },
                    'ImageProperties': {
                        'MaxDominantColors': 10
                    }
                }
            )
            analysis_results['labels'] = labels_response
            logger.info(f"Detected {len(labels_response.get('Labels', []))} labels")
        except Exception as e:
            logger.error(f"Label detection failed: {str(e)}")
            analysis_results['labels'] = {'error': str(e)}
        
        # 2. Detect and analyze faces
        try:
            faces_response = rekognition.detect_faces(
                Image=image,
                Attributes=['ALL']
            )
            analysis_results['faces'] = faces_response
            logger.info(f"Detected {len(faces_response.get('FaceDetails', []))} faces")
        except Exception as e:
            logger.error(f"Face detection failed: {str(e)}")
            analysis_results['faces'] = {'error': str(e)}
        
        # 3. Search faces in collection (if collection exists)
        try:
            face_collection_name = os.environ.get('FACE_COLLECTION_NAME')
            face_match_threshold = float(os.environ.get('FACE_MATCH_THRESHOLD', '80'))
            
            face_search_response = rekognition.search_faces_by_image(
                Image=image,
                CollectionId=face_collection_name,
                FaceMatchThreshold=face_match_threshold
            )
            analysis_results['face_matches'] = face_search_response
            logger.info(f"Found {len(face_search_response.get('FaceMatches', []))} face matches")
        except rekognition.exceptions.ResourceNotFoundException:
            logger.warning(f"Face collection {face_collection_name} not found")
            analysis_results['face_matches'] = {'error': 'Collection not found'}
        except Exception as e:
            logger.error(f"Face search failed: {str(e)}")
            analysis_results['face_matches'] = {'error': str(e)}
        
        # 4. Detect text
        try:
            text_response = rekognition.detect_text(Image=image)
            analysis_results['text'] = text_response
            detected_text = [t['DetectedText'] for t in text_response.get('TextDetections', []) if t['Type'] == 'LINE']
            logger.info(f"Detected text: {', '.join(detected_text) if detected_text else 'None'}")
        except Exception as e:
            logger.error(f"Text detection failed: {str(e)}")
            analysis_results['text'] = {'error': str(e)}
        
        # 5. Content moderation
        try:
            moderation_response = rekognition.detect_moderation_labels(Image=image)
            analysis_results['moderation'] = moderation_response
            moderation_labels = moderation_response.get('ModerationLabels', [])
            if moderation_labels:
                logger.warning(f"Content moderation flags: {[l['Name'] for l in moderation_labels]}")
        except Exception as e:
            logger.error(f"Content moderation failed: {str(e)}")
            analysis_results['moderation'] = {'error': str(e)}
        
        # Store results in S3
        results_key = f"image-analysis/{datetime.now().isoformat()}/{object_key.split('/')[-1]}.json"
        results_bucket = os.environ.get('RESULTS_BUCKET')
        
        s3.put_object(
            Bucket=results_bucket,
            Key=results_key,
            Body=json.dumps(analysis_results, default=str),
            ContentType='application/json'
        )
        
        # Send notification if significant results found
        high_confidence_labels = [l for l in analysis_results.get('labels', {}).get('Labels', []) if l.get('Confidence', 0) > 90]
        faces_detected = len(analysis_results.get('faces', {}).get('FaceDetails', []))
        face_matches = len(analysis_results.get('face_matches', {}).get('FaceMatches', []))
        
        if high_confidence_labels or faces_detected > 0 or face_matches > 0:
            notification_message = {
                'image': f"s3://{bucket_name}/{object_key}",
                'results_location': f"s3://{results_bucket}/{results_key}",
                'summary': {
                    'high_confidence_labels': len(high_confidence_labels),
                    'faces_detected': faces_detected,
                    'face_matches': face_matches,
                    'text_detected': len(analysis_results.get('text', {}).get('TextDetections', [])),
                    'moderation_flags': len(analysis_results.get('moderation', {}).get('ModerationLabels', []))
                }
            }
            
            sns.publish(
                TopicArn=os.environ.get('NOTIFICATION_TOPIC_ARN'),
                Subject=f'Computer Vision Analysis Complete: {object_key}',
                Message=json.dumps(notification_message, indent=2)
            )
        
        logger.info(f"Analysis complete for {object_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Image analysis completed successfully',
                'results_location': f"s3://{results_bucket}/{results_key}",
                'summary': {
                    'labels': len(analysis_results.get('labels', {}).get('Labels', [])),
                    'faces': faces_detected,
                    'face_matches': face_matches
                }
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing image: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`),
    });

    // Create Lambda function for processing videos
    this.processVideoFunction = new lambda.Function(this, 'ProcessVideoFunction', {
      functionName: `process-video-${this.region}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: Duration.minutes(15),
      memorySize: 1024,
      environment: {
        FACE_COLLECTION_NAME: faceCollectionName,
        RESULTS_BUCKET: this.resultsBucket.bucketName,
        REKOGNITION_ROLE_ARN: this.rekognitionRole.roleArn,
        NOTIFICATION_TOPIC_ARN: notificationTopic.topicArn,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
import time
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')
sns = boto3.client('sns')

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    Process video using Amazon Rekognition for comprehensive analysis
    
    Starts asynchronous video analysis jobs for:
    - Face detection and tracking
    - Object and activity detection
    - Person tracking and movement analysis
    """
    try:
        # Parse S3 event
        bucket_name = event['Records'][0]['s3']['bucket']['name']
        object_key = event['Records'][0]['s3']['object']['key']
        
        logger.info(f"Processing video: s3://{bucket_name}/{object_key}")
        
        # Skip non-video files
        if not object_key.lower().endswith(('.mp4', '.avi', '.mov', '.mkv')):
            logger.info(f"Skipping non-video file: {object_key}")
            return {'statusCode': 200, 'body': 'Skipped non-video file'}
        
        # Prepare video reference for Rekognition
        video = {
            'S3Object': {
                'Bucket': bucket_name,
                'Name': object_key
            }
        }
        
        role_arn = os.environ.get('REKOGNITION_ROLE_ARN')
        job_results = {}
        
        # Start video analysis jobs
        
        # 1. Start face detection job
        try:
            face_detection_response = rekognition.start_face_detection(
                Video=video,
                FaceAttributes='ALL'
            )
            job_results['face_detection_job'] = face_detection_response['JobId']
            logger.info(f"Started face detection job: {face_detection_response['JobId']}")
        except Exception as e:
            logger.error(f"Failed to start face detection job: {str(e)}")
            job_results['face_detection_job'] = {'error': str(e)}
        
        # 2. Start label detection job
        try:
            label_detection_response = rekognition.start_label_detection(
                Video=video,
                Features=['GENERAL_LABELS']
            )
            job_results['label_detection_job'] = label_detection_response['JobId']
            logger.info(f"Started label detection job: {label_detection_response['JobId']}")
        except Exception as e:
            logger.error(f"Failed to start label detection job: {str(e)}")
            job_results['label_detection_job'] = {'error': str(e)}
        
        # 3. Start person tracking job
        try:
            person_tracking_response = rekognition.start_person_tracking(
                Video=video
            )
            job_results['person_tracking_job'] = person_tracking_response['JobId']
            logger.info(f"Started person tracking job: {person_tracking_response['JobId']}")
        except Exception as e:
            logger.error(f"Failed to start person tracking job: {str(e)}")
            job_results['person_tracking_job'] = {'error': str(e)}
        
        # Store job information
        job_info = {
            'video_location': f"s3://{bucket_name}/{object_key}",
            'jobs': job_results,
            'started_at': datetime.now().isoformat(),
            'status': 'IN_PROGRESS'
        }
        
        results_key = f"video-jobs/{datetime.now().isoformat()}/{object_key.split('/')[-1]}.json"
        results_bucket = os.environ.get('RESULTS_BUCKET')
        
        s3.put_object(
            Bucket=results_bucket,
            Key=results_key,
            Body=json.dumps(job_info, default=str),
            ContentType='application/json'
        )
        
        # Send notification about job start
        notification_message = {
            'video': f"s3://{bucket_name}/{object_key}",
            'job_info_location': f"s3://{results_bucket}/{results_key}",
            'jobs_started': {k: v for k, v in job_results.items() if isinstance(v, str)},
            'message': 'Video analysis jobs started. Results will be available when processing completes.'
        }
        
        sns.publish(
            TopicArn=os.environ.get('NOTIFICATION_TOPIC_ARN'),
            Subject=f'Video Analysis Started: {object_key}',
            Message=json.dumps(notification_message, indent=2)
        )
        
        logger.info(f"Video analysis jobs started for {object_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Video analysis jobs started successfully',
                'job_info_location': f"s3://{results_bucket}/{results_key}",
                'jobs': job_results
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing video: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
`),
    });

    // Grant necessary permissions to Lambda functions
    this.mediaBucket.grantRead(this.processImageFunction);
    this.resultsBucket.grantWrite(this.processImageFunction);
    this.resultsBucket.grantWrite(this.processVideoFunction);
    notificationTopic.grantPublish(this.processImageFunction);
    notificationTopic.grantPublish(this.processVideoFunction);

    // Grant Rekognition permissions to Lambda functions
    this.processImageFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'rekognition:DetectLabels',
        'rekognition:DetectFaces',
        'rekognition:SearchFacesByImage',
        'rekognition:DetectText',
        'rekognition:DetectModerationLabels',
        'rekognition:CreateCollection',
        'rekognition:IndexFaces',
        'rekognition:ListCollections',
        'rekognition:DescribeCollection',
      ],
      resources: ['*'],
    }));

    this.processVideoFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'rekognition:StartFaceDetection',
        'rekognition:StartLabelDetection',
        'rekognition:StartPersonTracking',
        'rekognition:GetFaceDetection',
        'rekognition:GetLabelDetection',
        'rekognition:GetPersonTracking',
        'rekognition:CreateStreamProcessor',
        'rekognition:StartStreamProcessor',
        'rekognition:StopStreamProcessor',
        'rekognition:DeleteStreamProcessor',
      ],
      resources: ['*'],
    }));

    // Grant IAM PassRole permission to video processing function
    this.processVideoFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: ['iam:PassRole'],
      resources: [this.rekognitionRole.roleArn],
    }));

    // Configure S3 event notifications
    this.mediaBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.processImageFunction),
      { prefix: 'images/' }
    );

    this.mediaBucket.addEventNotification(
      s3.EventType.OBJECT_CREATED,
      new s3n.LambdaDestination(this.processVideoFunction),
      { prefix: 'videos/' }
    );

    // Create API Gateway for REST endpoints
    this.api = new apigateway.RestApi(this, 'ComputerVisionApi', {
      restApiName: `computer-vision-api-${this.region}`,
      description: 'REST API for Computer Vision Applications',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // Create Lambda function for API operations
    const apiFunction = new lambda.Function(this, 'ApiFunction', {
      functionName: `computer-vision-api-${this.region}`,
      runtime: lambda.Runtime.PYTHON_3_11,
      handler: 'index.handler',
      timeout: Duration.minutes(1),
      memorySize: 256,
      environment: {
        FACE_COLLECTION_NAME: faceCollectionName,
        MEDIA_BUCKET: this.mediaBucket.bucketName,
        RESULTS_BUCKET: this.resultsBucket.bucketName,
        KINESIS_VIDEO_STREAM: this.kinesisVideoStream.name!,
        KINESIS_DATA_STREAM: this.kinesisDataStream.streamName,
      },
      code: lambda.Code.fromInline(`
import json
import boto3
import logging
import os
from datetime import datetime
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')

def handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    """
    API Gateway handler for Computer Vision operations
    
    Supports endpoints for:
    - GET /collections - List face collections
    - POST /collections - Create face collection
    - GET /collections/{id}/faces - List faces in collection
    - POST /collections/{id}/faces - Add face to collection
    - GET /analysis/{type} - Get analysis results
    """
    try:
        http_method = event.get('httpMethod', '')
        resource_path = event.get('resource', '')
        path_parameters = event.get('pathParameters') or {}
        
        logger.info(f"API request: {http_method} {resource_path}")
        
        # Handle different API endpoints
        if resource_path == '/collections' and http_method == 'GET':
            return list_collections()
        elif resource_path == '/collections' and http_method == 'POST':
            return create_collection(event)
        elif resource_path == '/collections/{collection_id}/faces' and http_method == 'GET':
            return list_faces(path_parameters.get('collection_id'))
        elif resource_path == '/collections/{collection_id}/faces' and http_method == 'POST':
            return add_face_to_collection(path_parameters.get('collection_id'), event)
        elif resource_path == '/analysis/{type}' and http_method == 'GET':
            return get_analysis_results(path_parameters.get('type'), event)
        else:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Endpoint not found'})
            }
            
    except Exception as e:
        logger.error(f"API error: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def list_collections() -> Dict[str, Any]:
    """List all Rekognition face collections"""
    try:
        response = rekognition.list_collections()
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'collections': response.get('CollectionIds', []),
                'count': len(response.get('CollectionIds', []))
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def create_collection(event: Dict[str, Any]) -> Dict[str, Any]:
    """Create a new face collection"""
    try:
        body = json.loads(event.get('body', '{}'))
        collection_id = body.get('collection_id') or os.environ.get('FACE_COLLECTION_NAME')
        
        response = rekognition.create_collection(CollectionId=collection_id)
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'collection_id': collection_id,
                'collection_arn': response.get('CollectionArn'),
                'status_code': response.get('StatusCode')
            })
        }
    except rekognition.exceptions.ResourceAlreadyExistsException:
        return {
            'statusCode': 409,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Collection already exists'})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def list_faces(collection_id: str) -> Dict[str, Any]:
    """List faces in a collection"""
    try:
        if not collection_id:
            collection_id = os.environ.get('FACE_COLLECTION_NAME')
            
        response = rekognition.list_faces(CollectionId=collection_id)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'collection_id': collection_id,
                'faces': response.get('Faces', []),
                'count': len(response.get('Faces', []))
            }, default=str)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def add_face_to_collection(collection_id: str, event: Dict[str, Any]) -> Dict[str, Any]:
    """Add a face to collection from S3 image"""
    try:
        body = json.loads(event.get('body', '{}'))
        bucket_name = body.get('bucket', os.environ.get('MEDIA_BUCKET'))
        object_key = body.get('key')
        external_image_id = body.get('external_image_id')
        
        if not object_key or not external_image_id:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing required parameters: key, external_image_id'})
            }
        
        if not collection_id:
            collection_id = os.environ.get('FACE_COLLECTION_NAME')
        
        response = rekognition.index_faces(
            CollectionId=collection_id,
            Image={
                'S3Object': {
                    'Bucket': bucket_name,
                    'Name': object_key
                }
            },
            ExternalImageId=external_image_id,
            DetectionAttributes=['ALL']
        )
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'collection_id': collection_id,
                'external_image_id': external_image_id,
                'face_records': response.get('FaceRecords', []),
                'faces_indexed': len(response.get('FaceRecords', []))
            }, default=str)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }

def get_analysis_results(analysis_type: str, event: Dict[str, Any]) -> Dict[str, Any]:
    """Get analysis results from S3"""
    try:
        query_params = event.get('queryStringParameters') or {}
        results_bucket = os.environ.get('RESULTS_BUCKET')
        
        # List recent analysis results
        prefix = f"{analysis_type}-analysis/" if analysis_type in ['image', 'video'] else 'image-analysis/'
        
        response = s3.list_objects_v2(
            Bucket=results_bucket,
            Prefix=prefix,
            MaxKeys=10
        )
        
        results = []
        for obj in response.get('Contents', []):
            try:
                # Get the analysis result
                result_obj = s3.get_object(Bucket=results_bucket, Key=obj['Key'])
                result_data = json.loads(result_obj['Body'].read())
                
                results.append({
                    'key': obj['Key'],
                    'last_modified': obj['LastModified'],
                    'size': obj['Size'],
                    'analysis': result_data
                })
            except Exception as e:
                logger.warning(f"Failed to read result {obj['Key']}: {str(e)}")
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'analysis_type': analysis_type,
                'results_count': len(results),
                'results': results
            }, default=str)
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }
`),
    });

    // Grant API function necessary permissions
    this.mediaBucket.grantReadWrite(apiFunction);
    this.resultsBucket.grantReadWrite(apiFunction);
    apiFunction.addToRolePolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'rekognition:CreateCollection',
        'rekognition:ListCollections',
        'rekognition:DescribeCollection',
        'rekognition:IndexFaces',
        'rekognition:ListFaces',
        'rekognition:SearchFaces',
        'rekognition:SearchFacesByImage',
      ],
      resources: ['*'],
    }));

    // Create API Gateway resources and methods
    const collectionsResource = this.api.root.addResource('collections');
    const collectionIdResource = collectionsResource.addResource('{collection_id}');
    const facesResource = collectionIdResource.addResource('faces');
    const analysisResource = this.api.root.addResource('analysis');
    const analysisTypeResource = analysisResource.addResource('{type}');

    // Create Lambda integrations
    const lambdaIntegration = new apigateway.LambdaIntegration(apiFunction);

    // Add methods to API Gateway
    collectionsResource.addMethod('GET', lambdaIntegration);
    collectionsResource.addMethod('POST', lambdaIntegration);
    facesResource.addMethod('GET', lambdaIntegration);
    facesResource.addMethod('POST', lambdaIntegration);
    analysisTypeResource.addMethod('GET', lambdaIntegration);

    // CloudFormation outputs for important resources
    new CfnOutput(this, 'MediaBucketName', {
      value: this.mediaBucket.bucketName,
      description: 'Name of the S3 bucket for storing media files',
      exportName: `${this.stackName}-MediaBucketName`,
    });

    new CfnOutput(this, 'ResultsBucketName', {
      value: this.resultsBucket.bucketName,
      description: 'Name of the S3 bucket for storing analysis results',
      exportName: `${this.stackName}-ResultsBucketName`,
    });

    new CfnOutput(this, 'ApiEndpoint', {
      value: this.api.url,
      description: 'URL of the Computer Vision API Gateway',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new CfnOutput(this, 'KinesisVideoStreamName', {
      value: this.kinesisVideoStream.name!,
      description: 'Name of the Kinesis Video Stream',
      exportName: `${this.stackName}-KinesisVideoStreamName`,
    });

    new CfnOutput(this, 'KinesisDataStreamName', {
      value: this.kinesisDataStream.streamName,
      description: 'Name of the Kinesis Data Stream for results',
      exportName: `${this.stackName}-KinesisDataStreamName`,
    });

    new CfnOutput(this, 'RekognitionRoleArn', {
      value: this.rekognitionRole.roleArn,
      description: 'ARN of the IAM role for Rekognition video analysis',
      exportName: `${this.stackName}-RekognitionRoleArn`,
    });

    new CfnOutput(this, 'FaceCollectionName', {
      value: faceCollectionName,
      description: 'Name of the Rekognition face collection',
      exportName: `${this.stackName}-FaceCollectionName`,
    });

    new CfnOutput(this, 'NotificationTopicArn', {
      value: notificationTopic.topicArn,
      description: 'ARN of the SNS topic for notifications',
      exportName: `${this.stackName}-NotificationTopicArn`,
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Create the Computer Vision stack
new ComputerVisionStack(app, 'ComputerVisionStack', {
  description: 'Computer Vision Applications with Amazon Rekognition - Comprehensive solution for image and video analysis',
  
  // Optional configuration (can be overridden via CDK context or environment variables)
  faceCollectionName: app.node.tryGetContext('faceCollectionName'),
  streamRetentionHours: app.node.tryGetContext('streamRetentionHours') || 24,
  faceMatchThreshold: app.node.tryGetContext('faceMatchThreshold') || 80.0,
  
  // Stack-level configuration
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  
  // Add tags for resource management
  tags: {
    Application: 'ComputerVision',
    Component: 'Rekognition',
    Environment: app.node.tryGetContext('environment') || 'development',
    CostCenter: app.node.tryGetContext('costCenter') || 'engineering',
    Owner: app.node.tryGetContext('owner') || 'aws-solutions',
  },
});

// Synthesize the application
app.synth();