import { serverManager } from './src/server-manager.js';
import { read_table, call_function } from './src/tools/query-tools.js';
import { read_program } from './src/tools/abap-tools.js';

async function main() {
  await serverManager.loadConfig();
  const connectRes = await serverManager.setActiveServer('sandbox-new');
  console.log('Connect result:', connectRes);
  
  const result = await read_table({
    table: 'TSTC',
    fields: ['TCODE', 'PGMNA'],
    where: ["TCODE = 'ZQM016'"]
  });
  
  console.log('TSTC Result:', result);
  
  if (result.rows && result.rows.length > 0) {
    const pgmna = result.rows[0].PGMNA;
    console.log(`Program for ZQM016 is ${pgmna}`);
    
    // Now get the source code
    const sourceRes = await read_program({ program_name: pgmna });
    if (sourceRes.source) {
      import('fs').then(fs => {
        fs.writeFileSync('../' + pgmna + '.abap', sourceRes.source);
        console.log(`Successfully saved to ../${pgmna}.abap`);
      });
    } else {
      console.log('Failed to read program:', sourceRes);
    }
  }
}

main().catch(console.error);
