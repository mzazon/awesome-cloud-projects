"""
AWS Glue ETL Job for Data Visualization Pipeline
Transforms raw sales data into optimized datasets for QuickSight visualization
"""

import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def main():
    # Parse command line arguments
    args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_DATABASE', 'TARGET_BUCKET'])
    
    # Initialize Glue context
    sc = SparkContext()
    glueContext = GlueContext(sc)
    spark = glueContext.spark_session
    job = Job(glueContext)
    job.init(args['JOB_NAME'], args)
    
    logger.info(f"Starting ETL job: {args['JOB_NAME']}")
    logger.info(f"Source database: {args['SOURCE_DATABASE']}")
    logger.info(f"Target bucket: {args['TARGET_BUCKET']}")
    
    try:
        # Read source data from Glue catalog
        sales_df = read_sales_data(glueContext, args['SOURCE_DATABASE'])
        customers_df = read_customer_data(glueContext, args['SOURCE_DATABASE'])
        
        if sales_df is None or customers_df is None:
            logger.error("Failed to read source data")
            return
        
        # Transform and enrich data
        enriched_sales = transform_sales_data(sales_df, customers_df)
        
        # Create aggregated views
        monthly_sales = create_monthly_aggregation(enriched_sales)
        category_performance = create_category_aggregation(enriched_sales)
        customer_analysis = create_customer_aggregation(enriched_sales)
        
        # Write processed data to S3
        write_to_s3(enriched_sales, args['TARGET_BUCKET'], "enriched-sales")
        write_to_s3(monthly_sales, args['TARGET_BUCKET'], "monthly-sales")
        write_to_s3(category_performance, args['TARGET_BUCKET'], "category-performance")
        write_to_s3(customer_analysis, args['TARGET_BUCKET'], "customer-analysis")
        
        logger.info("ETL job completed successfully")
        
    except Exception as e:
        logger.error(f"ETL job failed: {str(e)}")
        raise
    finally:
        job.commit()

def read_sales_data(glue_context, database_name):
    """Read sales data from Glue catalog"""
    try:
        # Try different possible table names for sales data
        table_names = ["sales_2024_q1_csv", "sales_csv", "sales"]
        
        for table_name in table_names:
            try:
                logger.info(f"Attempting to read table: {table_name}")
                sales_df = glue_context.create_dynamic_frame.from_catalog(
                    database=database_name,
                    table_name=table_name
                ).toDF()
                logger.info(f"Successfully read sales data from table: {table_name}")
                logger.info(f"Sales data schema: {sales_df.schema}")
                logger.info(f"Sales data count: {sales_df.count()}")
                return sales_df
            except Exception as e:
                logger.warning(f"Failed to read table {table_name}: {str(e)}")
                continue
        
        logger.error("No sales data table found")
        return None
        
    except Exception as e:
        logger.error(f"Error reading sales data: {str(e)}")
        return None

def read_customer_data(glue_context, database_name):
    """Read customer data from Glue catalog"""
    try:
        # Try different possible table names for customer data
        table_names = ["customers_csv", "customers"]
        
        for table_name in table_names:
            try:
                logger.info(f"Attempting to read table: {table_name}")
                customers_df = glue_context.create_dynamic_frame.from_catalog(
                    database=database_name,
                    table_name=table_name
                ).toDF()
                logger.info(f"Successfully read customer data from table: {table_name}")
                logger.info(f"Customer data schema: {customers_df.schema}")
                logger.info(f"Customer data count: {customers_df.count()}")
                return customers_df
            except Exception as e:
                logger.warning(f"Failed to read table {table_name}: {str(e)}")
                continue
        
        logger.error("No customer data table found")
        return None
        
    except Exception as e:
        logger.error(f"Error reading customer data: {str(e)}")
        return None

def transform_sales_data(sales_df, customers_df):
    """Transform and enrich sales data"""
    try:
        logger.info("Starting data transformation")
        
        # Data type conversions with error handling
        sales_df = sales_df.withColumn("quantity", 
                                     F.when(F.col("quantity").cast(IntegerType()).isNotNull(), 
                                           F.col("quantity").cast(IntegerType())).otherwise(1))
        
        sales_df = sales_df.withColumn("unit_price", 
                                     F.when(F.col("unit_price").cast(DoubleType()).isNotNull(), 
                                           F.col("unit_price").cast(DoubleType())).otherwise(0.0))
        
        # Date conversion with multiple format support
        sales_df = sales_df.withColumn("order_date", 
                                     F.coalesce(
                                         F.to_date(F.col("order_date"), "yyyy-MM-dd"),
                                         F.to_date(F.col("order_date"), "MM/dd/yyyy"),
                                         F.to_date(F.col("order_date"), "dd-MM-yyyy")
                                     ))
        
        # Calculate derived fields
        sales_df = sales_df.withColumn("total_amount", F.col("quantity") * F.col("unit_price"))
        
        # Add time-based dimensions
        sales_df = sales_df.withColumn("order_month", F.month(F.col("order_date"))) \
                         .withColumn("order_year", F.year(F.col("order_date"))) \
                         .withColumn("order_quarter", F.quarter(F.col("order_date"))) \
                         .withColumn("order_day_of_week", F.dayofweek(F.col("order_date"))) \
                         .withColumn("order_week_of_year", F.weekofyear(F.col("order_date")))
        
        # Add business metrics
        sales_df = sales_df.withColumn("is_weekend", 
                                     F.when(F.col("order_day_of_week").isin([1, 7]), True).otherwise(False))
        
        # Join with customer data (left join to preserve all sales records)
        enriched_sales = sales_df.join(customers_df, "customer_id", "left")
        
        # Fill null customer data with defaults
        enriched_sales = enriched_sales.fillna({
            "customer_name": "Unknown Customer",
            "customer_tier": "Unknown",
            "city": "Unknown",
            "state": "Unknown"
        })
        
        # Add data quality flags
        enriched_sales = enriched_sales.withColumn("data_quality_score",
                                                 F.when(F.col("customer_name") != "Unknown Customer", 100)
                                                 .when(F.col("customer_tier") != "Unknown", 80)
                                                 .otherwise(60))
        
        logger.info(f"Enriched sales data count: {enriched_sales.count()}")
        logger.info(f"Enriched sales schema: {enriched_sales.schema}")
        
        return enriched_sales
        
    except Exception as e:
        logger.error(f"Error in data transformation: {str(e)}")
        raise

def create_monthly_aggregation(enriched_sales):
    """Create monthly sales aggregation"""
    try:
        logger.info("Creating monthly aggregation")
        
        monthly_sales = enriched_sales.groupBy("order_year", "order_month", "region") \
            .agg(
                F.sum("total_amount").alias("total_revenue"),
                F.count("order_id").alias("total_orders"),
                F.avg("total_amount").alias("avg_order_value"),
                F.countDistinct("customer_id").alias("unique_customers"),
                F.sum("quantity").alias("total_quantity"),
                F.min("order_date").alias("first_order_date"),
                F.max("order_date").alias("last_order_date"),
                F.avg("data_quality_score").alias("avg_data_quality")
            )
        
        # Add derived metrics
        monthly_sales = monthly_sales.withColumn("revenue_per_customer", 
                                               F.col("total_revenue") / F.col("unique_customers"))
        
        monthly_sales = monthly_sales.withColumn("orders_per_customer", 
                                               F.col("total_orders") / F.col("unique_customers"))
        
        logger.info(f"Monthly aggregation count: {monthly_sales.count()}")
        return monthly_sales
        
    except Exception as e:
        logger.error(f"Error creating monthly aggregation: {str(e)}")
        raise

def create_category_aggregation(enriched_sales):
    """Create product category performance aggregation"""
    try:
        logger.info("Creating category performance aggregation")
        
        category_performance = enriched_sales.groupBy("product_category", "region") \
            .agg(
                F.sum("total_amount").alias("category_revenue"),
                F.sum("quantity").alias("total_quantity"),
                F.count("order_id").alias("total_orders"),
                F.countDistinct("customer_id").alias("unique_customers"),
                F.avg("unit_price").alias("avg_unit_price"),
                F.countDistinct("product_name").alias("unique_products")
            )
        
        # Add derived metrics
        category_performance = category_performance.withColumn("avg_order_value", 
                                                             F.col("category_revenue") / F.col("total_orders"))
        
        category_performance = category_performance.withColumn("revenue_per_customer", 
                                                             F.col("category_revenue") / F.col("unique_customers"))
        
        logger.info(f"Category performance count: {category_performance.count()}")
        return category_performance
        
    except Exception as e:
        logger.error(f"Error creating category aggregation: {str(e)}")
        raise

def create_customer_aggregation(enriched_sales):
    """Create customer tier analysis aggregation"""
    try:
        logger.info("Creating customer analysis aggregation")
        
        customer_analysis = enriched_sales.groupBy("customer_tier", "region") \
            .agg(
                F.sum("total_amount").alias("tier_revenue"),
                F.count("order_id").alias("tier_orders"),
                F.countDistinct("customer_id").alias("tier_customers"),
                F.avg("total_amount").alias("avg_order_value"),
                F.sum("quantity").alias("total_quantity"),
                F.countDistinct("product_category").alias("categories_purchased")
            )
        
        # Add derived metrics
        customer_analysis = customer_analysis.withColumn("revenue_per_customer", 
                                                       F.col("tier_revenue") / F.col("tier_customers"))
        
        customer_analysis = customer_analysis.withColumn("orders_per_customer", 
                                                       F.col("tier_orders") / F.col("tier_customers"))
        
        logger.info(f"Customer analysis count: {customer_analysis.count()}")
        return customer_analysis
        
    except Exception as e:
        logger.error(f"Error creating customer aggregation: {str(e)}")
        raise

def write_to_s3(dataframe, bucket, path):
    """Write DataFrame to S3 in Parquet format"""
    try:
        s3_path = f"s3://{bucket}/{path}/"
        logger.info(f"Writing data to: {s3_path}")
        
        # Write with partitioning for better query performance where applicable
        if "order_year" in dataframe.columns and "order_month" in dataframe.columns:
            dataframe.write.mode("overwrite") \
                .partitionBy("order_year", "order_month") \
                .parquet(s3_path)
        elif "region" in dataframe.columns:
            dataframe.write.mode("overwrite") \
                .partitionBy("region") \
                .parquet(s3_path)
        else:
            dataframe.write.mode("overwrite").parquet(s3_path)
        
        logger.info(f"Successfully wrote data to: {s3_path}")
        
    except Exception as e:
        logger.error(f"Error writing to S3 path {path}: {str(e)}")
        raise

if __name__ == "__main__":
    main()