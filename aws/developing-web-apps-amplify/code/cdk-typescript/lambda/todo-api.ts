import { APIGatewayProxyEvent, APIGatewayProxyResult, Context } from 'aws-lambda';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  ScanCommand,
  PutCommand,
  UpdateCommand,
  DeleteCommand,
  GetCommand,
} from '@aws-sdk/lib-dynamodb';
import { v4 as uuidv4 } from 'uuid';

// Initialize DynamoDB client
const dynamoDbClient = new DynamoDBClient({ region: process.env.AWS_REGION });
const docClient = DynamoDBDocumentClient.from(dynamoDbClient);

// Environment variables
const TODO_TABLE_NAME = process.env.TODO_TABLE_NAME!;
const CORS_ORIGIN = process.env.CORS_ORIGIN || '*';
const LOG_LEVEL = process.env.LOG_LEVEL || 'INFO';

// Todo interface
interface Todo {
  id: string;
  title: string;
  completed: boolean;
  createdAt: string;
  updatedAt: string;
  userId: string;
}

interface CreateTodoRequest {
  title: string;
  completed?: boolean;
}

interface UpdateTodoRequest {
  title?: string;
  completed?: boolean;
}

// Logging utility
const log = (level: string, message: string, data?: any) => {
  if (LOG_LEVEL === 'DEBUG' || level === 'ERROR' || level === 'INFO') {
    console.log(JSON.stringify({
      level,
      message,
      timestamp: new Date().toISOString(),
      data,
    }));
  }
};

// CORS headers
const corsHeaders = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': CORS_ORIGIN,
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Amz-Date, X-Api-Key, X-Amz-Security-Token',
};

// Main Lambda handler
export const handler = async (
  event: APIGatewayProxyEvent,
  context: Context
): Promise<APIGatewayProxyResult> => {
  log('INFO', 'Lambda function invoked', {
    httpMethod: event.httpMethod,
    path: event.path,
    pathParameters: event.pathParameters,
    requestId: context.awsRequestId,
  });

  try {
    // Handle CORS preflight requests
    if (event.httpMethod === 'OPTIONS') {
      return {
        statusCode: 200,
        headers: corsHeaders,
        body: '',
      };
    }

    // Extract user ID from Cognito JWT token
    const userId = getUserIdFromEvent(event);
    if (!userId) {
      return createErrorResponse(401, 'Unauthorized: Invalid or missing user token');
    }

    // Route requests based on HTTP method and path
    const { httpMethod, pathParameters } = event;
    const todoId = pathParameters?.id;

    switch (httpMethod) {
      case 'GET':
        if (todoId) {
          return await getTodoById(todoId, userId);
        } else {
          return await getAllTodos(userId);
        }

      case 'POST':
        return await createTodo(event.body, userId);

      case 'PUT':
        if (!todoId) {
          return createErrorResponse(400, 'Todo ID is required for update');
        }
        return await updateTodo(todoId, event.body, userId);

      case 'DELETE':
        if (!todoId) {
          return createErrorResponse(400, 'Todo ID is required for delete');
        }
        return await deleteTodo(todoId, userId);

      default:
        return createErrorResponse(405, 'Method not allowed');
    }
  } catch (error) {
    log('ERROR', 'Unhandled error in Lambda function', {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
      event,
    });

    return createErrorResponse(500, 'Internal server error');
  }
};

// Extract user ID from Cognito JWT token in the event
function getUserIdFromEvent(event: APIGatewayProxyEvent): string | null {
  try {
    // The user ID is available in the requestContext when using Cognito authorizer
    const claims = event.requestContext.authorizer?.claims;
    return claims?.sub || claims?.['cognito:username'] || null;
  } catch (error) {
    log('ERROR', 'Error extracting user ID from event', { error });
    return null;
  }
}

// Get all todos for a user
async function getAllTodos(userId: string): Promise<APIGatewayProxyResult> {
  try {
    log('INFO', 'Getting all todos for user', { userId });

    const command = new ScanCommand({
      TableName: TODO_TABLE_NAME,
      FilterExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId,
      },
    });

    const result = await docClient.send(command);
    const todos = result.Items as Todo[] || [];

    // Sort todos by creation date (newest first)
    todos.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

    log('INFO', 'Retrieved todos successfully', { count: todos.length });

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify({
        todos,
        count: todos.length,
      }),
    };
  } catch (error) {
    log('ERROR', 'Error getting todos', { error, userId });
    return createErrorResponse(500, 'Failed to retrieve todos');
  }
}

// Get a specific todo by ID
async function getTodoById(todoId: string, userId: string): Promise<APIGatewayProxyResult> {
  try {
    log('INFO', 'Getting todo by ID', { todoId, userId });

    const command = new GetCommand({
      TableName: TODO_TABLE_NAME,
      Key: { id: todoId },
    });

    const result = await docClient.send(command);
    const todo = result.Item as Todo;

    if (!todo) {
      return createErrorResponse(404, 'Todo not found');
    }

    // Check if the todo belongs to the requesting user
    if (todo.userId !== userId) {
      return createErrorResponse(403, 'Access denied');
    }

    log('INFO', 'Retrieved todo successfully', { todoId });

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify(todo),
    };
  } catch (error) {
    log('ERROR', 'Error getting todo by ID', { error, todoId, userId });
    return createErrorResponse(500, 'Failed to retrieve todo');
  }
}

// Create a new todo
async function createTodo(body: string | null, userId: string): Promise<APIGatewayProxyResult> {
  try {
    if (!body) {
      return createErrorResponse(400, 'Request body is required');
    }

    const request: CreateTodoRequest = JSON.parse(body);

    // Validate request
    if (!request.title || typeof request.title !== 'string' || request.title.trim().length === 0) {
      return createErrorResponse(400, 'Todo title is required and must be a non-empty string');
    }

    if (request.title.length > 500) {
      return createErrorResponse(400, 'Todo title must be 500 characters or less');
    }

    const now = new Date().toISOString();
    const todo: Todo = {
      id: uuidv4(),
      title: request.title.trim(),
      completed: request.completed || false,
      createdAt: now,
      updatedAt: now,
      userId,
    };

    log('INFO', 'Creating new todo', { todoId: todo.id, userId });

    const command = new PutCommand({
      TableName: TODO_TABLE_NAME,
      Item: todo,
      ConditionExpression: 'attribute_not_exists(id)',
    });

    await docClient.send(command);

    log('INFO', 'Todo created successfully', { todoId: todo.id });

    return {
      statusCode: 201,
      headers: corsHeaders,
      body: JSON.stringify(todo),
    };
  } catch (error) {
    if (error instanceof SyntaxError) {
      return createErrorResponse(400, 'Invalid JSON in request body');
    }

    log('ERROR', 'Error creating todo', { error, userId });
    return createErrorResponse(500, 'Failed to create todo');
  }
}

// Update an existing todo
async function updateTodo(todoId: string, body: string | null, userId: string): Promise<APIGatewayProxyResult> {
  try {
    if (!body) {
      return createErrorResponse(400, 'Request body is required');
    }

    const request: UpdateTodoRequest = JSON.parse(body);

    // Validate request
    if (request.title !== undefined) {
      if (typeof request.title !== 'string' || request.title.trim().length === 0) {
        return createErrorResponse(400, 'Todo title must be a non-empty string');
      }
      if (request.title.length > 500) {
        return createErrorResponse(400, 'Todo title must be 500 characters or less');
      }
    }

    if (request.completed !== undefined && typeof request.completed !== 'boolean') {
      return createErrorResponse(400, 'Todo completed status must be a boolean');
    }

    // First, verify the todo exists and belongs to the user
    const getCommand = new GetCommand({
      TableName: TODO_TABLE_NAME,
      Key: { id: todoId },
    });

    const existingTodo = await docClient.send(getCommand);
    if (!existingTodo.Item) {
      return createErrorResponse(404, 'Todo not found');
    }

    if (existingTodo.Item.userId !== userId) {
      return createErrorResponse(403, 'Access denied');
    }

    log('INFO', 'Updating todo', { todoId, userId });

    // Build update expression dynamically
    const updateExpressions: string[] = [];
    const expressionAttributeNames: Record<string, string> = {};
    const expressionAttributeValues: Record<string, any> = {};

    if (request.title !== undefined) {
      updateExpressions.push('#title = :title');
      expressionAttributeNames['#title'] = 'title';
      expressionAttributeValues[':title'] = request.title.trim();
    }

    if (request.completed !== undefined) {
      updateExpressions.push('#completed = :completed');
      expressionAttributeNames['#completed'] = 'completed';
      expressionAttributeValues[':completed'] = request.completed;
    }

    // Always update the updatedAt timestamp
    updateExpressions.push('#updatedAt = :updatedAt');
    expressionAttributeNames['#updatedAt'] = 'updatedAt';
    expressionAttributeValues[':updatedAt'] = new Date().toISOString();

    const updateCommand = new UpdateCommand({
      TableName: TODO_TABLE_NAME,
      Key: { id: todoId },
      UpdateExpression: `SET ${updateExpressions.join(', ')}`,
      ExpressionAttributeNames: expressionAttributeNames,
      ExpressionAttributeValues: expressionAttributeValues,
      ConditionExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ...expressionAttributeValues,
        ':userId': userId,
      },
      ReturnValues: 'ALL_NEW',
    });

    const result = await docClient.send(updateCommand);
    const updatedTodo = result.Attributes as Todo;

    log('INFO', 'Todo updated successfully', { todoId });

    return {
      statusCode: 200,
      headers: corsHeaders,
      body: JSON.stringify(updatedTodo),
    };
  } catch (error) {
    if (error instanceof SyntaxError) {
      return createErrorResponse(400, 'Invalid JSON in request body');
    }

    log('ERROR', 'Error updating todo', { error, todoId, userId });
    return createErrorResponse(500, 'Failed to update todo');
  }
}

// Delete a todo
async function deleteTodo(todoId: string, userId: string): Promise<APIGatewayProxyResult> {
  try {
    log('INFO', 'Deleting todo', { todoId, userId });

    const command = new DeleteCommand({
      TableName: TODO_TABLE_NAME,
      Key: { id: todoId },
      ConditionExpression: 'userId = :userId',
      ExpressionAttributeValues: {
        ':userId': userId,
      },
      ReturnValues: 'ALL_OLD',
    });

    const result = await docClient.send(command);

    if (!result.Attributes) {
      return createErrorResponse(404, 'Todo not found or access denied');
    }

    log('INFO', 'Todo deleted successfully', { todoId });

    return {
      statusCode: 204,
      headers: corsHeaders,
      body: '',
    };
  } catch (error) {
    log('ERROR', 'Error deleting todo', { error, todoId, userId });
    return createErrorResponse(500, 'Failed to delete todo');
  }
}

// Create error response
function createErrorResponse(statusCode: number, message: string): APIGatewayProxyResult {
  return {
    statusCode,
    headers: corsHeaders,
    body: JSON.stringify({
      error: message,
      timestamp: new Date().toISOString(),
    }),
  };
}