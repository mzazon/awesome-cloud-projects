import os
import time
import json
import psutil
import logging
from flask import Flask, request, jsonify
from google.cloud import monitoring_v3
from datetime import datetime
import numpy as np

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize monitoring client
monitoring_client = monitoring_v3.MetricServiceClient()
project_id = os.environ.get('GOOGLE_CLOUD_PROJECT', 'default-project')

@app.route('/')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'ai-inference',
        'timestamp': datetime.utcnow().isoformat()
    })

@app.route('/infer', methods=['POST'])
def process_inference():
    """AI inference endpoint that simulates GPU workload"""
    start_time = time.time()
    
    try:
        # Get request data
        data = request.get_json() or {}
        model_type = data.get('model', 'default')
        complexity = data.get('complexity', 'medium')
        
        # Simulate GPU-intensive processing
        processing_time = simulate_gpu_inference(complexity)
        
        # Record metrics
        record_inference_metrics(processing_time, model_type)
        
        # Generate response
        result = {
            'status': 'success',
            'model': model_type,
            'processing_time': processing_time,
            'complexity': complexity,
            'inference_id': f"inf_{int(time.time())}_{hash(str(data)) % 10000}",
            'timestamp': datetime.utcnow().isoformat()
        }
        
        logger.info(f"Inference completed: {result['inference_id']} in {processing_time:.2f}s")
        return jsonify(result)
        
    except Exception as e:
        logger.error(f"Inference failed: {str(e)}")
        return jsonify({
            'status': 'error',
            'message': str(e),
            'timestamp': datetime.utcnow().isoformat()
        }), 500

def simulate_gpu_inference(complexity: str) -> float:
    """Simulate GPU inference processing with variable load"""
    complexity_multipliers = {
        'low': 0.5,
        'medium': 1.0,
        'high': 2.0,
        'extreme': 4.0
    }
    
    base_time = 0.1  # Base processing time
    multiplier = complexity_multipliers.get(complexity, 1.0)
    
    # Simulate variable processing load
    processing_time = base_time * multiplier * (1 + np.random.uniform(0, 0.5))
    
    # Simulate actual computation
    time.sleep(processing_time)
    
    return processing_time

def record_inference_metrics(processing_time: float, model_type: str):
    """Record custom metrics to Cloud Monitoring"""
    try:
        # Create custom metric for inference latency
        series = monitoring_v3.TimeSeries()
        series.metric.type = 'custom.googleapis.com/ai_inference/latency'
        series.resource.type = 'cloud_run_revision'
        series.resource.labels['service_name'] = os.environ.get('K_SERVICE', 'ai-inference')
        series.resource.labels['revision_name'] = os.environ.get('K_REVISION', 'unknown')
        series.resource.labels['location'] = os.environ.get('GOOGLE_CLOUD_REGION', 'us-central1')
        
        # Add metric labels
        series.metric.labels['model_type'] = model_type
        series.metric.labels['service'] = 'ai-inference'
        
        # Create data point
        point = monitoring_v3.Point()
        point.value.double_value = processing_time
        now = time.time()
        point.interval.end_time.seconds = int(now)
        point.interval.end_time.nanos = int((now - int(now)) * 10**9)
        series.points = [point]
        
        # Send metric (would work in actual Cloud Run environment)
        logger.info(f"Recording metric: latency={processing_time:.3f}s, model={model_type}")
        
    except Exception as e:
        logger.error(f"Failed to record metrics: {str(e)}")

@app.route('/metrics')
def get_metrics():
    """Endpoint to expose current resource utilization"""
    try:
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        
        metrics = {
            'cpu_utilization': cpu_percent,
            'memory_utilization': memory.percent,
            'memory_available_gb': memory.available / (1024**3),
            'timestamp': datetime.utcnow().isoformat()
        }
        
        return jsonify(metrics)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8080))
    app.run(host='0.0.0.0', port=port, debug=False)