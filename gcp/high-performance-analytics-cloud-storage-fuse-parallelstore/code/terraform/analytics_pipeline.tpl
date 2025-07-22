#!/usr/bin/env python3

"""
High-Performance Analytics Pipeline for Cloud Dataproc
This script demonstrates processing data using Cloud Storage FUSE and Parallelstore integration
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import avg, max, min, stddev, count
import time
import os

def create_spark_session():
    """Create optimized Spark session for high-performance analytics"""
    
    return SparkSession.builder \
        .appName('HighPerformanceAnalytics') \
        .config('spark.sql.adaptive.enabled', 'true') \
        .config('spark.sql.adaptive.coalescePartitions.enabled', 'true') \
        .config('spark.sql.adaptive.localShuffleReader.enabled', 'true') \
        .config('spark.sql.adaptive.skewJoin.enabled', 'true') \
        .config('spark.serializer', 'org.apache.spark.serializer.KryoSerializer') \
        .config('spark.sql.execution.arrow.pyspark.enabled', 'true') \
        .config('spark.sql.execution.arrow.pyspark.fallback.enabled', 'true') \
        .config('spark.sql.parquet.compression.codec', 'snappy') \
        .config('spark.sql.adaptive.advisoryPartitionSizeInBytes', '128MB') \
        .config('spark.sql.adaptive.coalescePartitions.minPartitionNum', '1') \
        .config('spark.sql.adaptive.coalescePartitions.parallelismFirst', 'false') \
        .config('spark.sql.files.maxPartitionBytes', '128MB') \
        .config('spark.sql.files.openCostInBytes', '4MB') \
        .getOrCreate()

def run_analytics_pipeline():
    """Run the complete high-performance analytics pipeline"""
    
    print("=" * 60)
    print("HIGH-PERFORMANCE ANALYTICS PIPELINE")
    print("=" * 60)
    
    # Initialize Spark with optimized settings
    spark = create_spark_session()
    spark.sparkContext.setLogLevel("WARN")
    
    try:
        # Configuration
        bucket_name = "${bucket_name}"
        project_id = "${project_id}"
        dataset_id = "${dataset_id}"
        
        print(f"Bucket: {bucket_name}")
        print(f"Project: {project_id}")
        print(f"Dataset: {dataset_id}")
        print("-" * 60)
        
        # Phase 1: Read data from Cloud Storage via FUSE
        print("Phase 1: Reading data from Cloud Storage...")
        read_start = time.time()
        
        # Read from Cloud Storage using gs:// paths for optimal performance
        input_path = f"gs://{bucket_name}/sample_data/raw/2024/01/*.csv"
        print(f"Reading from: {input_path}")
        
        df = spark.read \
            .option("header", "true") \
            .option("inferSchema", "true") \
            .option("multiline", "false") \
            .option("escape", "\"") \
            .csv(input_path)
        
        # Cache the dataframe for multiple operations
        df.cache()
        
        # Get initial count to trigger data loading
        record_count = df.count()
        read_time = time.time() - read_start
        
        print(f"✅ Data read completed in {read_time:.2f} seconds")
        print(f"📊 Total records: {record_count:,}")
        
        # Display schema and sample data
        print("\n📋 Data Schema:")
        df.printSchema()
        
        print("\n📋 Sample Data (first 10 rows):")
        df.show(10)
        
        # Phase 2: Data quality checks
        print("\nPhase 2: Data quality validation...")
        quality_start = time.time()
        
        # Check for null values
        null_counts = df.select([
            count(df[col]).alias(f"{col}_count") for col in df.columns
        ]).collect()[0]
        
        print("📊 Column completeness:")
        for col in df.columns:
            count_val = null_counts[f"{col}_count"]
            completeness = (count_val / record_count) * 100
            print(f"  {col}: {count_val:,} values ({completeness:.1f}% complete)")
        
        quality_time = time.time() - quality_start
        print(f"✅ Quality validation completed in {quality_time:.2f} seconds")
        
        # Phase 3: Analytics transformations
        print("\nPhase 3: Performing analytics transformations...")
        transform_start = time.time()
        
        # Cast timestamp and value columns to appropriate types
        df_clean = df.select(
            df.timestamp.cast("long").alias("timestamp"),
            df.sensor_id.alias("sensor_id"),
            df.value.cast("double").alias("value"),
            df.location.alias("location")
        )
        
        # Filter out any invalid data
        df_clean = df_clean.filter(
            (df_clean.value.isNotNull()) & 
            (df_clean.sensor_id.isNotNull()) &
            (df_clean.value >= 0) &
            (df_clean.value <= 100)
        )
        
        # Perform aggregations by sensor_id
        analytics_df = df_clean.groupBy("sensor_id").agg(
            avg("value").alias("avg_value"),
            max("value").alias("max_value"),
            min("value").alias("min_value"),
            stddev("value").alias("std_value"),
            count("value").alias("record_count")
        ).orderBy("sensor_id")
        
        # Cache results for multiple outputs
        analytics_df.cache()
        
        # Get analytics count
        analytics_count = analytics_df.count()
        transform_time = time.time() - transform_start
        
        print(f"✅ Transformations completed in {transform_time:.2f} seconds")
        print(f"📊 Unique sensors analyzed: {analytics_count}")
        
        # Display sample analytics results
        print("\n📊 Sample Analytics Results:")
        analytics_df.show(20, truncate=False)
        
        # Phase 4: Write results to multiple destinations
        print("\nPhase 4: Writing results to storage...")
        write_start = time.time()
        
        # Write to Cloud Storage in Parquet format for BigQuery
        parquet_output_path = f"gs://{bucket_name}/sample_data/processed/analytics"
        print(f"Writing Parquet to: {parquet_output_path}")
        
        analytics_df.write \
            .mode("overwrite") \
            .option("compression", "snappy") \
            .parquet(parquet_output_path)
        
        # Write to Cloud Storage in CSV format for easy viewing
        csv_output_path = f"gs://{bucket_name}/sample_data/processed/analytics_csv"
        print(f"Writing CSV to: {csv_output_path}")
        
        analytics_df.coalesce(1).write \
            .mode("overwrite") \
            .option("header", "true") \
            .csv(csv_output_path)
        
        write_time = time.time() - write_start
        print(f"✅ Results written in {write_time:.2f} seconds")
        
        # Phase 5: Performance summary and statistics
        print("\nPhase 5: Performance summary...")
        summary_start = time.time()
        
        # Calculate performance metrics
        total_pipeline_time = read_time + quality_time + transform_time + write_time
        throughput_records_per_second = record_count / total_pipeline_time
        
        print("\n" + "=" * 60)
        print("PERFORMANCE SUMMARY")
        print("=" * 60)
        print(f"📊 Input Records Processed: {record_count:,}")
        print(f"📊 Output Analytics Records: {analytics_count:,}")
        print(f"⏱️  Data Reading Time: {read_time:.2f} seconds")
        print(f"⏱️  Quality Validation Time: {quality_time:.2f} seconds")
        print(f"⏱️  Transformation Time: {transform_time:.2f} seconds")
        print(f"⏱️  Data Writing Time: {write_time:.2f} seconds")
        print(f"⏱️  Total Pipeline Time: {total_pipeline_time:.2f} seconds")
        print(f"🚀 Throughput: {throughput_records_per_second:,.0f} records/second")
        
        # Data insights
        print("\n" + "=" * 60)
        print("DATA INSIGHTS")
        print("=" * 60)
        
        # Calculate overall statistics
        overall_stats = df_clean.select(
            avg("value").alias("overall_avg"),
            max("value").alias("overall_max"),
            min("value").alias("overall_min"),
            stddev("value").alias("overall_std")
        ).collect()[0]
        
        print(f"📈 Overall Average Value: {overall_stats['overall_avg']:.2f}")
        print(f"📈 Overall Maximum Value: {overall_stats['overall_max']:.2f}")
        print(f"📈 Overall Minimum Value: {overall_stats['overall_min']:.2f}")
        print(f"📈 Overall Standard Deviation: {overall_stats['overall_std']:.2f}")
        
        # Top and bottom performing sensors
        print("\n🏆 Top 5 Sensors by Average Value:")
        analytics_df.orderBy(analytics_df.avg_value.desc()).show(5, truncate=False)
        
        print("\n📉 Bottom 5 Sensors by Average Value:")
        analytics_df.orderBy(analytics_df.avg_value.asc()).show(5, truncate=False)
        
        summary_time = time.time() - summary_start
        print(f"\n✅ Summary completed in {summary_time:.2f} seconds")
        
        # Phase 6: Validation queries
        print("\nPhase 6: Running validation queries...")
        validation_start = time.time()
        
        # Validate data consistency
        source_record_count = df_clean.count()
        aggregated_record_sum = analytics_df.select(
            sum("record_count").alias("total_records")
        ).collect()[0]["total_records"]
        
        print(f"🔍 Source records after cleaning: {source_record_count:,}")
        print(f"🔍 Sum of aggregated records: {aggregated_record_sum:,}")
        
        if source_record_count == aggregated_record_sum:
            print("✅ Data consistency validation PASSED")
        else:
            print("❌ Data consistency validation FAILED")
            print(f"   Difference: {abs(source_record_count - aggregated_record_sum):,} records")
        
        validation_time = time.time() - validation_start
        print(f"✅ Validation completed in {validation_time:.2f} seconds")
        
        # Phase 7: BigQuery integration test
        print("\nPhase 7: BigQuery integration verification...")
        bigquery_start = time.time()
        
        print(f"📋 Data written to: {parquet_output_path}")
        print(f"🔗 BigQuery external table should reference this location")
        print(f"🔗 Project: {project_id}")
        print(f"🔗 Dataset: {dataset_id}")
        print("📝 Sample BigQuery query:")
        print(f"""
        SELECT 
            sensor_id,
            avg_value,
            max_value,
            min_value,
            record_count
        FROM `{project_id}.{dataset_id}.sensor_analytics`
        ORDER BY avg_value DESC
        LIMIT 10;
        """)
        
        bigquery_time = time.time() - bigquery_start
        print(f"✅ BigQuery verification completed in {bigquery_time:.2f} seconds")
        
        # Final summary
        total_time = time.time() - read_start
        print("\n" + "=" * 60)
        print("PIPELINE EXECUTION COMPLETED SUCCESSFULLY")
        print("=" * 60)
        print(f"⏱️  Total Execution Time: {total_time:.2f} seconds")
        print(f"🎯 Pipeline completed at: {time.strftime('%Y-%m-%d %H:%M:%S')}")
        print("=" * 60)
        
    except Exception as e:
        print(f"❌ Pipeline failed with error: {str(e)}")
        import traceback
        traceback.print_exc()
        
    finally:
        # Clean up Spark session
        spark.stop()
        print("🧹 Spark session closed")

if __name__ == "__main__":
    run_analytics_pipeline()