import json
import boto3
import random
import os
from typing import Dict, Any

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda function to serve random inspirational quotes from S3.
    
    This function retrieves quotes from a JSON file stored in S3,
    selects a random quote, and returns it as a JSON response.
    
    Args:
        event: Lambda event data (HTTP request details when using Function URL)
        context: Lambda context object containing runtime information
        
    Returns:
        Dict containing HTTP response with status code, headers, and body
    """
    # Initialize S3 client
    s3_client = boto3.client('s3')
    bucket_name = os.environ.get('BUCKET_NAME')
    
    # Validate environment variable
    if not bucket_name:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Configuration error',
                'message': 'BUCKET_NAME environment variable not set'
            })
        }
    
    try:
        # Get quotes from S3
        response = s3_client.get_object(Bucket=bucket_name, Key='quotes.json')
        quotes_data = json.loads(response['Body'].read().decode('utf-8'))
        
        # Validate quotes data structure
        if 'quotes' not in quotes_data or not isinstance(quotes_data['quotes'], list):
            raise ValueError('Invalid quotes data structure')
        
        if not quotes_data['quotes']:
            raise ValueError('No quotes found in data')
        
        # Select random quote
        random_quote = random.choice(quotes_data['quotes'])
        
        # Validate quote structure
        if not isinstance(random_quote, dict) or 'text' not in random_quote or 'author' not in random_quote:
            raise ValueError('Invalid quote structure')
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Cache-Control': 'no-cache'
            },
            'body': json.dumps({
                'quote': random_quote['text'],
                'author': random_quote['author'],
                'timestamp': context.aws_request_id,
                'source': 'daily-quote-generator'
            }, ensure_ascii=False)
        }
        
    except s3_client.exceptions.NoSuchBucket:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Storage error',
                'message': f'S3 bucket {bucket_name} not found'
            })
        }
        
    except s3_client.exceptions.NoSuchKey:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Data error',
                'message': 'quotes.json file not found in S3 bucket'
            })
        }
        
    except json.JSONDecodeError as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Data format error',
                'message': f'Invalid JSON format in quotes data: {str(e)}'
            })
        }
        
    except ValueError as e:
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Data validation error',
                'message': str(e)
            })
        }
        
    except Exception as e:
        # Log the full error for debugging (will appear in CloudWatch Logs)
        print(f"Unexpected error: {str(e)}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error',
                'message': 'An unexpected error occurred while processing your request'
            })
        }