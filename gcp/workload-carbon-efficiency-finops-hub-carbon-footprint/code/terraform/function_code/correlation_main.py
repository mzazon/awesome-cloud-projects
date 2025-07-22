import json
import logging
import os
from google.cloud import monitoring_v3
from google.cloud import billing_budgets_v1
from google.cloud import recommender_v1
from datetime import datetime, timedelta
import functions_framework

@functions_framework.http
def correlate_carbon_efficiency(request):
    """Correlate FinOps Hub utilization insights with carbon footprint data."""
    
    project_id = os.environ.get('GCP_PROJECT', '${project_id}')
    billing_account = os.environ.get('BILLING_ACCOUNT_ID', '')
    efficiency_threshold = float(os.environ.get('EFFICIENCY_THRESHOLD', '70.0'))
    
    try:
        # Initialize clients for data collection
        monitoring_client = monitoring_v3.MetricServiceClient()
        recommender_client = recommender_v1.RecommenderClient()
        
        # Get project resource name for metrics
        project_name = f"projects/{project_id}"
        
        # Collect utilization insights from Active Assist
        recommendations = []
        recommender_types = [
            "google.compute.instance.MachineTypeRecommender",
            "google.compute.instance.IdleResourceRecommender",
            "google.compute.disk.IdleResourceRecommender"
        ]
        
        for recommender_type in recommender_types:
            try:
                recommender_name = f"projects/{project_id}/locations/global/recommenders/{recommender_type}"
                for recommendation in recommender_client.list_recommendations(parent=recommender_name):
                    recommendations.append({
                        'name': recommendation.name,
                        'description': recommendation.description,
                        'priority': recommendation.priority.name if hasattr(recommendation, 'priority') else 'MEDIUM',
                        'recommender_type': recommender_type,
                        'impact': {
                            'cost': recommendation.primary_impact.cost_projection.cost.units if (
                                hasattr(recommendation, 'primary_impact') and 
                                recommendation.primary_impact.cost_projection
                            ) else 0,
                            'category': recommendation.primary_impact.category.name if (
                                hasattr(recommendation, 'primary_impact')
                            ) else 'COST'
                        }
                    })
            except Exception as e:
                logging.warning(f"No recommendations available for {recommender_type}: {e}")
        
        # Calculate carbon efficiency score based on utilization and recommendations
        efficiency_score = calculate_efficiency_score(recommendations, efficiency_threshold)
        
        # Get current resource utilization metrics
        utilization_metrics = get_utilization_metrics(monitoring_client, project_name)
        
        # Create monitoring metric for carbon efficiency
        create_efficiency_metrics(monitoring_client, project_name, efficiency_score, utilization_metrics)
        
        # Generate insights for FinOps Hub integration
        finops_insights = generate_finops_insights(recommendations, efficiency_score)
        
        result = {
            'status': 'success',
            'efficiency_score': efficiency_score,
            'recommendations_count': len(recommendations),
            'utilization_summary': utilization_metrics,
            'finops_insights': finops_insights,
            'timestamp': datetime.now().isoformat(),
            'correlation_id': f"carbon-efficiency-{int(datetime.now().timestamp())}"
        }
        
        # Log results for FinOps Hub integration
        logging.info(json.dumps({
            'source': 'finops-hub',
            'event_type': 'carbon_efficiency_analysis',
            'data': result
        }))
        
        return json.dumps(result)
        
    except Exception as e:
        logging.error(f"Error in carbon efficiency correlation: {e}")
        return json.dumps({
            'status': 'error', 
            'message': str(e),
            'timestamp': datetime.now().isoformat()
        }), 500

def calculate_efficiency_score(recommendations, threshold):
    """Calculate carbon efficiency score based on recommendations and utilization."""
    if not recommendations:
        return 85.0  # Default score when no recommendations
    
    # Base score starts at 100
    base_score = 100.0
    
    # Calculate penalty based on recommendation severity and count
    high_priority_count = len([r for r in recommendations if r['priority'] == 'HIGH'])
    medium_priority_count = len([r for r in recommendations if r['priority'] == 'MEDIUM'])
    
    # Higher penalty for high-priority recommendations
    penalty = (high_priority_count * 5) + (medium_priority_count * 2)
    
    # Additional penalty for cost impact
    total_cost_impact = sum(float(r['impact']['cost']) for r in recommendations)
    cost_penalty = min(total_cost_impact / 100, 20)  # Cap at 20 points
    
    final_score = max(base_score - penalty - cost_penalty, 10.0)  # Minimum score of 10
    
    return round(final_score, 2)

def get_utilization_metrics(monitoring_client, project_name):
    """Get current resource utilization metrics."""
    try:
        # Define time range for metrics (last 24 hours)
        end_time = datetime.now()
        start_time = end_time - timedelta(hours=24)
        
        interval = monitoring_v3.TimeInterval({
            "end_time": {"seconds": int(end_time.timestamp())},
            "start_time": {"seconds": int(start_time.timestamp())}
        })
        
        # Query CPU utilization for compute instances
        cpu_filter = 'metric.type="compute.googleapis.com/instance/cpu/utilization" resource.type="gce_instance"'
        
        request = monitoring_v3.ListTimeSeriesRequest(
            name=project_name,
            filter=cpu_filter,
            interval=interval,
            view=monitoring_v3.ListTimeSeriesRequest.TimeSeriesView.FULL
        )
        
        results = monitoring_client.list_time_series(request=request)
        
        cpu_utilizations = []
        for result in results:
            if result.points:
                avg_cpu = sum(point.value.double_value for point in result.points) / len(result.points)
                cpu_utilizations.append(avg_cpu)
        
        avg_cpu_utilization = sum(cpu_utilizations) / len(cpu_utilizations) if cpu_utilizations else 0.0
        
        return {
            'average_cpu_utilization': round(avg_cpu_utilization * 100, 2),  # Convert to percentage
            'monitored_instances': len(cpu_utilizations),
            'low_utilization_instances': len([u for u in cpu_utilizations if u < 0.20]),  # < 20% utilization
            'collection_period': '24h'
        }
        
    except Exception as e:
        logging.warning(f"Could not retrieve utilization metrics: {e}")
        return {
            'average_cpu_utilization': 0.0,
            'monitored_instances': 0,
            'low_utilization_instances': 0,
            'collection_period': '24h'
        }

def create_efficiency_metrics(monitoring_client, project_name, efficiency_score, utilization_metrics):
    """Create custom metrics for carbon efficiency tracking."""
    try:
        # Create efficiency score metric
        efficiency_series = monitoring_v3.TimeSeries()
        efficiency_series.resource.type = "global"
        efficiency_series.metric.type = "custom.googleapis.com/carbon_efficiency/score"
        
        efficiency_point = monitoring_v3.Point()
        efficiency_point.value.double_value = efficiency_score
        efficiency_point.interval.end_time.seconds = int(datetime.now().timestamp())
        efficiency_series.points = [efficiency_point]
        
        monitoring_client.create_time_series(
            name=project_name,
            time_series=[efficiency_series]
        )
        
        # Create utilization metric
        if utilization_metrics['monitored_instances'] > 0:
            util_series = monitoring_v3.TimeSeries()
            util_series.resource.type = "global"
            util_series.metric.type = "custom.googleapis.com/carbon_efficiency/utilization"
            
            util_point = monitoring_v3.Point()
            util_point.value.double_value = utilization_metrics['average_cpu_utilization']
            util_point.interval.end_time.seconds = int(datetime.now().timestamp())
            util_series.points = [util_point]
            
            monitoring_client.create_time_series(
                name=project_name,
                time_series=[util_series]
            )
        
        logging.info("Carbon efficiency metrics created successfully")
        
    except Exception as e:
        logging.warning(f"Could not create custom metrics: {e}")

def generate_finops_insights(recommendations, efficiency_score):
    """Generate insights for FinOps Hub integration."""
    
    # Categorize recommendations by type
    rightsizing_recs = [r for r in recommendations if 'MachineType' in r['recommender_type']]
    idle_compute_recs = [r for r in recommendations if 'compute.instance.Idle' in r['recommender_type']]
    idle_disk_recs = [r for r in recommendations if 'disk.Idle' in r['recommender_type']]
    
    # Calculate potential savings
    total_cost_savings = sum(float(r['impact']['cost']) for r in recommendations)
    
    # Estimate carbon impact (simplified calculation)
    # Assumption: $1 saved ≈ 0.1 kg CO2e reduction (varies by region and service)
    estimated_carbon_reduction = total_cost_savings * 0.1
    
    insights = {
        'waste_categories': {
            'idle_compute_instances': len(idle_compute_recs),
            'undersized_instances': len(rightsizing_recs),
            'idle_disks': len(idle_disk_recs)
        },
        'optimization_potential': {
            'monthly_cost_savings_usd': round(total_cost_savings, 2),
            'estimated_carbon_reduction_kg': round(estimated_carbon_reduction, 2),
            'efficiency_improvement_percent': max(0, 90 - efficiency_score)  # Target 90% efficiency
        },
        'priority_actions': generate_priority_actions(recommendations, efficiency_score),
        'gemini_integration_ready': len(recommendations) > 0
    }
    
    return insights

def generate_priority_actions(recommendations, efficiency_score):
    """Generate prioritized action items based on recommendations."""
    actions = []
    
    if efficiency_score < 50:
        actions.append({
            'priority': 'HIGH',
            'action': 'Immediate optimization required',
            'description': 'Carbon efficiency is critically low. Review all active recommendations.'
        })
    elif efficiency_score < 70:
        actions.append({
            'priority': 'MEDIUM',
            'action': 'Optimization recommended',
            'description': 'Carbon efficiency below target. Implement high-impact recommendations.'
        })
    
    # Add specific recommendations
    high_priority_recs = [r for r in recommendations if r['priority'] == 'HIGH']
    if high_priority_recs:
        actions.append({
            'priority': 'HIGH',
            'action': f'Address {len(high_priority_recs)} high-priority recommendations',
            'description': 'Focus on recommendations with highest cost and carbon impact.'
        })
    
    idle_recs = [r for r in recommendations if 'Idle' in r['recommender_type']]
    if idle_recs:
        actions.append({
            'priority': 'MEDIUM',
            'action': f'Remove {len(idle_recs)} idle resources',
            'description': 'Idle resources contribute to unnecessary carbon emissions.'
        })
    
    return actions[:5]  # Return top 5 actions