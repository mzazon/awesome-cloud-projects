/**
 * Meeting Management Lambda Function for Amazon Chime SDK
 * This function handles creating, retrieving, and deleting Chime SDK meetings
 * 
 * Environment Variables:
 * - TABLE_NAME: DynamoDB table name for storing meeting metadata
 * - SNS_TOPIC_ARN: SNS topic ARN for meeting event notifications
 * - AWS_REGION: AWS region for Chime SDK service
 */

const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Initialize AWS services
const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: `https://meetings-chime.$${process.env.AWS_REGION}.amazonaws.com`
});

const dynamodb = new AWS.DynamoDB.DocumentClient();

/**
 * Main Lambda handler function
 * Routes HTTP requests to appropriate handler functions based on method and path
 */
exports.handler = async (event) => {
    console.log('Received event:', JSON.stringify(event, null, 2));
    
    const { httpMethod, path, body, pathParameters } = event;
    
    // Add CORS headers to all responses
    const corsHeaders = {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, X-Amz-Date, Authorization, X-Api-Key, X-Amz-Security-Token'
    };
    
    try {
        let response;
        
        switch (httpMethod) {
            case 'OPTIONS':
                // Handle CORS preflight requests
                response = {
                    statusCode: 200,
                    headers: corsHeaders,
                    body: JSON.stringify({ message: 'CORS preflight successful' })
                };
                break;
                
            case 'POST':
                if (path === '/meetings') {
                    response = await createMeeting(JSON.parse(body || '{}'));
                } else {
                    response = createErrorResponse(404, 'Not found', corsHeaders);
                }
                break;
                
            case 'GET':
                if (path.startsWith('/meetings/') && pathParameters && pathParameters.meetingId) {
                    response = await getMeeting(pathParameters.meetingId);
                } else {
                    response = createErrorResponse(404, 'Not found', corsHeaders);
                }
                break;
                
            case 'DELETE':
                if (path.startsWith('/meetings/') && pathParameters && pathParameters.meetingId) {
                    response = await deleteMeeting(pathParameters.meetingId);
                } else {
                    response = createErrorResponse(404, 'Not found', corsHeaders);
                }
                break;
                
            default:
                response = createErrorResponse(405, 'Method not allowed', corsHeaders);
        }
        
        // Ensure CORS headers are present in all responses
        response.headers = { ...response.headers, ...corsHeaders };
        return response;
        
    } catch (error) {
        console.error('Error processing request:', error);
        return createErrorResponse(500, 'Internal server error', corsHeaders, error.message);
    }
};

/**
 * Creates a new Chime SDK meeting
 * @param {Object} requestBody - Request body containing meeting parameters
 * @returns {Object} HTTP response with meeting details
 */
async function createMeeting(requestBody) {
    console.log('Creating meeting with request:', requestBody);
    
    const { 
        externalMeetingId, 
        mediaRegion, 
        meetingHostId,
        enableNotifications = true 
    } = requestBody;
    
    // Generate unique identifiers
    const clientRequestToken = uuidv4();
    const finalExternalMeetingId = externalMeetingId || `meeting-$${Date.now()}-$${clientRequestToken.substring(0, 8)}`;
    
    // Configure meeting request
    const meetingRequest = {
        ClientRequestToken: clientRequestToken,
        ExternalMeetingId: finalExternalMeetingId,
        MediaRegion: mediaRegion || process.env.AWS_REGION || 'us-east-1',
        MeetingHostId: meetingHostId,
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
    
    // Add notifications configuration if enabled and SNS topic is available
    if (enableNotifications && process.env.SNS_TOPIC_ARN) {
        meetingRequest.NotificationsConfiguration = {
            SnsTopicArn: process.env.SNS_TOPIC_ARN
        };
    }
    
    try {
        // Create meeting with Chime SDK
        console.log('Calling Chime SDK createMeeting with:', JSON.stringify(meetingRequest, null, 2));
        const meetingResponse = await chime.createMeeting(meetingRequest).promise();
        
        // Store meeting metadata in DynamoDB
        const meetingMetadata = {
            MeetingId: meetingResponse.Meeting.MeetingId,
            CreatedAt: new Date().toISOString(),
            ExternalMeetingId: meetingResponse.Meeting.ExternalMeetingId,
            MediaRegion: meetingResponse.Meeting.MediaRegion,
            Status: 'ACTIVE',
            MeetingHostId: meetingHostId || null,
            CreatedBy: 'ChimeSDK-Lambda',
            TTL: Math.floor(Date.now() / 1000) + (24 * 60 * 60) // 24 hours TTL
        };
        
        console.log('Storing meeting metadata in DynamoDB:', meetingMetadata);
        await dynamodb.put({
            TableName: process.env.TABLE_NAME,
            Item: meetingMetadata,
            ConditionExpression: 'attribute_not_exists(MeetingId)' // Prevent duplicate meetings
        }).promise();
        
        console.log('Meeting created successfully:', meetingResponse.Meeting.MeetingId);
        
        return {
            statusCode: 201,
            body: JSON.stringify({
                Meeting: meetingResponse.Meeting,
                Metadata: {
                    ExternalMeetingId: finalExternalMeetingId,
                    CreatedAt: meetingMetadata.CreatedAt,
                    Status: meetingMetadata.Status
                }
            })
        };
        
    } catch (error) {
        console.error('Error creating meeting:', error);
        
        if (error.code === 'ConditionalCheckFailedException') {
            return createErrorResponse(409, 'Meeting already exists');
        }
        
        throw error;
    }
}

/**
 * Retrieves an existing Chime SDK meeting
 * @param {string} meetingId - The meeting ID to retrieve
 * @returns {Object} HTTP response with meeting details
 */
async function getMeeting(meetingId) {
    console.log('Getting meeting:', meetingId);
    
    try {
        // Get meeting from Chime SDK
        const meetingResponse = await chime.getMeeting({ 
            MeetingId: meetingId 
        }).promise();
        
        // Get meeting metadata from DynamoDB
        let metadata = null;
        try {
            const dbResponse = await dynamodb.get({
                TableName: process.env.TABLE_NAME,
                Key: { MeetingId: meetingId }
            }).promise();
            metadata = dbResponse.Item;
        } catch (dbError) {
            console.warn('Could not retrieve meeting metadata from DynamoDB:', dbError);
        }
        
        console.log('Meeting retrieved successfully:', meetingId);
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                Meeting: meetingResponse.Meeting,
                Metadata: metadata
            })
        };
        
    } catch (error) {
        console.error('Error getting meeting:', error);
        
        if (error.code === 'NotFoundException') {
            return createErrorResponse(404, 'Meeting not found');
        }
        
        throw error;
    }
}

/**
 * Deletes an existing Chime SDK meeting
 * @param {string} meetingId - The meeting ID to delete
 * @returns {Object} HTTP response confirming deletion
 */
async function deleteMeeting(meetingId) {
    console.log('Deleting meeting:', meetingId);
    
    try {
        // Delete meeting from Chime SDK
        await chime.deleteMeeting({ 
            MeetingId: meetingId 
        }).promise();
        
        // Update meeting status in DynamoDB
        try {
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
                },
                ConditionExpression: 'attribute_exists(MeetingId)' // Only update if meeting exists
            }).promise();
        } catch (dbError) {
            console.warn('Could not update meeting status in DynamoDB:', dbError);
            // Continue with deletion even if DynamoDB update fails
        }
        
        console.log('Meeting deleted successfully:', meetingId);
        
        return {
            statusCode: 204,
            body: JSON.stringify({ 
                message: 'Meeting deleted successfully',
                meetingId: meetingId 
            })
        };
        
    } catch (error) {
        console.error('Error deleting meeting:', error);
        
        if (error.code === 'NotFoundException') {
            return createErrorResponse(404, 'Meeting not found');
        }
        
        throw error;
    }
}

/**
 * Creates a standardized error response
 * @param {number} statusCode - HTTP status code
 * @param {string} message - Error message
 * @param {Object} headers - Additional headers (optional)
 * @param {string} details - Additional error details (optional)
 * @returns {Object} HTTP error response
 */
function createErrorResponse(statusCode, message, headers = {}, details = null) {
    const errorBody = {
        error: message,
        statusCode: statusCode,
        timestamp: new Date().toISOString()
    };
    
    if (details) {
        errorBody.details = details;
    }
    
    return {
        statusCode: statusCode,
        headers: headers,
        body: JSON.stringify(errorBody)
    };
}