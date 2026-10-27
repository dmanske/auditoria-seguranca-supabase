# Ferramentas e skills usadas (e alternativas para quem não usa Claude)

Uma auditoria boa combina três coisas:
1. **Ler o catálogo do banco** (consultas SQL; o que **deveria** acontecer).
2. **Testar de verdade** com a chave pública e tokens falsos (o que **acontece**).
3. **Uma ou mais IAs/ferramentas revisando o código**, de preferência com verificação independente.

Nenhuma ferramenta sozinha resolve. Elas acham coisas diferentes, e as melhores descobertas vieram de
**cruzar** uma com a outra (uma varredura apontou, o teste ao vivo confirmou; uma revisão independente achou
o que a primeira deixou passar).

## Mapa rápido: quando usar o quê

| Situação | Com Claude Code | Sem Claude |
|---|---|---|
| Auditoria completa do servidor (banco + funções) | plugin **Claude Security** → Scan codebase, `medium`, escopo `supabase/` | prompt de `prompts/outras-ias.md` + **Semgrep** + consultas SQL |
| Triagem rápida e barata do site (front) | Claude Security → Scan codebase, `low`, escopo `src/` | **Semgrep** (`p/react`, `p/typescript`) |
| Revisar só o que mudou antes de publicar | `/security-review`, `/find-bugs`, Claude Security → Scan changes | outra IA com o diff + checklist da Parte 8 |
| Modelar ameaças / "posso ir para produção?" / incidente | skill **`007`** (ou `threat-modeling-expert`) | STRIDE à mão (GUIA, Parte 3) |
| Qualquer coisa de Supabase (RLS, policy, função, storage) | skills **`supabase`** + **`supabase-postgres-best-practices`** | docs oficiais + `referencias/consultas.sql` |
| Scanner oficial de configuração do Supabase | `supabase db advisors --linked --type security` | painel → **Advisors → Security Advisor** |
| Testar ataques específicos (IDOR, XSS, injeção, login) | skills de teste da coleção comunitária (abaixo) | **OWASP ZAP**, Burp Community |
| Pentest por IA que **ataca o alvo de verdade** (em sandbox Docker) | **Strix** (`usestrix/strix`): alvo = **cópia limpa sem `.env`**, `-m quick --max-budget <USD>`, `-n`; LLM via gateway da Lovable. Confira cada achado (a maioria de IDOR é barrada pela RLS = nota de endurecimento) | OWASP ZAP, Burp |
| Auditoria **ampla multi-domínio** (LLM/prompt-injection, cloud/IaC, supply-chain, cliente, IPC) | skill **`security-audit`** (Cloudflare): harness multiagente com coverage ledger e validação adversarial | — |
| Segredos no código e no histórico do git | `scripts/procurar-segredos.sh` | **gitleaks**, **trufflehog** |
| Dependências | `npm audit --omit=dev` | `npm audit`, Dependabot, Snyk |
| Headers do site | `vercel.json` + revisão | https://securityheaders.com, Mozilla Observatory |
| Analisar app/extensão/bundle de terceiros | skill **`reverse-engineer-anything`** (MCP `rea`) | DevTools (F12), sourcemaps |
| Ver o que a página pública entrega | F12 → Rede (Network) | o mesmo |
| Erros de tipo nas edge functions | `scripts/deno-check-todas.sh` | o mesmo (`deno check`) |

---

## 1. Claude Code (nativo)

### 1.1 Plugin Claude Security (`/claude-security:claude-security`)
- **O que é:** uma equipe de agentes de segurança. Mapeia o código, monta um modelo de ameaças, distribui pesquisadores
  por componente e categoria (acesso, injeção, segredos, memória) e passa **cada achado** por um painel de **3
  verificadores independentes** (fica no relatório só o que tem 2 de 3 votos). Não altera nada.
- **Como usar:**
  1. No Claude Code, aberto na pasta do projeto: `/claude-security:claude-security`.
  2. Escolha **Scan codebase** (projeto inteiro ou uma pasta), **Scan changes** (o que mudou numa branch ou commit) ou
     **Suggest patches** (transforma achados em arquivos `.patch` revisados, que você aplica com `git apply`).
  3. Escolha o escopo e o esforço. Ele pede uma confirmação de custo antes de começar.
  4. Funciona melhor em modo auto (Shift+Tab até aparecer "auto mode", ou `claude --permission-mode auto`).
- **Esforço:**
  - `low`: um pesquisador lê tudo + painel. Triagem rápida.
  - `medium`: inventário, modelo de ameaças, um pesquisador por componente × categoria, varredura extra + painel. **Padrão recomendado.**
  - `high`: dobra os pesquisadores e os componentes.
  - `max`: `high` + fase adversarial (cada achado enfrenta um "refutador").
- **Custo real que vimos:**
  - `medium` em ~300 arquivos de servidor: ~1 hora, ~13,5 milhões de tokens, 42 achados confirmados (6 altos).
  - `low` em ~2.700 arquivos de front: ~13 minutos, ~345 mil tokens, 1 achado.
  - Pode bater no limite de uso da sessão; ele refaz sozinho o que falhou.
- **Saída:** pasta `CLAUDE-SECURITY-<data>/` (fora do git) com relatório `.md`, `.jsonl` (para CI) e `.sarif` (para painéis de code scanning).
- **Limites:** só lê código (não prova no banco ao vivo); relatório "dirty" (com mudanças não commitadas) não serve para gerar patches; precisa da ferramenta Workflow (se faltar, ligar "Dynamic workflows" em `/config`).
- **Dica:** a varredura `medium` do servidor é onde ele mais rende. Para o front, `low` já é bom.

### 1.2 `/security-review`
- Revisão de segurança das **mudanças pendentes** da branch atual. Rápida. Boa antes de cada publicação.
- Usamos para revisar o commit de outra sessão: achou um path traversal grave antes de ir ao ar.

### 1.3 `/code-review`
- Revisão de bugs de correção de um diff, branch ou PR. Níveis `low` a `max`, e `ultra` (multiagente na nuvem).
  `--fix` aplica correções; `--comment` comenta no PR.

---

## 2. Skills (Claude Code, Kiro, Cursor, Gemini CLI e outros agentes)

Skills são "manuais especializados" que a IA carrega quando precisa. A mesma skill funciona em vários
assistentes: o formato é uma pasta com um `SKILL.md`.

### Como instalar

```bash
# instalador universal de skills (pergunta para qual agente: claude-code, kiro-cli, cursor, gemini...)
npx skills add https://github.com/supabase/agent-skills --skill supabase -g -y
npx skills add https://github.com/supabase/agent-skills --skill supabase-postgres-best-practices -g -y
npx skills add https://github.com/sickn33/agentic-awesome-skills --skill 007 -g -y
npx skills add https://github.com/sickn33/agentic-awesome-skills --skill find-bugs -g -y
npx skills add https://github.com/obra/superpowers --skill brainstorming -g -y
# esta skill:
npx skills add https://github.com/dmanske/auditoria-seguranca-supabase --skill auditoria-seguranca -g -y
```
`-g` = global (vale para todos os projetos); `-y` = sem perguntas.

**Instalar à mão:** copie a pasta da skill para o diretório do seu agente:
- Claude Code: `~/.claude/skills/<nome>/`
- Kiro: `~/.kiro/skills/<nome>/`
- Gemini CLI: `~/.gemini/skills/<nome>/`
- Outros: `.agent/skills/<nome>/` na raiz do projeto

**Como chamar:** no Claude Code, `/<nome>` ou só pedir ("faça uma auditoria de segurança"); no Kiro e em
vários outros, `@<nome> <pedido>`.

### 2.1 Skills principais (as que mais usamos)

| Skill | O que faz | Quando usar | Cuidados |
|---|---|---|---|
| **`007`** | Arquiteto de segurança: auditoria, modelagem de ameaças (STRIDE/PASTA), red team mental com personas, blue team, resposta a incidente. Dá nota 0–100 por área (segredos 20%, entrada 15%, autenticação/autorização 15%, dados 15%, resiliência, monitoramento, dependências, conformidade) e um veredito (aprovado / com ressalvas / bloqueado). | "Audite este projeto", "modele as ameaças", "posso colocar em produção?", "vazou um token". | A nota é qualitativa: já vimos 74/100 com a autorização real perto de 40. Não tem verificação independente; confirme os achados. Os scripts dela podem precisar de ajuste de caminho. |
| **`find-bugs`** | Revisa o diff da branch atrás de bugs e vulnerabilidades (injeção, XSS, autenticação, IDOR, CSRF, corrida, sessão, cripto, vazamento, lógica). Lista o que leu e o que não deu para verificar. | Antes de publicar uma mudança. | Só olha o que mudou; não varre o projeto. |
| **`supabase`** | Guia oficial para tudo de Supabase, com um checklist de segurança embutido (ex.: `user_metadata` não serve para autorização; views ignoram RLS; UPDATE precisa de policy de SELECT; `SECURITY DEFINER` é chamável por todos por padrão). | Qualquer tarefa com banco, Auth, Storage, Edge Functions. | É orientação, não scanner. |
| **`supabase-postgres-best-practices`** | Boas práticas de Postgres por prioridade (segurança e RLS é "crítico"): privilégios, RLS, performance de RLS. | Antes de escrever migration, policy, função, índice. | Guia, não auditoria. |
| **`brainstorming`** | Estrutura planos e decisões antes de construir. | Desenhar a correção de algo grande (ex.: trocar o modelo de links públicos). | — |
| **`reverse-engineer-anything`** (MCP `rea`) | Engenharia reversa com evidência: bundles JS, páginas, extensões, apps, binários. Captura o tráfego de uma página no navegador. | Ver o que uma página pública realmente recebe; auditar extensão/app de terceiros antes de confiar. | Precisa do servidor MCP `rea` instalado; não use para ler código-fonte que você já tem. |

### 2.2 Skills de teste da coleção comunitária (usadas no Kiro)

Uma coleção comunitária com centenas de skills (vários autores, como `zebbern` e `addyosmani/agent-skills`)
traz estas de segurança. As marcadas **ofensivas** ensinam a explorar a falha: use **só no seu sistema**.

| Skill | Para quê | Tipo |
|---|---|---|
| `api-security-testing` | Testar APIs REST/GraphQL: autenticação, autorização, limite, validação | teste |
| `web-security-testing` | Roteiro OWASP Top 10 para sites | teste |
| `idor-testing` | Achar IDOR (trocar id e ver dado alheio) | ofensiva |
| `broken-authentication` | Falhas de login e sessão | ofensiva |
| `xss-html-injection` | Achar XSS e injeção de HTML | ofensiva |
| `sql-injection-testing` | Achar injeção de SQL | ofensiva |
| `threat-modeling-expert` | STRIDE, PASTA, árvores de ataque | desenho |
| `vulnerability-scanner` | Princípios de análise (OWASP 2025, supply chain, superfície de ataque) | análise |
| `security-and-hardening` (addyosmani) | Endurecer código que recebe dado não confiável | construção |
| `frontend-security-coder` | Front seguro: XSS, saída, padrões do navegador | construção |
| `saas-multi-tenant` | Isolamento entre empresas com RLS e consultas por tenant | construção |
| `gdpr-data-handling` | Consentimento e privacidade (vale para a LGPD) | conformidade |
| `nextjs-supabase-auth` | Supabase Auth no Next.js (App Router) | construção |
| `verification-before-completion` | Proíbe dizer "pronto" sem verificar | processo |

Para achar e instalar: a skill `find-skills` ou `npx skills find <termo>`.

---

## 3. Supabase (nativo)

- **Security Advisor**: painel do projeto → Advisors → Security. É o mesmo do comando
  `supabase db advisors --linked --type security`. Aponta: views que furam a RLS, funções `SECURITY DEFINER`
  executáveis por `anon`/`authenticated`, `search_path` aberto, proteção de senha vazada desligada etc.
  **Não** diz se uma policy `USING (true)` é intencional nem testa nada ao vivo: combine com as consultas e o teste do visitante.
- **CLI:**
  - `supabase db query --linked "<SQL>"` (roda SQL sem Docker);
  - `supabase db push --linked --dry-run`;
  - `supabase migration list --linked`;
  - `supabase migration repair --linked --status applied <versão>`;
  - `supabase functions deploy|delete|list`;
  - `supabase secrets list|set|unset`.
- **MCP do Supabase** (em assistentes com MCP): `execute_sql`, `get_advisors`, `list_tables`. Pode negar permissão; aí use o CLI.
- **Nunca:** `supabase config push` como teste (aplica o `config.toml` inteiro sem perguntar).

---

## 4. Ferramentas sem IA (gratuitas)

| Ferramenta | Para quê | Comando típico |
|---|---|---|
| **npm audit** | Dependências vulneráveis | `npm audit --omit=dev` (produção primeiro) |
| **gitleaks** | Segredos no código e no **histórico** do git | `gitleaks detect --source . -v` |
| **trufflehog** | Idem, verificando se a chave ainda vale | `trufflehog git file://. --only-verified` |
| **Semgrep** | Análise estática (XSS, injeção, segredos, padrões ruins) | `semgrep --config p/default --config p/react --config p/typescript` |
| **OWASP ZAP** | Varredura dinâmica do site no ar | modo "Automated Scan" contra **o seu** site |
| **securityheaders.com** / **Mozilla Observatory** | Headers de segurança | colar a URL |
| **deno** | Erros de tipo nas edge functions | `deno check --no-lock --no-config supabase/functions/<f>/index.ts` |
| **DevTools (F12 → Rede)** | Ver o JSON que chega na página pública | abrir a página e olhar as respostas |
| **curl** | Testar endpoint com token falso | `curl -X POST <url> -H "apikey: <anon>" -d '{"token":"falso"}'` |

---

## 5. Usando com outras IAs (Cursor, Kiro, ChatGPT/Codex, Gemini, Copilot)

O conteúdo desta skill é texto. Ele funciona em qualquer assistente:

- **Kiro:** copie a pasta `auditoria-seguranca` para `~/.kiro/skills/` e use `@auditoria-seguranca faça uma
  auditoria`. Para regras permanentes do projeto, copie a Parte 2 (regras de ouro) para `.kiro/steering/seguranca.md`.
- **Cursor:** copie a pasta para `.agent/skills/` (ou anexe `GUIA_COMPLETO.md` ao chat) e cole o prompt de
  `prompts/outras-ias.md`. Para regras permanentes: `.cursor/rules/seguranca.mdc` com a Parte 2.
- **Gemini CLI:** `~/.gemini/skills/auditoria-seguranca/` ou `GEMINI.md` com a Parte 2.
- **ChatGPT / Codex / Copilot Chat:** anexe `GUIA_COMPLETO.md` + `referencias/consultas.sql` e cole o prompt.
  Se a IA não roda comandos, ela te diz o que rodar e você cola o resultado de volta.
- **Sem IA:** siga o `GUIA_COMPLETO.md`, Parte 3, rodando as consultas no SQL Editor do Supabase e os scripts no terminal.

**Regra que vale para qualquer IA:** ela não altera nada sem sua aprovação, mostra evidência de cada achado e diz o que não conseguiu verificar.
