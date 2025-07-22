"""
Multi-Cloud Resource Discovery Function
This Cloud Function processes location data from Google Cloud Location Finder API
and generates deployment recommendations for multi-cloud environments.
"""

import json
import logging
import os
from datetime import datetime
from typing import Dict, List, Any, Optional
import requests
from google.cloud import storage
from google.cloud import monitoring_v3
from google.cloud import pubsub_v1
import functions_framework
import base64

# Configure logging with structured format
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Environment variables and configuration
BUCKET_NAME = os.environ.get('BUCKET_NAME')
PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION', 'us-central1')

# Cloud Location Finder API configuration
LOCATION_FINDER_API_BASE = "https://cloudlocationfinder.googleapis.com/v1"

class LocationFinderError(Exception):
    """Custom exception for Location Finder API errors"""
    pass

class LocationDiscoveryProcessor:
    """Main processor class for multi-cloud location discovery"""
    
    def __init__(self):
        """Initialize the processor with Google Cloud clients"""
        self.storage_client = storage.Client()
        self.monitoring_client = monitoring_v3.MetricServiceClient()
        self.bucket = self.storage_client.bucket(BUCKET_NAME) if BUCKET_NAME else None
        
    def get_location_data(self) -> List[Dict[str, Any]]:
        """
        Fetch comprehensive location data from Cloud Location Finder API
        
        Returns:
            List of location dictionaries with provider and region information
        """
        try:
            # Cloud Location Finder provides unified multi-cloud location data
            url = f"{LOCATION_FINDER_API_BASE}/locations"
            
            # Configure request with timeout and headers
            headers = {
                'User-Agent': 'GCP-LocationDiscovery/1.0',
                'Accept': 'application/json'
            }
            
            logger.info("Fetching location data from Cloud Location Finder API")
            response = requests.get(url, headers=headers, timeout=30)
            response.raise_for_status()
            
            data = response.json()
            locations = data.get('locations', [])
            
            logger.info(f"Successfully retrieved {len(locations)} locations from API")
            return locations
            
        except requests.exceptions.RequestException as e:
            logger.error(f"Failed to fetch location data: {str(e)}")
            raise LocationFinderError(f"API request failed: {str(e)}")
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse API response: {str(e)}")
            raise LocationFinderError(f"Invalid JSON response: {str(e)}")
        except Exception as e:
            logger.error(f"Unexpected error fetching location data: {str(e)}")
            raise
    
    def analyze_locations(self, locations: List[Dict[str, Any]]) -> Dict[str, Any]:
        """
        Analyze location data to generate deployment insights and recommendations
        
        Args:
            locations: List of location data from Cloud Location Finder
            
        Returns:
            Comprehensive analysis with metrics and recommendations
        """
        analysis = {
            'metadata': {
                'analysis_timestamp': datetime.utcnow().isoformat(),
                'total_locations': len(locations),
                'api_source': 'google-cloud-location-finder'
            },
            'provider_distribution': {},
            'regional_analysis': {},
            'sustainability_metrics': {
                'low_carbon_regions': [],
                'carbon_intensity_stats': {}
            },
            'performance_insights': {
                'latency_zones': [],
                'high_availability_regions': []
            },
            'compliance_zones': {
                'data_sovereignty_regions': [],
                'regulatory_compliant_zones': []
            },
            'cost_optimization': {
                'cost_effective_regions': [],
                'premium_regions': []
            },
            'recommendations': []
        }
        
        # Provider and regional analysis
        carbon_intensities = []
        
        for location in locations:
            provider = location.get('cloudProvider', 'unknown')
            region_code = location.get('regionCode', 'unknown')
            region_name = location.get('regionName', region_code)
            
            # Track provider distribution
            if provider not in analysis['provider_distribution']:
                analysis['provider_distribution'][provider] = {
                    'region_count': 0,
                    'regions': []
                }
            
            analysis['provider_distribution'][provider]['region_count'] += 1
            analysis['provider_distribution'][provider]['regions'].append({
                'code': region_code,
                'name': region_name
            })
            
            # Analyze regional characteristics
            if region_code not in analysis['regional_analysis']:
                analysis['regional_analysis'][region_code] = {
                    'provider': provider,
                    'name': region_name,
                    'characteristics': {}
                }
            
            # Process carbon footprint data
            carbon_data = location.get('carbonFootprint', {})
            if carbon_data:
                carbon_intensity = carbon_data.get('carbonIntensity')
                if carbon_intensity is not None:
                    carbon_intensities.append(carbon_intensity)
                    
                    # Identify low-carbon regions (< 200g CO2/kWh)
                    if carbon_intensity < 200:
                        analysis['sustainability_metrics']['low_carbon_regions'].append({
                            'provider': provider,
                            'region': region_code,
                            'region_name': region_name,
                            'carbon_intensity': carbon_intensity,
                            'carbon_source': carbon_data.get('carbonSource', 'unknown')
                        })
            
            # Analyze performance characteristics
            performance_data = location.get('performance', {})
            if performance_data:
                latency_grade = performance_data.get('latencyGrade')
                if latency_grade and latency_grade.lower() in ['a', 'a+']:
                    analysis['performance_insights']['latency_zones'].append({
                        'provider': provider,
                        'region': region_code,
                        'latency_grade': latency_grade
                    })
            
            # Analyze compliance and regulatory information
            compliance_data = location.get('compliance', {})
            if compliance_data:
                data_residency = compliance_data.get('dataResidency', [])
                if data_residency:
                    analysis['compliance_zones']['data_sovereignty_regions'].append({
                        'provider': provider,
                        'region': region_code,
                        'data_residency_options': data_residency
                    })
        
        # Calculate carbon intensity statistics
        if carbon_intensities:
            analysis['sustainability_metrics']['carbon_intensity_stats'] = {
                'min': min(carbon_intensities),
                'max': max(carbon_intensities),
                'average': sum(carbon_intensities) / len(carbon_intensities),
                'sample_size': len(carbon_intensities)
            }
        
        # Generate intelligent recommendations
        analysis['recommendations'] = self._generate_recommendations(analysis)
        
        return analysis
    
    def _generate_recommendations(self, analysis: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        Generate actionable deployment recommendations based on analysis
        
        Args:
            analysis: Analyzed location data
            
        Returns:
            List of prioritized recommendations
        """
        recommendations = []
        
        # Sustainability recommendations
        low_carbon_count = len(analysis['sustainability_metrics']['low_carbon_regions'])
        if low_carbon_count > 0:
            recommendations.append({
                'category': 'sustainability',
                'priority': 'high',
                'title': 'Deploy to Low-Carbon Regions',
                'description': f"Found {low_carbon_count} regions with carbon intensity < 200g CO2/kWh",
                'action_items': [
                    f"Prioritize {min(3, low_carbon_count)} low-carbon regions for new deployments",
                    "Configure workload scheduling to prefer sustainable regions",
                    "Implement carbon-aware scaling policies"
                ],
                'impact': 'Reduce carbon footprint by up to 60% compared to high-carbon regions',
                'regions': analysis['sustainability_metrics']['low_carbon_regions'][:3]
            })
        
        # Multi-provider resilience recommendations
        provider_count = len(analysis['provider_distribution'])
        if provider_count >= 3:
            recommendations.append({
                'category': 'resilience',
                'priority': 'medium',
                'title': 'Implement Multi-Provider Strategy',
                'description': f"Access to {provider_count} cloud providers enables robust disaster recovery",
                'action_items': [
                    "Design active-passive failover across providers",
                    "Implement cross-provider data replication",
                    "Test disaster recovery procedures quarterly"
                ],
                'impact': 'Improve availability to 99.99% through provider diversity',
                'providers': list(analysis['provider_distribution'].keys())
            })
        
        # Performance optimization recommendations
        low_latency_count = len(analysis['performance_insights']['latency_zones'])
        if low_latency_count > 0:
            recommendations.append({
                'category': 'performance',
                'priority': 'medium',
                'title': 'Optimize for Low-Latency Regions',
                'description': f"Deploy latency-sensitive workloads to {low_latency_count} premium performance zones",
                'action_items': [
                    "Route user traffic to nearest low-latency region",
                    "Deploy CDN edge locations in performance zones",
                    "Implement intelligent load balancing"
                ],
                'impact': 'Reduce end-user latency by 20-40%',
                'regions': analysis['performance_insights']['latency_zones'][:5]
            })
        
        # Compliance and governance recommendations
        compliant_regions = len(analysis['compliance_zones']['data_sovereignty_regions'])
        if compliant_regions > 0:
            recommendations.append({
                'category': 'compliance',
                'priority': 'high',
                'title': 'Ensure Data Sovereignty Compliance',
                'description': f"Deploy to {compliant_regions} regions with data residency controls",
                'action_items': [
                    "Map data classification to appropriate regions",
                    "Implement automated compliance monitoring",
                    "Configure data lifecycle policies per jurisdiction"
                ],
                'impact': 'Maintain regulatory compliance and avoid penalties',
                'regions': analysis['compliance_zones']['data_sovereignty_regions'][:3]
            })
        
        # Cost optimization recommendations
        total_regions = analysis['metadata']['total_locations']
        if total_regions > 20:
            recommendations.append({
                'category': 'cost-optimization',
                'priority': 'low',
                'title': 'Implement Dynamic Region Selection',
                'description': f"Leverage {total_regions} regions for cost-effective workload placement",
                'action_items': [
                    "Implement spot instance strategies across regions",
                    "Use reserved capacity in cost-effective zones",
                    "Schedule batch workloads during off-peak pricing"
                ],
                'impact': 'Reduce compute costs by 30-50% through intelligent placement',
                'total_regions': total_regions
            })
        
        return recommendations
    
    def save_analysis_to_storage(self, analysis: Dict[str, Any]) -> str:
        """
        Save analysis results to Cloud Storage with organized structure
        
        Args:
            analysis: Analysis results to save
            
        Returns:
            Path to saved file in Cloud Storage
        """
        try:
            if not self.bucket:
                raise ValueError("Storage bucket not configured")
            
            # Generate timestamped filename
            timestamp = datetime.utcnow().strftime('%Y%m%d_%H%M%S')
            filename = f"reports/location_analysis_{timestamp}.json"
            
            # Create blob and upload JSON data
            blob = self.bucket.blob(filename)
            blob.upload_from_string(
                json.dumps(analysis, indent=2, default=str),
                content_type='application/json'
            )
            
            # Add metadata to blob
            blob.metadata = {
                'analysis_type': 'multi-cloud-location-discovery',
                'generated_by': 'cloud-function',
                'total_locations': str(analysis['metadata']['total_locations']),
                'provider_count': str(len(analysis['provider_distribution']))
            }
            blob.patch()
            
            logger.info(f"Analysis saved to Cloud Storage: {filename}")
            return filename
            
        except Exception as e:
            logger.error(f"Failed to save analysis to storage: {str(e)}")
            raise
    
    def create_monitoring_metrics(self, analysis: Dict[str, Any]) -> None:
        """
        Create custom Cloud Monitoring metrics for location discovery insights
        
        Args:
            analysis: Analysis results containing metrics
        """
        try:
            project_name = f"projects/{PROJECT_ID}"
            current_time = datetime.utcnow()
            
            # Create time series for total locations discovered
            total_locations_series = monitoring_v3.TimeSeries()
            total_locations_series.resource.type = "global"
            total_locations_series.metric.type = "custom.googleapis.com/multicloud/total_locations"
            
            point = total_locations_series.points.add()
            point.value.int64_value = analysis['metadata']['total_locations']
            point.interval.end_time.seconds = int(current_time.timestamp())
            
            # Create time series for provider count
            provider_count_series = monitoring_v3.TimeSeries()
            provider_count_series.resource.type = "global"
            provider_count_series.metric.type = "custom.googleapis.com/multicloud/provider_count"
            
            point = provider_count_series.points.add()
            point.value.int64_value = len(analysis['provider_distribution'])
            point.interval.end_time.seconds = int(current_time.timestamp())
            
            # Create time series for low-carbon regions
            low_carbon_series = monitoring_v3.TimeSeries()
            low_carbon_series.resource.type = "global"
            low_carbon_series.metric.type = "custom.googleapis.com/multicloud/low_carbon_regions"
            
            point = low_carbon_series.points.add()
            point.value.int64_value = len(analysis['sustainability_metrics']['low_carbon_regions'])
            point.interval.end_time.seconds = int(current_time.timestamp())
            
            # Write all time series to Cloud Monitoring
            time_series_list = [
                total_locations_series,
                provider_count_series,
                low_carbon_series
            ]
            
            self.monitoring_client.create_time_series(
                name=project_name,
                time_series=time_series_list
            )
            
            logger.info("Successfully created custom monitoring metrics")
            
        except Exception as e:
            logger.error(f"Failed to create monitoring metrics: {str(e)}")
            # Don't raise exception as this is not critical for main functionality

@functions_framework.cloud_event
def process_location_data(cloud_event):
    """
    Main Cloud Function entry point for processing location discovery events
    
    Args:
        cloud_event: CloudEvent containing Pub/Sub message data
        
    Returns:
        Dict with processing results and status
    """
    try:
        # Initialize processor
        processor = LocationDiscoveryProcessor()
        
        # Parse Pub/Sub message data
        message_data = {}
        if hasattr(cloud_event, 'data') and cloud_event.data:
            try:
                message_data = json.loads(base64.b64decode(cloud_event.data['message']['data']).decode('utf-8'))
            except (json.JSONDecodeError, KeyError, TypeError):
                logger.warning("Could not parse Pub/Sub message data, using default trigger")
                message_data = {"trigger": "unknown"}
        
        trigger_source = message_data.get('trigger', 'unknown')
        logger.info(f"Processing location discovery request from trigger: {trigger_source}")
        
        # Fetch location data from Cloud Location Finder API
        locations = processor.get_location_data()
        
        if not locations:
            logger.warning("No location data received from API")
            return {
                "status": "warning",
                "message": "No location data available",
                "locations_processed": 0
            }
        
        # Analyze location data for insights and recommendations
        analysis = processor.analyze_locations(locations)
        
        # Save analysis results to Cloud Storage
        storage_path = processor.save_analysis_to_storage(analysis)
        
        # Create custom monitoring metrics
        processor.create_monitoring_metrics(analysis)
        
        # Log processing summary
        summary = {
            "locations_processed": len(locations),
            "providers_discovered": len(analysis['provider_distribution']),
            "low_carbon_regions": len(analysis['sustainability_metrics']['low_carbon_regions']),
            "recommendations_generated": len(analysis['recommendations']),
            "storage_path": storage_path
        }
        
        logger.info(f"Location discovery processing completed successfully: {summary}")
        
        return {
            "status": "success",
            "message": "Location discovery completed successfully",
            **summary
        }
        
    except LocationFinderError as e:
        logger.error(f"Location Finder API error: {str(e)}")
        return {
            "status": "error",
            "message": f"Location Finder API error: {str(e)}",
            "error_type": "api_error"
        }
        
    except Exception as e:
        logger.error(f"Unexpected error in process_location_data: {str(e)}", exc_info=True)
        return {
            "status": "error",
            "message": f"Processing failed: {str(e)}",
            "error_type": "processing_error"
        }

# Health check function for function status monitoring
@functions_framework.http
def health_check(request):
    """
    HTTP health check endpoint for function monitoring
    
    Args:
        request: HTTP request object
        
    Returns:
        JSON response with health status
    """
    try:
        return {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "function": "multi-cloud-location-discovery",
            "version": "1.0"
        }
    except Exception as e:
        return {
            "status": "unhealthy",
            "error": str(e),
            "timestamp": datetime.utcnow().isoformat()
        }