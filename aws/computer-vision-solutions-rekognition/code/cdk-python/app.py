#!/usr/bin/env python3
"""
CDK Python Application for Computer Vision Solutions with Amazon Rekognition

This application creates the infrastructure for a comprehensive computer vision
solution using Amazon Rekognition for face detection, object recognition,
text extraction, and content moderation.

Key Components:
- S3 buckets for image storage and results
- DynamoDB table for analysis metadata
- Lambda function for comprehensive image analysis
- API Gateway for RESTful access
- Rekognition collection for face recognition
- IAM roles and policies with least privilege

Architecture:
- Event-driven processing triggered by S3 uploads
- RESTful API for on-demand analysis
- Centralized results storage in DynamoDB and S3
- Comprehensive logging and monitoring
"""

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_s3 as s3,
    aws_s3_notifications as s3n,
    aws_lambda as _lambda,
    aws_apigateway as apigw,
    aws_dynamodb as dynamodb,
    aws_iam as iam,
    aws_logs as logs,
    aws_lambda_python_alpha as lambda_python,
)
from constructs import Construct
import json
from typing import Dict, Any


class ComputerVisionStack(Stack):
    """
    CDK Stack for Computer Vision Solutions with Amazon Rekognition
    
    This stack creates a complete computer vision pipeline that can:
    - Automatically analyze images uploaded to S3
    - Provide RESTful API access for on-demand analysis
    - Store analysis results in DynamoDB and S3
    - Support face collections for identity verification
    - Implement content moderation and safety checks
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Generate unique suffix for resource names
        unique_suffix = self.node.try_get_context("unique_suffix") or "demo"
        
        # Create S3 buckets for image storage and results
        self._create_storage_resources(unique_suffix)
        
        # Create DynamoDB table for analysis metadata
        self._create_database_resources(unique_suffix)
        
        # Create Lambda function for image analysis
        self._create_compute_resources(unique_suffix)
        
        # Create API Gateway for RESTful access
        self._create_api_resources()
        
        # Create IAM roles and policies
        self._create_security_resources()
        
        # Setup S3 event notifications
        self._setup_event_processing()
        
        # Create outputs for verification and integration
        self._create_outputs()

    def _create_storage_resources(self, unique_suffix: str) -> None:
        """
        Create S3 buckets for image storage and analysis results
        
        Args:
            unique_suffix: Unique identifier for bucket names
        """
        # Main bucket for storing input images
        self.images_bucket = s3.Bucket(
            self, "ImagesBucket",
            bucket_name=f"rekognition-images-{unique_suffix}",
            versioning=False,
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="DeleteOldImages",
                    enabled=True,
                    expiration=Duration.days(90),  # Cleanup old images after 90 days
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

        # Bucket for storing analysis results and processed images
        self.results_bucket = s3.Bucket(
            self, "ResultsBucket",
            bucket_name=f"rekognition-results-{unique_suffix}",
            versioning=True,  # Keep version history of analysis results
            public_read_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            encryption=s3.BucketEncryption.S3_MANAGED,
            lifecycle_rules=[
                s3.LifecycleRule(
                    id="TransitionToIA",
                    enabled=True,
                    transitions=[
                        s3.Transition(
                            storage_class=s3.StorageClass.INFREQUENT_ACCESS,
                            transition_after=Duration.days(30)
                        ),
                        s3.Transition(
                            storage_class=s3.StorageClass.GLACIER,
                            transition_after=Duration.days(90)
                        )
                    ]
                )
            ],
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
        )

    def _create_database_resources(self, unique_suffix: str) -> None:
        """
        Create DynamoDB table for storing analysis metadata and results
        
        Args:
            unique_suffix: Unique identifier for table name
        """
        self.analysis_table = dynamodb.Table(
            self, "AnalysisTable",
            table_name=f"rekognition-analysis-{unique_suffix}",
            partition_key=dynamodb.Attribute(
                name="image_key",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="analysis_timestamp",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            encryption=dynamodb.TableEncryption.AWS_MANAGED,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
        )

        # Add Global Secondary Index for querying by analysis type
        self.analysis_table.add_global_secondary_index(
            index_name="AnalysisTypeIndex",
            partition_key=dynamodb.Attribute(
                name="analysis_type",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="analysis_timestamp",
                type=dynamodb.AttributeType.STRING
            ),
        )

        # Add Global Secondary Index for querying by moderation status
        self.analysis_table.add_global_secondary_index(
            index_name="ModerationStatusIndex",
            partition_key=dynamodb.Attribute(
                name="moderation_status",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="analysis_timestamp",
                type=dynamodb.AttributeType.STRING
            ),
        )

    def _create_compute_resources(self, unique_suffix: str) -> None:
        """
        Create Lambda function for comprehensive image analysis
        
        Args:
            unique_suffix: Unique identifier for function name
        """
        # Create CloudWatch Log Group with retention policy
        log_group = logs.LogGroup(
            self, "AnalysisLambdaLogGroup",
            log_group_name=f"/aws/lambda/rekognition-analysis-{unique_suffix}",
            retention=logs.RetentionDays.ONE_MONTH,
            removal_policy=RemovalPolicy.DESTROY,
        )

        # Lambda function for comprehensive image analysis
        self.analysis_function = _lambda.Function(
            self, "AnalysisFunction",
            function_name=f"rekognition-analysis-{unique_suffix}",
            runtime=_lambda.Runtime.PYTHON_3_11,
            handler="lambda_function.lambda_handler",
            code=_lambda.Code.from_inline(self._get_lambda_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "IMAGES_BUCKET": self.images_bucket.bucket_name,
                "RESULTS_BUCKET": self.results_bucket.bucket_name,
                "ANALYSIS_TABLE": self.analysis_table.table_name,
                "FACE_COLLECTION_ID": f"face-collection-{unique_suffix}",
                "AWS_REGION": self.region,
            },
            log_group=log_group,
            description="Comprehensive image analysis using Amazon Rekognition",
        )

    def _create_api_resources(self) -> None:
        """
        Create API Gateway for RESTful access to the analysis function
        """
        # Create API Gateway with CloudWatch logging
        self.api = apigw.RestApi(
            self, "AnalysisApi",
            rest_api_name="Rekognition Analysis API",
            description="RESTful API for computer vision analysis using Amazon Rekognition",
            default_cors_preflight_options=apigw.CorsOptions(
                allow_origins=apigw.Cors.ALL_ORIGINS,
                allow_methods=apigw.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            cloud_watch_role=True,
            deploy_options=apigw.StageOptions(
                stage_name="prod",
                throttling_rate_limit=100,
                throttling_burst_limit=200,
                logging_level=apigw.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True,
            ),
        )

        # Create Lambda integration
        lambda_integration = apigw.LambdaIntegration(
            self.analysis_function,
            request_templates={"application/json": '{"statusCode": "200"}'},
            integration_responses=[
                apigw.IntegrationResponse(
                    status_code="200",
                    response_templates={"application/json": ""},
                )
            ],
        )

        # Add resource and methods for image analysis
        analyze_resource = self.api.root.add_resource("analyze")
        
        # POST method for analyzing images
        analyze_resource.add_method(
            "POST",
            lambda_integration,
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_models={"application/json": apigw.Model.EMPTY_MODEL},
                )
            ],
        )

        # GET method for retrieving analysis results
        analyze_resource.add_method(
            "GET",
            lambda_integration,
            method_responses=[
                apigw.MethodResponse(
                    status_code="200",
                    response_models={"application/json": apigw.Model.EMPTY_MODEL},
                )
            ],
        )

    def _create_security_resources(self) -> None:
        """
        Create IAM roles and policies with least privilege access
        """
        # Grant Lambda function permissions to access required AWS services
        self.images_bucket.grant_read(self.analysis_function)
        self.results_bucket.grant_read_write(self.analysis_function)
        self.analysis_table.grant_read_write_data(self.analysis_function)

        # Add Rekognition permissions
        rekognition_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "rekognition:DetectFaces",
                "rekognition:DetectLabels",
                "rekognition:DetectText",
                "rekognition:DetectModerationLabels",
                "rekognition:CreateCollection",
                "rekognition:DeleteCollection",
                "rekognition:DescribeCollection",
                "rekognition:ListCollections",
                "rekognition:IndexFaces",
                "rekognition:ListFaces",
                "rekognition:SearchFaces",
                "rekognition:SearchFacesByImage",
                "rekognition:DeleteFaces",
            ],
            resources=["*"],  # Rekognition doesn't support resource-level permissions
        )

        self.analysis_function.add_to_role_policy(rekognition_policy)

        # Add CloudWatch Logs permissions
        logs_policy = iam.PolicyStatement(
            effect=iam.Effect.ALLOW,
            actions=[
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
            ],
            resources=[f"arn:aws:logs:{self.region}:{self.account}:*"],
        )

        self.analysis_function.add_to_role_policy(logs_policy)

    def _setup_event_processing(self) -> None:
        """
        Setup S3 event notifications to trigger automatic analysis
        """
        # Add S3 event notification to trigger Lambda on image uploads
        self.images_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3n.LambdaDestination(self.analysis_function),
            s3.NotificationKeyFilter(
                prefix="images/",
                suffix=".jpg"
            )
        )

        # Add support for other common image formats
        for suffix in [".jpeg", ".png", ".gif", ".bmp", ".webp"]:
            self.images_bucket.add_event_notification(
                s3.EventType.OBJECT_CREATED,
                s3n.LambdaDestination(self.analysis_function),
                s3.NotificationKeyFilter(
                    prefix="images/",
                    suffix=suffix
                )
            )

    def _create_outputs(self) -> None:
        """
        Create CloudFormation outputs for verification and integration
        """
        CfnOutput(
            self, "ImagesBucketName",
            value=self.images_bucket.bucket_name,
            description="S3 bucket for storing input images",
            export_name=f"{self.stack_name}-ImagesBucket",
        )

        CfnOutput(
            self, "ResultsBucketName",
            value=self.results_bucket.bucket_name,
            description="S3 bucket for storing analysis results",
            export_name=f"{self.stack_name}-ResultsBucket",
        )

        CfnOutput(
            self, "AnalysisTableName",
            value=self.analysis_table.table_name,
            description="DynamoDB table for analysis metadata",
            export_name=f"{self.stack_name}-AnalysisTable",
        )

        CfnOutput(
            self, "AnalysisFunctionName",
            value=self.analysis_function.function_name,
            description="Lambda function for image analysis",
            export_name=f"{self.stack_name}-AnalysisFunction",
        )

        CfnOutput(
            self, "ApiEndpoint",
            value=self.api.url,
            description="API Gateway endpoint for RESTful access",
            export_name=f"{self.stack_name}-ApiEndpoint",
        )

        CfnOutput(
            self, "FaceCollectionId",
            value=f"face-collection-{self.node.try_get_context('unique_suffix') or 'demo'}",
            description="Rekognition face collection ID",
            export_name=f"{self.stack_name}-FaceCollectionId",
        )

    def _get_lambda_code(self) -> str:
        """
        Return the Lambda function code for comprehensive image analysis
        
        Returns:
            str: Complete Lambda function code as a string
        """
        return '''
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List
import uuid

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')

# Environment variables
IMAGES_BUCKET = os.environ['IMAGES_BUCKET']
RESULTS_BUCKET = os.environ['RESULTS_BUCKET']
ANALYSIS_TABLE_NAME = os.environ['ANALYSIS_TABLE']
FACE_COLLECTION_ID = os.environ['FACE_COLLECTION_ID']
AWS_REGION = os.environ['AWS_REGION']

# Initialize DynamoDB table
analysis_table = dynamodb.Table(ANALYSIS_TABLE_NAME)


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for comprehensive image analysis
    
    Supports both S3 event processing and API Gateway requests
    """
    try:
        # Determine event source and process accordingly
        if 'Records' in event:
            # S3 event processing
            return handle_s3_event(event)
        else:
            # API Gateway request
            return handle_api_request(event)
            
    except Exception as e:
        logger.error(f"Error processing event: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': str(e)
            })
        }


def handle_s3_event(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Process S3 event notifications for automatic image analysis
    """
    results = []
    
    for record in event['Records']:
        bucket_name = record['s3']['bucket']['name']
        object_key = record['s3']['object']['key']
        
        logger.info(f"Processing S3 object: {bucket_name}/{object_key}")
        
        # Perform comprehensive analysis
        analysis_result = analyze_image_comprehensive(bucket_name, object_key)
        results.append(analysis_result)
    
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': f'Processed {len(results)} images',
            'results': results
        })
    }


def handle_api_request(event: Dict[str, Any]) -> Dict[str, Any]:
    """
    Handle API Gateway requests for on-demand analysis or result retrieval
    """
    http_method = event.get('httpMethod', '')
    query_params = event.get('queryStringParameters') or {}
    
    if http_method == 'POST':
        # Analyze specific image
        body = json.loads(event.get('body', '{}'))
        bucket_name = body.get('bucket', IMAGES_BUCKET)
        object_key = body.get('key', '')
        
        if not object_key:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'error': 'Missing required parameter: key'})
            }
        
        result = analyze_image_comprehensive(bucket_name, object_key)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(result)
        }
    
    elif http_method == 'GET':
        # Retrieve analysis results
        image_key = query_params.get('image_key')
        
        if image_key:
            # Get specific image analysis
            results = get_analysis_results(image_key)
        else:
            # Get all recent analyses
            results = get_recent_analyses()
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps(results)
        }
    
    else:
        return {
            'statusCode': 405,
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'error': 'Method not allowed'})
        }


def analyze_image_comprehensive(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """
    Perform comprehensive analysis using all Rekognition capabilities
    """
    analysis_id = str(uuid.uuid4())
    timestamp = datetime.utcnow().isoformat()
    
    result = {
        'analysis_id': analysis_id,
        'image_key': object_key,
        'bucket': bucket_name,
        'timestamp': timestamp,
        'analyses': {},
        'summary': {}
    }
    
    try:
        # Ensure face collection exists
        ensure_face_collection()
        
        # 1. Face Detection and Analysis
        face_analysis = analyze_faces(bucket_name, object_key)
        result['analyses']['faces'] = face_analysis
        
        # 2. Object and Scene Detection
        object_analysis = analyze_objects(bucket_name, object_key)
        result['analyses']['objects'] = object_analysis
        
        # 3. Text Detection and Recognition
        text_analysis = analyze_text(bucket_name, object_key)
        result['analyses']['text'] = text_analysis
        
        # 4. Content Moderation
        moderation_analysis = analyze_moderation(bucket_name, object_key)
        result['analyses']['moderation'] = moderation_analysis
        
        # 5. Face Recognition (if faces detected)
        if face_analysis['face_count'] > 0:
            recognition_analysis = analyze_face_recognition(bucket_name, object_key)
            result['analyses']['face_recognition'] = recognition_analysis
        
        # Generate summary
        result['summary'] = generate_analysis_summary(result['analyses'])
        
        # Store results in DynamoDB
        store_analysis_results(result)
        
        # Store detailed results in S3
        store_results_to_s3(result)
        
        logger.info(f"Completed comprehensive analysis for {object_key}")
        
    except Exception as e:
        logger.error(f"Error analyzing {object_key}: {str(e)}")
        result['error'] = str(e)
    
    return result


def analyze_faces(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """Analyze faces in the image"""
    try:
        response = rekognition.detect_faces(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': object_key}},
            Attributes=['ALL']
        )
        
        faces = response.get('FaceDetails', [])
        
        return {
            'face_count': len(faces),
            'faces': [{
                'confidence': face['Confidence'],
                'age_range': face.get('AgeRange', {}),
                'gender': face.get('Gender', {}).get('Value'),
                'emotions': [emotion for emotion in face.get('Emotions', []) if emotion['Confidence'] > 50],
                'quality': face.get('Quality', {}),
                'pose': face.get('Pose', {}),
                'landmarks': len(face.get('Landmarks', []))
            } for face in faces]
        }
    except Exception as e:
        logger.error(f"Face analysis error: {str(e)}")
        return {'face_count': 0, 'error': str(e)}


def analyze_objects(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """Analyze objects and scenes in the image"""
    try:
        response = rekognition.detect_labels(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': object_key}},
            MaxLabels=20,
            MinConfidence=75
        )
        
        labels = response.get('Labels', [])
        
        return {
            'label_count': len(labels),
            'labels': [{
                'name': label['Name'],
                'confidence': label['Confidence'],
                'parents': [parent['Name'] for parent in label.get('Parents', [])],
                'instances': len(label.get('Instances', []))
            } for label in labels]
        }
    except Exception as e:
        logger.error(f"Object analysis error: {str(e)}")
        return {'label_count': 0, 'error': str(e)}


def analyze_text(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """Analyze text in the image"""
    try:
        response = rekognition.detect_text(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': object_key}}
        )
        
        text_detections = response.get('TextDetections', [])
        lines = [text for text in text_detections if text['Type'] == 'LINE']
        words = [text for text in text_detections if text['Type'] == 'WORD']
        
        return {
            'text_found': len(lines) > 0,
            'line_count': len(lines),
            'word_count': len(words),
            'lines': [{
                'text': line['DetectedText'],
                'confidence': line['Confidence']
            } for line in lines]
        }
    except Exception as e:
        logger.error(f"Text analysis error: {str(e)}")
        return {'text_found': False, 'error': str(e)}


def analyze_moderation(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """Analyze content for moderation"""
    try:
        response = rekognition.detect_moderation_labels(
            Image={'S3Object': {'Bucket': bucket_name, 'Name': object_key}},
            MinConfidence=60
        )
        
        moderation_labels = response.get('ModerationLabels', [])
        
        return {
            'inappropriate_content': len(moderation_labels) > 0,
            'moderation_score': max([label['Confidence'] for label in moderation_labels], default=0),
            'labels': [{
                'name': label['Name'],
                'confidence': label['Confidence'],
                'parent_name': label.get('ParentName', '')
            } for label in moderation_labels]
        }
    except Exception as e:
        logger.error(f"Moderation analysis error: {str(e)}")
        return {'inappropriate_content': False, 'error': str(e)}


def analyze_face_recognition(bucket_name: str, object_key: str) -> Dict[str, Any]:
    """Search for known faces in the collection"""
    try:
        response = rekognition.search_faces_by_image(
            CollectionId=FACE_COLLECTION_ID,
            Image={'S3Object': {'Bucket': bucket_name, 'Name': object_key}},
            FaceMatchThreshold=80,
            MaxFaces=5
        )
        
        face_matches = response.get('FaceMatches', [])
        
        return {
            'known_faces_found': len(face_matches) > 0,
            'match_count': len(face_matches),
            'matches': [{
                'similarity': match['Similarity'],
                'face_id': match['Face']['FaceId'],
                'external_image_id': match['Face'].get('ExternalImageId', '')
            } for match in face_matches]
        }
    except Exception as e:
        logger.error(f"Face recognition error: {str(e)}")
        return {'known_faces_found': False, 'error': str(e)}


def generate_analysis_summary(analyses: Dict[str, Any]) -> Dict[str, Any]:
    """Generate a summary of all analyses"""
    summary = {
        'contains_faces': analyses.get('faces', {}).get('face_count', 0) > 0,
        'contains_text': analyses.get('text', {}).get('text_found', False),
        'object_categories': len(analyses.get('objects', {}).get('labels', [])),
        'moderation_status': 'safe' if not analyses.get('moderation', {}).get('inappropriate_content', False) else 'flagged',
        'known_faces': analyses.get('face_recognition', {}).get('known_faces_found', False)
    }
    
    # Determine overall confidence
    confidences = []
    for analysis_type, data in analyses.items():
        if isinstance(data, dict):
            if 'faces' in data:
                confidences.extend([face['confidence'] for face in data['faces']])
            elif 'labels' in data:
                confidences.extend([label['confidence'] for label in data['labels']])
    
    summary['average_confidence'] = sum(confidences) / len(confidences) if confidences else 0
    
    return summary


def ensure_face_collection():
    """Ensure the face collection exists"""
    try:
        rekognition.describe_collection(CollectionId=FACE_COLLECTION_ID)
    except rekognition.exceptions.ResourceNotFoundException:
        logger.info(f"Creating face collection: {FACE_COLLECTION_ID}")
        rekognition.create_collection(CollectionId=FACE_COLLECTION_ID)


def store_analysis_results(result: Dict[str, Any]) -> None:
    """Store analysis results in DynamoDB"""
    try:
        # Prepare item for DynamoDB (remove nested objects that are too large)
        item = {
            'image_key': result['image_key'],
            'analysis_timestamp': result['timestamp'],
            'analysis_id': result['analysis_id'],
            'bucket': result['bucket'],
            'analysis_type': 'comprehensive',
            'moderation_status': result['summary'].get('moderation_status', 'safe'),
            'face_count': result['analyses'].get('faces', {}).get('face_count', 0),
            'object_count': result['analyses'].get('objects', {}).get('label_count', 0),
            'contains_text': result['summary'].get('contains_text', False),
            'average_confidence': result['summary'].get('average_confidence', 0),
            'results_s3_key': f"analysis-results/{result['analysis_id']}.json"
        }
        
        analysis_table.put_item(Item=item)
        logger.info(f"Stored analysis results in DynamoDB for {result['image_key']}")
        
    except Exception as e:
        logger.error(f"Error storing results in DynamoDB: {str(e)}")


def store_results_to_s3(result: Dict[str, Any]) -> None:
    """Store detailed analysis results in S3"""
    try:
        s3_key = f"analysis-results/{result['analysis_id']}.json"
        
        s3.put_object(
            Bucket=RESULTS_BUCKET,
            Key=s3_key,
            Body=json.dumps(result, indent=2, default=str),
            ContentType='application/json'
        )
        
        logger.info(f"Stored detailed results in S3: {s3_key}")
        
    except Exception as e:
        logger.error(f"Error storing results in S3: {str(e)}")


def get_analysis_results(image_key: str) -> Dict[str, Any]:
    """Retrieve analysis results for a specific image"""
    try:
        response = analysis_table.query(
            KeyConditionExpression='image_key = :key',
            ExpressionAttributeValues={':key': image_key},
            ScanIndexForward=False,  # Get most recent first
            Limit=10
        )
        
        return {
            'image_key': image_key,
            'analyses': response.get('Items', [])
        }
    except Exception as e:
        logger.error(f"Error retrieving analysis results: {str(e)}")
        return {'error': str(e)}


def get_recent_analyses(limit: int = 20) -> Dict[str, Any]:
    """Retrieve recent analysis results"""
    try:
        response = analysis_table.scan(
            Limit=limit,
            ProjectionExpression='image_key, analysis_timestamp, analysis_id, moderation_status, face_count, object_count'
        )
        
        # Sort by timestamp (most recent first)
        items = sorted(response.get('Items', []), 
                      key=lambda x: x.get('analysis_timestamp', ''), reverse=True)
        
        return {
            'recent_analyses': items[:limit]
        }
    except Exception as e:
        logger.error(f"Error retrieving recent analyses: {str(e)}")
        return {'error': str(e)}
'''


def main():
    """
    Main entry point for the CDK application
    """
    app = cdk.App()
    
    # Get configuration from context or use defaults
    env = cdk.Environment(
        account=app.node.try_get_context("account") or None,
        region=app.node.try_get_context("region") or "us-east-1"
    )
    
    # Create the stack
    ComputerVisionStack(
        app, 
        "ComputerVisionRekognitionStack",
        env=env,
        description="Computer Vision Solutions with Amazon Rekognition - CDK Python Stack",
        tags={
            "Project": "ComputerVisionSolutions",
            "Environment": app.node.try_get_context("environment") or "development",
            "Owner": app.node.try_get_context("owner") or "CDK",
            "CostCenter": app.node.try_get_context("cost_center") or "Engineering",
        }
    )
    
    app.synth()


if __name__ == "__main__":
    main()