#!/usr/bin/env python3
"""
AWS Glue ETL Script for Data Lake Ingestion Pipeline
This script implements the medallion architecture (Bronze, Silver, Gold layers)
for processing data lake content with comprehensive data quality and transformation.

Template Variables:
- database_name: ${database_name}
- s3_bucket_name: ${s3_bucket_name}
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import DataFrame
from pyspark.sql.functions import *
from pyspark.sql.types import *
import boto3

# Initialize Glue context and Spark session
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session

# Get job parameters with defaults
args = getResolvedOptions(sys.argv, [
    'JOB_NAME',
    'DATABASE_NAME',
    'S3_BUCKET_NAME'
])

# Initialize the Glue job
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Job parameters
DATABASE_NAME = args.get('DATABASE_NAME', '${database_name}')
S3_BUCKET_NAME = args.get('S3_BUCKET_NAME', '${s3_bucket_name}')

print(f"Starting ETL job for database: {DATABASE_NAME}")
print(f"Using S3 bucket: {S3_BUCKET_NAME}")

try:
    # =====================================================
    # Data Source Discovery and Loading
    # =====================================================
    
    print("Discovering available tables in Data Catalog...")
    
    # Get Glue client to list tables
    glue_client = boto3.client('glue')
    
    # List all tables in the database
    tables_response = glue_client.get_tables(DatabaseName=DATABASE_NAME)
    table_names = [table['Name'] for table in tables_response['TableList']]
    
    print(f"Found tables: {table_names}")
    
    # Initialize DataFrames dictionary
    dataframes = {}
    
    # Load each table from the Data Catalog
    for table_name in table_names:
        try:
            print(f"Loading table: {table_name}")
            dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
                database=DATABASE_NAME,
                table_name=table_name
            )
            dataframes[table_name] = dynamic_frame.toDF()
            print(f"Successfully loaded {table_name} with {dataframes[table_name].count()} rows")
        except Exception as e:
            print(f"Warning: Could not load table {table_name}: {str(e)}")
            continue
    
    # Check if we have the expected tables
    events_table = None
    customers_table = None
    
    for table_name in table_names:
        if 'events' in table_name.lower() and table_name in dataframes:
            events_table = table_name
        elif 'customers' in table_name.lower() and table_name in dataframes:
            customers_table = table_name
    
    if not events_table:
        print("Warning: No events table found. Creating sample data...")
        # Create sample events data if not found
        events_data = [
            ("evt001", "user123", "purchase", "prod456", 89.99, "2024-01-15T10:30:00Z", "electronics"),
            ("evt002", "user456", "view", "prod789", 0.0, "2024-01-15T10:31:00Z", "books"),
            ("evt003", "user789", "cart_add", "prod123", 45.50, "2024-01-15T10:32:00Z", "clothing"),
            ("evt004", "user123", "purchase", "prod321", 129.00, "2024-01-15T10:33:00Z", "home"),
            ("evt005", "user654", "view", "prod555", 0.0, "2024-01-15T10:34:00Z", "electronics")
        ]
        
        events_schema = StructType([
            StructField("event_id", StringType(), True),
            StructField("user_id", StringType(), True),
            StructField("event_type", StringType(), True),
            StructField("product_id", StringType(), True),
            StructField("amount", DoubleType(), True),
            StructField("timestamp", StringType(), True),
            StructField("category", StringType(), True)
        ])
        
        dataframes['sample_events'] = spark.createDataFrame(events_data, events_schema)
        events_table = 'sample_events'
    
    if not customers_table:
        print("Warning: No customers table found. Creating sample data...")
        # Create sample customers data if not found
        customers_data = [
            ("user123", "John Doe", "john.doe@example.com", "2023-05-15", "US", "25-34"),
            ("user456", "Jane Smith", "jane.smith@example.com", "2023-06-20", "CA", "35-44"),
            ("user789", "Bob Johnson", "bob.johnson@example.com", "2023-07-10", "UK", "45-54"),
            ("user654", "Alice Brown", "alice.brown@example.com", "2023-08-05", "US", "18-24"),
            ("user321", "Charlie Wilson", "charlie.wilson@example.com", "2023-09-12", "AU", "25-34")
        ]
        
        customers_schema = StructType([
            StructField("customer_id", StringType(), True),
            StructField("name", StringType(), True),
            StructField("email", StringType(), True),
            StructField("registration_date", StringType(), True),
            StructField("country", StringType(), True),
            StructField("age_group", StringType(), True)
        ])
        
        dataframes['sample_customers'] = spark.createDataFrame(customers_data, customers_schema)
        customers_table = 'sample_customers'
    
    events_df = dataframes[events_table]
    customers_df = dataframes[customers_table]
    
    print(f"Using events table: {events_table}")
    print(f"Using customers table: {customers_table}")
    
    # =====================================================
    # Bronze Layer: Raw Data with Basic Cleansing
    # =====================================================
    
    print("Processing Bronze Layer...")
    
    # Clean and standardize events data
    events_bronze = events_df.withColumn(
        "timestamp", 
        to_timestamp(col("timestamp"))
    ).withColumn(
        "amount", 
        col("amount").cast("double")
    ).filter(
        col("event_id").isNotNull() & 
        col("user_id").isNotNull() &
        col("event_type").isNotNull()
    )
    
    # Add processing metadata
    events_bronze = events_bronze.withColumn(
        "processing_date", 
        current_date()
    ).withColumn(
        "processing_timestamp", 
        current_timestamp()
    ).withColumn(
        "data_source",
        lit("bronze_layer")
    )
    
    # Data quality checks for Bronze layer
    bronze_row_count = events_bronze.count()
    original_row_count = events_df.count()
    
    print(f"Bronze layer processing: {original_row_count} -> {bronze_row_count} rows")
    
    if bronze_row_count == 0:
        raise Exception("Bronze layer processing resulted in no data - check data quality")
    
    # Write to Bronze layer
    bronze_path = f"s3://{S3_BUCKET_NAME}/processed-data/bronze/events/"
    print(f"Writing Bronze layer to: {bronze_path}")
    
    events_bronze.write.mode("overwrite").option("compression", "snappy").parquet(bronze_path)
    
    # =====================================================
    # Silver Layer: Business Logic and Data Enrichment
    # =====================================================
    
    print("Processing Silver Layer...")
    
    # Enrich events with customer data
    events_silver = events_bronze.join(
        customers_df,
        events_bronze.user_id == customers_df.customer_id,
        "left"
    ).select(
        events_bronze["*"],
        customers_df["name"].alias("customer_name"),
        customers_df["email"].alias("customer_email"),
        customers_df["country"],
        customers_df["age_group"],
        customers_df["registration_date"].alias("customer_registration_date")
    )
    
    # Add business metrics and derived fields
    events_silver = events_silver.withColumn(
        "is_purchase", 
        when(col("event_type") == "purchase", 1).otherwise(0)
    ).withColumn(
        "is_high_value", 
        when(col("amount") > 100, 1).otherwise(0)
    ).withColumn(
        "event_date", 
        to_date(col("timestamp"))
    ).withColumn(
        "event_hour", 
        hour(col("timestamp"))
    ).withColumn(
        "event_day_of_week",
        dayofweek(col("timestamp"))
    ).withColumn(
        "event_month",
        month(col("timestamp"))
    ).withColumn(
        "event_year",
        year(col("timestamp"))
    )
    
    # Add customer lifetime calculations
    events_silver = events_silver.withColumn(
        "customer_lifetime_days",
        datediff(col("processing_date"), to_date(col("customer_registration_date")))
    )
    
    # Data quality checks for Silver layer
    silver_row_count = events_silver.count()
    print(f"Silver layer processing: {bronze_row_count} -> {silver_row_count} rows")
    
    # Check for data quality issues
    null_customer_count = events_silver.filter(col("customer_name").isNull()).count()
    if null_customer_count > 0:
        print(f"Warning: {null_customer_count} events have no matching customer data")
    
    # Write to Silver layer partitioned by date
    silver_path = f"s3://{S3_BUCKET_NAME}/processed-data/silver/events/"
    print(f"Writing Silver layer to: {silver_path}")
    
    events_silver.write.mode("overwrite").partitionBy("event_date").option("compression", "snappy").parquet(silver_path)
    
    # =====================================================
    # Gold Layer: Analytics-Ready Aggregated Data
    # =====================================================
    
    print("Processing Gold Layer...")
    
    # Daily sales summary by category and country
    daily_sales = events_silver.filter(
        col("event_type") == "purchase"
    ).groupBy(
        "event_date", "category", "country"
    ).agg(
        count("*").alias("total_purchases"),
        sum("amount").alias("total_revenue"),
        avg("amount").alias("avg_order_value"),
        countDistinct("user_id").alias("unique_customers"),
        max("amount").alias("max_order_value"),
        min("amount").alias("min_order_value")
    ).withColumn(
        "revenue_per_customer",
        col("total_revenue") / col("unique_customers")
    )
    
    # Customer behavior and lifetime value analysis
    customer_behavior = events_silver.groupBy(
        "user_id", "customer_name", "country", "age_group", "customer_registration_date"
    ).agg(
        count("*").alias("total_events"),
        sum("is_purchase").alias("total_purchases"),
        sum("amount").alias("total_spent"),
        countDistinct("category").alias("categories_engaged"),
        countDistinct("event_date").alias("active_days"),
        max("event_date").alias("last_activity_date"),
        min("event_date").alias("first_activity_date")
    ).withColumn(
        "avg_order_value",
        when(col("total_purchases") > 0, col("total_spent") / col("total_purchases")).otherwise(0)
    ).withColumn(
        "conversion_rate",
        when(col("total_events") > 0, col("total_purchases") / col("total_events")).otherwise(0)
    ).withColumn(
        "customer_lifetime_value",
        col("total_spent")
    )
    
    # Product performance analysis
    product_performance = events_silver.filter(
        col("event_type").isin(["purchase", "view", "cart_add"])
    ).groupBy(
        "product_id", "category"
    ).agg(
        countDistinct(when(col("event_type") == "view", col("user_id"))).alias("unique_viewers"),
        countDistinct(when(col("event_type") == "cart_add", col("user_id"))).alias("unique_cart_adds"),
        countDistinct(when(col("event_type") == "purchase", col("user_id"))).alias("unique_purchasers"),
        sum(when(col("event_type") == "purchase", col("amount"))).alias("total_revenue"),
        count(when(col("event_type") == "purchase", 1)).alias("total_purchases")
    ).withColumn(
        "view_to_cart_rate",
        when(col("unique_viewers") > 0, col("unique_cart_adds") / col("unique_viewers")).otherwise(0)
    ).withColumn(
        "cart_to_purchase_rate",
        when(col("unique_cart_adds") > 0, col("unique_purchasers") / col("unique_cart_adds")).otherwise(0)
    ).withColumn(
        "view_to_purchase_rate",
        when(col("unique_viewers") > 0, col("unique_purchasers") / col("unique_viewers")).otherwise(0)
    )
    
    # Hourly activity patterns
    hourly_patterns = events_silver.groupBy(
        "event_hour", "event_type"
    ).agg(
        count("*").alias("event_count"),
        sum("amount").alias("total_amount"),
        countDistinct("user_id").alias("unique_users")
    ).withColumn(
        "avg_amount_per_event",
        when(col("event_count") > 0, col("total_amount") / col("event_count")).otherwise(0)
    )
    
    # Data quality checks for Gold layer
    print(f"Gold layer tables created:")
    print(f"- Daily sales: {daily_sales.count()} rows")
    print(f"- Customer behavior: {customer_behavior.count()} rows")
    print(f"- Product performance: {product_performance.count()} rows")
    print(f"- Hourly patterns: {hourly_patterns.count()} rows")
    
    # Write Gold layer datasets
    gold_base_path = f"s3://{S3_BUCKET_NAME}/processed-data/gold/"
    
    print(f"Writing Gold layer to: {gold_base_path}")
    
    daily_sales.write.mode("overwrite").option("compression", "snappy").parquet(f"{gold_base_path}daily_sales/")
    customer_behavior.write.mode("overwrite").option("compression", "snappy").parquet(f"{gold_base_path}customer_behavior/")
    product_performance.write.mode("overwrite").option("compression", "snappy").parquet(f"{gold_base_path}product_performance/")
    hourly_patterns.write.mode("overwrite").option("compression", "snappy").parquet(f"{gold_base_path}hourly_patterns/")
    
    # =====================================================
    # Update Data Catalog with New Tables
    # =====================================================
    
    print("Updating Data Catalog with processed tables...")
    
    # Create DynamicFrames for catalog registration
    try:
        # Bronze events
        bronze_events_df = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [bronze_path]
            },
            format="parquet"
        )
        
        glueContext.write_dynamic_frame.from_catalog(
            frame=bronze_events_df,
            database=DATABASE_NAME,
            table_name="bronze_events",
            transformation_ctx="bronze_events_write"
        )
        
        # Silver events  
        silver_events_df = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [silver_path]
            },
            format="parquet"
        )
        
        glueContext.write_dynamic_frame.from_catalog(
            frame=silver_events_df,
            database=DATABASE_NAME,
            table_name="silver_events",
            transformation_ctx="silver_events_write"
        )
        
        # Gold layer tables
        daily_sales_df = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [f"{gold_base_path}daily_sales/"]
            },
            format="parquet"
        )
        
        glueContext.write_dynamic_frame.from_catalog(
            frame=daily_sales_df,
            database=DATABASE_NAME,
            table_name="gold_daily_sales",
            transformation_ctx="daily_sales_write"
        )
        
        customer_behavior_df = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [f"{gold_base_path}customer_behavior/"]
            },
            format="parquet"
        )
        
        glueContext.write_dynamic_frame.from_catalog(
            frame=customer_behavior_df,
            database=DATABASE_NAME,
            table_name="gold_customer_behavior",
            transformation_ctx="customer_behavior_write"
        )
        
        product_performance_df = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [f"{gold_base_path}product_performance/"]
            },
            format="parquet"
        )
        
        glueContext.write_dynamic_frame.from_catalog(
            frame=product_performance_df,
            database=DATABASE_NAME,
            table_name="gold_product_performance",
            transformation_ctx="product_performance_write"
        )
        
        hourly_patterns_df = glueContext.create_dynamic_frame.from_options(
            connection_type="s3",
            connection_options={
                "paths": [f"{gold_base_path}hourly_patterns/"]
            },
            format="parquet"
        )
        
        glueContext.write_dynamic_frame.from_catalog(
            frame=hourly_patterns_df,
            database=DATABASE_NAME,
            table_name="gold_hourly_patterns",
            transformation_ctx="hourly_patterns_write"
        )
        
        print("Successfully updated Data Catalog with all processed tables")
        
    except Exception as e:
        print(f"Warning: Could not update Data Catalog: {str(e)}")
        print("Tables were written to S3 but may need manual catalog update")
    
    # =====================================================
    # Job Completion and Metrics
    # =====================================================
    
    print("ETL job completed successfully!")
    
    # Print processing summary
    print("\n" + "="*50)
    print("PROCESSING SUMMARY")
    print("="*50)
    print(f"Database: {DATABASE_NAME}")
    print(f"S3 Bucket: {S3_BUCKET_NAME}")
    print(f"Source tables processed: {len(table_names)}")
    print(f"Bronze layer rows: {bronze_row_count}")
    print(f"Silver layer rows: {silver_row_count}")
    print(f"Gold layer tables created: 4")
    print("="*50)
    
except Exception as e:
    print(f"ERROR: ETL job failed with error: {str(e)}")
    import traceback
    traceback.print_exc()
    raise e

finally:
    # Commit the job
    job.commit()