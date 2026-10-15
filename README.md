# Auditoria de segurança para projetos Supabase

**Descubra se o seu sistema está vazando dados de clientes e corrija sem quebrar nada.**

Este repositório é o roteiro que usamos para auditar e endurecer um sistema real em produção: painel administrativo,
páginas públicas para clientes (links enviados por WhatsApp), pagamentos por Pix e cartão, contratos com assinatura
digital, envio de mensagens, arquivos privados e permissões por funcionário. Em duas semanas de trabalho achamos e
fechamos **mais de 40 tipos de falha**, de "qualquer pessoa lê todos os clientes" até "um link de recibo vira chave
para a base inteira". Tudo o que aprendemos está aqui, explicado para quem não é técnico e com o código pronto para
quem é.

Pensado para projetos com:
- front em **React/Vite ou Next.js** (Vercel ou similar);
- **Supabase**: banco Postgres com RLS, Storage, Edge Functions e Auth;
- páginas públicas, painel com funcionários, pagamentos e integrações (WhatsApp, e-mail, gateways).

Funciona com **Claude Code** (como skill), com **outras IAs** (Cursor, Kiro, ChatGPT/Codex, Gemini, Copilot) e
também **sem IA**, seguindo o guia à mão.

> ⚠️ Use só em projetos seus ou que você tem autorização para testar.

---

## O que este roteiro encontra

Exemplos reais do que achamos (todos corrigidos), para você ter ideia do que procurar:

**Dados vazando para quem não tem login**
- Uma regra do banco "todo mundo vê tudo" deixava qualquer pessoa ler **3.300 clientes** (CPF, telefone, e-mail) usando só a chave pública que está dentro do próprio site.
- Uma página de cliente baixava a **lista inteira de passageiros** (CPF, telefone, nascimento, valores) e filtrava no navegador: bastava abrir o F12 para ver todos.
- O link de um contrato entregava o **documento inteiro** (com CPF, assinatura e selfie) antes da pessoa digitar o CPF, e continuava funcionando depois de vencido.
- O **preço de custo** chegava ao navegador do cliente final e revelava a margem.

**Funcionários com poder demais**
- Qualquer funcionário logado podia trocar a chave Pix da empresa e se promover a dono (as permissões só existiam na tela).
- Funcionário bloqueado continuava usando o sistema até o login vencer.
- Um administrador conseguia apagar a conta do dono.

**Servidor aceitando o que não devia**
- Uma função do banco entregava o **segredo interno** do servidor a qualquer logado e, com ele, dava para baixar o banco inteiro.
- Uma função de backup pulava a autenticação se o pedido dissesse `"automatico": true`.
- Funções de estorno, de envio de WhatsApp e de IA podiam ser chamadas por qualquer um da internet.
- Um webhook de pagamento aceitava avisos falsos e permitia "rebaixar" pedidos já pagos.
- Um caminho de arquivo com `%2e%2e` (que significa `..`) faria o servidor assinar **o backup do banco**.

**Links e páginas públicas**
- Link igual para todos os clientes, sem validade, adivinhável ou com código de 2 caracteres.
- Prova de identidade (CPF + 4 dígitos do telefone) adivinhável porque o bloqueio zerava a cada 15 minutos.
- Token do link gravado em log, enviado a sites de terceiros pelo `Referer` e indexado pelo Google.

**Front**
- Um "link" gravado como `javascript:...` que, ao ser aberto pelo dono, levaria o login dele.
- Nome de cliente com HTML que virava código dentro do contrato (XSS).
- Chave de API de terceiro no código do site, e uma página "de desenvolvedor" esquecida que trocava o banco usado.

**Processo**
- Correções feitas direto no painel que sumiram na cópia do banco.
- Chave de serviço no histórico do git.
- 4 erros de tipo "antigos" que deixaram o site parado por 11 dias.
- Um teste que disparou 17 mensagens reais de WhatsApp.

Para cada um, o guia explica **em palavras simples**, mostra **como achar**, **como corrigir** (com código),
**como confirmar** e **a armadilha** que pegamos no caminho.

### Vazamento pelo navegador (F12)

Uma parte inteira do guia ensina a abrir o **Chrome → F12** e ver, nas abas **Rede**, **Console**, **Aplicação** e
**Fontes**, o que o seu site entrega de verdade, mesmo o que a tela não mostra. É o teste mais simples e mais
revelador: qualquer pessoa consegue fazer em 5 minutos por página. Ver
[GUIA_COMPLETO.md, Parte 9](skills/auditoria-seguranca/GUIA_COMPLETO.md#parte-9--vazamento-pelo-navegador-abas-rede-console-e-aplicação-f12).

---

## Instalação

### Tudo de uma vez (recomendado)
```bash
git clone https://github.com/dmanske/auditoria-seguranca-supabase
bash auditoria-seguranca-supabase/instalar.sh
```
Instala a skill `auditoria-seguranca` **e** as skills complementares (tabela abaixo). O instalador pergunta para
qual assistente instalar (Claude Code, Kiro, Cursor, Gemini CLI…).

### Só a skill principal
```bash
npx skills add https://github.com/dmanske/auditoria-seguranca-supabase --skill auditoria-seguranca -g -y
```
Ela funciona sozinha: traz o guia, as consultas, os modelos de correção, o código pronto e os scripts. As outras
skills **não** vêm junto; elas ajudam, mas são opcionais.

### Sem instalar nada
Leia o [GUIA_COMPLETO.md](skills/auditoria-seguranca/GUIA_COMPLETO.md) e use os prompts de [prompts/](prompts/).

---

## Skills e ferramentas que usamos

| Ferramenta | O que faz | Para quê | Como obter |
|---|---|---|---|
| **auditoria-seguranca** (esta) | Roteiro completo, catálogo de falhas, consultas, correções, scripts | A auditoria inteira | `instalar.sh` ou `npx skills add …` acima |
| **supabase** | Guia oficial de Supabase com checklist de segurança | Banco, Auth, Storage, Edge Functions | `npx skills add https://github.com/supabase/agent-skills --skill supabase -g -y` |
| **supabase-postgres-best-practices** | Boas práticas de Postgres (RLS, privilégios, performance) | Antes de escrever migration/policy | `npx skills add https://github.com/supabase/agent-skills --skill supabase-postgres-best-practices -g -y` |
| **007** | Auditoria, modelagem de ameaças (STRIDE/PASTA), red/blue team, nota por área, veredito "pode ir para produção?" | Visão geral e incidentes | `npx skills add https://github.com/renat/007 --skill 007 -g -y` |
| **find-bugs** | Revisa o diff da branch atrás de bugs e vulnerabilidades | Antes de publicar | `npx skills add https://github.com/anthropics/courses --skill find-bugs -g -y` |
| **brainstorming** | Estrutura o desenho antes de construir | Correções grandes | `npx skills add https://github.com/anthropics/courses --skill brainstorming -g -y` |
| **Claude Security** (plugin do Claude Code) | Equipe de agentes que varre o código e passa cada achado por 3 verificadores independentes | Varredura independente | No Claude Code: `/plugin` → "Claude Security" |
| **/security-review** e **/code-review** | Revisão de segurança/bugs do que mudou | Antes de publicar | Já vêm no Claude Code |
| **reverse-engineer-anything** + MCP **rea** | Engenharia reversa com evidência; captura o tráfego de páginas | Ver o que a página entrega; auditar apps de terceiros | Skill + servidor MCP `rea` |
| Skills de teste da coleção comunitária: `idor-testing`, `xss-html-injection`, `sql-injection-testing`, `broken-authentication`, `api-security-testing`, `web-security-testing`, `threat-modeling-expert`, `vulnerability-scanner`, `security-and-hardening`, `frontend-security-coder`, `saas-multi-tenant`, `gdpr-data-handling` | Testes e padrões específicos (as de "testing" ensinam a explorar: só no seu sistema) | Aprofundar um tipo de falha | `npx skills find <termo>` |
| **Supabase Security Advisor** | Scanner oficial de configuração | Toda auditoria | Painel → Advisors, ou `supabase db advisors --linked --type security` |
| **Supabase CLI** | Rodar SQL, migrations, funções, segredos | Toda auditoria | https://supabase.com/docs/guides/cli |
| **Deno** | Checar erros nas Edge Functions | Antes de publicar funções | `brew install deno` / https://deno.land |
| **gitleaks** / **trufflehog** | Segredos no histórico do git | Fase de segredos | gitleaks.io / github.com/trufflesecurity/trufflehog |
| **Semgrep** | Análise estática do código | Alternativa sem IA | semgrep.dev |
| **OWASP ZAP** | Testa o site no ar | Alternativa sem IA | zaproxy.org |
| **Chrome DevTools (F12)** | Ver o que chega ao navegador | Páginas públicas | Já vem no navegador |

Detalhes de cada uma (quando usar, custo, limites e como usar em outras IAs):
[referencias/ferramentas.md](skills/auditoria-seguranca/referencias/ferramentas.md).

---

## Como usar: escolha o seu caminho

### 1. Uso Claude Code
Na pasta do seu projeto:
```
Faça uma auditoria de segurança deste projeto usando a skill auditoria-seguranca. Só leitura primeiro.
```
A IA segue o roteiro (preparar → inventário → banco → teste do visitante → teste por perfil → funções do servidor →
páginas públicas → navegador → front → segredos → varredura independente → relatório), mostra a evidência de cada
achado, explica em linguagem simples e **não altera nada sem a sua aprovação**. Outras formas de pedir:
[prompts/claude-code.md](prompts/claude-code.md).

### 2. Uso outra IA (Cursor, Kiro, ChatGPT, Gemini, Copilot…)
Abra a IA na pasta do projeto, anexe o [GUIA_COMPLETO.md](skills/auditoria-seguranca/GUIA_COMPLETO.md) e cole o
prompt de [prompts/outras-ias.md](prompts/outras-ias.md). No Kiro, a skill instalada responde a `@auditoria-seguranca`.

### 3. Não uso IA
Siga o [GUIA_COMPLETO.md](skills/auditoria-seguranca/GUIA_COMPLETO.md), Parte 3. Rode as consultas de
[consultas.sql](skills/auditoria-seguranca/referencias/consultas.sql) no **SQL Editor** do Supabase, faça o teste do
navegador (Parte 9) e use os scripts:

```bash
# o que um estranho consegue ler com a chave pública do seu site?
supabase db query --linked -f skills/auditoria-seguranca/scripts/alvos-visitante.sql > alvos.json
node skills/auditoria-seguranca/scripts/teste-visitante.mjs caminho/do/projeto/.env alvos.json

# chaves esquecidas no código ou no histórico do git
bash skills/auditoria-seguranca/scripts/procurar-segredos.sh caminho/do/projeto

# erros nas Edge Functions
bash skills/auditoria-seguranca/scripts/deno-check-todas.sh caminho/do/projeto
```

---

## O que tem aqui

```
instalar.sh                      ← instala a skill e as complementares
skills/auditoria-seguranca/
├── SKILL.md                     ← roteiro que a IA segue
├── GUIA_COMPLETO.md             ← o guia (9 partes):
│                                   1 conceitos para leigos · 2 as 20 regras de ouro · 3 roteiro da auditoria
│                                   4 catálogo de ~45 falhas (achar / corrigir / confirmar / armadilha)
│                                   5 publicar sem quebrar · 6 padrões aprovados · 7 incidentes reais
│                                   8 checklist final · 9 vazamento pelo navegador (F12)
├── referencias/
│   ├── consultas.sql            ← diagnóstico do banco (só leitura)
│   ├── padroes-correcao.sql     ← modelos de migration (fechar função, policies, storage, travas, verificação)
│   ├── pecas-de-codigo.md       ← código pronto: autorização, link assinado, CORS, IP e limites,
│   │                               HTML seguro, links seguros, storage privado, webhook, hierarquia
│   └── ferramentas.md           ← todas as skills e ferramentas, e como usar em outras IAs
└── scripts/
    ├── teste-visitante.mjs      ← tenta ler tudo só com a chave pública e aponta vazamentos
    ├── alvos-visitante.sql      ← lista o que o visitante alcança
    ├── conferir-endpoints.mjs   ← confere endpoints com tokens falsos (antes e depois de publicar)
    ├── deno-check-todas.sh      ← erros de tipo em todas as Edge Functions
    └── procurar-segredos.sh     ← chaves no código e no histórico do git (diz se o JWT é público ou de serviço)
prompts/
├── claude-code.md               ← como pedir no Claude Code
└── outras-ias.md                ← prompt pronto para qualquer outra IA
```

## Os princípios por trás de tudo

1. **A chave pública do site é pública.** A segurança tem que funcionar com ela nas mãos de um estranho.
2. **O que chega ao navegador é público**, mesmo que a tela não mostre.
3. **Teste com o papel errado** (visitante, funcionário sem permissão, bloqueado), não com o seu.
4. **O banco ao vivo é a verdade**; toda mudança vira migration.
5. **Prove com evidência**: um `[]` numa tabela vazia não prova proteção.
6. **Nada muda sem aprovação**, e todo "corrigido" diz o que **não** foi testado.

## Requisitos

- [Supabase CLI](https://supabase.com/docs/guides/cli) (`supabase login` + `supabase link`)
- Node.js 18+ (scripts e instalador)
- Opcional: [Deno](https://deno.land), gitleaks ou trufflehog, semgrep

## Licença

MIT. Use, adapte e compartilhe.
