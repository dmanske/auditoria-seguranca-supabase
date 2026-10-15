# Guia completo de auditoria de segurança: Supabase + front na Vercel

Este guia junta tudo o que aprendemos auditando e endurecendo um sistema real (painel administrativo,
páginas públicas para clientes, pagamentos, WhatsApp, contratos, arquivos privados). Ele foi escrito para
**três tipos de leitor**:

- **Quem não é técnico:** cada falha começa com "Em palavras simples". Dá para entender o risco e decidir.
- **Quem programa:** cada falha tem "Como achar", "Como corrigir" (com código), "Como confirmar" e "Armadilha".
- **Uma IA (Claude, Cursor, Kiro, ChatGPT…):** o roteiro da Parte 3 é o passo a passo que ela deve seguir.

> Use este material **só em projetos seus ou que você tem autorização para testar.**

## Sumário

1. [Conceitos em 10 minutos (glossário)](#parte-1--conceitos-em-10-minutos)
2. [As 20 regras de ouro](#parte-2--as-20-regras-de-ouro)
3. [Roteiro da auditoria, passo a passo](#parte-3--roteiro-da-auditoria-passo-a-passo)
4. [Catálogo de falhas (o que procurar e como corrigir)](#parte-4--catálogo-de-falhas)
5. [Como corrigir sem quebrar: publicação segura](#parte-5--como-corrigir-sem-quebrar-publicação-segura)
6. [Padrões de desenho aprovados](#parte-6--padrões-de-desenho-aprovados)
7. [Incidentes reais e lições](#parte-7--incidentes-reais-e-lições)
8. [Checklist final](#parte-8--checklist-final)

Arquivos de apoio (mesma pasta): `referencias/consultas.sql`, `referencias/padroes-correcao.sql`,
`referencias/pecas-de-codigo.md`, `referencias/ferramentas.md`, `scripts/`.

---

## Parte 1 — Conceitos em 10 minutos

Se você entender estes termos, entende 90% das falhas deste guia.

| Termo | Em palavras simples |
|---|---|
| **Supabase** | O "servidor pronto": banco de dados Postgres + login + arquivos + funções. O site conversa direto com ele. |
| **Chave pública (anon key)** | A chave que vai dentro do site. **Qualquer pessoa consegue copiar.** Ela não é segredo, e toda a segurança tem que funcionar mesmo com ela nas mãos de um estranho. |
| **Visitante (`anon`)** | Quem usa o site sem login. No banco, é o papel `anon`. |
| **Logado (`authenticated`)** | Quem fez login. **Atenção:** "logado" inclui funcionário bloqueado, funcionário sem permissão e, se o cadastro estiver aberto, qualquer pessoa da internet que criou conta. |
| **Chave de serviço (`service_role`)** | A chave-mestra. Passa por cima de todas as regras. **Nunca** pode ir para o navegador; só o servidor usa. |
| **RLS (Row Level Security)** | As regras de "quem vê qual linha" de cada tabela. Sem RLS, a tabela fica aberta para quem tiver a chave pública. |
| **Policy** | Uma regra da RLS. Ex.: "o cliente só vê os próprios pedidos". Uma policy `USING (true)` significa "todo mundo vê tudo". |
| **GRANT / REVOKE** | A permissão de **usar** a tabela ou a função (antes mesmo da RLS). O Supabase, por padrão, dá permissão demais. |
| **Função do banco (RPC)** | Um "procedimento" que o site chama: `supabase.rpc('nome')`. |
| **`SECURITY DEFINER`** | Função que roda com o poder de quem a criou (o dono do banco), **pulando a RLS**. Útil e perigosa: se o visitante puder chamá-la, ela faz por ele o que a RLS proibiria. |
| **View** | Uma "tabela virtual" feita de uma consulta. Por padrão **ignora a RLS** das tabelas de base. |
| **Edge Function** | Código que roda no servidor do Supabase (Deno). É onde vão as regras que não podem ficar no navegador. |
| **`verify_jwt`** | Configuração da Edge Function. `true` **não** significa "só logado": a chave pública também é um JWT válido e passa. |
| **Bucket** | Uma pasta de arquivos no Storage. Pública = qualquer um com o link abre. |
| **Link assinado (signed URL)** | Link temporário para um arquivo privado. Vence sozinho. |
| **Token** | Um código secreto num link (`?token=...`). Só é seguro se for longo, aleatório, individual, com validade e revogável. |
| **HMAC** | Uma "assinatura" de um texto com uma chave secreta. Serve para provar que um link foi gerado pelo servidor. |
| **CORS** | A lista de sites que podem chamar suas funções pelo navegador. `*` = qualquer site. |
| **XSS** | Quando um texto gravado por alguém vira código que roda no navegador de outra pessoa (e rouba o login dela). |
| **IDOR** | Trocar um id na requisição e ver/alterar o que é de outra pessoa. |
| **Enumeração** | Descobrir se algo existe pela diferença das respostas ("CPF não existe" × "senha errada"). |
| **Limite de tentativas (rate limit)** | Barreira contra quem tenta adivinhar códigos e senhas por força bruta. |
| **Falha fechada** | Quando algo dá errado (segredo faltando, consulta falhou), o sistema **recusa**. O contrário, falha aberta, libera. |
| **Migration** | Arquivo SQL versionado que muda o banco. Tudo que muda o banco deve virar migration no git. |
| **Transação desfeita** | `begin; ...; rollback;`: roda tudo e desfaz no fim. Serve para testar sem gravar nada. |
| **42501** | O código de erro "permissão negada" do Postgres. É a prova de que algo está **protegido** (e não só vazio). |

---

## Parte 2 — As 20 regras de ouro

Cada regra nasceu de um problema real (ver Parte 7).

1. **A chave pública é pública.** Pense sempre: "um estranho com a chave do site consegue fazer isto?".
2. **Teste com o papel errado, não com o seu.** Visitante, funcionário sem permissão, bloqueado. O dono vê tudo e esconde os furos.
3. **`[]` não prova nada.** Uma tabela vazia devolve `[]` mesmo aberta. A prova de proteção é o erro 42501/401/403, ou a policy lida no catálogo.
4. **O banco ao vivo é a verdade.** Dumps, migrations antigas e documentação mentem quando alguém mexeu "por fora".
5. **Toda mudança de banco vira migration no git, no mesmo dia.** Correção feita direto no painel some na próxima cópia do banco.
6. **`REVOKE FROM PUBLIC` não basta no Supabase.** Revogue também de `anon` e `authenticated`, e ajuste os privilégios padrão.
7. **`verify_jwt = true` não é "logado".** A autorização real fica no código da função.
8. **Função com `service_role` ignora a RLS.** Autorize quem chama ANTES de ler qualquer dado.
9. **Nunca confie no corpo da requisição para decidir poder** (`automatico: true`, `role`, `user_id`, preço).
10. **Link compartilhado por várias pessoas não é segredo.** Token na URL vai para histórico, prints, logs. Proteja com escopo individual, validade, revogação e prova de identidade.
11. **UUID não é controle de acesso.** Se o id aparece em alguma outra resposta, ele não protege nada.
12. **Dado autodeclarado não prova identidade.** CPF digitado numa conta, nome, telefone: qualquer um digita o de outra pessoa.
13. **Segredo apagado do código continua no histórico do git.** Troque o segredo.
14. **Segredo sem valor de reserva.** `env('X') || 'padrao'` é uma porta dos fundos. Sem o segredo, a função recusa.
15. **Antes de fechar, procure quem usa.** Restringir uma função usada dentro de uma policy derruba telas inteiras.
16. **Ordem de publicação importa.** Caminho novo → telas → publicar → fechar o antigo. Banco antes das funções que dependem dele.
17. **Base de erros é zero.** Se a Vercel roda `tsc` no build, 1 erro de tipo deixa o site parado (já ficou 11 dias).
18. **Nunca teste envio em massa contra produção.** Um teste já disparou 17 WhatsApps reais.
19. **Nunca `supabase config push` como simulação.** Ele aplica tudo sem perguntar.
20. **Registre o que NÃO foi testado.** "Corrigido" sem "como foi testado" e "o que falta testar" é promessa.

---

## Parte 3 — Roteiro da auditoria, passo a passo

Cada fase diz **o que fazer**, **o comando** e **o que esperar**. Uma IA deve seguir na ordem e parar no fim
de cada fase para resumir.

### 3.0 Preparar

1. **Acesso só de leitura ao banco.** Instale o CLI do Supabase e ligue ao projeto:
   ```bash
   supabase login
   supabase link --project-ref <PROJECT_REF>     # o ref está na URL do painel
   supabase migration list --linked              # local × remoto
   ```
   Para rodar SQL sem Docker: `supabase db query --linked "select 1"`. Se o MCP do Supabase disser
   "You do not have permission", use esse comando.
2. **Saber qual banco o site usa:** `.env` (`VITE_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_URL`). Não imprima o `.env`
   inteiro; extraia só a variável: `grep '^VITE_SUPABASE_URL=' .env`.
3. **Histórico de migrations alinhado?** `supabase db push --linked --dry-run`. Se ele quiser reaplicar dezenas
   de migrations antigas, o histórico está desalinhado: **pare** e alinhe com
   `supabase migration repair --linked --status applied <versão>` (uma por uma), sem aplicar nada.
4. **Perguntar ao dono:** o que é público de propósito (páginas sem login, links enviados por WhatsApp/e-mail),
   se há dados reais no banco, se há webhooks de pagamento, quem são os perfis (dono, admin, funcionário…).

### 3.1 Inventário

Monte uma lista (vai virar o mapa da auditoria):
- tabelas e views (`referencias/consultas.sql`, seção 1);
- funções do banco e quem pode executá-las (seção 3);
- buckets (seção 6);
- edge functions: `ls supabase/functions`, e o `verify_jwt` de cada uma em `supabase/config.toml`;
- rotas públicas do front (procure no roteador as rotas sem login, ex.: `/contrato/:token`);
- webhooks (funções chamadas por terceiros: pagamento, WhatsApp);
- crons: `select jobname, schedule, command from cron.job;`
- segredos usados: `grep -rn "Deno.env.get" supabase/functions` e `grep -rn "import.meta.env\|process.env" src`.

### 3.2 Banco (catálogo)

Rode as seções de `referencias/consultas.sql`. O que cada uma revela:

| Consulta | Procura | Achado típico |
|---|---|---|
| Tabelas sem RLS | tabela aberta | tabela nova esquecida |
| Policies abertas para `anon`/`public` | `USING (true)`, `IS NOT NULL` | vazamento de clientes |
| Policies que só olham "tem login" | `auth.role()='authenticated'`, `auth.uid() is not null` | qualquer logado (até bloqueado) faz tudo |
| Grants de tabela por papel | `anon` com `INSERT/UPDATE/DELETE/TRUNCATE` | escrita anônima |
| Funções `SECURITY DEFINER` executáveis por `anon`/`authenticated` | funções sem trava interna | segredo lido, SQL livre, saldo alterado |
| Funções sem `search_path` | `proconfig is null` | sequestro de função |
| Views sem `security_invoker` | view que fura a RLS | relatório financeiro aberto |
| Buckets públicos e policies do storage | `public = true`, `anon` gravando | fotos de cliente abertas |
| Crons com chave escrita | `Bearer eyJ...` no comando | chave de serviço no banco |

Depois rode o scanner oficial: `supabase db advisors --linked --type security` (ou painel → Advisors).

### 3.3 Teste do visitante (empírico)

O catálogo diz o que **deveria** acontecer; este teste prova o que **acontece**. Use `scripts/teste-visitante.mjs`:

```bash
# 1) gerar a lista de alvos (tabelas, views, funções e buckets que o visitante alcança)
supabase db query --linked -f skills/auditoria-seguranca/scripts/alvos-visitante.sql > /tmp/alvos.json
# 2) testar só com a chave pública (lê do .env; nunca imprime valores)
node skills/auditoria-seguranca/scripts/teste-visitante.mjs .env /tmp/alvos.json /tmp/resultado.json
```

O script tenta ler cada tabela/view, chama as funções estáveis sem argumento (o servidor recusa `GET` em
função que altera dado) e tenta listar cada bucket. Ele aponta colunas pessoais (cpf, telefone, email,
nascimento, senha, token…) e padrões de CPF/e-mail/telefone, **sem mostrar os valores**.

**Leitura do resultado:**
- "N linhas visíveis" numa tabela de cliente = **vazamento**.
- Tabela vazia (0) não prova proteção: confira a policy (regra 3).
- Funções "não chamadas" (pedem argumento) precisam de revisão manual (Parte 4, C1).

### 3.4 Teste por perfil (em transação desfeita)

Para cada perfil, simule no banco e **desfaça**:

```sql
begin;
  set local role authenticated;
  select set_config('request.jwt.claims', json_build_object('sub','<uuid-do-usuario-de-teste>','role','authenticated')::text, true);
  -- leitura
  select count(*) from public.clientes;
  -- escrita (deve falhar com 42501 para quem não pode)
  update public.configuracoes set valor = 'x' where chave = 'chave_pix';
rollback;
```

Perfis: **visitante** (`set local role anon`), **funcionário sem a permissão**, **funcionário com a permissão**,
**bloqueado** (`ativo = false`), **dono**, **servidor** (`service_role`). Monte a tabela "quem × ação × antes × depois".

**Não esqueça a escrita cruzada:** chame a função com o **seu** id no parâmetro principal e o id de **outra**
pessoa num parâmetro secundário (ex.: `cancelar_pedido(meu_cliente_id, pedido_de_outro)`). Muitos furos
estão aí, não na leitura.

Para testar pela API como funcionário: crie um usuário de teste pela Admin API, com papel limitado, e apague no fim.

### 3.5 Edge functions

Para cada função, responda: **quem pode chamar e o que acontece se um estranho chamar?**

Teste rápido sem disparar nada: chame sem login e com corpo vazio.
- `401/403` = travada.
- `400 "campo obrigatório"` = **aceitou a chamada**, só faltou o dado (provavelmente aberta).
- Lembre que a chave pública passa o `verify_jwt`.

Procure no código (Parte 4, grupo B):
- não chama `auth.getUser()` nem confere papel/permissão;
- decide pelo corpo (`if (body.automatico)`, `body.user_id`, `body.role`);
- cria o cliente `service_role` antes de autorizar;
- recebe id de outro usuário sem conferir hierarquia (admin apagando o dono);
- segredo com reserva (`|| 'default'`);
- `Access-Control-Allow-Origin: *`;
- IP do **primeiro** item de `x-forwarded-for`;
- limite de tentativas que libera quando o banco falha;
- caminho de arquivo vindo do cliente e assinado com `service_role`;
- webhook sem assinatura, ou assinatura opcional;
- mensagem de erro com `e.message` cru.

Rode `scripts/deno-check-todas.sh`: erro de tipo às vezes esconde bug real.

### 3.6 Páginas públicas e links com token

Para cada rota pública, preencha:

| Pergunta | Bom | Ruim |
|---|---|---|
| Como o token é gerado? | `gen_random_bytes(16+)`, `crypto.getRandomValues` | `Math.random`, sequencial, derivado de CPF |
| Quantos bits? | ≥ 128 | < 64 |
| Um por pessoa ou um para todos? | por pessoa (ou link geral + prova de identidade) | um link para a empresa inteira |
| Vence? | sim (ex.: 2 dias depois do evento) | nunca |
| Dá para revogar? | sim | não |
| Limite de tentativas? | por IP e por identidade, com bloqueio longo | nenhum, ou zera a cada 15 min |
| Respostas iguais para "não existe" e "errado"? | sim | não (permite enumerar) |
| O que a API entrega × o que a tela mostra? | só o que a tela mostra | CPF inteiro, dados de terceiros, ids internos |
| Indexação | `X-Robots-Tag: noindex` | sem |
| Token vaza? | `Referrer-Policy`, sem token em log | log grava a URL inteira |

Confirme ao vivo **só com tokens falsos** (`scripts/conferir-endpoints.mjs`). Abra a página com F12 → Rede e
veja o JSON que chega: é o melhor jeito de ver "o que vai a mais".

### 3.7 Front

```bash
grep -rn "dangerouslySetInnerHTML\|document.write\|innerHTML" src
grep -rnE "(href|src)=\{" src            # valores vindos do banco?
grep -rn "service_role\|SERVICE_ROLE" src .env* 2>/dev/null   # nunca com VITE_/NEXT_PUBLIC_
npm audit --omit=dev                      # o que roda em produção primeiro
```

Confira `vercel.json` (ou equivalente): CSP, HSTS, `X-Frame-Options`, `X-Content-Type-Options`,
`Referrer-Policy`, `Permissions-Policy`. Teste em https://securityheaders.com.

### 3.8 Segredos e histórico do git

`scripts/procurar-segredos.sh` procura chaves no código e no **histórico inteiro**. O que já esteve no git
precisa ser trocado no painel do serviço (Supabase, gateway de pagamento, WhatsApp, e-mail…). Confira também:
`select jobname, command from cron.job where command like '%Bearer%';`

### 3.9 Varredura independente (opcional)

Uma segunda opinião acha o que a primeira deixou passar (no nosso caso, um path traversal sério foi achado
assim antes de ir ao ar). Com Claude Code + plugin Claude Security: `/claude-security:claude-security` →
Scan codebase → escopo `supabase/` → esforço `medium`. Sem Claude: Semgrep, ou outra IA com o prompt de
`prompts/outras-ias.md`. Ver `referencias/ferramentas.md`.

### 3.10 Relatório e plano

Para cada achado: **título**, **severidade** (crítico/alto/médio/baixo), **evidência**, **impacto em
linguagem simples**, **correção proposta**, **risco da correção** (o que pode quebrar), **ordem**. Depois, o
plano em fases, começando pelo que é mais grave e mais fácil:

1. **Fase 0 (horas):** fechar funções perigosas para `anon`/`authenticated`, desligar cadastro aberto, trocar segredos expostos.
2. **Fase 1:** policies abertas, grants de escrita anônima, buckets.
3. **Fase 2:** edge functions sem autorização, webhooks.
4. **Fase 3:** páginas públicas e links.
5. **Fase 4:** permissões finas por funcionário, bloqueio imediato.
6. **Fase 5:** endurecimento (search_path, CSP, dependências, noindex).

---

## Parte 4 — Catálogo de falhas

Formato de cada item: **Em palavras simples** → **Como achar** → **Como corrigir** → **Como confirmar** →
**Armadilha**. O código completo está em `referencias/padroes-correcao.sql` e `referencias/pecas-de-codigo.md`.

### Grupo A — Banco de dados

#### A1. Tabela sem RLS
- **Em palavras simples:** a tabela não tem porteiro; quem tem a chave pública lê e escreve.
- **Como achar:** consultas.sql §1.
- **Como corrigir:** `alter table public.x enable row level security;` + policies explícitas. Tabela usada só pelo
  servidor: RLS ligada **sem** policy (tudo negado para a API; o servidor passa).
- **Como confirmar:** visitante recebe 42501 ou `[]` **com** dado na tabela.
- **Armadilha:** o aviso "RLS enabled no policy" é seguro (significa "fechada"); às vezes revela tabelas de backup esquecidas.

#### A2. Policy aberta (`USING (true)`) para visitante
- **Em palavras simples:** a porta tem porteiro, mas a regra dele é "deixa todo mundo entrar".
- **Como achar:** consultas.sql §2 (policies `anon`/`public` sem nenhuma condição de login, header ou permissão).
- **Como corrigir:** trocar `TO public` por `TO authenticated` + condição real; o que for público de propósito
  vira lista explícita de colunas (A7) ou função que devolve só o necessário.
- **Caso real:** uma policy `anon_select_after_insert ... using (true)` deixava qualquer um ler 3.300 clientes (CPF, telefone, e-mail).

#### A3. Policy "disfarçada" (`IS NOT NULL`)
- **Em palavras simples:** parece que confere o código do link, mas só confere que *existe* um código, não que é o **seu**.
- **Como achar:** policies com `token IS NOT NULL`, `access_token IS NOT NULL`.
- **Como corrigir:** comparar com o header: `token = nullif(current_setting('request.headers', true)::json ->> 'x-access-token', '')`,
  ou (melhor) tirar o acesso direto e servir por edge function (Parte 6.1).

#### A4. Policy que só olha "tem login"
- **Em palavras simples:** "logado pode tudo", incluindo funcionário bloqueado, sem permissão ou um estranho que criou conta.
- **Como achar:** consultas.sql §2b (`auth.role()='authenticated'`, `auth.uid() is not null`, `true` para authenticated).
- **Como corrigir:** função `is_equipe_ativa()` (logado **e** ativo) para ler; `user_has_permission('<caixa>')` ou
  `pode_gravar_area('<area>')` para gravar. Use `(select fn())` na policy (avalia uma vez, não por linha).
- **Armadilha:** "app de uma empresa só, então tudo aberto para logado é intencional" estava **errado**: anulava as
  permissões por funcionário (que só existiam na tela), deixava funcionário trocar a chave PIX e se promover a dono.

#### A5. Grants de tabela totais para `anon` e `authenticated`
- **Em palavras simples:** o Supabase dá, por padrão, poder de ler, gravar, apagar e até **esvaziar** (`TRUNCATE`)
  toda tabela nova. A RLS vira a única barreira, e `TRUNCATE` nem passa pela RLS.
- **Como achar:** consultas.sql §4 (grants por papel) e §5 (privilégios padrão).
- **Como corrigir (em ondas):** 1) `revoke truncate, references, trigger ... from anon, authenticated` + privilégios
  padrão; 2) `revoke delete ... from anon`; 3) `revoke insert, update ... from anon` com grants mínimos por fluxo
  público (inventário de escrita anônima: fluxo → tabela → colunas); 4) `select` por último (maior risco).
- **Como confirmar:** 42501 `permission denied for table` (mais forte que `[]`).

#### A6. Escrita anônima perigosa
- **Em palavras simples:** um estranho consegue **gravar** coisas que o sistema depois executa.
- **Casos reais:** criar "mensagem agendada" que o robô enviava pelo WhatsApp da empresa (golpe em nome dela);
  trocar o destino de links curtos; criar carteira com saldo; inserir permissão de dono para um usuário novo.
- **Como achar:** policies INSERT/UPDATE/DELETE para `anon`/`public` com `with_check` nulo ou `true` (consultas.sql §2);
  ensaio em transação desfeita como visitante.
- **Como corrigir:** remover; quem grava é a equipe logada (com permissão) ou o servidor (sem policy).
- **Armadilha:** policies com nome "Sistema…"/"Webhook…" abertas para `anon` são peso morto: o servidor usa `service_role` e não precisa delas.

#### A7. Coluna sensível exposta junto com a linha
- **Em palavras simples:** a RLS decide **quais linhas**, não **quais colunas**. Se a linha é pública, todas as colunas vão.
- **Como corrigir:** grant por coluna:
  `revoke select on public.viagens from anon; grant select (id, nome, data, ...) on public.viagens to anon;`
  e no front nunca `select('*')` em tabela pública (lista de colunas num arquivo central).
- **Armadilha:** páginas antigas com `select('*')` quebram com 42501: publique o site **antes** da migration.

#### A8. View que fura a RLS
- **Em palavras simples:** a view roda com o poder do dono e mostra tudo, mesmo que as tabelas tenham regras.
- **Como achar:** consultas.sql §7 (views sem `security_invoker=true`) + teste do visitante.
- **Como corrigir:** `alter view public.v set (security_invoker = true);`. View materializada não aceita: tire o `select` de `anon`/`authenticated`.
- **Armadilha:** com `security_invoker`, telas do admin que dependiam do "furo" podem ficar vazias; confira como equipe.
  Para mostrar "nome e foto de terceiros", view não serve: use função `SECURITY DEFINER` que se autoriza.

#### A9. Função `SECURITY DEFINER` executável por quem não devia
- **Em palavras simples:** uma função com poder de dono que qualquer visitante (ou qualquer logado) pode chamar.
- **Casos reais:** função que devolvia o **segredo interno** do servidor (com ele, baixava-se o banco inteiro);
  função de **SQL livre** (`exec_readonly_query`); desligar gatilhos; agendar cron com texto livre; debitar a
  carteira de qualquer cliente; listar e-mails de todos os usuários.
- **Como achar:** consultas.sql §3 (executáveis por `anon`/`authenticated`) e §3b (sem nenhuma checagem de quem chama no corpo).
- **Como corrigir:**
  ```sql
  revoke all on function public.f(args) from public, anon, authenticated;   -- só servidor
  grant execute on function public.f(args) to service_role;
  ```
  Se a equipe precisa chamar: deixe `authenticated` e **coloque a trava dentro** (padroes-correcao.sql §2):
  `if auth.uid() is not null and not public.user_has_permission('x') then raise exception ... using errcode='42501';`
- **Armadilha 1:** no Supabase, `revoke ... from public` **não basta** (há grant direto para `anon`/`authenticated`).
- **Armadilha 2:** função usada **dentro de policy**: se o papel perder o `execute`, a policy inteira passa a dar erro
  (`permission denied for function`). Uma vitrine pública ficou vazia assim. Limite a policy de equipe a `TO authenticated`.
- **Armadilha 3:** segredo exposto precisa ser **trocado** depois do revoke.

#### A10. Função sem `search_path` fixo
- **Em palavras simples:** a função procura tabelas/funções "no caminho"; um atacante com permissão de criar objetos pode pôr uma armadilha com o mesmo nome.
- **Como corrigir:** `alter function public.f(args) set search_path = public, pg_temp;` (gere em lote pelo catálogo, consultas.sql §8).
- **Armadilha:** funções que usam extensões (`gen_random_bytes` do `pgcrypto`) param de achá-las (erro 42883). Use
  `extensions.gen_random_bytes(...)` ou inclua `extensions` no `search_path`.

#### A11. SQL dinâmico (injeção)
- **Como achar:** `select proname from pg_proc where prosrc ~* 'execute'`.
- **Como corrigir:** `format('... %I ...', nome)` para identificadores e `USING` para valores; nunca concatenar texto do usuário.
- **Nota:** o front que usa a API do Supabase já é parametrizado; o risco mora nas funções PL/pgSQL.

#### A12. Tabela de papéis editável
- **Em palavras simples:** se o funcionário consegue editar a tabela que diz "quem é admin", ele vira admin.
- **Como corrigir:** gravar em tabela de papéis/permissões só `is_admin_or_owner()`; admin não promove a dono nem mexe na linha do dono.
- **Armadilha:** `user_metadata` do Supabase Auth é editável pelo próprio usuário. Papel vai em tabela própria ou em `app_metadata`.

#### A13. Bloqueio que não é imediato
- **Em palavras simples:** você bloqueia o funcionário e ele continua usando até o login vencer.
- **Como corrigir:** toda função/policy que lê o papel confere `ativo`; ao bloquear, apague as sessões
  (`delete from auth.sessions where user_id = ...; delete from auth.refresh_tokens where user_id::uuid = ...`) por
  função só do servidor; o front desloga quem foi bloqueado ao voltar para a aba.
- **Como confirmar:** bloco `DO` que conta policies que leem o papel sem conferir `ativo` e falha se houver alguma.

#### A14. Gatilho de trava contornável
- **Caso real:** a trava de "parcela fixa" deixava passar se a parcela **antiga** estivesse paga. Ataque em 2 passos: marcar paga, depois desmarcar e editar.
- **Lição:** trava por gatilho deve olhar **o que muda** (valor, data, dono), não o estado de pagamento.

#### A15. Tabelas de backup e dados parados em produção
- **Como achar:** tabelas `backup_*`, `*_old`, `*_bkp`.
- **Como corrigir:** guardar cópia fora do banco e apagar por migration (com trava que aborta se houver dado inesperado).

#### A16. Restaurar backup como escalada
- **Em palavras simples:** se "restaurar backup" aceita um arquivo montado pelo usuário, ele restaura a tabela de permissões com ele mesmo como dono.
- **Como corrigir:** a restauração ignora tabelas de permissão/configuração, exceto para o desenvolvedor.

### Grupo B — Edge functions (servidor)

#### B1. Função sem checagem de quem chama
- **Em palavras simples:** um endereço na internet que faz coisas importantes para qualquer um.
- **Casos reais:** estornar pagamento só com o id do pedido; trocar o nome de qualquer usuário; gastar a chave de IA
  (custo); fazer o servidor chamar um endereço informado pelo usuário (SSRF); enviar WhatsApp para qualquer número
  pelo número da empresa; listar passageiros com telefone.
- **Como corrigir:** um arquivo comum de guardas, chamado **antes** de ler o corpo e de criar o cliente `service_role`
  (pecas-de-codigo.md §1): `exigirEquipe`, `exigirEquipeQuePode({permissao})`, `exigirDonoOuAdmin`,
  `exigirSegredoInterno` (cron/gatilho). Sem login → 401; logado sem permissão → 403.
- **Como confirmar:** chamar só com a chave pública → 401.

#### B2. "Interno" decidido pelo corpo
- **Caso real:** `if (body.automatico === true)` pulava a autenticação de uma função de backup: um POST anônimo devolvia
  um link para o banco inteiro.
- **Como corrigir:** caminho interno exige segredo no header (`x-internal-secret`), comparado em tempo constante.
  Melhor ainda: apagar o caminho se nada o usa.

#### B3. Crons disparáveis de fora
- **Como corrigir:** o cron chama a função mandando o segredo (lido do Vault por uma função do banco que só o
  servidor executa), e a função exige o segredo.
- **Ordem:** banco primeiro (o disparador já manda o segredo), funções depois. Ao contrário, os crons param com 401.

#### B4. Permissão sem olhar o alvo (hierarquia)
- **Caso real:** admin apagando o dono e o desenvolvedor; admin bloqueado ainda criando contas.
- **Como corrigir:** regras puras e testáveis por alvo (ninguém mexe no desenvolvedor; dono só por dono; ninguém apaga a si mesmo; todo chamador `ativo`).

#### B5. Link com token usado como chave-mestra
- **Caso real:** o link de um comprovante (enviado ao operador) abria uma busca em **toda** a base de clientes, com telefone e dívida.
- **Regra:** link com token **identifica**, não **autoriza** ação de operador. Ação de operador exige login de equipe com permissão.

#### B6. Função que gera link ou assina arquivo sem checar quem pede
- **Caso real:** a "prévia" de um link de presente devolvia o link assinado para quem tivesse a chave pública e o id.
- **Regra:** toda função que **assina**, **gera link** ou **assina URL de arquivo** checa o chamador.

#### B7. Segredo com valor de reserva
- **Como achar:** `grep -rnE "get\(['\"][A-Z_]+['\"]\)\s*(\|\||\?\?)" supabase/functions`.
- **Casos reais:** `JWT_SECRET || 'your-secret-key-change-in-production'` (forjar sessão de qualquer cliente); token da
  instância de WhatsApp caindo para o número global; chave de um link caindo para a de outro e depois para a `service_role`.
- **Como corrigir:** segredo obrigatório; ausente → recusa (503).

#### B8. Mesmo segredo para finalidades diferentes
- **Caso real:** link de presente e link de comprovante assinados com a mesma chave e o mesmo formato: quem tinha um, tinha assinatura válida no outro.
- **Como corrigir:** chave dedicada por finalidade + rótulo na mensagem (`'comprovante:v1:' + id`) + 128 bits + comparação em tempo constante (pecas-de-codigo.md §2).

#### B9. IP forjável no limite de tentativas
- **Em palavras simples:** o limite "por IP" usava um cabeçalho que o próprio atacante escreve; a cada tentativa ele "trocava de IP".
- **Como corrigir:** `cf-connecting-ip` → `x-real-ip` → **último** item de `x-forwarded-for`. Guarde o IP como HMAC, nunca puro (pecas-de-codigo.md §4).

#### B10. Limite que falha aberto
- **Em palavras simples:** se o banco do contador falha, o limite some.
- **Como corrigir:** em login e prova de identidade, falhe fechado (503). Onde o limite não é a única barreira (formulário de contato), falha aberta pode ser aceita, **por escrito**.

#### B11. CORS `*`
- **Como achar:** `grep -rn "Access-Control-Allow-Origin.*\*" supabase/functions`.
- **Como corrigir:** lista vinda de segredo (`ALLOWED_ORIGINS`, `SITE_URL`) + localhost; origem desconhecida recebe a
  primeira da lista (o navegador bloqueia); `Vary: Origin` (pecas-de-codigo.md §3).
- **Armadilha:** grave os segredos **antes** de publicar as funções. Domínio esquecido = site parado, e o sintoma
  parece falha de rede ("Failed to send a request to the Edge Function").

#### B12. Domínio vindo do corpo
- **Caso real:** o link de verificação no PDF usava o `origin` enviado pelo cliente; dava para gerar documento oficial apontando para um site falso.
- **Como corrigir:** só `SITE_URL` do servidor.

#### B13. Webhook sem assinatura (ou com assinatura opcional)
- **Em palavras simples:** qualquer um finge ser o banco/gateway e avisa "pagamento aprovado".
- **Como corrigir (três barreiras):** 1) assinatura conferida (sem segredo → 503; sem header → recusa; HMAC em tempo
  constante); 2) reconsultar o status na API do provedor (não confiar no corpo); 3) conferir valor, referência e
  idempotência. Ids validados antes de montar URL (`^\d{1,20}$`).
- **Armadilhas:** a) "replay": repetir um aviso antigo para **rebaixar** um pedido pago; regra: nunca mover um pedido
  pago para trás por webhook. b) id cru na URL da API do provedor permitia `../` e `%2e%2e` (o servidor fazia GET em
  qualquer endpoint com o token do comerciante). c) Provedor sem assinatura (alguns de WhatsApp): chave longa por
  instância no endereço do webhook, comparada em tempo constante.

#### B14. Remetente não conferido (mensagens e botões)
- **Caso real:** um toque em botão do WhatsApp com um código de 2 caracteres confirmava pagamentos; o texto do botão é controlado por quem manda a mensagem.
- **Como corrigir:** a ação só vale se vier do número do operador da sessão, na instância certa; qualquer outro remetente recebe **silêncio** (não confirma que a sessão existe).

#### B15. Mensagem de erro com detalhe interno
- **Como corrigir:** resposta genérica (`erro_interno`); detalhe só no log do servidor, sem dado pessoal.

#### B16. Sessão própria que não pode ser revogada
- **Em palavras simples:** um login de 7 dias continua valendo depois de trocar a senha ou desativar a conta.
- **Como corrigir:** versão da sessão no token (`sessao_versao`/`senha_alterada_em`) e checagem de `ativo` em toda função.

### Grupo C — Dados públicos, links e identidade

#### C1. Função pública que entrega conteúdo antes da prova
- **Caso real:** a função do link de contrato entregava o contrato inteiro (com CPF, assinatura, selfie, IP) **antes**
  da pessoa digitar o CPF, e continuava entregando depois do link vencer e do contrato ser assinado.
- **Como corrigir:** a função pública devolve só metadados (nome, número, situação, prazo); o conteúdo sai do servidor
  depois da prova (CPF certo) e só enquanto válido. Teste de regressão: bloco `DO` que lê a definição da função e
  falha se um campo sensível voltar (padroes-correcao.sql §6).

#### C2. Identidade por dado autodeclarado
- **Caso real:** a conta de cliente aceitava qualquer CPF digitado, e a foto privada era entregue "a quem tem aquele CPF".
- **Regra:** dado que o próprio usuário digita nunca prova identidade. Vínculo feito pela equipe, ou prova que só o titular tem.

#### C3. Prova de identidade adivinhável
- **Em palavras simples:** "CPF + 4 últimos dígitos do telefone" são 10.000 combinações; com o bloqueio zerando a cada 15 minutos, dá para tentar todas em dias.
- **Como corrigir:** dois níveis de limite (curto para rajada + longo de 24 h por identidade e por IP); números num arquivo central.
  Conta para registrar: 20 tentativas/24 h por CPF = 200 em 10 dias contra 10.000 combinações.

#### C4. Link único para todos
- **Caso real:** `/meus-creditos?token=X` era o mesmo para todos os clientes; a barreira real era saber o CPF de alguém.
- **Como corrigir:** token por cliente (256 bits) em tabela com RLS sem policy; acesso por função da equipe; revogável.

#### C5. Token fraco ou previsível
- **Como achar:** `grep -rn "Math.random" src supabase` em tudo que vira código, token ou id.
- **Como corrigir:** `crypto.getRandomValues` (sem viés: descarte bytes fora da faixa), `gen_random_bytes(16+)` no banco.
- **Caso real:** código curto de link montado com "adversário + ano + 4 dígitos do CPF" (adivinhável).

#### C6. Link que não vence
- **Como corrigir:** validade de domínio (ex.: 2 dias depois do evento) numa constante central, aplicada no servidor
  (410 `link_expirado`, só **depois** de o token conferir, para não virar oráculo).

#### C7. Enumeração
- **Como corrigir:** uma mensagem única para qualquer falha ("Confira os dados"); comparação em tempo constante;
  "hash isca" quando o usuário não existe (o tempo de resposta fica igual).

#### C8. Dados de terceiros na resposta
- **Caso real:** a página pública baixava a lista inteira do ônibus e filtrava pelo CPF no navegador; digitar uma letra na busca abria o cartão de outra pessoa.
- **Como corrigir:** o servidor devolve só o cartão de quem provou identidade; ids de terceiros viram ids temporários; F12 → Rede é a prova.

#### C9. Token em log e em URL
- **Caso real:** o diagnóstico de login gravava `window.location.href` (com `?token=`) numa tabela de log.
- **Como corrigir:** gravar só `origin + pathname`; limpar os registros antigos
  (`update ... set url = regexp_replace(url, '[?#].*$', '') where url ~ '[?#]'`); `Referrer-Policy: strict-origin-when-cross-origin`.

#### C10. Indexação pelo Google
- **Como corrigir:** `X-Robots-Tag: noindex, nofollow` nas rotas com link de cliente (`vercel.json`) + `Disallow` no `robots.txt`.
- **Armadilha:** `robots.txt` é público e lista os caminhos: não é controle de acesso.

#### C11. Cadastro aberto no login da equipe
- **Em palavras simples:** se a API do Supabase Auth aceita criar conta, qualquer um vira "logado" e passa em toda regra "tem login".
- **Como corrigir:** painel → Authentication → desligar "Allow new users to sign up". Funcionários são criados por função de servidor (Admin API).
- **Armadilha:** não registre isso no `config.toml` se alguém puder rodar `supabase config push`.

#### C12. Cadastro público de clientes
- **Como corrigir:** só por edge function: limite por IP, validações iguais às da tela (CPF com dígito, DDD que existe,
  datas), campos extras ignorados, aceite LGPD marcado pelo servidor; checagem "CPF já existe" responde só sim/não, com limite próprio.

### Grupo D — Front e saída (XSS, links, arquivos)

#### D1. XSS guardado em HTML gerado
- **Caso real:** o nome do cliente (do cadastro público) entrava cru no HTML do contrato; o único filtro era por regex
  (contornável com `<img src=x/onerror=...>` e `<scr<script>ipt>`).
- **Como corrigir (3 camadas):** 1) escapar **todo** valor como texto ao montar o documento (troca por função, numa
  passada só); 2) sanitizador por lista de permitidos que **reconstrói** a saída; 3) exibir em
  `<iframe srcdoc sandbox>` **sem** `allow-same-origin` (pecas-de-codigo.md §5).
- **Armadilha:** `texto.replaceAll(chave, valor)` interpreta `$&`, `$1` no valor; use função: `replace(re, () => valor)`.

#### D2. `document.write` / janela de impressão
- **Como corrigir:** `escaparHtml` em cada valor; URLs de imagem por `urlSegura`.

#### D3. `javascript:` em `<iframe src>` e `<a href>`
- **Em palavras simples:** um "link" gravado por alguém que, ao ser aberto, roda código no navegador de quem abriu (e leva o login dele).
- **Como achar:** `grep -rnE "(href|src)=\{" src` onde o valor vem do banco.
- **Como corrigir:** `hrefSeguro()` (só http, https, mailto, tel) e `linkSeguroParaPrevia()` (só https e blob) +
  `CHECK (col is null or col ~* '^https://')` no banco (pecas-de-codigo.md §6).
- **Armadilha:** `java\tscript:` e maiúsculas: use o parser de URL (`new URL(...).protocol`), não regex.

#### D4. HTML em e-mail enviado em nome da empresa
- **Como corrigir:** validar e escapar cada campo, campo-isca invisível (`website`), limite por IP e global, log sem dado pessoal.

#### D5. Marcação injetada em mensagens
- **Caso real:** um nome de cliente com `[botao:Pague aqui|https://...]` virava botão em mensagens enviadas a **outros** clientes.
- **Como corrigir:** valores de variáveis nunca levam os caracteres da marcação (`[`, `]`).

#### D6. Path traversal no storage com chave de serviço
- **Em palavras simples:** o usuário informava "o caminho do arquivo"; com `%2e%2e` (que significa `..`) ele subia de pasta e o servidor assinava **o backup do banco**.
- **Por quê:** o cliente do storage não codifica o caminho e o `fetch` transforma `%2e%2e` em `..`.
- **Como corrigir (camadas):** formato fechado (`<uuid>/<uuid>.<ext>`); recusar se decodificar mudar o caminho ou se
  houver segmento `.`, `..` ou vazio; **assinar com o login de quem chamou** (não com `service_role`) + policy "só a
  própria pasta"; lista fechada de buckets assináveis.
- **Testes:** `UID/%2e%2e/x`, `UID/.%2e/x`, `UID/%2E./x`, `UID/%2e%2e%2fx`, `UID/a/b`.

#### D7. Arquivo privado em bucket público
- **Como corrigir:** bucket privado; o banco guarda uma referência (`privado:pasta/arquivo`), não uma URL; a tela recebe link temporário (1–2 h).
- **Armadilha:** os arquivos antigos já gravados na pasta pública continuam abrindo: mova-os, troque a referência e apague as cópias.

#### D8. Storage aberto para visitante
- **Casos reais:** visitante enviava, trocava e apagava fotos; listava pastas inteiras.
- **Como achar:** `POST /storage/v1/object/list/<bucket>` com a chave pública (200 com itens = falha).
- **Como corrigir:** policies só para equipe; upload anônimo (se necessário) com nome rígido por regex, sem listar nem ler de volta.

#### D9. Segredo no bundle do front
- **Regra:** `service_role` e chaves de terceiros nunca com prefixo `VITE_`/`NEXT_PUBLIC_`. Rota "só desenvolvedor" no front não esconde nada: o JavaScript é público.

#### D10. Página de desenvolvedor esquecida
- **Caso real:** uma página `/dev-mode` permitia trocar a URL e a chave do banco usadas pelo site. Removida.

#### D11. CSP fraca
- **Situação comum:** `script-src 'unsafe-inline' 'unsafe-eval'`. Endurecer exige teste no navegador (nonce/hash). Enquanto não, a defesa contra XSS é escape + lista de permitidos + iframe sandbox.

### Grupo E — Lógica de negócio e pagamentos

#### E1. Preço vindo do navegador
- **Caso real:** o checkout somava `preco * quantidade` enviados pelo cliente: Pix de R$ 1 por um item de R$ 750.
- **Como corrigir:** o cliente manda só ids e quantidades; o servidor busca o preço no catálogo, confere estoque com
  `select ... for update`, congela o total no pedido; o webhook confere que o valor pago bate com o total.

#### E2. Id do usuário vindo do corpo
- **Como corrigir:** o id vem de dentro do token de sessão, nunca do corpo (anti-IDOR).

#### E3. Senha com hash fraco e sem limite
- **Caso real:** SHA-256 sem sal, sem limite (15 tentativas em 5 s, nenhum bloqueio); o reset gravava bcrypt e o login comparava SHA-256.
- **Como corrigir:** bcrypt (rehash no login para contas antigas), limite por IP e por e-mail, comparação em tempo
  constante, trocar senha exige a atual, reset responde sempre "enviado" e o token expira em 1 h.

#### E4. Módulo desligado com portas abertas
- **Caso real:** a loja estava "desligada" por um interruptor nas funções, mas 4 funções do banco (com QR de Pix) continuavam abertas a visitantes e 5 webhooks no ar.
- **Regra:** desligar na borda não fecha o banco. Módulo congelado precisa de superfície zero: revogar funções, apagar funções do servidor (`supabase functions delete`), tirar segredos sem uso.

### Grupo F — Processo, segredos e operação

#### F1. Segredo no histórico do git
- **Como achar:** `git log -p -S'eyJ' --all`, `scripts/procurar-segredos.sh`; dumps de schema com crons que levam a chave no comando.
- **Como corrigir:** **trocar** a chave no painel (derruba o site até atualizar as variáveis na Vercel: horário calmo) e substituir no arquivo por placeholder.

#### F2. Correção feita fora das migrations
- **Caso real:** uma auditoria inteira aplicada direto no painel; a cópia do banco para um ambiente novo voltou com todas as falhas.
- **Regra:** tudo vira migration; se aplicou por fora, `supabase migration repair --status applied <versão>` no mesmo dia.

#### F3. Erro de tipo derrubando o site
- **Caso real:** 4 erros de tipo "antigos" aceitos; o build da Vercel (que roda `tsc`) falhou e o site ficou 11 dias numa versão velha, enquanto banco e funções já tinham mudado.
- **Regra:** 0 erros antes de cada push; `tsc` numa cópia limpa do commit.

#### F4. Erro de tipo nas edge functions escondendo bug
- **Caso real:** `deno check` mostrou uma função chamada com 1 argumento onde precisava de 2: um aviso ao operador nunca era enviado havia uma semana.
- **Regra:** rode `scripts/deno-check-todas.sh` antes de publicar funções.

#### F5. Dependências vulneráveis
- **Como fazer:** `npm audit --omit=dev` primeiro (o que roda em produção); atualize antes as bibliotecas de defesa (`dompurify`), depois `npm audit fix` sem `--force`.

#### F6. Envio em massa em teste
- **Caso real:** um teste do modo automático disparou 17 mensagens reais.
- **Regra:** nunca chamar endpoint de envio em lote contra produção; use modo manual com id de teste, instância de simulação ou desligue o cron.

---

## Parte 5 — Como corrigir sem quebrar: publicação segura

### 5.1 Antes de mudar
1. Mostre ao dono: **como está**, **como fica**, **o que pode afetar**, **como reverter**.
2. Procure **quem usa** o que você vai fechar: `grep` no front e nas funções, policies que chamam a função
   (`select * from pg_policies where qual like '%nome_da_funcao%'`), gatilhos.
3. Decida a **ordem** (5.3).

### 5.2 A migration
- Número **acima da maior existente** (`ls supabase/migrations | tail -3`); se há outra sessão trabalhando, confira de novo antes de aplicar.
- Cabeçalho: **PROBLEMA** (com a evidência), **CORREÇÃO**, **QUEM USA**, **ORDEM DE PUBLICAÇÃO**, **COMO REVERTER** (SQL).
- Termine com um **bloco `DO` de verificação** que falha se a correção não pegou (bucket ainda público, função ainda
  executável, campo sensível ainda na definição). A migration falha e desfaz sozinha (padroes-correcao.sql §6).
- Mudanças que apagam dados: trava que aborta se houver linha inesperada.

### 5.3 Ordem de publicação
- **Regra de fundo:** o código novo não pode chamar o que ainda não existe; o banco novo não pode quebrar o código que está no ar.
- **Padrão:** banco → funções → site.
- **Fechar um caminho antigo:** caminho novo → trocar as telas → publicar o site → fechar o antigo.
- **Grant por coluna:** site (sem `select('*')`) → migration.
- **CORS por lista:** segredos (`ALLOWED_ORIGINS`, `SITE_URL`) → funções.
- **Cron com segredo:** banco (disparador manda o segredo) → funções (passam a exigir).
- **Remover um módulo:** site → apagar funções → banco.

### 5.4 Ensaiar, simular, aplicar
```bash
# ensaio: rode a migration dentro de uma transação desfeita (psql ou SQL Editor)
#   begin; \i supabase/migrations/<versao>_<nome>.sql  -- + testes por perfil
#   rollback;
supabase db push --linked --dry-run      # deve listar SÓ as suas migrations
supabase db push --linked                # aplica
supabase migration list --linked         # confere
```
Se o histórico estiver desalinhado: aplique uma migration por vez (`psql "$DATABASE_URL" -v ON_ERROR_STOP=1 --single-transaction -f arquivo.sql`)
e registre com `supabase migration repair --linked --status applied <versão>`. Nunca `--include-all` sem entender.

### 5.5 Funções do servidor
```bash
deno check --no-lock --no-config supabase/functions/<nome>/index.ts
supabase functions deploy <nome> [<nome2> ...] --project-ref <PROJECT_REF>
supabase functions delete <nome> --project-ref <PROJECT_REF>     # código fica no git
supabase secrets set NOME=valor --project-ref <PROJECT_REF>
supabase secrets unset NOME --project-ref <PROJECT_REF>
```
Republique também as funções que **importam** um arquivo compartilhado alterado.

### 5.6 Site
- Testes + `tsc` com 0 erros numa **cópia limpa** do commit (sem o lixo local nem o trabalho de outras sessões):
  ```bash
  git worktree add --detach /tmp/copia-limpa HEAD
  ln -s "$PWD/node_modules" /tmp/copia-limpa/node_modules
  (cd /tmp/copia-limpa && npx tsc -p tsconfig.app.json --noEmit)
  git worktree remove --force /tmp/copia-limpa
  ```
- Só então `git push` (a Vercel publica sozinha). Não precisa ficar vigiando o deploy; olhe a lista de deploys só se algo "não entrou no ar".

### 5.7 Conferir depois de publicar
- De fora, com tokens falsos: `scripts/conferir-endpoints.mjs` (cada função responde 401/403/404 como esperado).
- No catálogo: `has_function_privilege`, `storage.buckets`, contagem de registros limpos.
- Repita o teste do visitante.

### 5.8 Trocar um segredo exposto
1. Gere o valor novo sem exibir (`openssl rand -hex 32` direto no comando de gravação).
2. Grave em todos os lugares que usam (Vault do banco **e** segredos das funções, com o mesmo valor).
3. Confira por **hash** (o `supabase secrets list` mostra o sha256 do valor; compare com o sha256 do Vault), sem imprimir o valor.
4. Confirme que a rotina que usa o segredo continuou funcionando (ex.: a próxima execução do cron respondeu 200).

### 5.9 Várias sessões/agentes no mesmo repositório
- **Nunca** `git stash`, `git checkout -- .`, `git reset` (apaga o trabalho dos outros).
- Commit **só dos seus arquivos** (`git add <arquivos>` + `git commit --only <arquivos>` ou `--pathspec-from-file`).
- Arquivo mexido por duas sessões: confira o diff linha a linha antes do commit; na dúvida, separe as linhas.
- O `tsc` na cópia limpa pega a mistura (já pegou: duas linhas de outra sessão dependiam de um arquivo ainda não commitado).
- Migrations: número acima da maior existente, `--dry-run` mostrando só as suas.

### 5.10 Comunicar
- O que mudou, em linguagem simples; o que muda para o usuário final; o que **não** foi testado; o que você fez **além do pedido** e como reverter.
- Acrescente os testes manuais ao roteiro de testes do projeto.

---

## Parte 6 — Padrões de desenho aprovados

### 6.1 Página pública sem login
- O link é igual para todos os participantes (ex.: da viagem); a pessoa **prova quem é** (ex.: CPF + cidade de embarque + 4 últimos dígitos do telefone).
- Tudo passa por uma edge function: ela confere a prova, aplica limites (sessão, identidade, IP; curto e longo) e devolve **só o cartão daquela pessoa**.
- Busca por nome nunca abre cartão; erro sempre genérico; ids de terceiros viram temporários.
- Link vence (ex.: 2 dias depois do evento).
- Alternativa quando não há prova natural: token **por pessoa**, 256 bits, revogável, com validade.

### 6.2 Equipe externa (guia, parceiro)
Senha por evento (bcrypt), sessão curta (12 h), versão que invalida sessões ao gerar senha nova, senha mostrada uma vez, bloqueio por IP (não por evento: senão alguém bloqueia de propósito), validade após o evento.

### 6.3 Sessão própria (fora do Supabase Auth)
JWT assinado com segredo próprio (sem valor de reserva); id do usuário **dentro** do token; duração curta; versão para revogar; `ativo` conferido a cada chamada.

### 6.4 Links assinados
HMAC-SHA256 com rótulo de finalidade e versão (`finalidade:v1:id`), chave dedicada por finalidade, 128 bits, comparação em tempo constante. Formato antigo aceito só por prazo definido.

### 6.5 Permissões
- Papéis (desenvolvedor, dono, admin, funcionário) + caixas de permissão por área.
- A **mesma** função de permissão na tela e no banco; mapa tabela → área para gravação.
- "Equipe ativa" é pré-condição de tudo; bloqueio é imediato.
- Funcionário novo nasce com o mínimo; caixa nova herda da antiga no dia da mudança (ninguém perde acesso de surpresa).
- Dado pessoal mascarado (`•••`) para quem não tem a caixa.

### 6.6 Dinheiro
Preço sempre no servidor; total congelado no pedido; webhook com três barreiras; idempotência; pedido pago nunca volta por webhook.

### 6.7 Arquivos
Bucket privado; referência no banco; link temporário gerado no servidor só para o dono do arquivo; lista fechada de buckets; caminho em formato fechado; assinatura com o login de quem pede.

### 6.8 Falha fechada (sempre que possível)
Sem segredo → recusa. Consulta de permissão falhou → "não". Token inválido → bloqueia. Função nova não nasce aberta ao visitante (`alter default privileges ... revoke execute on functions from anon`).

### 6.9 O servidor não precisa de policy
`service_role` passa por cima da RLS. Para dados só do servidor: RLS ligada **sem** policy e grant só para `service_role`.

---

## Parte 7 — Incidentes reais e lições

| O que aconteceu | Lição |
|---|---|
| Policy `using (true)` expôs 3.300 clientes com CPF, telefone e e-mail | Rode o teste do visitante em todo projeto, hoje |
| Uma auditoria "OK" testou só o visitante; a função de SQL livre estava aberta para qualquer logado | Teste também como `authenticated` sem permissão |
| Correções aplicadas direto no painel sumiram na cópia do banco | Tudo vira migration |
| Teste "217 tabelas devolvem `[]`" passou uma tabela aberta porque estava vazia | Prove com 42501 ou com a policy |
| Restringir uma função usada numa policy esvaziou a vitrine pública | Procure quem usa antes de fechar |
| Teste de envio automático disparou 17 WhatsApps reais | Nunca teste envio em lote em produção |
| `supabase config push` sobrescreveu o login de vários apps | Nunca use como simulação |
| 4 erros de tipo "antigos" pararam o site por 11 dias | Base zero; `tsc` em cópia limpa |
| Segredo interno legível por qualquer logado permitia baixar o banco | Revise grants de funções `SECURITY DEFINER`; troque o segredo |
| Path traversal com `%2e%2e` assinaria o backup do banco | Revisão independente antes de publicar; assinar com o login de quem pede |
| Link de comprovante virou chave-mestra da base de clientes | Link identifica, não autoriza |
| `javascript:` gravado num comprovante roubaria a sessão do dono | `hrefSeguro`/`linkSeguroParaPrevia` + CHECK no banco |
| Chave de serviço de outro projeto ficou num dump antigo no git | Procure no histórico; troque a chave |
| Commit levou linhas de outra sessão que dependiam de arquivo não commitado | `tsc` em cópia limpa antes do push |
| `deno check` revelou aviso ao operador que nunca era enviado | Rode `deno check` nas funções |
| Scripts do repositório gravavam no projeto de produção com o ref fixo | Scripts leem o `.env` e recusam produção |

---

## Parte 8 — Checklist final

Copie e marque.

**Banco**
- [ ] Toda tabela com RLS
- [ ] Nenhuma policy `anon`/`public` com `true` ou `IS NOT NULL` em dado sensível
- [ ] Nenhuma policy "só tem login" em tabela de equipe (usa equipe ativa + permissão)
- [ ] `anon` sem `INSERT/UPDATE/DELETE/TRUNCATE` (exceto grants mínimos documentados)
- [ ] Privilégios padrão ajustados (tabela e função nova não nascem abertas)
- [ ] Nenhuma função `SECURITY DEFINER` sensível executável por `anon`/`authenticated` sem trava interna
- [ ] Todas as `SECURITY DEFINER` com `search_path` fixo
- [ ] Views com `security_invoker`
- [ ] Bloqueio imediato (`ativo` em toda checagem; sessões encerradas)
- [ ] Nenhuma tabela de backup parada em produção
- [ ] `supabase db advisors --type security` revisado

**Storage**
- [ ] Buckets com dado pessoal privados; links temporários
- [ ] Visitante não lista nem grava (exceto upload rígido documentado)
- [ ] Assinatura de arquivo com lista fechada de buckets e caminho em formato fechado

**Edge functions**
- [ ] Toda função checa quem chama antes de ler dados (`verify_jwt` não basta)
- [ ] Nada de "interno" decidido pelo corpo; cron com segredo
- [ ] Hierarquia por alvo em funções de usuário
- [ ] Segredos sem valor de reserva
- [ ] CORS por lista; `SITE_URL` do servidor
- [ ] IP pelo último item / `cf-connecting-ip`; limites que falham fechado no login
- [ ] Webhooks: assinatura obrigatória + reconsulta + valor + idempotência
- [ ] Erros genéricos; log sem dado pessoal
- [ ] `deno check` sem erros

**Páginas públicas**
- [ ] Token forte, individual ou com prova de identidade
- [ ] Validade e revogação
- [ ] Limites curto e longo; respostas iguais
- [ ] API entrega só o que a tela mostra
- [ ] `noindex`; token fora de logs; `Referrer-Policy`

**Front**
- [ ] Sem `service_role` no bundle
- [ ] XSS: escape, lista de permitidos, iframe sandbox
- [ ] `href`/`src` com valor do banco passam por `hrefSeguro`/`linkSeguroParaPrevia`
- [ ] Headers de segurança; CSP sem `unsafe-inline` (quando possível)
- [ ] `npm audit` de produção limpo
- [ ] Sem páginas de desenvolvedor esquecidas

**Processo**
- [ ] Segredos fora do git; histórico verificado; chaves expostas trocadas
- [ ] Cadastro aberto do Auth desligado (se não for usado)
- [ ] Proteção de senha vazada e MFA para quem administra
- [ ] Tudo em migration; histórico alinhado
- [ ] `tsc` 0 erros; testes passando
- [ ] Roteiro de testes manuais atualizado
- [ ] Varredura independente feita (Claude Security ou equivalente)
