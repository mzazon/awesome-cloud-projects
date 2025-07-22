"""
Multi-tier Content Caching Lambda Function

This Lambda function demonstrates the cache-aside pattern by integrating
with ElastiCache Redis for application-level caching. It serves as the 
compute bridge between API Gateway and ElastiCache, implementing intelligent
caching logic with automatic fallback to simulated database queries.

Environment Variables:
- REDIS_ENDPOINT: ElastiCache Redis cluster endpoint
- REDIS_PORT: Redis port (default: 6379)
- TTL_SECONDS: Time-to-live for cached data
"""

import json
import redis
import time
import os
import logging
from datetime import datetime, timezone
from typing import Dict, Any, Optional

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment configuration
REDIS_ENDPOINT = os.environ.get('REDIS_ENDPOINT', 'localhost')
REDIS_PORT = int(os.environ.get('REDIS_PORT', '6379'))
TTL_SECONDS = int(os.environ.get('TTL_SECONDS', '${elasticache_ttl}'))

# Redis connection (reused across invocations)
redis_client = None

def get_redis_connection() -> Optional[redis.Redis]:
    """
    Get Redis connection with connection pooling and error handling.
    Returns None if connection fails.
    """
    global redis_client
    
    if redis_client is None:
        try:
            redis_client = redis.Redis(
                host=REDIS_ENDPOINT,
                port=REDIS_PORT,
                decode_responses=True,
                socket_connect_timeout=5,
                socket_timeout=5,
                retry_on_timeout=True,
                health_check_interval=30
            )
            # Test connection
            redis_client.ping()
            logger.info(f"Successfully connected to Redis at {REDIS_ENDPOINT}:{REDIS_PORT}")
        except Exception as e:
            logger.error(f"Failed to connect to Redis: {str(e)}")
            redis_client = None
    
    return redis_client

def simulate_database_query(query_complexity: str = "simple") -> Dict[str, Any]:
    """
    Simulate a database query with realistic response times.
    In a real application, this would be actual database operations.
    """
    # Simulate different query complexities
    complexity_delays = {
        "simple": 0.05,    # 50ms
        "medium": 0.1,     # 100ms  
        "complex": 0.2,    # 200ms
        "heavy": 0.5       # 500ms
    }
    
    delay = complexity_delays.get(query_complexity, 0.1)
    time.sleep(delay)
    
    # Generate realistic sample data
    sample_data = {
        "user_id": "user_12345",
        "session_data": {
            "preferences": {
                "theme": "dark",
                "language": "en-US",
                "notifications": True
            },
            "last_activity": datetime.now(timezone.utc).isoformat(),
            "session_duration": "45 minutes"
        },
        "product_recommendations": [
            {"id": "prod_001", "name": "Premium Widget", "score": 0.95},
            {"id": "prod_002", "name": "Deluxe Gadget", "score": 0.87},
            {"id": "prod_003", "name": "Standard Tool", "score": 0.76}
        ],
        "analytics": {
            "page_views": 127,
            "cart_items": 3,
            "conversion_probability": 0.34
        },
        "query_metadata": {
            "complexity": query_complexity,
            "simulated_delay_ms": int(delay * 1000),
            "generated_at": datetime.now(timezone.utc).isoformat()
        }
    }
    
    return sample_data

def lambda_handler(event, context) -> Dict[str, Any]:
    """
    AWS Lambda handler implementing cache-aside pattern.
    
    Flow:
    1. Check ElastiCache for cached data
    2. If cache hit, return cached data with metadata
    3. If cache miss, query "database" (simulated)
    4. Store result in cache with TTL
    5. Return response with caching headers for CloudFront
    """
    
    try:
        # Extract request information
        request_id = context.aws_request_id
        query_params = event.get('queryStringParameters') or {}
        cache_key = f"demo_data:{query_params.get('key', 'default')}"
        complexity = query_params.get('complexity', 'simple')
        
        logger.info(f"Processing request {request_id} with cache key: {cache_key}")
        
        # Performance tracking
        start_time = time.time()
        cache_hit = False
        data_source = "Database"
        cache_status = "miss"
        
        # Try to get Redis connection
        r = get_redis_connection()
        cached_data = None
        
        if r is not None:
            try:
                # Check cache first (cache-aside pattern)
                cached_data = r.get(cache_key)
                if cached_data:
                    cache_hit = True
                    data_source = "ElastiCache"
                    cache_status = "hit"
                    logger.info(f"Cache hit for key: {cache_key}")
            except Exception as e:
                logger.warning(f"Cache read error: {str(e)}")
                # Continue without cache - graceful degradation
        
        # Prepare response data
        if cached_data:
            # Parse cached data and add cache metadata
            data = json.loads(cached_data)
            data.update({
                'cache_hit': True,
                'source': data_source,
                'cache_key': cache_key,
                'served_from_cache_at': datetime.now(timezone.utc).isoformat()
            })
        else:
            # Cache miss - query database and populate cache
            logger.info(f"Cache miss for key: {cache_key}, querying database")
            
            # Simulate database query
            db_start = time.time()
            db_data = simulate_database_query(complexity)
            db_duration = time.time() - db_start
            
            # Prepare response data
            data = {
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'request_id': request_id,
                'message': f'Data retrieved from {data_source}',
                'cache_hit': False,
                'source': data_source,
                'cache_key': cache_key,
                'database_query_time_ms': round(db_duration * 1000, 2),
                'data': db_data
            }
            
            # Try to cache the result
            if r is not None:
                try:
                    cache_data = json.dumps(data)
                    r.setex(cache_key, TTL_SECONDS, cache_data)
                    logger.info(f"Data cached with TTL {TTL_SECONDS}s for key: {cache_key}")
                except Exception as e:
                    logger.warning(f"Cache write error: {str(e)}")
                    # Continue without caching - graceful degradation
        
        # Calculate total response time
        total_time = time.time() - start_time
        
        # Add performance metadata
        data.update({
            'performance': {
                'total_response_time_ms': round(total_time * 1000, 2),
                'cache_status': cache_status,
                'redis_connected': r is not None,
                'ttl_seconds': TTL_SECONDS
            },
            'lambda_context': {
                'function_name': context.function_name,
                'function_version': context.function_version,
                'memory_limit': context.memory_limit_in_mb,
                'remaining_time_ms': context.get_remaining_time_in_millis()
            }
        })
        
        # Determine appropriate Cache-Control header based on data freshness
        if cache_hit:
            # Data is from cache, allow CloudFront to cache for shorter time
            cache_control = f"public, max-age=60, stale-while-revalidate=30"
        else:
            # Fresh data from database, allow longer CloudFront caching
            cache_control = f"public, max-age=90, stale-while-revalidate=60"
        
        # Return response with appropriate caching headers
        response = {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': cache_control,
                'X-Cache-Status': cache_status,
                'X-Data-Source': data_source,
                'X-Request-ID': request_id,
                'X-Lambda-Function': context.function_name,
                # CORS headers for browser requests
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key',
                'Access-Control-Allow-Methods': 'GET,POST,OPTIONS'
            },
            'body': json.dumps(data, default=str)
        }
        
        logger.info(f"Request {request_id} completed in {total_time*1000:.2f}ms, cache_hit: {cache_hit}")
        return response
        
    except Exception as e:
        # Error handling with detailed logging
        error_details = {
            'error': str(e),
            'error_type': type(e).__name__,
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'request_id': getattr(context, 'aws_request_id', 'unknown'),
            'function_name': getattr(context, 'function_name', 'unknown')
        }
        
        logger.error(f"Lambda execution error: {error_details}")
        
        return {
            'statusCode': 500,
            'headers': {
                'Content-Type': 'application/json',
                'Cache-Control': 'no-cache, no-store, must-revalidate',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'message': 'Internal server error',
                'error_details': error_details,
                'troubleshooting': {
                    'check_elasticache': 'Verify ElastiCache cluster is running and accessible',
                    'check_network': 'Ensure Lambda has VPC access to ElastiCache',
                    'check_security_groups': 'Verify security group allows Redis traffic'
                }
            })
        }