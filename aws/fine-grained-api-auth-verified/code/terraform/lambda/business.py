import json
import boto3
import uuid
import os
from datetime import datetime
from decimal import Decimal

# Initialize AWS resources
dynamodb = boto3.resource('dynamodb')
documents_table_name = os.environ.get('DOCUMENTS_TABLE', '${documents_table}')

def lambda_handler(event, context):
    """
    Lambda function for document management business logic.
    Handles CRUD operations on documents with user context from authorizer.
    """
    try:
        # Initialize DynamoDB table
        table = dynamodb.Table(documents_table_name)
        
        # Extract user context from API Gateway authorizer
        user_context = event.get('requestContext', {}).get('authorizer', {})
        user_id = user_context.get('userId', 'unknown')
        department = user_context.get('department', '')
        role = user_context.get('role', '')
        auth_decision = user_context.get('authDecision', 'UNKNOWN')
        
        # Log authorization context for debugging
        print(f"Request from user: {user_id}, department: {department}, role: {role}")
        print(f"Authorization decision: {auth_decision}")
        
        # Extract request information
        http_method = event['httpMethod']
        path_parameters = event.get('pathParameters') or {}
        document_id = path_parameters.get('documentId')
        
        # Route request to appropriate handler
        if http_method == 'GET' and document_id:
            return handle_get_document(table, document_id, user_context)
        elif http_method == 'GET':
            return handle_list_documents(table, user_context)
        elif http_method == 'POST':
            return handle_create_document(table, event, user_context)
        elif http_method == 'PUT' and document_id:
            return handle_update_document(table, document_id, event, user_context)
        elif http_method == 'DELETE' and document_id:
            return handle_delete_document(table, document_id, user_context)
        else:
            return create_error_response(400, 'Invalid request method or parameters')
            
    except Exception as e:
        print(f"Business logic error: {str(e)}")
        return create_error_response(500, f'Internal server error: {str(e)}')

def handle_get_document(table, document_id, user_context):
    """
    Retrieve a specific document by ID
    """
    try:
        response = table.get_item(Key={'documentId': document_id})
        
        if 'Item' not in response:
            return create_error_response(404, 'Document not found')
        
        document = response['Item']
        
        # Convert Decimal types to int/float for JSON serialization
        document = convert_decimal_to_number(document)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(document)
        }
        
    except Exception as e:
        print(f"Error retrieving document {document_id}: {str(e)}")
        return create_error_response(500, f'Failed to retrieve document: {str(e)}')

def handle_list_documents(table, user_context):
    """
    List all documents (in production, this would be filtered by user permissions)
    """
    try:
        # In a production system, you would implement proper filtering here
        # based on user department, role, and ownership
        response = table.scan()
        
        documents = response.get('Items', [])
        
        # Convert Decimal types for JSON serialization
        documents = [convert_decimal_to_number(doc) for doc in documents]
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'documents': documents,
                'count': len(documents)
            })
        }
        
    except Exception as e:
        print(f"Error listing documents: {str(e)}")
        return create_error_response(500, f'Failed to list documents: {str(e)}')

def handle_create_document(table, event, user_context):
    """
    Create a new document
    """
    try:
        # Parse request body
        if not event.get('body'):
            return create_error_response(400, 'Request body is required')
        
        body = json.loads(event['body'])
        
        # Validate required fields
        if not body.get('title') or not body.get('content'):
            return create_error_response(400, 'Title and content are required')
        
        # Extract user information
        user_id = user_context.get('userId', 'unknown')
        department = user_context.get('department', '')
        
        # Create document object
        document = {
            'documentId': str(uuid.uuid4()),
            'title': body['title'],
            'content': body['content'],
            'owner': user_id,
            'department': department,
            'createdAt': datetime.utcnow().isoformat(),
            'updatedAt': datetime.utcnow().isoformat(),
            'version': 1
        }
        
        # Add optional fields
        if body.get('tags'):
            document['tags'] = body['tags']
        
        # Store document in DynamoDB
        table.put_item(Item=document)
        
        # Convert Decimal types for JSON response
        document = convert_decimal_to_number(document)
        
        return {
            'statusCode': 201,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(document)
        }
        
    except json.JSONDecodeError:
        return create_error_response(400, 'Invalid JSON in request body')
    except Exception as e:
        print(f"Error creating document: {str(e)}")
        return create_error_response(500, f'Failed to create document: {str(e)}')

def handle_update_document(table, document_id, event, user_context):
    """
    Update an existing document
    """
    try:
        # Parse request body
        if not event.get('body'):
            return create_error_response(400, 'Request body is required')
        
        body = json.loads(event['body'])
        
        # Build update expression
        update_expression = "SET updatedAt = :updated"
        expression_attribute_values = {
            ':updated': datetime.utcnow().isoformat()
        }
        
        # Update title if provided
        if body.get('title'):
            update_expression += ", title = :title"
            expression_attribute_values[':title'] = body['title']
        
        # Update content if provided
        if body.get('content'):
            update_expression += ", content = :content"
            expression_attribute_values[':content'] = body['content']
        
        # Update tags if provided
        if body.get('tags'):
            update_expression += ", tags = :tags"
            expression_attribute_values[':tags'] = body['tags']
        
        # Increment version
        update_expression += ", version = if_not_exists(version, :zero) + :one"
        expression_attribute_values[':zero'] = 0
        expression_attribute_values[':one'] = 1
        
        # Update document in DynamoDB
        response = table.update_item(
            Key={'documentId': document_id},
            UpdateExpression=update_expression,
            ExpressionAttributeValues=expression_attribute_values,
            ReturnValues='ALL_NEW'
        )
        
        if 'Attributes' not in response:
            return create_error_response(404, 'Document not found')
        
        document = response['Attributes']
        
        # Convert Decimal types for JSON response
        document = convert_decimal_to_number(document)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps(document)
        }
        
    except json.JSONDecodeError:
        return create_error_response(400, 'Invalid JSON in request body')
    except Exception as e:
        print(f"Error updating document {document_id}: {str(e)}")
        return create_error_response(500, f'Failed to update document: {str(e)}')

def handle_delete_document(table, document_id, user_context):
    """
    Delete a document
    """
    try:
        # Check if document exists before deletion
        response = table.get_item(Key={'documentId': document_id})
        
        if 'Item' not in response:
            return create_error_response(404, 'Document not found')
        
        # Delete document from DynamoDB
        table.delete_item(Key={'documentId': document_id})
        
        return {
            'statusCode': 204,
            'headers': {
                'Access-Control-Allow-Origin': '*'
            },
            'body': ''
        }
        
    except Exception as e:
        print(f"Error deleting document {document_id}: {str(e)}")
        return create_error_response(500, f'Failed to delete document: {str(e)}')

def convert_decimal_to_number(obj):
    """
    Convert DynamoDB Decimal types to regular numbers for JSON serialization
    """
    if isinstance(obj, list):
        return [convert_decimal_to_number(item) for item in obj]
    elif isinstance(obj, dict):
        return {key: convert_decimal_to_number(value) for key, value in obj.items()}
    elif isinstance(obj, Decimal):
        return int(obj) if obj % 1 == 0 else float(obj)
    else:
        return obj

def create_error_response(status_code, message):
    """
    Create standardized error response
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'Access-Control-Allow-Origin': '*'
        },
        'body': json.dumps({
            'error': message,
            'timestamp': datetime.utcnow().isoformat()
        })
    }