import json
import logging
import os
import time
import pandas as pd
import numpy as np
from google.cloud import logging as cloud_logging
from google.cloud import storage
from google.cloud import aiplatform
import base64
import functions_framework

# Initialize clients
cloud_logging.Client().setup_logging()
storage_client = storage.Client()
logger = logging.getLogger(__name__)

@functions_framework.cloud_event
def process_bias_alert(cloud_event):
    """Process model monitoring alerts for bias detection."""
    try:
        # Decode Pub/Sub message
        data = json.loads(base64.b64decode(cloud_event.data['message']['data']))
        
        logger.info(f"Processing bias alert: {data}")
        
        # Extract monitoring information
        model_name = data.get('model_name', 'unknown')
        drift_metric = data.get('drift_metric', 0.0)
        alert_type = data.get('alert_type', 'unknown')
        
        # Calculate bias metrics
        bias_scores = calculate_bias_metrics(data)
        
        # Generate bias report
        report = {
            'timestamp': data.get('timestamp'),
            'model_name': model_name,
            'drift_metric': drift_metric,
            'alert_type': alert_type,
            'bias_scores': bias_scores,
            'fairness_violations': identify_violations(bias_scores),
            'recommendations': generate_recommendations(bias_scores)
        }
        
        # Log bias analysis results
        log_bias_analysis(report)
        
        # Store detailed report in Cloud Storage
        store_bias_report(report)
        
        return {"status": "success", "bias_score": bias_scores.get('demographic_parity', 0.0)}
        
    except Exception as e:
        logger.error(f"Error processing bias alert: {str(e)}")
        return {"status": "error", "message": str(e)}

def calculate_bias_metrics(data):
    """Calculate various bias and fairness metrics."""
    # Simulate bias calculation - in production, use actual prediction data
    np.random.seed(42)
    
    # Mock demographic parity calculation
    demographic_parity = abs(np.random.normal(0.1, 0.05))
    
    # Mock equalized odds calculation
    equalized_odds = abs(np.random.normal(0.08, 0.03))
    
    # Mock calibration metric
    calibration_score = abs(np.random.normal(0.06, 0.02))
    
    return {
        'demographic_parity': round(demographic_parity, 4),
        'equalized_odds': round(equalized_odds, 4),
        'calibration': round(calibration_score, 4),
        'overall_bias_score': round((demographic_parity + equalized_odds + calibration_score) / 3, 4)
    }

def identify_violations(bias_scores):
    """Identify fairness violations based on thresholds."""
    violations = []
    
    if bias_scores['demographic_parity'] > 0.1:
        violations.append('Demographic parity violation detected')
    
    if bias_scores['equalized_odds'] > 0.1:
        violations.append('Equalized odds violation detected')
        
    if bias_scores['calibration'] > 0.05:
        violations.append('Calibration bias detected')
    
    return violations

def generate_recommendations(bias_scores):
    """Generate actionable recommendations for bias mitigation."""
    recommendations = []
    
    if bias_scores['demographic_parity'] > 0.1:
        recommendations.append('Consider rebalancing training data across demographic groups')
    
    if bias_scores['equalized_odds'] > 0.1:
        recommendations.append('Review feature selection for protected attributes')
        
    if bias_scores['overall_bias_score'] > 0.1:
        recommendations.append('Implement bias correction post-processing techniques')
    
    return recommendations

def log_bias_analysis(report):
    """Log bias analysis for compliance and auditing."""
    logger.info(f"BIAS_ANALYSIS: {json.dumps(report)}")

def store_bias_report(report):
    """Store detailed bias report in Cloud Storage."""
    bucket_name = os.environ.get('BUCKET_NAME')
    if bucket_name:
        bucket = storage_client.bucket(bucket_name)
        timestamp = report['timestamp'].replace(':', '-')
        blob_name = f"reports/bias-analysis-{timestamp}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(report, indent=2))
        logger.info(f"Bias report stored: {blob_name}")