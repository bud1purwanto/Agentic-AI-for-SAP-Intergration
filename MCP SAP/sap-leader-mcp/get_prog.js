import { serverManager } from './src/server-manager.js';
import { read_program } from './src/tools/abap-tools.js';
import fs from 'fs';

async function main() {
  serverManager.loadConfig();
  await serverManager.setActiveServer('sandbox-new');
  
  const result = await read_program({ program_name: process.argv[2] });
  if (result.source) {
    fs.writeFileSync(`${process.argv[2]}.abap`, result.source);
    console.log(`Successfully saved to ${process.argv[2]}.abap`);
  } else {
    console.log('Failed:', result);
  }
}

main().catch(console.error);
