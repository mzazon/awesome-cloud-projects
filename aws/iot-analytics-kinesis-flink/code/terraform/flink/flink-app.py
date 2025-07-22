"""
Apache Flink application for real-time IoT analytics.

This application:
1. Reads IoT sensor data from Kinesis Data Streams
2. Performs windowed aggregations (5-minute tumbling windows)
3. Calculates statistics (average, min, max) for each sensor
4. Writes results to S3 for further analysis
"""

from pyflink.table import EnvironmentSettings, TableEnvironment
from pyflink.table.descriptors import Schema, Kafka, Json
import os

def create_iot_analytics_job():
    """
    Create and configure the Flink job for IoT analytics.
    
    This function sets up the Flink environment, defines source and sink tables,
    and executes the streaming analytics query.
    """
    # Set up the execution environment for streaming
    env_settings = EnvironmentSettings.new_instance().in_streaming_mode().build()
    table_env = TableEnvironment.create(env_settings)
    
    # Get configuration from environment variables
    kinesis_stream_name = "${kinesis_stream_name}"
    s3_bucket_name = "${s3_bucket_name}"
    aws_region = "${aws_region}"
    
    # Define source table from Kinesis Data Stream
    source_ddl = f"""
    CREATE TABLE iot_source (
        device_id STRING,
        timestamp TIMESTAMP(3),
        sensor_type STRING,
        value DOUBLE,
        unit STRING,
        location STRING,
        -- Define watermark for event time processing
        WATERMARK FOR timestamp AS timestamp - INTERVAL '5' SECOND
    ) WITH (
        'connector' = 'kinesis',
        'stream' = '{kinesis_stream_name}',
        'aws.region' = '{aws_region}',
        'format' = 'json',
        'json.fail-on-missing-field' = 'false',
        'json.ignore-parse-errors' = 'true'
    )
    """
    
    # Define sink table to S3 for analytics results
    sink_ddl = f"""
    CREATE TABLE iot_analytics_sink (
        device_id STRING,
        sensor_type STRING,
        location STRING,
        avg_value DOUBLE,
        max_value DOUBLE,
        min_value DOUBLE,
        record_count BIGINT,
        window_start TIMESTAMP(3),
        window_end TIMESTAMP(3)
    ) WITH (
        'connector' = 'filesystem',
        'path' = 's3://{s3_bucket_name}/analytics-results/',
        'format' = 'json',
        'sink.partition-commit.delay' = '1 min',
        'sink.partition-commit.policy.kind' = 'success-file'
    )
    """
    
    # Define aggregated metrics sink for real-time monitoring
    metrics_sink_ddl = f"""
    CREATE TABLE iot_metrics_sink (
        sensor_type STRING,
        location STRING,
        total_devices BIGINT,
        avg_value DOUBLE,
        max_value DOUBLE,
        min_value DOUBLE,
        total_records BIGINT,
        anomaly_count BIGINT,
        window_start TIMESTAMP(3),
        window_end TIMESTAMP(3)
    ) WITH (
        'connector' = 'filesystem',
        'path' = 's3://{s3_bucket_name}/metrics-results/',
        'format' = 'json',
        'sink.partition-commit.delay' = '1 min',
        'sink.partition-commit.policy.kind' = 'success-file'
    )
    """
    
    # Create tables
    table_env.execute_sql(source_ddl)
    table_env.execute_sql(sink_ddl)
    table_env.execute_sql(metrics_sink_ddl)
    
    # Define device-level analytics query
    # This query creates 5-minute tumbling windows and calculates statistics
    # for each device, sensor type, and location combination
    device_analytics_query = """
    INSERT INTO iot_analytics_sink
    SELECT 
        device_id,
        sensor_type,
        location,
        AVG(value) as avg_value,
        MAX(value) as max_value,
        MIN(value) as min_value,
        COUNT(*) as record_count,
        TUMBLE_START(timestamp, INTERVAL '5' MINUTE) as window_start,
        TUMBLE_END(timestamp, INTERVAL '5' MINUTE) as window_end
    FROM iot_source
    GROUP BY 
        device_id,
        sensor_type,
        location,
        TUMBLE(timestamp, INTERVAL '5' MINUTE)
    """
    
    # Define location-level metrics query
    # This query aggregates data by sensor type and location for broader insights
    location_metrics_query = """
    INSERT INTO iot_metrics_sink
    SELECT 
        sensor_type,
        location,
        COUNT(DISTINCT device_id) as total_devices,
        AVG(value) as avg_value,
        MAX(value) as max_value,
        MIN(value) as min_value,
        COUNT(*) as total_records,
        SUM(
            CASE 
                WHEN sensor_type = 'temperature' AND value > 80 THEN 1
                WHEN sensor_type = 'pressure' AND value > 100 THEN 1
                WHEN sensor_type = 'vibration' AND value > 50 THEN 1
                WHEN sensor_type = 'flow' AND value > 75 THEN 1
                ELSE 0
            END
        ) as anomaly_count,
        TUMBLE_START(timestamp, INTERVAL '5' MINUTE) as window_start,
        TUMBLE_END(timestamp, INTERVAL '5' MINUTE) as window_end
    FROM iot_source
    GROUP BY 
        sensor_type,
        location,
        TUMBLE(timestamp, INTERVAL '5' MINUTE)
    """
    
    # Execute the analytics queries
    # Note: In a real deployment, you might want to run these as separate jobs
    # or use Flink's async execution capabilities
    
    # Start device-level analytics
    device_job = table_env.execute_sql(device_analytics_query)
    
    # Start location-level metrics (this will run concurrently)
    metrics_job = table_env.execute_sql(location_metrics_query)
    
    print("Flink IoT Analytics application started successfully")
    print(f"Processing data from Kinesis stream: {kinesis_stream_name}")
    print(f"Writing results to S3 bucket: {s3_bucket_name}")
    
    # Keep the job running
    try:
        device_job.wait()
        metrics_job.wait()
    except KeyboardInterrupt:
        print("Stopping Flink application...")
    except Exception as e:
        print(f"Error in Flink application: {str(e)}")
        raise

def configure_flink_settings():
    """
    Configure additional Flink settings for optimal performance.
    """
    # These settings can be configured via environment variables
    # or Flink configuration when deploying to Amazon Managed Service for Apache Flink
    
    checkpoint_interval = os.environ.get('CHECKPOINT_INTERVAL', '60000')  # 1 minute
    parallelism = os.environ.get('PARALLELISM', '1')
    
    print(f"Flink configuration:")
    print(f"  Checkpoint interval: {checkpoint_interval}ms")
    print(f"  Parallelism: {parallelism}")

if __name__ == "__main__":
    """
    Main entry point for the Flink application.
    """
    try:
        print("Starting IoT Analytics Flink Application...")
        configure_flink_settings()
        create_iot_analytics_job()
    except Exception as e:
        print(f"Failed to start Flink application: {str(e)}")
        raise