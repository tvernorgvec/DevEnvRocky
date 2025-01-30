import express from 'express';
import { exec } from 'child_process';
import { promisify } from 'util';
import cors from 'cors';

const app = express();
const execAsync = promisify(exec);

// Middleware
app.use(express.json());
app.use(cors());

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ status: 'healthy' });
});

// Update endpoint
app.post('/update', async (req, res) => {
  try {
    const { stdout, stderr } = await execAsync('sudo /home/project/scripts/update-system.sh');
    
    console.log('Update stdout:', stdout);
    if (stderr) console.error('Update stderr:', stderr);
    
    res.json({ 
      success: true, 
      message: 'System updated successfully',
      details: stdout
    });
  } catch (error) {
    console.error('Update failed:', error);
    res.status(500).json({ 
      success: false, 
      message: 'Update failed',
      error: error.message 
    });
  }
});

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});