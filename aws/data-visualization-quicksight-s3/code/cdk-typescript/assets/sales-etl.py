import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F
from pyspark.sql.types import *

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_DATABASE', 'TARGET_BUCKET'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

try:
    # Read sales data
    sales_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['SOURCE_DATABASE'],
        table_name="sales_2024_q1_csv"
    ).toDF()
    
    # Read customer data
    customers_df = glueContext.create_dynamic_frame.from_catalog(
        database=args['SOURCE_DATABASE'],
        table_name="customers_csv"
    ).toDF()
    
    # Data transformations
    # Convert data types
    sales_df = sales_df.withColumn("quantity", F.col("quantity").cast(IntegerType())) \
                     .withColumn("unit_price", F.col("unit_price").cast(DoubleType())) \
                     .withColumn("order_date", F.to_date(F.col("order_date"), "yyyy-MM-dd"))
    
    # Calculate total amount
    sales_df = sales_df.withColumn("total_amount", F.col("quantity") * F.col("unit_price"))
    
    # Add derived columns
    sales_df = sales_df.withColumn("order_month", F.month(F.col("order_date"))) \
                     .withColumn("order_year", F.year(F.col("order_date"))) \
                     .withColumn("order_quarter", F.quarter(F.col("order_date")))
    
    # Join with customer data
    enriched_sales = sales_df.join(customers_df, "customer_id", "left")
    
    # Create aggregated views
    # Monthly sales summary
    monthly_sales = enriched_sales.groupBy("order_year", "order_month", "region") \
        .agg(
            F.sum("total_amount").alias("total_revenue"),
            F.count("order_id").alias("total_orders"),
            F.avg("total_amount").alias("avg_order_value"),
            F.countDistinct("customer_id").alias("unique_customers")
        )
    
    # Product category performance
    category_performance = enriched_sales.groupBy("product_category", "region") \
        .agg(
            F.sum("total_amount").alias("category_revenue"),
            F.sum("quantity").alias("total_quantity"),
            F.count("order_id").alias("total_orders")
        )
    
    # Customer tier analysis
    customer_analysis = enriched_sales.groupBy("customer_tier", "region") \
        .agg(
            F.sum("total_amount").alias("tier_revenue"),
            F.count("order_id").alias("tier_orders"),
            F.countDistinct("customer_id").alias("tier_customers")
        )
    
    # Write processed data to S3 in Parquet format
    target_bucket = args['TARGET_BUCKET']
    
    # Write enriched sales data
    enriched_sales.write.mode("overwrite").parquet(f"s3://{target_bucket}/enriched-sales/")
    
    # Write aggregated views
    monthly_sales.write.mode("overwrite").parquet(f"s3://{target_bucket}/monthly-sales/")
    category_performance.write.mode("overwrite").parquet(f"s3://{target_bucket}/category-performance/")
    customer_analysis.write.mode("overwrite").parquet(f"s3://{target_bucket}/customer-analysis/")
    
    print("ETL job completed successfully")
    
except Exception as e:
    print(f"ETL job failed: {str(e)}")
    raise e

job.commit()