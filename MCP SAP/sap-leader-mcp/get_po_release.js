import { serverManager } from './src/server-manager.js';
import { read_program } from './src/tools/abap-tools.js';
import fs from 'fs';

async function main() {
  await serverManager.loadConfig();
  const connectRes = await serverManager.setActiveServer('dev-aix');
  console.log('Connect result:', connectRes);
  
  const result = await read_program({ program_name: 'ZMMI_PO_RELEASE' });
  if (result.source) {
    fs.writeFileSync('../ZMMI_PO_RELEASE.abap', result.source);
    console.log('Successfully saved to ../ZMMI_PO_RELEASE.abap');
  } else {
    console.log('Failed:', result);
  }
}

main().catch(console.error);
