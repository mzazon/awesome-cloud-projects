"""
Aurora DSQL Database Initialization Lambda Function
Initializes the database schema and optionally creates sample data
"""

import json
import os
import boto3
import logging
from typing import Dict, Any

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Environment variables
DSQL_ENDPOINT = os.environ.get('DSQL_ENDPOINT')
DATABASE_NAME = os.environ.get('DATABASE_NAME', '${database_name}')
CREATE_SAMPLE_DATA = os.environ.get('CREATE_SAMPLE_DATA', '${create_sample_data}').lower() == 'true'


def get_dsql_client():
    """Create Aurora DSQL client with IAM authentication"""
    try:
        return boto3.client('dsql')
    except Exception as e:
        logger.error(f"Failed to create DSQL client: {str(e)}")
        raise


def execute_sql(client, sql: str, description: str = "SQL operation"):
    """Execute SQL statement with error handling and logging"""
    try:
        logger.info(f"Executing {description}...")
        logger.debug(f"SQL: {sql}")
        
        response = client.execute_statement(
            Database=DATABASE_NAME,
            Sql=sql
        )
        
        logger.info(f"{description} completed successfully")
        return response
        
    except Exception as e:
        logger.error(f"{description} failed: {str(e)}")
        raise


def create_database_schema(client):
    """Create the database schema with tables and indexes"""
    
    # Create users table
    create_users_table_sql = """
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            name VARCHAR(100) NOT NULL,
            email VARCHAR(255) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """
    
    execute_sql(client, create_users_table_sql, "Create users table")
    
    # Create indexes for efficient querying
    create_email_index_sql = """
        CREATE INDEX IF NOT EXISTS idx_users_email ON users(email)
    """
    
    execute_sql(client, create_email_index_sql, "Create email index")
    
    create_created_at_index_sql = """
        CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at)
    """
    
    execute_sql(client, create_created_at_index_sql, "Create created_at index")
    
    # Create updated_at trigger function
    create_trigger_function_sql = """
        CREATE OR REPLACE FUNCTION update_updated_at_column()
        RETURNS TRIGGER AS $$
        BEGIN
            NEW.updated_at = CURRENT_TIMESTAMP;
            RETURN NEW;
        END;
        $$ language 'plpgsql'
    """
    
    execute_sql(client, create_trigger_function_sql, "Create trigger function")
    
    # Create trigger for automatic updated_at
    create_trigger_sql = """
        DROP TRIGGER IF EXISTS update_users_updated_at ON users;
        CREATE TRIGGER update_users_updated_at
            BEFORE UPDATE ON users
            FOR EACH ROW
            EXECUTE FUNCTION update_updated_at_column()
    """
    
    execute_sql(client, create_trigger_sql, "Create updated_at trigger")
    
    logger.info("Database schema creation completed successfully")


def create_sample_data(client):
    """Create sample data for testing purposes"""
    
    if not CREATE_SAMPLE_DATA:
        logger.info("Sample data creation skipped (CREATE_SAMPLE_DATA=false)")
        return
    
    # Sample users data
    sample_users = [
        ('John Doe', 'john.doe@example.com'),
        ('Jane Smith', 'jane.smith@example.com'),
        ('Bob Johnson', 'bob.johnson@example.com'),
        ('Alice Brown', 'alice.brown@example.com'),
        ('Charlie Wilson', 'charlie.wilson@example.com')
    ]
    
    # Insert sample users with conflict handling
    for name, email in sample_users:
        insert_user_sql = """
            INSERT INTO users (name, email) 
            VALUES ($1, $2) 
            ON CONFLICT (email) DO NOTHING
        """
        
        try:
            client.execute_statement(
                Database=DATABASE_NAME,
                Sql=insert_user_sql,
                Parameters=[
                    {'stringValue': name},
                    {'stringValue': email}
                ]
            )
            logger.info(f"Sample user created: {name} ({email})")
        except Exception as e:
            logger.warning(f"Failed to create sample user {name}: {str(e)}")
    
    logger.info("Sample data creation completed")


def verify_schema(client):
    """Verify that the schema was created correctly"""
    
    # Check if users table exists and has expected structure
    verify_table_sql = """
        SELECT column_name, data_type, is_nullable
        FROM information_schema.columns
        WHERE table_name = 'users'
        ORDER BY ordinal_position
    """
    
    try:
        response = execute_sql(client, verify_table_sql, "Verify users table structure")
        
        if 'Records' in response and response['Records']:
            logger.info("Users table structure verified:")
            for record in response['Records']:
                column_name = record[0].get('stringValue', 'N/A')
                data_type = record[1].get('stringValue', 'N/A')
                is_nullable = record[2].get('stringValue', 'N/A')
                logger.info(f"  - {column_name}: {data_type} (nullable: {is_nullable})")
        else:
            raise Exception("Users table not found or has no columns")
        
        # Check indexes
        verify_indexes_sql = """
            SELECT indexname, indexdef
            FROM pg_indexes
            WHERE tablename = 'users'
        """
        
        response = execute_sql(client, verify_indexes_sql, "Verify indexes")
        
        if 'Records' in response and response['Records']:
            logger.info("Indexes verified:")
            for record in response['Records']:
                index_name = record[0].get('stringValue', 'N/A')
                logger.info(f"  - {index_name}")
        
        # Count records
        count_records_sql = "SELECT COUNT(*) FROM users"
        response = execute_sql(client, count_records_sql, "Count users")
        
        if 'Records' in response and response['Records']:
            count = response['Records'][0][0].get('longValue', 0)
            logger.info(f"Total users in database: {count}")
        
        logger.info("Schema verification completed successfully")
        
    except Exception as e:
        logger.error(f"Schema verification failed: {str(e)}")
        raise


def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    Main Lambda handler for database initialization
    
    Args:
        event: Lambda event (not used)
        context: Lambda context
        
    Returns:
        Success/failure response
    """
    try:
        logger.info("Starting Aurora DSQL database initialization")
        logger.info(f"Database endpoint: {DSQL_ENDPOINT}")
        logger.info(f"Database name: {DATABASE_NAME}")
        logger.info(f"Create sample data: {CREATE_SAMPLE_DATA}")
        
        # Initialize DSQL client
        client = get_dsql_client()
        
        # Create database schema
        create_database_schema(client)
        
        # Create sample data if requested
        create_sample_data(client)
        
        # Verify schema creation
        verify_schema(client)
        
        result = {
            'statusCode': 200,
            'body': {
                'message': 'Database initialization completed successfully',
                'database_name': DATABASE_NAME,
                'sample_data_created': CREATE_SAMPLE_DATA,
                'timestamp': context.aws_request_id
            }
        }
        
        logger.info("Database initialization completed successfully")
        return result
        
    except Exception as e:
        error_msg = f"Database initialization failed: {str(e)}"
        logger.error(error_msg)
        
        return {
            'statusCode': 500,
            'body': {
                'error': error_msg,
                'database_name': DATABASE_NAME,
                'timestamp': context.aws_request_id
            }
        }