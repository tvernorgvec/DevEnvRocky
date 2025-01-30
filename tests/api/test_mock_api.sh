#!/bin/bash

# Test health endpoint
echo "Testing health endpoint..."
response=$(curl -s http://localhost:8080/api/health)
if echo "$response" | jq -e '.status == "healthy"' > /dev/null; then
    echo "✅ Health check passed"
else
    echo "❌ Health check failed"
    exit 1
fi

# Test users endpoint
echo "Testing users endpoint..."
response=$(curl -s http://localhost:8080/api/users)
if echo "$response" | jq -e 'length > 0' > /dev/null; then
    echo "✅ Users endpoint passed"
else
    echo "❌ Users endpoint failed"
    exit 1
fi

# Test user creation
echo "Testing user creation..."
response=$(curl -s -X POST http://localhost:8080/api/users \
    -H "Content-Type: application/json" \
    -d '{"name": "New User"}')
if echo "$response" | jq -e '.id and .name == "New User"' > /dev/null; then
    echo "✅ User creation passed"
else
    echo "❌ User creation failed"
    exit 1
fi

echo "All tests passed! ✨"