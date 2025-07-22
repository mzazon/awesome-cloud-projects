import json
import boto3
import urllib.parse
from datetime import datetime
import os
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

def lambda_handler(event, context):
    """
    AWS Lambda function to analyze content using Amazon Bedrock and publish results to EventBridge
    
    Args:
        event: S3 event notification containing bucket and key information
        context: Lambda runtime context
        
    Returns:
        dict: Response containing status code and message
    """
    try:
        # Parse S3 event to extract bucket and object key
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        logger.info(f"Processing content from s3://{bucket}/{key}")
        
        # Get content from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        
        # Truncate content for analysis (first 2000 characters)
        content_for_analysis = content[:2000]
        
        # Prepare moderation prompt for Claude
        prompt = f"""
Human: Please analyze the following content for policy violations. 
Consider harmful content including hate speech, violence, harassment, 
inappropriate sexual content, misinformation, and spam.

Content to analyze:
{content_for_analysis}

Respond with a JSON object containing:
- "decision": "approved", "rejected", or "review"
- "confidence": score from 0.0 to 1.0
- "reason": brief explanation
- "categories": array of policy categories if violations found