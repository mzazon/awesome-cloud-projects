# Infrastructure Anomaly Detection with Cloud Monitoring and Gemini
# Cloud Function source code for AI-powered anomaly analysis

import functions_framework
import json
import base64
from google.cloud import aiplatform
from google.cloud import monitoring_v3
from datetime import datetime, timedelta
import logging
import os
import traceback

# Initialize Vertex AI with template variables
PROJECT_ID = "${project_id}"
REGION = "${region}"
GEMINI_MODEL = "${gemini_model}"

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Vertex AI
aiplatform.init(project=PROJECT_ID, location=REGION)

@functions_framework.cloud_event
def analyze_anomaly(cloud_event):
    """
    Analyze monitoring data for anomalies using Gemini AI.
    
    This function processes Pub/Sub messages containing monitoring data,
    analyzes them using Gemini AI for anomaly detection, and triggers
    appropriate alerts based on the analysis results.
    
    Args:
        cloud_event: CloudEvent containing Pub/Sub message data
        
    Returns:
        dict: Status and analysis results
    """
    
    try:
        # Decode Pub/Sub message
        if not cloud_event.data or "message" not in cloud_event.data:
            logger.error("Invalid cloud event data structure")
            return {"status": "error", "message": "Invalid event data"}
            
        message_data = base64.b64decode(cloud_event.data["message"]["data"]).decode()
        logger.info(f"Received monitoring data: {message_data}")
        
        # Parse monitoring data
        try:
            monitoring_data = json.loads(message_data)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse monitoring data as JSON: {e}")
            return {"status": "error", "message": "Invalid JSON format"}
        
        # Extract metric information with defaults
        metric_name = monitoring_data.get('metric_name', 'unknown')
        metric_value = monitoring_data.get('value', 0)
        resource_name = monitoring_data.get('resource', 'unknown')
        timestamp = monitoring_data.get('timestamp', datetime.now().isoformat())
        alert_context = monitoring_data.get('alert_context', '')
        
        logger.info(f"Processing metric: {metric_name}, value: {metric_value}, resource: {resource_name}")
        
        # Get historical data for context
        historical_context = get_historical_metrics(metric_name, resource_name)
        
        # Prepare detailed prompt for Gemini analysis
        analysis_prompt = f"""
        You are an expert infrastructure monitoring analyst. Analyze this monitoring data for anomalies:
        
        CURRENT METRICS:
        - Metric Name: {metric_name}
        - Current Value: {metric_value}
        - Resource: {resource_name}
        - Timestamp: {timestamp}
        - Context: {alert_context}
        
        HISTORICAL CONTEXT:
        {historical_context}
        
        ANALYSIS REQUIREMENTS:
        Please provide a comprehensive analysis including:
        1. Anomaly Probability (0-100%): How likely this represents an anomaly
        2. Severity Level: Low, Medium, High, or Critical
        3. Potential Root Causes: List 2-3 most likely causes
        4. Recommended Actions: Specific steps to investigate or remediate
        5. Business Impact: Potential impact on operations
        6. Confidence Level: How confident you are in this assessment (0-100%)
        
        RESPONSE FORMAT:
        Respond in valid JSON format with these exact keys:
        {{
            "anomaly_probability": <number 0-100>,
            "severity": "<Low|Medium|High|Critical>",
            "root_causes": ["cause1", "cause2", "cause3"],
            "recommended_actions": ["action1", "action2", "action3"],
            "business_impact": "<description>",
            "confidence_level": <number 0-100>,
            "analysis_summary": "<brief summary>"
        }}
        
        Consider factors like:
        - Normal operating ranges for this metric type
        - Time of day patterns
        - Resource type and expected behavior
        - Correlation with other potential issues
        """
        
        # Call Gemini for analysis
        try:
            from vertexai.generative_models import GenerativeModel, GenerationConfig
            
            # Configure generation parameters for consistent JSON output
            generation_config = GenerationConfig(
                temperature=0.1,  # Low temperature for consistent analysis
                top_p=0.8,
                top_k=40,
                max_output_tokens=1024,
            )
            
            model = GenerativeModel(GEMINI_MODEL)
            response = model.generate_content(
                analysis_prompt,
                generation_config=generation_config
            )
            
            analysis_result = response.text
            logger.info(f"Gemini analysis completed: {analysis_result}")
            
        except Exception as e:
            logger.error(f"Error calling Gemini API: {e}")
            # Provide fallback analysis
            analysis_result = create_fallback_analysis(metric_name, metric_value, resource_name)
        
        # Parse and validate AI response
        try:
            ai_analysis = json.loads(analysis_result)
            
            # Validate required fields
            required_fields = ['anomaly_probability', 'severity', 'root_causes', 'recommended_actions', 'business_impact', 'confidence_level']
            for field in required_fields:
                if field not in ai_analysis:
                    logger.warning(f"Missing required field in AI analysis: {field}")
                    ai_analysis[field] = get_default_value(field)
            
            # Validate anomaly probability range
            anomaly_probability = ai_analysis.get('anomaly_probability', 0)
            if not isinstance(anomaly_probability, (int, float)) or anomaly_probability < 0 or anomaly_probability > 100:
                anomaly_probability = 0
                ai_analysis['anomaly_probability'] = 0
                
        except json.JSONDecodeError:
            logger.warning("Could not parse AI response as JSON, creating fallback analysis")
            ai_analysis = create_fallback_analysis(metric_name, metric_value, resource_name)
            anomaly_probability = ai_analysis.get('anomaly_probability', 0)
        
        # Determine if alert should be triggered
        should_alert = anomaly_probability > 70 and ai_analysis.get('confidence_level', 0) > 60
        
        if should_alert:
            logger.info(f"HIGH CONFIDENCE ANOMALY DETECTED: {anomaly_probability}% probability")
            send_alert(ai_analysis, monitoring_data)
        else:
            logger.info(f"Normal operation detected: {anomaly_probability}% anomaly probability")
        
        # Log analysis results for monitoring dashboard
        log_analysis_metrics(ai_analysis, monitoring_data)
        
        return {
            "status": "success",
            "analysis": ai_analysis,
            "alert_triggered": should_alert,
            "timestamp": datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error in anomaly analysis: {str(e)}")
        logger.error(f"Stack trace: {traceback.format_exc()}")
        return {
            "status": "error",
            "message": str(e),
            "timestamp": datetime.now().isoformat()
        }

def get_historical_metrics(metric_name, resource_name):
    """
    Retrieve historical metric data for context analysis.
    
    Args:
        metric_name: Name of the metric to analyze
        resource_name: Name of the resource being monitored
        
    Returns:
        str: Formatted historical context for AI analysis
    """
    try:
        client = monitoring_v3.MetricServiceClient()
        project_name = f"projects/{PROJECT_ID}"
        
        # Define time range (last 24 hours)
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        # Convert to timestamp format
        from google.protobuf.timestamp_pb2 import Timestamp
        
        interval = monitoring_v3.TimeInterval()
        interval.end_time = Timestamp()
        interval.end_time.FromDatetime(end_time)
        interval.start_time = Timestamp()
        interval.start_time.FromDatetime(start_time)
        
        # Build metric filter
        filter_str = f'metric.type="{metric_name}" AND resource.labels.instance_name="{resource_name}"'
        
        # Query historical data
        request = monitoring_v3.ListTimeSeriesRequest(
            name=project_name,
            filter=filter_str,
            interval=interval,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        )
        
        try:
            results = client.list_time_series(request=request)
            
            # Process results for context
            data_points = []
            for result in results:
                for point in result.points:
                    data_points.append({
                        'timestamp': point.interval.end_time.ToDatetime().isoformat(),
                        'value': point.value.double_value or point.value.int64_value
                    })
            
            if data_points:
                # Calculate statistics
                values = [dp['value'] for dp in data_points]
                avg_value = sum(values) / len(values)
                min_value = min(values)
                max_value = max(values)
                
                return f"""
                Historical Data Summary (Last 24 hours):
                - Data Points: {len(data_points)}
                - Average Value: {avg_value:.2f}
                - Min Value: {min_value:.2f}
                - Max Value: {max_value:.2f}
                - Recent Trend: {"Increasing" if len(values) > 1 and values[-1] > values[-2] else "Stable/Decreasing"}
                """
            else:
                return "No historical data available for this metric and resource."
                
        except Exception as e:
            logger.warning(f"Error querying historical metrics: {e}")
            return f"Unable to retrieve historical data: {str(e)}"
            
    except Exception as e:
        logger.error(f"Error in get_historical_metrics: {e}")
        return f"Historical data unavailable due to error: {str(e)}"

def create_fallback_analysis(metric_name, metric_value, resource_name):
    """
    Create fallback analysis when Gemini API is unavailable.
    
    Args:
        metric_name: Name of the metric
        metric_value: Current metric value
        resource_name: Resource name
        
    Returns:
        dict: Fallback analysis results
    """
    # Simple rule-based fallback analysis
    anomaly_probability = 0
    severity = "Low"
    
    # Basic threshold-based analysis
    if "cpu" in metric_name.lower():
        if metric_value > 0.9:
            anomaly_probability = 85
            severity = "High"
        elif metric_value > 0.8:
            anomaly_probability = 60
            severity = "Medium"
        elif metric_value > 0.7:
            anomaly_probability = 30
            severity = "Low"
    
    elif "memory" in metric_name.lower():
        if metric_value > 0.95:
            anomaly_probability = 80
            severity = "High"
        elif metric_value > 0.85:
            anomaly_probability = 50
            severity = "Medium"
    
    return {
        "anomaly_probability": anomaly_probability,
        "severity": severity,
        "root_causes": ["High resource utilization", "Increased workload", "Potential resource contention"],
        "recommended_actions": ["Monitor resource usage", "Check for unusual processes", "Consider scaling resources"],
        "business_impact": "Potential performance degradation if trend continues",
        "confidence_level": 50,
        "analysis_summary": f"Fallback analysis for {metric_name} on {resource_name}",
        "analysis_type": "fallback"
    }

def get_default_value(field):
    """Get default value for missing analysis fields."""
    defaults = {
        'anomaly_probability': 0,
        'severity': 'Low',
        'root_causes': ['Unknown'],
        'recommended_actions': ['Monitor situation'],
        'business_impact': 'Unknown impact',
        'confidence_level': 0
    }
    return defaults.get(field, 'Unknown')

def send_alert(ai_analysis, monitoring_data):
    """
    Send alert based on AI analysis results.
    
    Args:
        ai_analysis: AI analysis results
        monitoring_data: Original monitoring data
    """
    severity = ai_analysis.get('severity', 'Unknown')
    anomaly_probability = ai_analysis.get('anomaly_probability', 0)
    
    alert_message = {
        "alert_type": "infrastructure_anomaly",
        "severity": severity,
        "anomaly_probability": anomaly_probability,
        "metric": monitoring_data.get('metric_name', 'unknown'),
        "resource": monitoring_data.get('resource', 'unknown'),
        "current_value": monitoring_data.get('value', 0),
        "ai_analysis": ai_analysis,
        "timestamp": datetime.now().isoformat(),
        "project_id": PROJECT_ID
    }
    
    # Log structured alert for monitoring systems
    logger.info(f"ALERT: {severity} anomaly detected", extra={
        "alert_data": alert_message,
        "structured_log": True
    })
    
    # In production, integrate with notification systems like:
    # - Send to Slack/Teams webhook
    # - Create incident in PagerDuty
    # - Send email via SendGrid
    # - Create support ticket
    
    print(f"🚨 INFRASTRUCTURE ANOMALY ALERT 🚨")
    print(f"Severity: {severity}")
    print(f"Probability: {anomaly_probability}%")
    print(f"Resource: {monitoring_data.get('resource', 'unknown')}")
    print(f"Metric: {monitoring_data.get('metric_name', 'unknown')}")
    print(f"AI Analysis: {ai_analysis.get('analysis_summary', 'No summary')}")

def log_analysis_metrics(ai_analysis, monitoring_data):
    """
    Log analysis metrics for monitoring dashboard.
    
    Args:
        ai_analysis: AI analysis results
        monitoring_data: Original monitoring data
    """
    # Create structured log entry for monitoring dashboard
    metric_entry = {
        "anomaly_score": ai_analysis.get('anomaly_probability', 0),
        "confidence_score": ai_analysis.get('confidence_level', 0),
        "severity": ai_analysis.get('severity', 'Unknown'),
        "metric_name": monitoring_data.get('metric_name', 'unknown'),
        "resource": monitoring_data.get('resource', 'unknown'),
        "timestamp": datetime.now().isoformat()
    }
    
    # Log as structured data for metrics extraction
    logger.info("ANOMALY_METRICS", extra={
        "anomaly_metrics": metric_entry,
        "structured_log": True
    })