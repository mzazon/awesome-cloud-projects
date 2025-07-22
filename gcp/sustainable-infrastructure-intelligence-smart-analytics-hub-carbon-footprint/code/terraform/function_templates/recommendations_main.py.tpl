import os
import json
import logging
from google.cloud import bigquery
from google.cloud import storage
from datetime import datetime, timedelta
import pandas as pd

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def generate_recommendations(request):
    """
    Generate sustainability recommendations based on carbon footprint analysis
    
    This function analyzes carbon emissions patterns and generates actionable
    suggestions for reducing environmental impact while maintaining performance.
    
    Args:
        request: HTTP request object (for HTTP-triggered function)
        
    Returns:
        Dictionary containing recommendation results and report location
    """
    
    try:
        # Initialize Google Cloud clients
        client = bigquery.Client()
        storage_client = storage.Client()
        
        # Get configuration from environment variables
        project_id = "${project_id}"
        dataset_id = "${dataset_name}"
        bucket_name = "${bucket_name}"
        monitoring_months = ${monitoring_months}
        
        logger.info(f"Generating sustainability recommendations for project: {project_id}")
        
        # Analyze emissions patterns for recommendations
        recommendations_query = f"""
        WITH emissions_analysis AS (
            SELECT 
                service,
                region,
                project_id,
                AVG(location_based_carbon_emissions_kgCO2e) as avg_emissions,
                MAX(location_based_carbon_emissions_kgCO2e) as peak_emissions,
                MIN(location_based_carbon_emissions_kgCO2e) as min_emissions,
                STDDEV(location_based_carbon_emissions_kgCO2e) as emissions_variance,
                COUNT(*) as measurement_count,
                -- Calculate monthly trend
                (MAX(month) = DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)) as has_recent_data
            FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
            WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months} MONTH)
            GROUP BY service, region, project_id
        ),
        efficiency_analysis AS (
            SELECT 
                *,
                CASE 
                    WHEN emissions_variance > avg_emissions * 0.5 THEN 'HIGH_VARIABILITY'
                    WHEN avg_emissions > 100 THEN 'HIGH_EMISSIONS'
                    WHEN region NOT IN ('us-central1', 'us-west1', 'europe-west1', 'europe-west4', 'europe-north1') 
                    THEN 'CARBON_INTENSIVE_REGION'
                    WHEN peak_emissions > avg_emissions * 3 THEN 'PEAK_USAGE_OPTIMIZATION'
                    ELSE 'OPTIMIZED'
                END as recommendation_category,
                -- Calculate potential savings
                CASE 
                    WHEN emissions_variance > avg_emissions * 0.5 THEN emissions_variance * 0.6
                    WHEN avg_emissions > 100 THEN avg_emissions * 0.3
                    WHEN region NOT IN ('us-central1', 'us-west1', 'europe-west1', 'europe-west4', 'europe-north1')
                    THEN avg_emissions * 0.4
                    WHEN peak_emissions > avg_emissions * 3 THEN (peak_emissions - avg_emissions) * 0.5
                    ELSE 0
                END as potential_reduction_kgco2e
            FROM emissions_analysis
        )
        SELECT 
            service,
            region,
            project_id,
            avg_emissions,
            peak_emissions,
            min_emissions,
            emissions_variance,
            recommendation_category,
            potential_reduction_kgco2e,
            measurement_count,
            has_recent_data
        FROM efficiency_analysis
        WHERE avg_emissions > 0 AND recommendation_category != 'OPTIMIZED'
        ORDER BY potential_reduction_kgco2e DESC, avg_emissions DESC
        """
        
        logger.info("Executing recommendations analysis query")
        results = client.query(recommendations_query).to_dataframe()
        
        recommendations = []
        
        if not results.empty:
            logger.info(f"Analyzing {len(results)} services for optimization opportunities")
            
            for _, row in results.iterrows():
                recommendation = generate_service_recommendation(row)
                if recommendation:
                    recommendations.append(recommendation)
        
        # Generate additional recommendations based on regional analysis
        regional_recommendations = generate_regional_recommendations(client, project_id, dataset_id, monitoring_months)
        recommendations.extend(regional_recommendations)
        
        # Generate cost optimization recommendations
        cost_recommendations = generate_cost_optimization_recommendations(client, project_id, dataset_id, monitoring_months)
        recommendations.extend(cost_recommendations)
        
        # Create comprehensive report
        report = create_sustainability_report(recommendations, project_id, monitoring_months)
        
        # Save report to Cloud Storage
        report_location = save_report_to_storage(storage_client, bucket_name, report)
        
        logger.info(f"Generated {len(recommendations)} recommendations and saved report to {report_location}")
        
        return {
            'status': 'success',
            'recommendations_generated': len(recommendations),
            'report_location': report_location,
            'total_potential_reduction_kgco2e': sum([r.get('potential_reduction_kgco2e', 0) for r in recommendations]),
            'high_priority_count': len([r for r in recommendations if r.get('priority') == 'High']),
            'medium_priority_count': len([r for r in recommendations if r.get('priority') == 'Medium']),
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error generating recommendations: {str(e)}")
        return {
            'status': 'error',
            'error_message': str(e),
            'timestamp': datetime.now().isoformat()
        }

def generate_service_recommendation(row):
    """
    Generate specific recommendation based on service analysis
    
    Args:
        row: Pandas Series containing service emission analysis data
        
    Returns:
        Dictionary containing recommendation details
    """
    
    try:
        category = row['recommendation_category']
        service = row['service']
        region = row['region']
        project_id = row['project_id']
        avg_emissions = row['avg_emissions']
        potential_reduction = row['potential_reduction_kgco2e']
        
        recommendation = {
            'service': service,
            'region': region,
            'project': project_id,
            'current_avg_emissions_kgco2e': float(avg_emissions),
            'potential_reduction_kgco2e': float(potential_reduction),
            'generated_at': datetime.now().isoformat()
        }
        
        if category == 'HIGH_VARIABILITY':
            recommendation.update({
                'type': 'Resource Optimization',
                'priority': 'High',
                'title': f'Optimize Variable Workloads for {service}',
                'description': f'High emissions variability detected in {service} ({region}). Implementing auto-scaling and scheduled resources can significantly reduce carbon footprint.',
                'actions': [
                    'Enable auto-scaling for variable workloads to match demand',
                    'Schedule non-critical resources during low-carbon periods (when renewable energy is abundant)',
                    'Consider using preemptible/spot instances for batch workloads',
                    'Implement workload scheduling based on regional carbon intensity',
                    'Review resource allocation patterns and optimize for efficiency'
                ],
                'implementation_complexity': 'Medium',
                'estimated_implementation_time': '2-4 weeks',
                'additional_benefits': ['Cost reduction through better resource utilization', 'Improved performance predictability']
            })
            
        elif category == 'HIGH_EMISSIONS':
            recommendation.update({
                'type': 'Service Architecture Optimization',
                'priority': 'High',
                'title': f'Reduce High Carbon Footprint for {service}',
                'description': f'High carbon emissions detected from {service} in {region}. Consider architectural changes and green alternatives.',
                'actions': [
                    'Evaluate serverless alternatives to reduce idle resource consumption',
                    'Optimize resource allocation and improve utilization rates',
                    'Consider migrating to more energy-efficient service configurations',
                    'Implement caching and optimization strategies to reduce compute requirements',
                    'Review service architecture for opportunities to consolidate workloads'
                ],
                'implementation_complexity': 'High',
                'estimated_implementation_time': '4-8 weeks',
                'additional_benefits': ['Potential cost savings', 'Improved service performance', 'Reduced operational complexity']
            })
            
        elif category == 'CARBON_INTENSIVE_REGION':
            recommendation.update({
                'type': 'Regional Migration',
                'priority': 'Medium',
                'title': f'Migrate {service} to Carbon-Free Energy Regions',
                'description': f'Service deployed in carbon-intensive region. Migration to Google Cloud carbon-free energy regions can significantly reduce environmental impact.',
                'actions': [
                    'Plan migration to carbon-free energy regions (us-central1, us-west1, europe-west1, europe-west4, europe-north1)',
                    'Conduct performance impact assessment for regional change',
                    'Implement gradual migration strategy with proper testing',
                    'Update disaster recovery and backup strategies for new region',
                    'Monitor latency and user experience after migration'
                ],
                'recommended_regions': ['us-central1', 'us-west1', 'europe-west1', 'europe-west4', 'europe-north1'],
                'implementation_complexity': 'Medium',
                'estimated_implementation_time': '3-6 weeks',
                'additional_benefits': ['Access to latest Google Cloud features', 'Potential latency improvements', 'Enhanced disaster recovery options']
            })
            
        elif category == 'PEAK_USAGE_OPTIMIZATION':
            recommendation.update({
                'type': 'Peak Usage Optimization',
                'priority': 'Medium',
                'title': f'Optimize Peak Usage Patterns for {service}',
                'description': f'Significant peak usage detected that creates carbon emission spikes. Implementing peak optimization can smooth environmental impact.',
                'actions': [
                    'Implement load balancing and traffic distribution strategies',
                    'Use Cloud CDN and caching to reduce backend load during peaks',
                    'Consider implementing queue-based processing for non-urgent tasks',
                    'Schedule batch jobs during off-peak hours',
                    'Implement auto-scaling with carbon-aware policies'
                ],
                'implementation_complexity': 'Medium',
                'estimated_implementation_time': '2-4 weeks',
                'additional_benefits': ['Improved user experience during peak times', 'Better cost predictability', 'Enhanced system reliability']
            })
        
        return recommendation
        
    except Exception as e:
        logger.error(f"Error generating service recommendation: {str(e)}")
        return None

def generate_regional_recommendations(client, project_id, dataset_id, monitoring_months):
    """
    Generate recommendations based on regional carbon intensity analysis
    
    Args:
        client: BigQuery client instance
        project_id: Google Cloud project ID
        dataset_id: BigQuery dataset ID
        monitoring_months: Number of months to analyze
        
    Returns:
        List of regional recommendations
    """
    
    recommendations = []
    
    try:
        regional_query = f"""
        SELECT 
            region,
            COUNT(DISTINCT service) as services_count,
            SUM(location_based_carbon_emissions_kgCO2e) as total_emissions,
            AVG(location_based_carbon_emissions_kgCO2e) as avg_emissions_per_service,
            CASE 
                WHEN region IN ('us-central1', 'us-west1', 'europe-west1', 'europe-west4', 'europe-north1')
                THEN 'CARBON_FREE_ENERGY'
                ELSE 'STANDARD_CARBON'
            END as carbon_profile
        FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
        WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months} MONTH)
        GROUP BY region
        HAVING total_emissions > 0
        ORDER BY total_emissions DESC
        """
        
        results = client.query(regional_query).to_dataframe()
        
        for _, row in results.iterrows():
            if row['carbon_profile'] == 'STANDARD_CARBON' and row['services_count'] > 1:
                recommendation = {
                    'type': 'Regional Consolidation',
                    'priority': 'Medium',
                    'title': f'Consolidate Services from {row["region"]} to Carbon-Free Regions',
                    'region': row['region'],
                    'description': f'Multiple services in carbon-intensive region. Consolidation to carbon-free energy regions recommended.',
                    'current_emissions_kgco2e': float(row['total_emissions']),
                    'potential_reduction_kgco2e': float(row['total_emissions'] * 0.4),  # Estimated 40% reduction
                    'services_affected': int(row['services_count']),
                    'actions': [
                        'Evaluate migration feasibility for all services in the region',
                        'Prioritize migration based on service criticality and carbon impact',
                        'Plan phased migration to minimize disruption',
                        'Update monitoring and alerting for new regions'
                    ],
                    'implementation_complexity': 'High',
                    'estimated_implementation_time': '6-12 weeks',
                    'generated_at': datetime.now().isoformat()
                }
                recommendations.append(recommendation)
                
    except Exception as e:
        logger.error(f"Error generating regional recommendations: {str(e)}")
    
    return recommendations

def generate_cost_optimization_recommendations(client, project_id, dataset_id, monitoring_months):
    """
    Generate cost and carbon optimization recommendations
    
    Args:
        client: BigQuery client instance
        project_id: Google Cloud project ID
        dataset_id: BigQuery dataset ID
        monitoring_months: Number of months to analyze
        
    Returns:
        List of cost optimization recommendations
    """
    
    recommendations = []
    
    try:
        # Analyze services with potential for sustained commitments
        sustainability_query = f"""
        WITH service_consistency AS (
            SELECT 
                service,
                region,
                COUNT(DISTINCT month) as months_active,
                AVG(location_based_carbon_emissions_kgCO2e) as avg_monthly_emissions,
                STDDEV(location_based_carbon_emissions_kgCO2e) / AVG(location_based_carbon_emissions_kgCO2e) as coefficient_of_variation
            FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
            WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months} MONTH)
            GROUP BY service, region
        )
        SELECT 
            service,
            region,
            avg_monthly_emissions,
            coefficient_of_variation,
            months_active
        FROM service_consistency
        WHERE months_active >= 3
          AND coefficient_of_variation < 0.5  -- Consistent usage pattern
          AND avg_monthly_emissions > 10     -- Significant emissions
        ORDER BY avg_monthly_emissions DESC
        """
        
        results = client.query(sustainability_query).to_dataframe()
        
        if not results.empty:
            recommendation = {
                'type': 'Sustainable Usage Optimization',
                'priority': 'Low',
                'title': 'Optimize Consistent Workloads for Sustainability',
                'description': 'Services with consistent usage patterns identified for sustained use discounts and carbon optimization.',
                'services_count': len(results),
                'total_potential_reduction_kgco2e': float(results['avg_monthly_emissions'].sum() * 0.15),  # Estimated 15% reduction
                'actions': [
                    'Consider committed use discounts for consistent workloads',
                    'Implement resource right-sizing for sustained workloads',
                    'Evaluate opportunities for reserved capacity in carbon-free regions',
                    'Implement carbon-aware scheduling for flexible workloads'
                ],
                'services_analyzed': results[['service', 'region', 'avg_monthly_emissions']].to_dict('records'),
                'implementation_complexity': 'Low',
                'estimated_implementation_time': '1-2 weeks',
                'additional_benefits': ['Cost reduction through committed use discounts', 'Predictable carbon footprint', 'Better resource planning'],
                'generated_at': datetime.now().isoformat()
            }
            recommendations.append(recommendation)
            
    except Exception as e:
        logger.error(f"Error generating cost optimization recommendations: {str(e)}")
    
    return recommendations

def create_sustainability_report(recommendations, project_id, monitoring_months):
    """
    Create comprehensive sustainability report
    
    Args:
        recommendations: List of recommendation dictionaries
        project_id: Google Cloud project ID
        monitoring_months: Number of months analyzed
        
    Returns:
        Dictionary containing the complete sustainability report
    """
    
    total_potential_reduction = sum([r.get('potential_reduction_kgco2e', 0) for r in recommendations])
    high_priority_count = len([r for r in recommendations if r.get('priority') == 'High'])
    medium_priority_count = len([r for r in recommendations if r.get('priority') == 'Medium'])
    low_priority_count = len([r for r in recommendations if r.get('priority') == 'Low'])
    
    report = {
        'report_metadata': {
            'generated_at': datetime.now().isoformat(),
            'project_id': project_id,
            'analysis_period_months': monitoring_months,
            'report_version': '1.0',
            'generator': 'Sustainability Intelligence Engine'
        },
        'executive_summary': {
            'total_recommendations': len(recommendations),
            'total_potential_reduction_kgco2e': total_potential_reduction,
            'high_priority_recommendations': high_priority_count,
            'medium_priority_recommendations': medium_priority_count,
            'low_priority_recommendations': low_priority_count,
            'estimated_annual_impact_kgco2e': total_potential_reduction * 12,  # Extrapolate to annual
            'key_insights': generate_key_insights(recommendations)
        },
        'recommendations': recommendations,
        'implementation_roadmap': create_implementation_roadmap(recommendations),
        'sustainability_metrics': {
            'carbon_reduction_potential': {
                'monthly_kgco2e': total_potential_reduction,
                'annual_kgco2e': total_potential_reduction * 12,
                'equivalent_metrics': {
                    'cars_off_road_annually': (total_potential_reduction * 12) / 4600,  # Average car emissions
                    'trees_planted_equivalent': (total_potential_reduction * 12) / 21.77  # Tree CO2 absorption
                }
            },
            'optimization_categories': {
                'resource_optimization': len([r for r in recommendations if r.get('type') == 'Resource Optimization']),
                'regional_migration': len([r for r in recommendations if r.get('type') == 'Regional Migration']),
                'architecture_optimization': len([r for r in recommendations if r.get('type') == 'Service Architecture Optimization']),
                'peak_usage_optimization': len([r for r in recommendations if r.get('type') == 'Peak Usage Optimization']),
                'cost_optimization': len([r for r in recommendations if r.get('type') == 'Sustainable Usage Optimization'])
            }
        },
        'next_review_date': (datetime.now() + timedelta(days=30)).isoformat()
    }
    
    return report

def generate_key_insights(recommendations):
    """Generate key insights from recommendations analysis"""
    
    insights = []
    
    if len(recommendations) == 0:
        insights.append("Infrastructure is well-optimized for sustainability with no major recommendations identified.")
        return insights
    
    # Analyze recommendation patterns
    high_impact_recs = [r for r in recommendations if r.get('potential_reduction_kgco2e', 0) > 50]
    if high_impact_recs:
        insights.append(f"{len(high_impact_recs)} high-impact optimization opportunities identified with significant carbon reduction potential.")
    
    regional_recs = [r for r in recommendations if r.get('type') == 'Regional Migration']
    if regional_recs:
        insights.append(f"Regional migration to carbon-free energy regions recommended for {len(regional_recs)} services.")
    
    variability_recs = [r for r in recommendations if r.get('type') == 'Resource Optimization']
    if variability_recs:
        insights.append(f"Resource optimization opportunities identified for {len(variability_recs)} services with variable usage patterns.")
    
    return insights

def create_implementation_roadmap(recommendations):
    """Create phased implementation roadmap"""
    
    roadmap = {
        'phase_1_immediate': {
            'timeline': '1-2 weeks',
            'recommendations': [r for r in recommendations if r.get('implementation_complexity') == 'Low'],
            'focus': 'Quick wins and low-complexity optimizations'
        },
        'phase_2_short_term': {
            'timeline': '2-6 weeks',
            'recommendations': [r for r in recommendations if r.get('implementation_complexity') == 'Medium'],
            'focus': 'Medium complexity optimizations and architectural improvements'
        },
        'phase_3_long_term': {
            'timeline': '6-12 weeks',
            'recommendations': [r for r in recommendations if r.get('implementation_complexity') == 'High'],
            'focus': 'Major architectural changes and regional migrations'
        }
    }
    
    return roadmap

def save_report_to_storage(storage_client, bucket_name, report):
    """
    Save sustainability report to Cloud Storage
    
    Args:
        storage_client: Cloud Storage client instance
        bucket_name: Name of the storage bucket
        report: Report dictionary to save
        
    Returns:
        String containing the storage location of the saved report
    """
    
    try:
        bucket = storage_client.bucket(bucket_name)
        
        # Generate report filename with timestamp
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        blob_name = f"sustainability_reports/recommendations_{timestamp}.json"
        
        # Create blob and upload report
        blob = bucket.blob(blob_name)
        blob.upload_from_string(
            json.dumps(report, indent=2, default=str),
            content_type='application/json'
        )
        
        # Set metadata
        blob.metadata = {
            'report_type': 'sustainability_recommendations',
            'generated_at': datetime.now().isoformat(),
            'project_id': report['report_metadata']['project_id']
        }
        blob.patch()
        
        storage_location = f"gs://{bucket_name}/{blob_name}"
        logger.info(f"Report saved to: {storage_location}")
        
        return storage_location
        
    except Exception as e:
        logger.error(f"Error saving report to storage: {str(e)}")
        raise