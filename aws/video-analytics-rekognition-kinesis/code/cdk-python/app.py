#!/usr/bin/env python3
"""
Real-Time Video Analytics with Amazon Rekognition and Kinesis
CDK Python Application

This CDK application deploys a comprehensive real-time video analytics platform
that processes video streams using Amazon Rekognition, stores results in DynamoDB,
and provides real-time alerting capabilities.

Architecture Components:
- Kinesis Video Streams for video ingestion
- Amazon Rekognition stream processors for computer vision
- Kinesis Data Streams for analytics event processing
- Lambda functions for event processing and API queries
- DynamoDB tables for metadata storage
- SNS for alerting
- API Gateway for query endpoints
- IAM roles and policies with least privilege access
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    Duration,
    RemovalPolicy,
    CfnOutput,
    aws_iam as iam,
    aws_lambda as lambda_,
    aws_dynamodb as dynamodb,
    aws_kinesis as kinesis,
    aws_kinesisanalytics as kinesisanalytics,
    aws_sns as sns,
    aws_apigateway as apigateway,
    aws_logs as logs,
    aws_events as events,
    aws_events_targets as targets,
)
from constructs import Construct


class VideoAnalyticsStack(Stack):
    """
    CDK Stack for Real-Time Video Analytics Platform
    
    This stack creates a complete video analytics infrastructure including:
    - Video stream ingestion and processing
    - Computer vision analysis with Rekognition
    - Real-time event processing and alerting
    - Query APIs for analytics data
    - Monitoring and logging
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Stack configuration
        self.project_name = "video-analytics"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Create core infrastructure
        self._create_iam_roles()
        self._create_data_storage()
        self._create_streaming_infrastructure()
        self._create_lambda_functions()
        self._create_api_gateway()
        self._create_monitoring()
        self._create_outputs()

    def _create_iam_roles(self) -> None:
        """Create IAM roles for video analytics services"""
        
        # Role for Rekognition stream processor
        self.rekognition_role = iam.Role(
            self,
            "RekognitionStreamRole",
            assumed_by=iam.ServicePrincipal("rekognition.amazonaws.com"),
            description="Role for Rekognition stream processor to access video streams",
            inline_policies={
                "KinesisVideoAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesisvideo:GetDataEndpoint",
                                "kinesisvideo:GetMedia",
                                "kinesisvideo:GetMediaForFragmentList",
                                "kinesisvideo:ListFragments"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:PutRecord",
                                "kinesis:PutRecords"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

        # Role for Lambda functions
        self.lambda_execution_role = iam.Role(
            self,
            "LambdaExecutionRole",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            description="Execution role for video analytics Lambda functions",
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ],
            inline_policies={
                "VideoAnalyticsAccess": iam.PolicyDocument(
                    statements=[
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "dynamodb:PutItem",
                                "dynamodb:GetItem",
                                "dynamodb:Query",
                                "dynamodb:Scan",
                                "dynamodb:UpdateItem"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "sns:Publish"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "kinesis:DescribeStream",
                                "kinesis:GetShardIterator",
                                "kinesis:GetRecords",
                                "kinesis:ListStreams"
                            ],
                            resources=["*"]
                        ),
                        iam.PolicyStatement(
                            effect=iam.Effect.ALLOW,
                            actions=[
                                "rekognition:CreateCollection",
                                "rekognition:DeleteCollection",
                                "rekognition:ListCollections",
                                "rekognition:IndexFaces",
                                "rekognition:SearchFaces",
                                "rekognition:SearchFacesByImage"
                            ],
                            resources=["*"]
                        )
                    ]
                )
            }
        )

    def _create_data_storage(self) -> None:
        """Create DynamoDB tables for storing analytics metadata"""
        
        # Table for detection events
        self.detections_table = dynamodb.Table(
            self,
            "DetectionsTable",
            table_name=f"{self.project_name}-detections-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="StreamName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            time_to_live_attribute="TTL"
        )

        # Global Secondary Index for querying by detection type
        self.detections_table.add_global_secondary_index(
            index_name="DetectionTypeIndex",
            partition_key=dynamodb.Attribute(
                name="DetectionType",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            )
        )

        # Table for face detection metadata
        self.faces_table = dynamodb.Table(
            self,
            "FacesTable",
            table_name=f"{self.project_name}-faces-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="FaceId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            removal_policy=RemovalPolicy.DESTROY,
            point_in_time_recovery=True,
            time_to_live_attribute="TTL"
        )

        # Global Secondary Index for querying by stream name
        self.faces_table.add_global_secondary_index(
            index_name="StreamNameIndex",
            partition_key=dynamodb.Attribute(
                name="StreamName",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="Timestamp",
                type=dynamodb.AttributeType.NUMBER
            )
        )

    def _create_streaming_infrastructure(self) -> None:
        """Create Kinesis streams for video and analytics data"""
        
        # Kinesis Data Stream for analytics results
        self.analytics_stream = kinesis.Stream(
            self,
            "AnalyticsStream",
            stream_name=f"{self.project_name}-analytics-{self.environment}",
            shard_count=2,
            retention_period=Duration.hours(24),
            encryption=kinesis.StreamEncryption.KMS
        )

        # SNS topic for security alerts
        self.alerts_topic = sns.Topic(
            self,
            "SecurityAlertsTopic",
            topic_name=f"{self.project_name}-security-alerts-{self.environment}",
            display_name="Video Analytics Security Alerts"
        )

        # Add email subscription for alerts (can be configured via context)
        alert_email = self.node.try_get_context("alert_email")
        if alert_email:
            sns.Subscription(
                self,
                "EmailAlertSubscription",
                topic=self.alerts_topic,
                endpoint=alert_email,
                protocol=sns.SubscriptionProtocol.EMAIL
            )

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for processing and API queries"""
        
        # Create Lambda layer for common dependencies
        self.lambda_layer = lambda_.LayerVersion(
            self,
            "VideoAnalyticsLayer",
            code=lambda_.Code.from_inline("""
# This would contain common dependencies like boto3, json, etc.
# In production, create a proper layer with requirements
import json
import boto3
from datetime import datetime, timedelta
            """),
            compatible_runtimes=[lambda_.Runtime.PYTHON_3_9],
            description="Common dependencies for video analytics functions"
        )

        # Analytics processing Lambda function
        self.analytics_processor = lambda_.Function(
            self,
            "AnalyticsProcessor",
            function_name=f"{self.project_name}-analytics-processor-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_analytics_processor_code()),
            timeout=Duration.minutes(5),
            memory_size=512,
            role=self.lambda_execution_role,
            layers=[self.lambda_layer],
            environment={
                "DETECTIONS_TABLE": self.detections_table.table_name,
                "FACES_TABLE": self.faces_table.table_name,
                "SNS_TOPIC_ARN": self.alerts_topic.topic_arn,
                "ENVIRONMENT": self.environment
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Add Kinesis event source for analytics processor
        self.analytics_processor.add_event_source(
            lambda_.KinesisEventSource(
                stream=self.analytics_stream,
                batch_size=10,
                starting_position=lambda_.StartingPosition.LATEST,
                retry_attempts=3
            )
        )

        # Query API Lambda function
        self.query_api = lambda_.Function(
            self,
            "QueryAPI",
            function_name=f"{self.project_name}-query-api-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_query_api_code()),
            timeout=Duration.seconds(30),
            memory_size=256,
            role=self.lambda_execution_role,
            layers=[self.lambda_layer],
            environment={
                "DETECTIONS_TABLE": self.detections_table.table_name,
                "FACES_TABLE": self.faces_table.table_name,
                "PROJECT_NAME": self.project_name,
                "ENVIRONMENT": self.environment
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

        # Face collection management Lambda function
        self.face_collection_manager = lambda_.Function(
            self,
            "FaceCollectionManager",
            function_name=f"{self.project_name}-face-manager-{self.environment}",
            runtime=lambda_.Runtime.PYTHON_3_9,
            handler="index.lambda_handler",
            code=lambda_.Code.from_inline(self._get_face_manager_code()),
            timeout=Duration.minutes(2),
            memory_size=256,
            role=self.lambda_execution_role,
            environment={
                "COLLECTION_NAME": f"{self.project_name}-faces-{self.environment}",
                "ENVIRONMENT": self.environment
            },
            log_retention=logs.RetentionDays.ONE_WEEK
        )

    def _create_api_gateway(self) -> None:
        """Create API Gateway for video analytics queries"""
        
        # Create REST API
        self.api = apigateway.RestApi(
            self,
            "VideoAnalyticsAPI",
            rest_api_name=f"{self.project_name}-api-{self.environment}",
            description="API for querying video analytics data",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization"]
            ),
            endpoint_configuration=apigateway.EndpointConfiguration(
                types=[apigateway.EndpointType.REGIONAL]
            )
        )

        # Create Lambda integration
        query_integration = apigateway.LambdaIntegration(
            self.query_api,
            request_templates={
                "application/json": '{"statusCode": "200"}'
            }
        )

        # Add API resources and methods
        detections_resource = self.api.root.add_resource("detections")
        detections_resource.add_method("GET", query_integration)

        faces_resource = self.api.root.add_resource("faces")
        faces_resource.add_method("GET", query_integration)

        stats_resource = self.api.root.add_resource("stats")
        stats_resource.add_method("GET", query_integration)

        # Face collection management endpoints
        collections_resource = self.api.root.add_resource("collections")
        collections_resource.add_method(
            "POST",
            apigateway.LambdaIntegration(self.face_collection_manager)
        )
        collections_resource.add_method(
            "DELETE",
            apigateway.LambdaIntegration(self.face_collection_manager)
        )

        # Create API deployment
        deployment = apigateway.Deployment(
            self,
            "APIDeployment",
            api=self.api,
            description=f"Deployment for {self.environment} environment"
        )

        # Create stage
        self.api_stage = apigateway.Stage(
            self,
            "APIStage",
            deployment=deployment,
            stage_name=self.environment,
            throttling_rate_limit=1000,
            throttling_burst_limit=2000
        )

    def _create_monitoring(self) -> None:
        """Create CloudWatch monitoring and alarms"""
        
        # Create custom log groups
        self.video_analytics_log_group = logs.LogGroup(
            self,
            "VideoAnalyticsLogGroup",
            log_group_name=f"/aws/video-analytics/{self.project_name}-{self.environment}",
            retention=logs.RetentionDays.ONE_WEEK,
            removal_policy=RemovalPolicy.DESTROY
        )

        # CloudWatch alarm for Lambda errors
        lambda_error_alarm = events.Rule(
            self,
            "LambdaErrorAlarm",
            description="Monitor Lambda function errors",
            event_pattern=events.EventPattern(
                source=["aws.lambda"],
                detail_type=["Lambda Function Invocation Result - Failure"],
                detail={
                    "functionName": [
                        self.analytics_processor.function_name,
                        self.query_api.function_name
                    ]
                }
            )
        )

        # Add SNS target for error notifications
        lambda_error_alarm.add_target(
            targets.SnsTopic(
                self.alerts_topic,
                message=events.RuleTargetInput.from_text(
                    "Lambda function error detected in video analytics system"
                )
            )
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources"""
        
        CfnOutput(
            self,
            "DetectionsTableName",
            value=self.detections_table.table_name,
            description="DynamoDB table for detection events",
            export_name=f"{self.stack_name}-DetectionsTable"
        )

        CfnOutput(
            self,
            "FacesTableName",
            value=self.faces_table.table_name,
            description="DynamoDB table for face detection metadata",
            export_name=f"{self.stack_name}-FacesTable"
        )

        CfnOutput(
            self,
            "AnalyticsStreamName",
            value=self.analytics_stream.stream_name,
            description="Kinesis Data Stream for analytics events",
            export_name=f"{self.stack_name}-AnalyticsStream"
        )

        CfnOutput(
            self,
            "AlertsTopicArn",
            value=self.alerts_topic.topic_arn,
            description="SNS topic for security alerts",
            export_name=f"{self.stack_name}-AlertsTopic"
        )

        CfnOutput(
            self,
            "APIEndpoint",
            value=self.api.url,
            description="API Gateway endpoint for video analytics queries",
            export_name=f"{self.stack_name}-APIEndpoint"
        )

        CfnOutput(
            self,
            "RekognitionRoleArn",
            value=self.rekognition_role.role_arn,
            description="IAM role ARN for Rekognition stream processor",
            export_name=f"{self.stack_name}-RekognitionRole"
        )

    def _get_analytics_processor_code(self) -> str:
        """Return the Lambda function code for analytics processing"""
        return '''
import json
import boto3
import base64
from datetime import datetime, timedelta
import os

dynamodb = boto3.resource('dynamodb')
sns = boto3.client('sns')
rekognition = boto3.client('rekognition')

DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN')

def lambda_handler(event, context):
    """Process video analytics events from Kinesis stream"""
    processed_records = 0
    
    for record in event['Records']:
        try:
            # Decode Kinesis data
            payload = base64.b64decode(record['kinesis']['data'])
            data = json.loads(payload)
            
            process_detection_event(data)
            processed_records += 1
            
        except Exception as e:
            print(f"Error processing record: {str(e)}")
            # In production, consider sending to DLQ
    
    return {
        'statusCode': 200,
        'processedRecords': processed_records
    }

def process_detection_event(data):
    """Process individual detection event"""
    timestamp = datetime.now().timestamp()
    stream_name = data.get('StreamName', 'unknown')
    
    # Process different types of detection events
    if 'FaceSearchResponse' in data:
        process_face_detection(data['FaceSearchResponse'], stream_name, timestamp)
    
    if 'LabelDetectionResponse' in data:
        process_label_detection(data['LabelDetectionResponse'], stream_name, timestamp)
    
    if 'PersonTrackingResponse' in data:
        process_person_tracking(data['PersonTrackingResponse'], stream_name, timestamp)

def process_face_detection(face_data, stream_name, timestamp):
    """Process face detection results"""
    table = dynamodb.Table(FACES_TABLE)
    
    for face_match in face_data.get('FaceMatches', []):
        face_id = face_match['Face']['FaceId']
        confidence = face_match['Face']['Confidence']
        similarity = face_match['Similarity']
        
        # Calculate TTL (30 days from now)
        ttl = int((datetime.now() + timedelta(days=30)).timestamp())
        
        # Store face detection event
        table.put_item(
            Item={
                'FaceId': face_id,
                'Timestamp': int(timestamp * 1000),
                'StreamName': stream_name,
                'Confidence': str(confidence),
                'Similarity': str(similarity),
                'BoundingBox': face_match['Face']['BoundingBox'],
                'TTL': ttl
            }
        )
        
        # Send alert for high-confidence matches
        if similarity > 90:
            send_alert(
                f"High confidence face match detected: {face_id}",
                f"Similarity: {similarity}%, Stream: {stream_name}, Time: {datetime.fromtimestamp(timestamp)}"
            )

def process_label_detection(label_data, stream_name, timestamp):
    """Process object/label detection results"""
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    for label in label_data.get('Labels', []):
        label_name = label['Label']['Name']
        confidence = label['Label']['Confidence']
        
        # Calculate TTL (30 days from now)
        ttl = int((datetime.now() + timedelta(days=30)).timestamp())
        
        # Store detection event
        table.put_item(
            Item={
                'StreamName': stream_name,
                'Timestamp': int(timestamp * 1000),
                'DetectionType': 'Label',
                'Label': label_name,
                'Confidence': str(confidence),
                'BoundingBox': json.dumps(label['Label'].get('BoundingBox', {})),
                'TTL': ttl
            }
        )
        
        # Check for security-relevant objects
        security_objects = ['Weapon', 'Gun', 'Knife', 'Person', 'Car', 'Motorcycle', 'Backpack']
        if label_name in security_objects and confidence > 80:
            send_alert(
                f"Security object detected: {label_name}",
                f"Confidence: {confidence}%, Stream: {stream_name}, Time: {datetime.fromtimestamp(timestamp)}"
            )

def process_person_tracking(person_data, stream_name, timestamp):
    """Process person tracking results"""
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    for person in person_data.get('Persons', []):
        person_id = person.get('Index', 'unknown')
        
        # Calculate TTL (30 days from now)
        ttl = int((datetime.now() + timedelta(days=30)).timestamp())
        
        # Store person tracking event
        table.put_item(
            Item={
                'StreamName': stream_name,
                'Timestamp': int(timestamp * 1000),
                'DetectionType': 'Person',
                'PersonId': str(person_id),
                'BoundingBox': json.dumps(person.get('BoundingBox', {})),
                'TTL': ttl
            }
        )

def send_alert(subject, message):
    """Send alert via SNS"""
    if SNS_TOPIC_ARN:
        try:
            sns.publish(
                TopicArn=SNS_TOPIC_ARN,
                Subject=subject,
                Message=message
            )
        except Exception as e:
            print(f"Failed to send alert: {str(e)}")
'''

    def _get_query_api_code(self) -> str:
        """Return the Lambda function code for query API"""
        return '''
import json
import boto3
from boto3.dynamodb.conditions import Key
from datetime import datetime, timedelta
import os

dynamodb = boto3.resource('dynamodb')

DETECTIONS_TABLE = os.environ['DETECTIONS_TABLE']
FACES_TABLE = os.environ['FACES_TABLE']
PROJECT_NAME = os.environ['PROJECT_NAME']

def lambda_handler(event, context):
    """Handle API Gateway requests for video analytics data"""
    try:
        # Parse request
        http_method = event['httpMethod']
        path = event['path']
        query_params = event.get('queryStringParameters', {}) or {}
        
        # Add CORS headers
        headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
        }
        
        if path == '/detections' and http_method == 'GET':
            return get_detections(query_params, headers)
        elif path == '/faces' and http_method == 'GET':
            return get_face_detections(query_params, headers)
        elif path == '/stats' and http_method == 'GET':
            return get_statistics(query_params, headers)
        else:
            return {
                'statusCode': 404,
                'headers': headers,
                'body': json.dumps({'error': 'Not found'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def get_detections(params, headers):
    """Get detection events from DynamoDB"""
    table = dynamodb.Table(DETECTIONS_TABLE)
    
    stream_name = params.get('stream')
    hours_back = int(params.get('hours', 24))
    detection_type = params.get('type')
    
    if not stream_name:
        return {
            'statusCode': 400,
            'headers': headers,
            'body': json.dumps({'error': 'stream parameter required'})
        }
    
    # Query recent detections
    start_time = int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
    
    key_condition = Key('StreamName').eq(stream_name) & Key('Timestamp').gte(start_time)
    
    response = table.query(
        KeyConditionExpression=key_condition,
        ScanIndexForward=False,
        Limit=100
    )
    
    # Filter by detection type if specified
    items = response['Items']
    if detection_type:
        items = [item for item in items if item.get('DetectionType') == detection_type]
    
    return {
        'statusCode': 200,
        'headers': headers,
        'body': json.dumps({
            'detections': items,
            'count': len(items),
            'stream': stream_name,
            'timeRange': f"{hours_back} hours"
        }, default=str)
    }

def get_face_detections(params, headers):
    """Get face detection events from DynamoDB"""
    table = dynamodb.Table(FACES_TABLE)
    
    stream_name = params.get('stream')
    hours_back = int(params.get('hours', 24))
    
    try:
        if stream_name:
            # Query by stream name using GSI
            start_time = int((datetime.now() - timedelta(hours=hours_back)).timestamp() * 1000)
            
            response = table.query(
                IndexName='StreamNameIndex',
                KeyConditionExpression=Key('StreamName').eq(stream_name) & 
                                     Key('Timestamp').gte(start_time),
                ScanIndexForward=False,
                Limit=50
            )
        else:
            # Scan recent face detections
            response = table.scan(Limit=50)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'faces': response['Items'],
                'count': len(response['Items']),
                'stream': stream_name or 'all'
            }, default=str)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f"Query failed: {str(e)}"})
        }

def get_statistics(params, headers):
    """Get analytics statistics"""
    try:
        # Get detection counts by type
        detections_table = dynamodb.Table(DETECTIONS_TABLE)
        faces_table = dynamodb.Table(FACES_TABLE)
        
        # Simple count queries (in production, use more sophisticated analytics)
        detections_response = detections_table.scan(
            Select='COUNT',
            FilterExpression=Key('Timestamp').gte(
                int((datetime.now() - timedelta(hours=24)).timestamp() * 1000)
            )
        )
        
        faces_response = faces_table.scan(
            Select='COUNT',
            FilterExpression=Key('Timestamp').gte(
                int((datetime.now() - timedelta(hours=24)).timestamp() * 1000)
            )
        )
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'statistics': {
                    'detectionsLast24h': detections_response.get('Count', 0),
                    'facesLast24h': faces_response.get('Count', 0),
                    'timestamp': datetime.now().isoformat()
                }
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': 'Statistics endpoint - basic implementation',
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })
        }
'''

    def _get_face_manager_code(self) -> str:
        """Return the Lambda function code for face collection management"""
        return '''
import json
import boto3
import os

rekognition = boto3.client('rekognition')

COLLECTION_NAME = os.environ['COLLECTION_NAME']

def lambda_handler(event, context):
    """Manage Rekognition face collections"""
    try:
        http_method = event['httpMethod']
        
        headers = {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization',
            'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS'
        }
        
        if http_method == 'POST':
            return create_collection(headers)
        elif http_method == 'DELETE':
            return delete_collection(headers)
        else:
            return {
                'statusCode': 405,
                'headers': headers,
                'body': json.dumps({'error': 'Method not allowed'})
            }
            
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({'error': str(e)})
        }

def create_collection(headers):
    """Create Rekognition face collection"""
    try:
        response = rekognition.create_collection(CollectionId=COLLECTION_NAME)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': f'Face collection {COLLECTION_NAME} created successfully',
                'collectionArn': response['CollectionArn'],
                'statusCode': response['StatusCode']
            })
        }
        
    except rekognition.exceptions.ResourceAlreadyExistsException:
        return {
            'statusCode': 409,
            'headers': headers,
            'body': json.dumps({
                'message': f'Face collection {COLLECTION_NAME} already exists'
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Failed to create collection: {str(e)}'})
        }

def delete_collection(headers):
    """Delete Rekognition face collection"""
    try:
        response = rekognition.delete_collection(CollectionId=COLLECTION_NAME)
        
        return {
            'statusCode': 200,
            'headers': headers,
            'body': json.dumps({
                'message': f'Face collection {COLLECTION_NAME} deleted successfully',
                'statusCode': response['StatusCode']
            })
        }
        
    except rekognition.exceptions.ResourceNotFoundException:
        return {
            'statusCode': 404,
            'headers': headers,
            'body': json.dumps({
                'message': f'Face collection {COLLECTION_NAME} not found'
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': headers,
            'body': json.dumps({'error': f'Failed to delete collection: {str(e)}'})
        }
'''


class VideoAnalyticsApp(cdk.App):
    """CDK Application for Video Analytics Platform"""
    
    def __init__(self):
        super().__init__()
        
        # Get environment configuration
        env = cdk.Environment(
            account=os.environ.get("CDK_DEFAULT_ACCOUNT"),
            region=os.environ.get("CDK_DEFAULT_REGION", "us-east-1")
        )
        
        # Create the main stack
        VideoAnalyticsStack(
            self,
            "VideoAnalyticsStack",
            env=env,
            description="Real-Time Video Analytics with Amazon Rekognition and Kinesis"
        )


# Create and synthesize the CDK app
app = VideoAnalyticsApp()
app.synth()