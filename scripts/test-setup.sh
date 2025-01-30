#!/bin/bash

# Exit on error
set -e

# Create necessary directories
echo "Creating required directories..."
mkdir -p config/wiremock/mappings
mkdir -p scripts
mkdir -p tests/api
mkdir -p kubernetes

# Create WireMock mappings
echo "Setting up WireMock mappings..."
cat > config/wiremock/mappings/api-mocks.json <<EOF
{
  "mappings": [
    {
      "request": {
        "method": "GET",
        "url": "/api/health"
      },
      "response": {
        "status": 200,
        "headers": {
          "Content-Type": "application/json"
        },
        "jsonBody": {
          "status": "healthy",
          "timestamp": "{{now}}"
        }
      }
    },
    {
      "request": {
        "method": "GET",
        "url": "/api/users"
      },
      "response": {
        "status": 200,
        "headers": {
          "Content-Type": "application/json"
        },
        "jsonBody": [
          {
            "id": 1,
            "name": "Test User",
            "email": "test@example.com"
          }
        ]
      }
    }
  ]
}
EOF

# Create test script
echo "Creating test script..."
cat > tests/api/test_mock_api.sh <<EOF
#!/bin/bash

# Exit on error
set -e

# Test health endpoint
echo "Testing health endpoint..."
response=\$(curl -s http://localhost:8080/api/health)
if echo "\$response" | jq -e '.status == "healthy"' > /dev/null; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    exit 1
fi

# Test users endpoint
echo "Testing users endpoint..."
response=\$(curl -s http://localhost:8080/api/users)
if echo "\$response" | jq -e 'length > 0' > /dev/null; then
    echo "✅ Users endpoint passed"
else
    echo "❌ Users endpoint failed"
    exit 1
fi

echo "All tests passed! ✨"
EOF

# Make scripts executable
chmod +x tests/api/test_mock_api.sh

# Verify docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed"
    exit 1
fi

# Start test environment
echo "Starting test environment..."
if [ ! -f docker-compose.test.yml ]; then
    echo "Error: docker-compose.test.yml not found"
    exit 1
fi

docker-compose -f docker-compose.test.yml up -d

# Wait for WireMock to be ready
echo "Waiting for WireMock to be ready..."
max_retries=30
retry_count=0
while ! curl -s http://localhost:8080/__admin/mappings > /dev/null && [ $retry_count -lt $max_retries ]; do
    echo "Waiting for WireMock... ($(($retry_count + 1))/$max_retries)"
    sleep 2
    retry_count=$((retry_count + 1))
done

if [ $retry_count -eq $max_retries ]; then
    echo "Error: WireMock failed to start"
    docker-compose -f docker-compose.test.yml logs
    docker-compose -f docker-compose.test.yml down
    exit 1
fi

# Run tests
echo "Running tests..."
./tests/api/test_mock_api.sh

echo "Test environment setup complete!"
echo "WireMock UI: http://localhost:8080/__admin"
echo "Mock API Endpoint: http://localhost:8080/api"