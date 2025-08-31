"""
Weather API Service - Cloud Function Implementation
This module provides a serverless weather API with intelligent caching using Cloud Storage.
"""

import json
import requests
import os
from datetime import datetime, timedelta
from google.cloud import storage
from functions_framework import http

# Initialize storage client
storage_client = storage.Client()
BUCKET_NAME = os.environ.get('WEATHER_CACHE_BUCKET')
API_KEY = os.environ.get('OPENWEATHER_API_KEY', 'demo_key')
LOG_LEVEL = os.environ.get('LOG_LEVEL', 'INFO')
ENABLE_CORS = os.environ.get('ENABLE_CORS', 'true').lower() == 'true'

@http
def weather_api(request):
    """
    HTTP Cloud Function to provide weather data with intelligent caching.
    
    Args:
        request: HTTP request object containing query parameters
        
    Returns:
        tuple: (response_body, status_code, headers)
    """
    
    # Enable CORS for web applications
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # Extract and validate city parameter from request
    city = request.args.get('city', '').strip()
    
    if not city:
        headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
        error_response = {
            'error': 'City parameter is required',
            'usage': 'Add ?city=CityName to your request',
            'example': 'https://your-function-url?city=London'
        }
        return (json.dumps(error_response), 400, headers)
    
    # Validate city name format
    if len(city) < 2 or len(city) > 100:
        headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
        error_response = {
            'error': 'City name must be between 2 and 100 characters',
            'provided': city
        }
        return (json.dumps(error_response), 400, headers)
    
    try:
        # Check cache first for improved performance
        cache_key = f"weather_{city.lower().replace(' ', '_').replace(',', '_')}.json"
        weather_data = get_cached_weather(cache_key)
        cached = bool(weather_data)
        
        if not weather_data:
            # Fetch from external API if not cached
            weather_data = fetch_weather_data(city)
            if weather_data and weather_data.get('cod') != 404:
                cache_weather_data(cache_key, weather_data)
            cached = False
        
        if weather_data and weather_data.get('cod') != 404:
            # Format successful response
            response_data = format_weather_response(city, weather_data, cached)
            headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
            headers.update({'Content-Type': 'application/json'})
            
            log_request(city, 'success', cached)
            return (json.dumps(response_data), 200, headers)
        else:
            # Handle city not found
            headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
            error_response = {
                'error': 'City not found',
                'city': city,
                'suggestion': 'Please check the city name spelling and try again'
            }
            log_request(city, 'not_found', False)
            return (json.dumps(error_response), 404, headers)
            
    except requests.exceptions.Timeout:
        headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
        error_response = {
            'error': 'Weather service timeout',
            'message': 'The weather service is currently slow to respond. Please try again.'
        }
        log_request(city, 'timeout', False)
        return (json.dumps(error_response), 503, headers)
        
    except requests.exceptions.RequestException as e:
        headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
        error_response = {
            'error': 'Weather service unavailable',
            'message': 'Unable to fetch weather data at this time. Please try again later.'
        }
        log_request(city, 'service_error', False)
        print(f"Weather API request error for {city}: {str(e)}")
        return (json.dumps(error_response), 503, headers)
        
    except Exception as e:
        headers = {'Access-Control-Allow-Origin': '*'} if ENABLE_CORS else {}
        error_response = {
            'error': 'Internal server error',
            'message': 'An unexpected error occurred. Please try again.'
        }
        log_request(city, 'internal_error', False)
        print(f"Unexpected error processing weather request for {city}: {str(e)}")
        return (json.dumps(error_response), 500, headers)

def get_cached_weather(cache_key):
    """
    Retrieve weather data from Cloud Storage cache.
    
    Args:
        cache_key (str): Unique key for the cached weather data
        
    Returns:
        dict or None: Cached weather data if available and valid
    """
    try:
        if not BUCKET_NAME:
            print("Warning: No cache bucket configured")
            return None
        
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(cache_key)
        
        if blob.exists():
            # Check if cache is still valid (not expired)
            blob.reload()
            cache_age = datetime.now() - blob.time_created.replace(tzinfo=None)
            
            # Cache is valid for 1 hour
            if cache_age < timedelta(hours=1):
                data = json.loads(blob.download_as_text())
                if LOG_LEVEL == 'DEBUG':
                    print(f"Cache hit for key: {cache_key}")
                return data
            else:
                # Delete expired cache
                blob.delete()
                if LOG_LEVEL == 'DEBUG':
                    print(f"Expired cache deleted for key: {cache_key}")
                    
    except Exception as e:
        print(f"Cache retrieval error for key {cache_key}: {str(e)}")
    
    return None

def cache_weather_data(cache_key, data):
    """
    Store weather data in Cloud Storage cache with metadata.
    
    Args:
        cache_key (str): Unique key for caching the weather data
        data (dict): Weather data to cache
    """
    try:
        if not BUCKET_NAME:
            print("Warning: No cache bucket configured")
            return
        
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(cache_key)
        
        # Add caching metadata
        cache_data = {
            **data,
            'cached_at': datetime.now().isoformat(),
            'cache_key': cache_key
        }
        
        # Upload with metadata
        blob.metadata = {
            'cached-at': datetime.now().isoformat(),
            'data-type': 'weather',
            'source': 'openweathermap'
        }
        
        blob.upload_from_string(
            json.dumps(cache_data),
            content_type='application/json'
        )
        
        if LOG_LEVEL in ['DEBUG', 'INFO']:
            print(f"Weather data cached for key: {cache_key}")
            
    except Exception as e:
        # Don't fail the request if caching fails
        print(f"Cache storage error for key {cache_key}: {str(e)}")

def fetch_weather_data(city):
    """
    Fetch weather data from OpenWeatherMap API with proper error handling.
    
    Args:
        city (str): City name to fetch weather for
        
    Returns:
        dict or None: Weather data from API or demo data
    """
    # Return demo data when no API key is provided
    if API_KEY == 'demo_key':
        return {
            'main': {
                'temp': 20 + hash(city) % 20,  # Vary temperature by city
                'humidity': 60 + hash(city) % 30,
                'pressure': 1013,
                'feels_like': 18 + hash(city) % 20
            },
            'weather': [{
                'main': 'Clear',
                'description': 'clear sky',
                'icon': '01d'
            }],
            'wind': {
                'speed': 2.5 + (hash(city) % 50) / 10,
                'deg': hash(city) % 360
            },
            'name': city.title(),
            'sys': {
                'country': 'DEMO',
                'sunrise': int(datetime.now().timestamp()),
                'sunset': int((datetime.now() + timedelta(hours=12)).timestamp())
            },
            'dt': int(datetime.now().timestamp()),
            'cod': 200
        }
    
    # Make API request to OpenWeatherMap
    url = "https://api.openweathermap.org/data/2.5/weather"
    params = {
        'q': city,
        'appid': API_KEY,
        'units': 'metric'
    }
    
    try:
        response = requests.get(url, params=params, timeout=10)
        response.raise_for_status()
        return response.json()
        
    except requests.exceptions.RequestException as e:
        print(f"Weather API request error for {city}: {str(e)}")
        raise

def format_weather_response(city, weather_data, cached):
    """
    Format weather data into a consistent API response.
    
    Args:
        city (str): City name requested
        weather_data (dict): Raw weather data
        cached (bool): Whether data came from cache
        
    Returns:
        dict: Formatted weather response
    """
    main_data = weather_data.get('main', {})
    weather_list = weather_data.get('weather', [{}])
    wind_data = weather_data.get('wind', {})
    sys_data = weather_data.get('sys', {})
    
    return {
        'city': weather_data.get('name', city),
        'country': sys_data.get('country', 'Unknown'),
        'temperature': {
            'current': main_data.get('temp'),
            'feels_like': main_data.get('feels_like'),
            'unit': 'celsius'
        },
        'weather': {
            'main': weather_list[0].get('main', 'Unknown'),
            'description': weather_list[0].get('description', 'No description'),
            'icon': weather_list[0].get('icon', '01d')
        },
        'humidity': main_data.get('humidity'),
        'pressure': main_data.get('pressure'),
        'wind': {
            'speed': wind_data.get('speed'),
            'direction': wind_data.get('deg')
        },
        'data_source': 'cache' if cached else 'live_api',
        'cached': cached,
        'timestamp': datetime.now().isoformat(),
        'api_version': '2.0'
    }

def log_request(city, status, cached):
    """
    Log API request for monitoring and debugging.
    
    Args:
        city (str): City name requested
        status (str): Request status (success, error, etc.)
        cached (bool): Whether response was cached
    """
    if LOG_LEVEL in ['DEBUG', 'INFO']:
        log_entry = {
            'timestamp': datetime.now().isoformat(),
            'city': city,
            'status': status,
            'cached': cached,
            'function': 'weather_api'
        }
        print(json.dumps(log_entry))