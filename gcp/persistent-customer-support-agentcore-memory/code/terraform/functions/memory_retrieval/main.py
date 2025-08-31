# Memory Retrieval Cloud Function
# Retrieves conversation history from Firestore for AI customer support context

import functions_framework
from google.cloud import firestore
import json
import os
from flask import Request
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional

# Initialize Firestore client
db = firestore.Client(project="${project_id}")

@functions_framework.http
def retrieve_memory(request: Request):
    """
    Retrieve conversation memory for customer context.
    
    This function queries Firestore to retrieve recent conversation history
    for a specific customer, enabling the AI to provide contextual responses.
    
    Args:
        request: HTTP request containing customer_id in JSON body
        
    Returns:
        JSON response with conversation history and customer context
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for main request
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Parse request JSON
        if not request.is_json:
            return ({'error': 'Request must be JSON'}, 400, headers)
        
        request_json = request.get_json(silent=True)
        if not request_json:
            return ({'error': 'Invalid JSON in request'}, 400, headers)
        
        customer_id = request_json.get('customer_id')
        
        if not customer_id:
            return ({'error': 'customer_id is required'}, 400, headers)
        
        # Validate customer_id format (basic validation)
        if not isinstance(customer_id, str) or len(customer_id.strip()) == 0:
            return ({'error': 'customer_id must be a non-empty string'}, 400, headers)
        
        customer_id = customer_id.strip()
        
        # Retrieve recent conversations (last 30 days)
        thirty_days_ago = datetime.now() - timedelta(days=30)
        
        # Query conversations collection with proper indexing
        conversations_ref = db.collection('conversations')
        query = conversations_ref.where('customer_id', '==', customer_id) \
                               .where('timestamp', '>=', thirty_days_ago) \
                               .order_by('timestamp', direction=firestore.Query.DESCENDING) \
                               .limit(10)
        
        # Execute query and process results
        conversations = []
        total_conversations = 0
        
        try:
            query_results = query.stream()
            for doc in query_results:
                conversation = doc.to_dict()
                conversations.append({
                    'id': doc.id,
                    'message': conversation.get('message', ''),
                    'response': conversation.get('response', ''),
                    'timestamp': conversation.get('timestamp'),
                    'sentiment': conversation.get('sentiment', 'neutral'),
                    'resolved': conversation.get('resolved', False),
                    'context_used': conversation.get('context_used', {})
                })
                total_conversations += 1
                
        except Exception as query_error:
            print(f"Error querying Firestore: {query_error}")
            # Return empty result instead of failing
            conversations = []
            total_conversations = 0
        
        # Extract and analyze customer context
        customer_context = analyze_customer_context(conversations)
        customer_context['total_conversations'] = total_conversations
        
        # Prepare response
        response_data = {
            'customer_id': customer_id,
            'conversations': conversations,
            'context': customer_context,
            'retrieved_at': datetime.now().isoformat(),
            'query_period_days': 30,
            'max_conversations': 10
        }
        
        return (response_data, 200, headers)
        
    except Exception as e:
        error_message = f"Internal server error: {str(e)}"
        print(f"Error in retrieve_memory: {error_message}")
        return ({'error': 'Internal server error', 'details': str(e)}, 500, headers)

def analyze_customer_context(conversations: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Analyze conversation history to extract customer context and patterns.
    
    Args:
        conversations: List of conversation dictionaries
        
    Returns:
        Dictionary containing analyzed customer context
    """
    
    context = {
        'recent_topics': [],
        'satisfaction_trend': 'neutral',
        'common_issues': [],
        'unresolved_issues': 0,
        'interaction_frequency': 'low',
        'last_interaction': None,
        'sentiment_distribution': {'positive': 0, 'neutral': 0, 'negative': 0}
    }
    
    if not conversations:
        return context
    
    # Analyze unresolved issues
    unresolved_count = sum(1 for c in conversations if not c.get('resolved', False))
    context['unresolved_issues'] = unresolved_count
    
    # Extract recent topics (simplified keyword extraction)
    recent_messages = []
    for conv in conversations[:3]:  # Last 3 conversations
        message = conv.get('message', '')
        if message and len(message.strip()) > 0:
            # Take first 100 characters for topic summary
            topic_summary = message.strip()[:100]
            if len(message) > 100:
                topic_summary += "..."
            recent_messages.append(topic_summary)
    
    context['recent_topics'] = recent_messages
    
    # Analyze sentiment distribution
    sentiment_counts = {'positive': 0, 'neutral': 0, 'negative': 0}
    for conv in conversations:
        sentiment = conv.get('sentiment', 'neutral')
        if sentiment in sentiment_counts:
            sentiment_counts[sentiment] += 1
        else:
            sentiment_counts['neutral'] += 1
    
    context['sentiment_distribution'] = sentiment_counts
    
    # Determine overall satisfaction trend
    total_conversations = len(conversations)
    if total_conversations > 0:
        negative_ratio = sentiment_counts['negative'] / total_conversations
        positive_ratio = sentiment_counts['positive'] / total_conversations
        
        if negative_ratio > 0.5:
            context['satisfaction_trend'] = 'declining'
        elif positive_ratio > 0.6:
            context['satisfaction_trend'] = 'positive'
        else:
            context['satisfaction_trend'] = 'neutral'
    
    # Determine interaction frequency
    if total_conversations >= 5:
        context['interaction_frequency'] = 'high'
    elif total_conversations >= 2:
        context['interaction_frequency'] = 'medium'
    else:
        context['interaction_frequency'] = 'low'
    
    # Set last interaction timestamp
    if conversations:
        context['last_interaction'] = conversations[0].get('timestamp')
    
    # Extract common issues (simplified pattern matching)
    issue_keywords = []
    for conv in conversations:
        message = conv.get('message', '').lower()
        # Simple keyword extraction for common issues
        if 'order' in message or 'purchase' in message:
            issue_keywords.append('order_issues')
        if 'payment' in message or 'billing' in message:
            issue_keywords.append('payment_issues')
        if 'delivery' in message or 'shipping' in message:
            issue_keywords.append('delivery_issues')
        if 'refund' in message or 'return' in message:
            issue_keywords.append('refund_requests')
        if 'technical' in message or 'bug' in message or 'error' in message:
            issue_keywords.append('technical_issues')
    
    # Count frequency of each issue type
    issue_frequency = {}
    for issue in issue_keywords:
        issue_frequency[issue] = issue_frequency.get(issue, 0) + 1
    
    # Get most common issues
    common_issues = sorted(issue_frequency.items(), key=lambda x: x[1], reverse=True)
    context['common_issues'] = [issue[0] for issue in common_issues[:3]]
    
    return context

if __name__ == "__main__":
    # For local testing
    print("Memory retrieval function initialized")
    print(f"Project: ${project_id}")
    print(f"Region: ${region}")