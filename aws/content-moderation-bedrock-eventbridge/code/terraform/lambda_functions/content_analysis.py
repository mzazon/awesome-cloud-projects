#!/usr/bin/env python3
import json
import boto3
import urllib.parse
import logging
import os
from datetime import datetime
from typing import Dict, Any, Optional

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock = boto3.client('bedrock-runtime')
s3 = boto3.client('s3')
eventbridge = boto3.client('events')

CUSTOM_BUS_NAME = os.environ.get('CUSTOM_BUS_NAME', '${custom_bus_name}')
BEDROCK_MODEL_ID = os.environ.get('BEDROCK_MODEL_ID', '${bedrock_model_id}')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    try:
        logger.info(f"Processing S3 event: {json.dumps(event)}")
        
        bucket = event['Records'][0]['s3']['bucket']['name']
        key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'])
        
        logger.info(f"Analyzing content from s3://{bucket}/{key}")
        
        content = get_content_from_s3(bucket, key)
        if not content:
            logger.warning(f"No content found or content is empty for {key}")
            return create_response(200, "No content to analyze")
        
        moderation_result = analyze_content_with_bedrock(content)
        event_published = publish_moderation_event(bucket, key, moderation_result)
        
        if event_published:
            logger.info(f"Successfully processed content {key} with decision: {moderation_result['decision']}")
            return create_response(200, {
                'message': 'Content analyzed successfully',
                'decision': moderation_result['decision'],
                'confidence': moderation_result['confidence']
            })
        else:
            logger.error(f"Failed to publish event for content {key}")
            return create_response(500, "Failed to publish moderation event")
            
    except Exception as e:
        logger.error(f"Error processing content: {str(e)}", exc_info=True)
        return create_response(500, {'error': str(e)})

def get_content_from_s3(bucket: str, key: str) -> Optional[str]:
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        content = response['Body'].read().decode('utf-8')
        logger.info(f"Retrieved content of length {len(content)} characters")
        return content
    except Exception as e:
        logger.error(f"Error retrieving content from S3: {str(e)}")
        return None

def analyze_content_with_bedrock(content: str) -> Dict[str, Any]:
    try:
        content_to_analyze = content[:2000] if len(content) > 2000 else content
        
        prompt = f"""Human: Please analyze the following content for policy violations. Consider harmful content including hate speech, violence, harassment, inappropriate sexual content, misinformation, and spam.

Content to analyze:
{content_to_analyze}

Respond with a JSON object containing:
- "decision": "approved", "rejected", or "review"
- "confidence": score from 0.0 to 1.0  
- "reason": brief explanation
- "categories": array of policy categories if violations found

Assistant: """
        
        # Invoke Bedrock Claude model
        body = json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 1000,
            "messages": [
                {"role": "user", "content": prompt}
            ]
        })
        
        bedrock_response = bedrock.invoke_model(
            modelId=BEDROCK_MODEL_ID,
            body=body,
            contentType='application/json'
        )
        
        response_body = json.loads(bedrock_response['body'].read())
        moderation_result = json.loads(response_body['content'][0]['text'])
        
        logger.info(f"Bedrock analysis complete: {moderation_result['decision']} with confidence {moderation_result['confidence']}")
        return moderation_result
        
    except Exception as e:
        logger.error(f"Error analyzing content with Bedrock: {str(e)}")
        # Return default safe decision on error
        return {
            'decision': 'review',
            'confidence': 0.0,
            'reason': f'Analysis error: {str(e)[:100]}',
            'categories': ['error']
        }

def publish_moderation_event(bucket: str, key: str, moderation_result: Dict[str, Any]) -> bool:
    """
    Publish moderation decision to EventBridge for workflow routing.
    
    Args:
        bucket: Source S3 bucket name
        key: Source S3 object key
        moderation_result: Moderation analysis results
        
    Returns:
        Boolean indicating success or failure
    """
    try:
        # Create event detail with moderation results
        event_detail = {
            'bucket': bucket,
            'key': key,
            'decision': moderation_result['decision'],
            'confidence': moderation_result['confidence'],
            'reason': moderation_result['reason'],
            'categories': moderation_result.get('categories', []),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        # Determine event type based on decision
        detail_type = f"Content {moderation_result['decision'].title()}"
        
        # Publish event to custom EventBridge bus
        eventbridge.put_events(
            Entries=[
                {
                    'Source': 'content.moderation',
                    'DetailType': detail_type,
                    'Detail': json.dumps(event_detail),
                    'EventBusName': CUSTOM_BUS_NAME
                }
            ]
        )
        
        logger.info(f"Successfully published {detail_type} event to EventBridge")
        return True
        
    except Exception as e:
        logger.error(f"Error publishing event to EventBridge: {str(e)}")
        return False

def create_response(status_code: int, body: Any) -> Dict[str, Any]:
    """
    Create standardized Lambda response object.
    
    Args:
        status_code: HTTP status code
        body: Response body content
        
    Returns:
        Formatted Lambda response dictionary
    """
    return {
        'statusCode': status_code,
        'headers': {
            'Content-Type': 'application/json',
            'X-Content-Analysis': 'bedrock-claude'
        },
        'body': json.dumps(body) if isinstance(body, (dict, list)) else str(body)
    }