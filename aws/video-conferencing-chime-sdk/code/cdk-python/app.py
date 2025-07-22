#!/usr/bin/env python3
"""
CDK Python application for Amazon Chime SDK Video Conferencing Solution.

This application creates a complete video conferencing infrastructure using:
- Amazon Chime SDK for real-time audio/video communication
- AWS Lambda for backend logic
- Amazon API Gateway for RESTful endpoints
- Amazon DynamoDB for meeting metadata
- Amazon S3 for recording storage
- Amazon SNS for event notifications
- Amazon CloudWatch for monitoring

Author: AWS CDK Generator
Version: 1.0.0
"""

import os
from typing import Dict, Any

import aws_cdk as cdk
from aws_cdk import (
    Stack,
    CfnOutput,
    Duration,
    RemovalPolicy,
    aws_lambda as lambda_,
    aws_apigateway as apigateway,
    aws_dynamodb as dynamodb,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sns_subscriptions as sns_subscriptions,
    aws_sqs as sqs,
    aws_iam as iam,
    aws_logs as logs,
    aws_cloudwatch as cloudwatch,
    aws_lambda_event_sources as lambda_event_sources,
)
from constructs import Construct


class VideoConferencingStack(Stack):
    """
    CDK Stack for Amazon Chime SDK Video Conferencing Solution.
    
    This stack creates all necessary infrastructure components for a scalable
    video conferencing platform with custom branding and advanced features.
    """

    def __init__(self, scope: Construct, construct_id: str, **kwargs) -> None:
        super().__init__(scope, construct_id, **kwargs)

        # Configuration parameters
        self.project_name = "video-conferencing"
        self.environment = self.node.try_get_context("environment") or "dev"
        
        # Create core infrastructure
        self._create_storage_resources()
        self._create_notification_resources()
        self._create_lambda_execution_role()
        self._create_lambda_functions()
        self._create_api_gateway()
        self._create_monitoring_resources()
        self._create_outputs()

    def _create_storage_resources(self) -> None:
        """Create S3 bucket for recordings and DynamoDB table for metadata."""
        
        # S3 bucket for meeting recordings and artifacts
        self.recordings_bucket = s3.Bucket(
            self, "RecordingsBucket",
            bucket_name=f"{self.project_name}-recordings-{self.account}-{self.region}",
            versioned=True,
            encryption=s3.BucketEncryption.S3_MANAGED,
            public_read_access=False,
            public_write_access=False,
            block_public_access=s3.BlockPublicAccess.BLOCK_ALL,
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
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN
        )

        # DynamoDB table for meeting metadata
        self.meetings_table = dynamodb.Table(
            self, "MeetingsTable",
            table_name=f"{self.project_name}-meetings-{self.environment}",
            partition_key=dynamodb.Attribute(
                name="MeetingId",
                type=dynamodb.AttributeType.STRING
            ),
            sort_key=dynamodb.Attribute(
                name="CreatedAt",
                type=dynamodb.AttributeType.STRING
            ),
            billing_mode=dynamodb.BillingMode.PAY_PER_REQUEST,
            stream=dynamodb.StreamViewType.NEW_AND_OLD_IMAGES,
            point_in_time_recovery=True,
            removal_policy=RemovalPolicy.DESTROY if self.environment == "dev" else RemovalPolicy.RETAIN
        )

        # Add GSI for querying by external meeting ID
        self.meetings_table.add_global_secondary_index(
            index_name="ExternalMeetingIdIndex",
            partition_key=dynamodb.Attribute(
                name="ExternalMeetingId",
                type=dynamodb.AttributeType.STRING
            ),
            projection_type=dynamodb.ProjectionType.ALL
        )

    def _create_notification_resources(self) -> None:
        """Create SNS topic and SQS queue for event notifications."""
        
        # SNS topic for meeting events
        self.meeting_events_topic = sns.Topic(
            self, "MeetingEventsTopic",
            topic_name=f"{self.project_name}-events-{self.environment}",
            display_name="Chime SDK Meeting Events"
        )

        # SQS queue for processing meeting events
        self.event_processing_queue = sqs.Queue(
            self, "EventProcessingQueue",
            queue_name=f"{self.project_name}-event-processing-{self.environment}",
            visibility_timeout=Duration.seconds(300),
            dead_letter_queue=sqs.DeadLetterQueue(
                max_receive_count=3,
                queue=sqs.Queue(
                    self, "EventProcessingDLQ",
                    queue_name=f"{self.project_name}-event-processing-dlq-{self.environment}"
                )
            )
        )

        # Subscribe SQS to SNS
        self.meeting_events_topic.add_subscription(
            sns_subscriptions.SqsSubscription(self.event_processing_queue)
        )

    def _create_lambda_execution_role(self) -> None:
        """Create IAM role for Lambda functions with appropriate permissions."""
        
        self.lambda_execution_role = iam.Role(
            self, "LambdaExecutionRole",
            role_name=f"{self.project_name}-lambda-role-{self.environment}",
            assumed_by=iam.ServicePrincipal("lambda.amazonaws.com"),
            managed_policies=[
                iam.ManagedPolicy.from_aws_managed_policy_name(
                    "service-role/AWSLambdaBasicExecutionRole"
                )
            ]
        )

        # Add Chime SDK permissions
        self.lambda_execution_role.add_to_policy(
            iam.PolicyStatement(
                effect=iam.Effect.ALLOW,
                actions=[
                    "chime:CreateMeeting",
                    "chime:DeleteMeeting",
                    "chime:GetMeeting",
                    "chime:ListMeetings",
                    "chime:CreateAttendee",
                    "chime:DeleteAttendee",
                    "chime:GetAttendee",
                    "chime:ListAttendees",
                    "chime:BatchCreateAttendee",
                    "chime:BatchDeleteAttendee",
                    "chime:StartMeetingTranscription",
                    "chime:StopMeetingTranscription",
                    "chime:CreateMediaCapturePipeline",
                    "chime:DeleteMediaCapturePipeline",
                    "chime:GetMediaCapturePipeline",
                    "chime:ListMediaCapturePipelines"
                ],
                resources=["*"]
            )
        )

        # Add DynamoDB permissions
        self.meetings_table.grant_read_write_data(self.lambda_execution_role)

        # Add S3 permissions
        self.recordings_bucket.grant_read_write(self.lambda_execution_role)

        # Add SNS permissions
        self.meeting_events_topic.grant_publish(self.lambda_execution_role)

    def _create_lambda_functions(self) -> None:
        """Create Lambda functions for meeting and attendee management."""
        
        # Common Lambda environment variables
        common_env_vars = {
            "MEETINGS_TABLE_NAME": self.meetings_table.table_name,
            "RECORDINGS_BUCKET_NAME": self.recordings_bucket.bucket_name,
            "SNS_TOPIC_ARN": self.meeting_events_topic.topic_arn,
            "LOG_LEVEL": "INFO"
        }

        # Meeting management Lambda function
        self.meeting_handler = lambda_.Function(
            self, "MeetingHandler",
            function_name=f"{self.project_name}-meeting-handler-{self.environment}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_meeting_handler_code()),
            role=self.lambda_execution_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment=common_env_vars,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
            description="Handles Chime SDK meeting lifecycle operations"
        )

        # Attendee management Lambda function
        self.attendee_handler = lambda_.Function(
            self, "AttendeeHandler",
            function_name=f"{self.project_name}-attendee-handler-{self.environment}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_attendee_handler_code()),
            role=self.lambda_execution_role,
            timeout=Duration.seconds(30),
            memory_size=256,
            environment=common_env_vars,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
            description="Handles Chime SDK attendee management operations"
        )

        # Event processing Lambda function
        self.event_processor = lambda_.Function(
            self, "EventProcessor",
            function_name=f"{self.project_name}-event-processor-{self.environment}",
            runtime=lambda_.Runtime.NODEJS_18_X,
            handler="index.handler",
            code=lambda_.Code.from_inline(self._get_event_processor_code()),
            role=self.lambda_execution_role,
            timeout=Duration.seconds(300),
            memory_size=512,
            environment=common_env_vars,
            log_retention=logs.RetentionDays.ONE_WEEK,
            tracing=lambda_.Tracing.ACTIVE,
            description="Processes Chime SDK meeting events for analytics and recordings"
        )

        # Connect SQS to event processor
        self.event_processor.add_event_source(
            lambda_event_sources.SqsEventSource(
                self.event_processing_queue,
                batch_size=10,
                max_batching_window=Duration.seconds(5)
            )
        )

    def _create_api_gateway(self) -> None:
        """Create API Gateway REST API with proper routing and CORS."""
        
        # Create REST API
        self.api = apigateway.RestApi(
            self, "VideoConferencingApi",
            rest_api_name=f"{self.project_name}-api-{self.environment}",
            description="API for Chime SDK Video Conferencing",
            default_cors_preflight_options=apigateway.CorsOptions(
                allow_origins=apigateway.Cors.ALL_ORIGINS,
                allow_methods=apigateway.Cors.ALL_METHODS,
                allow_headers=["Content-Type", "X-Amz-Date", "Authorization", "X-Api-Key", "X-Amz-Security-Token"]
            ),
            deploy_options=apigateway.StageOptions(
                stage_name="prod",
                throttling_rate_limit=1000,
                throttling_burst_limit=2000,
                logging_level=apigateway.MethodLoggingLevel.INFO,
                data_trace_enabled=True,
                metrics_enabled=True
            )
        )

        # Create Lambda integrations
        meeting_integration = apigateway.LambdaIntegration(
            self.meeting_handler,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        attendee_integration = apigateway.LambdaIntegration(
            self.attendee_handler,
            proxy=True,
            integration_responses=[
                apigateway.IntegrationResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": "'*'"
                    }
                )
            ]
        )

        # Create API resources and methods
        # /meetings
        meetings_resource = self.api.root.add_resource("meetings")
        meetings_resource.add_method(
            "POST",
            meeting_integration,
            method_responses=[
                apigateway.MethodResponse(
                    status_code="200",
                    response_parameters={
                        "method.response.header.Access-Control-Allow-Origin": True
                    }
                )
            ]
        )

        # /meetings/{meetingId}
        meeting_id_resource = meetings_resource.add_resource("{meetingId}")
        meeting_id_resource.add_method("GET", meeting_integration)
        meeting_id_resource.add_method("DELETE", meeting_integration)

        # /meetings/{meetingId}/attendees
        attendees_resource = meeting_id_resource.add_resource("attendees")
        attendees_resource.add_method("POST", attendee_integration)

        # /meetings/{meetingId}/attendees/{attendeeId}
        attendee_id_resource = attendees_resource.add_resource("{attendeeId}")
        attendee_id_resource.add_method("GET", attendee_integration)
        attendee_id_resource.add_method("DELETE", attendee_integration)

        # Grant API Gateway permission to invoke Lambda functions
        self.meeting_handler.grant_invoke(iam.ServicePrincipal("apigateway.amazonaws.com"))
        self.attendee_handler.grant_invoke(iam.ServicePrincipal("apigateway.amazonaws.com"))

    def _create_monitoring_resources(self) -> None:
        """Create CloudWatch dashboards and alarms for monitoring."""
        
        # Create CloudWatch dashboard
        self.dashboard = cloudwatch.Dashboard(
            self, "VideoConferencingDashboard",
            dashboard_name=f"{self.project_name}-dashboard-{self.environment}"
        )

        # Add API Gateway metrics
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="API Gateway Requests",
                left=[
                    cloudwatch.Metric(
                        namespace="AWS/ApiGateway",
                        metric_name="Count",
                        dimensions_map={
                            "ApiName": self.api.rest_api_name
                        },
                        statistic="Sum"
                    )
                ],
                width=12,
                height=6
            )
        )

        # Add Lambda metrics
        self.dashboard.add_widgets(
            cloudwatch.GraphWidget(
                title="Lambda Function Duration",
                left=[
                    self.meeting_handler.metric_duration(),
                    self.attendee_handler.metric_duration()
                ],
                width=12,
                height=6
            )
        )

        # Create alarms for high error rates
        cloudwatch.Alarm(
            self, "HighErrorRateAlarm",
            alarm_name=f"{self.project_name}-high-error-rate-{self.environment}",
            metric=self.api.metric_client_error(),
            threshold=10,
            evaluation_periods=2,
            alarm_description="High error rate detected in API Gateway"
        )

    def _create_outputs(self) -> None:
        """Create CloudFormation outputs for important resources."""
        
        CfnOutput(
            self, "ApiEndpoint",
            value=self.api.url,
            description="API Gateway endpoint URL",
            export_name=f"{self.project_name}-api-endpoint-{self.environment}"
        )

        CfnOutput(
            self, "MeetingsTableName",
            value=self.meetings_table.table_name,
            description="DynamoDB table name for meeting metadata",
            export_name=f"{self.project_name}-meetings-table-{self.environment}"
        )

        CfnOutput(
            self, "RecordingsBucketName",
            value=self.recordings_bucket.bucket_name,
            description="S3 bucket name for meeting recordings",
            export_name=f"{self.project_name}-recordings-bucket-{self.environment}"
        )

        CfnOutput(
            self, "MeetingEventsTopicArn",
            value=self.meeting_events_topic.topic_arn,
            description="SNS topic ARN for meeting events",
            export_name=f"{self.project_name}-events-topic-{self.environment}"
        )

    def _get_meeting_handler_code(self) -> str:
        """Return the Node.js code for the meeting handler Lambda function."""
        return '''
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: `https://meetings-chime.${process.env.AWS_REGION}.amazonaws.com`
});

const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    const { httpMethod, path, body } = event;
    
    try {
        switch (httpMethod) {
            case 'POST':
                if (path === '/meetings') {
                    return await createMeeting(JSON.parse(body || '{}'));
                }
                break;
            case 'GET':
                if (path.startsWith('/meetings/')) {
                    const meetingId = path.split('/')[2];
                    return await getMeeting(meetingId);
                }
                break;
            case 'DELETE':
                if (path.startsWith('/meetings/')) {
                    const meetingId = path.split('/')[2];
                    return await deleteMeeting(meetingId);
                }
                break;
        }
        
        return {
            statusCode: 404,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ error: 'Not found' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};

async function createMeeting(requestBody) {
    const { externalMeetingId, mediaRegion, meetingHostId } = requestBody;
    
    const meetingRequest = {
        ClientRequestToken: uuidv4(),
        ExternalMeetingId: externalMeetingId || uuidv4(),
        MediaRegion: mediaRegion || process.env.AWS_REGION,
        MeetingHostId: meetingHostId,
        NotificationsConfiguration: {
            SnsTopicArn: process.env.SNS_TOPIC_ARN
        },
        MeetingFeatures: {
            Audio: {
                EchoReduction: 'AVAILABLE'
            },
            Video: {
                MaxResolution: 'HD'
            },
            Content: {
                MaxResolution: 'FHD'
            }
        }
    };
    
    const meeting = await chime.createMeeting(meetingRequest).promise();
    
    // Store meeting metadata in DynamoDB
    await dynamodb.put({
        TableName: process.env.MEETINGS_TABLE_NAME,
        Item: {
            MeetingId: meeting.Meeting.MeetingId,
            CreatedAt: new Date().toISOString(),
            ExternalMeetingId: meeting.Meeting.ExternalMeetingId,
            MediaRegion: meeting.Meeting.MediaRegion,
            Status: 'ACTIVE',
            MeetingHostId: meetingHostId || 'unknown'
        }
    }).promise();
    
    return {
        statusCode: 201,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Meeting: meeting.Meeting
        })
    };
}

async function getMeeting(meetingId) {
    const meeting = await chime.getMeeting({ MeetingId: meetingId }).promise();
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Meeting: meeting.Meeting
        })
    };
}

async function deleteMeeting(meetingId) {
    await chime.deleteMeeting({ MeetingId: meetingId }).promise();
    
    // Update meeting status in DynamoDB
    // First get the item to obtain the CreatedAt value
    const existingItem = await dynamodb.get({
        TableName: process.env.MEETINGS_TABLE_NAME,
        Key: { MeetingId: meetingId }
    }).promise();
    
    if (existingItem.Item) {
        await dynamodb.update({
            TableName: process.env.MEETINGS_TABLE_NAME,
            Key: { 
                MeetingId: meetingId,
                CreatedAt: existingItem.Item.CreatedAt
            },
            UpdateExpression: 'SET #status = :status, UpdatedAt = :updatedAt',
            ExpressionAttributeNames: {
                '#status': 'Status'
            },
            ExpressionAttributeValues: {
                ':status': 'DELETED',
                ':updatedAt': new Date().toISOString()
            }
        }).promise();
    }
    
    return {
        statusCode: 204,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    };
}
        '''

    def _get_attendee_handler_code(self) -> str:
        """Return the Node.js code for the attendee handler Lambda function."""
        return '''
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: `https://meetings-chime.${process.env.AWS_REGION}.amazonaws.com`
});

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    const { httpMethod, path, body } = event;
    
    try {
        switch (httpMethod) {
            case 'POST':
                if (path.includes('/attendees') && !path.includes('/attendees/')) {
                    const meetingId = path.split('/')[2];
                    return await createAttendee(meetingId, JSON.parse(body || '{}'));
                }
                break;
            case 'GET':
                if (path.includes('/attendees/')) {
                    const pathParts = path.split('/');
                    const meetingId = pathParts[2];
                    const attendeeId = pathParts[4];
                    return await getAttendee(meetingId, attendeeId);
                }
                break;
            case 'DELETE':
                if (path.includes('/attendees/')) {
                    const pathParts = path.split('/');
                    const meetingId = pathParts[2];
                    const attendeeId = pathParts[4];
                    return await deleteAttendee(meetingId, attendeeId);
                }
                break;
        }
        
        return {
            statusCode: 404,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ error: 'Not found' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            body: JSON.stringify({ error: 'Internal server error' })
        };
    }
};

async function createAttendee(meetingId, requestBody) {
    const { externalUserId, capabilities } = requestBody;
    
    const attendeeRequest = {
        MeetingId: meetingId,
        ExternalUserId: externalUserId || uuidv4(),
        Capabilities: capabilities || {
            Audio: 'SendReceive',
            Video: 'SendReceive',
            Content: 'SendReceive'
        }
    };
    
    const attendee = await chime.createAttendee(attendeeRequest).promise();
    
    return {
        statusCode: 201,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Attendee: attendee.Attendee
        })
    };
}

async function getAttendee(meetingId, attendeeId) {
    const attendee = await chime.getAttendee({
        MeetingId: meetingId,
        AttendeeId: attendeeId
    }).promise();
    
    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
            Attendee: attendee.Attendee
        })
    };
}

async function deleteAttendee(meetingId, attendeeId) {
    await chime.deleteAttendee({
        MeetingId: meetingId,
        AttendeeId: attendeeId
    }).promise();
    
    return {
        statusCode: 204,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    };
}
        '''

    def _get_event_processor_code(self) -> str:
        """Return the Node.js code for the event processor Lambda function."""
        return '''
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();

exports.handler = async (event) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    
    for (const record of event.Records) {
        try {
            const message = JSON.parse(record.body);
            const snsMessage = JSON.parse(message.Message);
            
            await processChimeEvent(snsMessage);
            
        } catch (error) {
            console.error('Error processing record:', error);
            throw error; // This will send the message to DLQ
        }
    }
    
    return { statusCode: 200 };
};

async function processChimeEvent(event) {
    const { eventType, meetingId, attendeeId, timestamp } = event;
    
    console.log(`Processing event: ${eventType} for meeting: ${meetingId}`);
    
    switch (eventType) {
        case 'chime:MeetingStarted':
            await handleMeetingStarted(meetingId, timestamp);
            break;
        case 'chime:MeetingEnded':
            await handleMeetingEnded(meetingId, timestamp);
            break;
        case 'chime:AttendeeJoined':
            await handleAttendeeJoined(meetingId, attendeeId, timestamp);
            break;
        case 'chime:AttendeeLeft':
            await handleAttendeeLeft(meetingId, attendeeId, timestamp);
            break;
        case 'chime:AttendeeDropped':
            await handleAttendeeDropped(meetingId, attendeeId, timestamp);
            break;
        default:
            console.log(`Unknown event type: ${eventType}`);
    }
}

async function handleMeetingStarted(meetingId, timestamp) {
    // Query to find the meeting item with this MeetingId
    const queryResult = await dynamodb.query({
        TableName: process.env.MEETINGS_TABLE_NAME,
        KeyConditionExpression: 'MeetingId = :meetingId',
        ExpressionAttributeValues: {
            ':meetingId': meetingId
        },
        Limit: 1
    }).promise();
    
    if (queryResult.Items && queryResult.Items.length > 0) {
        const item = queryResult.Items[0];
        await dynamodb.update({
            TableName: process.env.MEETINGS_TABLE_NAME,
            Key: { 
                MeetingId: meetingId,
                CreatedAt: item.CreatedAt
            },
            UpdateExpression: 'SET #status = :status, StartedAt = :startedAt',
            ExpressionAttributeNames: {
                '#status': 'Status'
            },
            ExpressionAttributeValues: {
                ':status': 'STARTED',
                ':startedAt': timestamp
            }
        }).promise();
    }
}

async function handleMeetingEnded(meetingId, timestamp) {
    // Query to find the meeting item with this MeetingId
    const queryResult = await dynamodb.query({
        TableName: process.env.MEETINGS_TABLE_NAME,
        KeyConditionExpression: 'MeetingId = :meetingId',
        ExpressionAttributeValues: {
            ':meetingId': meetingId
        },
        Limit: 1
    }).promise();
    
    if (queryResult.Items && queryResult.Items.length > 0) {
        const item = queryResult.Items[0];
        await dynamodb.update({
            TableName: process.env.MEETINGS_TABLE_NAME,
            Key: { 
                MeetingId: meetingId,
                CreatedAt: item.CreatedAt
            },
            UpdateExpression: 'SET #status = :status, EndedAt = :endedAt',
            ExpressionAttributeNames: {
                '#status': 'Status'
            },
            ExpressionAttributeValues: {
                ':status': 'ENDED',
                ':endedAt': timestamp
            }
        }).promise();
    }
}

async function handleAttendeeJoined(meetingId, attendeeId, timestamp) {
    // Log attendee join event
    console.log(`Attendee ${attendeeId} joined meeting ${meetingId} at ${timestamp}`);
    
    // Could store attendee events in a separate table for analytics
}

async function handleAttendeeLeft(meetingId, attendeeId, timestamp) {
    // Log attendee leave event
    console.log(`Attendee ${attendeeId} left meeting ${meetingId} at ${timestamp}`);
}

async function handleAttendeeDropped(meetingId, attendeeId, timestamp) {
    // Log attendee drop event (unexpected disconnect)
    console.log(`Attendee ${attendeeId} dropped from meeting ${meetingId} at ${timestamp}`);
}
        '''


class VideoConferencingApp(cdk.App):
    """CDK Application for Video Conferencing Solution."""
    
    def __init__(self):
        super().__init__()
        
        # Create the main stack
        VideoConferencingStack(
            self, 
            "VideoConferencingStack",
            env=cdk.Environment(
                account=os.getenv('CDK_DEFAULT_ACCOUNT'),
                region=os.getenv('CDK_DEFAULT_REGION')
            ),
            description="Amazon Chime SDK Video Conferencing Solution"
        )


# Create and run the application
if __name__ == "__main__":
    app = VideoConferencingApp()
    app.synth()