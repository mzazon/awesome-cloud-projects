# Carbon-Aware Scheduler Cloud Function
# Intelligent workload orchestration based on sustainability data

import json
import logging
import os
from datetime import datetime, timedelta
from google.cloud import batch_v1
from google.cloud import pubsub_v1
from google.cloud import storage

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def carbon_aware_scheduler(request):
    """
    Carbon-aware batch job scheduler with sustainability intelligence.
    
    This function analyzes regional carbon data and makes intelligent
    scheduling decisions to minimize environmental impact.
    """
    try:
        # Parse request data
        request_json = request.get_json(silent=True) or {}
        
        # Configuration from environment and request
        project_id = request_json.get('project_id', os.environ.get('PROJECT_ID'))
        topic_name = request_json.get('topic_name', os.environ.get('TOPIC_NAME'))
        carbon_intensity_threshold = float(os.environ.get('CARBON_INTENSITY_THRESHOLD', '${carbon_intensity_threshold}'))
        cfe_percentage_threshold = float(os.environ.get('CFE_PERCENTAGE_THRESHOLD', '${cfe_percentage_threshold}'))
        
        logger.info(f"Processing carbon scheduling request for project: {project_id}")
        
        # Get regional carbon-free energy data
        # In production, this would fetch real-time data from Google's CFE API
        regions_carbon_data = get_regional_carbon_data()
        
        # Analyze carbon efficiency across regions
        carbon_analysis = analyze_carbon_efficiency(regions_carbon_data, 
                                                  carbon_intensity_threshold,
                                                  cfe_percentage_threshold)
        
        # Make scheduling decision based on carbon analysis
        scheduling_decision = make_scheduling_decision(carbon_analysis)
        
        # Publish decision to Pub/Sub for event-driven coordination
        if project_id and topic_name:
            publish_scheduling_decision(project_id, topic_name, scheduling_decision, carbon_analysis)
        
        # Return scheduling recommendation
        response = {
            "statusCode": 200,
            "timestamp": datetime.utcnow().isoformat(),
            "decision": scheduling_decision,
            "carbon_analysis": carbon_analysis,
            "sustainability_metrics": calculate_sustainability_metrics(carbon_analysis)
        }
        
        logger.info(f"Scheduling decision: {scheduling_decision['action']} in {scheduling_decision['region']}")
        return response
        
    except Exception as e:
        logger.error(f"Carbon scheduler error: {str(e)}")
        return {
            "statusCode": 500,
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }

def get_regional_carbon_data():
    """
    Fetch regional carbon-free energy data and grid carbon intensity.
    
    In production, this would integrate with:
    - Google Cloud Carbon Footprint API
    - Regional grid carbon intensity data
    - Renewable energy forecast APIs
    """
    # Simulated regional data based on Google Cloud's CFE reporting
    # Production implementation would fetch real-time data
    regions_data = {
        "us-central1": {
            "cfe_percent": 85,
            "carbon_intensity": 120,  # gCO2e/kWh
            "renewable_forecast": "high",
            "grid_stability": "stable",
            "time_to_high_cfe": 0  # hours
        },
        "europe-west1": {
            "cfe_percent": 92,
            "carbon_intensity": 95,
            "renewable_forecast": "very_high", 
            "grid_stability": "stable",
            "time_to_high_cfe": 0
        },
        "us-west1": {
            "cfe_percent": 78,
            "carbon_intensity": 140,
            "renewable_forecast": "medium",
            "grid_stability": "stable",
            "time_to_high_cfe": 2
        },
        "asia-northeast1": {
            "cfe_percent": 45,
            "carbon_intensity": 380,
            "renewable_forecast": "low",
            "grid_stability": "stable",
            "time_to_high_cfe": 6
        },
        "asia-southeast1": {
            "cfe_percent": 35,
            "carbon_intensity": 420,
            "renewable_forecast": "low",
            "grid_stability": "variable",
            "time_to_high_cfe": 8
        }
    }
    
    logger.info(f"Retrieved carbon data for {len(regions_data)} regions")
    return regions_data

def analyze_carbon_efficiency(regions_data, intensity_threshold, cfe_threshold):
    """
    Analyze carbon efficiency across regions and identify optimal scheduling options.
    """
    analysis = {
        "optimal_regions": [],
        "acceptable_regions": [],
        "defer_regions": [],
        "best_region": None,
        "carbon_savings_potential": 0
    }
    
    # Find regions meeting carbon efficiency criteria
    for region, data in regions_data.items():
        region_score = calculate_carbon_score(data, intensity_threshold, cfe_threshold)
        
        region_analysis = {
            "region": region,
            "cfe_percent": data["cfe_percent"],
            "carbon_intensity": data["carbon_intensity"],
            "carbon_score": region_score,
            "renewable_forecast": data["renewable_forecast"],
            "recommendation": get_region_recommendation(data, intensity_threshold, cfe_threshold)
        }
        
        if data["cfe_percent"] >= cfe_threshold and data["carbon_intensity"] <= intensity_threshold:
            analysis["optimal_regions"].append(region_analysis)
        elif data["cfe_percent"] >= (cfe_threshold * 0.8):
            analysis["acceptable_regions"].append(region_analysis)
        else:
            analysis["defer_regions"].append(region_analysis)
    
    # Sort by carbon score (higher is better)
    all_regions = analysis["optimal_regions"] + analysis["acceptable_regions"] + analysis["defer_regions"]
    all_regions.sort(key=lambda x: x["carbon_score"], reverse=True)
    
    if all_regions:
        analysis["best_region"] = all_regions[0]
        
        # Calculate potential carbon savings vs worst region
        if len(all_regions) > 1:
            best_intensity = all_regions[0]["carbon_intensity"]
            worst_intensity = all_regions[-1]["carbon_intensity"]
            analysis["carbon_savings_potential"] = ((worst_intensity - best_intensity) / worst_intensity) * 100
    
    return analysis

def calculate_carbon_score(region_data, intensity_threshold, cfe_threshold):
    """
    Calculate a composite carbon efficiency score for a region.
    Higher scores indicate better carbon efficiency.
    """
    cfe_score = region_data["cfe_percent"] / 100  # 0-1 scale
    
    # Invert carbon intensity (lower is better)
    intensity_score = max(0, (intensity_threshold - region_data["carbon_intensity"]) / intensity_threshold)
    
    # Renewable forecast bonus
    forecast_bonus = {
        "very_high": 0.2,
        "high": 0.1,
        "medium": 0.0,
        "low": -0.1
    }.get(region_data["renewable_forecast"], 0)
    
    # Composite score (weighted)
    composite_score = (cfe_score * 0.6) + (intensity_score * 0.3) + forecast_bonus
    
    return min(1.0, max(0.0, composite_score))  # Clamp to 0-1 range

def get_region_recommendation(region_data, intensity_threshold, cfe_threshold):
    """
    Get scheduling recommendation for a specific region.
    """
    cfe_percent = region_data["cfe_percent"]
    carbon_intensity = region_data["carbon_intensity"]
    
    if cfe_percent >= cfe_threshold and carbon_intensity <= intensity_threshold:
        return "schedule_immediately"
    elif cfe_percent >= (cfe_threshold * 0.8):
        return "schedule_with_monitoring"
    elif region_data["time_to_high_cfe"] <= 4:
        return "schedule_delayed"
    else:
        return "defer_to_better_region"

def make_scheduling_decision(carbon_analysis):
    """
    Make final scheduling decision based on carbon analysis.
    """
    if carbon_analysis["optimal_regions"]:
        best_region = carbon_analysis["optimal_regions"][0]
        return {
            "action": "schedule_now",
            "region": best_region["region"],
            "reason": f"Optimal CFE% ({best_region['cfe_percent']}%) and low carbon intensity",
            "carbon_intensity": best_region["carbon_intensity"],
            "cfe_percent": best_region["cfe_percent"],
            "estimated_impact": "minimal",
            "priority": "high"
        }
    
    elif carbon_analysis["acceptable_regions"]:
        best_acceptable = carbon_analysis["acceptable_regions"][0]
        return {
            "action": "schedule_with_monitoring",
            "region": best_acceptable["region"],
            "reason": f"Acceptable CFE% ({best_acceptable['cfe_percent']}%) with monitoring",
            "carbon_intensity": best_acceptable["carbon_intensity"],
            "cfe_percent": best_acceptable["cfe_percent"],
            "estimated_impact": "low",
            "priority": "medium"
        }
    
    else:
        # All regions have poor carbon efficiency
        least_bad = carbon_analysis["best_region"] if carbon_analysis["best_region"] else {
            "region": "us-central1", "cfe_percent": 0, "carbon_intensity": 999
        }
        
        return {
            "action": "defer",
            "region": least_bad["region"],
            "defer_hours": 4,
            "reason": "All regions have poor carbon efficiency - deferring for better conditions",
            "carbon_intensity": least_bad["carbon_intensity"],
            "cfe_percent": least_bad["cfe_percent"],
            "estimated_impact": "high",
            "priority": "low"
        }

def publish_scheduling_decision(project_id, topic_name, decision, analysis):
    """
    Publish scheduling decision to Pub/Sub for event-driven coordination.
    """
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(project_id, topic_name)
        
        message_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "event_type": "carbon_scheduling_decision",
            "scheduler_decision": decision,
            "carbon_analysis": analysis,
            "metadata": {
                "scheduler_version": "1.0",
                "analysis_model": "carbon_efficiency_v1"
            }
        }
        
        message = json.dumps(message_data).encode('utf-8')
        future = publisher.publish(topic_path, message)
        
        message_id = future.result()
        logger.info(f"Published scheduling decision to Pub/Sub: {message_id}")
        
        return message_id
        
    except Exception as e:
        logger.error(f"Failed to publish scheduling decision: {str(e)}")
        raise

def calculate_sustainability_metrics(carbon_analysis):
    """
    Calculate comprehensive sustainability metrics for reporting.
    """
    if not carbon_analysis["best_region"]:
        return {}
    
    best_region = carbon_analysis["best_region"]
    
    metrics = {
        "carbon_efficiency_score": best_region["carbon_score"],
        "potential_carbon_savings_percent": carbon_analysis.get("carbon_savings_potential", 0),
        "optimal_regions_available": len(carbon_analysis["optimal_regions"]),
        "total_regions_analyzed": len(carbon_analysis["optimal_regions"]) + 
                                 len(carbon_analysis["acceptable_regions"]) + 
                                 len(carbon_analysis["defer_regions"]),
        "sustainability_grade": get_sustainability_grade(best_region["carbon_score"]),
        "renewable_energy_alignment": best_region["renewable_forecast"],
        "carbon_impact_category": get_carbon_impact_category(best_region["carbon_intensity"])
    }
    
    return metrics

def get_sustainability_grade(carbon_score):
    """
    Convert carbon score to sustainability grade (A-F).
    """
    if carbon_score >= 0.9:
        return "A"
    elif carbon_score >= 0.8:
        return "B" 
    elif carbon_score >= 0.7:
        return "C"
    elif carbon_score >= 0.6:
        return "D"
    else:
        return "F"

def get_carbon_impact_category(carbon_intensity):
    """
    Categorize carbon intensity impact level.
    """
    if carbon_intensity <= 100:
        return "very_low"
    elif carbon_intensity <= 200:
        return "low"
    elif carbon_intensity <= 300:
        return "medium"
    elif carbon_intensity <= 400:
        return "high"
    else:
        return "very_high"