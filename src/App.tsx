import React, { useState } from 'react';
import { Terminal, Settings } from 'lucide-react';
import ServerStatus from './components/ServerStatus';

function App() {
  return (
    <div className="min-h-screen bg-gray-100">
      {/* Header */}
      <header className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 py-4 sm:px-6 lg:px-8 flex items-center justify-between">
          <div className="flex items-center">
            <Terminal className="h-8 w-8 text-indigo-600" />
            <h1 className="ml-3 text-2xl font-bold text-gray-900">Server Management</h1>
          </div>
          <div className="flex items-center space-x-4">
            <Settings className="h-6 w-6 text-gray-400" />
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto px-4 py-8 sm:px-6 lg:px-8">
        <ServerStatus />
      </main>
    </div>
  );
}

export default App;