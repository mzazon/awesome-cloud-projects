"""
TimesFM Financial Data Processing Cloud Function

This function processes incoming financial data, validates time series consistency,
and triggers TimesFM forecasting workflows using BigQuery's AI.FORECAST functionality.
"""

import functions_framework
from google.cloud import bigquery
import json
import logging
import os
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Configuration from environment variables
PROJECT_ID = "${project_id}"
DATASET_NAME = "${dataset_name}"
FORECAST_HORIZON_DAYS = ${forecast_horizon_days}
CONFIDENCE_LEVEL = ${confidence_level}

# Initialize BigQuery client
client = bigquery.Client(project=PROJECT_ID)

@functions_framework.http
def process_financial_data(request):
    """
    Main entry point for processing financial data and triggering forecasts.
    
    Handles both individual data ingestion and batch forecasting operations.
    """
    
    try:
        # Parse incoming request
        request_json = request.get_json(silent=True)
        if not request_json:
            return {'error': 'No JSON data provided'}, 400
        
        action = request_json.get('action', 'ingest_data')
        
        if action == 'ingest_data':
            return handle_data_ingestion(request_json)
        elif action == 'daily_forecast':
            return handle_daily_forecast(request_json)
        elif action == 'monitor_accuracy':
            return handle_accuracy_monitoring(request_json)
        else:
            return {'error': f'Unknown action: {action}'}, 400
            
    except Exception as e:
        logger.error(f"Processing error: {str(e)}")
        return {'error': str(e)}, 500

def handle_data_ingestion(request_json: Dict[str, Any]) -> tuple:
    """Handle individual financial data point ingestion."""
    
    # Validate required fields for data ingestion
    required_fields = ['symbol', 'date', 'close_price']
    if not all(field in request_json for field in required_fields):
        return {'error': 'Missing required fields: symbol, date, close_price'}, 400
    
    try:
        # Prepare data for BigQuery insertion
        table_id = f"{PROJECT_ID}.{DATASET_NAME}.stock_prices"
        
        # Validate and format data
        row_data = {
            'date': request_json['date'],
            'symbol': str(request_json['symbol']).upper(),
            'close_price': float(request_json['close_price']),
            'volume': int(request_json.get('volume', 0)) if request_json.get('volume') else None,
            'market_cap': float(request_json.get('market_cap', 0)) if request_json.get('market_cap') else None,
            'created_at': datetime.utcnow().isoformat()
        }
        
        # Insert data into BigQuery
        table = client.get_table(table_id)
        errors = client.insert_rows_json(table, [row_data])
        
        if errors:
            logger.error(f"BigQuery insert errors: {errors}")
            return {'error': 'Failed to insert data', 'details': errors}, 500
        
        logger.info(f"Successfully inserted data for {row_data['symbol']} on {row_data['date']}")
        
        # Check if we should trigger forecasting
        if should_trigger_forecast(row_data['symbol']):
            trigger_forecast_result = trigger_timesfm_forecast(row_data['symbol'])
            return {
                'status': 'success', 
                'message': 'Data processed and forecast triggered',
                'forecast_result': trigger_forecast_result
            }
        
        return {'status': 'success', 'message': 'Data processed successfully'}
        
    except ValueError as e:
        logger.error(f"Data validation error: {str(e)}")
        return {'error': f'Invalid data format: {str(e)}'}, 400
    except Exception as e:
        logger.error(f"Data ingestion error: {str(e)}")
        return {'error': f'Data ingestion failed: {str(e)}'}, 500

def handle_daily_forecast(request_json: Dict[str, Any]) -> tuple:
    """Handle scheduled daily forecasting for specified symbols."""
    
    symbols = request_json.get('symbols', ['AAPL', 'GOOGL', 'MSFT', 'AMZN'])
    results = {}
    
    for symbol in symbols:
        try:
            result = trigger_timesfm_forecast(symbol)
            results[symbol] = result
            logger.info(f"Forecast completed for {symbol}")
        except Exception as e:
            logger.error(f"Forecast failed for {symbol}: {str(e)}")
            results[symbol] = {'error': str(e)}
    
    return {
        'status': 'success',
        'message': f'Daily forecasting completed for {len(symbols)} symbols',
        'results': results
    }

def handle_accuracy_monitoring(request_json: Dict[str, Any]) -> tuple:
    """Handle forecast accuracy monitoring and metric calculation."""
    
    try:
        # Calculate accuracy metrics for recent forecasts
        accuracy_results = calculate_accuracy_metrics()
        
        # Check for alert conditions
        alerts = check_alert_conditions()
        
        return {
            'status': 'success',
            'message': 'Accuracy monitoring completed',
            'accuracy_metrics': accuracy_results,
            'alerts': alerts
        }
        
    except Exception as e:
        logger.error(f"Accuracy monitoring error: {str(e)}")
        return {'error': f'Accuracy monitoring failed: {str(e)}'}, 500

def should_trigger_forecast(symbol: str) -> bool:
    """
    Determine if we should trigger a new forecast for the given symbol.
    
    Triggers forecast if we have enough recent data points and haven't 
    forecasted recently.
    """
    
    try:
        # Check data availability
        query = f"""
        SELECT COUNT(*) as count,
               MAX(date) as latest_date
        FROM `{PROJECT_ID}.{DATASET_NAME}.stock_prices`
        WHERE symbol = '{symbol}' 
        AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 60 DAY)
        """
        
        result = client.query(query).to_dataframe()
        
        if result.empty or result['count'].iloc[0] < 30:
            logger.info(f"Insufficient data for {symbol}: {result['count'].iloc[0] if not result.empty else 0} days")
            return False
        
        # Check if we've forecasted recently
        forecast_query = f"""
        SELECT COUNT(*) as recent_forecasts
        FROM `{PROJECT_ID}.{DATASET_NAME}.timesfm_forecasts`
        WHERE symbol = '{symbol}'
        AND DATE(forecast_created_at) = CURRENT_DATE()
        """
        
        forecast_result = client.query(forecast_query).to_dataframe()
        
        if not forecast_result.empty and forecast_result['recent_forecasts'].iloc[0] > 0:
            logger.info(f"Forecast already generated today for {symbol}")
            return False
        
        return True
        
    except Exception as e:
        logger.error(f"Error checking forecast trigger for {symbol}: {str(e)}")
        return False

def trigger_timesfm_forecast(symbol: str) -> Dict[str, Any]:
    """
    Trigger TimesFM forecasting using BigQuery's AI.FORECAST function.
    
    This leverages the TimesFM foundation model for time series forecasting
    without requiring custom model training.
    """
    
    try:
        logger.info(f"Starting TimesFM forecast for {symbol}")
        
        # Create forecast using BigQuery's AI.FORECAST with TimesFM
        forecast_query = f"""
        INSERT INTO `{PROJECT_ID}.{DATASET_NAME}.timesfm_forecasts`
        (symbol, forecast_timestamp, forecast_value, 
         prediction_interval_lower_bound, prediction_interval_upper_bound,
         forecast_created_at, model_version, confidence_level)
        WITH forecast_input AS (
          SELECT 
            symbol,
            TIMESTAMP(date) as time_series_timestamp,
            close_price as time_series_data
          FROM `{PROJECT_ID}.{DATASET_NAME}.stock_prices`
          WHERE symbol = '{symbol}'
          AND date >= DATE_SUB(CURRENT_DATE(), INTERVAL 90 DAY)
          AND close_price IS NOT NULL
          ORDER BY date
        ),
        forecasts AS (
          SELECT 
            '{symbol}' as symbol,
            forecast_timestamp,
            forecast_value,
            prediction_interval_lower_bound,
            prediction_interval_upper_bound
          FROM ML.FORECAST(
            (SELECT time_series_timestamp, time_series_data FROM forecast_input),
            STRUCT(
              'time_series_timestamp' as time_column,
              'time_series_data' as data_column,
              {FORECAST_HORIZON_DAYS} as horizon,
              {CONFIDENCE_LEVEL} as confidence_level
            )
          )
        )
        SELECT 
          symbol,
          forecast_timestamp,
          forecast_value,
          prediction_interval_lower_bound,
          prediction_interval_upper_bound,
          CURRENT_TIMESTAMP() as forecast_created_at,
          'TimesFM-1.0' as model_version,
          {CONFIDENCE_LEVEL} as confidence_level
        FROM forecasts
        """
        
        job = client.query(forecast_query)
        job.result()  # Wait for the query to complete
        
        logger.info(f"TimesFM forecast completed for {symbol}")
        
        # Get forecast summary
        summary_query = f"""
        SELECT 
          COUNT(*) as forecast_points,
          MIN(forecast_value) as min_forecast,
          MAX(forecast_value) as max_forecast,
          AVG(forecast_value) as avg_forecast
        FROM `{PROJECT_ID}.{DATASET_NAME}.timesfm_forecasts`
        WHERE symbol = '{symbol}'
        AND DATE(forecast_created_at) = CURRENT_DATE()
        """
        
        summary = client.query(summary_query).to_dataframe()
        
        return {
            'status': 'success',
            'symbol': symbol,
            'forecast_points': int(summary['forecast_points'].iloc[0]) if not summary.empty else 0,
            'forecast_range': {
                'min': float(summary['min_forecast'].iloc[0]) if not summary.empty and summary['min_forecast'].iloc[0] is not None else None,
                'max': float(summary['max_forecast'].iloc[0]) if not summary.empty and summary['max_forecast'].iloc[0] is not None else None,
                'avg': float(summary['avg_forecast'].iloc[0]) if not summary.empty and summary['avg_forecast'].iloc[0] is not None else None
            }
        }
        
    except Exception as e:
        logger.error(f"TimesFM forecast error for {symbol}: {str(e)}")
        return {'status': 'error', 'symbol': symbol, 'error': str(e)}

def calculate_accuracy_metrics() -> Dict[str, Any]:
    """Calculate and store accuracy metrics for recent forecasts."""
    
    try:
        # Calculate accuracy metrics
        metrics_query = f"""
        INSERT INTO `{PROJECT_ID}.{DATASET_NAME}.forecast_metrics`
        (symbol, metric_date, avg_percentage_error, error_std_dev, 
         forecast_count, accuracy_rate, calculated_at)
        WITH accuracy_data AS (
          SELECT 
            f.symbol,
            DATE(f.forecast_timestamp) as forecast_date,
            ABS(f.forecast_value - a.close_price) / a.close_price * 100 as percentage_error,
            CASE 
              WHEN a.close_price BETWEEN f.prediction_interval_lower_bound AND f.prediction_interval_upper_bound 
              THEN 1.0 ELSE 0.0 
            END as within_interval
          FROM `{PROJECT_ID}.{DATASET_NAME}.timesfm_forecasts` f
          INNER JOIN `{PROJECT_ID}.{DATASET_NAME}.stock_prices` a
            ON f.symbol = a.symbol 
            AND DATE(f.forecast_timestamp) = a.date
          WHERE DATE(f.forecast_timestamp) >= DATE_SUB(CURRENT_DATE(), INTERVAL 7 DAY)
          AND DATE(f.forecast_timestamp) < CURRENT_DATE()
        )
        SELECT 
          symbol,
          forecast_date as metric_date,
          AVG(percentage_error) as avg_percentage_error,
          STDDEV(percentage_error) as error_std_dev,
          COUNT(*) as forecast_count,
          AVG(within_interval) * 100 as accuracy_rate,
          CURRENT_TIMESTAMP() as calculated_at
        FROM accuracy_data
        GROUP BY symbol, forecast_date
        HAVING COUNT(*) > 0
        """
        
        job = client.query(metrics_query)
        job.result()
        
        # Get summary of calculated metrics
        summary_query = f"""
        SELECT 
          COUNT(DISTINCT symbol) as symbols_analyzed,
          COUNT(*) as metrics_calculated,
          AVG(avg_percentage_error) as overall_avg_error,
          AVG(accuracy_rate) as overall_accuracy_rate
        FROM `{PROJECT_ID}.{DATASET_NAME}.forecast_metrics`
        WHERE DATE(calculated_at) = CURRENT_DATE()
        """
        
        summary = client.query(summary_query).to_dataframe()
        
        return {
            'symbols_analyzed': int(summary['symbols_analyzed'].iloc[0]) if not summary.empty else 0,
            'metrics_calculated': int(summary['metrics_calculated'].iloc[0]) if not summary.empty else 0,
            'overall_avg_error': float(summary['overall_avg_error'].iloc[0]) if not summary.empty and summary['overall_avg_error'].iloc[0] is not None else None,
            'overall_accuracy_rate': float(summary['overall_accuracy_rate'].iloc[0]) if not summary.empty and summary['overall_accuracy_rate'].iloc[0] is not None else None
        }
        
    except Exception as e:
        logger.error(f"Error calculating accuracy metrics: {str(e)}")
        return {'error': str(e)}

def check_alert_conditions() -> List[Dict[str, Any]]:
    """Check for alert conditions based on recent forecast performance."""
    
    try:
        alerts_query = f"""
        SELECT 
          symbol,
          alert_level,
          alert_message,
          alert_priority,
          business_impact,
          recommendation
        FROM `{PROJECT_ID}.{DATASET_NAME}.alert_conditions`
        WHERE alert_level != 'NORMAL'
        AND metric_date >= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
        ORDER BY 
          CASE alert_priority
            WHEN 'CRITICAL' THEN 1
            WHEN 'HIGH' THEN 2
            WHEN 'MEDIUM' THEN 3
            ELSE 4
          END,
          symbol
        LIMIT 20
        """
        
        alerts_df = client.query(alerts_query).to_dataframe()
        
        if alerts_df.empty:
            return []
        
        alerts = []
        for _, row in alerts_df.iterrows():
            alerts.append({
                'symbol': row['symbol'],
                'level': row['alert_level'],
                'message': row['alert_message'],
                'priority': row['alert_priority'],
                'impact': row['business_impact'],
                'recommendation': row['recommendation']
            })
        
        return alerts
        
    except Exception as e:
        logger.error(f"Error checking alert conditions: {str(e)}")
        return [{'error': str(e)}]