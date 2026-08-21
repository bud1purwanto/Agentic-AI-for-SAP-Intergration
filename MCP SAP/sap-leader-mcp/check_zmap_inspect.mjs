import { serverManager } from './src/server-manager.js';
import { read_table, call_function } from './src/tools/query-tools.js';

async function main() {
  await serverManager.loadConfig();
  await serverManager.setActiveServer('sandbox-new');

  // 1. Cek isi tabel ZMAP_TYPE untuk ZPPI_COHVPI
  const resTable = await read_table({
    table: 'ZMAP_TYPE',
    where: ["PROG = 'ZPPI_COHVPI'"]
  });
  console.log('=== DATA ZMAP_TYPE UNTUK ZPPI_COHVPI ===');
  console.log(JSON.stringify(resTable, null, 2));

  // 2. Cek syntax program ZPPI_COHVPI via RFC jika memungkinkan / atau cek status update
  const syn = await call_function({
    function_name: 'SYNTAX_CHECK_PROGRAM',
    parameters: {
      PROGRAM: 'ZPPI_COHVPI'
    }
  });
  console.log('=== HASIL SYNTAX CHECK (RFC SYNTAX_CHECK_PROGRAM) ===');
  console.log(JSON.stringify(syn, null, 2));
}

main().catch(console.error);
