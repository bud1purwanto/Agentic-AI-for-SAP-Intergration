import { serverManager } from './src/server-manager.js';
import { read_program } from './src/tools/abap-tools.js';
import fs from 'fs';

async function main() {
  await serverManager.loadConfig();
  // Try sandbox-new first, if not try dev-aix
  await serverManager.setActiveServer('sandbox-new');
  
  let result = await read_program({ program_name: 'ZMMI_PO_RELEASE_PHASE2' });
  if (!result.source) {
      console.log('Not found in sandbox, trying dev-aix...');
      await serverManager.setActiveServer('dev-aix');
      result = await read_program({ program_name: 'ZMMI_PO_RELEASE_PHASE2' });
  }

  if (result.source) {
    fs.writeFileSync('../ZMMI_PO_RELEASE_PHASE2.abap', result.source);
    console.log('Successfully saved to ../ZMMI_PO_RELEASE_PHASE2.abap');
  } else {
    console.log('Failed to fetch from both servers:', result);
  }
}

main().catch(console.error);
