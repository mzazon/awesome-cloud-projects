"""
Climate Risk Assessment - Earth Engine Data Processor
This Cloud Function processes climate data from Earth Engine and loads it to BigQuery.
"""

import ee
import functions_framework
from google.cloud import bigquery
from google.cloud import storage
import json
import pandas as pd
from datetime import datetime, timedelta
import os
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize Earth Engine
try:
    ee.Initialize()
    logger.info("Earth Engine initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Earth Engine: {str(e)}")
    raise


@functions_framework.http
def process_climate_data(request):
    """
    Process climate data from Earth Engine and load to BigQuery
    
    Args:
        request: HTTP request object with JSON payload containing:
            - region_bounds: List of [west, south, east, north] coordinates
            - start_date: Start date for analysis (YYYY-MM-DD)
            - end_date: End date for analysis (YYYY-MM-DD)
            - dataset_id: BigQuery dataset ID
    
    Returns:
        JSON response with processing results
    """
    try:
        # Parse request parameters
        request_json = request.get_json()
        if not request_json:
            return {'error': 'No JSON data provided'}, 400
        
        # Get parameters with defaults
        region_bounds = request_json.get('region_bounds', 
            [-125, 25, -66, 49])  # Default: Continental US
        start_date = request_json.get('start_date', '2020-01-01')
        end_date = request_json.get('end_date', '2023-12-31')
        dataset_id = request_json.get('dataset_id')
        
        if not dataset_id:
            return {'error': 'dataset_id is required'}, 400
        
        logger.info(f"Processing climate data for region: {region_bounds}, "
                   f"period: {start_date} to {end_date}")
        
        # Define region of interest
        region = ee.Geometry.Rectangle(region_bounds)
        
        # Load climate datasets
        logger.info("Loading Earth Engine datasets...")
        
        # MODIS Land Surface Temperature
        lst_collection = ee.ImageCollection('MODIS/006/MOD11A1') \
            .filterDate(start_date, end_date) \
            .filterBounds(region) \
            .select(['LST_Day_1km', 'LST_Night_1km'])
        
        # CHIRPS Precipitation Data
        precip_collection = ee.ImageCollection('UCSB-CHG/CHIRPS/DAILY') \
            .filterDate(start_date, end_date) \
            .filterBounds(region) \
            .select('precipitation')
        
        # MODIS Vegetation Indices
        ndvi_collection = ee.ImageCollection('MODIS/006/MOD13Q1') \
            .filterDate(start_date, end_date) \
            .filterBounds(region) \
            .select(['NDVI', 'EVI'])
        
        # Calculate climate statistics
        logger.info("Calculating climate statistics...")
        
        # Convert LST from Kelvin to Celsius and apply scale factor
        lst_mean = lst_collection.mean().multiply(0.02).subtract(273.15)
        precip_total = precip_collection.sum()
        ndvi_mean = ndvi_collection.mean().multiply(0.0001)  # Apply NDVI scale factor
        
        # Create composite image with all climate indicators
        climate_composite = lst_mean.addBands(precip_total) \
                                   .addBands(ndvi_mean)
        
        # Sample climate data at regular intervals
        logger.info("Sampling climate data...")
        sample_points = region.coveringGrid(0.1)  # ~10km grid
        
        # Extract values at sample points
        climate_samples = climate_composite.sampleRegions(
            collection=sample_points,
            scale=1000,
            geometries=True,
            tileScale=4  # Reduce memory usage
        )
        
        # Convert to DataFrame format for BigQuery
        logger.info("Converting Earth Engine data to DataFrame...")
        features = climate_samples.getInfo()['features']
        
        if not features:
            return {'error': 'No climate data found for the specified region and time period'}, 404
        
        data_rows = []
        for feature in features:
            try:
                properties = feature['properties']
                geometry = feature['geometry']['coordinates']
                
                # Validate coordinate values
                if not (-180 <= geometry[0] <= 180 and -90 <= geometry[1] <= 90):
                    continue
                
                row = {
                    'longitude': float(geometry[0]),
                    'latitude': float(geometry[1]),
                    'location': f"POINT({geometry[0]} {geometry[1]})",
                    'avg_day_temp_c': properties.get('LST_Day_1km', None),
                    'avg_night_temp_c': properties.get('LST_Night_1km', None),
                    'total_precipitation_mm': properties.get('precipitation', None),
                    'avg_ndvi': properties.get('NDVI', None),
                    'avg_evi': properties.get('EVI', None),
                    'analysis_date': datetime.now().isoformat(),
                    'analysis_period_start': start_date,
                    'analysis_period_end': end_date
                }
                
                # Only include rows with valid data
                if any(row[field] is not None for field in 
                      ['avg_day_temp_c', 'avg_night_temp_c', 'total_precipitation_mm', 'avg_ndvi']):
                    data_rows.append(row)
                    
            except Exception as e:
                logger.warning(f"Error processing feature: {str(e)}")
                continue
        
        if not data_rows:
            return {'error': 'No valid climate data points found'}, 404
        
        # Load data to BigQuery
        logger.info(f"Loading {len(data_rows)} records to BigQuery...")
        
        client = bigquery.Client()
        project_id = os.environ.get('PROJECT_ID', client.project)
        table_id = f"{project_id}.{dataset_id}.climate_indicators"
        
        job_config = bigquery.LoadJobConfig(
            write_disposition="WRITE_APPEND",
            schema=[
                bigquery.SchemaField("longitude", "FLOAT"),
                bigquery.SchemaField("latitude", "FLOAT"),
                bigquery.SchemaField("location", "GEOGRAPHY"),
                bigquery.SchemaField("avg_day_temp_c", "FLOAT"),
                bigquery.SchemaField("avg_night_temp_c", "FLOAT"),
                bigquery.SchemaField("total_precipitation_mm", "FLOAT"),
                bigquery.SchemaField("avg_ndvi", "FLOAT"),
                bigquery.SchemaField("avg_evi", "FLOAT"),
                bigquery.SchemaField("analysis_date", "TIMESTAMP"),
                bigquery.SchemaField("analysis_period_start", "DATE"),
                bigquery.SchemaField("analysis_period_end", "DATE"),
            ]
        )
        
        df = pd.DataFrame(data_rows)
        job = client.load_table_from_dataframe(df, table_id, job_config=job_config)
        job.result()  # Wait for job completion
        
        logger.info("Climate data processing completed successfully")
        
        return {
            'status': 'success',
            'records_processed': len(data_rows),
            'table_id': table_id,
            'message': f'Processed {len(data_rows)} climate data points',
            'analysis_region': region_bounds,
            'analysis_period': f"{start_date} to {end_date}",
            'timestamp': datetime.now().isoformat()
        }
        
    except Exception as e:
        logger.error(f"Error processing climate data: {str(e)}")
        return {
            'status': 'error',
            'error': str(e),
            'timestamp': datetime.now().isoformat()
        }, 500