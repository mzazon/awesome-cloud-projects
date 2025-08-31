"""
Weather API Cloud Function with intelligent caching using Cloud Storage.

This function provides a serverless weather API that fetches data from external weather services
and caches responses in Google Cloud Storage to reduce costs and improve performance.
The caching strategy reduces external API calls by up to 90% for frequently requested locations.
"""

import json
import os
import requests
from datetime import datetime, timedelta
from google.cloud import storage
from flask import Request
import functions_framework
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Cache duration configuration (templated from Terraform)
CACHE_DURATION_MINUTES = int(os.environ.get('CACHE_DURATION', '${cache_duration_minutes}'))
CACHE_BUCKET = os.environ.get('CACHE_BUCKET', '')
WEATHER_API_KEY = os.environ.get('WEATHER_API_KEY', 'demo_key')
PROJECT_ID = os.environ.get('PROJECT_ID', '')

# Initialize Cloud Storage client
try:
    storage_client = storage.Client(project=PROJECT_ID)
    bucket = storage_client.bucket(CACHE_BUCKET) if CACHE_BUCKET else None
    logger.info(f"Initialized storage client for bucket: {CACHE_BUCKET}")
except Exception as e:
    logger.error(f"Failed to initialize storage client: {e}")
    storage_client = None
    bucket = None


@functions_framework.http
def weather_api(request: Request):
    """
    HTTP Cloud Function to serve weather data with intelligent caching.
    
    Args:
        request: HTTP request object containing query parameters
        
    Returns:
        JSON response with weather data and cache metadata
    """
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Set CORS headers for all responses
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Extract city parameter from request
        city = request.args.get('city', 'London').strip()
        if not city:
            return json.dumps({'error': 'City parameter is required'}), 400, headers
        
        # Validate city name (basic security check)
        if len(city) > 100 or not city.replace(' ', '').replace('-', '').isalpha():
            return json.dumps({'error': 'Invalid city name format'}), 400, headers
        
        logger.info(f"Processing weather request for city: {city}")
        
        # Check cache first if storage is available
        cached_data = None
        if bucket:
            try:
                cached_data = get_cached_weather(city)
                if cached_data:
                    logger.info(f"Cache hit for city: {city}")
                    cached_data['from_cache'] = True
                    cached_data['cache_status'] = 'hit'
                    return json.dumps(cached_data), 200, headers
            except Exception as e:
                logger.warning(f"Cache lookup failed for {city}: {e}")
        
        # Fetch fresh data from external weather API
        logger.info(f"Cache miss for city: {city}, fetching fresh data")
        weather_data = fetch_weather_data(city)
        
        if not weather_data:
            return json.dumps({'error': 'Failed to fetch weather data'}), 500, headers
        
        # Prepare response with metadata
        response_data = {
            'city': weather_data.get('name', city),
            'country': weather_data.get('sys', {}).get('country', ''),
            'temperature': weather_data.get('main', {}).get('temp', 0),
            'feels_like': weather_data.get('main', {}).get('feels_like', 0),
            'description': weather_data.get('weather', [{}])[0].get('description', ''),
            'humidity': weather_data.get('main', {}).get('humidity', 0),
            'pressure': weather_data.get('main', {}).get('pressure', 0),
            'wind_speed': weather_data.get('wind', {}).get('speed', 0),
            'visibility': weather_data.get('visibility', 0) / 1000 if weather_data.get('visibility') else 0,  # Convert to km
            'cached_at': datetime.utcnow().isoformat() + 'Z',
            'from_cache': False,
            'cache_status': 'miss',
            'cache_duration_minutes': CACHE_DURATION_MINUTES,
            'api_version': '1.0'
        }
        
        # Cache the result if storage is available
        if bucket:
            try:
                cache_weather_data(city, response_data)
                logger.info(f"Successfully cached weather data for city: {city}")
            except Exception as e:
                logger.warning(f"Failed to cache data for {city}: {e}")
        
        return json.dumps(response_data), 200, headers
        
    except requests.exceptions.RequestException as e:
        logger.error(f"External API request failed: {e}")
        error_response = {
            'error': 'Weather service temporarily unavailable',
            'message': 'Please try again later',
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }
        return json.dumps(error_response), 503, headers
        
    except Exception as e:
        logger.error(f"Unexpected error processing request: {e}")
        error_response = {
            'error': 'Internal server error',
            'message': 'An unexpected error occurred',
            'timestamp': datetime.utcnow().isoformat() + 'Z'
        }
        return json.dumps(error_response), 500, headers


def get_cached_weather(city: str) -> dict:
    """
    Retrieve cached weather data from Cloud Storage.
    
    Args:
        city: Name of the city to retrieve cached data for
        
    Returns:
        Dictionary with cached weather data or None if not found/expired
    """
    
    if not bucket:
        return None
    
    cache_key = f"weather_{city.lower().replace(' ', '_')}.json"
    
    try:
        blob = bucket.blob(cache_key)
        
        # Check if cached data exists
        if not blob.exists():
            logger.info(f"No cached data found for {city}")
            return None
        
        # Get cached data
        cached_content = blob.download_as_text()
        cached_data = json.loads(cached_content)
        
        # Check if cache is still valid
        cached_time = datetime.fromisoformat(cached_data['cached_at'].replace('Z', '+00:00'))
        cache_age = datetime.utcnow().replace(tzinfo=cached_time.tzinfo) - cached_time
        
        if cache_age < timedelta(minutes=CACHE_DURATION_MINUTES):
            logger.info(f"Valid cached data found for {city}, age: {cache_age}")
            return cached_data
        else:
            logger.info(f"Cached data for {city} is expired, age: {cache_age}")
            # Optionally delete expired cache
            try:
                blob.delete()
                logger.info(f"Deleted expired cache for {city}")
            except Exception as e:
                logger.warning(f"Failed to delete expired cache for {city}: {e}")
            return None
            
    except Exception as e:
        logger.error(f"Error retrieving cached data for {city}: {e}")
        return None


def cache_weather_data(city: str, data: dict) -> None:
    """
    Cache weather data in Cloud Storage.
    
    Args:
        city: Name of the city to cache data for
        data: Weather data to cache
    """
    
    if not bucket:
        return
    
    cache_key = f"weather_{city.lower().replace(' ', '_')}.json"
    
    try:
        blob = bucket.blob(cache_key)
        
        # Add cache metadata
        cache_data = data.copy()
        cache_data['cached_at'] = datetime.utcnow().isoformat() + 'Z'
        cache_data['cache_expiry'] = (datetime.utcnow() + timedelta(minutes=CACHE_DURATION_MINUTES)).isoformat() + 'Z'
        
        # Upload to storage with metadata
        blob.upload_from_string(
            json.dumps(cache_data, indent=2),
            content_type='application/json'
        )
        
        # Set custom metadata
        blob.metadata = {
            'city': city,
            'cached_timestamp': str(int(datetime.utcnow().timestamp())),
            'cache_duration_minutes': str(CACHE_DURATION_MINUTES)
        }
        blob.patch()
        
        logger.info(f"Successfully cached weather data for {city}")
        
    except Exception as e:
        logger.error(f"Failed to cache weather data for {city}: {e}")
        raise


def fetch_weather_data(city: str) -> dict:
    """
    Fetch weather data from external weather API.
    
    Args:
        city: Name of the city to fetch weather for
        
    Returns:
        Dictionary with weather data from external API
    """
    
    # Use demo data if using demo API key
    if WEATHER_API_KEY == 'demo_key':
        logger.info(f"Using demo weather data for {city}")
        return get_demo_weather_data(city)
    
    # Construct API URL for OpenWeatherMap
    api_url = f"https://api.openweathermap.org/data/2.5/weather"
    params = {
        'q': city,
        'appid': WEATHER_API_KEY,
        'units': 'metric'  # Use metric units (Celsius, m/s, etc.)
    }
    
    try:
        # Make request with timeout
        response = requests.get(api_url, params=params, timeout=10)
        response.raise_for_status()
        
        weather_data = response.json()
        logger.info(f"Successfully fetched weather data for {city} from external API")
        
        return weather_data
        
    except requests.exceptions.Timeout:
        logger.error(f"Timeout fetching weather data for {city}")
        raise requests.exceptions.RequestException("Weather API request timed out")
        
    except requests.exceptions.HTTPError as e:
        if response.status_code == 404:
            logger.error(f"City not found: {city}")
            raise requests.exceptions.RequestException(f"City '{city}' not found")
        else:
            logger.error(f"HTTP error fetching weather for {city}: {e}")
            raise
            
    except requests.exceptions.RequestException as e:
        logger.error(f"Request error fetching weather for {city}: {e}")
        raise


def get_demo_weather_data(city: str) -> dict:
    """
    Generate demo weather data for testing purposes.
    
    Args:
        city: Name of the city to generate demo data for
        
    Returns:
        Dictionary with demo weather data
    """
    
    # Demo data based on city name hash for consistency
    city_hash = hash(city.lower()) % 1000
    
    demo_data = {
        'name': city.title(),
        'sys': {'country': 'XX'},
        'main': {
            'temp': 15 + (city_hash % 20),  # Temperature between 15-35°C
            'feels_like': 13 + (city_hash % 22),
            'humidity': 40 + (city_hash % 40),  # Humidity between 40-80%
            'pressure': 1000 + (city_hash % 50)  # Pressure around 1000-1050 hPa
        },
        'weather': [{
            'description': ['clear sky', 'few clouds', 'scattered clouds', 'broken clouds', 'light rain'][city_hash % 5]
        }],
        'wind': {
            'speed': (city_hash % 15) + 1  # Wind speed 1-15 m/s
        },
        'visibility': 8000 + (city_hash % 2000)  # Visibility 8-10 km
    }
    
    return demo_data


if __name__ == '__main__':
    # For local testing
    from flask import Flask
    app = Flask(__name__)
    
    @app.route('/')
    def test_endpoint():
        from flask import request
        return weather_api(request)
    
    app.run(host='0.0.0.0', port=8080, debug=True)