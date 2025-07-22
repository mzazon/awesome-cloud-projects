"""
Query Optimization ML Model

This script trains a machine learning model to predict query optimization opportunities
based on historical query performance data and execution patterns.
"""

import pandas as pd
import numpy as np
from google.cloud import bigquery
from google.cloud import aiplatform
from google.cloud import storage
import joblib
import logging
import json
import re
from datetime import datetime
from sklearn.ensemble import RandomForestRegressor, GradientBoostingClassifier
from sklearn.preprocessing import StandardScaler, LabelEncoder
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error, classification_report, accuracy_score
import warnings
warnings.filterwarnings('ignore')

# Configuration
PROJECT_ID = "${project_id}"
DATASET_NAME = "${dataset_name}"
BUCKET_NAME = "${bucket_name}"
MODEL_NAME = "query-optimization-model"

class QueryFeatureExtractor:
    """
    Extract features from SQL query text for ML model training
    """
    
    def __init__(self):
        self.sql_keywords = [
            'SELECT', 'FROM', 'WHERE', 'GROUP BY', 'ORDER BY', 'HAVING',
            'JOIN', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'FULL JOIN',
            'UNION', 'DISTINCT', 'LIMIT', 'OFFSET', 'WITH', 'CASE'
        ]
        
        self.aggregate_functions = [
            'SUM', 'COUNT', 'AVG', 'MAX', 'MIN', 'STDDEV', 'VARIANCE'
        ]
        
        self.window_functions = [
            'ROW_NUMBER', 'RANK', 'DENSE_RANK', 'LAG', 'LEAD', 'OVER'
        ]
    
    def extract_features(self, query_text):
        """
        Extract numerical features from SQL query text
        """
        if not query_text or not isinstance(query_text, str):
            return self._get_default_features()
        
        query_upper = query_text.upper()
        
        features = {
            # Basic query characteristics
            'query_length': len(query_text),
            'query_complexity_score': self._calculate_complexity_score(query_upper),
            'word_count': len(query_text.split()),
            'line_count': len(query_text.split('\n')),
            
            # SQL keyword counts
            'select_count': query_upper.count('SELECT'),
            'from_count': query_upper.count('FROM'),
            'where_count': query_upper.count('WHERE'),
            'group_by_count': query_upper.count('GROUP BY'),
            'order_by_count': query_upper.count('ORDER BY'),
            'having_count': query_upper.count('HAVING'),
            
            # Join analysis
            'join_count': sum([query_upper.count(join_type) for join_type in 
                              ['JOIN', 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'FULL JOIN']]),
            'subquery_count': query_upper.count('SELECT') - 1,  # Subqueries
            
            # Function usage
            'aggregate_function_count': sum([query_upper.count(func + '(') for func in self.aggregate_functions]),
            'window_function_count': sum([query_upper.count(func) for func in self.window_functions]),
            
            # Pattern detection
            'has_select_star': 1 if 'SELECT *' in query_upper else 0,
            'has_distinct': 1 if 'DISTINCT' in query_upper else 0,
            'has_union': 1 if 'UNION' in query_upper else 0,
            'has_limit': 1 if 'LIMIT' in query_upper else 0,
            'has_cte': 1 if 'WITH' in query_upper else 0,
            'has_case_when': 1 if 'CASE' in query_upper and 'WHEN' in query_upper else 0,
            
            # Potential optimization indicators
            'potential_index_benefit': self._check_index_benefit(query_upper),
            'potential_mv_benefit': self._check_materialized_view_benefit(query_upper),
            'potential_partition_benefit': self._check_partition_benefit(query_upper),
            
            # Query pattern classification
            'query_pattern_score': self._classify_query_pattern(query_upper)
        }
        
        return features
    
    def _calculate_complexity_score(self, query_upper):
        """Calculate a complexity score based on query structure"""
        score = 0
        score += query_upper.count('SELECT') * 2
        score += query_upper.count('JOIN') * 3
        score += query_upper.count('WHERE') * 1
        score += query_upper.count('GROUP BY') * 2
        score += query_upper.count('ORDER BY') * 1
        score += query_upper.count('UNION') * 3
        score += query_upper.count('WITH') * 2
        return score
    
    def _check_index_benefit(self, query_upper):
        """Check if query might benefit from indexing"""
        return 1 if ('ORDER BY' in query_upper and 'LIMIT' in query_upper) else 0
    
    def _check_materialized_view_benefit(self, query_upper):
        """Check if query might benefit from materialized views"""
        has_aggregates = any(func in query_upper for func in self.aggregate_functions)
        has_group_by = 'GROUP BY' in query_upper
        return 1 if (has_aggregates and has_group_by) else 0
    
    def _check_partition_benefit(self, query_upper):
        """Check if query might benefit from partitioning"""
        date_patterns = ['DATE(', 'TIMESTAMP(', '_PARTITIONTIME', '_PARTITIONDATE']
        return 1 if any(pattern in query_upper for pattern in date_patterns) else 0
    
    def _classify_query_pattern(self, query_upper):
        """Classify query pattern for optimization strategy"""
        if 'SELECT *' in query_upper:
            return 1  # Column selection optimization
        elif query_upper.count('JOIN') > 2:
            return 2  # Join optimization
        elif 'GROUP BY' in query_upper and any(func in query_upper for func in self.aggregate_functions):
            return 3  # Aggregation optimization
        elif 'ORDER BY' in query_upper and 'LIMIT' in query_upper:
            return 4  # Sorting optimization
        else:
            return 0  # General optimization
    
    def _get_default_features(self):
        """Return default features for empty/invalid queries"""
        return {key: 0 for key in [
            'query_length', 'query_complexity_score', 'word_count', 'line_count',
            'select_count', 'from_count', 'where_count', 'group_by_count',
            'order_by_count', 'having_count', 'join_count', 'subquery_count',
            'aggregate_function_count', 'window_function_count', 'has_select_star',
            'has_distinct', 'has_union', 'has_limit', 'has_cte', 'has_case_when',
            'potential_index_benefit', 'potential_mv_benefit', 'potential_partition_benefit',
            'query_pattern_score'
        ]}

class QueryOptimizationModel:
    """
    Machine learning model for predicting query optimization opportunities
    """
    
    def __init__(self):
        self.feature_extractor = QueryFeatureExtractor()
        self.performance_model = RandomForestRegressor(
            n_estimators=100,
            max_depth=10,
            random_state=42
        )
        self.optimization_classifier = GradientBoostingClassifier(
            n_estimators=100,
            max_depth=6,
            random_state=42
        )
        self.scaler = StandardScaler()
        self.label_encoder = LabelEncoder()
        self.is_trained = False
        
        # Initialize logging
        logging.basicConfig(level=logging.INFO)
        self.logger = logging.getLogger(__name__)
    
    def load_training_data(self):
        """
        Load historical query performance data for training
        """
        self.logger.info("Loading training data from BigQuery")
        
        client = bigquery.Client(project=PROJECT_ID)
        
        # Query to get historical performance data with features
        training_query = f"""
        WITH query_stats AS (
            SELECT 
                query,
                query_hash,
                AVG(duration_ms) as avg_duration,
                AVG(total_bytes_processed) as avg_bytes_processed,
                AVG(total_slot_ms) as avg_slot_ms,
                COUNT(*) as execution_count,
                MAX(creation_time) as last_execution,
                -- Performance indicators
                CASE 
                    WHEN AVG(duration_ms) > 30000 THEN 'slow'
                    WHEN AVG(duration_ms) > 10000 THEN 'moderate'
                    ELSE 'fast'
                END as performance_category,
                -- Optimization opportunities
                LOGICAL_OR(has_select_star) as has_select_star,
                LOGICAL_OR(potential_index_benefit) as potential_index_benefit,
                LOGICAL_OR(complex_joins) as complex_joins
            FROM `{PROJECT_ID}.{DATASET_NAME}.query_performance_metrics`
            WHERE 
                creation_time >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 30 DAY)
                AND query IS NOT NULL
                AND duration_ms > 0
            GROUP BY query, query_hash
            HAVING execution_count >= 2
        )
        SELECT 
            query,
            avg_duration,
            avg_bytes_processed,
            avg_slot_ms,
            execution_count,
            performance_category,
            has_select_star,
            potential_index_benefit,
            complex_joins,
            -- Optimization type based on characteristics
            CASE 
                WHEN has_select_star THEN 'column_selection'
                WHEN complex_joins THEN 'join_optimization'
                WHEN avg_duration > 30000 THEN 'query_restructuring'
                WHEN execution_count >= 10 THEN 'materialized_view'
                ELSE 'general_optimization'
            END as optimization_type
        FROM query_stats
        ORDER BY avg_duration DESC
        LIMIT 5000
        """
        
        try:
            df = client.query(training_query).to_dataframe()
            self.logger.info(f"Loaded {len(df)} training samples")
            return df
        except Exception as e:
            self.logger.error(f"Failed to load training data: {str(e)}")
            raise
    
    def prepare_features(self, df):
        """
        Prepare features and labels for training
        """
        self.logger.info("Preparing features for training")
        
        features_list = []
        
        for _, row in df.iterrows():
            query_features = self.feature_extractor.extract_features(row['query'])
            
            # Add performance metrics as features
            query_features.update({
                'avg_bytes_processed_log': np.log1p(row['avg_bytes_processed']),
                'avg_slot_ms_log': np.log1p(row['avg_slot_ms']),
                'execution_frequency': row['execution_count']
            })
            
            features_list.append(query_features)
        
        # Convert to DataFrame
        X = pd.DataFrame(features_list)
        
        # Prepare labels
        y_performance = df['avg_duration']  # Regression target
        y_optimization = df['optimization_type']  # Classification target
        
        # Encode optimization types
        y_optimization_encoded = self.label_encoder.fit_transform(y_optimization)
        
        self.logger.info(f"Prepared {X.shape[1]} features for {len(X)} samples")
        
        return X, y_performance, y_optimization_encoded, y_optimization
    
    def train(self):
        """
        Train the optimization model on historical data
        """
        self.logger.info("Starting model training")
        
        # Load and prepare data
        df = self.load_training_data()
        
        if len(df) < 50:
            self.logger.warning(f"Insufficient training data: {len(df)} samples. Need at least 50.")
            return False
        
        X, y_performance, y_optimization_encoded, y_optimization = self.prepare_features(df)
        
        # Handle missing values
        X = X.fillna(0)
        
        # Split data
        X_train, X_test, y_perf_train, y_perf_test, y_opt_train, y_opt_test = train_test_split(
            X, y_performance, y_optimization_encoded, test_size=0.2, random_state=42
        )
        
        # Scale features
        X_train_scaled = self.scaler.fit_transform(X_train)
        X_test_scaled = self.scaler.transform(X_test)
        
        # Train performance regression model
        self.logger.info("Training performance prediction model")
        self.performance_model.fit(X_train_scaled, y_perf_train)
        
        # Evaluate performance model
        perf_pred = self.performance_model.predict(X_test_scaled)
        perf_rmse = np.sqrt(mean_squared_error(y_perf_test, perf_pred))
        self.logger.info(f"Performance model RMSE: {perf_rmse:.2f}ms")
        
        # Train optimization classification model
        self.logger.info("Training optimization type classifier")
        self.optimization_classifier.fit(X_train_scaled, y_opt_train)
        
        # Evaluate classification model
        opt_pred = self.optimization_classifier.predict(X_test_scaled)
        opt_accuracy = accuracy_score(y_opt_test, opt_pred)
        self.logger.info(f"Optimization classifier accuracy: {opt_accuracy:.3f}")
        
        # Feature importance analysis
        feature_importance = pd.DataFrame({
            'feature': X.columns,
            'importance': self.performance_model.feature_importances_
        }).sort_values('importance', ascending=False)
        
        self.logger.info("Top 5 important features:")
        for _, row in feature_importance.head().iterrows():
            self.logger.info(f"  {row['feature']}: {row['importance']:.3f}")
        
        self.is_trained = True
        return True
    
    def predict_optimization_opportunity(self, query):
        """
        Predict optimization opportunity for a given query
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before making predictions")
        
        # Extract features
        features = self.feature_extractor.extract_features(query)
        
        # Add default performance metrics for new queries
        features.update({
            'avg_bytes_processed_log': 0,
            'avg_slot_ms_log': 0,
            'execution_frequency': 1
        })
        
        # Convert to DataFrame and scale
        X = pd.DataFrame([features])
        X_scaled = self.scaler.transform(X)
        
        # Make predictions
        predicted_duration = self.performance_model.predict(X_scaled)[0]
        predicted_opt_type_encoded = self.optimization_classifier.predict(X_scaled)[0]
        predicted_opt_type = self.label_encoder.inverse_transform([predicted_opt_type_encoded])[0]
        
        # Calculate optimization confidence
        opt_probabilities = self.optimization_classifier.predict_proba(X_scaled)[0]
        confidence = np.max(opt_probabilities)
        
        return {
            'predicted_duration_ms': float(predicted_duration),
            'optimization_type': predicted_opt_type,
            'confidence_score': float(confidence),
            'needs_optimization': predicted_duration > 10000,  # > 10 seconds
            'features': features
        }
    
    def save_model(self):
        """
        Save trained model to Cloud Storage
        """
        if not self.is_trained:
            raise ValueError("Model must be trained before saving")
        
        self.logger.info("Saving model to Cloud Storage")
        
        # Create local model files
        joblib.dump(self.performance_model, 'performance_model.pkl')
        joblib.dump(self.optimization_classifier, 'optimization_classifier.pkl')
        joblib.dump(self.scaler, 'scaler.pkl')
        joblib.dump(self.label_encoder, 'label_encoder.pkl')
        
        # Upload to Cloud Storage
        client = storage.Client(project=PROJECT_ID)
        bucket = client.bucket(BUCKET_NAME)
        
        model_files = [
            'performance_model.pkl',
            'optimization_classifier.pkl',
            'scaler.pkl',
            'label_encoder.pkl'
        ]
        
        for file_name in model_files:
            blob = bucket.blob(f'ml/models/{file_name}')
            blob.upload_from_filename(file_name)
            self.logger.info(f"Uploaded {file_name} to Cloud Storage")
        
        # Save model metadata
        metadata = {
            'model_name': MODEL_NAME,
            'training_date': datetime.now().isoformat(),
            'model_version': '1.0',
            'features_count': len(self.feature_extractor._get_default_features()),
            'optimization_types': self.label_encoder.classes_.tolist()
        }
        
        metadata_blob = bucket.blob(f'ml/models/metadata.json')
        metadata_blob.upload_from_string(json.dumps(metadata, indent=2))
        
        self.logger.info("Model saved successfully")

def main():
    """
    Main training function
    """
    print("Starting Query Optimization Model Training")
    
    # Initialize and train model
    model = QueryOptimizationModel()
    
    try:
        success = model.train()
        if success:
            model.save_model()
            print("Model training completed successfully")
            
            # Test prediction on sample query
            sample_query = """
            SELECT *
            FROM sales_transactions
            WHERE transaction_date >= '2024-01-01'
            ORDER BY amount DESC
            LIMIT 100
            """
            
            prediction = model.predict_optimization_opportunity(sample_query)
            print(f"Sample prediction: {prediction}")
            
        else:
            print("Model training failed - insufficient data")
            
    except Exception as e:
        print(f"Training failed: {str(e)}")
        raise

if __name__ == "__main__":
    main()