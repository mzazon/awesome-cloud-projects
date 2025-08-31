"""
Solar Assessment Cloud Function for automated property solar potential analysis.

This function processes CSV files uploaded to Cloud Storage and enriches them with
solar potential data from Google Maps Platform Solar API.

Required CSV columns: address, latitude, longitude
Output: Enhanced CSV with solar potential metrics and assessment data
"""

import json
import pandas as pd
import requests
from google.cloud import storage
import os
from io import StringIO
import functions_framework
import time
import logging
from typing import Dict, List, Any, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Cloud Storage client
storage_client = storage.Client()

# Configuration from environment variables
SOLAR_API_QUALITY = "${solar_api_required_quality}"
MAX_RETRIES = 3
RATE_LIMIT_DELAY = 0.1  # seconds between API calls


@functions_framework.cloud_event
def process_solar_assessment(cloud_event) -> None:
    """
    Process uploaded CSV files and perform solar assessments.
    Triggered by Cloud Storage object creation events.
    
    Args:
        cloud_event: CloudEvent containing file upload information
    """
    try:
        # Extract file information from cloud event
        data = cloud_event.data
        bucket_name = data['bucket']
        file_name = data['name']
        
        logger.info(f"Processing file: {file_name} from bucket: {bucket_name}")
        
        # Only process CSV files
        if not file_name.lower().endswith('.csv'):
            logger.info(f"Skipping non-CSV file: {file_name}")
            return
        
        # Skip processing result files to avoid infinite loops
        if 'solar_assessment' in file_name.lower():
            logger.info(f"Skipping already processed file: {file_name}")
            return
        
        # Process the solar assessment
        process_csv_file(bucket_name, file_name)
        
        logger.info(f"Successfully completed solar assessment for: {file_name}")
        
    except Exception as e:
        logger.error(f"Error processing cloud event: {str(e)}")
        raise


def process_csv_file(bucket_name: str, file_name: str) -> None:
    """
    Process a single CSV file with property coordinates.
    
    Args:
        bucket_name: Name of the Cloud Storage bucket
        file_name: Name of the CSV file to process
    """
    try:
        # Download CSV file from input bucket
        bucket = storage_client.bucket(bucket_name)
        blob = bucket.blob(file_name)
        csv_content = blob.download_as_text()
        
        logger.info(f"Downloaded CSV file: {file_name} ({len(csv_content)} bytes)")
        
        # Parse CSV file
        df = pd.read_csv(StringIO(csv_content))
        
        # Validate required columns
        required_columns = ['address', 'latitude', 'longitude']
        missing_columns = [col for col in required_columns if col not in df.columns]
        
        if missing_columns:
            raise ValueError(f"CSV must contain columns: {required_columns}. Missing: {missing_columns}")
        
        logger.info(f"Processing {len(df)} properties from CSV")
        
        # Get API key from environment
        solar_api_key = os.environ.get('SOLAR_API_KEY')
        if not solar_api_key:
            raise ValueError("SOLAR_API_KEY environment variable not set")
        
        # Process each property
        results = []
        successful_assessments = 0
        failed_assessments = 0
        
        for index, row in df.iterrows():
            try:
                logger.info(f"Processing property {index + 1}/{len(df)}: {row['address']}")
                
                solar_data = get_building_insights(
                    row['latitude'], 
                    row['longitude'], 
                    solar_api_key
                )
                
                # Create assessment result
                result = create_assessment_result(row, solar_data)
                results.append(result)
                
                successful_assessments += 1
                logger.info(f"✅ Successfully processed: {row['address']}")
                
                # Rate limiting to respect API quotas
                time.sleep(RATE_LIMIT_DELAY)
                
            except Exception as e:
                failed_assessments += 1
                logger.warning(f"❌ Error processing {row['address']}: {str(e)}")
                
                # Add error record to maintain data completeness
                error_result = create_error_result(row, str(e))
                results.append(error_result)
        
        # Save results to output bucket
        output_bucket_name = os.environ.get('OUTPUT_BUCKET')
        if not output_bucket_name:
            raise ValueError("OUTPUT_BUCKET environment variable not set")
        
        save_results_to_storage(results, output_bucket_name, file_name)
        
        logger.info(f"""
Solar assessment completed:
- Total properties: {len(df)}
- Successful assessments: {successful_assessments}
- Failed assessments: {failed_assessments}
- Results saved to: gs://{output_bucket_name}
        """)
        
    except Exception as e:
        logger.error(f"Error processing CSV file {file_name}: {str(e)}")
        raise


def get_building_insights(latitude: float, longitude: float, api_key: str) -> Dict[str, Any]:
    """
    Get solar insights for a building location using Solar API.
    
    Args:
        latitude: Building latitude coordinate
        longitude: Building longitude coordinate
        api_key: Google Maps Platform API key
        
    Returns:
        Dict containing solar potential data from the API
    """
    url = "https://solar.googleapis.com/v1/buildingInsights:findClosest"
    
    params = {
        'location.latitude': latitude,
        'location.longitude': longitude,
        'requiredQuality': SOLAR_API_QUALITY,
        'key': api_key
    }
    
    for attempt in range(MAX_RETRIES):
        try:
            logger.debug(f"Solar API request attempt {attempt + 1} for {latitude}, {longitude}")
            
            response = requests.get(url, params=params, timeout=30)
            
            if response.status_code == 200:
                return response.json()
            elif response.status_code == 404:
                # Building not found in Solar API dataset
                logger.warning(f"Building not found in Solar API for coordinates: {latitude}, {longitude}")
                return create_empty_solar_data("BUILDING_NOT_FOUND")
            elif response.status_code == 429:
                # Rate limit exceeded, wait and retry
                wait_time = (2 ** attempt) + RATE_LIMIT_DELAY
                logger.warning(f"Rate limit exceeded, waiting {wait_time}s before retry")
                time.sleep(wait_time)
                continue
            else:
                response.raise_for_status()
                
        except requests.RequestException as e:
            if attempt == MAX_RETRIES - 1:
                logger.error(f"Solar API request failed after {MAX_RETRIES} attempts: {str(e)}")
                raise
            
            wait_time = (2 ** attempt) + RATE_LIMIT_DELAY
            logger.warning(f"Request failed, retrying in {wait_time}s: {str(e)}")
            time.sleep(wait_time)
    
    # If we get here, all retries failed
    raise Exception(f"Solar API request failed after {MAX_RETRIES} attempts")


def create_empty_solar_data(reason: str) -> Dict[str, Any]:
    """
    Create empty solar data structure for buildings not found in API.
    
    Args:
        reason: Reason why data is empty (e.g., "BUILDING_NOT_FOUND")
        
    Returns:
        Dict with empty solar data structure
    """
    return {
        'solarPotential': {
            'maxArrayPanelsCount': 0,
            'wholeRoofStats': {
                'areaMeters2': 0,
                'sunshineQuantiles': []
            }
        },
        'imageryQuality': reason,
        'postalCode': '',
        'regionCode': '',
        'administrativeArea': ''
    }


def create_assessment_result(property_row: pd.Series, solar_data: Dict[str, Any]) -> Dict[str, Any]:
    """
    Create assessment result by combining property data with solar insights.
    
    Args:
        property_row: Original property data from CSV
        solar_data: Solar potential data from API
        
    Returns:
        Dict containing enhanced property data with solar assessment
    """
    # Extract solar potential data with safe navigation
    solar_potential = solar_data.get('solarPotential', {})
    roof_stats = solar_potential.get('wholeRoofStats', {})
    max_panels = solar_potential.get('maxArrayPanelsCount', 0)
    
    # Calculate estimated annual energy production (assuming 400 kWh per panel per year)
    estimated_kwh_per_year = max_panels * 400 if max_panels > 0 else 0
    
    # Extract sunshine quantiles for roof quality assessment
    sunshine_quantiles = roof_stats.get('sunshineQuantiles', [])
    avg_sunshine = sum(sunshine_quantiles) / len(sunshine_quantiles) if sunshine_quantiles else 0
    
    # Create comprehensive assessment result
    result = {
        # Original property information
        'address': property_row['address'],
        'latitude': property_row['latitude'],
        'longitude': property_row['longitude'],
        
        # Solar potential metrics
        'solar_potential_kwh_per_year': estimated_kwh_per_year,
        'roof_area_sqm': roof_stats.get('areaMeters2', 0),
        'max_panels': max_panels,
        'average_sunshine_hours': round(avg_sunshine, 2),
        
        # Data quality and source information
        'imagery_quality': solar_data.get('imageryQuality', 'UNKNOWN'),
        'postal_code': solar_data.get('postalCode', ''),
        'region_code': solar_data.get('regionCode', ''),
        'administrative_area': solar_data.get('administrativeArea', ''),
        
        # Assessment metadata
        'assessment_timestamp': pd.Timestamp.now().isoformat(),
        'api_quality_used': SOLAR_API_QUALITY,
        'assessment_status': 'SUCCESS',
        'error_message': None
    }
    
    # Add additional fields if available in original data
    for col in property_row.index:
        if col not in ['address', 'latitude', 'longitude']:
            result[f'original_{col}'] = property_row[col]
    
    return result


def create_error_result(property_row: pd.Series, error_message: str) -> Dict[str, Any]:
    """
    Create error result for properties that failed processing.
    
    Args:
        property_row: Original property data from CSV
        error_message: Error message describing the failure
        
    Returns:
        Dict containing property data with error information
    """
    result = {
        # Original property information
        'address': property_row['address'],
        'latitude': property_row['latitude'],
        'longitude': property_row['longitude'],
        
        # Empty solar metrics
        'solar_potential_kwh_per_year': 0,
        'roof_area_sqm': 0,
        'max_panels': 0,
        'average_sunshine_hours': 0,
        
        # Error information
        'imagery_quality': 'ERROR',
        'postal_code': '',
        'region_code': '',
        'administrative_area': '',
        
        # Assessment metadata
        'assessment_timestamp': pd.Timestamp.now().isoformat(),
        'api_quality_used': SOLAR_API_QUALITY,
        'assessment_status': 'ERROR',
        'error_message': error_message
    }
    
    # Add additional fields if available in original data
    for col in property_row.index:
        if col not in ['address', 'latitude', 'longitude']:
            result[f'original_{col}'] = property_row[col]
    
    return result


def save_results_to_storage(results: List[Dict[str, Any]], bucket_name: str, original_filename: str) -> None:
    """
    Save assessment results to Cloud Storage.
    
    Args:
        results: List of assessment results
        bucket_name: Name of the output bucket
        original_filename: Original CSV filename for naming output
    """
    try:
        # Create results DataFrame
        results_df = pd.DataFrame(results)
        
        # Generate output filename with timestamp
        base_name = original_filename.replace('.csv', '')
        timestamp = pd.Timestamp.now().strftime('%Y%m%d_%H%M%S')
        output_filename = f"{base_name}_solar_assessment_{timestamp}.csv"
        
        # Save to output bucket
        output_bucket = storage_client.bucket(bucket_name)
        output_blob = output_bucket.blob(output_filename)
        
        # Convert DataFrame to CSV string and upload
        csv_string = results_df.to_csv(index=False)
        output_blob.upload_from_string(
            csv_string, 
            content_type='text/csv'
        )
        
        # Add metadata to the blob
        metadata = {
            'original_file': original_filename,
            'processed_properties': str(len(results)),
            'processing_timestamp': pd.Timestamp.now().isoformat(),
            'solar_api_quality': SOLAR_API_QUALITY
        }
        output_blob.metadata = metadata
        output_blob.patch()
        
        logger.info(f"✅ Results saved to gs://{bucket_name}/{output_filename}")
        logger.info(f"Processed {len(results)} properties with metadata")
        
    except Exception as e:
        logger.error(f"Error saving results to storage: {str(e)}")
        raise