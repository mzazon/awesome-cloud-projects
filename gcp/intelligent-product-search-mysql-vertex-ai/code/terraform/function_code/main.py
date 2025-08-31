import json
import os
import logging
import numpy as np
from google.cloud import aiplatform
from google.cloud.sql.connector import Connector
import pymysql
import functions_framework
import vertexai
from vertexai.language_models import TextEmbeddingModel

# Configure logging
logging.basicConfig(level=getattr(logging, os.environ.get('LOG_LEVEL', 'INFO')))
logger = logging.getLogger(__name__)

# Initialize Vertex AI
PROJECT_ID = os.environ.get('PROJECT_ID')
REGION = os.environ.get('REGION')
INSTANCE_NAME = os.environ.get('INSTANCE_NAME')
DB_PASSWORD = os.environ.get('DB_PASSWORD')

# Initialize Vertex AI with project and location
vertexai.init(project=PROJECT_ID, location=REGION)

def get_embedding(text):
    """Generate embedding using Vertex AI text-embedding-005 model."""
    try:
        model = TextEmbeddingModel.from_pretrained("text-embedding-005")
        embeddings = model.get_embeddings([text])
        return embeddings[0].values
    except Exception as e:
        logger.error(f"Error generating embedding: {str(e)}")
        raise

def get_db_connection():
    """Create database connection using Cloud SQL Connector."""
    try:
        connector = Connector()
        
        def getconn():
            conn = connector.connect(
                f"{PROJECT_ID}:{REGION}:{INSTANCE_NAME}",
                "pymysql",
                user="root",
                password=DB_PASSWORD,
                db="products"
            )
            return conn
        
        return getconn()
    except Exception as e:
        logger.error(f"Error connecting to database: {str(e)}")
        raise

def calculate_cosine_similarity(vec1, vec2):
    """Calculate cosine similarity between two vectors."""
    try:
        vec1_array = np.array(vec1)
        vec2_array = np.array(vec2)
        
        dot_product = np.dot(vec1_array, vec2_array)
        norm1 = np.linalg.norm(vec1_array)
        norm2 = np.linalg.norm(vec2_array)
        
        if norm1 == 0 or norm2 == 0:
            return 0.0
            
        return dot_product / (norm1 * norm2)
    except Exception as e:
        logger.error(f"Error calculating cosine similarity: {str(e)}")
        return 0.0

@functions_framework.http
def search_products(request):
    """Handle product search requests with semantic similarity."""
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Content-Type': 'application/json'
    }
    
    try:
        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON in request body'}), 400, headers)
        
        query = request_json.get('query', '').strip()
        limit = request_json.get('limit', 10)
        min_similarity = request_json.get('min_similarity', 0.0)
        
        # Validate inputs
        if not query:
            return (json.dumps({'error': 'Query parameter is required'}), 400, headers)
        
        if not isinstance(limit, int) or limit <= 0 or limit > 100:
            limit = 10
        
        if not isinstance(min_similarity, (int, float)) or min_similarity < 0 or min_similarity > 1:
            min_similarity = 0.0
        
        logger.info(f"Processing search query: '{query}' with limit: {limit}")
        
        # Generate embedding for search query
        query_embedding = get_embedding(query)
        logger.info(f"Generated embedding with {len(query_embedding)} dimensions")
        
        # Connect to database
        conn = get_db_connection()
        cursor = conn.cursor(pymysql.cursors.DictCursor)
        
        try:
            # Store search query for analytics
            cursor.execute(
                "INSERT INTO search_queries (query_text, query_embedding) VALUES (%s, %s)",
                (query, json.dumps(query_embedding))
            )
            query_id = cursor.lastrowid
            
            # Get all products with embeddings for similarity calculation
            cursor.execute("""
                SELECT id, name, description, category, price, image_url, embedding
                FROM product_catalog 
                WHERE embedding IS NOT NULL
                ORDER BY created_at DESC
            """)
            
            products = cursor.fetchall()
            logger.info(f"Found {len(products)} products with embeddings")
            
            if not products:
                # Update results count
                cursor.execute(
                    "UPDATE search_queries SET results_count = 0 WHERE id = %s",
                    (query_id,)
                )
                conn.commit()
                
                return (json.dumps({
                    'results': [],
                    'total_products': 0,
                    'query': query,
                    'message': 'No products found with embeddings'
                }), 200, headers)
            
            results = []
            
            # Calculate similarity for each product
            for product in products:
                try:
                    product_embedding = json.loads(product['embedding'])
                    
                    # Calculate cosine similarity
                    similarity = calculate_cosine_similarity(query_embedding, product_embedding)
                    
                    # Only include results above minimum similarity threshold
                    if similarity >= min_similarity:
                        results.append({
                            'id': product['id'],
                            'name': product['name'],
                            'description': product['description'],
                            'category': product['category'],
                            'price': float(product['price']) if product['price'] else None,
                            'image_url': product['image_url'],
                            'similarity': float(similarity)
                        })
                
                except (json.JSONDecodeError, TypeError, KeyError) as e:
                    logger.warning(f"Skipping product {product.get('id', 'unknown')} due to invalid embedding: {str(e)}")
                    continue
            
            # Sort by similarity (highest first) and limit results
            results.sort(key=lambda x: x['similarity'], reverse=True)
            total_matches = len(results)
            results = results[:limit]
            
            # Update results count in database
            cursor.execute(
                "UPDATE search_queries SET results_count = %s WHERE id = %s",
                (total_matches, query_id)
            )
            conn.commit()
            
            logger.info(f"Returning {len(results)} results out of {total_matches} matches")
            
            response_data = {
                'results': results,
                'total_matches': total_matches,
                'returned_count': len(results),
                'query': query,
                'min_similarity': min_similarity,
                'max_similarity': max(r['similarity'] for r in results) if results else 0.0,
                'avg_similarity': sum(r['similarity'] for r in results) / len(results) if results else 0.0
            }
            
            return (json.dumps(response_data), 200, headers)
            
        finally:
            cursor.close()
            conn.close()
        
    except Exception as e:
        logger.error(f"Error in search_products: {str(e)}")
        error_response = {
            'error': 'Internal server error occurred during search',
            'message': str(e) if os.environ.get('LOG_LEVEL') == 'DEBUG' else 'Please try again later'
        }
        return (json.dumps(error_response), 500, headers)

@functions_framework.http
def add_product(request):
    """Add new product with automatic embedding generation."""
    # Handle CORS preflight requests
    if request.method == 'OPTIONS':
        headers = {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'POST, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
            'Access-Control-Max-Age': '3600'
        }
        return ('', 204, headers)
    
    # CORS headers for actual requests
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        'Content-Type': 'application/json'
    }
    
    try:
        # Parse request JSON
        request_json = request.get_json(silent=True)
        if not request_json:
            return (json.dumps({'error': 'Invalid JSON in request body'}), 400, headers)
        
        # Extract and validate product data
        name = request_json.get('name', '').strip()
        description = request_json.get('description', '').strip()
        category = request_json.get('category', '').strip()
        price = request_json.get('price')
        image_url = request_json.get('image_url', '').strip()
        
        # Validate required fields
        if not name:
            return (json.dumps({'error': 'Product name is required'}), 400, headers)
        
        if not description:
            return (json.dumps({'error': 'Product description is required'}), 400, headers)
        
        # Validate price if provided
        if price is not None:
            try:
                price = float(price)
                if price < 0:
                    return (json.dumps({'error': 'Price must be non-negative'}), 400, headers)
            except (ValueError, TypeError):
                return (json.dumps({'error': 'Price must be a valid number'}), 400, headers)
        
        # Validate name and description length
        if len(name) > 255:
            return (json.dumps({'error': 'Product name must be 255 characters or less'}), 400, headers)
        
        if len(description) > 5000:
            return (json.dumps({'error': 'Product description must be 5000 characters or less'}), 400, headers)
        
        logger.info(f"Adding new product: '{name}' in category: '{category}'")
        
        # Generate embedding for product description
        # Combine name and description for better embedding context
        embedding_text = f"{name}. {description}"
        embedding = get_embedding(embedding_text)
        logger.info(f"Generated embedding with {len(embedding)} dimensions for product")
        
        # Connect to database
        conn = get_db_connection()
        cursor = conn.cursor()
        
        try:
            # Insert product with embedding
            cursor.execute("""
                INSERT INTO product_catalog (name, description, category, price, image_url, embedding)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                name,
                description,
                category if category else None,
                price,
                image_url if image_url else None,
                json.dumps(embedding)
            ))
            
            product_id = cursor.lastrowid
            conn.commit()
            
            logger.info(f"Successfully added product with ID: {product_id}")
            
            response_data = {
                'id': product_id,
                'name': name,
                'description': description,
                'category': category,
                'price': price,
                'image_url': image_url,
                'status': 'success',
                'embedding_dimensions': len(embedding),
                'message': 'Product added successfully with semantic embedding'
            }
            
            return (json.dumps(response_data), 201, headers)
            
        finally:
            cursor.close()
            conn.close()
        
    except Exception as e:
        logger.error(f"Error in add_product: {str(e)}")
        error_response = {
            'error': 'Internal server error occurred while adding product',
            'message': str(e) if os.environ.get('LOG_LEVEL') == 'DEBUG' else 'Please try again later'
        }
        return (json.dumps(error_response), 500, headers)

@functions_framework.http
def health_check(request):
    """Health check endpoint for monitoring."""
    headers = {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json'
    }
    
    try:
        # Test database connection
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT 1")
        cursor.fetchone()
        cursor.close()
        conn.close()
        
        # Test Vertex AI (without making an API call to avoid costs)
        vertexai.init(project=PROJECT_ID, location=REGION)
        
        response_data = {
            'status': 'healthy',
            'timestamp': int(time.time()),
            'services': {
                'database': 'connected',
                'vertex_ai': 'initialized',
                'embedding_model': 'text-embedding-005'
            },
            'environment': {
                'project_id': PROJECT_ID,
                'region': REGION,
                'instance_name': INSTANCE_NAME
            }
        }
        
        return (json.dumps(response_data), 200, headers)
        
    except Exception as e:
        logger.error(f"Health check failed: {str(e)}")
        error_response = {
            'status': 'unhealthy',
            'error': str(e),
            'timestamp': int(time.time())
        }
        return (json.dumps(error_response), 503, headers)

# Import time for health check
import time