require('dotenv').config();
const httpntlm = require('httpntlm');

const pass = process.env.EMAIL_PASS;

const soap = [
  '<?xml version="1.0" encoding="utf-8"?>',
  '<soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"',
  '  xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"',
  '  xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">',
  '  <soap:Body>',
  '    <m:FindItem Traversal="Shallow">',
  '      <m:ItemShape><t:BaseShape>IdOnly</t:BaseShape></m:ItemShape>',
  '      <m:CalendarView StartDate="2026-07-01T00:00:00Z" EndDate="2026-07-31T23:59:59Z" MaxEntriesReturned="3"/>',
  '      <m:ParentFolderIds>',
  '        <t:DistinguishedFolderId Id="calendar"/>',
  '      </m:ParentFolderIds>',
  '    </m:FindItem>',
  '  </soap:Body>',
  '</soap:Envelope>'
].join('\n');

function tryAuth(label, opts) {
  return new Promise(resolve => {
    httpntlm.post({
      ...opts,
      body: soap,
      headers: { 'Content-Type': 'text/xml; charset=utf-8' },
    }, function(err, res) {
      const status = err ? 'ERR:' + err.message : 'HTTP ' + res.statusCode;
      const body = (!err && res.body) ? res.body.toString().slice(0, 200) : '';
      console.log(label, '->', status, body ? '| ' + body.replace(/\s+/g,' ').slice(0,100) : '');
      resolve();
    });
  });
}

const rawUser = process.env.EMAIL_LOGIN_USER || '';
const domain = rawUser.includes('\\') ? rawUser.split('\\')[0] : '';
const username = rawUser.includes('\\') ? rawUser.split('\\')[1] : rawUser;
const emailAddr = process.env.EMAIL_USER || '';

(async () => {
  if (domain && username) {
    // Try 1: DOMAIN\user with short domain
    await tryAuth(`NTLM ${domain}\\${username}`, {
      url: 'https://mail.trst.co.id/EWS/Exchange.asmx',
      username, password: pass, domain,
    });
  }
  if (emailAddr) {
    // Try 2: email address as username (no domain)
    await tryAuth('NTLM email address', {
      url: 'https://mail.trst.co.id/EWS/Exchange.asmx',
      username: emailAddr, password: pass, domain: '',
    });
  }
})();
