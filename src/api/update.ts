import express from 'express';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);
const router = express.Router();

router.post('/update', async (req, res) => {
  try {
    // Execute the update script
    const { stdout, stderr } = await execAsync('/home/project/scripts/update-system.sh');
    
    // Log the output
    console.log('Update stdout:', stdout);
    if (stderr) console.error('Update stderr:', stderr);
    
    res.json({ success: true, message: 'System updated successfully' });
  } catch (error) {
    console.error('Update failed:', error);
    res.status(500).json({ success: false, message: 'Update failed' });
  }
});

export default router;