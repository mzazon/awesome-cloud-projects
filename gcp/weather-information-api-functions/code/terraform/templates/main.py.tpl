import functions_framework
import requests
import json
import os
import logging
from flask import jsonify

# Configure logging
logging.basicConfig(level=getattr(logging, "${log_level}", logging.INFO))
logger = logging.getLogger(__name__)

@functions_framework.http
def get_weather(request):
    """HTTP Cloud Function to get weather information for a city.
    
    Args:
        request (flask.Request): The request object containing city parameter
        
    Returns:
        flask.Response: JSON response with weather data or error message
    """
    
    # Set CORS headers for cross-origin requests
    cors_origins = os.environ.get('CORS_ORIGINS', '*').split(',')
    origin = request.headers.get('Origin', '')
    
    headers = {
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type'
    }
    
    # Handle CORS origin validation
    if '*' in cors_origins or origin in cors_origins:
        headers['Access-Control-Allow-Origin'] = origin if origin else '*'
    else:
        headers['Access-Control-Allow-Origin'] = cors_origins[0] if cors_origins else '*'
    
    # Handle preflight OPTIONS request
    if request.method == 'OPTIONS':
        return ('', 204, headers)
    
    try:
        # Get city parameter from request
        city = request.args.get('city', '').strip()
        
        if not city:
            logger.warning("Request received without city parameter")
            return jsonify({
                'error': 'City parameter is required',
                'example': '?city=London',
                'usage': 'Send GET request with city parameter'
            }), 400, headers
        
        logger.info(f"Weather request for city: {city}")
        
        # Get API key from environment variable
        api_key = os.environ.get('WEATHER_API_KEY', '${weather_api_key}')
        
        if api_key == 'demo_key_please_replace' or api_key == '${weather_api_key}':
            # Return mock data for demo purposes
            logger.info(f"Returning demo data for city: {city}")
            return jsonify({
                'city': city,
                'country': 'DEMO',
                'temperature': 22.5,
                'feels_like': 24.1,
                'description': 'Partly Cloudy (Demo Data)',
                'humidity': 65,
                'wind_speed': 5.2,
                'timestamp': 1625097600,
                'note': 'This is demo data. Set WEATHER_API_KEY environment variable for real data.',
                'api_usage': 'Demo mode - no external API calls made'
            }), 200, headers
        
        # Make request to OpenWeatherMap API
        weather_url = "https://api.openweathermap.org/data/2.5/weather"
        params = {
            'q': city,
            'appid': api_key,
            'units': 'metric'
        }
        
        logger.debug(f"Making API request to OpenWeatherMap for city: {city}")
        
        response = requests.get(weather_url, params=params, timeout=10)
        
        if response.status_code == 401:
            logger.error("Invalid API key for OpenWeatherMap")
            return jsonify({
                'error': 'Invalid weather API key',
                'suggestion': 'Please check your OpenWeatherMap API key configuration'
            }), 401, headers
        
        if response.status_code == 404:
            logger.warning(f"City not found: {city}")
            return jsonify({
                'error': f'City "{city}" not found',
                'suggestion': 'Please check the spelling or try a different city name',
                'examples': ['London', 'New York', 'Tokyo', 'Paris']
            }), 404, headers
        
        if response.status_code == 429:
            logger.warning("Rate limit exceeded for weather API")
            return jsonify({
                'error': 'Weather API rate limit exceeded',
                'suggestion': 'Please try again later'
            }), 429, headers
        
        if response.status_code != 200:
            logger.error(f"Weather service error: {response.status_code}")
            return jsonify({
                'error': 'Weather service temporarily unavailable',
                'status_code': response.status_code,
                'retry': 'Please try again in a few moments'
            }), 502, headers
        
        weather_data = response.json()
        logger.info(f"Successfully retrieved weather data for {city}")
        
        # Extract and format relevant weather information
        formatted_response = {
            'city': weather_data['name'],
            'country': weather_data['sys']['country'],
            'temperature': round(weather_data['main']['temp'], 1),
            'feels_like': round(weather_data['main']['feels_like'], 1),
            'description': weather_data['weather'][0]['description'].title(),
            'weather_main': weather_data['weather'][0]['main'],
            'humidity': weather_data['main']['humidity'],
            'pressure': weather_data['main'].get('pressure'),
            'wind_speed': weather_data.get('wind', {}).get('speed', 0),
            'wind_direction': weather_data.get('wind', {}).get('deg'),
            'cloudiness': weather_data.get('clouds', {}).get('all'),
            'visibility': weather_data.get('visibility'),
            'sunrise': weather_data['sys'].get('sunrise'),
            'sunset': weather_data['sys'].get('sunset'),
            'timestamp': weather_data['dt'],
            'timezone': weather_data.get('timezone'),
            'coordinates': {
                'lat': weather_data['coord']['lat'],
                'lon': weather_data['coord']['lon']
            }
        }
        
        return jsonify(formatted_response), 200, headers
        
    except requests.exceptions.Timeout:
        logger.error("Timeout while fetching weather data")
        return jsonify({
            'error': 'Weather service request timed out',
            'retry': 'Please try again in a few moments',
            'timeout': '10 seconds'
        }), 504, headers
        
    except requests.exceptions.ConnectionError:
        logger.error("Connection error while fetching weather data")
        return jsonify({
            'error': 'Unable to connect to weather service',
            'suggestion': 'Please check your internet connection and try again'
        }), 502, headers
        
    except requests.exceptions.RequestException as e:
        logger.error(f"Request error: {str(e)}")
        return jsonify({
            'error': 'Failed to fetch weather data',
            'details': 'External API request failed',
            'type': 'RequestException'
        }), 502, headers
        
    except KeyError as e:
        logger.error(f"Data parsing error: {str(e)}")
        return jsonify({
            'error': 'Weather data format error',
            'message': 'Unexpected response format from weather service'
        }), 502, headers
        
    except Exception as e:
        logger.error(f"Unexpected error: {str(e)}")
        return jsonify({
            'error': 'Internal server error',
            'message': 'An unexpected error occurred',
            'type': type(e).__name__
        }), 500, headers