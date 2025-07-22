import os
import json
import logging
from google.cloud import bigquery
from google.cloud import pubsub_v1
import pandas as pd
from datetime import datetime, timedelta

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def process_carbon_data(cloud_event):
    """
    Process carbon footprint data and generate insights
    
    This function is triggered by Pub/Sub messages and performs:
    1. Analysis of recent carbon emissions data
    2. Trend detection and anomaly identification
    3. Creation of analytical views for Smart Analytics Hub
    4. Publishing alerts for significant emission increases
    
    Args:
        cloud_event: Cloud Event containing Pub/Sub message data
    """
    
    try:
        # Initialize Google Cloud clients
        client = bigquery.Client()
        
        # Get configuration from environment variables
        project_id = "${project_id}"
        dataset_id = "${dataset_name}"
        topic_name = "${topic_name}"
        increase_threshold = ${increase_threshold}
        monitoring_months = ${monitoring_months}
        
        logger.info(f"Processing carbon data for project: {project_id}")
        
        # Query recent carbon emissions data for trend analysis
        query = f"""
        SELECT 
            month,
            project_id,
            service,
            region,
            location_based_carbon_emissions_kgCO2e,
            market_based_carbon_emissions_kgCO2e,
            carbon_model_version
        FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
        WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months} MONTH)
        ORDER BY month DESC, location_based_carbon_emissions_kgCO2e DESC
        """
        
        logger.info("Executing carbon emissions query")
        results = client.query(query).to_dataframe()
        
        if not results.empty:
            logger.info(f"Processed {len(results)} carbon emission records")
            
            # Calculate monthly trends and identify anomalies
            monthly_totals = results.groupby('month')['location_based_carbon_emissions_kgCO2e'].sum().sort_index(ascending=False)
            
            # Detect significant increases (configurable threshold)
            if len(monthly_totals) >= 2:
                latest_month = monthly_totals.iloc[0]
                previous_month = monthly_totals.iloc[1]
                
                if previous_month > 0:  # Avoid division by zero
                    increase_pct = ((latest_month - previous_month) / previous_month) * 100
                    
                    logger.info(f"Month-over-month change: {increase_pct:.2f}%")
                    
                    if increase_pct > increase_threshold:
                        # Publish alert for significant increase
                        publish_carbon_alert(project_id, topic_name, {
                            'type': 'carbon_increase_alert',
                            'increase_percentage': increase_pct,
                            'latest_emissions': float(latest_month),
                            'previous_emissions': float(previous_month),
                            'threshold': increase_threshold,
                            'timestamp': datetime.now().isoformat(),
                            'monitoring_period_months': monitoring_months
                        })
                        
                        logger.warning(f"Carbon increase alert triggered: {increase_pct:.2f}% increase")
                    else:
                        logger.info(f"Carbon emissions within normal range: {increase_pct:.2f}% change")
            
            # Create analytical views for Smart Analytics Hub
            create_analytical_views(client, project_id, dataset_id, monitoring_months)
            
            # Generate service-level insights
            service_insights = analyze_service_emissions(results)
            logger.info(f"Generated insights for {len(service_insights)} services")
            
            # Regional analysis
            regional_insights = analyze_regional_emissions(results)
            logger.info(f"Generated insights for {len(regional_insights)} regions")
            
            return {
                'status': 'success',
                'processed_rows': len(results),
                'monthly_periods': len(monthly_totals),
                'service_insights': len(service_insights),
                'regional_insights': len(regional_insights),
                'timestamp': datetime.now().isoformat()
            }
        else:
            logger.warning("No carbon footprint data found for analysis")
            return {
                'status': 'no_data',
                'message': 'No carbon footprint data available for the specified monitoring period',
                'monitoring_months': monitoring_months,
                'timestamp': datetime.now().isoformat()
            }
            
    except Exception as e:
        logger.error(f"Error processing carbon data: {str(e)}")
        raise

def publish_carbon_alert(project_id, topic_name, alert_data):
    """
    Publish carbon emission alert to Pub/Sub topic
    
    Args:
        project_id: Google Cloud project ID
        topic_name: Pub/Sub topic name for alerts
        alert_data: Dictionary containing alert information
    """
    try:
        publisher = pubsub_v1.PublisherClient()
        topic_path = publisher.topic_path(project_id, topic_name)
        
        # Add metadata to alert
        alert_data.update({
            'source': 'carbon_data_processor',
            'severity': 'warning' if alert_data.get('increase_percentage', 0) < 50 else 'critical',
            'project_id': project_id
        })
        
        # Publish the alert message
        message_data = json.dumps(alert_data).encode('utf-8')
        future = publisher.publish(topic_path, message_data)
        
        logger.info(f"Published carbon alert with message ID: {future.result()}")
        
    except Exception as e:
        logger.error(f"Failed to publish carbon alert: {str(e)}")
        raise

def create_analytical_views(client, project_id, dataset_id, monitoring_months):
    """
    Create analytical views for Smart Analytics Hub sharing
    
    Args:
        client: BigQuery client instance
        project_id: Google Cloud project ID
        dataset_id: BigQuery dataset ID
        monitoring_months: Number of months to include in analysis
    """
    try:
        # Monthly emissions trend view with comprehensive metrics
        monthly_view_query = f"""
        CREATE OR REPLACE VIEW `{project_id}.{dataset_id}.monthly_emissions_trend` AS
        SELECT 
            month,
            SUM(location_based_carbon_emissions_kgCO2e) as total_location_emissions,
            SUM(market_based_carbon_emissions_kgCO2e) as total_market_emissions,
            AVG(location_based_carbon_emissions_kgCO2e) as avg_location_emissions,
            AVG(market_based_carbon_emissions_kgCO2e) as avg_market_emissions,
            COUNT(DISTINCT project_id) as active_projects,
            COUNT(DISTINCT service) as active_services,
            COUNT(DISTINCT region) as active_regions,
            MIN(location_based_carbon_emissions_kgCO2e) as min_service_emissions,
            MAX(location_based_carbon_emissions_kgCO2e) as max_service_emissions,
            STDDEV(location_based_carbon_emissions_kgCO2e) as emissions_std_dev
        FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
        WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months * 2} MONTH)
        GROUP BY month
        ORDER BY month DESC
        """
        
        # Service-level emissions analysis view
        service_view_query = f"""
        CREATE OR REPLACE VIEW `{project_id}.{dataset_id}.service_emissions_analysis` AS
        SELECT 
            service,
            region,
            project_id,
            AVG(location_based_carbon_emissions_kgCO2e) as avg_monthly_emissions,
            SUM(location_based_carbon_emissions_kgCO2e) as total_emissions,
            MAX(location_based_carbon_emissions_kgCO2e) as peak_emissions,
            MIN(location_based_carbon_emissions_kgCO2e) as min_emissions,
            COUNT(*) as measurement_count,
            STDDEV(location_based_carbon_emissions_kgCO2e) as emissions_variability,
            -- Calculate efficiency metrics
            CASE 
                WHEN STDDEV(location_based_carbon_emissions_kgCO2e) > AVG(location_based_carbon_emissions_kgCO2e) * 0.5 
                THEN 'HIGH_VARIABILITY'
                WHEN AVG(location_based_carbon_emissions_kgCO2e) > 100 
                THEN 'HIGH_EMISSIONS'
                WHEN region NOT IN ('us-central1', 'us-west1', 'europe-west1', 'europe-west4')
                THEN 'CARBON_INTENSIVE_REGION'
                ELSE 'OPTIMIZED'
            END as efficiency_category,
            -- Recent trend analysis
            LAG(AVG(location_based_carbon_emissions_kgCO2e), 1) OVER (
                PARTITION BY service, region, project_id 
                ORDER BY MAX(month)
            ) as previous_avg_emissions
        FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
        WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months} MONTH)
        GROUP BY service, region, project_id
        HAVING avg_monthly_emissions > 0
        ORDER BY avg_monthly_emissions DESC
        """
        
        # Regional carbon intensity view
        regional_view_query = f"""
        CREATE OR REPLACE VIEW `{project_id}.{dataset_id}.regional_carbon_intensity` AS
        SELECT 
            region,
            COUNT(DISTINCT service) as services_count,
            COUNT(DISTINCT project_id) as projects_count,
            SUM(location_based_carbon_emissions_kgCO2e) as total_regional_emissions,
            AVG(location_based_carbon_emissions_kgCO2e) as avg_service_emissions,
            -- Carbon intensity per service
            SUM(location_based_carbon_emissions_kgCO2e) / COUNT(DISTINCT service) as emissions_per_service,
            -- Regional efficiency ranking
            RANK() OVER (ORDER BY AVG(location_based_carbon_emissions_kgCO2e) ASC) as efficiency_rank,
            -- Classification based on Google's carbon-free energy regions
            CASE 
                WHEN region IN ('us-central1', 'us-west1', 'europe-west1', 'europe-west4', 'europe-north1')
                THEN 'CARBON_FREE_ENERGY'
                WHEN region LIKE 'us-%' OR region LIKE 'europe-%'
                THEN 'LOW_CARBON'
                ELSE 'STANDARD_CARBON'
            END as carbon_profile
        FROM `{project_id}.{dataset_id}.carbon_footprint_dataset`
        WHERE month >= DATE_SUB(CURRENT_DATE(), INTERVAL {monitoring_months} MONTH)
        GROUP BY region
        ORDER BY total_regional_emissions DESC
        """
        
        # Execute view creation queries
        logger.info("Creating monthly emissions trend view")
        client.query(monthly_view_query).result()
        
        logger.info("Creating service emissions analysis view")
        client.query(service_view_query).result()
        
        logger.info("Creating regional carbon intensity view")
        client.query(regional_view_query).result()
        
        logger.info("Successfully created all analytical views")
        
    except Exception as e:
        logger.error(f"Failed to create analytical views: {str(e)}")
        raise

def analyze_service_emissions(emissions_df):
    """
    Analyze service-level emissions patterns
    
    Args:
        emissions_df: DataFrame containing carbon emissions data
        
    Returns:
        List of service-level insights
    """
    insights = []
    
    try:
        # Group by service for analysis
        service_analysis = emissions_df.groupby('service').agg({
            'location_based_carbon_emissions_kgCO2e': ['sum', 'mean', 'std', 'count'],
            'region': 'nunique',
            'project_id': 'nunique'
        }).reset_index()
        
        # Flatten column names
        service_analysis.columns = [
            'service', 'total_emissions', 'avg_emissions', 'std_emissions', 
            'record_count', 'regions_count', 'projects_count'
        ]
        
        for _, service in service_analysis.iterrows():
            insight = {
                'service': service['service'],
                'total_emissions': float(service['total_emissions']),
                'avg_emissions': float(service['avg_emissions']),
                'variability': float(service['std_emissions']) if pd.notna(service['std_emissions']) else 0,
                'regions_count': int(service['regions_count']),
                'projects_count': int(service['projects_count'])
            }
            insights.append(insight)
            
    except Exception as e:
        logger.error(f"Error analyzing service emissions: {str(e)}")
    
    return insights

def analyze_regional_emissions(emissions_df):
    """
    Analyze regional emissions patterns
    
    Args:
        emissions_df: DataFrame containing carbon emissions data
        
    Returns:
        List of regional insights
    """
    insights = []
    
    try:
        # Group by region for analysis
        regional_analysis = emissions_df.groupby('region').agg({
            'location_based_carbon_emissions_kgCO2e': ['sum', 'mean', 'count'],
            'service': 'nunique',
            'project_id': 'nunique'
        }).reset_index()
        
        # Flatten column names
        regional_analysis.columns = [
            'region', 'total_emissions', 'avg_emissions', 'record_count',
            'services_count', 'projects_count'
        ]
        
        for _, region in regional_analysis.iterrows():
            insight = {
                'region': region['region'],
                'total_emissions': float(region['total_emissions']),
                'avg_emissions': float(region['avg_emissions']),
                'services_count': int(region['services_count']),
                'projects_count': int(region['projects_count']),
                'carbon_intensity': float(region['total_emissions']) / int(region['services_count']) if region['services_count'] > 0 else 0
            }
            insights.append(insight)
            
    except Exception as e:
        logger.error(f"Error analyzing regional emissions: {str(e)}")
    
    return insights