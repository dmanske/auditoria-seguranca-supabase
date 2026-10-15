// Teste do visitante: com SÓ a chave pública (anon), tenta ler tudo o que o banco expõe a visitante e
// marca respostas com dado pessoal. Só leitura:
//   - GET em cada tabela/view (até 5 linhas + contagem);
//   - GET em funções ESTÁVEIS sem argumento (o PostgREST recusa GET em função que altera dado);
//   - listagem de cada bucket.
// Nunca imprime valores: só nomes de colunas, contagens e o TIPO de dado encontrado.
//
// Uso:
//   supabase db query --linked -f alvos-visitante.sql > alvos.json
//   node teste-visitante.mjs <arquivo .env> alvos.json resultado.json
// O .env precisa ter a URL e a chave pública (aceita VITE_*, NEXT_PUBLIC_* ou SUPABASE_*).
import { readFileSync, writeFileSync } from 'node:fs';

const [envPath, alvosPath, saidaPath = 'resultado-visitante.json'] = process.argv.slice(2);
if (!envPath || !alvosPath) {
  console.error('Uso: node teste-visitante.mjs <.env> <alvos.json> [resultado.json]');
  process.exit(1);
}

const env = Object.fromEntries(
  readFileSync(envPath, 'utf8').split('\n')
    .map((l) => l.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)).filter(Boolean)
    .map((m) => [m[1], m[2].replace(/^["']|["']$/g, '')]),
);
const pegar = (...nomes) => nomes.map((n) => env[n]).find(Boolean);
const URL_BASE = pegar('VITE_SUPABASE_URL', 'NEXT_PUBLIC_SUPABASE_URL', 'SUPABASE_URL');
const CHAVE = pegar('VITE_SUPABASE_ANON_KEY', 'VITE_SUPABASE_PUBLISHABLE_KEY', 'NEXT_PUBLIC_SUPABASE_ANON_KEY',
  'NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY', 'SUPABASE_ANON_KEY');
if (!URL_BASE || !CHAVE) { console.error('URL ou chave pública não encontradas no .env'); process.exit(1); }
const H = { apikey: CHAVE, Authorization: `Bearer ${CHAVE}` };

const bruto = readFileSync(alvosPath, 'utf8');
const alvos = JSON.parse(bruto.slice(bruto.indexOf('{'))).rows;

const PADROES = {
  cpf: /\b\d{3}\.?\d{3}\.?\d{3}-?\d{2}\b/,
  email: /[^\s@"]+@[^\s@"]+\.[a-z]{2,}/i,
  telefone: /\b(?:\+?55)?\s?\(?\d{2}\)?\s?9?\d{4}[-\s]?\d{4}\b/,
  jwt: /eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/,
};
const COLUNAS_SENSIVEIS = /cpf|rg\b|cnpj|telefone|celular|whats|email|nascimento|endereco|cep|foto|selfie|senha|password|hash|token|secret|chave|pix|cartao|card/i;

function analisar(linhas) {
  const colunas = new Set(); const achados = new Set();
  for (const l of linhas) {
    for (const [k, v] of Object.entries(l ?? {})) {
      colunas.add(k);
      if (v == null) continue;
      const s = typeof v === 'string' ? v : JSON.stringify(v);
      for (const [nome, re] of Object.entries(PADROES)) if (re.test(s)) achados.add(`${nome} (coluna ${k})`);
    }
  }
  return {
    colunas: [...colunas],
    colunas_sensiveis: [...colunas].filter((c) => COLUNAS_SENSIVEIS.test(c)),
    padroes_encontrados: [...achados],
  };
}

async function pedir(caminho, opcoes = {}) {
  const r = await fetch(URL_BASE + caminho, { ...opcoes, headers: { ...H, ...(opcoes.headers || {}) } });
  const texto = await r.text();
  let corpo = null; try { corpo = JSON.parse(texto); } catch { /* não é JSON */ }
  return { status: r.status, corpo, total: r.headers.get('content-range') };
}

const resultado = { quando: new Date().toISOString(), tabelas: [], funcoes_chamadas: [], funcoes_nao_chamadas: [], buckets: [] };

for (const a of alvos.filter((x) => x.tipo === 'tabela')) {
  const r = await pedir(`/rest/v1/${encodeURIComponent(a.nome)}?select=*&limit=5`, { headers: { Prefer: 'count=exact', Range: '0-4' } });
  const linhas = Array.isArray(r.corpo) ? r.corpo : [];
  const total = r.total ? r.total.split('/')[1] : null;
  resultado.tabelas.push({ nome: a.nome, status: r.status, linhas_visiveis: total, ...(linhas.length ? analisar(linhas) : {}) });
}

for (const a of alvos.filter((x) => x.tipo === 'funcao')) {
  if (a.nargs === 0 && (a.volatil === 's' || a.volatil === 'i')) {
    const r = await pedir(`/rest/v1/rpc/${encodeURIComponent(a.nome)}`);
    const linhas = Array.isArray(r.corpo) ? r.corpo : r.corpo && typeof r.corpo === 'object' ? [r.corpo] : [];
    resultado.funcoes_chamadas.push({ nome: a.nome, definer: a.definer, status: r.status, itens: linhas.length, ...(linhas.length ? analisar(linhas) : {}) });
  } else {
    resultado.funcoes_nao_chamadas.push({ nome: a.nome, definer: a.definer, nargs: a.nargs, volatil: a.volatil });
  }
}

for (const a of alvos.filter((x) => x.tipo === 'bucket')) {
  const r = await pedir(`/storage/v1/object/list/${encodeURIComponent(a.nome)}`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prefix: '', limit: 5, offset: 0 }),
  });
  resultado.buckets.push({ bucket: a.nome, publico: a.definer, status: r.status, itens_listados: Array.isArray(r.corpo) ? r.corpo.length : null });
}

writeFileSync(saidaPath, JSON.stringify(resultado, null, 2));

const leem = resultado.tabelas.filter((t) => Number(t.linhas_visiveis) > 0);
console.log(`Tabelas/views testadas: ${resultado.tabelas.length}; com linhas visíveis ao visitante: ${leem.length}`);
for (const t of leem) {
  const alerta = t.colunas_sensiveis?.length || t.padroes_encontrados?.length ? '  <-- REVISAR' : '';
  console.log(`- ${t.nome}: ${t.linhas_visiveis} linhas | colunas sensíveis: ${t.colunas_sensiveis?.join(', ') || '-'} | padrões: ${t.padroes_encontrados?.join(', ') || '-'}${alerta}`);
}
console.log(`\nFunções chamadas (estáveis, sem argumento): ${resultado.funcoes_chamadas.length}`);
for (const f of resultado.funcoes_chamadas.filter((f) => f.itens > 0)) {
  console.log(`- ${f.nome}${f.definer ? ' [SECURITY DEFINER]' : ''}: ${f.itens} itens | colunas sensíveis: ${f.colunas_sensiveis?.join(', ') || '-'} | padrões: ${f.padroes_encontrados?.join(', ') || '-'}`);
}
const naoChamadasDefiner = resultado.funcoes_nao_chamadas.filter((f) => f.definer).map((f) => f.nome);
console.log(`Funções NÃO chamadas (pedem argumento ou alteram dado): ${resultado.funcoes_nao_chamadas.length}`);
console.log(`  das quais SECURITY DEFINER (revisar à mão, furam a RLS): ${naoChamadasDefiner.join(', ') || '-'}`);
console.log('\nBuckets (listagem pelo visitante):');
for (const b of resultado.buckets) {
  const alerta = b.itens_listados > 0 ? '  <-- VISITANTE LISTA ARQUIVOS' : '';
  console.log(`- ${b.bucket}${b.publico ? ' (público)' : ''}: status ${b.status}, itens listados ${b.itens_listados}${alerta}`);
}
console.log('\nLembrete: tabela vazia devolve 0 mesmo aberta. Confira a policy (consultas.sql §2) antes de concluir "protegido".');
