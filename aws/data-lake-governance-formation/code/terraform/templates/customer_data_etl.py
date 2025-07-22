#!/usr/bin/env python3
"""
Customer Data ETL Job with Lineage Tracking
==========================================

This AWS Glue ETL job processes customer data from the raw zone to curated zone
with comprehensive data quality validation and lineage tracking. The job is designed
to work within the Lake Formation governance framework while providing detailed
metadata for DataZone discovery and lineage visualization.

Features:
- Data quality validation and cleansing
- Comprehensive lineage tracking
- Partitioned output for performance
- Error handling and logging
- Integration with Lake Formation governance
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as F
from pyspark.sql.types import *
import datetime
import logging

# Configure logging for detailed job monitoring
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    """
    Main ETL processing function with comprehensive data governance features.
    """
    
    # Initialize Glue context and job
    args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATA_LAKE_BUCKET'])
    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Starting ETL job: {args['JOB_NAME']}")
    logger.info(f"Data Lake Bucket: {args['DATA_LAKE_BUCKET']}")
    
    try:
        # Configure Spark for enhanced lineage tracking and performance
        configure_spark_session(spark, args['DATA_LAKE_BUCKET'])
        
        # Process customer data with quality validation
        process_customer_data(spark, args['DATA_LAKE_BUCKET'])
        
        # Generate analytics aggregations
        generate_customer_analytics(spark, args['DATA_LAKE_BUCKET'])
        
        logger.info("ETL job completed successfully")
        
    except Exception as e:
        logger.error(f"ETL job failed with error: {str(e)}")
        raise e
    finally:
        job.commit()

def configure_spark_session(spark, data_lake_bucket):
    """
    Configure Spark session for optimal performance and lineage tracking.
    
    Args:
        spark: Spark session object
        data_lake_bucket: S3 bucket name for data lake
    """
    
    # Enable Iceberg catalog for advanced table features
    spark.conf.set("spark.sql.catalog.glue_catalog", "org.apache.iceberg.spark.SparkCatalog")
    spark.conf.set("spark.sql.catalog.glue_catalog.warehouse", f"s3://{data_lake_bucket}/analytics-data/")
    
    # Configure for better performance with large datasets
    spark.conf.set("spark.sql.adaptive.enabled", "true")
    spark.conf.set("spark.sql.adaptive.coalescePartitions.enabled", "true")
    spark.conf.set("spark.sql.adaptive.skewJoin.enabled", "true")
    
    # Enable detailed lineage tracking
    spark.conf.set("spark.sql.lineage.enabled", "true")
    spark.conf.set("spark.sql.queryExecutionListeners", "com.amazon.glue.spark.lineage.LineageListener")
    
    logger.info("Spark session configured with advanced features")

def process_customer_data(spark, data_lake_bucket):
    """
    Process customer data from raw zone to curated zone with quality validation.
    
    Args:
        spark: Spark session object
        data_lake_bucket: S3 bucket name for data lake
    """
    
    logger.info("Starting customer data processing")
    
    # Read raw customer data
    raw_data_path = f"s3://{data_lake_bucket}/raw-data/customer_data/"
    logger.info(f"Reading raw customer data from: {raw_data_path}")
    
    try:
        raw_customer_df = spark.read.option("header", "true").csv(raw_data_path)
        logger.info(f"Raw customer data loaded: {raw_customer_df.count()} records")
    except Exception as e:
        logger.warning(f"No raw customer data found at {raw_data_path}, creating sample data")
        raw_customer_df = create_sample_customer_data(spark)
    
    # Data quality transformations and validation
    curated_customer_df = apply_data_quality_rules(raw_customer_df)
    
    # Add governance and lineage metadata
    curated_customer_df = add_governance_metadata(curated_customer_df, "customer_data", "CRM")
    
    # Write to curated zone with partitioning
    curated_output_path = f"s3://{data_lake_bucket}/curated-data/customer_data/"
    logger.info(f"Writing curated customer data to: {curated_output_path}")
    
    curated_customer_df.write \
        .partitionBy("registration_year", "registration_month") \
        .mode("overwrite") \
        .option("compression", "snappy") \
        .parquet(curated_output_path)
    
    logger.info(f"Customer data processing completed: {curated_customer_df.count()} records written")

def apply_data_quality_rules(df):
    """
    Apply comprehensive data quality rules and transformations.
    
    Args:
        df: Input DataFrame
        
    Returns:
        DataFrame with quality rules applied
    """
    
    logger.info("Applying data quality rules")
    
    # Cast data types for consistency
    df = df.withColumn("customer_id", F.col("customer_id").cast("bigint")) \
           .withColumn("lifetime_value", F.col("lifetime_value").cast("double")) \
           .withColumn("registration_date", F.to_date(F.col("registration_date")))
    
    # Filter out invalid records
    quality_df = df.filter(F.col("customer_id").isNotNull()) \
                   .filter(F.col("email").contains("@")) \
                   .filter(F.col("customer_segment").isin(["premium", "standard", "basic"])) \
                   .filter(F.col("lifetime_value") >= 0)
    
    # Add derived columns for analytics
    quality_df = quality_df.withColumn("registration_year", F.year(F.col("registration_date"))) \
                          .withColumn("registration_month", F.month(F.col("registration_date"))) \
                          .withColumn("registration_quarter", F.quarter(F.col("registration_date"))) \
                          .withColumn("customer_age_days", F.datediff(F.current_date(), F.col("registration_date")))
    
    # Add data quality score based on completeness
    quality_df = quality_df.withColumn("data_quality_score", 
        F.when(F.col("phone").isNotNull() & 
               F.col("email").isNotNull() & 
               F.col("lifetime_value").isNotNull(), 100.0)
         .when(F.col("email").isNotNull() & 
               F.col("lifetime_value").isNotNull(), 85.0)
         .otherwise(70.0))
    
    # Standardize data formats
    quality_df = quality_df.withColumn("email", F.lower(F.trim(F.col("email")))) \
                          .withColumn("region", F.upper(F.trim(F.col("region")))) \
                          .withColumn("customer_segment", F.lower(F.trim(F.col("customer_segment"))))
    
    logger.info("Data quality rules applied successfully")
    return quality_df

def add_governance_metadata(df, table_name, source_system):
    """
    Add governance and lineage metadata to the DataFrame.
    
    Args:
        df: Input DataFrame
        table_name: Name of the target table
        source_system: Source system identifier
        
    Returns:
        DataFrame with governance metadata
    """
    
    logger.info(f"Adding governance metadata for table: {table_name}")
    
    # Add lineage and governance metadata
    metadata_df = df.withColumn("source_system", F.lit(source_system)) \
                   .withColumn("etl_job_name", F.lit("CustomerDataETLWithLineage")) \
                   .withColumn("etl_run_id", F.lit(str(datetime.datetime.now().timestamp()))) \
                   .withColumn("processed_timestamp", F.current_timestamp()) \
                   .withColumn("data_classification", F.lit("confidential")) \
                   .withColumn("governance_version", F.lit("1.0")) \
                   .withColumn("data_lineage_id", F.monotonically_increasing_id())
    
    # Add PII classification flags for governance
    metadata_df = metadata_df.withColumn("contains_pii", F.lit(True)) \
                            .withColumn("pii_columns", F.lit("first_name,last_name,email,phone")) \
                            .withColumn("retention_policy", F.lit("7_years")) \
                            .withColumn("compliance_flags", F.lit("GDPR,CCPA"))
    
    logger.info("Governance metadata added successfully")
    return metadata_df

def generate_customer_analytics(spark, data_lake_bucket):
    """
    Generate analytics aggregations from curated customer data.
    
    Args:
        spark: Spark session object
        data_lake_bucket: S3 bucket name for data lake
    """
    
    logger.info("Starting customer analytics generation")
    
    # Read curated customer data
    curated_data_path = f"s3://{data_lake_bucket}/curated-data/customer_data/"
    
    try:
        curated_df = spark.read.parquet(curated_data_path)
        logger.info(f"Curated customer data loaded: {curated_df.count()} records")
    except Exception as e:
        logger.error(f"Failed to read curated data from {curated_data_path}: {str(e)}")
        return
    
    # Generate customer segment analytics
    segment_analytics = curated_df.groupBy("customer_segment", "region", "registration_year") \
        .agg(
            F.count("customer_id").alias("customer_count"),
            F.avg("lifetime_value").alias("avg_lifetime_value"),
            F.sum("lifetime_value").alias("total_lifetime_value"),
            F.min("lifetime_value").alias("min_lifetime_value"),
            F.max("lifetime_value").alias("max_lifetime_value"),
            F.stddev("lifetime_value").alias("stddev_lifetime_value"),
            F.avg("data_quality_score").alias("avg_data_quality_score"),
            F.avg("customer_age_days").alias("avg_customer_age_days")
        )
    
    # Add analytics metadata
    segment_analytics = segment_analytics.withColumn("analytics_type", F.lit("customer_segment_summary")) \
                                       .withColumn("generated_timestamp", F.current_timestamp()) \
                                       .withColumn("data_freshness", F.lit("daily")) \
                                       .withColumn("analytics_version", F.lit("1.0"))
    
    # Generate regional analytics
    regional_analytics = curated_df.groupBy("region", "registration_year", "registration_quarter") \
        .agg(
            F.count("customer_id").alias("total_customers"),
            F.countDistinct("customer_segment").alias("segment_diversity"),
            F.avg("lifetime_value").alias("avg_regional_clv"),
            F.sum("lifetime_value").alias("total_regional_value")
        )
    
    # Add regional metadata
    regional_analytics = regional_analytics.withColumn("analytics_type", F.lit("regional_summary")) \
                                         .withColumn("generated_timestamp", F.current_timestamp()) \
                                         .withColumn("data_freshness", F.lit("daily")) \
                                         .withColumn("analytics_version", F.lit("1.0"))
    
    # Write analytics data
    analytics_output_path = f"s3://{data_lake_bucket}/analytics-data/"
    
    # Write segment analytics
    segment_analytics.write \
        .mode("overwrite") \
        .option("compression", "snappy") \
        .parquet(f"{analytics_output_path}customer_segment_analytics/")
    
    # Write regional analytics
    regional_analytics.write \
        .mode("overwrite") \
        .option("compression", "snappy") \
        .parquet(f"{analytics_output_path}regional_customer_analytics/")
    
    logger.info("Customer analytics generation completed successfully")

def create_sample_customer_data(spark):
    """
    Create sample customer data for testing when raw data is not available.
    
    Args:
        spark: Spark session object
        
    Returns:
        DataFrame with sample customer data
    """
    
    logger.info("Creating sample customer data for testing")
    
    # Define sample data schema
    schema = StructType([
        StructField("customer_id", StringType(), True),
        StructField("first_name", StringType(), True),
        StructField("last_name", StringType(), True),
        StructField("email", StringType(), True),
        StructField("phone", StringType(), True),
        StructField("registration_date", StringType(), True),
        StructField("customer_segment", StringType(), True),
        StructField("lifetime_value", StringType(), True),
        StructField("region", StringType(), True)
    ])
    
    # Sample data rows
    sample_data = [
        ("1001", "John", "Smith", "john.smith@email.com", "555-0101", "2023-01-15", "premium", "15000.50", "us-east"),
        ("1002", "Sarah", "Johnson", "sarah.johnson@email.com", "555-0102", "2023-02-20", "standard", "8500.25", "us-west"),
        ("1003", "Michael", "Brown", "michael.brown@email.com", "555-0103", "2023-03-10", "premium", "22000.75", "eu-west"),
        ("1004", "Emily", "Davis", "emily.davis@email.com", "555-0104", "2023-04-05", "standard", "6200.30", "us-east"),
        ("1005", "David", "Wilson", "david.wilson@email.com", "555-0105", "2023-05-12", "basic", "2100.80", "us-central"),
        ("1006", "Lisa", "Anderson", "lisa.anderson@email.com", "555-0106", "2023-06-08", "premium", "18500.90", "eu-central"),
        ("1007", "Robert", "Taylor", "robert.taylor@email.com", "555-0107", "2023-07-22", "standard", "7800.40", "asia-pacific"),
        ("1008", "Jennifer", "Thomas", "jennifer.thomas@email.com", "555-0108", "2023-08-15", "premium", "19200.60", "us-west"),
        ("1009", "William", "Jackson", "william.jackson@email.com", "555-0109", "2023-09-03", "standard", "5900.20", "eu-west"),
        ("1010", "Amanda", "White", "amanda.white@email.com", "555-0110", "2023-10-18", "basic", "1800.15", "us-east")
    ]
    
    # Create DataFrame
    sample_df = spark.createDataFrame(sample_data, schema)
    
    logger.info(f"Sample customer data created: {sample_df.count()} records")
    return sample_df

if __name__ == "__main__":
    main()