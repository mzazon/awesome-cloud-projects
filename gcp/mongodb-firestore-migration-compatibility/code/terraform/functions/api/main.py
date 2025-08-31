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