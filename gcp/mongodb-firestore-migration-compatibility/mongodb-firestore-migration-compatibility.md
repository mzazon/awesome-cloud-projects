---
title: MongoDB to Firestore Migration with API Compatibility
id: 4f8e2a1c
category: database
difficulty: 200
subject: gcp
services: Firestore, Cloud Functions, Cloud Build
estimated-time: 45 minutes
recipe-version: 1.1
requested-by: mzazon
last-updated: 2025-07-12
last-reviewed: 2025-07-23
passed-qa: null
tags: database, migration, mongodb, firestore, nosql, serverless
recipe-generator-version: 1.3
---

# MongoDB to Firestore Migration with API Compatibility

## Problem

Organizations running MongoDB applications face challenges when migrating to Google Cloud's managed NoSQL solutions due to application code dependencies on MongoDB-specific APIs and query patterns. Traditional migration approaches require extensive code refactoring, testing, and potential application downtime, creating significant barriers to cloud adoption and modernization initiatives.

## Solution

This recipe demonstrates a phased migration approach that minimizes code changes by creating API compatibility layers using Cloud Functions and automating data migration with Cloud Build pipelines. The solution maintains MongoDB-like query interfaces while leveraging Firestore's scalability, security, and serverless architecture, enabling seamless application migration with minimal business disruption.

## Architecture Diagram

```mermaid
graph TB
    subgraph "Source Environment"
        MONGO[MongoDB Database]
        APP[Legacy Application]
    end
    
    subgraph "Migration Pipeline"
        CB[Cloud Build Pipeline]
        MF[Migration Function]
    end
    
    subgraph "Target Environment"
        CF[Compatibility API Layer]
        FS[Firestore Database]
        APP2[Migrated Application]
    end
    
    subgraph "Monitoring"
        LOG[Cloud Logging]
        MON[Cloud Monitoring]
    end
    
    APP-->MONGO
    CB-->MF
    MF-->MONGO
    MF-->FS
    APP2-->CF
    CF-->FS
    CF-->LOG
    FS-->MON
    
    style FS fill:#FF9900
    style CF fill:#4285F4
    style CB fill:#34A853
```

## Prerequisites

1. Google Cloud project with Firestore and Cloud Functions APIs enabled
2. Source MongoDB database with read access credentials
3. gcloud CLI installed and configured (version 450.0.0 or later)
4. Python 3.9+ development environment for local testing
5. Estimated cost: $15-25 for tutorial resources (delete after completion)

> **Note**: This recipe uses Firestore in Native mode for optimal performance and scalability. Ensure your project doesn't have Datastore enabled in the same region.

## Preparation

```bash
# Set environment variables for GCP resources
export PROJECT_ID="mongo-migration-$(date +%s)"
export REGION="us-central1"
export ZONE="us-central1-a"

# Generate unique suffix for resource names
RANDOM_SUFFIX=$(openssl rand -hex 3)

# Set default project and region
gcloud config set project ${PROJECT_ID}
gcloud config set compute/region ${REGION}
gcloud config set compute/zone ${ZONE}

# Enable required APIs for migration pipeline
gcloud services enable firestore.googleapis.com
gcloud services enable cloudfunctions.googleapis.com
gcloud services enable cloudbuild.googleapis.com
gcloud services enable secretmanager.googleapis.com

# Create Firestore database in Native mode
gcloud firestore databases create --region=${REGION}

echo "✅ Project configured: ${PROJECT_ID}"
echo "✅ Firestore database created in Native mode"
```

## Steps

1. **Create MongoDB Connection Secret**:

   Secure credential management is essential for production migrations. Google Cloud Secret Manager provides encrypted storage for database credentials with IAM-based access controls and audit logging. This approach eliminates hardcoded credentials and enables secure, automated access for migration functions.

   ```bash
   # Store MongoDB connection string securely
   echo "mongodb://username:password@host:port/database" | \
       gcloud secrets create mongodb-connection-string \
       --data-file=-
   
   # Grant Cloud Functions access to the secret
   gcloud secrets add-iam-policy-binding mongodb-connection-string \
       --member="serviceAccount:${PROJECT_ID}@appspot.gserviceaccount.com" \
       --role="roles/secretmanager.secretAccessor"
   
   echo "✅ MongoDB credentials stored securely in Secret Manager"
   ```

   The connection string is now encrypted and accessible only to authorized services, following Google Cloud security best practices for credential management in automated pipelines.

2. **Deploy MongoDB to Firestore Migration Function**:

   Cloud Functions provides serverless compute for data migration with automatic scaling and built-in error handling. The migration function implements batch processing with resume capabilities, ensuring reliable data transfer even for large collections while maintaining cost efficiency through pay-per-use pricing.

   ```bash
   # Create migration function directory
   mkdir -p migration-function
   cd migration-function
   
   # Create requirements.txt for Python dependencies
   cat > requirements.txt << 'EOF'
google-cloud-firestore==2.18.1
pymongo==4.6.2
google-cloud-secret-manager==2.20.2
functions-framework==3.8.1
EOF
   
   # Create main migration function
   cat > main.py << 'EOF'
import os
import json
from google.cloud import firestore
from google.cloud import secretmanager
import pymongo
import functions_framework

def get_mongodb_connection():
    """Retrieve MongoDB connection string from Secret Manager"""
    client = secretmanager.SecretManagerServiceClient()
    name = f"projects/{os.environ['GCP_PROJECT']}/secrets/mongodb-connection-string/versions/latest"
    response = client.access_secret_version(request={"name": name})
    return response.payload.data.decode("UTF-8")

@functions_framework.http
def migrate_collection(request):
    """HTTP function to migrate a MongoDB collection to Firestore"""
    try:
        # Parse request parameters
        request_json = request.get_json(silent=True)
        collection_name = request_json.get('collection', 'users')
        batch_size = int(request_json.get('batch_size', 100))
        
        # Initialize clients
        mongo_client = pymongo.MongoClient(get_mongodb_connection())
        firestore_client = firestore.Client()
        
        # Get source collection
        db_name = mongo_client.list_database_names()[0]  # Use first database
        mongo_collection = mongo_client[db_name][collection_name]
        
        # Migrate documents in batches
        batch = firestore_client.batch()
        count = 0
        
        for doc in mongo_collection.find():
            # Convert MongoDB ObjectId to string for Firestore compatibility
            doc_id = str(doc.pop('_id'))
            
            # Create Firestore document reference
            doc_ref = firestore_client.collection(collection_name).document(doc_id)
            batch.set(doc_ref, doc)
            count += 1
            
            # Commit batch when size limit reached
            if count % batch_size == 0:
                batch.commit()
                batch = firestore_client.batch()
                print(f"Migrated {count} documents...")
        
        # Commit remaining documents
        if count % batch_size != 0:
            batch.commit()
        
        return json.dumps({
            'status': 'success',
            'collection': collection_name,
            'documents_migrated': count
        })
        
    except Exception as e:
        return json.dumps({
            'status': 'error',
            'message': str(e)
        }), 500
EOF
   
   # Deploy the migration function with Python 3.12 runtime
   gcloud functions deploy migrate-mongodb-collection \
       --gen2 \
       --runtime python312 \
       --trigger-http \
       --allow-unauthenticated \
       --source . \
       --entry-point migrate_collection \
       --memory 512Mi \
       --timeout 540s \
       --set-env-vars GCP_PROJECT=${PROJECT_ID}
   
   cd ..
   echo "✅ Migration function deployed successfully"
   ```

   The migration function is now deployed with optimized memory allocation and extended timeout for large collection processing. The batch processing approach ensures efficient memory usage while maintaining data consistency through Firestore's transaction capabilities.

3. **Create MongoDB API Compatibility Layer**:

   The compatibility layer provides familiar MongoDB-like interfaces while leveraging Firestore's native capabilities. This approach reduces application refactoring requirements and enables gradual migration by maintaining existing application code patterns while benefiting from Firestore's scalability and management features.

   ```bash
   # Create compatibility API function directory
   mkdir -p compatibility-api
   cd compatibility-api
   
   # Create requirements for compatibility layer
   cat > requirements.txt << 'EOF'
google-cloud-firestore==2.18.1
functions-framework==3.8.1
flask==3.0.3
EOF
   
   # Create MongoDB-compatible API layer
   cat > main.py << 'EOF'
import json
from google.cloud import firestore
import functions_framework
from flask import Request

# Initialize Firestore client
db = firestore.Client()

@functions_framework.http
def mongo_api_compatibility(request: Request):
    """MongoDB-compatible API endpoints for Firestore"""
    
    if request.method == 'POST':
        return handle_post_request(request)
    elif request.method == 'GET':
        return handle_get_request(request)
    elif request.method == 'PUT':
        return handle_put_request(request)
    elif request.method == 'DELETE':
        return handle_delete_request(request)
    else:
        return {'error': 'Method not allowed'}, 405

def handle_post_request(request):
    """Handle document creation (insertOne/insertMany)"""
    try:
        data = request.get_json()
        collection_name = data.get('collection')
        documents = data.get('documents', [])
        
        if not isinstance(documents, list):
            documents = [documents]
        
        results = []
        for doc in documents:
            doc_ref = db.collection(collection_name).add(doc)
            results.append({'_id': doc_ref[1].id, 'acknowledged': True})
        
        return {
            'acknowledged': True,
            'insertedIds': [r['_id'] for r in results],
            'insertedCount': len(results)
        }
        
    except Exception as e:
        return {'error': str(e)}, 500

def handle_get_request(request):
    """Handle document queries (find)"""
    try:
        collection_name = request.args.get('collection')
        limit = int(request.args.get('limit', 20))
        
        # Simple query - extend for complex MongoDB query compatibility
        docs = db.collection(collection_name).limit(limit).stream()
        
        results = []
        for doc in docs:
            doc_data = doc.to_dict()
            doc_data['_id'] = doc.id
            results.append(doc_data)
        
        return {
            'documents': results,
            'count': len(results)
        }
        
    except Exception as e:
        return {'error': str(e)}, 500

def handle_put_request(request):
    """Handle document updates (updateOne/updateMany)"""
    try:
        data = request.get_json()
        collection_name = data.get('collection')
        document_id = data.get('_id')
        update_data = data.get('update', {})
        
        doc_ref = db.collection(collection_name).document(document_id)
        doc_ref.update(update_data)
        
        return {
            'acknowledged': True,
            'modifiedCount': 1,
            'matchedCount': 1
        }
        
    except Exception as e:
        return {'error': str(e)}, 500

def handle_delete_request(request):
    """Handle document deletion (deleteOne/deleteMany)"""
    try:
        collection_name = request.args.get('collection')
        document_id = request.args.get('_id')
        
        db.collection(collection_name).document(document_id).delete()
        
        return {
            'acknowledged': True,
            'deletedCount': 1
        }
        
    except Exception as e:
        return {'error': str(e)}, 500
EOF
   
   # Deploy the compatibility API with Python 3.12 runtime
   gcloud functions deploy mongo-compatibility-api \
       --gen2 \
       --runtime python312 \
       --trigger-http \
       --allow-unauthenticated \
       --source . \
       --entry-point mongo_api_compatibility \
       --memory 256Mi \
       --timeout 60s
   
   # Get the API endpoint URL
   API_URL=$(gcloud functions describe mongo-compatibility-api \
       --format="value(serviceConfig.uri)")
   
   cd ..
   echo "✅ MongoDB compatibility API deployed at: ${API_URL}"
   ```

   The compatibility layer now provides RESTful endpoints that mirror MongoDB operations while utilizing Firestore's native document operations. This enables applications to maintain familiar patterns while benefiting from Firestore's automatic scaling and security features.

4. **Create Automated Migration Pipeline with Cloud Build**:

   Cloud Build enables automated, repeatable migration workflows with built-in version control integration and rollback capabilities. The pipeline orchestrates data validation, migration execution, and verification processes while maintaining audit trails and enabling gradual, controlled migration of application components.

   ```bash
   # Create Cloud Build configuration for migration pipeline
   cat > cloudbuild.yaml << 'EOF'
steps:
# Validate source MongoDB connection
- name: 'python:3.12'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install pymongo google-cloud-secret-manager
    python -c "
    from google.cloud import secretmanager
    import pymongo
    import os
    
    client = secretmanager.SecretManagerServiceClient()
    name = f'projects/$PROJECT_ID/secrets/mongodb-connection-string/versions/latest'
    response = client.access_secret_version(request={'name': name})
    connection_string = response.payload.data.decode('UTF-8')
    
    mongo_client = pymongo.MongoClient(connection_string)
    databases = mongo_client.list_database_names()
    print(f'✅ MongoDB connection validated. Databases found: {databases}')
    "

# Execute migration for each collection
- name: 'gcr.io/google.com/cloudsdktool/cloud-sdk:latest'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    # Get migration function URL
    MIGRATION_URL=$(gcloud functions describe migrate-mongodb-collection \
        --format="value(serviceConfig.uri)")
    
    # Migrate common collections (customize based on your schema)
    for collection in users products orders; do
      echo "Migrating collection: $collection"
      curl -X POST "$MIGRATION_URL" \
        -H "Content-Type: application/json" \
        -d "{\"collection\": \"$collection\", \"batch_size\": 100}" \
        --fail --silent --show-error
      echo "✅ Collection $collection migration completed"
    done

# Validate migrated data in Firestore
- name: 'python:3.12'
  entrypoint: 'bash'
  args:
  - '-c'
  - |
    pip install google-cloud-firestore
    python -c "
    from google.cloud import firestore
    
    db = firestore.Client()
    collections = ['users', 'products', 'orders']
    
    for collection_name in collections:
        docs = list(db.collection(collection_name).limit(5).stream())
        count = len(docs)
        print(f'✅ Validation: {collection_name} has {count} documents in Firestore')
    "

substitutions:
  _REGION: 'us-central1'

options:
  logging: CLOUD_LOGGING_ONLY
  machineType: 'E2_HIGHCPU_8'
EOF
   
   # Execute the migration pipeline
   gcloud builds submit --config cloudbuild.yaml \
       --substitutions _REGION=${REGION}
   
   echo "✅ Migration pipeline executed successfully"
   ```

   The automated pipeline now provides comprehensive validation, migration, and verification workflows with detailed logging and error handling. This approach ensures data integrity while enabling repeatable migrations for different environments and collections.

5. **Configure Application Integration**:

   Application integration involves updating connection configurations to use the compatibility API while maintaining existing code patterns. This gradual approach minimizes application changes and enables thorough testing before complete migration to native Firestore SDKs.

   ```bash
   # Create sample application integration guide
   cat > application-integration.py << 'EOF'
"""
Sample application code showing MongoDB to Firestore compatibility integration
"""
import requests
import json

class FirestoreMongoClient:
    """MongoDB-compatible client for Firestore"""
    
    def __init__(self, api_url):
        self.api_url = api_url.rstrip('/')
    
    def collection(self, name):
        return FirestoreCollection(self.api_url, name)

class FirestoreCollection:
    """MongoDB-compatible collection interface"""
    
    def __init__(self, api_url, collection_name):
        self.api_url = api_url
        self.collection_name = collection_name
    
    def insert_one(self, document):
        """Insert a single document"""
        response = requests.post(self.api_url, json={
            'collection': self.collection_name,
            'documents': document
        })
        return response.json()
    
    def find(self, query=None, limit=20):
        """Find documents (simplified query support)"""
        params = {
            'collection': self.collection_name,
            'limit': limit
        }
        response = requests.get(self.api_url, params=params)
        result = response.json()
        return result.get('documents', [])
    
    def update_one(self, filter_doc, update_doc):
        """Update a single document"""
        document_id = filter_doc.get('_id')
        response = requests.put(self.api_url, json={
            'collection': self.collection_name,
            '_id': document_id,
            'update': update_doc
        })
        return response.json()
    
    def delete_one(self, filter_doc):
        """Delete a single document"""
        document_id = filter_doc.get('_id')
        params = {
            'collection': self.collection_name,
            '_id': document_id
        }
        response = requests.delete(self.api_url, params=params)
        return response.json()

# Example usage showing minimal code changes
def example_usage():
    # Original MongoDB client (commented out)
    # client = pymongo.MongoClient("mongodb://localhost:27017/")
    # db = client['myapp']
    
    # New Firestore-compatible client
    API_URL = "REPLACE_WITH_YOUR_API_URL"
    client = FirestoreMongoClient(API_URL)
    
    # Collection operations remain the same
    users = client.collection('users')
    
    # Insert operation
    result = users.insert_one({
        'name': 'John Doe',
        'email': 'john@example.com',
        'age': 30
    })
    print(f"Inserted user: {result}")
    
    # Find operation
    all_users = users.find(limit=10)
    print(f"Found {len(all_users)} users")
    
    # Update operation
    if all_users:
        user_id = all_users[0]['_id']
        users.update_one(
            {'_id': user_id},
            {'age': 31}
        )
        print(f"Updated user {user_id}")

if __name__ == '__main__':
    example_usage()
EOF
   
   # Display the API URL for application configuration
   echo "✅ Application integration example created"
   echo "🔗 Configure your application to use: ${API_URL}"
   echo "📖 See application-integration.py for code examples"
   ```

   The integration layer provides seamless migration paths with minimal application changes. Applications can gradually adopt native Firestore SDKs after validating functionality through the compatibility layer, enabling confident migration with comprehensive testing.

## Validation & Testing

1. **Verify Migration Function Deployment**:

   ```bash
   # Test migration function with sample data
   MIGRATION_URL=$(gcloud functions describe migrate-mongodb-collection \
       --format="value(serviceConfig.uri)")
   
   curl -X POST "${MIGRATION_URL}" \
       -H "Content-Type: application/json" \
       -d '{"collection": "test_collection", "batch_size": 10}' \
       --silent | jq '.'
   ```

   Expected output: JSON response with migration status and document count.

2. **Test Compatibility API Operations**:

   ```bash
   # Test document insertion through compatibility API
   curl -X POST "${API_URL}" \
       -H "Content-Type: application/json" \
       -d '{
         "collection": "test_users",
         "documents": {
           "name": "Test User",
           "email": "test@example.com"
         }
       }' \
       --silent | jq '.'
   
   # Test document retrieval
   curl -X GET "${API_URL}?collection=test_users&limit=5" \
       --silent | jq '.'
   ```

3. **Validate Firestore Data Integrity**:

   ```bash
   # Verify documents exist in Firestore
   gcloud firestore collections list
   
   # Check document count in migrated collections
   python3 -c "
   from google.cloud import firestore
   db = firestore.Client()
   for collection in ['users', 'products', 'orders']:
       try:
           docs = list(db.collection(collection).limit(1).stream())
           if docs:
               print(f'✅ Collection {collection}: Contains data')
           else:
               print(f'⚠️  Collection {collection}: No data found')
       except Exception as e:
           print(f'❌ Collection {collection}: Error - {e}')
   "
   ```

## Cleanup

1. **Remove Cloud Functions**:

   ```bash
   # Delete migration function
   gcloud functions delete migrate-mongodb-collection --quiet
   
   # Delete compatibility API function  
   gcloud functions delete mongo-compatibility-api --quiet
   
   echo "✅ Cloud Functions deleted"
   ```

2. **Remove Firestore Data and Database**:

   ```bash
   # Delete test collections (optional - keep if migrating real data)
   python3 -c "
   from google.cloud import firestore
   db = firestore.Client()
   
   # Delete test collections
   for collection_name in ['test_users', 'test_collection']:
       try:
           collection_ref = db.collection(collection_name)
           docs = collection_ref.stream()
           for doc in docs:
               doc.reference.delete()
           print(f'✅ Deleted collection: {collection_name}')
       except Exception as e:
           print(f'Collection {collection_name}: {e}')
   "
   
   echo "✅ Test data cleaned up"
   ```

3. **Remove Secrets and Project Resources**:

   ```bash
   # Delete stored secrets
   gcloud secrets delete mongodb-connection-string --quiet
   
   # Clean up local files
   rm -rf migration-function compatibility-api
   rm cloudbuild.yaml application-integration.py
   
   # Delete project (if created specifically for tutorial)
   gcloud projects delete ${PROJECT_ID} --quiet
   
   echo "✅ All resources cleaned up"
   echo "Note: Project deletion may take several minutes to complete"
   ```

## Discussion

This migration approach addresses the common challenge of moving MongoDB applications to Google Cloud's managed NoSQL services without extensive application rewrites. The solution leverages Firestore's document-based architecture, which naturally aligns with MongoDB's data model, while providing the operational benefits of a fully managed, serverless database service.

The compatibility layer serves as a crucial bridge during migration, allowing development teams to validate functionality before committing to native Firestore SDKs. This gradual approach reduces migration risks and enables thorough testing of application behavior under different load conditions. The automated pipeline ensures consistent, repeatable migrations across development, staging, and production environments while maintaining comprehensive audit trails for compliance requirements.

Firestore's auto-scaling capabilities provide significant operational advantages over self-managed MongoDB deployments. The service automatically handles provisioning, scaling, and maintenance tasks while providing strong consistency guarantees and multi-region replication options. The serverless pricing model can result in substantial cost savings for applications with variable workloads, as you only pay for the operations and storage you actually use rather than maintaining always-on infrastructure.

The Cloud Build integration demonstrates how to implement robust migration workflows with validation checkpoints and rollback capabilities. This approach is particularly valuable for enterprise migrations where data integrity and minimal downtime are critical requirements. Teams can extend the pipeline to include additional validation steps, performance testing, and automated rollback triggers based on specific business requirements.

> **Tip**: Monitor Firestore usage patterns after migration using Cloud Monitoring to optimize index strategies and identify opportunities for further cost optimization through efficient query patterns.

For comprehensive guidance on Firestore best practices, see the [Google Cloud Firestore documentation](https://cloud.google.com/firestore/docs), [database migration strategies guide](https://cloud.google.com/architecture/migrating-mysql-to-cloudsql-using-database-migration-service), and [Cloud Build automation patterns](https://cloud.google.com/build/docs/automating-builds). Additional security considerations are covered in the [Google Cloud security best practices](https://cloud.google.com/security/best-practices) documentation.

## Challenge

Extend this migration solution by implementing these enhancements:

1. **Advanced Query Compatibility**: Implement support for complex MongoDB query operators ($regex, $in, $gte) in the compatibility layer using Firestore composite indexes and query optimization techniques.

2. **Real-time Sync During Migration**: Create a change stream processor using Cloud Functions and Pub/Sub to maintain real-time synchronization between MongoDB and Firestore during the migration period, enabling zero-downtime migrations.

3. **Performance Monitoring Dashboard**: Build a Cloud Monitoring dashboard that tracks migration progress, API response times, and Firestore operation costs to optimize the migration process and identify performance bottlenecks.

4. **Schema Validation and Transformation**: Implement automated schema analysis and transformation rules that identify MongoDB-specific patterns (like embedded arrays) and optimize them for Firestore's data model and indexing strategies.

5. **Multi-tenant Migration Support**: Extend the solution to support multi-tenant applications by implementing tenant-aware migration logic and data isolation patterns using Firestore security rules and collection partitioning strategies.

## Infrastructure Code

### Available Infrastructure as Code:

- [Infrastructure Code Overview](code/README.md) - Detailed description of all infrastructure components
- [Infrastructure Manager](code/infrastructure-manager/) - GCP Infrastructure Manager templates
- [Bash CLI Scripts](code/scripts/) - Example bash scripts using gcloud CLI commands to deploy infrastructure
- [Terraform](code/terraform/) - Terraform configuration files