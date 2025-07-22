import json
import logging
from google.cloud import bigquery
from google.cloud import monitoring_v3
import datetime
import os

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def route_traffic(request):
    """
    Intelligent traffic routing based on real-time analytics
    
    This function analyzes recent performance metrics from BigQuery
    and makes intelligent routing decisions based on:
    - Average response times
    - Request counts
    - Service health status
    - AI confidence scoring
    """
    
    try:
        # Extract request metadata
        request_data = request.get_json() if request.get_json() else {}
        source_ip = request_data.get('source_ip', request.environ.get('REMOTE_ADDR', 'unknown'))
        user_agent = request_data.get('user_agent', request.headers.get('User-Agent', ''))
        request_size = request_data.get('request_size', 0)
        
        # Get environment variables
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        dataset_name = os.environ.get('DATASET_NAME', '${dataset_name}')
        
        logger.info(f"Processing routing request from {source_ip}")
        
        # Initialize BigQuery client
        client = bigquery.Client(project=project_id)
        
        # Query recent performance metrics to make intelligent routing decisions
        query = f"""
        SELECT 
            target_service,
            AVG(response_time) as avg_response_time,
            COUNT(*) as request_count,
            AVG(CASE WHEN status_code BETWEEN 200 AND 299 THEN 1 ELSE 0 END) as success_rate,
            STDDEV(response_time) as response_time_stddev
        FROM `{project_id}.{dataset_name}.lb_metrics`
        WHERE timestamp >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 5 MINUTE)
        GROUP BY target_service
        HAVING COUNT(*) >= 3  -- Ensure minimum sample size
        ORDER BY 
            success_rate DESC,
            avg_response_time ASC
        LIMIT 5
        """
        
        # Execute query with timeout
        job_config = bigquery.QueryJobConfig()
        job_config.use_query_cache = True
        query_job = client.query(query, job_config=job_config)
        
        # Get results with timeout
        results = list(query_job.result(timeout=10))
        
        # Determine optimal service based on performance metrics
        if results and len(results) > 0:
            # Select best performing service
            best_service = results[0].target_service
            avg_response_time = float(results[0].avg_response_time or 0)
            success_rate = float(results[0].success_rate or 0)
            
            # Calculate confidence score based on performance metrics
            # Higher success rate and lower response time = higher confidence
            confidence = min(0.95, (success_rate * 0.7) + ((2.0 - min(avg_response_time, 2.0)) / 2.0 * 0.3))
            
            ai_reasoning = f"Selected {best_service} based on {success_rate:.1%} success rate and {avg_response_time:.3f}s avg response time"
            
        else:
            # Default routing logic when no recent metrics available
            logger.info("No recent metrics available, using default routing")
            
            # Simple load balancing based on request characteristics
            if 'fast' in request.path.lower() or request_size < 1000:
                best_service = "service-a"
                ai_reasoning = "Routed to fast service based on path or small request size"
            elif 'intensive' in request.path.lower() or request_size > 10000:
                best_service = "service-c"
                ai_reasoning = "Routed to intensive service based on path or large request size"
            else:
                best_service = "service-b"
                ai_reasoning = "Routed to standard service as default"
            
            confidence = 0.6  # Medium confidence for rule-based routing
        
        # Generate unique decision ID
        decision_id = f"dec_{datetime.datetime.utcnow().strftime('%Y%m%d_%H%M%S_%f')}"
        
        # Prepare routing decision data for BigQuery
        decision_data = {
            'timestamp': datetime.datetime.utcnow().isoformat(),
            'decision_id': decision_id,
            'source_criteria': f"ip:{source_ip},size:{request_size},ua:{user_agent[:50]}",
            'target_service': best_service,
            'confidence_score': confidence,
            'ai_reasoning': ai_reasoning
        }
        
        # Insert routing decision into BigQuery (async)
        try:
            table_id = f"{project_id}.{dataset_name}.routing_decisions"
            table = client.get_table(table_id)
            errors = client.insert_rows_json(table, [decision_data])
            
            if errors:
                logger.warning(f"BigQuery insert errors: {errors}")
            else:
                logger.info(f"Routing decision logged: {decision_id}")
                
        except Exception as bq_error:
            logger.error(f"Failed to log routing decision: {bq_error}")
            # Continue with routing even if logging fails
        
        # Return routing decision
        response_data = {
            'target_service': best_service,
            'confidence': confidence,
            'decision_id': decision_id,
            'routing_metadata': {
                'ai_reasoning': ai_reasoning,
                'timestamp': decision_data['timestamp'],
                'source_criteria': decision_data['source_criteria']
            },
            'status': 'success'
        }
        
        logger.info(f"Routing decision: {best_service} (confidence: {confidence:.2f})")
        
        return json.dumps(response_data), 200, {'Content-Type': 'application/json'}
        
    except bigquery.exceptions.NotFound as e:
        logger.error(f"BigQuery table not found: {e}")
        return json.dumps({
            'target_service': 'service-a',
            'confidence': 0.3,
            'error': 'Analytics data not available',
            'status': 'fallback'
        }), 200, {'Content-Type': 'application/json'}
        
    except Exception as e:
        logger.error(f"Routing error: {e}")
        
        # Fallback routing logic
        fallback_service = 'service-a'  # Default to fastest service
        
        return json.dumps({
            'target_service': fallback_service,
            'confidence': 0.2,
            'error': str(e),
            'status': 'error_fallback',
            'ai_reasoning': 'Error occurred, using fallback routing to primary service'
        }), 200, {'Content-Type': 'application/json'}

def health_check(request):
    """Health check endpoint for the Cloud Function"""
    return json.dumps({
        'status': 'healthy',
        'timestamp': datetime.datetime.utcnow().isoformat(),
        'service': 'traffic-router'
    }), 200, {'Content-Type': 'application/json'}