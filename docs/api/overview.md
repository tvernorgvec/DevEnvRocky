# API Documentation

## Introduction

This API documentation provides comprehensive information about the available endpoints, authentication methods, and usage examples for the Development Sandbox services.

## Authentication

All API endpoints require authentication. We support the following methods:

- JWT Authentication
- API Key Authentication
- OAuth2 (for specific services)

## Base URLs

- Development: `http://localhost:8000`
- Staging: `https://api-staging.${DOMAIN}`
- Production: `https://api.${DOMAIN}`

## Rate Limiting

The API implements rate limiting to ensure fair usage:

- 100 requests per minute
- 1000 requests per hour

## Common Response Codes

- `200`: Success
- `201`: Created
- `400`: Bad Request
- `401`: Unauthorized
- `403`: Forbidden
- `404`: Not Found
- `429`: Too Many Requests
- `500`: Internal Server Error