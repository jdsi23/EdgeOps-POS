# Use official Python base image
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy dependencies
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy app source and templates
COPY app.py .
COPY templates ./templates

# Expose port 5000
EXPOSE 5000

# Run the Flask app
CMD ["python", "app.py"]
