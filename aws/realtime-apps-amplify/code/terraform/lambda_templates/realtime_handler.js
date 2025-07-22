/**
 * AWS Lambda function for handling real-time operations
 * This function processes real-time events like typing indicators, 
 * presence updates, and room management for the chat application
 */

const AWS = require('aws-sdk');

// Initialize AWS services
const dynamodb = new AWS.DynamoDB.DocumentClient();

// Environment variables
const CHAT_ROOMS_TABLE = '${chat_rooms_table}';
const MESSAGES_TABLE = '${messages_table}';
const REACTIONS_TABLE = '${reactions_table}';
const USER_PRESENCE_TABLE = '${user_presence_table}';
const NOTIFICATIONS_TABLE = '${notifications_table}';
const REGION = '${region}';

/**
 * Main Lambda handler function
 * @param {Object} event - The AppSync event containing field, source, arguments, and identity
 * @param {Object} context - The Lambda context object
 * @returns {Object} - The response object
 */
exports.handler = async (event, context) => {
    console.log('Real-time event received:', JSON.stringify(event, null, 2));
    
    const { field, source, arguments: args, identity } = event;
    
    // Extract user information from Cognito identity
    const userId = identity.claims.sub;
    const userName = identity.claims['cognito:username'] || identity.claims.email;
    
    try {
        switch (field) {
            case 'startTyping':
                return await handleTypingStart(args.chatRoomId, userId, userName);
            
            case 'stopTyping':
                return await handleTypingStop(args.chatRoomId, userId, userName);
            
            case 'updatePresence':
                return await updateUserPresence(userId, userName, args.status, args.currentRoom);
            
            case 'joinRoom':
                return await joinChatRoom(args.roomId, userId, userName);
            
            case 'leaveRoom':
                return await leaveChatRoom(args.roomId, userId, userName);
            
            default:
                throw new Error(`Unknown field: $${field}`);
        }
    } catch (error) {
        console.error('Error processing real-time operation:', error);
        throw new Error(`Failed to process $${field}: $${error.message}`);
    }
};

/**
 * Handle typing start event
 * @param {string} chatRoomId - The ID of the chat room
 * @param {string} userId - The user ID
 * @param {string} userName - The username
 * @returns {Object} - Typing indicator object
 */
async function handleTypingStart(chatRoomId, userId, userName) {
    const typingIndicator = {
        userId,
        userName,
        chatRoomId,
        timestamp: new Date().toISOString()
    };
    
    console.log('User started typing:', typingIndicator);
    
    // In a real implementation, you would publish this to subscriptions
    // For now, we'll just return the typing indicator
    return typingIndicator;
}

/**
 * Handle typing stop event
 * @param {string} chatRoomId - The ID of the chat room
 * @param {string} userId - The user ID
 * @param {string} userName - The username
 * @returns {Object} - Typing indicator object
 */
async function handleTypingStop(chatRoomId, userId, userName) {
    const typingIndicator = {
        userId,
        userName,
        chatRoomId,
        timestamp: new Date().toISOString()
    };
    
    console.log('User stopped typing:', typingIndicator);
    
    return typingIndicator;
}

/**
 * Update user presence status
 * @param {string} userId - The user ID
 * @param {string} userName - The username
 * @param {string} status - The presence status (ONLINE, AWAY, BUSY, OFFLINE)
 * @param {string} currentRoom - The current room (optional)
 * @returns {Object} - Updated presence object
 */
async function updateUserPresence(userId, userName, status, currentRoom) {
    const now = new Date().toISOString();
    const ttl = Math.floor(Date.now() / 1000) + (24 * 60 * 60); // 24 hours TTL
    
    const presence = {
        id: userId,
        userId,
        userName,
        status,
        lastSeen: now,
        currentRoom: currentRoom || null,
        deviceInfo: 'Web',
        ttl,
        createdAt: now,
        updatedAt: now
    };
    
    try {
        // Update presence in DynamoDB
        await dynamodb.put({
            TableName: USER_PRESENCE_TABLE,
            Item: presence
        }).promise();
        
        console.log('Updated user presence:', presence);
        return presence;
    } catch (error) {
        console.error('Error updating user presence:', error);
        throw error;
    }
}

/**
 * Join a chat room
 * @param {string} roomId - The room ID to join
 * @param {string} userId - The user ID
 * @param {string} userName - The username
 * @returns {Object} - Updated chat room object
 */
async function joinChatRoom(roomId, userId, userName) {
    const now = new Date().toISOString();
    
    try {
        // Add user to room members list
        await dynamodb.update({
            TableName: CHAT_ROOMS_TABLE,
            Key: { id: roomId },
            UpdateExpression: 'ADD members :userId SET lastActivity = :timestamp',
            ExpressionAttributeValues: {
                ':userId': dynamodb.createSet([userId]),
                ':timestamp': now
            }
        }).promise();
        
        // Update user presence to show current room
        await updateUserPresence(userId, userName, 'ONLINE', roomId);
        
        // Get updated room data
        const roomResponse = await dynamodb.get({
            TableName: CHAT_ROOMS_TABLE,
            Key: { id: roomId }
        }).promise();
        
        console.log('User joined room:', { roomId, userId, userName });
        return roomResponse.Item;
    } catch (error) {
        console.error('Error joining chat room:', error);
        throw error;
    }
}

/**
 * Leave a chat room
 * @param {string} roomId - The room ID to leave
 * @param {string} userId - The user ID
 * @param {string} userName - The username
 * @returns {Object} - Updated chat room object
 */
async function leaveChatRoom(roomId, userId, userName) {
    const now = new Date().toISOString();
    
    try {
        // Remove user from room members list
        await dynamodb.update({
            TableName: CHAT_ROOMS_TABLE,
            Key: { id: roomId },
            UpdateExpression: 'DELETE members :userId SET lastActivity = :timestamp',
            ExpressionAttributeValues: {
                ':userId': dynamodb.createSet([userId]),
                ':timestamp': now
            }
        }).promise();
        
        // Update user presence to clear current room
        await updateUserPresence(userId, userName, 'ONLINE', null);
        
        // Get updated room data
        const roomResponse = await dynamodb.get({
            TableName: CHAT_ROOMS_TABLE,
            Key: { id: roomId }
        }).promise();
        
        console.log('User left room:', { roomId, userId, userName });
        return roomResponse.Item;
    } catch (error) {
        console.error('Error leaving chat room:', error);
        throw error;
    }
}

/**
 * Create a notification for a user
 * @param {string} userId - The user ID to notify
 * @param {string} type - The notification type
 * @param {string} title - The notification title
 * @param {string} message - The notification message
 * @param {string} relatedId - Related object ID (optional)
 * @returns {Object} - Created notification object
 */
async function createNotification(userId, type, title, message, relatedId = null) {
    const now = new Date().toISOString();
    const notificationId = `notification-$${Date.now()}-$${Math.random().toString(36).substr(2, 9)}`;
    
    const notification = {
        id: notificationId,
        type,
        title,
        message,
        userId,
        isRead: false,
        relatedId,
        actionUrl: null,
        createdAt: now,
        updatedAt: now
    };
    
    try {
        await dynamodb.put({
            TableName: NOTIFICATIONS_TABLE,
            Item: notification
        }).promise();
        
        console.log('Created notification:', notification);
        return notification;
    } catch (error) {
        console.error('Error creating notification:', error);
        throw error;
    }
}

/**
 * Get active users in a chat room
 * @param {string} roomId - The room ID
 * @returns {Array} - List of active users
 */
async function getActiveUsersInRoom(roomId) {
    try {
        const response = await dynamodb.query({
            TableName: USER_PRESENCE_TABLE,
            IndexName: 'byUser',
            KeyConditionExpression: 'currentRoom = :roomId',
            FilterExpression: '#status IN (:online, :away, :busy)',
            ExpressionAttributeNames: {
                '#status': 'status'
            },
            ExpressionAttributeValues: {
                ':roomId': roomId,
                ':online': 'ONLINE',
                ':away': 'AWAY',
                ':busy': 'BUSY'
            }
        }).promise();
        
        return response.Items || [];
    } catch (error) {
        console.error('Error getting active users:', error);
        return [];
    }
}

/**
 * Utility function to generate unique IDs
 * @param {string} prefix - Prefix for the ID
 * @returns {string} - Unique ID
 */
function generateUniqueId(prefix = 'id') {
    return `$${prefix}-$${Date.now()}-$${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * Utility function to validate required parameters
 * @param {Object} params - Parameters to validate
 * @param {Array} required - Required parameter names
 * @throws {Error} - If required parameters are missing
 */
function validateRequiredParams(params, required) {
    for (const param of required) {
        if (!params[param]) {
            throw new Error(`Missing required parameter: $${param}`);
        }
    }
}

/**
 * Utility function to sanitize user input
 * @param {string} input - Input to sanitize
 * @returns {string} - Sanitized input
 */
function sanitizeInput(input) {
    if (typeof input !== 'string') {
        return input;
    }
    
    // Remove potential XSS and injection attacks
    return input
        .replace(/[<>]/g, '') // Remove HTML tags
        .replace(/['";]/g, '') // Remove quotes and semicolons
        .trim()
        .substring(0, 1000); // Limit length
}