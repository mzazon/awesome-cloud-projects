// Lambda function for Todo API backend
// This function handles CRUD operations for the Todo application

const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Initialize DynamoDB DocumentClient
const dynamodb = new AWS.DynamoDB.DocumentClient();

// Get table name from environment variable
const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || '${table_name}';

// CORS headers for all responses
const CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': process.env.CORS_ORIGIN || '*',
    'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS'
};

/**
 * Main Lambda handler function
 * @param {Object} event - API Gateway event object
 * @param {Object} context - Lambda context object
 * @returns {Object} - API Gateway response object
 */
exports.handler = async (event, context) => {
    console.log('Event:', JSON.stringify(event, null, 2));
    console.log('Context:', JSON.stringify(context, null, 2));

    try {
        // Extract HTTP method and path from event
        const { httpMethod, path, pathParameters, body, queryStringParameters } = event;
        
        // Route requests based on HTTP method and path
        switch (httpMethod) {
            case 'GET':
                if (pathParameters && pathParameters.id) {
                    return await getTodoById(pathParameters.id);
                } else {
                    return await getAllTodos(queryStringParameters);
                }
                
            case 'POST':
                return await createTodo(JSON.parse(body || '{}'));
                
            case 'PUT':
                if (pathParameters && pathParameters.id) {
                    return await updateTodo(pathParameters.id, JSON.parse(body || '{}'));
                } else {
                    return createErrorResponse(400, 'Todo ID is required for PUT requests');
                }
                
            case 'DELETE':
                if (pathParameters && pathParameters.id) {
                    return await deleteTodo(pathParameters.id);
                } else {
                    return createErrorResponse(400, 'Todo ID is required for DELETE requests');
                }
                
            case 'OPTIONS':
                return createResponse(200, { message: 'CORS preflight' });
                
            default:
                return createErrorResponse(405, `Method ${httpMethod} not allowed`);
        }
    } catch (error) {
        console.error('Error processing request:', error);
        return createErrorResponse(500, 'Internal server error', error.message);
    }
};

/**
 * Get all todos with optional filtering and pagination
 * @param {Object} queryParams - Query string parameters
 * @returns {Object} - API response with todos list
 */
async function getAllTodos(queryParams = {}) {
    try {
        console.log('Getting all todos with params:', queryParams);
        
        const params = {
            TableName: TABLE_NAME
        };
        
        // Add pagination if provided
        if (queryParams && queryParams.lastKey) {
            params.ExclusiveStartKey = JSON.parse(decodeURIComponent(queryParams.lastKey));
        }
        
        // Add limit if provided
        if (queryParams && queryParams.limit) {
            params.Limit = parseInt(queryParams.limit);
        }
        
        const result = await dynamodb.scan(params).promise();
        
        // Sort todos by creation date (newest first)
        const sortedTodos = result.Items.sort((a, b) => 
            new Date(b.createdAt) - new Date(a.createdAt)
        );
        
        const response = {
            todos: sortedTodos,
            count: sortedTodos.length,
            totalCount: result.Count
        };
        
        // Include pagination token if there are more items
        if (result.LastEvaluatedKey) {
            response.nextKey = encodeURIComponent(JSON.stringify(result.LastEvaluatedKey));
        }
        
        console.log(`Successfully retrieved ${sortedTodos.length} todos`);
        return createResponse(200, response);
        
    } catch (error) {
        console.error('Error getting todos:', error);
        return createErrorResponse(500, 'Failed to retrieve todos', error.message);
    }
}

/**
 * Get a specific todo by ID
 * @param {string} todoId - Todo ID
 * @returns {Object} - API response with todo item
 */
async function getTodoById(todoId) {
    try {
        console.log('Getting todo by ID:', todoId);
        
        const params = {
            TableName: TABLE_NAME,
            Key: { id: todoId }
        };
        
        const result = await dynamodb.get(params).promise();
        
        if (!result.Item) {
            return createErrorResponse(404, 'Todo not found');
        }
        
        console.log('Successfully retrieved todo:', result.Item.id);
        return createResponse(200, result.Item);
        
    } catch (error) {
        console.error('Error getting todo by ID:', error);
        return createErrorResponse(500, 'Failed to retrieve todo', error.message);
    }
}

/**
 * Create a new todo item
 * @param {Object} todoData - Todo data from request body
 * @returns {Object} - API response with created todo
 */
async function createTodo(todoData) {
    try {
        console.log('Creating new todo:', todoData);
        
        // Validate required fields
        if (!todoData.title || typeof todoData.title !== 'string') {
            return createErrorResponse(400, 'Title is required and must be a string');
        }
        
        // Create new todo item with generated ID and timestamp
        const todo = {
            id: uuidv4(),
            title: todoData.title.trim(),
            completed: Boolean(todoData.completed),
            createdAt: new Date().toISOString(),
            updatedAt: new Date().toISOString(),
            // Add optional fields if provided
            ...(todoData.description && { description: todoData.description.trim() }),
            ...(todoData.priority && { priority: todoData.priority }),
            ...(todoData.dueDate && { dueDate: todoData.dueDate })
        };
        
        const params = {
            TableName: TABLE_NAME,
            Item: todo,
            // Ensure we don't overwrite existing items
            ConditionExpression: 'attribute_not_exists(id)'
        };
        
        await dynamodb.put(params).promise();
        
        console.log('Successfully created todo:', todo.id);
        return createResponse(201, todo);
        
    } catch (error) {
        console.error('Error creating todo:', error);
        if (error.code === 'ConditionalCheckFailedException') {
            return createErrorResponse(409, 'Todo with this ID already exists');
        }
        return createErrorResponse(500, 'Failed to create todo', error.message);
    }
}

/**
 * Update an existing todo item
 * @param {string} todoId - Todo ID to update
 * @param {Object} updateData - Updated todo data
 * @returns {Object} - API response with updated todo
 */
async function updateTodo(todoId, updateData) {
    try {
        console.log('Updating todo:', todoId, updateData);
        
        // First, check if the todo exists
        const getParams = {
            TableName: TABLE_NAME,
            Key: { id: todoId }
        };
        
        const existingTodo = await dynamodb.get(getParams).promise();
        if (!existingTodo.Item) {
            return createErrorResponse(404, 'Todo not found');
        }
        
        // Build update expression dynamically
        const updateExpressions = [];
        const expressionAttributeNames = {};
        const expressionAttributeValues = {};
        
        // Update allowed fields
        const allowedFields = ['title', 'completed', 'description', 'priority', 'dueDate'];
        
        allowedFields.forEach(field => {
            if (updateData.hasOwnProperty(field)) {
                const attrName = `#${field}`;
                const attrValue = `:${field}`;
                
                updateExpressions.push(`${attrName} = ${attrValue}`);
                expressionAttributeNames[attrName] = field;
                
                // Validate and process field values
                switch (field) {
                    case 'title':
                        if (typeof updateData[field] !== 'string' || !updateData[field].trim()) {
                            return createErrorResponse(400, 'Title must be a non-empty string');
                        }
                        expressionAttributeValues[attrValue] = updateData[field].trim();
                        break;
                    case 'completed':
                        expressionAttributeValues[attrValue] = Boolean(updateData[field]);
                        break;
                    default:
                        expressionAttributeValues[attrValue] = updateData[field];
                }
            }
        });
        
        // Always update the updatedAt timestamp
        updateExpressions.push('#updatedAt = :updatedAt');
        expressionAttributeNames['#updatedAt'] = 'updatedAt';
        expressionAttributeValues[':updatedAt'] = new Date().toISOString();
        
        if (updateExpressions.length === 1) { // Only updatedAt
            return createErrorResponse(400, 'No valid fields to update');
        }
        
        const updateParams = {
            TableName: TABLE_NAME,
            Key: { id: todoId },
            UpdateExpression: `SET ${updateExpressions.join(', ')}`,
            ExpressionAttributeNames: expressionAttributeNames,
            ExpressionAttributeValues: expressionAttributeValues,
            ReturnValues: 'ALL_NEW'
        };
        
        const result = await dynamodb.update(updateParams).promise();
        
        console.log('Successfully updated todo:', todoId);
        return createResponse(200, result.Attributes);
        
    } catch (error) {
        console.error('Error updating todo:', error);
        return createErrorResponse(500, 'Failed to update todo', error.message);
    }
}

/**
 * Delete a todo item
 * @param {string} todoId - Todo ID to delete
 * @returns {Object} - API response confirming deletion
 */
async function deleteTodo(todoId) {
    try {
        console.log('Deleting todo:', todoId);
        
        const params = {
            TableName: TABLE_NAME,
            Key: { id: todoId },
            // Return the deleted item to confirm it existed
            ReturnValues: 'ALL_OLD'
        };
        
        const result = await dynamodb.delete(params).promise();
        
        if (!result.Attributes) {
            return createErrorResponse(404, 'Todo not found');
        }
        
        console.log('Successfully deleted todo:', todoId);
        return createResponse(200, { 
            message: 'Todo deleted successfully',
            deletedTodo: result.Attributes
        });
        
    } catch (error) {
        console.error('Error deleting todo:', error);
        return createErrorResponse(500, 'Failed to delete todo', error.message);
    }
}

/**
 * Create a successful API Gateway response
 * @param {number} statusCode - HTTP status code
 * @param {Object} data - Response data
 * @returns {Object} - Formatted API Gateway response
 */
function createResponse(statusCode, data) {
    return {
        statusCode,
        headers: CORS_HEADERS,
        body: JSON.stringify(data)
    };
}

/**
 * Create an error API Gateway response
 * @param {number} statusCode - HTTP status code
 * @param {string} message - Error message
 * @param {string} details - Optional error details
 * @returns {Object} - Formatted API Gateway error response
 */
function createErrorResponse(statusCode, message, details = null) {
    const errorResponse = {
        error: message,
        statusCode,
        timestamp: new Date().toISOString()
    };
    
    if (details) {
        errorResponse.details = details;
    }
    
    console.error('API Error:', errorResponse);
    
    return {
        statusCode,
        headers: CORS_HEADERS,
        body: JSON.stringify(errorResponse)
    };
}