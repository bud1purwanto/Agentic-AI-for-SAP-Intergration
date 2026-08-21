import { serverManager } from './src/server-manager.js';
import { read_table } from './src/tools/query-tools.js';

async function main() {
  await serverManager.loadConfig();
  await serverManager.setActiveServer('sandbox-new');
  
  // Find AFPO records that might have MILL_OC_AUFNR_U populated
  const res = await read_table({
    table: 'AFPO',
    fields: ['AUFNR', 'MILL_OC_AUFNR_U'],
    where: ["MILL_OC_AUFNR_U <> ''"],
    rowcount: 5
  });
  console.log(res);
}

main().catch(console.error);
