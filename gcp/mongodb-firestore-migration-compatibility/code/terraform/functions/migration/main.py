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