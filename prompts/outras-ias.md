# Prompt para outras IAs (Cursor, Kiro, ChatGPT/Codex, Gemini, Copilot…)

**Antes de colar:**
1. Abra o assistente **na pasta do projeto** (Cursor, Kiro, Gemini CLI, Codex CLI). Se for um chat sem acesso
   aos arquivos (ChatGPT web), anexe o `GUIA_COMPLETO.md`, o `referencias/consultas.sql` e os arquivos do projeto
   que ele pedir.
2. Se possível, deixe o assistente rodar comandos no terminal. Se não puder, ele te diz o que rodar e você cola o resultado.
3. Se o seu assistente aceita skills (Kiro, Gemini CLI, Cursor com `.agent/skills`), copie a pasta
   `skills/auditoria-seguranca` para a pasta de skills dele e diga "use a skill auditoria-seguranca".

---

## Prompt (copie tudo)

```
Você vai fazer uma auditoria de segurança deste projeto (front + Supabase: Postgres com RLS, Storage e Edge
Functions). Siga o roteiro do arquivo GUIA_COMPLETO.md (Parte 3), use as consultas de referencias/consultas.sql
e os scripts de scripts/. Responda em português, em linguagem simples (eu posso ser leigo).

REGRAS
1. Primeiro só leitura. NÃO altere banco, funções, storage, segredos nem configuração sem eu aprovar.
2. Cada achado com evidência: arquivo:linha ou a consulta e o resultado. Verifique achado grave antes de me
   reportar como fato. Diga o que não conseguiu verificar.
3. O banco ao vivo é a verdade (consulte o catálogo; dumps e migrations antigas podem estar desatualizados).
   Para rodar SQL: supabase db query --linked "<SQL>" (ou me peça para rodar no SQL Editor do Supabase).
4. Prove o que vaza: teste como VISITANTE (só a chave pública do .env), como funcionário sem permissão e como
   usuário bloqueado. Lembre: tabela vazia devolve [] mesmo aberta; a prova de proteção é o erro 42501/401/403
   ou a policy lida no catálogo.
5. Nunca use dados reais nos testes (tokens falsos, dados fictícios). Testes de gravação só em transação
   desfeita (begin; ...; rollback;). Nunca teste envio em massa (WhatsApp, e-mail) contra produção.
   Nunca rode "supabase config push". Nunca imprima o .env.
6. Lembre que verify_jwt = true NÃO significa "logado" (a chave pública passa) e que funções com service_role
   ignoram a RLS: a autorização tem que estar no código.

FASES (pare no fim de cada uma e me resuma o que achou)
0. Preparar: qual projeto Supabase o site usa, CLI ligado, histórico de migrations alinhado
   (supabase db push --linked --dry-run). Pergunte o que é público de propósito.
1. Inventário: tabelas, views, funções, buckets, edge functions (e o verify_jwt), rotas públicas, webhooks,
   crons, segredos usados.
2. Banco: consultas.sql §1 a §13 + supabase db advisors --linked --type security.
3. Teste do visitante: scripts/teste-visitante.mjs.
4. Teste por perfil em transação desfeita (visitante, funcionário sem/com permissão, bloqueado, dono, servidor),
   incluindo escrita cruzada (meu id num parâmetro, id de outro em outro parâmetro).
5. Edge functions: quem pode chamar cada uma, o que faz para um estranho (ver o Grupo B do catálogo de falhas).
   Rode scripts/deno-check-todas.sh.
6. Páginas públicas e links: token, validade, revogação, limite de tentativas, respostas iguais, o que a API
   entrega além da tela, noindex, token em log. Confirme com scripts/conferir-endpoints.mjs (tokens falsos).
7. Front: XSS (dangerouslySetInnerHTML, document.write, href/src com valor do banco), segredos no bundle,
   headers de segurança, npm audit.
8. Segredos e histórico do git: scripts/procurar-segredos.sh.

ENTREGA
- docs/seguranca/auditoria-<data>.md: achados por severidade, cada um com evidência, impacto em linguagem
  simples, correção proposta e o que a correção pode afetar.
- docs/seguranca/plano-<data>.md: as correções em ordem (o mais grave e mais fácil primeiro), com a ordem de
  publicação (Parte 5 do guia).
- Uma tabela-resumo: o que vaza hoje × o que está protegido.
- Me avise NA HORA de qualquer achado crítico (dado de cliente legível por visitante, função que deixa baixar
  o banco, segredo exposto), propondo a correção sem aplicar.
```

---

## Dicas por ferramenta

- **Kiro:** copie `skills/auditoria-seguranca` para `~/.kiro/skills/` e use `@auditoria-seguranca` + o prompt.
  Regras permanentes: `.kiro/steering/seguranca.md` com a Parte 2 do guia (as 20 regras de ouro).
- **Cursor:** modo Agent; anexe `@GUIA_COMPLETO.md`. Regras permanentes: `.cursor/rules/seguranca.mdc`.
- **Gemini CLI / Codex CLI:** rode na raiz do projeto; eles executam os comandos com sua aprovação.
- **ChatGPT (web):** não acessa seu banco. Rode você as consultas no SQL Editor do Supabase, cole os resultados
  e peça a análise. Para o código, anexe os arquivos que ele pedir (comece pelas edge functions e migrations).
- **Copilot Chat:** use em modo agente com o workspace aberto; anexe o guia.

## Ferramentas sem IA que complementam

`npm audit`, `gitleaks`/`trufflehog` (segredos no histórico), `semgrep` (análise estática),
OWASP ZAP (teste do site no ar), securityheaders.com. Detalhes em `referencias/ferramentas.md`.
