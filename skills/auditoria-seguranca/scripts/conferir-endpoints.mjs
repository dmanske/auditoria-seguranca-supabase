// Confere, como VISITANTE (só a chave pública e tokens FALSOS), se cada endpoint responde como esperado.
// Use antes e depois de publicar correções. Não usa token real nem dado de cliente.
//
// Uso:  node conferir-endpoints.mjs <.env> <casos.json>
// casos.json: lista de { "nome", "caminho", "metodo"?, "corpo"?, "esperado": [401, 403], "nao_conter"?: ["cpf"] }
//   - caminho começa com /functions/v1/... ou /rest/v1/rpc/...
//   - "esperado": status aceitos; "nao_conter": textos que NÃO podem aparecer na resposta.
// Veja conferir-endpoints.exemplo.json.
import { readFileSync } from 'node:fs';

const [envPath, casosPath] = process.argv.slice(2);
if (!envPath || !casosPath) { console.error('Uso: node conferir-endpoints.mjs <.env> <casos.json>'); process.exit(1); }

const env = Object.fromEntries(
  readFileSync(envPath, 'utf8').split('\n')
    .map((l) => l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)).filter(Boolean)
    .map((m) => [m[1], m[2].replace(/^["']|["']$/g, '')]),
);
const pegar = (...n) => n.map((k) => env[k]).find(Boolean);
const URL_BASE = pegar('VITE_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_URL');
const CHAVE = pegar('VITE_SUPABASE_ANON_KEY', 'VITE_SUPABASE_PUBLISHABLE_KEY', 'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY');
const H = { apikey: CHAVE, Authorization: `Bearer ${CHAVE}`, 'Content-Type': 'application/json' };

const casos = JSON.parse(readFileSync(casosPath, 'utf8'));
let falhas = 0;
for (const c of casos) {
  const r = await fetch(URL_BASE + c.caminho, { method: c.metodo || 'POST', headers: H, body: c.corpo ? JSON.stringify(c.corpo) : '{}' });
  const texto = (await r.text()).slice(0, 300).replace(/\s+/g, ' ');
  const statusOk = (c.esperado || []).includes(r.status);
  const vazou = (c.nao_conter || []).filter((t) => texto.toLowerCase().includes(t.toLowerCase()));
  const ok = statusOk && vazou.length === 0;
  if (!ok) falhas++;
  console.log(`${ok ? 'OK   ' : 'FALHA'} ${c.nome}: ${r.status} ${vazou.length ? `(contém: ${vazou.join(', ')}) ` : ''}${texto.slice(0, 140)}`);
}
console.log(`\n${casos.length - falhas} de ${casos.length} como esperado.`);
process.exit(falhas ? 1 : 0);
