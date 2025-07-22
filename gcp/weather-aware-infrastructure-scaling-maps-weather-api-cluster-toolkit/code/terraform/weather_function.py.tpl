#!/usr/bin/env python3
"""
Weather-Aware HPC Scaling Function

This Cloud Function processes weather data from Google Maps Platform Weather API
and generates scaling decisions for HPC clusters based on meteorological conditions.
"""

import json
import logging
import os
import requests
from datetime import datetime, timezone
from google.cloud import pubsub_v1
from google.cloud import storage
from google.cloud import monitoring_v1
from google.cloud import secretmanager
import functions_framework

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from template variables
PROJECT_ID = "${project_id}"
TOPIC_NAME = "${topic_name}"
BUCKET_NAME = "${bucket_name}"
WEATHER_LOCATIONS = ${jsonencode(locations)}

# Weather API configuration
WEATHER_API_BASE_URL = "https://weather.googleapis.com/v1/weather:forecastHourly"

class WeatherProcessor:
    """Main class for processing weather data and generating scaling decisions."""
    
    def __init__(self):
        """Initialize the weather processor with Google Cloud clients."""
        self.publisher = pubsub_v1.PublisherClient()
        self.storage_client = storage.Client()
        self.monitoring_client = monitoring_v1.MetricServiceClient()
        self.secret_client = secretmanager.SecretManagerServiceClient()
        
        # Get Weather API key from Secret Manager
        self.weather_api_key = self._get_weather_api_key()
        
        # Create topic path for publishing
        self.topic_path = self.publisher.topic_path(PROJECT_ID, TOPIC_NAME)
        
        logger.info(f"Weather processor initialized for project: {PROJECT_ID}")
    
    def _get_weather_api_key(self):
        """Retrieve Weather API key from Secret Manager."""
        try:
            secret_name = os.environ.get('WEATHER_API_SECRET')
            if not secret_name:
                raise ValueError("WEATHER_API_SECRET environment variable not set")
            
            secret_path = self.secret_client.secret_version_path(
                PROJECT_ID, secret_name, "latest"
            )
            
            response = self.secret_client.access_secret_version(
                request={"name": secret_path}
            )
            
            return response.payload.data.decode("UTF-8")
        except Exception as e:
            logger.error(f"Failed to retrieve Weather API key: {str(e)}")
            raise
    
    def fetch_weather_data(self, location):
        """Fetch weather data for a specific location."""
        try:
            headers = {
                'X-Goog-Api-Key': self.weather_api_key
            }
            
            params = {
                'location.latitude': location['latitude'],
                'location.longitude': location['longitude'],
                'hourCount': 6,  # 6-hour forecast
                'units': 'metric'
            }
            
            response = requests.get(
                WEATHER_API_BASE_URL,
                headers=headers,
                params=params,
                timeout=30
            )
            
            response.raise_for_status()
            return response.json()
        
        except requests.exceptions.RequestException as e:
            logger.error(f"Weather API request failed for {location['name']}: {str(e)}")
            raise
        except Exception as e:
            logger.error(f"Unexpected error fetching weather data: {str(e)}")
            raise
    
    def analyze_weather_conditions(self, weather_data):
        """Analyze weather conditions and calculate scaling factor."""
        try:
            if 'hourlyForecasts' not in weather_data:
                logger.warning("No hourly forecasts in weather data")
                return 1.0, {}
            
            forecasts = weather_data['hourlyForecasts'][:6]  # Next 6 hours
            
            # Initialize weather metrics
            total_precipitation = 0.0
            max_wind_speed = 0.0
            temperatures = []
            humidity_levels = []
            
            # Extract weather metrics from forecasts
            for forecast in forecasts:
                # Precipitation analysis (mm/hour)
                if 'precipitationMm' in forecast:
                    total_precipitation += forecast['precipitationMm']
                
                # Wind speed analysis (km/h)
                if 'windSpeedKph' in forecast:
                    max_wind_speed = max(max_wind_speed, forecast['windSpeedKph'])
                
                # Temperature collection
                if 'temperatureCelsius' in forecast:
                    temperatures.append(forecast['temperatureCelsius'])
                
                # Humidity collection
                if 'relativeHumidity' in forecast:
                    humidity_levels.append(forecast['relativeHumidity'])
            
            # Calculate temperature variance
            temperature_variance = 0.0
            if len(temperatures) > 1:
                avg_temp = sum(temperatures) / len(temperatures)
                temperature_variance = sum((t - avg_temp) ** 2 for t in temperatures) / len(temperatures)
            
            # Calculate average humidity
            avg_humidity = sum(humidity_levels) / len(humidity_levels) if humidity_levels else 0
            
            # Weather-based scaling logic
            scaling_factor = 1.0
            
            # Heavy precipitation increases climate modeling demand
            if total_precipitation > 10:  # Heavy rain/snow
                scaling_factor *= 1.5
                logger.info(f"Heavy precipitation detected: {total_precipitation}mm")
            elif total_precipitation > 5:  # Moderate precipitation
                scaling_factor *= 1.2
                logger.info(f"Moderate precipitation detected: {total_precipitation}mm")
            
            # High wind speeds trigger renewable energy forecasting
            if max_wind_speed > 50:  # Strong winds (>50 km/h)
                scaling_factor *= 1.4
                logger.info(f"Strong winds detected: {max_wind_speed}km/h")
            elif max_wind_speed > 30:  # Moderate winds (30-50 km/h)
                scaling_factor *= 1.1
                logger.info(f"Moderate winds detected: {max_wind_speed}km/h")
            
            # Temperature variance indicates weather instability
            if temperature_variance > 25:  # High variance
                scaling_factor *= 1.3
                logger.info(f"High temperature variance: {temperature_variance}")
            elif temperature_variance > 10:  # Moderate variance
                scaling_factor *= 1.1
                logger.info(f"Moderate temperature variance: {temperature_variance}")
            
            # High humidity affects atmospheric modeling
            if avg_humidity > 80:  # High humidity
                scaling_factor *= 1.2
                logger.info(f"High humidity detected: {avg_humidity}%")
            
            # Cap scaling factor for cost control
            scaling_factor = min(scaling_factor, 2.0)
            
            # Weather summary for logging
            weather_summary = {
                'total_precipitation_mm': round(total_precipitation, 2),
                'max_wind_speed_kmh': round(max_wind_speed, 2),
                'temperature_variance': round(temperature_variance, 2),
                'avg_temperature_c': round(sum(temperatures) / len(temperatures), 2) if temperatures else None,
                'avg_humidity_percent': round(avg_humidity, 2),
                'forecast_hours': len(forecasts)
            }
            
            logger.info(f"Weather analysis complete. Scaling factor: {scaling_factor}")
            return scaling_factor, weather_summary
        
        except Exception as e:
            logger.error(f"Error analyzing weather conditions: {str(e)}")
            return 1.0, {}
    
    def store_weather_data(self, location_name, weather_data):
        """Store weather data in Cloud Storage for historical analysis."""
        try:
            bucket = self.storage_client.bucket(BUCKET_NAME)
            
            # Create timestamped blob name
            timestamp = datetime.now(timezone.utc).strftime('%Y%m%d-%H%M%S')
            blob_name = f"weather-data/{location_name}/{timestamp}.json"
            
            # Upload weather data
            blob = bucket.blob(blob_name)
            blob.upload_from_string(
                json.dumps(weather_data, indent=2),
                content_type='application/json'
            )
            
            logger.info(f"Weather data stored: {blob_name}")
            
        except Exception as e:
            logger.error(f"Error storing weather data: {str(e)}")
    
    def publish_scaling_decision(self, location_name, scaling_factor, weather_summary):
        """Publish scaling decision to Pub/Sub topic."""
        try:
            scaling_decision = {
                'region': location_name,
                'scaling_factor': scaling_factor,
                'weather_summary': weather_summary,
                'timestamp': datetime.now(timezone.utc).isoformat(),
                'processor_version': '1.0'
            }
            
            message_data = json.dumps(scaling_decision).encode('utf-8')
            
            # Publish message with attributes
            future = self.publisher.publish(
                self.topic_path,
                message_data,
                region=location_name,
                scaling_factor=str(scaling_factor),
                timestamp=scaling_decision['timestamp']
            )
            
            message_id = future.result()
            logger.info(f"Published scaling decision for {location_name}, message ID: {message_id}")
            
        except Exception as e:
            logger.error(f"Error publishing scaling decision: {str(e)}")
    
    def send_custom_metrics(self, location_name, scaling_factor, weather_summary):
        """Send custom metrics to Cloud Monitoring."""
        try:
            project_name = f"projects/{PROJECT_ID}"
            
            # Create time series for scaling factor
            series = monitoring_v1.TimeSeries()
            series.metric.type = 'custom.googleapis.com/weather/scaling_factor'
            series.metric.labels['region'] = location_name
            series.resource.type = 'global'
            
            # Add scaling factor data point
            point = series.points.add()
            point.value.double_value = scaling_factor
            point.interval.end_time.seconds = int(datetime.now(timezone.utc).timestamp())
            
            # Send scaling factor metric
            self.monitoring_client.create_time_series(
                name=project_name,
                time_series=[series]
            )
            
            # Send weather metrics
            weather_metrics = [
                ('precipitation_mm', weather_summary.get('total_precipitation_mm', 0)),
                ('wind_speed_kmh', weather_summary.get('max_wind_speed_kmh', 0)),
                ('temperature_variance', weather_summary.get('temperature_variance', 0)),
                ('humidity_percent', weather_summary.get('avg_humidity_percent', 0))
            ]
            
            for metric_name, value in weather_metrics:
                if value is not None:
                    series = monitoring_v1.TimeSeries()
                    series.metric.type = f'custom.googleapis.com/weather/{metric_name}'
                    series.metric.labels['region'] = location_name
                    series.resource.type = 'global'
                    
                    point = series.points.add()
                    point.value.double_value = float(value)
                    point.interval.end_time.seconds = int(datetime.now(timezone.utc).timestamp())
                    
                    self.monitoring_client.create_time_series(
                        name=project_name,
                        time_series=[series]
                    )
            
            logger.info(f"Custom metrics sent for {location_name}")
            
        except Exception as e:
            logger.error(f"Error sending custom metrics: {str(e)}")
    
    def process_all_locations(self):
        """Process weather data for all configured locations."""
        scaling_decisions = []
        
        for location in WEATHER_LOCATIONS:
            try:
                logger.info(f"Processing weather data for {location['name']}")
                
                # Fetch weather data
                weather_data = self.fetch_weather_data(location)
                
                # Analyze weather conditions
                scaling_factor, weather_summary = self.analyze_weather_conditions(weather_data)
                
                # Store weather data
                self.store_weather_data(location['name'], weather_data)
                
                # Publish scaling decision
                self.publish_scaling_decision(location['name'], scaling_factor, weather_summary)
                
                # Send custom metrics
                self.send_custom_metrics(location['name'], scaling_factor, weather_summary)
                
                # Add to results
                scaling_decisions.append({
                    'location': location['name'],
                    'scaling_factor': scaling_factor,
                    'weather_summary': weather_summary
                })
                
            except Exception as e:
                logger.error(f"Error processing location {location['name']}: {str(e)}")
                continue
        
        return scaling_decisions


@functions_framework.http
def weather_processor(request):
    """
    HTTP Cloud Function entry point for weather processing.
    
    This function is triggered by Cloud Scheduler to collect weather data
    and generate scaling decisions for weather-aware HPC infrastructure.
    """
    try:
        logger.info("Weather processor function triggered")
        
        # Initialize weather processor
        processor = WeatherProcessor()
        
        # Process all configured locations
        results = processor.process_all_locations()
        
        # Prepare response
        response = {
            'status': 'success',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'processed_locations': len(results),
            'scaling_decisions': results
        }
        
        logger.info(f"Weather processing completed successfully for {len(results)} locations")
        
        return response
        
    except Exception as e:
        logger.error(f"Weather processor function failed: {str(e)}")
        
        error_response = {
            'status': 'error',
            'timestamp': datetime.now(timezone.utc).isoformat(),
            'error': str(e)
        }
        
        return error_response, 500


# Health check endpoint
@functions_framework.http
def health_check(request):
    """Health check endpoint for the weather processor function."""
    return {
        'status': 'healthy',
        'timestamp': datetime.now(timezone.utc).isoformat(),
        'version': '1.0'
    }