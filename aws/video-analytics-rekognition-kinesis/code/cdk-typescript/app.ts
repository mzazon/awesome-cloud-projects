#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as rekognition from 'aws-cdk-lib/aws-rekognition';
import * as kinesis from 'aws-cdk-lib/aws-kinesis';
import * as kinesisVideo from 'aws-cdk-lib/aws-kinesisvideo';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as snsSubscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as eventsources from 'aws-cdk-lib/aws-lambda-event-sources';

/**
 * Interface for configuration parameters
 */
interface VideoAnalyticsStackProps extends cdk.StackProps {
  readonly projectName?: string;
  readonly faceMatchThreshold?: number;
  readonly retentionInHours?: number;
  readonly alertEmail?: string;
}

/**
 * Stack for Real-Time Video Analytics with Amazon Rekognition and Kinesis
 * 
 * This stack creates a comprehensive video analytics platform that processes live video streams
 * from Kinesis Video Streams using Amazon Rekognition for real-time object and face detection.
 * Results are processed by Lambda functions and stored in DynamoDB for analysis and alerting.
 */
export class VideoAnalyticsStack extends cdk.Stack {
  
  // Core service references for integration
  public readonly videoStream: kinesisVideo.CfnStream;
  public readonly dataStream: kinesis.Stream;
  public readonly faceCollection: rekognition.CfnCollection;
  public readonly streamProcessor: rekognition.CfnStreamProcessor;
  public readonly analyticsFunction: lambda.Function;
  public readonly queryApiFunction: lambda.Function;
  public readonly detectionsTable: dynamodb.Table;
  public readonly facesTable: dynamodb.Table;
  public readonly alertsTopic: sns.Topic;
  public readonly queryApi: apigateway.RestApi;

  constructor(scope: Construct, id: string, props: VideoAnalyticsStackProps = {}) {
    super(scope, id, props);

    // Configuration with defaults
    const projectName = props.projectName || 'video-analytics';
    const faceMatchThreshold = props.faceMatchThreshold || 80.0;
    const retentionInHours = props.retentionInHours || 24;
    const alertEmail = props.alertEmail;

    // Create IAM role for video analytics services
    const videoAnalyticsRole = this.createVideoAnalyticsRole();

    // Create Kinesis Video Stream for video ingestion
    this.videoStream = this.createVideoStream(projectName, retentionInHours);

    // Create Kinesis Data Stream for analytics results
    this.dataStream = this.createDataStream(projectName);

    // Create Rekognition face collection for facial recognition
    this.faceCollection = this.createFaceCollection(projectName);

    // Create DynamoDB tables for metadata storage
    const { detectionsTable, facesTable } = this.createDynamoDBTables(projectName);
    this.detectionsTable = detectionsTable;
    this.facesTable = facesTable;

    // Create SNS topic for alerting
    this.alertsTopic = this.createAlertsTopic(projectName, alertEmail);

    // Create Lambda function for analytics processing
    this.analyticsFunction = this.createAnalyticsProcessor(
      projectName,
      this.detectionsTable,
      this.facesTable,
      this.alertsTopic
    );

    // Create Lambda function for query API
    this.queryApiFunction = this.createQueryApiFunction(
      projectName,
      this.detectionsTable,
      this.facesTable
    );

    // Create API Gateway for video analytics queries
    this.queryApi = this.createQueryApi(projectName, this.queryApiFunction);

    // Configure Kinesis Data Stream trigger for analytics processing
    this.configureStreamTrigger();

    // Create Rekognition stream processor for real-time video analysis
    this.streamProcessor = this.createStreamProcessor(
      projectName,
      this.videoStream,
      this.dataStream,
      this.faceCollection,
      videoAnalyticsRole,
      faceMatchThreshold
    );

    // Output key resource information
    this.createOutputs(projectName);

    // Add tags to all resources for organization and cost tracking
    cdk.Tags.of(this).add('Project', projectName);
    cdk.Tags.of(this).add('Application', 'video-analytics');
    cdk.Tags.of(this).add('Environment', 'demo');
  }

  /**
   * Creates IAM role with permissions for video analytics services
   */
  private createVideoAnalyticsRole(): iam.Role {
    const role = new iam.Role(this, 'VideoAnalyticsRole', {
      assumedBy: new iam.CompositePrincipal(
        new iam.ServicePrincipal('lambda.amazonaws.com'),
        new iam.ServicePrincipal('rekognition.amazonaws.com')
      ),
      description: 'Role for video analytics services with Rekognition and Kinesis permissions',
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonRekognitionFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonKinesisVideoStreamsFullAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonKinesisFullAccess')
      ]
    });

    // Add DynamoDB permissions for metadata storage
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'dynamodb:PutItem',
        'dynamodb:GetItem',
        'dynamodb:Query',
        'dynamodb:Scan',
        'dynamodb:UpdateItem',
        'dynamodb:DeleteItem'
      ],
      resources: ['*']
    }));

    // Add SNS permissions for alerting
    role.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'sns:Publish'
      ],
      resources: ['*']
    }));

    return role;
  }

  /**
   * Creates Kinesis Video Stream for video ingestion
   */
  private createVideoStream(projectName: string, retentionInHours: number): kinesisVideo.CfnStream {
    return new kinesisVideo.CfnStream(this, 'VideoStream', {
      name: `${projectName}-video-stream`,
      dataRetentionInHours: retentionInHours,
      mediaType: 'video/h264',
      tags: [{
        key: 'Purpose',
        value: 'VideoIngestion'
      }]
    });
  }

  /**
   * Creates Kinesis Data Stream for analytics results
   */
  private createDataStream(projectName: string): kinesis.Stream {
    return new kinesis.Stream(this, 'AnalyticsDataStream', {
      streamName: `${projectName}-analytics-stream`,
      shardCount: 2,
      retentionPeriod: cdk.Duration.hours(24),
      encryption: kinesis.StreamEncryption.MANAGED,
      streamModeDetails: kinesis.StreamMode.provisioned()
    });
  }

  /**
   * Creates Rekognition face collection for facial recognition
   */
  private createFaceCollection(projectName: string): rekognition.CfnCollection {
    return new rekognition.CfnCollection(this, 'FaceCollection', {
      collectionId: `${projectName}-faces`,
      tags: [{
        key: 'Purpose',
        value: 'FacialRecognition'
      }]
    });
  }

  /**
   * Creates DynamoDB tables for storing detection metadata
   */
  private createDynamoDBTables(projectName: string): {
    detectionsTable: dynamodb.Table;
    facesTable: dynamodb.Table;
  } {
    // Table for general detection events (objects, labels, activities)
    const detectionsTable = new dynamodb.Table(this, 'DetectionsTable', {
      tableName: `${projectName}-detections`,
      partitionKey: {
        name: 'StreamName',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      timeToLiveAttribute: 'TTL'
    });

    // Table for face detection events and metadata
    const facesTable = new dynamodb.Table(this, 'FacesTable', {
      tableName: `${projectName}-faces`,
      partitionKey: {
        name: 'FaceId',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      billingMode: dynamodb.BillingMode.PROVISIONED,
      readCapacity: 5,
      writeCapacity: 5,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      pointInTimeRecovery: true,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // For demo purposes
      timeToLiveAttribute: 'TTL'
    });

    // Add Global Secondary Index for querying by stream name
    facesTable.addGlobalSecondaryIndex({
      indexName: 'StreamNameIndex',
      partitionKey: {
        name: 'StreamName',
        type: dynamodb.AttributeType.STRING
      },
      sortKey: {
        name: 'Timestamp',
        type: dynamodb.AttributeType.NUMBER
      },
      readCapacity: 5,
      writeCapacity: 5
    });

    return { detectionsTable, facesTable };
  }

  /**
   * Creates SNS topic for security alerts and notifications
   */
  private createAlertsTopic(projectName: string, alertEmail?: string): sns.Topic {
    const topic = new sns.Topic(this, 'AlertsTopic', {
      topicName: `${projectName}-security-alerts`,
      displayName: 'Video Analytics Security Alerts',
      fifo: false
    });

    // Add email subscription if provided
    if (alertEmail) {
      topic.addSubscription(new snsSubscriptions.EmailSubscription(alertEmail));
    }

    return topic;
  }

  /**
   * Creates Lambda function for processing analytics events from Kinesis
   */
  private createAnalyticsProcessor(
    projectName: string,
    detectionsTable: dynamodb.Table,
    facesTable: dynamodb.Table,
    alertsTopic: sns.Topic
  ): lambda.Function {
    const analyticsFunction = new lambda.Function(this, 'AnalyticsProcessor', {
      functionName: `${projectName}-analytics-processor`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(60),
      memorySize: 256,
      environment: {
        DETECTIONS_TABLE: detectionsTable.tableName,
        FACES_TABLE: facesTable.tableName,
        SNS_TOPIC_ARN: alertsTopic.topicArn,
        PROJECT_NAME: projectName
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
import base64
import os
from datetime import datetime, timedelta
from decimal import Decimal

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')

# Environment variables
DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
SNS_TOPIC_ARN = os.environ['SNS_TOPIC_ARN']
PROJECT_NAME = os.environ['PROJECT_NAME']

def lambda_handler(event, context):
    """
    Process video analytics events from Kinesis Data Stream
    """
    processed_records = 0
    
    try:
        for record in event['Records']:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            
            # Process the detection event
            process_detection_event(data)
            processed_records += 1
            
        print(f"Successfully processed {processed_records} records")
        
    except Exception as e:
        print(f"Error processing records: {str(e)}")
        raise e
        
    return {
        'statusCode': 200,
        'processedRecords': processed_records
    }

def process_detection_event(data):
    """
    Process individual detection event and route to appropriate handler
    """
    timestamp = int(datetime.now().timestamp() * 1000)
    stream_name = data.get('StreamName', 'unknown')
    
    # Calculate TTL (7 days from now)
    ttl = int((datetime.now() + timedelta(days=7)).timestamp())
    
    try:
        # Process face search results
        if 'FaceSearchResponse' in data:
            process_face_detection(data['FaceSearchResponse'], stream_name, timestamp, ttl)
        
        # Process label detection results
        if 'LabelDetectionResponse' in data:
            process_label_detection(data['LabelDetectionResponse'], stream_name, timestamp, ttl)
        
        # Process person tracking results
        if 'PersonTrackingResponse' in data:
            process_person_tracking(data['PersonTrackingResponse'], stream_name, timestamp, ttl)
            
    except Exception as e:
        print(f"Error processing detection event: {str(e)}")
        raise e

def process_face_detection(face_data, stream_name, timestamp, ttl):
    """
    Process face detection and recognition results
    """
    table = dynamodb.Table(FACES_TABLE)
    
    try:
        face_matches = face_data.get('FaceMatches', [])
        unmatched_faces = face_data.get('UnmatchedFaces', [])
        
        # Process matched faces
        for face_match in face_matches:
            face_id = face_match['Face']['FaceId']
            confidence = face_match['Face']['Confidence']
            similarity = face_match['Similarity']
            
            # Store face detection event
            table.put_item(
                Item={
                    'FaceId': face_id,
                    'Timestamp': timestamp,
                    'StreamName': stream_name,
                    'Confidence': Decimal(str(confidence)),
                    'Similarity': Decimal(str(similarity)),
                    'BoundingBox': face_match['Face']['BoundingBox'],
                    'TTL': ttl,
                    'MatchType': 'Recognized'
                }
            )
            
            # Send alert for high-confidence matches
            if similarity > 90:
                send_alert(
                    f"High Confidence Face Match - {PROJECT_NAME}",
                    f"Recognized face {face_id} with {similarity:.1f}% similarity on stream {stream_name}"
                )
        
        # Process unmatched faces
        for face in unmatched_faces:
            face_id = f"unmatched-{timestamp}"
            confidence = face.get('Confidence', 0)
            
            table.put_item(
                Item={
                    'FaceId': face_id,
                    'Timestamp': timestamp,
                    'StreamName': stream_name,
                    'Confidence': Decimal(str(confidence)),
                    'Similarity': Decimal('0'),
                    'BoundingBox': face.get('BoundingBox', {}),
                    'TTL': ttl,
                    'MatchType': 'Unrecognized'
                }
            )
            
    except Exception as e:
        print(f"Error processing face detection: {str(e)}")
        raise e

def process_label_detection(label_data, stream_name, timestamp, ttl):
    """
    Process object and label detection results
    """
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    try:
        for label in label_data.get('Labels', []):
            label_name = label['Label']['Name']
            confidence = label['Label']['Confidence']
            
            # Store detection event
            table.put_item(
                Item={
                    'StreamName': stream_name,
                    'Timestamp': timestamp,
                    'DetectionType': 'Label',
                    'Label': label_name,
                    'Confidence': Decimal(str(confidence)),
                    'BoundingBox': json.dumps(label['Label'].get('BoundingBox', {})),
                    'TTL': ttl
                }
            )
            
            # Check for security-relevant objects
            security_objects = ['Weapon', 'Gun', 'Knife', 'Person', 'Car', 'Motorcycle', 'Truck']
            if label_name in security_objects and confidence > 80:
                send_alert(
                    f"Security Object Detected - {PROJECT_NAME}",
                    f"Detected {label_name} with {confidence:.1f}% confidence on stream {stream_name}"
                )
                
    except Exception as e:
        print(f"Error processing label detection: {str(e)}")
        raise e

def process_person_tracking(person_data, stream_name, timestamp, ttl):
    """
    Process person tracking results
    """
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    try:
        for person in person_data.get('Persons', []):
            person_id = person.get('Index', 'unknown')
            
            # Store person tracking event
            table.put_item(
                Item={
                    'StreamName': stream_name,
                    'Timestamp': timestamp,
                    'DetectionType': 'Person',
                    'PersonId': str(person_id),
                    'BoundingBox': json.dumps(person.get('BoundingBox', {})),
                    'TTL': ttl
                }
            )
            
    except Exception as e:
        print(f"Error processing person tracking: {str(e)}")
        raise e

def send_alert(subject, message):
    """
    Send alert notification via SNS
    """
    try:
        sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        print(f"Alert sent: {subject}")
        
    except Exception as e:
        print(f"Failed to send alert: {str(e)}")
`)
    });

    // Grant permissions to DynamoDB tables
    detectionsTable.grantReadWriteData(analyticsFunction);
    facesTable.grantReadWriteData(analyticsFunction);
    
    // Grant permission to publish to SNS topic
    alertsTopic.grantPublish(analyticsFunction);

    return analyticsFunction;
  }

  /**
   * Creates Lambda function for the query API
   */
  private createQueryApiFunction(
    projectName: string,
    detectionsTable: dynamodb.Table,
    facesTable: dynamodb.Table
  ): lambda.Function {
    const queryFunction = new lambda.Function(this, 'QueryApiFunction', {
      functionName: `${projectName}-query-api`,
      runtime: lambda.Runtime.PYTHON_3_9,
      handler: 'index.lambda_handler',
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      environment: {
        DETECTIONS_TABLE: detectionsTable.tableName,
        FACES_TABLE: facesTable.tableName,
        PROJECT_NAME: projectName
      },
      logRetention: logs.RetentionDays.ONE_WEEK,
      code: lambda.Code.fromInline(`
import json
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta
from decimal import Decimal

# Initialize DynamoDB resource
dynamodb = boto3.resource('dynamodb')

# Environment variables
DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
PROJECT_NAME = os.environ['PROJECT_NAME']

def lambda_handler(event, context):
    """
    API Gateway Lambda handler for video analytics queries
    """
    try:
        # Parse request
        http_method = event['httpMethod']
        path = event['path']
        query_params = event.get('queryStringParameters', {}) or {}
        
        # Enable CORS
        headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        }
        
        # Handle OPTIONS requests for CORS
        if http_method == 'OPTIONS':
            return {
                'statusCode': 200,
                'headers': headers,
                'body': ''
            }
        
        # Route requests
        if path == '/detections' and http_method == 'GET':
            return get_detections(query_params, headers)
        elif path == '/faces' and http_method == 'GET':
            return get_face_detections(query_params, headers)
        elif path == '/stats' and http_method == 'GET':
            return get_statistics(query_params, headers)
        elif path == '/health' and http_method == 'GET':
            return get_health_check(headers)
        else:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Endpoint not found'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': str(e)})
        }

def get_detections(params, headers):
    """
    Get detection events for a specific stream
    """
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    stream_name = params.get('stream')
    hours_back = int(params.get('hours', 24))
    limit = int(params.get('limit', 100))
    
    if not stream_name:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'stream parameter required'})
        }
    
    # Calculate time range
    start_time = int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
    
    try:
        response = table.query(
            KeyConditionExpression=Key('StreamName').eq(stream_name) & 
                                 Key('Timestamp').gte(start_time),
            ScanIndexForward=False,
            Limit=limit
        )
        
        # Convert Decimal objects to float for JSON serialization
        items = []
        for item in response['Items']:
            converted_item = convert_decimal(item)
            items.append(converted_item)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'detections': items,
                'count': len(items),
                'stream': stream_name,
                'timeRange': f"{hours_back} hours"
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f"Failed to query detections: {str(e)}"})
        }

def get_face_detections(params, headers):
    """
    Get face detection events
    """
    table = dynamodb.Table(FACES_TABLE)
    
    face_id = params.get('faceId')
    stream_name = params.get('stream')
    hours_back = int(params.get('hours', 24))
    limit = int(params.get('limit', 50))
    
    try:
        if face_id:
            # Query specific face
            start_time = int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
            response = table.query(
                KeyConditionExpression=Key('FaceId').eq(face_id) & 
                                     Key('Timestamp').gte(start_time),
                ScanIndexForward=False,
                Limit=limit
            )
        elif stream_name:
            # Query by stream using GSI
            start_time = int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
            response = table.query(
                IndexName='StreamNameIndex',
                KeyConditionExpression=Key('StreamName').eq(stream_name) & 
                                     Key('Timestamp').gte(start_time),
                ScanIndexForward=False,
                Limit=limit
            )
        else:
            # Scan recent faces (limited scan for demo)
            response = table.scan(
                Limit=limit,
                FilterExpression=Key('Timestamp').gte(
                    int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
                )
            )
        
        # Convert Decimal objects to float for JSON serialization
        items = []
        for item in response['Items']:
            converted_item = convert_decimal(item)
            items.append(converted_item)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'faces': items,
                'count': len(items),
                'faceId': face_id,
                'stream': stream_name,
                'timeRange': f"{hours_back} hours"
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f"Failed to query faces: {str(e)}"})
        }

def get_statistics(params, headers):
    """
    Get basic statistics about detection events
    """
    try:
        # Simple statistics - in production, consider using DynamoDB Streams with analytics
        current_time = datetime.now()
        
        stats = {
            'timestamp': current_time.isoformat(),
            'project': PROJECT_NAME,
            'message': 'Statistics endpoint ready',
            'availableEndpoints': [
                'GET /detections?stream=<stream_name>&hours=<hours>&limit=<limit>',
                'GET /faces?faceId=<face_id>&stream=<stream_name>&hours=<hours>&limit=<limit>',
                'GET /stats',
                'GET /health'
            ],
            'note': 'Implement detailed statistics based on your analytics requirements'
        }
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps(stats)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f"Failed to get statistics: {str(e)}"})
        }

def get_health_check(headers):
    """
    Health check endpoint
    """
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'status': 'healthy',
            'timestamp': datetime.now().isoformat(),
            'service': 'video-analytics-api'
        })
    }

def convert_decimal(obj):
    """
    Convert DynamoDB Decimal objects to float for JSON serialization
    """
    if isinstance(obj, list):
        return [convert_decimal(item) for item in obj]
    elif isinstance(obj, dict):
        return {key: convert_decimal(value) for key, value in obj.items()}
    elif isinstance(obj, Decimal):
        return float(obj)
    else:
        return obj
`)
    });

    // Grant read permissions to DynamoDB tables
    detectionsTable.grantReadData(queryFunction);
    facesTable.grantReadData(queryFunction);

    return queryFunction;
  }

  /**
   * Creates API Gateway for video analytics queries
   */
  private createQueryApi(projectName: string, queryFunction: lambda.Function): apigateway.RestApi {
    const api = new apigateway.RestApi(this, 'VideoAnalyticsApi', {
      restApiName: `${projectName}-api`,
      description: 'API for querying video analytics data',
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key', 'X-Amz-Security-Token']
      },
      deployOptions: {
        stageName: 'prod',
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
        throttlingRateLimit: 100,
        throttlingBurstLimit: 200
      }
    });

    // Create Lambda integration
    const integration = new apigateway.LambdaIntegration(queryFunction, {
      requestTemplates: { 'application/json': '{ "statusCode": "200" }' }
    });

    // Add API endpoints
    const detections = api.root.addResource('detections');
    detections.addMethod('GET', integration);

    const faces = api.root.addResource('faces');
    faces.addMethod('GET', integration);

    const stats = api.root.addResource('stats');
    stats.addMethod('GET', integration);

    const health = api.root.addResource('health');
    health.addMethod('GET', integration);

    return api;
  }

  /**
   * Configures Kinesis Data Stream as event source for Lambda function
   */
  private configureStreamTrigger(): void {
    this.analyticsFunction.addEventSource(
      new eventsources.KinesisEventSource(this.dataStream, {
        startingPosition: lambda.StartingPosition.LATEST,
        batchSize: 10,
        maxBatchingWindow: cdk.Duration.seconds(5),
        retryAttempts: 3,
        reportBatchItemFailures: true
      })
    );
  }

  /**
   * Creates Rekognition stream processor for real-time video analysis
   */
  private createStreamProcessor(
    projectName: string,
    videoStream: kinesisVideo.CfnStream,
    dataStream: kinesis.Stream,
    faceCollection: rekognition.CfnCollection,
    serviceRole: iam.Role,
    faceMatchThreshold: number
  ): rekognition.CfnStreamProcessor {
    return new rekognition.CfnStreamProcessor(this, 'StreamProcessor', {
      name: `${projectName}-stream-processor`,
      kinesisVideoStream: {
        arn: videoStream.attrArn
      },
      kinesisDataStream: {
        arn: dataStream.streamArn
      },
      roleArn: serviceRole.roleArn,
      faceSearchSettings: {
        collectionId: faceCollection.collectionId,
        faceMatchThreshold: faceMatchThreshold
      },
      tags: [{
        key: 'Purpose',
        value: 'VideoAnalysis'
      }]
    });
  }

  /**
   * Creates CloudFormation outputs for key resources
   */
  private createOutputs(projectName: string): void {
    new cdk.CfnOutput(this, 'VideoStreamName', {
      value: this.videoStream.name!,
      description: 'Kinesis Video Stream name for video ingestion',
      exportName: `${projectName}-video-stream-name`
    });

    new cdk.CfnOutput(this, 'VideoStreamArn', {
      value: this.videoStream.attrArn,
      description: 'Kinesis Video Stream ARN',
      exportName: `${projectName}-video-stream-arn`
    });

    new cdk.CfnOutput(this, 'DataStreamName', {
      value: this.dataStream.streamName,
      description: 'Kinesis Data Stream name for analytics results',
      exportName: `${projectName}-data-stream-name`
    });

    new cdk.CfnOutput(this, 'FaceCollectionId', {
      value: this.faceCollection.collectionId,
      description: 'Rekognition face collection ID',
      exportName: `${projectName}-face-collection-id`
    });

    new cdk.CfnOutput(this, 'StreamProcessorName', {
      value: this.streamProcessor.name!,
      description: 'Rekognition stream processor name',
      exportName: `${projectName}-stream-processor-name`
    });

    new cdk.CfnOutput(this, 'DetectionsTableName', {
      value: this.detectionsTable.tableName,
      description: 'DynamoDB table for detection events',
      exportName: `${projectName}-detections-table`
    });

    new cdk.CfnOutput(this, 'FacesTableName', {
      value: this.facesTable.tableName,
      description: 'DynamoDB table for face detection events',
      exportName: `${projectName}-faces-table`
    });

    new cdk.CfnOutput(this, 'AlertsTopicArn', {
      value: this.alertsTopic.topicArn,
      description: 'SNS topic ARN for security alerts',
      exportName: `${projectName}-alerts-topic-arn`
    });

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: this.queryApi.url,
      description: 'API Gateway endpoint for video analytics queries',
      exportName: `${projectName}-api-endpoint`
    });

    new cdk.CfnOutput(this, 'AnalyticsFunctionName', {
      value: this.analyticsFunction.functionName,
      description: 'Lambda function name for analytics processing',
      exportName: `${projectName}-analytics-function`
    });

    new cdk.CfnOutput(this, 'QueryApiFunctionName', {
      value: this.queryApiFunction.functionName,
      description: 'Lambda function name for query API',
      exportName: `${projectName}-query-api-function`
    });
  }
}

/**
 * CDK Application
 */
const app = new cdk.App();

// Get configuration from context or environment
const projectName = app.node.tryGetContext('projectName') || process.env.PROJECT_NAME || 'video-analytics';
const faceMatchThreshold = parseFloat(app.node.tryGetContext('faceMatchThreshold') || process.env.FACE_MATCH_THRESHOLD || '80.0');
const retentionInHours = parseInt(app.node.tryGetContext('retentionInHours') || process.env.RETENTION_IN_HOURS || '24');
const alertEmail = app.node.tryGetContext('alertEmail') || process.env.ALERT_EMAIL;

// Create the video analytics stack
new VideoAnalyticsStack(app, 'VideoAnalyticsStack', {
  projectName,
  faceMatchThreshold,
  retentionInHours,
  alertEmail,
  description: 'Real-time video analytics platform with Amazon Rekognition and Kinesis',
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION || 'us-east-1'
  }
});

// Synthesize the app
app.synth();