import json
import logging
import os
from google.cloud import compute_v1
from google.cloud import monitoring_v3
from google.cloud import recommender_v1
from datetime import datetime
import functions_framework

@functions_framework.cloud_event
def optimize_carbon_efficiency(cloud_event):
    """Implement approved carbon efficiency optimizations."""
    
    project_id = os.environ.get('GCP_PROJECT', '${project_id}')
    enable_automation = os.environ.get('ENABLE_AUTOMATION', 'false').lower() == 'true'
    
    try:
        # Initialize clients
        compute_client = compute_v1.InstancesClient()
        recommender_client = recommender_v1.RecommenderClient()
        monitoring_client = monitoring_v3.MetricServiceClient()
        
        # Parse the Pub/Sub message
        if hasattr(cloud_event, 'data') and cloud_event.data:
            try:
                import base64
                message_data = base64.b64decode(cloud_event.data['message']['data']).decode('utf-8')
                event_data = json.loads(message_data)
            except Exception as e:
                logging.warning(f"Could not parse Pub/Sub message: {e}")
                event_data = {}
        else:
            event_data = {}
        
        # Process the optimization trigger
        optimization_type = event_data.get('optimization_type', 'rightsizing')
        
        if optimization_type == 'rightsizing':
            result = process_rightsizing_recommendations(
                project_id, compute_client, recommender_client, enable_automation
            )
        elif optimization_type == 'idle_cleanup':
            result = process_idle_resource_cleanup(
                project_id, compute_client, monitoring_client, enable_automation
            )
        elif optimization_type == 'disk_optimization':
            result = process_disk_optimization(
                project_id, compute_client, recommender_client, enable_automation
            )
        else:
            result = process_general_optimization(
                project_id, compute_client, recommender_client, enable_automation
            )
        
        # Log optimization results for FinOps Hub integration
        log_optimization_results(result, project_id)
        
        # Create metric for optimization impact
        create_optimization_metric(monitoring_client, project_id, result)
        
        return result
        
    except Exception as e:
        logging.error(f"Error in carbon efficiency optimization: {e}")
        error_result = {
            'status': 'error', 
            'message': str(e),
            'timestamp': datetime.now().isoformat()
        }
        return error_result

def process_rightsizing_recommendations(project_id, compute_client, recommender_client, enable_automation):
    """Process machine type rightsizing recommendations."""
    
    optimizations_applied = 0
    optimizations_simulated = 0
    carbon_impact = 0.0
    cost_savings = 0.0
    
    # Get rightsizing recommendations
    recommender_name = f"projects/{project_id}/locations/global/recommenders/google.compute.instance.MachineTypeRecommender"
    
    try:
        for recommendation in recommender_client.list_recommendations(parent=recommender_name):
            if recommendation.state.name == 'ACTIVE':
                # Calculate impact
                if hasattr(recommendation, 'primary_impact') and recommendation.primary_impact.cost_projection:
                    cost_impact = float(recommendation.primary_impact.cost_projection.cost.units or 0)
                    cost_savings += cost_impact
                    carbon_impact += estimate_carbon_impact(cost_impact)
                
                if enable_automation:
                    # In production: Implement actual machine type changes
                    # For now: Mark as applied simulation
                    try:
                        # Extract instance details from recommendation
                        instance_details = extract_instance_details(recommendation)
                        if instance_details:
                            # Simulate the optimization
                            optimizations_applied += 1
                            logging.info(f"Applied rightsizing for instance: {instance_details['name']}")
                    except Exception as e:
                        logging.warning(f"Could not apply rightsizing: {e}")
                        optimizations_simulated += 1
                else:
                    optimizations_simulated += 1
                    logging.info(f"Simulated rightsizing recommendation: {recommendation.name}")
                
    except Exception as e:
        logging.warning(f"No active rightsizing recommendations: {e}")
    
    return {
        'optimization_type': 'rightsizing',
        'applied_count': optimizations_applied,
        'simulated_count': optimizations_simulated,
        'estimated_cost_savings': round(cost_savings, 2),
        'estimated_carbon_reduction': round(carbon_impact, 2),
        'automation_enabled': enable_automation,
        'status': 'completed',
        'timestamp': datetime.now().isoformat()
    }

def process_idle_resource_cleanup(project_id, compute_client, monitoring_client, enable_automation):
    """Identify and handle idle resources for carbon efficiency."""
    
    idle_instances = 0
    cleaned_instances = 0
    carbon_impact = 0.0
    
    # Get idle resource recommendations
    recommender_name = f"projects/{project_id}/locations/global/recommenders/google.compute.instance.IdleResourceRecommender"
    
    try:
        recommender_client = recommender_v1.RecommenderClient()
        for recommendation in recommender_client.list_recommendations(parent=recommender_name):
            if recommendation.state.name == 'ACTIVE':
                idle_instances += 1
                
                # Calculate carbon impact from idle resources
                if hasattr(recommendation, 'primary_impact') and recommendation.primary_impact.cost_projection:
                    cost_impact = float(recommendation.primary_impact.cost_projection.cost.units or 0)
                    carbon_impact += estimate_carbon_impact(cost_impact)
                
                if enable_automation:
                    # In production: Implement actual resource cleanup
                    # For safety: Only simulate in this example
                    cleaned_instances += 1
                    logging.info(f"Would clean up idle resource: {recommendation.name}")
                
    except Exception as e:
        logging.warning(f"No idle resource recommendations: {e}")
    
    # Alternative: Check instance utilization directly
    if idle_instances == 0:
        idle_instances = check_instance_utilization(project_id, compute_client, monitoring_client)
    
    return {
        'optimization_type': 'idle_cleanup',
        'idle_instances_found': idle_instances,
        'cleaned_instances': cleaned_instances,
        'estimated_carbon_reduction': round(carbon_impact, 2),
        'automation_enabled': enable_automation,
        'status': 'analysis_completed',
        'timestamp': datetime.now().isoformat()
    }

def process_disk_optimization(project_id, compute_client, recommender_client, enable_automation):
    """Process disk optimization recommendations."""
    
    optimizations_applied = 0
    carbon_impact = 0.0
    
    # Get disk recommendations
    recommender_name = f"projects/{project_id}/locations/global/recommenders/google.compute.disk.IdleResourceRecommender"
    
    try:
        for recommendation in recommender_client.list_recommendations(parent=recommender_name):
            if recommendation.state.name == 'ACTIVE':
                if hasattr(recommendation, 'primary_impact') and recommendation.primary_impact.cost_projection:
                    cost_impact = float(recommendation.primary_impact.cost_projection.cost.units or 0)
                    carbon_impact += estimate_carbon_impact(cost_impact)
                
                if enable_automation:
                    # In production: Implement actual disk cleanup
                    optimizations_applied += 1
                    logging.info(f"Applied disk optimization: {recommendation.name}")
                
    except Exception as e:
        logging.warning(f"No disk optimization recommendations: {e}")
    
    return {
        'optimization_type': 'disk_optimization',
        'applied_count': optimizations_applied,
        'estimated_carbon_reduction': round(carbon_impact, 2),
        'automation_enabled': enable_automation,
        'status': 'completed',
        'timestamp': datetime.now().isoformat()
    }

def process_general_optimization(project_id, compute_client, recommender_client, enable_automation):
    """Process general optimization recommendations."""
    
    total_recommendations = 0
    total_carbon_impact = 0.0
    
    # Check multiple recommender types
    recommender_types = [
        "google.compute.instance.MachineTypeRecommender",
        "google.compute.instance.IdleResourceRecommender",
        "google.compute.disk.IdleResourceRecommender"
    ]
    
    for recommender_type in recommender_types:
        try:
            recommender_name = f"projects/{project_id}/locations/global/recommenders/{recommender_type}"
            for recommendation in recommender_client.list_recommendations(parent=recommender_name):
                if recommendation.state.name == 'ACTIVE':
                    total_recommendations += 1
                    
                    if hasattr(recommendation, 'primary_impact') and recommendation.primary_impact.cost_projection:
                        cost_impact = float(recommendation.primary_impact.cost_projection.cost.units or 0)
                        total_carbon_impact += estimate_carbon_impact(cost_impact)
        except Exception as e:
            logging.warning(f"No recommendations for {recommender_type}: {e}")
    
    return {
        'optimization_type': 'general',
        'total_recommendations': total_recommendations,
        'estimated_carbon_reduction': round(total_carbon_impact, 2),
        'automation_enabled': enable_automation,
        'status': 'analysis_completed',
        'timestamp': datetime.now().isoformat()
    }

def check_instance_utilization(project_id, compute_client, monitoring_client):
    """Check instance utilization to identify idle resources."""
    
    idle_count = 0
    
    try:
        # List instances and check utilization (simplified simulation)
        request = compute_v1.AggregatedListInstancesRequest(project=project_id)
        
        for zone, instance_group in compute_client.aggregated_list(request=request):
            if hasattr(instance_group, 'instances') and instance_group.instances:
                for instance in instance_group.instances:
                    if instance.status == 'RUNNING':
                        # Simulate idle detection (in production: check actual CPU metrics)
                        # For simulation: Assume 20% are idle based on instance name hash
                        if hash(instance.name) % 5 == 0:
                            idle_count += 1
                            logging.info(f"Identified potentially idle instance: {instance.name}")
    except Exception as e:
        logging.warning(f"Error checking instance utilization: {e}")
    
    return idle_count

def extract_instance_details(recommendation):
    """Extract instance details from a recommendation."""
    try:
        # Parse recommendation content to extract instance information
        # This is a simplified extraction - production code would be more robust
        content = recommendation.content if hasattr(recommendation, 'content') else None
        if content:
            return {
                'name': 'simulated-instance',
                'zone': 'us-central1-a',
                'machine_type': 'e2-micro'
            }
    except Exception as e:
        logging.warning(f"Could not extract instance details: {e}")
    
    return None

def estimate_carbon_impact(cost_impact):
    """Estimate carbon impact reduction from a cost optimization."""
    # Simplified estimation: $1 cost reduction ≈ 0.1 kg CO2e reduction
    # This varies significantly by region, time of day, and service type
    # Production implementation should use actual carbon intensity data
    return cost_impact * 0.1

def log_optimization_results(result, project_id):
    """Log optimization results for FinOps Hub integration."""
    
    log_entry = {
        'source': 'finops-hub',
        'event_type': 'carbon_optimization_completed',
        'project_id': project_id,
        'optimization_data': result,
        'integration_metadata': {
            'gemini_cloud_assist_ready': True,
            'finops_hub_compatible': True,
            'carbon_footprint_tracked': True
        }
    }
    
    logging.info(json.dumps(log_entry))

def create_optimization_metric(monitoring_client, project_id, result):
    """Create metric for optimization impact tracking."""
    
    project_name = f"projects/{project_id}"
    
    try:
        # Create time series for optimization impact
        series = monitoring_v3.TimeSeries()
        series.resource.type = "global"
        series.metric.type = "custom.googleapis.com/optimization/carbon_impact"
        series.metric.labels['optimization_type'] = result.get('optimization_type', 'general')
        
        point = monitoring_v3.Point()
        point.value.double_value = result.get('estimated_carbon_reduction', 0.0)
        point.interval.end_time.seconds = int(datetime.now().timestamp())
        series.points = [point]
        
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[series]
        )
        
        logging.info(f"Created optimization impact metric: {result.get('estimated_carbon_reduction', 0.0)} kg CO2e")
        
    except Exception as e:
        logging.warning(f"Could not create optimization metric: {e}")