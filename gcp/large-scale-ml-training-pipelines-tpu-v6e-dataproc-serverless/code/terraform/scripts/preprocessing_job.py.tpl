#!/usr/bin/env python3
"""
Dataproc Serverless preprocessing job for ML training pipeline.
This script processes raw training data and prepares it for TPU consumption.
"""

from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import sys
import logging

def setup_logging():
    """Configure logging for the preprocessing job."""
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    return logging.getLogger(__name__)

def create_spark_session():
    """Create optimized Spark session for TPU data preprocessing."""
    return SparkSession.builder \
        .appName("ML-Data-Preprocessing-TPU-Pipeline") \
        .config("spark.sql.adaptive.enabled", "true") \
        .config("spark.sql.adaptive.coalescePartitions.enabled", "true") \
        .config("spark.sql.adaptive.skewJoin.enabled", "true") \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.sql.execution.arrow.pyspark.enabled", "true") \
        .getOrCreate()

def preprocess_training_data(spark, input_path, output_path, logger):
    """
    Preprocess training data for TPU v6e consumption.
    
    Args:
        spark: SparkSession object
        input_path: Path to raw training data
        output_path: Path for processed data output
        logger: Logger instance
    """
    logger.info(f"Starting data preprocessing from {input_path}")
    
    try:
        # Read raw text data with error handling
        logger.info("Reading raw training data...")
        df = spark.read.option("multiline", "true") \
                      .option("encoding", "UTF-8") \
                      .text(input_path)
        
        logger.info(f"Raw data count: {df.count()} records")
        
        # Data preprocessing optimized for language model training
        logger.info("Applying preprocessing transformations...")
        processed_df = df.select(
            col("value").alias("text")
        ).filter(
            # Filter out empty lines and very short text
            (length(col("text")) > 10) & 
            (col("text").isNotNull()) &
            (~col("text").rlike(r"^\s*$"))
        ).withColumn(
            # Add sequence length for TPU batching optimization
            "sequence_length", length(col("text"))
        ).withColumn(
            # Add unique ID for tracking
            "record_id", monotonically_increasing_id()
        ).filter(
            # Filter sequences that are too long for efficient TPU processing
            col("sequence_length") <= 2048
        )
        
        # Optimize partitioning for TPU consumption (100 partitions for v6e-8)
        logger.info("Optimizing partitioning for TPU consumption...")
        final_df = processed_df.repartition(100)
        
        # Add data quality metrics
        logger.info("Computing data quality metrics...")
        total_records = final_df.count()
        avg_length = final_df.agg(avg("sequence_length")).collect()[0][0]
        
        logger.info(f"Processed data statistics:")
        logger.info(f"  Total records: {total_records}")
        logger.info(f"  Average sequence length: {avg_length:.2f}")
        
        # Write preprocessed data in Parquet format with optimized compression
        logger.info(f"Writing processed data to {output_path}")
        final_df.select("record_id", "text", "sequence_length") \
                .write \
                .mode("overwrite") \
                .option("compression", "snappy") \
                .option("parquet.block.size", "268435456")  # 256MB blocks
                .parquet(output_path)
        
        # Write metadata file for training pipeline
        metadata = spark.createDataFrame([
            (total_records, avg_length, "snappy", 100)
        ], ["total_records", "avg_sequence_length", "compression", "num_partitions"])
        
        metadata.write.mode("overwrite").json(f"{output_path}_metadata")
        
        logger.info("Data preprocessing completed successfully")
        
    except Exception as e:
        logger.error(f"Error during preprocessing: {str(e)}")
        raise
    
    finally:
        spark.stop()

def main():
    """Main function for the preprocessing job."""
    logger = setup_logging()
    
    if len(sys.argv) != 3:
        logger.error("Usage: preprocessing_job.py <input_path> <output_path>")
        sys.exit(1)
    
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    logger.info(f"Dataproc Serverless preprocessing job started")
    logger.info(f"Input path: {input_path}")
    logger.info(f"Output path: {output_path}")
    logger.info(f"Bucket: ${bucket_name}")
    
    # Create Spark session
    spark = create_spark_session()
    
    try:
        # Process the data
        preprocess_training_data(spark, input_path, output_path, logger)
        logger.info("Preprocessing job completed successfully")
        
    except Exception as e:
        logger.error(f"Preprocessing job failed: {str(e)}")
        sys.exit(1)

if __name__ == "__main__":
    main()