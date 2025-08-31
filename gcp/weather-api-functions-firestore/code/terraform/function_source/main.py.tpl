import os
import json
import requests
from datetime import datetime, timedelta
from google.cloud import firestore
import functions_framework

# Initialize Firestore client
db = firestore.Client()

# Configuration from environment variables
CACHE_TTL_MINUTES = int(os.environ.get('CACHE_TTL_MINUTES', '${cache_ttl_minutes}'))
ENABLE_CORS = os.environ.get('ENABLE_CORS', '${enable_cors}').lower() == 'true'
ALLOWED_ORIGINS = json.loads(os.environ.get('ALLOWED_ORIGINS', '${allowed_origins}'))
ENVIRONMENT = os.environ.get('ENVIRONMENT', 'dev')

@functions_framework.http
def weather_api(request):
    """HTTP Cloud Function to fetch and cache weather data."""
    
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {}
        if ENABLE_CORS:
            headers.update({
                'Access-Control-Allow-Origin': '*' if '*' in ALLOWED_ORIGINS else ','.join(ALLOWED_ORIGINS),
                'Access-Control-Allow-Methods': 'GET, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization',
                'Access-Control-Max-Age': '3600'
            })
        return ('', 204, headers)
    
    # Set CORS headers for the main request
    headers = {'Content-Type': 'application/json'}
    if ENABLE_CORS:
        origin = request.headers.get('Origin', '')
        if '*' in ALLOWED_ORIGINS or origin in ALLOWED_ORIGINS:
            headers['Access-Control-Allow-Origin'] = '*' if '*' in ALLOWED_ORIGINS else origin
    
    try:
        # Extract city parameter from request
        city = request.args.get('city', 'London')
        if not city or len(city.strip()) == 0:
            return json.dumps({'error': 'City parameter is required'}), 400, headers
        
        # Validate city name (basic sanitization)
        city = city.strip()[:50]  # Limit length to prevent abuse
        
        # Get Weather API key from environment
        weather_api_key = os.environ.get('WEATHER_API_KEY')
        if not weather_api_key:
            print(f"[{ENVIRONMENT}] ERROR: Weather API key not configured")
            return json.dumps({'error': 'Weather API key not configured'}), 500, headers
        
        # Check cache first (data valid for configured TTL)
        doc_ref = db.collection('weather_cache').document(city.lower())
        doc = doc_ref.get()
        
        if doc.exists:
            data = doc.to_dict()
            cache_time = data.get('timestamp')
            
            # Use cached data if less than TTL minutes old
            if cache_time and datetime.now() - cache_time < timedelta(minutes=CACHE_TTL_MINUTES):
                print(f"[{ENVIRONMENT}] Cache hit for city: {city}")
                weather_data = data['weather_data']
                weather_data['cached'] = True
                weather_data['cache_timestamp'] = cache_time.isoformat()
                return json.dumps(weather_data), 200, headers
        
        print(f"[{ENVIRONMENT}] Cache miss for city: {city}, fetching from API")
        
        # Fetch fresh data from OpenWeatherMap API
        weather_url = f"https://api.openweathermap.org/data/2.5/weather?q={city}&appid={weather_api_key}&units=metric"
        
        try:
            response = requests.get(weather_url, timeout=10)
        except requests.exceptions.Timeout:
            print(f"[{ENVIRONMENT}] Timeout fetching weather data for city: {city}")
            return json.dumps({'error': 'Weather service timeout'}), 504, headers
        except requests.exceptions.RequestException as e:
            print(f"[{ENVIRONMENT}] Request error fetching weather data: {str(e)}")
            return json.dumps({'error': 'Failed to fetch weather data'}), 502, headers
        
        if response.status_code == 404:
            return json.dumps({'error': f'City "{city}" not found'}), 404, headers
        elif response.status_code == 401:
            print(f"[{ENVIRONMENT}] Invalid Weather API key")
            return json.dumps({'error': 'Invalid weather API key'}), 500, headers
        elif response.status_code != 200:
            print(f"[{ENVIRONMENT}] Weather API returned status: {response.status_code}")
            return json.dumps({'error': 'Weather service unavailable'}), 502, headers
        
        try:
            weather_data = response.json()
        except json.JSONDecodeError:
            print(f"[{ENVIRONMENT}] Invalid JSON response from weather API")
            return json.dumps({'error': 'Invalid weather data format'}), 502, headers
        
        # Add metadata
        weather_data['cached'] = False
        weather_data['fetch_timestamp'] = datetime.now().isoformat()
        
        # Cache the data in Firestore
        cache_data = {
            'weather_data': weather_data,
            'timestamp': datetime.now(),
            'city': city.lower(),
            'environment': ENVIRONMENT
        }
        
        try:
            doc_ref.set(cache_data)
            print(f"[{ENVIRONMENT}] Cached weather data for city: {city}")
        except Exception as cache_error:
            print(f"[{ENVIRONMENT}] Failed to cache data: {str(cache_error)}")
            # Continue execution even if caching fails
        
        return json.dumps(weather_data), 200, headers
        
    except Exception as e:
        print(f"[{ENVIRONMENT}] Unexpected error: {str(e)}")
        return json.dumps({
            'error': 'Internal server error',
            'environment': ENVIRONMENT if ENVIRONMENT == 'dev' else None
        }), 500, headers