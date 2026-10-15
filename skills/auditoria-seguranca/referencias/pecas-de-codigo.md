# Peças de código prontas (Edge Functions em Deno + front React)

Código que resolveu falhas reais. Copie para `supabase/functions/_shared/` (servidor) ou `src/lib/` (front),
ajuste os nomes e **escreva testes** para cada peça (são funções puras na maior parte: dá para testar com
vitest/jest sem subir nada). Numeração citada no `GUIA_COMPLETO.md`.

---

## §1. Autorização na Edge Function (`_shared/autorizacao.ts`)

**Problema que resolve:** `verify_jwt` não prova "logado" (a chave pública passa) e a função usa `service_role`,
que ignora a RLS. A checagem tem que estar no código, **antes** de ler o corpo e de criar o cliente de serviço.

```ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

export type Acesso = { ok: true; userId: string | null } | { ok: false; status: 401 | 403; erro: string };

// Cliente "como o chamador": usa a chave pública + o Authorization dele, então as RPCs respeitam as regras do banco.
async function clienteDoChamador(req: Request) {
  const auth = req.headers.get('Authorization');
  if (!auth) return null;
  const cliente = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user }, error } = await cliente.auth.getUser(); // a chave pública NÃO devolve usuário
  if (error || !user) return null;
  return { cliente, userId: user.id };
}

/** Logado, ativo e (opcional) com a permissão. Falha fechada: qualquer erro = negado. */
export async function exigirEquipeQuePode(req: Request, permissao?: string): Promise<Acesso> {
  const c = await clienteDoChamador(req);
  if (!c) return { ok: false, status: 401, erro: 'nao_autenticado' };
  const { data: ativo, error: e1 } = await c.cliente.rpc('is_equipe_ativa');
  if (e1 || ativo !== true) return { ok: false, status: 403, erro: 'sem_permissao' };
  if (permissao) {
    const { data: pode, error: e2 } = await c.cliente.rpc('user_has_permission', { p_permissao: permissao });
    if (e2 || pode !== true) return { ok: false, status: 403, erro: 'sem_permissao' };
  }
  return { ok: true, userId: c.userId };
}

export function iguaisSeguro(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

/** Para cron e gatilhos do banco: segredo no header, comparado em tempo constante. Sem segredo = recusa. */
export function exigirSegredoInterno(req: Request): Acesso {
  const esperado = Deno.env.get('INTERNAL_TRIGGER_SECRET') || '';
  const recebido = req.headers.get('x-internal-secret') || '';
  if (!esperado || !recebido || !iguaisSeguro(recebido, esperado)) return { ok: false, status: 401, erro: 'nao_autorizado' };
  return { ok: true, userId: null };
}

// Uso, logo no começo do handler:
// const acesso = await exigirEquipeQuePode(req, 'financeiro_editar');
// if (!acesso.ok) return new Response(JSON.stringify({ ok: false, erro: acesso.erro }), { status: acesso.status, headers });
// const servico = createClient(URL, SERVICE_ROLE_KEY);   // só DEPOIS de autorizar
```

**Regras:** id do usuário vem de `acesso.userId`, nunca do corpo. Funções que mexem em outro usuário (apagar,
bloquear, trocar senha) também conferem a **hierarquia** (§12).

---

## §2. Link assinado por finalidade (`_shared/link-assinado.ts`)

**Problema que resolve:** links públicos (comprovante, presente, atendimento) assinados com a mesma chave e o
mesmo formato: quem tinha um, tinha assinatura válida no outro.

```ts
export type Finalidade = 'comprovante' | 'presente' | 'atendimento';
const VARIAVEL: Record<Finalidade, string> = {
  comprovante: 'COMPROVANTE_LINK_SECRET', presente: 'PRESENTE_LINK_SECRET', atendimento: 'ATENDIMENTO_LINK_SECRET',
};

/** Chave dedicada; ausente = erro (sem cair para outra chave nem para a service role). */
export function segredoDoLink(f: Finalidade): string {
  const s = Deno.env.get(VARIAVEL[f]);
  if (!s) throw new Error(`Segredo ${VARIAVEL[f]} não configurado`);
  return s;
}

async function hmacHex(segredo: string, msg: string) {
  const k = await crypto.subtle.importKey('raw', new TextEncoder().encode(segredo), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const s = await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(msg));
  return Array.from(new Uint8Array(s)).map((b) => b.toString(16).padStart(2, '0')).join('');
}

export async function assinarLink(f: Finalidade, id: string): Promise<string> {
  return (await hmacHex(segredoDoLink(f), `${f}:v1:${id}`)).slice(0, 32);   // rótulo + versão; 128 bits
}

export async function conferirLink(f: Finalidade, id: string, token: unknown): Promise<boolean> {
  if (typeof token !== 'string' || token.length !== 32 || !id) return false;
  return iguaisSeguro(token, await assinarLink(f, id));
}
// Link com dois campos (ex.: contato + telefone): assine os dois juntos: assinarLink('atendimento', `${contato}:${telefone}`)
```

**Lembre:** link assinado **identifica**; ação de operador exige login de equipe (GUIA, B5).

---

## §3. CORS por lista (`_shared/cors.ts`)

```ts
function origem(u: string) { try { return new URL(u).origin; } catch { return null; } }
const LOCALHOST = ['http://localhost:5173', 'http://localhost:3000'];
const DOMINIOS = [
  ...(Deno.env.get('ALLOWED_ORIGINS') || '').split(',').map((d) => d.trim()).filter((d) => d && d !== '*'),
  Deno.env.get('SITE_URL') || '',
].map(origem).filter((o): o is string => !!o);

export function getCorsHeaders(req?: Request): Record<string, string> {
  const o = req?.headers.get('origin') || '';
  const permitido = [...DOMINIOS, ...LOCALHOST].includes(o);
  return {
    'Access-Control-Allow-Origin': permitido ? o : (DOMINIOS[0] ?? LOCALHOST[0]),   // desconhecido: o navegador bloqueia
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  };
}
```

**Ordem:** grave `ALLOWED_ORIGINS` e `SITE_URL` **antes** de publicar as funções. Webhooks (chamados por
servidor) não precisam de CORS. Links que o servidor gera usam `SITE_URL`, nunca o `origin` do corpo.

---

## §4. IP real, hash e limite de tentativas (`_shared/seguranca.ts`)

```ts
/** cf-connecting-ip (a plataforma sobrescreve) → x-real-ip → ÚLTIMO item do x-forwarded-for. Nunca o primeiro. */
export function extrairIp(req: Request): string {
  const cf = req.headers.get('cf-connecting-ip')?.trim(); if (cf) return cf;
  const real = req.headers.get('x-real-ip')?.trim(); if (real) return real;
  const xff = req.headers.get('x-forwarded-for');
  if (xff) { const itens = xff.split(',').map((i) => i.trim()).filter(Boolean); if (itens.length) return itens[itens.length - 1]; }
  return 'desconhecido';
}

/** IP e CPF guardados como HMAC com rótulo (hash puro de CPF/IP se quebra por força bruta). */
export async function hashChave(valor: string, rotulo: string): Promise<string> {
  return hmacHex(Deno.env.get('RATE_LIMIT_SECRET')!, `${rotulo}:${valor}`);
}
```

No banco, um contador **atômico** (uma RPC só do servidor):

```sql
create table if not exists public.tentativas (
  escopo text, chave text, falhas int not null default 0,
  janela_inicio timestamptz not null default now(), bloqueado_ate timestamptz,
  primary key (escopo, chave));
alter table public.tentativas enable row level security;   -- sem policy
revoke all on public.tentativas from public, anon, authenticated;

create or replace function public.registrar_tentativa(p_escopo text, p_chave text, p_max int,
  p_janela interval default '15 minutes', p_bloqueio interval default '30 minutes')
returns table(permitido boolean, bloqueado_ate timestamptz)
language plpgsql security definer set search_path = public, pg_temp as $$
declare r public.tentativas;
begin
  insert into public.tentativas as t (escopo, chave, falhas) values (p_escopo, p_chave, 1)
  on conflict (escopo, chave) do update set
    falhas = case when t.janela_inicio < now() - p_janela then 1 else t.falhas + 1 end,
    janela_inicio = case when t.janela_inicio < now() - p_janela then now() else t.janela_inicio end
  returning * into r;
  if r.bloqueado_ate is not null and r.bloqueado_ate > now() then return query select false, r.bloqueado_ate; return; end if;
  if r.falhas > p_max then
    update public.tentativas set bloqueado_ate = now() + p_bloqueio where escopo = p_escopo and chave = p_chave;
    return query select false, now() + p_bloqueio; return;
  end if;
  return query select true, null::timestamptz;
end $$;
revoke all on function public.registrar_tentativa(text, text, int, interval, interval) from public, anon, authenticated;
grant execute on function public.registrar_tentativa(text, text, int, interval, interval) to service_role;
```

**Regras:**
- Limite em camadas: por sessão, por identidade (CPF/e-mail) e por IP. Curto (rajada) e longo (24 h).
- Os números ficam num arquivo central.
- Sucesso zera o contador.
- Login e prova de identidade **falham fechado** (se o contador falhar, responda 503).
- Não bloqueie por recurso compartilhado (ex.: a senha de um evento usada por vários), ou alguém trava todos de propósito.

---

## §5. HTML seguro (documentos, e-mails, impressão)

```ts
export function escaparHtml(v: unknown): string {
  return String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/** Preenche {{variaveis}} numa passada só; valor é TEXTO (escapado), exceto blocos montados pelo próprio código. */
export function preencherModelo(modelo: string, valores: Record<string, string>, chavesHtml: readonly string[] = []) {
  const html = new Set(chavesHtml);
  return modelo.replace(/\{\{[^{}]+\}\}/g, (chave) => {
    if (!Object.prototype.hasOwnProperty.call(valores, chave)) return chave;
    const v = valores[chave];
    return html.has(chave) ? String(v ?? '') : escaparHtml(v);   // troca por FUNÇÃO: "$&" e "$1" ficam literais
  });
}
```

**Exibir HTML gerado** (contrato, recibo) sem dar acesso à sessão do painel:

```ts
// iframe com srcdoc e sandbox SEM allow-same-origin: o documento roda numa origem "opaca"
const f = document.createElement('iframe');
f.setAttribute('sandbox', 'allow-popups allow-modals');    // sandbox ANTES do srcdoc
f.setAttribute('referrerpolicy', 'no-referrer');
f.srcdoc = htmlDoDocumento;
container.appendChild(f);
```

**Sanitizar HTML de modelo editável:** no navegador, use DOMPurify com lista de tags e atributos permitidos
(e um filtro extra para `style`, que o DOMPurify não limpa). No servidor (Deno, sem DOM), use um tokenizador
que **reconstrói** a saída só com o permitido, nunca uma sequência de regex de "tirar o ruim". Teste com
`<img src=x/onerror=alert(1)>`, `<scr<script>ipt>`, `javascript&colon;`, `<!-->`, `style="background:url(javascript:...)"`.

---

## §6. Links e prévias seguros no front (`src/lib/linkSeguro.ts`)

```ts
const PROTOCOLOS_LINK = new Set(['https:', 'http:', 'mailto:', 'tel:']);

/** Para <a href> com valor vindo do banco. Fora da lista: undefined (o link some). */
export function hrefSeguro(url: string | null | undefined): string | undefined {
  if (!url) return undefined;
  const limpo = url.trim();
  try { return PROTOCOLOS_LINK.has(new URL(limpo).protocol) ? limpo : undefined; } catch { return undefined; }
}

/** Para <img>/<iframe> de prévia: só https e blob (arquivo escolhido na tela). */
export function linkSeguroParaPrevia(url: string | null | undefined): string | null {
  if (!url) return null;
  try { const p = new URL(url.trim()).protocol; return p === 'https:' || p === 'blob:' ? url.trim() : null; } catch { return null; }
}
```

Use o **parser de URL** (ele normaliza `java\tscript:` e maiúsculas), não regex. Complete com um `CHECK` no
banco (padroes-correcao.sql §9) e com `referrerPolicy="no-referrer"` em `<img>`/`<iframe>`.

**Log sem segredo:** grave `location.origin + location.pathname`, nunca `location.href` (leva `?token=`).

---

## §7. Storage privado e caminho de arquivo (`_shared/arquivo-privado.ts`)

```ts
const BUCKETS_ASSINAVEIS = ['fotos-clientes', 'comprovantes', 'ingressos'];   // lista FECHADA

/** O banco guarda "privado:<bucket>/<caminho>", nunca uma URL. */
export function lerReferencia(valor: string): { bucket: string; caminho: string } | null {
  const m = /^privado:([a-z0-9-]+)\/(.+)$/.exec(valor ?? '');
  return m ? { bucket: m[1], caminho: m[2] } : null;
}

/** Recusa: bucket fora da lista, caminho absoluto, "..", "." e o que muda ao decodificar (%2e%2e = ..). */
export function caminhoAssinavel(ref: { bucket: string; caminho: string }): boolean {
  if (!BUCKETS_ASSINAVEIS.includes(ref.bucket)) return false;
  if (!ref.caminho || ref.caminho.startsWith('/')) return false;
  let dec: string; try { dec = decodeURIComponent(ref.caminho); } catch { return false; }
  if (dec.includes('\\') || dec.startsWith('/')) return false;
  const ruim = (c: string) => c.split('/').some((p) => p === '' || p === '.' || p === '..');
  return !ruim(ref.caminho) && !ruim(dec);
}

/** Caminho enviado pelo usuário: formato FECHADO (<uid>/<uuid>.<ext>). */
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
export const FORMATO_ENVIO = new RegExp(`^${UUID}\\/${UUID}\\.[a-z0-9]{2,5}$`);
```

**Regras:**
- Para arquivo enviado pelo usuário, **assine com o cliente do chamador** (Authorization dele), não com a `service_role`, e tenha policy "só a própria pasta". Assim, mesmo que a validação falhe, o banco segura.
- Teste com `UID/%2e%2e/x`, `UID/.%2e/x`, `UID/%2E./x`, `UID/%2e%2e%2fx`, `UID/a/b`.
- Link temporário: 1 h no painel, 2 h para o cliente. Gere no servidor só para o arquivo **daquela pessoa**.

---

## §8. Webhook de pagamento (exemplo: Mercado Pago)

```ts
type Resultado = 'ok' | 'invalida' | 'sem_segredo';

export async function conferirAssinatura(segredo: string | undefined, xSignature: string | null,
                                         xRequestId: string | null, dataId: string): Promise<Resultado> {
  if (!segredo) return 'sem_segredo';                       // responda 503: o provedor reenvia depois
  if (!xSignature || !xRequestId) return 'invalida';         // header ausente NÃO pula a checagem
  const p = Object.fromEntries(xSignature.split(',').map((x) => { const [k, ...r] = x.trim().split('='); return [k, r.join('=')]; }));
  if (!p['ts'] || !p['v1']) return 'invalida';
  const manifesto = `id:${dataId};request-id:${xRequestId};ts:${p['ts']};`;
  const esperado = await hmacHex(segredo, manifesto);
  return iguaisSeguro(esperado, p['v1'].toLowerCase()) ? 'ok' : 'invalida';
}

export const idPagamentoValido = (id: unknown) => typeof id === 'string' && /^\d{1,20}$/.test(id);   // antes de montar URL
```

**Depois da assinatura:**
1. Reconsulte o pagamento na API do provedor (não confie no corpo).
2. Confira se o valor bate com o total congelado no pedido.
3. Aplique com idempotência (já pago = ignora).
4. **Nunca** mova um pedido pago para trás.

**Provedor sem assinatura** (alguns de WhatsApp): chave longa por instância no endereço do webhook
(`?chave=<64 hex>&instancia=<id>`), gerada pelo banco, comparada em tempo constante; sem chave = 401 sem processar.

---

## §9. Código curto aleatório sem viés

```ts
const ALFABETO = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';   // sem 0/O/1/I/L

export function gerarCodigo(tamanho = 6): string {
  const n = ALFABETO.length, limite = 256 - (256 % n);
  let codigo = '';
  while (codigo.length < tamanho) {
    for (const b of crypto.getRandomValues(new Uint8Array(tamanho * 2))) {
      if (b >= limite) continue;   // descarta para não ter viés
      codigo += ALFABETO[b % n];
      if (codigo.length === tamanho) break;
    }
  }
  return codigo;
}
```

Código curto só é aceitável se houver **outra** prova de quem usa (ex.: só vale vindo do número do operador). Token de link: 128 a 256 bits.

---

## §10. Respostas e erros de página pública

```ts
export const ERRO_IDENTIFICACAO = 'Não foi possível validar os dados informados.';   // a MESMA para qualquer falha
export const ehUuid = (v: unknown) => typeof v === 'string' && /^[0-9a-f-]{36}$/i.test(v);
export function erroInterno(contexto: string, e: unknown) {
  console.error(contexto, e instanceof Error ? e.message : e);   // detalhe só no log, sem dado pessoal
  return new Response(JSON.stringify({ ok: false, erro: 'erro_interno' }), { status: 500 });
}
```

**Regras:**
- **Anti-timing:** quando o usuário não existe, rode o bcrypt contra um "hash isca" para o tempo de resposta ser igual.
- Link vencido responde 410, mas só **depois** de o token conferir (para não virar oráculo de existência).

---

## §11. Validade depois do evento

```ts
export const DIAS_DE_VALIDADE_APOS_EVENTO = 2;   // ponto único de ajuste
export function acessoVencido(ultimaData: string | null, hoje: Date = new Date()): boolean {
  if (!ultimaData) return false;
  const fim = new Date(ultimaData); fim.setDate(fim.getDate() + DIAS_DE_VALIDADE_APOS_EVENTO);
  return hoje > fim;
}
```

---

## §12. Hierarquia de usuários (funções com `service_role` repetem as regras do banco)

```ts
type P = { role: 'desenvolvedor' | 'dono' | 'admin' | 'funcionario'; ativo: boolean };
export function podeMexerNoUsuario(chamador: P, idChamador: string, alvo: P, idAlvo: string): boolean {
  if (!chamador.ativo) return false;
  if (idChamador === idAlvo) return false;                    // ninguém apaga/bloqueia a si mesmo
  if (alvo.role === 'desenvolvedor') return false;             // ninguém mexe no desenvolvedor
  if (alvo.role === 'dono') return chamador.role === 'dono' || chamador.role === 'desenvolvedor';
  return ['desenvolvedor', 'dono', 'admin'].includes(chamador.role);
}
```

---

## §13. Teste de regressão que trava o "jeito antigo"

Um teste que **falha** se o padrão inseguro voltar ao código. Exemplos:
- falha se aparecer chamada direta à API de WhatsApp fora da função de servidor;
- falha se `Access-Control-Allow-Origin: *` aparecer em `supabase/functions`;
- falha se `Math.random` aparecer em gerador de token.

```ts
import { readFileSync } from 'node:fs';
import { globSync } from 'glob';
it('nenhuma função usa CORS *', () => {
  for (const f of globSync('supabase/functions/**/*.ts')) {
    expect(readFileSync(f, 'utf8')).not.toMatch(/Allow-Origin['"]?\s*:\s*['"]\*/);
  }
});
```
