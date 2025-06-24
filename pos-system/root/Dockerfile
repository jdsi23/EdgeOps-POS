# Use official Python slim image
FROM python:3.9-slim

# Set working directory inside container
WORKDIR /app

# Copy requirements.txt if you have one, otherwise skip this step
# COPY requirements.txt .

# Install Python dependencies (Flask)
RUN pip install --no-cache-dir flask boto3

# Copy your app and config files into the container
COPY app.py .
COPY nginx.conf .

# Expose port 80 for the container
EXPOSE 80

# Start the Flask app
CMD ["python", "app.py"]
