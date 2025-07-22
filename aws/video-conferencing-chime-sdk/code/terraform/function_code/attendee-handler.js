/**
 * Attendee Management Lambda Function for Amazon Chime SDK
 * This function handles creating, retrieving, and deleting Chime SDK meeting attendees
 * 
 * Environment Variables:
 * - AWS_REGION: AWS region for Chime SDK service
 */

const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Initialize AWS services
const chime = new AWS.ChimeSDKMeetings({
    region: process.env.AWS_REGION,
    endpoint: `https://meetings-chime.${process.env.AWS_REGION}.amazonaws.com`
});

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
                if (path.includes('/attendees') && pathParameters && pathParameters.meetingId) {
                    response = await createAttendee(pathParameters.meetingId, JSON.parse(body || '{}'));
                } else {
                    response = createErrorResponse(404, 'Not found', corsHeaders);
                }
                break;
                
            case 'GET':
                if (path.includes('/attendees/') && pathParameters && pathParameters.meetingId && pathParameters.attendeeId) {
                    response = await getAttendee(pathParameters.meetingId, pathParameters.attendeeId);
                } else {
                    response = createErrorResponse(404, 'Not found', corsHeaders);
                }
                break;
                
            case 'DELETE':
                if (path.includes('/attendees/') && pathParameters && pathParameters.meetingId && pathParameters.attendeeId) {
                    response = await deleteAttendee(pathParameters.meetingId, pathParameters.attendeeId);
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
 * Creates a new attendee for a Chime SDK meeting
 * @param {string} meetingId - The meeting ID to add the attendee to
 * @param {Object} requestBody - Request body containing attendee parameters
 * @returns {Object} HTTP response with attendee details
 */
async function createAttendee(meetingId, requestBody) {
    console.log('Creating attendee for meeting:', meetingId, 'with request:', requestBody);
    
    const { 
        externalUserId, 
        capabilities = {
            Audio: 'SendReceive',
            Video: 'SendReceive',
            Content: 'SendReceive'
        }
    } = requestBody;
    
    // Generate unique external user ID if not provided
    const finalExternalUserId = externalUserId || `user-${Date.now()}-${uuidv4().substring(0, 8)}`;
    
    // Configure attendee request
    const attendeeRequest = {
        MeetingId: meetingId,
        ExternalUserId: finalExternalUserId,
        Capabilities: capabilities
    };
    
    // Validate capabilities
    const validCapabilities = ['SendReceive', 'Send', 'Receive', 'None'];
    const capabilityTypes = ['Audio', 'Video', 'Content'];
    
    for (const capType of capabilityTypes) {
        if (capabilities[capType] && !validCapabilities.includes(capabilities[capType])) {
            return createErrorResponse(400, `Invalid ${capType} capability: ${capabilities[capType]}. Must be one of: ${validCapabilities.join(', ')}`);
        }
    }
    
    try {
        // Create attendee with Chime SDK
        console.log('Calling Chime SDK createAttendee with:', JSON.stringify(attendeeRequest, null, 2));
        const attendeeResponse = await chime.createAttendee(attendeeRequest).promise();
        
        console.log('Attendee created successfully:', attendeeResponse.Attendee.AttendeeId);
        
        return {
            statusCode: 201,
            body: JSON.stringify({
                Attendee: attendeeResponse.Attendee,
                Metadata: {
                    ExternalUserId: finalExternalUserId,
                    CreatedAt: new Date().toISOString(),
                    Capabilities: capabilities
                }
            })
        };
        
    } catch (error) {
        console.error('Error creating attendee:', error);
        
        if (error.code === 'NotFoundException') {
            return createErrorResponse(404, 'Meeting not found');
        }
        
        if (error.code === 'LimitExceededException') {
            return createErrorResponse(429, 'Meeting attendee limit exceeded');
        }
        
        if (error.code === 'BadRequestException') {
            return createErrorResponse(400, 'Invalid request parameters');
        }
        
        throw error;
    }
}

/**
 * Retrieves an existing attendee from a Chime SDK meeting
 * @param {string} meetingId - The meeting ID
 * @param {string} attendeeId - The attendee ID to retrieve
 * @returns {Object} HTTP response with attendee details
 */
async function getAttendee(meetingId, attendeeId) {
    console.log('Getting attendee:', attendeeId, 'from meeting:', meetingId);
    
    try {
        // Get attendee from Chime SDK
        const attendeeResponse = await chime.getAttendee({
            MeetingId: meetingId,
            AttendeeId: attendeeId
        }).promise();
        
        console.log('Attendee retrieved successfully:', attendeeId);
        
        return {
            statusCode: 200,
            body: JSON.stringify({
                Attendee: attendeeResponse.Attendee,
                Metadata: {
                    RetrievedAt: new Date().toISOString()
                }
            })
        };
        
    } catch (error) {
        console.error('Error getting attendee:', error);
        
        if (error.code === 'NotFoundException') {
            return createErrorResponse(404, 'Attendee or meeting not found');
        }
        
        throw error;
    }
}

/**
 * Deletes an attendee from a Chime SDK meeting
 * @param {string} meetingId - The meeting ID
 * @param {string} attendeeId - The attendee ID to delete
 * @returns {Object} HTTP response confirming deletion
 */
async function deleteAttendee(meetingId, attendeeId) {
    console.log('Deleting attendee:', attendeeId, 'from meeting:', meetingId);
    
    try {
        // Delete attendee from Chime SDK
        await chime.deleteAttendee({
            MeetingId: meetingId,
            AttendeeId: attendeeId
        }).promise();
        
        console.log('Attendee deleted successfully:', attendeeId);
        
        return {
            statusCode: 204,
            body: JSON.stringify({
                message: 'Attendee deleted successfully',
                meetingId: meetingId,
                attendeeId: attendeeId,
                deletedAt: new Date().toISOString()
            })
        };
        
    } catch (error) {
        console.error('Error deleting attendee:', error);
        
        if (error.code === 'NotFoundException') {
            return createErrorResponse(404, 'Attendee or meeting not found');
        }
        
        throw error;
    }
}

/**
 * Batch creates multiple attendees for a meeting (helper function for future use)
 * @param {string} meetingId - The meeting ID
 * @param {Array} attendeeRequests - Array of attendee request objects
 * @returns {Object} HTTP response with batch creation results
 */
async function batchCreateAttendees(meetingId, attendeeRequests) {
    console.log('Batch creating attendees for meeting:', meetingId);
    
    // Validate input
    if (!Array.isArray(attendeeRequests) || attendeeRequests.length === 0) {
        return createErrorResponse(400, 'attendeeRequests must be a non-empty array');
    }
    
    if (attendeeRequests.length > 100) {
        return createErrorResponse(400, 'Cannot create more than 100 attendees in a single batch');
    }
    
    try {
        // Prepare attendee requests for batch creation
        const batchRequest = {
            MeetingId: meetingId,
            Attendees: attendeeRequests.map(request => ({
                ExternalUserId: request.externalUserId || `user-${Date.now()}-${uuidv4().substring(0, 8)}`,
                Capabilities: request.capabilities || {
                    Audio: 'SendReceive',
                    Video: 'SendReceive',
                    Content: 'SendReceive'
                }
            }))
        };
        
        // Call Chime SDK batch create attendees
        const batchResponse = await chime.batchCreateAttendee(batchRequest).promise();
        
        console.log('Batch attendee creation completed. Created:', batchResponse.Attendees?.length, 'Failed:', batchResponse.Errors?.length);
        
        return {
            statusCode: 201,
            body: JSON.stringify({
                Attendees: batchResponse.Attendees || [],
                Errors: batchResponse.Errors || [],
                Summary: {
                    Requested: attendeeRequests.length,
                    Created: batchResponse.Attendees?.length || 0,
                    Failed: batchResponse.Errors?.length || 0
                }
            })
        };
        
    } catch (error) {
        console.error('Error batch creating attendees:', error);
        
        if (error.code === 'NotFoundException') {
            return createErrorResponse(404, 'Meeting not found');
        }
        
        if (error.code === 'LimitExceededException') {
            return createErrorResponse(429, 'Meeting attendee limit exceeded');
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