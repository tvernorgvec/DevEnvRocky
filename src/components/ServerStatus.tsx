import React, { useState } from 'react';
import { RefreshCw, Server, Check, AlertTriangle, XCircle } from 'lucide-react';

interface ServiceStatus {
  name: string;
  status: 'running' | 'warning' | 'stopped';
  url?: string;
  lastUpdated: string;
}

const API_URL = 'http://localhost:3001';

const ServerStatus: React.FC = () => {
  const [isUpdating, setIsUpdating] = useState(false);
  const [updateError, setUpdateError] = useState<string | null>(null);
  const [services, setServices] = useState<ServiceStatus[]>([
    {
      name: 'Nginx',
      status: 'running',
      url: 'https://isp-pybox.gvec.net',
      lastUpdated: new Date().toISOString()
    },
    {
      name: 'Docker',
      status: 'running',
      lastUpdated: new Date().toISOString()
    },
    {
      name: 'Prometheus',
      status: 'running',
      url: 'https://prometheus.isp-pybox.gvec.net',
      lastUpdated: new Date().toISOString()
    },
    {
      name: 'Grafana',
      status: 'running',
      url: 'https://grafana.isp-pybox.gvec.net',
      lastUpdated: new Date().toISOString()
    }
  ]);

  const handleUpdate = async () => {
    setIsUpdating(true);
    setUpdateError(null);
    
    try {
      const response = await fetch(`${API_URL}/update`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        }
      });

      const data = await response.json();

      if (!response.ok) {
        throw new Error(data.message || 'Update failed');
      }

      // Update services status
      setServices(prev => prev.map(service => ({
        ...service,
        lastUpdated: new Date().toISOString()
      })));

    } catch (error) {
      console.error('Update failed:', error);
      setUpdateError(error.message || 'Update failed. Please try again.');
    } finally {
      setIsUpdating(false);
    }
  };

  const getStatusIcon = (status: ServiceStatus['status']) => {
    switch (status) {
      case 'running':
        return <Check className="h-5 w-5 text-green-500" />;
      case 'warning':
        return <AlertTriangle className="h-5 w-5 text-yellow-500" />;
      case 'stopped':
        return <XCircle className="h-5 w-5 text-red-500" />;
    }
  };

  return (
    <div className="bg-white shadow-lg rounded-lg p-6">
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center">
          <Server className="h-6 w-6 text-indigo-600 mr-3" />
          <h2 className="text-2xl font-bold text-gray-800">Server Status</h2>
        </div>
        <button
          onClick={handleUpdate}
          disabled={isUpdating}
          className={`flex items-center px-4 py-2 rounded-md text-white ${
            isUpdating ? 'bg-gray-400' : 'bg-indigo-600 hover:bg-indigo-700'
          }`}
        >
          <RefreshCw className={`h-5 w-5 mr-2 ${isUpdating ? 'animate-spin' : ''}`} />
          {isUpdating ? 'Updating...' : 'Update System'}
        </button>
      </div>

      {updateError && (
        <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-md">
          <p className="text-red-700">{updateError}</p>
        </div>
      )}

      <div className="grid gap-6 mb-8">
        {services.map((service) => (
          <div
            key={service.name}
            className="flex items-center justify-between p-4 bg-gray-50 rounded-lg"
          >
            <div className="flex items-center">
              {getStatusIcon(service.status)}
              <div className="ml-4">
                <h3 className="text-lg font-medium text-gray-900">{service.name}</h3>
                {service.url && (
                  <a
                    href={service.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-sm text-indigo-600 hover:text-indigo-800"
                  >
                    {service.url}
                  </a>
                )}
              </div>
            </div>
            <div className="text-right">
              <div className="text-sm text-gray-500">
                Last Updated
              </div>
              <div className="text-sm font-medium text-gray-900">
                {new Date(service.lastUpdated).toLocaleString()}
              </div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};

export default ServerStatus;