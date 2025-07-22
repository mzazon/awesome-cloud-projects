"""
Real-Time Event Processing Function

This Cloud Function processes events from Pub/Sub, caches data in Redis,
and stores analytics data in BigQuery for the real-time event processing system.

Author: Terraform-generated
Version: 1.0
"""

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import redis
from google.cloud import bigquery
from google.cloud.functions_v1.context import Context

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Environment configuration
PROJECT_ID = os.environ.get('PROJECT_ID', '${project_id}')
REDIS_HOST = os.environ.get('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', '6379'))
BIGQUERY_DATASET = os.environ.get('BIGQUERY_DATASET', 'event_analytics')
BIGQUERY_TABLE = os.environ.get('BIGQUERY_TABLE', 'processed_events')
CACHE_TTL_SECONDS = int(os.environ.get('CACHE_TTL_SECONDS', '3600'))

# Global clients (initialized on cold start)
redis_client: Optional[redis.Redis] = None
bigquery_client: Optional[bigquery.Client] = None
bigquery_table_ref: Optional[bigquery.TableReference] = None


def get_redis_client() -> redis.Redis:
    """Get or create Redis client with connection pooling."""
    global redis_client
    
    if redis_client is None:
        try:
            # Create Redis client with connection pooling
            redis_client = redis.Redis(
                host=REDIS_HOST,
                port=REDIS_PORT,
                db=0,
                decode_responses=True,
                socket_timeout=5,
                socket_connect_timeout=5,
                connection_pool_kwargs={
                    'max_connections': 10,
                    'retry_on_timeout': True
                }
            )
            
            # Test connection
            redis_client.ping()
            logger.info(f"Connected to Redis at {REDIS_HOST}:{REDIS_PORT}")
            
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {e}")
            raise
    
    return redis_client


def get_bigquery_client() -> bigquery.Client:
    """Get or create BigQuery client."""
    global bigquery_client, bigquery_table_ref
    
    if bigquery_client is None:
        try:
            bigquery_client = bigquery.Client(project=PROJECT_ID)
            
            # Create table reference for faster inserts
            dataset_ref = bigquery_client.dataset(BIGQUERY_DATASET)
            bigquery_table_ref = dataset_ref.table(BIGQUERY_TABLE)
            
            logger.info(f"Connected to BigQuery dataset: {BIGQUERY_DATASET}")
            
        except Exception as e:
            logger.error(f"Failed to connect to BigQuery: {e}")
            raise
    
    return bigquery_client


def parse_event_data(message_data: str) -> Dict[str, Any]:
    """Parse and validate event data from Pub/Sub message."""
    try:
        event_data = json.loads(message_data)
        
        # Validate required fields
        required_fields = ['id', 'userId', 'type', 'timestamp']
        for field in required_fields:
            if field not in event_data:
                raise ValueError(f"Missing required field: {field}")
        
        # Add processing timestamp
        event_data['processing_timestamp'] = datetime.now(timezone.utc).isoformat()
        
        return event_data
        
    except json.JSONDecodeError as e:
        logger.error(f"Invalid JSON in message: {e}")
        raise
    except Exception as e:
        logger.error(f"Error parsing event data: {e}")
        raise


def cache_event_data(redis_client: redis.Redis, event_data: Dict[str, Any]) -> Dict[str, Any]:
    """Cache event data in Redis with aggregation."""
    try:
        user_id = event_data['userId']
        event_type = event_data['type']
        cache_key = f"event:{event_type}:{user_id}"
        
        # Get existing cache data
        cached_data_json = redis_client.get(cache_key)
        
        if cached_data_json:
            # Update existing cache entry
            cached_data = json.loads(cached_data_json)
            cached_data['event_count'] += 1
            cached_data['last_event_time'] = event_data['timestamp']
            cached_data['last_processing_time'] = event_data['processing_timestamp']
            
            # Add current event to recent events (keep last 10)
            if 'recent_events' not in cached_data:
                cached_data['recent_events'] = []
            
            cached_data['recent_events'].append({
                'id': event_data['id'],
                'timestamp': event_data['timestamp'],
                'metadata': event_data.get('metadata', {})
            })
            
            # Keep only last 10 events to manage memory
            if len(cached_data['recent_events']) > 10:
                cached_data['recent_events'] = cached_data['recent_events'][-10:]
                
            logger.info(f"Cache hit for key: {cache_key}, count: {cached_data['event_count']}")
            
        else:
            # Create new cache entry
            cached_data = {
                'user_id': user_id,
                'event_type': event_type,
                'event_count': 1,
                'first_event_time': event_data['timestamp'],
                'last_event_time': event_data['timestamp'],
                'first_processing_time': event_data['processing_timestamp'],
                'last_processing_time': event_data['processing_timestamp'],
                'recent_events': [{
                    'id': event_data['id'],
                    'timestamp': event_data['timestamp'],
                    'metadata': event_data.get('metadata', {})
                }]
            }
            
            logger.info(f"Cache miss for key: {cache_key}, creating new entry")
        
        # Store updated data in cache with TTL
        redis_client.setex(
            cache_key,
            CACHE_TTL_SECONDS,
            json.dumps(cached_data)
        )
        
        return cached_data
        
    except Exception as e:
        logger.error(f"Error caching event data: {e}")
        raise


def store_event_in_bigquery(bigquery_client: bigquery.Client, event_data: Dict[str, Any]) -> None:
    """Store event data in BigQuery for analytics."""
    try:
        # Prepare row for BigQuery
        row = {
            'event_id': event_data['id'],
            'user_id': event_data['userId'],
            'event_type': event_data['type'],
            'timestamp': event_data['timestamp'],
            'source': event_data.get('source', 'unknown'),
            'metadata': json.dumps(event_data.get('metadata', {})),
            'processing_timestamp': event_data['processing_timestamp']
        }
        
        # Insert row into BigQuery
        table = bigquery_client.get_table(bigquery_table_ref)
        errors = bigquery_client.insert_rows_json(table, [row])
        
        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
            raise Exception(f"Failed to insert row into BigQuery: {errors}")
        
        logger.info(f"Successfully stored event {event_data['id']} in BigQuery")
        
    except Exception as e:
        logger.error(f"Error storing event in BigQuery: {e}")
        raise


def update_metrics(event_data: Dict[str, Any], cached_data: Dict[str, Any]) -> None:
    """Update custom metrics for monitoring."""
    try:
        # Log structured data for monitoring
        metrics = {
            'event_id': event_data['id'],
            'user_id': event_data['userId'],
            'event_type': event_data['type'],
            'cache_hit': cached_data['event_count'] > 1,
            'total_user_events': cached_data['event_count'],
            'processing_time_ms': time.time() * 1000
        }
        
        # Log metrics in structured format for Cloud Monitoring
        logger.info(f"METRICS: {json.dumps(metrics)}")
        
    except Exception as e:
        logger.error(f"Error updating metrics: {e}")


def process_event(cloud_event: Any) -> None:
    """
    Main function to process Pub/Sub events.
    
    Args:
        cloud_event: CloudEvent containing Pub/Sub message
    """
    start_time = time.time()
    
    try:
        # Extract message data
        message_data = cloud_event.data.get('message', {}).get('data')
        if not message_data:
            logger.error("No message data found in CloudEvent")
            return
        
        # Decode base64 message data
        import base64
        decoded_data = base64.b64decode(message_data).decode('utf-8')
        
        # Parse event data
        event_data = parse_event_data(decoded_data)
        logger.info(f"Processing event: {event_data['id']} for user: {event_data['userId']}")
        
        # Get clients
        redis_client = get_redis_client()
        bigquery_client = get_bigquery_client()
        
        # Cache event data in Redis
        cached_data = cache_event_data(redis_client, event_data)
        
        # Store event in BigQuery for analytics
        store_event_in_bigquery(bigquery_client, event_data)
        
        # Update monitoring metrics
        update_metrics(event_data, cached_data)
        
        # Log successful processing
        processing_time = (time.time() - start_time) * 1000
        logger.info(
            f"Event processed successfully: {event_data['id']} "
            f"(processing time: {processing_time:.2f}ms)"
        )
        
    except Exception as e:
        processing_time = (time.time() - start_time) * 1000
        logger.error(
            f"Error processing event: {e} "
            f"(processing time: {processing_time:.2f}ms)"
        )
        # Re-raise to trigger retry mechanism
        raise


# Health check function for monitoring
def health_check() -> Dict[str, Any]:
    """Health check function to verify service status."""
    try:
        # Test Redis connection
        redis_client = get_redis_client()
        redis_client.ping()
        
        # Test BigQuery connection
        bigquery_client = get_bigquery_client()
        bigquery_client.query("SELECT 1").result()
        
        return {
            'status': 'healthy',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'services': {
                'redis': 'connected',
                'bigquery': 'connected'
            }
        }
        
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {
            'status': 'unhealthy',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'error': str(e)
        }


# Entry point for Cloud Functions
def main(cloud_event: Any) -> None:
    """Entry point for Cloud Functions triggered by Pub/Sub."""
    process_event(cloud_event)


# For local testing
if __name__ == "__main__":
    # Mock CloudEvent for local testing
    import base64
    
    class MockCloudEvent:
        def __init__(self, test_data: Dict[str, Any]):
            encoded_data = base64.b64encode(
                json.dumps(test_data).encode('utf-8')
            ).decode('utf-8')
            
            self.data = {
                'message': {
                    'data': encoded_data
                }
            }
    
    # Test event data
    test_event = {
        'id': 'test-event-001',
        'userId': 'user123',
        'type': 'login',
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'source': 'web',
        'metadata': {
            'ip_address': '192.168.1.1',
            'user_agent': 'Mozilla/5.0...'
        }
    }
    
    # Process test event
    mock_event = MockCloudEvent(test_event)
    main(mock_event)