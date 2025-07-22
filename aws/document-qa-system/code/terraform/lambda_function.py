import json
import boto3
import os
import logging
from typing import Dict, List, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
kendra = boto3.client('kendra')
bedrock = boto3.client('bedrock-runtime')

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    AWS Lambda handler for processing intelligent document QA requests.
    
    This function implements a Retrieval-Augmented Generation (RAG) pattern:
    1. Extracts the user question from the event
    2. Queries Amazon Kendra for relevant document passages
    3. Uses AWS Bedrock to generate a contextual answer
    4. Returns the answer with source citations
    
    Args:
        event: Lambda event containing the user question
        context: Lambda context object
        
    Returns:
        Dict containing the question, answer, and source citations
    """
    
    try:
        # Extract question from event
        # Support both direct invocation and API Gateway proxy integration
        if 'body' in event:
            # API Gateway integration
            if isinstance(event['body'], str):
                body = json.loads(event['body'])
            else:
                body = event['body']
            question = body.get('question', '')
        else:
            # Direct invocation
            question = event.get('question', '')
        
        if not question:
            return {
                'statusCode': 400,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'error': 'Question is required'
                })
            }
        
        logger.info(f"Processing question: {question}")
        
        # Get environment variables
        index_id = os.environ.get('KENDRA_INDEX_ID')
        model_id = os.environ.get('BEDROCK_MODEL_ID', '${bedrock_model_id}')
        max_tokens = int(os.environ.get('MAX_TOKENS', '${max_tokens}'))
        
        if not index_id:
            raise ValueError("KENDRA_INDEX_ID environment variable not set")
        
        # Query Kendra for relevant documents
        logger.info(f"Querying Kendra index: {index_id}")
        kendra_response = kendra.query(
            IndexId=index_id,
            QueryText=question,
            PageSize=5,  # Retrieve top 5 results
            QueryResultTypeFilter='DOCUMENT'  # Focus on document excerpts
        )
        
        # Extract relevant passages from Kendra results
        passages = []
        for item in kendra_response.get('ResultItems', []):
            if item.get('Type') == 'DOCUMENT':
                # Extract document excerpt
                excerpt = item.get('DocumentExcerpt', {})
                text = excerpt.get('Text', '').strip()
                
                # Extract document metadata
                title = item.get('DocumentTitle', {}).get('Text', 'Unknown Document')
                uri = item.get('DocumentURI', '')
                score = item.get('ScoreAttributes', {}).get('ScoreConfidence', 'UNKNOWN')
                
                if text:  # Only include passages with actual content
                    passages.append({
                        'text': text,
                        'title': title,
                        'uri': uri,
                        'confidence': score
                    })
        
        logger.info(f"Found {len(passages)} relevant passages")
        
        if not passages:
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*'
                },
                'body': json.dumps({
                    'question': question,
                    'answer': "I couldn't find any relevant information in the document repository to answer your question. Please try rephrasing your question or ensure the relevant documents are uploaded to the system.",
                    'sources': [],
                    'confidence': 'LOW'
                })
            }
        
        # Prepare context for Bedrock
        context_text = '\n\n'.join([
            f"Document: {passage['title']}\nContent: {passage['text']}"
            for passage in passages
        ])
        
        # Create prompt for Bedrock Claude model
        prompt = f"""You are an intelligent document analysis assistant. Based on the following document excerpts, please provide a comprehensive and accurate answer to the user's question.

Question: {question}

Document excerpts:
{context_text}

Instructions:
1. Provide a clear, well-structured answer based solely on the information in the document excerpts
2. If the documents don't contain sufficient information to fully answer the question, acknowledge this limitation
3. Reference specific documents when making claims
4. Be concise but thorough
5. If multiple documents provide conflicting information, acknowledge this and present both perspectives

Answer:"""
        
        # Call Bedrock Claude model
        logger.info(f"Calling Bedrock model: {model_id}")
        bedrock_request = {
            'anthropic_version': 'bedrock-2023-05-31',
            'max_tokens': max_tokens,
            'messages': [
                {
                    'role': 'user',
                    'content': prompt
                }
            ],
            'temperature': 0.1,  # Low temperature for more factual responses
            'top_p': 0.9
        }
        
        bedrock_response = bedrock.invoke_model(
            modelId=model_id,
            body=json.dumps(bedrock_request)
        )
        
        # Parse Bedrock response
        response_body = json.loads(bedrock_response['body'].read())
        answer = response_body['content'][0]['text'].strip()
        
        # Determine overall confidence based on Kendra scores
        confidence_scores = [p.get('confidence', 'LOW') for p in passages]
        if 'VERY_HIGH' in confidence_scores or 'HIGH' in confidence_scores:
            overall_confidence = 'HIGH'
        elif 'MEDIUM' in confidence_scores:
            overall_confidence = 'MEDIUM'
        else:
            overall_confidence = 'LOW'
        
        # Prepare sources for response
        sources = [
            {
                'title': passage['title'],
                'uri': passage['uri'],
                'confidence': passage['confidence']
            }
            for passage in passages
        ]
        
        logger.info("Successfully generated answer")
        
        # Return successful response
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'question': question,
                'answer': answer,
                'sources': sources,
                'confidence': overall_confidence,
                'total_sources': len(sources)
            })
        }
        
    except Exception as e:
        logger.error(f"Error processing request: {str(e)}", exc_info=True)
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'error': 'Internal server error occurred while processing your question',
                'details': str(e) if logger.level == logging.DEBUG else None
            })
        }


def validate_environment() -> bool:
    """
    Validate that all required environment variables are set.
    
    Returns:
        bool: True if all required variables are present
    """
    required_vars = ['KENDRA_INDEX_ID']
    missing_vars = [var for var in required_vars if not os.environ.get(var)]
    
    if missing_vars:
        logger.error(f"Missing required environment variables: {missing_vars}")
        return False
    
    return True


# Validate environment on module load
if not validate_environment():
    logger.error("Environment validation failed")