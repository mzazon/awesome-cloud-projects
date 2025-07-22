#!/usr/bin/env python3
# Carbon-Aware Batch Job Script
# Demonstrates sustainability intelligence in batch processing workloads

import os
import time
import json
import logging
from datetime import datetime
from google.cloud import pubsub_v1
from google.cloud import monitoring_v3
from google.cloud import storage

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_regional_carbon_data():
    """
    Retrieve regional carbon intensity and CFE data.
    In production, this would integrate with Google Cloud's Carbon Footprint API.
    """
    current_region = os.environ.get('REGION', '${region}')
    
    # Simulated regional carbon data based on Google Cloud CFE reporting
    regions_data = {
        "us-central1": {
            "cfe_percent": 85, 
            "carbon_intensity": 120,  # gCO2e/kWh
            "renewable_sources": ["wind", "solar"],
            "peak_renewable_hours": [10, 11, 12, 13, 14, 15]  # Hours of day
        },
        "europe-west1": {
            "cfe_percent": 92,
            "carbon_intensity": 95,
            "renewable_sources": ["wind", "hydro", "solar"],
            "peak_renewable_hours": [9, 10, 11, 12, 13, 14, 15, 16]
        },
        "us-west1": {
            "cfe_percent": 78,
            "carbon_intensity": 140,
            "renewable_sources": ["solar", "wind"],
            "peak_renewable_hours": [11, 12, 13, 14, 15]
        },
        "asia-northeast1": {
            "cfe_percent": 45,
            "carbon_intensity": 380,
            "renewable_sources": ["solar"],
            "peak_renewable_hours": [12, 13, 14]
        }
    }
    
    return regions_data.get(current_region, regions_data["us-central1"])

def calculate_carbon_aware_workload_intensity(carbon_data):
    """
    Calculate optimal workload intensity based on current carbon conditions.
    """
    cfe_percent = carbon_data['cfe_percent']
    carbon_intensity = carbon_data['carbon_intensity']
    current_hour = datetime.now().hour
    
    # Base intensity calculation
    if cfe_percent > 80:
        base_intensity = 1.0  # Full intensity
        logger.info("High CFE region - running at full intensity")
    elif cfe_percent > 60:
        base_intensity = 0.75  # Moderate intensity
        logger.info("Medium CFE region - running at moderate intensity")
    else:
        base_intensity = 0.5  # Reduced intensity
        logger.info("Low CFE region - running at reduced intensity")
    
    # Adjust for peak renewable energy hours
    peak_hours = carbon_data.get('peak_renewable_hours', [])
    if current_hour in peak_hours:
        renewable_bonus = 0.2
        logger.info(f"Peak renewable hour ({current_hour}:00) - applying bonus")
    else:
        renewable_bonus = 0.0
    
    final_intensity = min(1.0, base_intensity + renewable_bonus)
    
    return {
        "intensity_factor": final_intensity,
        "base_intensity": base_intensity,
        "renewable_bonus": renewable_bonus,
        "reasoning": f"CFE: {cfe_percent}%, CI: {carbon_intensity} gCO2e/kWh, Hour: {current_hour}"
    }

def simulate_carbon_aware_workload(workload_config):
    """
    Simulate a carbon-aware compute workload with adaptive processing intensity.
    """
    logger.info("Starting carbon-aware batch processing...")
    
    intensity_factor = workload_config["intensity_factor"]
    base_iterations = 1000
    
    # Adjust workload based on carbon efficiency
    target_iterations = int(base_iterations * intensity_factor)
    
    logger.info(f"Workload intensity: {intensity_factor:.2f} (target iterations: {target_iterations})")
    logger.info(f"Reasoning: {workload_config['reasoning']}")
    
    # Simulate processing work with carbon awareness
    start_time = time.time()
    processed_items = 0
    
    for i in range(target_iterations):
        # Simulate compute work (mathematical operations)
        result = sum(range(1000))
        processed_items += 1
        
        # Progress reporting
        if i % 100 == 0 and i > 0:
            elapsed = time.time() - start_time
            logger.info(f"Processed {i}/{target_iterations} iterations ({elapsed:.1f}s elapsed)")
        
        # Adaptive sleep based on carbon conditions
        # Higher carbon intensity = longer pauses between operations
        carbon_intensity = workload_config.get("carbon_intensity", 100)
        if carbon_intensity > 300:
            time.sleep(0.01)  # Pause for high carbon intensity
    
    processing_time = time.time() - start_time
    
    logger.info(f"Carbon-aware processing completed: {processed_items} items in {processing_time:.2f}s")
    
    return {
        "processed_items": processed_items,
        "processing_time": processing_time,
        "target_iterations": target_iterations,
        "intensity_factor": intensity_factor,
        "items_per_second": processed_items / processing_time if processing_time > 0 else 0
    }

def calculate_carbon_impact(carbon_data, workload_results):
    """
    Calculate estimated carbon impact of the workload execution.
    """
    processing_time = workload_results["processing_time"]
    carbon_intensity = carbon_data["carbon_intensity"]  # gCO2e/kWh
    
    # Estimate power consumption (simplified model)
    # Assumes ~100W average power consumption for e2-standard-2 instance
    estimated_power_kwh = (100 / 1000) * (processing_time / 3600)  # Convert to kWh
    
    # Calculate carbon impact
    carbon_impact_grams = estimated_power_kwh * carbon_intensity
    carbon_impact_kg = carbon_impact_grams / 1000
    
    # Calculate efficiency metrics
    carbon_per_item = carbon_impact_grams / workload_results["processed_items"] if workload_results["processed_items"] > 0 else 0
    
    return {
        "carbon_impact_kg": carbon_impact_kg,
        "carbon_impact_grams": carbon_impact_grams,
        "carbon_per_item_grams": carbon_per_item,
        "estimated_power_kwh": estimated_power_kwh,
        "carbon_intensity_used": carbon_intensity,
        "efficiency_rating": get_carbon_efficiency_rating(carbon_per_item)
    }

def get_carbon_efficiency_rating(carbon_per_item):
    """
    Calculate carbon efficiency rating based on carbon per processed item.
    """
    if carbon_per_item < 0.001:
        return "excellent"
    elif carbon_per_item < 0.005:
        return "good"
    elif carbon_per_item < 0.01:
        return "fair"
    else:
        return "poor"

def publish_carbon_metrics(carbon_data, workload_results, carbon_impact):
    """
    Publish carbon efficiency metrics to Pub/Sub for monitoring and reporting.
    """
    try:
        publisher = pubsub_v1.PublisherClient()
        project_id = os.environ.get('PROJECT_ID', '${project_id}')
        topic_name = os.environ.get('TOPIC_NAME', '${topic_name}')
        
        topic_path = publisher.topic_path(project_id, topic_name)
        
        # Comprehensive carbon metrics payload
        message_data = {
            "timestamp": datetime.utcnow().isoformat(),
            "event_type": "carbon_workload_completed",
            "job_id": os.environ.get('BATCH_JOB_NAME', 'unknown'),
            "region": os.environ.get('REGION', '${region}'),
            "carbon_data": carbon_data,
            "workload_results": workload_results,
            "carbon_impact": carbon_impact,
            "sustainability_metrics": {
                "cfe_utilization": carbon_data["cfe_percent"],
                "carbon_efficiency_rating": carbon_impact["efficiency_rating"],
                "renewable_sources": carbon_data.get("renewable_sources", []),
                "optimization_applied": True
            },
            "metadata": {
                "job_version": "1.0",
                "sustainability_model": "carbon_aware_v1",
                "execution_environment": "cloud_batch"
            }
        }
        
        message = json.dumps(message_data).encode('utf-8')
        future = publisher.publish(topic_path, message)
        message_id = future.result()
        
        logger.info(f"Published carbon metrics to Pub/Sub: {message_id}")
        
        return message_id
        
    except Exception as e:
        logger.error(f"Failed to publish carbon metrics: {str(e)}")
        return None

def save_results_to_storage(carbon_data, workload_results, carbon_impact):
    """
    Save comprehensive results to Cloud Storage for analysis and reporting.
    """
    try:
        client = storage.Client()
        bucket_name = os.environ.get('BUCKET_NAME', '${bucket_name}')
        bucket = client.bucket(bucket_name)
        
        # Create comprehensive results document
        results_document = {
            "execution_timestamp": datetime.utcnow().isoformat(),
            "job_metadata": {
                "job_id": os.environ.get('BATCH_JOB_NAME', 'unknown'),
                "region": os.environ.get('REGION', '${region}'),
                "execution_environment": "google_cloud_batch"
            },
            "carbon_intelligence": {
                "regional_data": carbon_data,
                "workload_optimization": workload_results,
                "carbon_impact_assessment": carbon_impact
            },
            "sustainability_report": {
                "carbon_efficiency_score": calculate_efficiency_score(carbon_impact),
                "regional_cfe_utilization": carbon_data["cfe_percent"],
                "carbon_intensity_category": categorize_carbon_intensity(carbon_data["carbon_intensity"]),
                "optimization_recommendations": generate_optimization_recommendations(carbon_data, carbon_impact)
            }
        }
        
        # Save with timestamp for historical tracking
        timestamp = datetime.utcnow().strftime('%Y%m%d-%H%M%S')
        blob_name = f"results/carbon-job-{timestamp}.json"
        blob = bucket.blob(blob_name)
        blob.upload_from_string(json.dumps(results_document, indent=2))
        
        logger.info(f"Results saved to Cloud Storage: gs://{bucket_name}/{blob_name}")
        
        return blob_name
        
    except Exception as e:
        logger.error(f"Failed to save results to storage: {str(e)}")
        return None

def calculate_efficiency_score(carbon_impact):
    """
    Calculate overall carbon efficiency score (0-100).
    """
    carbon_per_item = carbon_impact["carbon_per_item_grams"]
    
    # Scoring based on carbon per processed item
    if carbon_per_item < 0.001:
        return 95  # Excellent efficiency
    elif carbon_per_item < 0.005:
        return 80  # Good efficiency
    elif carbon_per_item < 0.01:
        return 65  # Fair efficiency
    elif carbon_per_item < 0.02:
        return 40  # Poor efficiency
    else:
        return 20  # Very poor efficiency

def categorize_carbon_intensity(carbon_intensity):
    """
    Categorize regional carbon intensity for reporting.
    """
    if carbon_intensity < 100:
        return "very_low"
    elif carbon_intensity < 200:
        return "low"
    elif carbon_intensity < 300:
        return "medium"
    elif carbon_intensity < 400:
        return "high"
    else:
        return "very_high"

def generate_optimization_recommendations(carbon_data, carbon_impact):
    """
    Generate actionable recommendations for improving carbon efficiency.
    """
    recommendations = []
    
    cfe_percent = carbon_data["cfe_percent"]
    carbon_intensity = carbon_data["carbon_intensity"]
    efficiency_rating = carbon_impact["efficiency_rating"]
    
    # CFE-based recommendations
    if cfe_percent < 70:
        recommendations.append("Consider scheduling workloads in regions with higher CFE% (>80%)")
    
    # Carbon intensity recommendations
    if carbon_intensity > 200:
        recommendations.append("Schedule workloads during peak renewable energy hours")
        recommendations.append("Consider workload deferral during high carbon intensity periods")
    
    # Efficiency-based recommendations
    if efficiency_rating in ["fair", "poor"]:
        recommendations.append("Optimize algorithms to reduce processing time per item")
        recommendations.append("Consider batch size optimization to improve carbon efficiency")
    
    # Temporal recommendations
    peak_hours = carbon_data.get('peak_renewable_hours', [])
    current_hour = datetime.now().hour
    if current_hour not in peak_hours:
        recommendations.append(f"Consider scheduling during peak renewable hours: {peak_hours}")
    
    return recommendations

def main():
    """
    Main execution function for carbon-aware batch job.
    """
    logger.info("=== Carbon-Aware Batch Job Starting ===")
    
    try:
        # Step 1: Gather carbon intelligence data
        logger.info("Gathering regional carbon data...")
        carbon_data = get_regional_carbon_data()
        logger.info(f"Regional CFE%: {carbon_data['cfe_percent']}%")
        logger.info(f"Carbon intensity: {carbon_data['carbon_intensity']} gCO2e/kWh")
        
        # Step 2: Calculate optimal workload configuration
        logger.info("Calculating carbon-aware workload configuration...")
        workload_config = calculate_carbon_aware_workload_intensity(carbon_data)
        
        # Step 3: Execute carbon-optimized workload
        logger.info("Executing carbon-optimized workload...")
        workload_results = simulate_carbon_aware_workload(workload_config)
        
        # Step 4: Calculate carbon impact
        logger.info("Calculating carbon impact assessment...")
        carbon_impact = calculate_carbon_impact(carbon_data, workload_results)
        
        logger.info(f"Estimated carbon impact: {carbon_impact['carbon_impact_kg']:.6f} kgCO2e")
        logger.info(f"Carbon efficiency rating: {carbon_impact['efficiency_rating']}")
        
        # Step 5: Publish sustainability metrics
        logger.info("Publishing carbon metrics...")
        message_id = publish_carbon_metrics(carbon_data, workload_results, carbon_impact)
        
        # Step 6: Save comprehensive results
        logger.info("Saving results to Cloud Storage...")
        results_path = save_results_to_storage(carbon_data, workload_results, carbon_impact)
        
        # Step 7: Final reporting
        logger.info("=== Carbon-Aware Batch Job Completed Successfully ===")
        logger.info(f"Processing efficiency: {workload_results['items_per_second']:.1f} items/second")
        logger.info(f"Carbon impact per item: {carbon_impact['carbon_per_item_grams']:.6f} gCO2e")
        logger.info(f"Regional CFE utilization: {carbon_data['cfe_percent']}%")
        
        if message_id:
            logger.info(f"Metrics published to Pub/Sub: {message_id}")
        if results_path:
            logger.info(f"Detailed results saved: {results_path}")
        
    except Exception as e:
        logger.error(f"Carbon-aware batch job failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()