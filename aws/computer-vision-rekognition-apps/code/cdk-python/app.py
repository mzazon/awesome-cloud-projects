#!/usr/bin/env python3
"""
Computer Vision Applications with Amazon Rekognition
AWS CDK Python Application

This CDK application deploys a comprehensive computer vision solution using Amazon Rekognition
for analyzing images and videos, including face recognition, object detection, and real-time
streaming analysis capabilities.

Author: AWS Cloud Development Kit
Version: 1.0.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    aws_s3 as s3,
    aws_iam as iam,
    aws_kinesis as kinesis,
    aws_kinesisvideo as kinesisvideo,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_s3_notifications as s3_notifications,
    aws_logs as logs,
    CfnOutput,
    Duration,
    RemovalPolicy,
    Tags
)
from constructs import Construct


class ComputerVisionStack(Stack):
    """
    CDK Stack for Computer Vision Applications with Amazon Rekognition
    
    This stack creates:
    - S3 bucket for storing images and videos
    - IAM roles for Rekognition service access
    - Kinesis Video Stream for real-time processing
    - Kinesis Data Stream for analysis results
    - Lambda functions for processing and analytics
    - API Gateway for REST API endpoints
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Add stack-wide tags
        Tags.of(self).add("Project", "ComputerVisionApp")
        Tags.of(self).add("Environment", "Demo")
        Tags.of(self).add("CostCenter", "ML-Analytics")

        # Create S3 bucket for images and videos
        self.media_bucket = self._create_media_bucket()
        
        # Create IAM roles
        self.rekognition_role = self._create_rekognition_service_role()
        self.lambda_execution_role = self._create_lambda_execution_role()
        
        # Create Kinesis streams
        self.kinesis_data_stream = self._create_kinesis_data_stream()
        self.kinesis_video_stream = self._create_kinesis_video_stream()
        
        # Create Lambda functions
        self.image_processor_function = self._create_image_processor_lambda()
        self.analytics_function = self._create_analytics_lambda()
        
        # Create API Gateway
        self.api = self._create_api_gateway()
        
        # Configure S3 notifications
        self._configure_s3_notifications()
        
        # Create outputs
        self._create_outputs()

    def _create_media_bucket(self) -> s3.Bucket:
        """Create S3 bucket for storing images and videos with appropriate configuration."""
        bucket = s3.Bucket(
            self, "MediaBucket",
            bucket_name=f"computer-vision-media-{self.account}-{self.region}",
            versioning=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
            removal_policy=RemovalPolicy.DESTROY,
            auto_delete_objects=True,
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
            ]
        )

        # Create folder structure using CfnObject
        folders = ["images/", "videos/", "results/", "thumbnails/"]
        for folder in folders:
            s3.CfnObject(
                self, f"Folder{folder.replace('/', '').title()}",
                bucket=bucket.bucket_name,
                key=folder
            )

        return bucket

    def _create_rekognition_service_role(self) -> iam.Role:
        """Create IAM role for Amazon Rekognition service access."""
        role = iam.Role(
            self, "RekognitionServiceRole",
            role_name=f"RekognitionVideoAnalysisRole-{self.region}",
            assumed_by=iam.ServicePrincipal("rekognition.amazonaws.com"),
            description="IAM role for Amazon Rekognition video analysis operations",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AmazonRekognitionServiceRole"
                )
            ]
        )

        # Add additional permissions for Kinesis and S3 access
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:PutRecord",
                    "kinesis:PutRecords",
                    "kinesis:DescribeStream"
                ],
                resources=[
                    f"arn:aws:kinesis:{self.region}:{self.account}:stream/*"
                ]
            )
        )

        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:GetObjectVersion"
                ],
                resources=[
                    f"arn:aws:s3:::computer-vision-media-{self.account}-{self.region}/*"
                ]
            )
        )

        return role

    def _create_lambda_execution_role(self) -> iam.Role:
        """Create IAM role for Lambda function execution."""
        role = iam.Role(
            self, "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="IAM role for Lambda functions in computer vision application",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add Rekognition permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "rekognition:DetectLabels",
                    "rekognition:DetectFaces",
                    "rekognition:DetectText",
                    "rekognition:DetectModerationLabels",
                    "rekognition:SearchFacesByImage",
                    "rekognition:IndexFaces",
                    "rekognition:CreateCollection",
                    "rekognition:DeleteCollection",
                    "rekognition:ListCollections",
                    "rekognition:DescribeCollection",
                    "rekognition:ListFaces",
                    "rekognition:DeleteFaces",
                    "rekognition:StartFaceDetection",
                    "rekognition:StartLabelDetection",
                    "rekognition:StartPersonTracking",
                    "rekognition:GetFaceDetection",
                    "rekognition:GetLabelDetection",
                    "rekognition:GetPersonTracking"
                ],
                resources=["*"]
            )
        )

        # Add S3 permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:ListBucket"
                ],
                resources=[
                    self.media_bucket.bucket_arn,
                    f"{self.media_bucket.bucket_arn}/*"
                ]
            )
        )

        # Add Kinesis permissions
        role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "kinesis:PutRecord",
                    "kinesis:PutRecords",
                    "kinesis:GetRecords",
                    "kinesis:GetShardIterator",
                    "kinesis:DescribeStream",
                    "kinesis:ListStreams"
                ],
                resources=[
                    f"arn:aws:kinesis:{self.region}:{self.account}:stream/*"
                ]
            )
        )

        return role

    def _create_kinesis_data_stream(self) -> kinesis.Stream:
        """Create Kinesis Data Stream for analysis results."""
        stream = kinesis.Stream(
            self, "RekognitionResultsStream",
            stream_name=f"rekognition-results-{self.account}",
            shard_count=1,
            retention_period=Duration.hours(24),
            encryption=kinesis.StreamEncryption.MANAGED
        )

        return stream

    def _create_kinesis_video_stream(self) -> kinesisvideo.CfnStream:
        """Create Kinesis Video Stream for real-time video processing."""
        stream = kinesisvideo.CfnStream(
            self, "SecurityVideoStream",
            name=f"security-video-{self.account}",
            data_retention_in_hours=24,
            device_name="security-camera",
            media_type="video/h264",
            tags=[
                cdk.CfnTag(key="Purpose", value="SecurityMonitoring"),
                cdk.CfnTag(key="Environment", value="Demo")
            ]
        )

        return stream

    def _create_image_processor_lambda(self) -> lambda_.Function:
        """Create Lambda function for processing uploaded images."""
        function = lambda_.Function(
            self, "ImageProcessorFunction",
            function_name=f"computer-vision-image-processor-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.minutes(5),
            memory_size=512,
            environment={
                "BUCKET_NAME": self.media_bucket.bucket_name,
                "KINESIS_STREAM_NAME": self.kinesis_data_stream.stream_name,
                "FACE_COLLECTION_PREFIX": f"retail-faces-{self.account}"
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
import logging
from datetime import datetime
from typing import Dict, Any, List

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
rekognition = boto3.client('rekognition')
s3 = boto3.client('s3')
kinesis = boto3.client('kinesis')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    \"\"\"
    Process uploaded images with Amazon Rekognition.
    
    This function performs comprehensive image analysis including:
    - Object and scene detection
    - Facial analysis and demographics
    - Text detection
    - Content moderation
    - Face matching against collections
    \"\"\"
    try:
        # Parse S3 event
        records = event.get('Records', [])
        
        for record in records:
            bucket = record['s3']['bucket']['name']
            key = record['s3']['object']['key']
            
            # Skip if not an image file
            if not key.lower().endswith(('.jpg', '.jpeg', '.png')):
                continue
                
            logger.info(f"Processing image: {key}")
            
            # Perform comprehensive analysis
            analysis_results = analyze_image(bucket, key)
            
            # Store results in S3
            results_key = f"results/{key}_analysis.json"
            store_results(bucket, results_key, analysis_results)
            
            # Send to Kinesis stream
            send_to_kinesis(analysis_results)
            
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': f'Successfully processed {len(records)} images',
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing images: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def analyze_image(bucket: str, key: str) -> Dict[str, Any]:
    \"\"\"Perform comprehensive image analysis using Rekognition.\"\"\"
    s3_object = {'Bucket': bucket, 'Name': key}
    results = {
        'image_key': key,
        'timestamp': datetime.utcnow().isoformat(),
        'analyses': {}
    }
    
    try:
        # 1. Detect labels (objects and scenes)
        labels_response = rekognition.detect_labels(
            Image={'S3Object': s3_object},
            Features=['GENERAL_LABELS', 'IMAGE_PROPERTIES'],
            Settings={
                'GeneralLabels': {
                    'MaxLabels': 20,
                    'LabelInclusionFilters': [],
                    'LabelExclusionFilters': []
                },
                'ImageProperties': {
                    'MaxDominantColors': 10
                }
            }
        )
        results['analyses']['labels'] = labels_response
        
        # 2. Detect faces
        faces_response = rekognition.detect_faces(
            Image={'S3Object': s3_object},
            Attributes=['ALL']
        )
        results['analyses']['faces'] = faces_response
        
        # 3. Detect text
        text_response = rekognition.detect_text(
            Image={'S3Object': s3_object}
        )
        results['analyses']['text'] = text_response
        
        # 4. Content moderation
        moderation_response = rekognition.detect_moderation_labels(
            Image={'S3Object': s3_object}
        )
        results['analyses']['moderation'] = moderation_response
        
        # 5. Face search (if faces detected)
        if faces_response.get('FaceDetails'):
            try:
                face_search_response = rekognition.search_faces_by_image(
                    Image={'S3Object': s3_object},
                    CollectionId=f"{os.environ['FACE_COLLECTION_PREFIX']}-collection",
                    FaceMatchThreshold=80.0
                )
                results['analyses']['face_search'] = face_search_response
            except rekognition.exceptions.ResourceNotFoundException:
                logger.info("Face collection not found, skipping face search")
            except Exception as e:
                logger.warning(f"Face search failed: {str(e)}")
        
    except Exception as e:
        logger.error(f"Error in image analysis: {str(e)}")
        results['error'] = str(e)
    
    return results

def store_results(bucket: str, key: str, results: Dict[str, Any]) -> None:
    \"\"\"Store analysis results in S3.\"\"\"
    try:
        s3.put_object(
            Bucket=bucket,
            Key=key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        logger.info(f"Stored results at s3://{bucket}/{key}")
    except Exception as e:
        logger.error(f"Failed to store results: {str(e)}")

def send_to_kinesis(results: Dict[str, Any]) -> None:
    \"\"\"Send analysis results to Kinesis stream.\"\"\"
    try:
        kinesis.put_record(
            StreamName=os.environ['KINESIS_STREAM_NAME'],
            Data=json.dumps(results),
            PartitionKey=results['image_key']
        )
        logger.info("Sent results to Kinesis stream")
    except Exception as e:
        logger.error(f"Failed to send to Kinesis: {str(e)}")
""")
        )

        return function

    def _create_analytics_lambda(self) -> lambda_.Function:
        """Create Lambda function for analytics and reporting."""
        function = lambda_.Function(
            self, "AnalyticsFunction",
            function_name=f"computer-vision-analytics-{self.region}",
            runtime=lambda_.Runtime.PYTHON_3_11,
            handler="index.lambda_handler",
            role=self.lambda_execution_role,
            timeout=Duration.minutes(10),
            memory_size=1024,
            environment={
                "BUCKET_NAME": self.media_bucket.bucket_name,
                "KINESIS_STREAM_NAME": self.kinesis_data_stream.stream_name
            },
            log_retention=logs.RetentionDays.ONE_WEEK,
            code=lambda_.Code.from_inline("""
import json
import boto3
import os
import logging
from datetime import datetime, timedelta
from typing import Dict, Any, List
from collections import defaultdict

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
s3 = boto3.client('s3')
kinesis = boto3.client('kinesis')

def lambda_handler(event: Dict[str, Any], context) -> Dict[str, Any]:
    \"\"\"
    Generate analytics reports from computer vision analysis results.
    
    This function:
    - Aggregates analysis results from S3
    - Calculates business metrics
    - Generates comprehensive reports
    - Returns analytics via API Gateway
    \"\"\"
    try:
        # Parse query parameters
        query_params = event.get('queryStringParameters', {}) or {}
        report_type = query_params.get('type', 'summary')
        time_range = query_params.get('timeRange', '24h')
        
        # Generate report based on type
        if report_type == 'summary':
            report = generate_summary_report(time_range)
        elif report_type == 'demographics':
            report = generate_demographics_report(time_range)
        elif report_type == 'objects':
            report = generate_object_detection_report(time_range)
        elif report_type == 'security':
            report = generate_security_report(time_range)
        else:
            report = generate_summary_report(time_range)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(report, indent=2)
        }
        
    except Exception as e:
        logger.error(f"Error generating analytics: {str(e)}")
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def generate_summary_report(time_range: str) -> Dict[str, Any]:
    \"\"\"Generate a comprehensive summary report.\"\"\"
    try:
        # Get analysis results from S3
        results = get_recent_analysis_results(time_range)
        
        # Calculate metrics
        total_images = len(results)
        total_faces = sum(len(r.get('analyses', {}).get('faces', {}).get('FaceDetails', [])) for r in results)
        total_labels = sum(len(r.get('analyses', {}).get('labels', {}).get('Labels', [])) for r in results)
        
        # Aggregate label confidence
        high_confidence_labels = 0
        for result in results:
            labels = result.get('analyses', {}).get('labels', {}).get('Labels', [])
            high_confidence_labels += len([l for l in labels if l.get('Confidence', 0) > 90])
        
        # Calculate demographics
        demographics = calculate_demographics(results)
        
        # Top detected objects
        top_objects = get_top_objects(results, limit=10)
        
        # Security insights
        security_flags = count_security_flags(results)
        
        report = {
            'report_type': 'summary',
            'time_range': time_range,
            'generated_at': datetime.utcnow().isoformat(),
            'metrics': {
                'total_images_analyzed': total_images,
                'total_faces_detected': total_faces,
                'total_labels_detected': total_labels,
                'high_confidence_labels': high_confidence_labels
            },
            'demographics': demographics,
            'top_objects': top_objects,
            'security': security_flags,
            'recommendations': generate_recommendations(results)
        }
        
        return report
        
    except Exception as e:
        logger.error(f"Error generating summary report: {str(e)}")
        return {'error': str(e)}

def get_recent_analysis_results(time_range: str) -> List[Dict[str, Any]]:
    \"\"\"Retrieve recent analysis results from S3.\"\"\"
    bucket_name = os.environ['BUCKET_NAME']
    results = []
    
    try:
        # List objects in results folder
        response = s3.list_objects_v2(
            Bucket=bucket_name,
            Prefix='results/',
            MaxKeys=100  # Limit for demo purposes
        )
        
        for obj in response.get('Contents', []):
            if obj['Key'].endswith('_analysis.json'):
                try:
                    # Get object content
                    obj_response = s3.get_object(Bucket=bucket_name, Key=obj['Key'])
                    content = json.loads(obj_response['Body'].read().decode('utf-8'))
                    
                    # Check if within time range
                    if is_within_time_range(content.get('timestamp'), time_range):
                        results.append(content)
                        
                except Exception as e:
                    logger.warning(f"Failed to process {obj['Key']}: {str(e)}")
                    
    except Exception as e:
        logger.error(f"Error retrieving results: {str(e)}")
    
    return results

def is_within_time_range(timestamp_str: str, time_range: str) -> bool:
    \"\"\"Check if timestamp is within specified time range.\"\"\"
    if not timestamp_str:
        return False
        
    try:
        timestamp = datetime.fromisoformat(timestamp_str.replace('Z', '+00:00'))
        now = datetime.utcnow().replace(tzinfo=timestamp.tzinfo)
        
        if time_range == '1h':
            return now - timestamp <= timedelta(hours=1)
        elif time_range == '24h':
            return now - timestamp <= timedelta(hours=24)
        elif time_range == '7d':
            return now - timestamp <= timedelta(days=7)
        else:
            return now - timestamp <= timedelta(hours=24)  # Default to 24h
            
    except Exception:
        return False

def calculate_demographics(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    \"\"\"Calculate demographic insights from face analysis.\"\"\"
    age_groups = defaultdict(int)
    genders = defaultdict(int)
    emotions = defaultdict(int)
    
    for result in results:
        faces = result.get('analyses', {}).get('faces', {}).get('FaceDetails', [])
        
        for face in faces:
            # Age grouping
            age_range = face.get('AgeRange', {})
            low_age = age_range.get('Low', 0)
            if low_age < 18:
                age_groups['Under 18'] += 1
            elif low_age < 35:
                age_groups['18-34'] += 1
            elif low_age < 50:
                age_groups['35-49'] += 1
            elif low_age < 65:
                age_groups['50-64'] += 1
            else:
                age_groups['65+'] += 1
            
            # Gender
            gender = face.get('Gender', {})
            if gender.get('Confidence', 0) > 80:
                genders[gender.get('Value', 'Unknown')] += 1
            
            # Emotions
            face_emotions = face.get('Emotions', [])
            if face_emotions:
                top_emotion = max(face_emotions, key=lambda x: x.get('Confidence', 0))
                if top_emotion.get('Confidence', 0) > 70:
                    emotions[top_emotion.get('Type', 'Unknown')] += 1
    
    return {
        'age_groups': dict(age_groups),
        'genders': dict(genders),
        'emotions': dict(emotions)
    }

def get_top_objects(results: List[Dict[str, Any]], limit: int = 10) -> List[Dict[str, Any]]:
    \"\"\"Get most frequently detected objects.\"\"\"
    object_counts = defaultdict(lambda: {'count': 0, 'confidence_sum': 0})
    
    for result in results:
        labels = result.get('analyses', {}).get('labels', {}).get('Labels', [])
        
        for label in labels:
            name = label.get('Name')
            confidence = label.get('Confidence', 0)
            
            if confidence > 70:  # Only high-confidence labels
                object_counts[name]['count'] += 1
                object_counts[name]['confidence_sum'] += confidence
    
    # Calculate average confidence and sort by frequency
    top_objects = []
    for name, data in object_counts.items():
        avg_confidence = data['confidence_sum'] / data['count'] if data['count'] > 0 else 0
        top_objects.append({
            'name': name,
            'count': data['count'],
            'avg_confidence': round(avg_confidence, 1)
        })
    
    # Sort by count and limit results
    top_objects.sort(key=lambda x: x['count'], reverse=True)
    return top_objects[:limit]

def count_security_flags(results: List[Dict[str, Any]]) -> Dict[str, Any]:
    \"\"\"Count security-related flags from moderation analysis.\"\"\"
    moderation_labels = defaultdict(int)
    total_flags = 0
    
    for result in results:
        moderation = result.get('analyses', {}).get('moderation', {})
        labels = moderation.get('ModerationLabels', [])
        
        for label in labels:
            name = label.get('Name')
            confidence = label.get('Confidence', 0)
            
            if confidence > 80:  # High-confidence moderation flags
                moderation_labels[name] += 1
                total_flags += 1
    
    return {
        'total_flags': total_flags,
        'flag_types': dict(moderation_labels)
    }

def generate_recommendations(results: List[Dict[str, Any]]) -> List[str]:
    \"\"\"Generate actionable recommendations based on analysis.\"\"\"
    recommendations = []
    
    if len(results) > 10:
        recommendations.append("Consider implementing automated alerts for high-traffic periods")
    
    # Check for consistent face detection
    total_faces = sum(len(r.get('analyses', {}).get('faces', {}).get('FaceDetails', [])) for r in results)
    if total_faces > len(results) * 2:  # More than 2 faces per image on average
        recommendations.append("High foot traffic detected - consider crowd management strategies")
    
    # Check for security flags
    security_flags = count_security_flags(results)
    if security_flags['total_flags'] > 0:
        recommendations.append("Security concerns detected - review moderation alerts")
    
    if not recommendations:
        recommendations.append("System operating normally - continue monitoring")
    
    return recommendations

# Additional report functions would be implemented similarly...
def generate_demographics_report(time_range: str) -> Dict[str, Any]:
    \"\"\"Generate detailed demographics report.\"\"\"
    # Implementation would be similar to summary but focused on demographics
    return {'report_type': 'demographics', 'message': 'Demographics report placeholder'}

def generate_object_detection_report(time_range: str) -> Dict[str, Any]:
    \"\"\"Generate object detection report.\"\"\"
    return {'report_type': 'objects', 'message': 'Object detection report placeholder'}

def generate_security_report(time_range: str) -> Dict[str, Any]:
    \"\"\"Generate security-focused report.\"\"\"
    return {'report_type': 'security', 'message': 'Security report placeholder'}
""")
        )

        return function

    def _create_api_gateway(self) -> apigateway.RestApi:
        """Create API Gateway for REST endpoints."""
        api = apigateway.RestApi(
            self, "ComputerVisionAPI",
            rest_api_name="Computer Vision Analytics API",
            description="API for computer vision analytics and reporting",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key"]
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            )
        )

        # Create analytics resource
        analytics_resource = api.root.add_resource("analytics")
        
        # Add reports resource
        reports_resource = analytics_resource.add_resource("reports")
        
        # Add GET method for reports
        reports_resource.add_method(
            "GET",
            apigateway.LambdaIntegration(
                self.analytics_function,
                proxy=True
            ),
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        # Create face collection management resource
        faces_resource = api.root.add_resource("faces")
        collections_resource = faces_resource.add_resource("collections")
        
        # Add POST method for creating collections
        collections_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(
                self.image_processor_function,
                proxy=True
            )
        )

        return api

    def _configure_s3_notifications(self) -> None:
        """Configure S3 bucket notifications to trigger Lambda functions."""
        # Add notification for image uploads
        self.media_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.image_processor_function),
            s3.NotificationKeyFilter(
                prefix="images/",
                suffix=".jpg"
            )
        )
        
        self.media_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.image_processor_function),
            s3.NotificationKeyFilter(
                prefix="images/",
                suffix=".jpeg"
            )
        )
        
        self.media_bucket.add_event_notification(
            s3.EventType.OBJECT_CREATED,
            s3_notifications.LambdaDestination(self.image_processor_function),
            s3.NotificationKeyFilter(
                prefix="images/",
                suffix=".png"
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resource information."""
        CfnOutput(
            self, "MediaBucketName",
            value=self.media_bucket.bucket_name,
            description="Name of the S3 bucket for storing images and videos",
            export_name=f"{self.stack_name}-MediaBucketName"
        )

        CfnOutput(
            self, "MediaBucketArn",
            value=self.media_bucket.bucket_arn,
            description="ARN of the S3 bucket for storing images and videos",
            export_name=f"{self.stack_name}-MediaBucketArn"
        )

        CfnOutput(
            self, "KinesisDataStreamName",
            value=self.kinesis_data_stream.stream_name,
            description="Name of the Kinesis Data Stream for analysis results",
            export_name=f"{self.stack_name}-KinesisDataStreamName"
        )

        CfnOutput(
            self, "KinesisVideoStreamName",
            value=self.kinesis_video_stream.name,
            description="Name of the Kinesis Video Stream for real-time processing",
            export_name=f"{self.stack_name}-KinesisVideoStreamName"
        )

        CfnOutput(
            self, "RekognitionServiceRoleArn",
            value=self.rekognition_role.role_arn,
            description="ARN of the IAM role for Rekognition service access",
            export_name=f"{self.stack_name}-RekognitionServiceRoleArn"
        )

        CfnOutput(
            self, "ImageProcessorFunctionArn",
            value=self.image_processor_function.function_arn,
            description="ARN of the Lambda function for image processing",
            export_name=f"{self.stack_name}-ImageProcessorFunctionArn"
        )

        CfnOutput(
            self, "AnalyticsFunctionArn",
            value=self.analytics_function.function_arn,
            description="ARN of the Lambda function for analytics",
            export_name=f"{self.stack_name}-AnalyticsFunctionArn"
        )

        CfnOutput(
            self, "APIGatewayEndpoint",
            value=self.api.url,
            description="URL of the API Gateway endpoint for analytics",
            export_name=f"{self.stack_name}-APIGatewayEndpoint"
        )

        CfnOutput(
            self, "FaceCollectionPrefix",
            value=f"retail-faces-{self.account}",
            description="Prefix for face collection names",
            export_name=f"{self.stack_name}-FaceCollectionPrefix"
        )


# Main application entry point
app = cdk.App()

# Get environment configuration
env = cdk.Environment(
    account=os.environ.get('CDK_DEFAULT_ACCOUNT'),
    region=os.environ.get('CDK_DEFAULT_REGION', 'us-east-1')
)

# Create the stack
ComputerVisionStack(
    app, "ComputerVisionStack",
    env=env,
    description="Computer Vision Applications with Amazon Rekognition - CDK Python Stack",
    stack_name="computer-vision-rekognition"
)

# Synthesize the stack
app.synth()