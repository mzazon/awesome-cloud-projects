#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigateway from 'aws-cdk-lib/aws-apigateway';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as path from 'path';

/**
 * Stack for Video Conferencing Solution with Amazon Chime SDK
 * 
 * This stack deploys:
 * - DynamoDB table for meeting metadata
 * - S3 bucket for recordings and artifacts
 * - SNS topic for event notifications
 * - Lambda functions for meeting and attendee management
 * - API Gateway REST API with proper routing
 * - IAM roles and policies with least privilege access
 */
export class VideoConferencingChimeSDKStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Generate unique suffix for resource names
    const uniqueSuffix = this.node.addr.substring(0, 8);
    
    // S3 bucket for storing meeting recordings and artifacts
    const recordingsBucket = new s3.Bucket(this, 'RecordingsBucket', {
      bucketName: `video-conferencing-recordings-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      enforceSSL: true,
    });

    // DynamoDB table for meeting metadata and analytics
    const meetingsTable = new dynamodb.Table(this, 'MeetingsTable', {
      tableName: `video-conferencing-meetings-${uniqueSuffix}`,
      partitionKey: {
        name: 'MeetingId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'CreatedAt',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: true,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
      // Global Secondary Index for querying by status
      globalSecondaryIndexes: [{
        indexName: 'StatusIndex',
        partitionKey: {
          name: 'Status',
          type: dynamodb.AttributeType.STRING,
        },
        sortKey: {
          name: 'CreatedAt',
          type: dynamodb.AttributeType.STRING,
        },
      }],
    });

    // SNS topic for meeting event notifications
    const eventsTopic = new sns.Topic(this, 'EventsTopic', {
      topicName: `video-conferencing-events-${uniqueSuffix}`,
      displayName: 'Video Conferencing Events',
      enforceSSL: true,
    });

    // SQS queue for processing meeting events
    const eventsQueue = new sqs.Queue(this, 'EventsQueue', {
      queueName: `video-conferencing-events-${uniqueSuffix}`,
      visibilityTimeout: cdk.Duration.seconds(300),
      encryption: sqs.QueueEncryption.SQS_MANAGED,
    });

    // Subscribe SQS queue to SNS topic
    eventsTopic.addSubscription(
      new (require('aws-cdk-lib/aws-sns-subscriptions').SqsSubscription)(eventsQueue)
    );

    // IAM role for Lambda functions with Chime SDK permissions
    const lambdaRole = new iam.Role(this, 'LambdaExecutionRole', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('service-role/AWSLambdaBasicExecutionRole'),
      ],
      inlinePolicies: {
        ChimeSDKPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'chime:CreateMeeting',
                'chime:DeleteMeeting',
                'chime:GetMeeting',
                'chime:ListMeetings',
                'chime:CreateAttendee',
                'chime:DeleteAttendee',
                'chime:GetAttendee',
                'chime:ListAttendees',
                'chime:BatchCreateAttendee',
                'chime:BatchDeleteAttendee',
                'chime:StartMeetingTranscription',
                'chime:StopMeetingTranscription',
              ],
              resources: ['*'],
            }),
          ],
        }),
        DynamoDBPolicy: new iam.PolicyDocument({
          statements: [
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
                meetingsTable.tableArn,
                `${meetingsTable.tableArn}/index/*`,
              ],
            }),
          ],
        }),
        S3Policy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                's3:PutObject',
                's3:GetObject',
                's3:DeleteObject',
                's3:PutObjectAcl',
              ],
              resources: [
                `${recordingsBucket.bucketArn}/*`,
              ],
            }),
          ],
        }),
        SNSPolicy: new iam.PolicyDocument({
          statements: [
            new iam.PolicyStatement({
              effect: iam.Effect.ALLOW,
              actions: [
                'sns:Publish',
              ],
              resources: [eventsTopic.topicArn],
            }),
          ],
        }),
      },
    });

    // Lambda function for meeting management
    const meetingHandlerFunction = new lambda.Function(this, 'MeetingHandlerFunction', {
      functionName: `video-conferencing-meeting-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: \`https://meetings-chime.\${process.env.AWS_REGION}.amazonaws.com\`
});

const dynamodb = new AWS.DynamoDB.DocumentClient();

exports.handler = async (event) => {
    const { httpMethod, path, body } = event;
    
    try {
        switch (httpMethod) {
            case 'POST':
                if (path === '/meetings') {
                    return await createMeeting(JSON.parse(body));
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
            headers: { 'Access-Control-Allow-Origin': '*' },
            body: JSON.stringify({ error: 'Not found' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: { 'Access-Control-Allow-Origin': '*' },
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
        TableName: process.env.TABLE_NAME,
        Item: {
            MeetingId: meeting.Meeting.MeetingId,
            CreatedAt: new Date().toISOString(),
            ExternalMeetingId: meeting.Meeting.ExternalMeetingId,
            MediaRegion: meeting.Meeting.MediaRegion,
            Status: 'ACTIVE'
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
    await dynamodb.update({
        TableName: process.env.TABLE_NAME,
        Key: { MeetingId: meetingId },
        UpdateExpression: 'SET #status = :status, UpdatedAt = :updatedAt',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': 'DELETED',
            ':updatedAt': new Date().toISOString()
        }
    }).promise();
    
    return {
        statusCode: 204,
        headers: {
            'Access-Control-Allow-Origin': '*'
        }
    };
}
      `),
      role: lambdaRole,
      environment: {
        TABLE_NAME: meetingsTable.tableName,
        SNS_TOPIC_ARN: eventsTopic.topicArn,
        BUCKET_NAME: recordingsBucket.bucketName,
      },
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
    });

    // Lambda function for attendee management
    const attendeeHandlerFunction = new lambda.Function(this, 'AttendeeHandlerFunction', {
      functionName: `video-conferencing-attendee-handler-${uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: \`https://meetings-chime.\${process.env.AWS_REGION}.amazonaws.com\`
});

exports.handler = async (event) => {
    const { httpMethod, path, body } = event;
    
    try {
        switch (httpMethod) {
            case 'POST':
                if (path.startsWith('/meetings/') && path.endsWith('/attendees')) {
                    const meetingId = path.split('/')[2];
                    return await createAttendee(meetingId, JSON.parse(body));
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
            headers: { 'Access-Control-Allow-Origin': '*' },
            body: JSON.stringify({ error: 'Not found' })
        };
    } catch (error) {
        console.error('Error:', error);
        return {
            statusCode: 500,
            headers: { 'Access-Control-Allow-Origin': '*' },
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
      `),
      role: lambdaRole,
      environment: {
        TABLE_NAME: meetingsTable.tableName,
        SNS_TOPIC_ARN: eventsTopic.topicArn,
        BUCKET_NAME: recordingsBucket.bucketName,
      },
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
    });

    // Lambda function for processing meeting events
    const eventProcessorFunction = new lambda.Function(this, 'EventProcessorFunction', {
      functionName: `video-conferencing-event-processor-${uniqueSuffix}`,
      runtime: lambda.Runtime.NODEJS_18_X,
      handler: 'index.handler',
      code: lambda.Code.fromInline(`
const AWS = require('aws-sdk');

const dynamodb = new AWS.DynamoDB.DocumentClient();
const s3 = new AWS.S3();

exports.handler = async (event) => {
    console.log('Processing event:', JSON.stringify(event, null, 2));
    
    for (const record of event.Records) {
        try {
            const message = JSON.parse(record.body);
            const snsMessage = JSON.parse(message.Message);
            
            // Process different event types
            switch (snsMessage.eventType) {
                case 'chime:MeetingStarted':
                    await handleMeetingStarted(snsMessage);
                    break;
                case 'chime:MeetingEnded':
                    await handleMeetingEnded(snsMessage);
                    break;
                case 'chime:AttendeeJoined':
                    await handleAttendeeJoined(snsMessage);
                    break;
                case 'chime:AttendeeLeft':
                    await handleAttendeeLeft(snsMessage);
                    break;
                default:
                    console.log('Unhandled event type:', snsMessage.eventType);
            }
        } catch (error) {
            console.error('Error processing record:', error);
        }
    }
};

async function handleMeetingStarted(event) {
    await dynamodb.update({
        TableName: process.env.TABLE_NAME,
        Key: { MeetingId: event.detail.meetingId },
        UpdateExpression: 'SET #status = :status, StartedAt = :startedAt',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': 'STARTED',
            ':startedAt': new Date().toISOString()
        }
    }).promise();
}

async function handleMeetingEnded(event) {
    await dynamodb.update({
        TableName: process.env.TABLE_NAME,
        Key: { MeetingId: event.detail.meetingId },
        UpdateExpression: 'SET #status = :status, EndedAt = :endedAt',
        ExpressionAttributeNames: {
            '#status': 'Status'
        },
        ExpressionAttributeValues: {
            ':status': 'ENDED',
            ':endedAt': new Date().toISOString()
        }
    }).promise();
}

async function handleAttendeeJoined(event) {
    console.log('Attendee joined:', event.detail.attendeeId);
    // Additional logic for attendee join events
}

async function handleAttendeeLeft(event) {
    console.log('Attendee left:', event.detail.attendeeId);
    // Additional logic for attendee leave events
}
      `),
      role: lambdaRole,
      environment: {
        TABLE_NAME: meetingsTable.tableName,
        BUCKET_NAME: recordingsBucket.bucketName,
      },
      timeout: cdk.Duration.seconds(300),
      memorySize: 512,
    });

    // Configure SQS queue to trigger event processor Lambda
    eventProcessorFunction.addEventSource(
      new (require('aws-cdk-lib/aws-lambda-event-sources').SqsEventSource)(eventsQueue, {
        batchSize: 10,
        maxBatchingWindow: cdk.Duration.seconds(5),
      })
    );

    // API Gateway REST API
    const api = new apigateway.RestApi(this, 'VideoConferencingApi', {
      restApiName: `video-conferencing-api-${uniqueSuffix}`,
      description: 'API for Video Conferencing with Amazon Chime SDK',
      deployOptions: {
        stageName: 'prod',
        throttle: {
          rateLimit: 100,
          burstLimit: 200,
        },
        loggingLevel: apigateway.MethodLoggingLevel.INFO,
        dataTraceEnabled: true,
      },
      defaultCorsPreflightOptions: {
        allowOrigins: apigateway.Cors.ALL_ORIGINS,
        allowMethods: apigateway.Cors.ALL_METHODS,
        allowHeaders: ['Content-Type', 'X-Amz-Date', 'Authorization', 'X-Api-Key'],
      },
    });

    // Create API Gateway integrations
    const meetingIntegration = new apigateway.LambdaIntegration(meetingHandlerFunction, {
      proxy: true,
    });

    const attendeeIntegration = new apigateway.LambdaIntegration(attendeeHandlerFunction, {
      proxy: true,
    });

    // Create API resources and methods
    const meetingsResource = api.root.addResource('meetings');
    
    // POST /meetings - Create meeting
    meetingsResource.addMethod('POST', meetingIntegration);
    
    // GET /meetings/{meetingId} - Get meeting details
    const meetingResource = meetingsResource.addResource('{meetingId}');
    meetingResource.addMethod('GET', meetingIntegration);
    
    // DELETE /meetings/{meetingId} - Delete meeting
    meetingResource.addMethod('DELETE', meetingIntegration);
    
    // POST /meetings/{meetingId}/attendees - Create attendee
    const attendeesResource = meetingResource.addResource('attendees');
    attendeesResource.addMethod('POST', attendeeIntegration);
    
    // GET /meetings/{meetingId}/attendees/{attendeeId} - Get attendee details
    const attendeeResource = attendeesResource.addResource('{attendeeId}');
    attendeeResource.addMethod('GET', attendeeIntegration);
    
    // DELETE /meetings/{meetingId}/attendees/{attendeeId} - Delete attendee
    attendeeResource.addMethod('DELETE', attendeeIntegration);

    // CloudWatch Log Group for API Gateway
    const apiLogGroup = new (require('aws-cdk-lib/aws-logs').LogGroup)(this, 'ApiGatewayLogGroup', {
      logGroupName: `/aws/apigateway/video-conferencing-api-${uniqueSuffix}`,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // Outputs
    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: api.url,
      description: 'API Gateway endpoint URL',
      exportName: `${this.stackName}-ApiEndpoint`,
    });

    new cdk.CfnOutput(this, 'MeetingsTableName', {
      value: meetingsTable.tableName,
      description: 'DynamoDB table name for meetings',
      exportName: `${this.stackName}-MeetingsTableName`,
    });

    new cdk.CfnOutput(this, 'RecordingsBucketName', {
      value: recordingsBucket.bucketName,
      description: 'S3 bucket name for recordings',
      exportName: `${this.stackName}-RecordingsBucketName`,
    });

    new cdk.CfnOutput(this, 'EventsTopicArn', {
      value: eventsTopic.topicArn,
      description: 'SNS topic ARN for events',
      exportName: `${this.stackName}-EventsTopicArn`,
    });

    new cdk.CfnOutput(this, 'MeetingHandlerFunctionArn', {
      value: meetingHandlerFunction.functionArn,
      description: 'Meeting handler Lambda function ARN',
      exportName: `${this.stackName}-MeetingHandlerFunctionArn`,
    });

    new cdk.CfnOutput(this, 'AttendeeHandlerFunctionArn', {
      value: attendeeHandlerFunction.functionArn,
      description: 'Attendee handler Lambda function ARN',
      exportName: `${this.stackName}-AttendeeHandlerFunctionArn`,
    });

    // Add tags to all resources
    cdk.Tags.of(this).add('Application', 'VideoConferencing');
    cdk.Tags.of(this).add('Service', 'ChimeSDK');
    cdk.Tags.of(this).add('Environment', 'Production');
    cdk.Tags.of(this).add('CostCenter', 'Engineering');
  }
}

// Create the CDK app
const app = new cdk.App();
new VideoConferencingChimeSDKStack(app, 'VideoConferencingChimeSDKStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: process.env.CDK_DEFAULT_REGION,
  },
  description: 'Video Conferencing Solution with Amazon Chime SDK - CDK TypeScript Implementation',
});