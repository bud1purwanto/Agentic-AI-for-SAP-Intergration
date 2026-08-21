import { serverManager } from './src/server-manager.js';
import { read_table } from './src/tools/query-tools.js';

async function main() {
  await serverManager.loadConfig();
  await serverManager.setActiveServer('dev');
  
  const mseg = await read_table({ table: 'MSEG', fields: ['MBLNR', 'ZEILE', 'BWART', 'AUFNR', 'SHKZG'], where: ["CHARG = '0000405831'"] });
  console.log("0000405831 MSEG:", JSON.stringify(mseg.rows, null, 2));

  const mseg2 = await read_table({ table: 'MSEG', fields: ['MBLNR', 'ZEILE', 'BWART', 'AUFNR', 'SHKZG'], where: ["CHARG = '0000405832'"] });
  console.log("0000405832 MSEG:", JSON.stringify(mseg2.rows, null, 2));
}

main().catch(console.error);
