import React from 'react';
import SwaggerUI from 'swagger-ui-react';
import 'swagger-ui-react/swagger-ui.css';

const ApiDocs: React.FC = () => {
  const spec = {
    openapi: '3.0.0',
    info: {
      title: 'Development Sandbox API',
      version: '1.0.0',
      description: 'API documentation for the Development Sandbox environment'
    },
    servers: [
      {
        url: 'http://localhost:8000',
        description: 'Development server'
      },
      {
        url: 'https://api.${DOMAIN}',
        description: 'Production server'
      }
    ],
    components: {
      securitySchemes: {
        bearerAuth: {
          type: 'http',
          scheme: 'bearer',
          bearerFormat: 'JWT'
        }
      }
    },
    paths: {
      '/api/health': {
        get: {
          summary: 'Health Check',
          responses: {
            '200': {
              description: 'System is healthy',
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    properties: {
                      status: {
                        type: 'string',
                        example: 'healthy'
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  };

  return (
    <div className="w-full">
      <SwaggerUI spec={spec} />
    </div>
  );
};

export default ApiDocs;