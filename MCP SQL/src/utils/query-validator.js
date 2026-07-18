// query-validator.js
// Text-based read-only enforcement for run_query / explain_query.
// This is a defense-in-depth layer, not the sole guarantee — the SQL Server
// login used by this MCP should also be restricted to db_datareader.

function stripCommentsAndStrings(sqlText) {
  let result = '';
  let i = 0;
  const n = sqlText.length;
  while (i < n) {
    const ch = sqlText[i];
    const two = sqlText.slice(i, i + 2);

    if (ch === "'") {
      let j = i + 1;
      while (j < n) {
        if (sqlText[j] === "'" && sqlText[j + 1] === "'") {
          j += 2;
          continue;
        }
        if (sqlText[j] === "'") {
          j++;
          break;
        }
        j++;
      }
      result += ' STR ';
      i = j;
      continue;
    }

    if (two === '--') {
      let j = i + 2;
      while (j < n && sqlText[j] !== '\n') j++;
      i = j;
      continue;
    }

    if (two === '/*') {
      let j = i + 2;
      while (j < n && sqlText.slice(j, j + 2) !== '*/') j++;
      i = j + 2;
      continue;
    }

    result += ch;
    i++;
  }
  return result;
}

const FORBIDDEN_KEYWORDS = [
  'INSERT', 'UPDATE', 'DELETE', 'MERGE', 'DROP', 'ALTER',
  'TRUNCATE', 'EXEC', 'EXECUTE', 'INTO', 'GRANT', 'REVOKE', 'CREATE'
];

export function validateReadOnlyQuery(rawSql) {
  if (!rawSql || !rawSql.trim()) {
    return { ok: false, reason: 'Query kosong.' };
  }

  const cleaned = stripCommentsAndStrings(rawSql).trim();

  if (!/^(SELECT|WITH)\b/i.test(cleaned)) {
    return { ok: false, reason: 'Hanya statement SELECT atau WITH...SELECT yang diizinkan.' };
  }

  const withoutTrailingSemicolon = cleaned.replace(/;\s*$/, '');
  if (withoutTrailingSemicolon.includes(';')) {
    return { ok: false, reason: 'Multi-statement (dipisah ";") tidak diizinkan.' };
  }

  for (const kw of FORBIDDEN_KEYWORDS) {
    const re = new RegExp(`\\b${kw}\\b`, 'i');
    if (re.test(cleaned)) {
      return { ok: false, reason: `Kata kunci terlarang terdeteksi: ${kw}.` };
    }
  }

  return { ok: true };
}
