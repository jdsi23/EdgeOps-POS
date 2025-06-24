# Use official Python image as base
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy requirements first (for caching)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy app source code
COPY app.py .
COPY templates ./templates

# Expose port 5000
EXPOSE 5000

# Run the Flask app
CMD ["python", "app.py"]
