#!/bin/bash
set -e

AWS_REGION=$(aws configure get region)
LAMBDA_ZIP=lambda/dynamo_stream_to_master.zip

echo "Packaging Lambda function..."
(cd lambda && zip -r ../$LAMBDA_ZIP dynamo_stream_to_master.py)

echo "Lambda package created at $LAMBDA_ZIP"

# Optional: Upload to S3 if you prefer managing Lambda packages via S3
# echo "Uploading Lambda package to S3 bucket..."
# aws s3 cp $LAMBDA_ZIP s3://your-lambda-bucket/$LAMBDA_ZIP
# echo "Upload complete."

echo "Lambda packaging done."
