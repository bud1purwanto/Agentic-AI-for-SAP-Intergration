import { serverManager } from './src/server-manager.js';
import { call_function } from './src/tools/query-tools.js';
import fs from 'fs';

async function main() {
  await serverManager.loadConfig();
  await serverManager.setActiveServer('sandbox-new');
  
  const progName = process.argv[2];
  const fileName = process.argv[3];
  
  const sourceCode = fs.readFileSync(fileName, 'utf-8');
  const sourceLines = sourceCode.split(/\r?\n/);
  
  const itSource = sourceLines.map(line => ({ LINE: line }));

  console.log(`Pushing ${itSource.length} lines to ${progName}...`);

  const result = await call_function({
    function_name: 'Z_RFC_PROGRAM_UPDATE',
    parameters: {
      IV_PROGRAM_NAME: progName,
      IV_PACKAGE: '$TMP',
      IV_CORRNUMBER: ' ',
      IT_SOURCE: itSource
    }
  });

  if (result.result) {
    console.log('Success:', result.result.EV_SUCCESS);
    console.log('Message:', result.result.EV_MESSAGE);
  } else {
    console.log('Result:', result);
  }
}

main().catch(console.error);
