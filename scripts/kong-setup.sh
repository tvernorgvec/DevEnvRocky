#!/bin/bash

# Wait for Kong to be ready
echo "Waiting for Kong to be ready..."
until curl -s http://localhost:8001/status > /dev/null; do
    sleep 5
done

# Configure services and routes
echo "Configuring Kong services and routes..."

# ProjectX Service
curl -i -X POST http://localhost:8001/services \
    --data name=projectx \
    --data url=http://projectx:8080

curl -i -X POST http://localhost:8001/services/projectx/routes \
    --data 'paths[]=/api/projectx' \
    --data name=projectx-route

# ProjectY Service
curl -i -X POST http://localhost:8001/services \
    --data name=projecty \
    --data url=http://projecty:3000

curl -i -X POST http://localhost:8001/services/projecty/routes \
    --data 'paths[]=/api/projecty' \
    --data name=projecty-route

# Enable rate limiting plugin globally
curl -i -X POST http://localhost:8001/plugins \
    --data name=rate-limiting \
    --data config.minute=100 \
    --data config.hour=1000

# Enable JWT authentication
curl -i -X POST http://localhost:8001/plugins \
    --data name=jwt

# Enable CORS
curl -i -X POST http://localhost:8001/plugins \
    --data name=cors \
    --data config.origins=* \
    --data config.methods=GET,POST,PUT,DELETE,OPTIONS \
    --data config.headers=Content-Type,Authorization \
    --data config.exposed_headers=X-Auth-Token \
    --data config.credentials=true \
    --data config.max_age=3600

echo "Kong configuration completed successfully"