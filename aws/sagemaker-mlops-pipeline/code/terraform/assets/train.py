import argparse
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report
import joblib
import os
import json

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--n_estimators', type=int, default=100)
    parser.add_argument('--max_depth', type=int, default=10)
    parser.add_argument('--model_dir', type=str, default=os.environ.get('SM_MODEL_DIR'))
    parser.add_argument('--train', type=str, default=os.environ.get('SM_CHANNEL_TRAINING'))
    
    args = parser.parse_args()
    
    # Generate synthetic training data for demonstration
    np.random.seed(42)
    n_samples = 10000
    n_features = 20
    
    # Create synthetic features
    X = np.random.randn(n_samples, n_features)
    # Create target with some correlation to features
    y = (X[:, 0] + X[:, 1] + np.random.randn(n_samples) * 0.1 > 0).astype(int)
    
    # Split data
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42
    )
    
    # Train model
    model = RandomForestClassifier(
        n_estimators=args.n_estimators,
        max_depth=args.max_depth,
        random_state=42
    )
    model.fit(X_train, y_train)
    
    # Evaluate model
    y_pred = model.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    
    print(f"Model accuracy: {accuracy:.4f}")
    print(classification_report(y_test, y_pred))
    
    # Save model
    joblib.dump(model, os.path.join(args.model_dir, 'model.joblib'))
    
    # Save model metrics
    metrics = {
        'accuracy': accuracy,
        'n_estimators': args.n_estimators,
        'max_depth': args.max_depth
    }
    
    with open(os.path.join(args.model_dir, 'metrics.json'), 'w') as f:
        json.dump(metrics, f)

if __name__ == '__main__':
    main()