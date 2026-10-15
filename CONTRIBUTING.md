# Como contribuir

Obrigado por querer ajudar! Este guia nasceu de um projeto só; quanto mais gente rodar e contar o que achou, mais
completo ele fica para todo mundo. **Você não precisa ser especialista em segurança nem saber usar git** para contribuir.

## Formas de contribuir (da mais fácil para a mais técnica)

| Você quer… | Faça isto | Precisa saber git? |
|---|---|---|
| Contar que rodou no seu projeto e o que achou | Abra uma issue **"Rodei no meu projeto"** | Não |
| Avisar de um erro, comando que não funciona ou trecho confuso | Abra uma issue **"Erro no guia"** | Não |
| Sugerir uma falha que não está no guia | Abra uma issue **"Falha nova"** | Não |
| Explicar uma solução (ou um jeito melhor de corrigir algo) | Abra uma issue **"Tenho a solução"**, ou mande um pull request | Não |
| Corrigir um texto ou acrescentar uma falha você mesmo | Pull request pelo site (passo a passo abaixo) | Não |
| Melhorar scripts, acrescentar outra stack (Firebase, Prisma, Next…) | Pull request pela linha de comando | Sim |

---

## 1. Antes de tudo: como achar falhas no seu projeto

A melhor contribuição é **rodar o roteiro no seu projeto** e contar o que apareceu (sem expor nada, ver regras abaixo).

**Caminho rápido (30 minutos):**
1. **Teste do navegador:** abra o seu site numa janela anônima, aperte F12 → **Rede** → filtro **Fetch/XHR**, use as
   páginas públicas e veja as respostas. Procure CPF, telefone, e-mail, dados de outras pessoas, tokens.
   Passo a passo: [GUIA_COMPLETO.md, Parte 9](skills/auditoria-seguranca/GUIA_COMPLETO.md#parte-9--vazamento-pelo-navegador-abas-rede-console-e-aplicação-f12).
2. **Teste do visitante:** com o Supabase CLI ligado ao seu projeto:
   ```bash
   supabase db query --linked -f skills/auditoria-seguranca/scripts/alvos-visitante.sql > alvos.json
   node skills/auditoria-seguranca/scripts/teste-visitante.mjs caminho/do/seu/projeto/.env alvos.json
   ```
3. **Segredos:** `bash skills/auditoria-seguranca/scripts/procurar-segredos.sh caminho/do/seu/projeto`
4. **Banco:** rode as consultas de [consultas.sql](skills/auditoria-seguranca/referencias/consultas.sql) no SQL Editor.

**Caminho completo:** peça à sua IA para seguir a skill (veja o [README](README.md)) ou siga a Parte 3 do guia à mão.

**Achou algo que o guia não cobre?** Ótimo: é exatamente isso que queremos. Veja o item 3.

---

## 2. Regras de ouro para contribuir (importante!)

1. **Nunca publique dados reais:** nada de CPF, telefone, e-mail, nomes de clientes, prints com dados, chaves,
   tokens, IDs de projeto (`abcdefgh...supabase.co`), domínios privados ou URLs internas. Troque por exemplos
   (`<PROJECT_REF>`, `cliente A`, `000.000.000-00`).
2. **Corrija primeiro, conte depois.** Se a falha está **aberta** no seu sistema em produção, feche antes de publicar
   os detalhes. Issues são públicas.
3. **Só teste o que é seu** ou o que você tem autorização para testar. Não abra issue sobre falha **no sistema de outra
   pessoa ou empresa**: avise o dono em particular.
4. **Falha nos próprios scripts deste repositório** (ex.: um script que vaza algo): não abra issue pública. Use a aba
   **Security → Report a vulnerability** do repositório (relato privado).
5. Escreva do jeito que você explicaria para um colega que não é técnico. Este guia é para leigos também.

---

## 3. Contribuindo pelo site do GitHub (sem instalar nada)

### 3.1 Abrir uma issue (relato, dúvida, erro, falha nova)
1. Crie uma conta grátis em https://github.com (se ainda não tiver).
2. Abra https://github.com/dmanske/auditoria-seguranca-supabase/issues e clique em **New issue**.
3. Escolha o modelo: **Falha nova**, **Erro no guia** ou **Rodei no meu projeto**.
4. Preencha os campos (o modelo explica cada um) e clique em **Submit new issue**.

Pronto. A gente lê, conversa nos comentários e, se for o caso, incorpora ao guia com o seu crédito.

### 3.2 Corrigir ou acrescentar texto você mesmo (pull request pelo navegador)
1. No repositório, abra o arquivo que quer mudar (ex.: `skills/auditoria-seguranca/GUIA_COMPLETO.md`).
2. Clique no **lápis** (✏️ "Edit this file") no canto superior direito do arquivo.
   O GitHub cria automaticamente uma **cópia sua** do repositório (um "fork").
3. Faça a mudança no editor. Para acrescentar uma falha nova, copie o modelo do item 5 abaixo.
4. Clique em **Commit changes…**, escreva em uma linha o que mudou (ex.: "Falha nova: bucket público com fotos de documentos")
   e clique em **Propose changes**.
5. Na tela seguinte, clique em **Create pull request**, conte o porquê da mudança e envie.

Pronto: isso é um **pull request** (PR), um pedido para incluir a sua mudança. A gente revisa, pode sugerir ajustes
nos comentários, e faz o "merge" (inclui) quando estiver tudo certo.

---

### 3.3 Já sei a solução: como explicar

Você tem dois caminhos. Escolha o que for mais confortável:

**a) Descrever numa issue (mais fácil).** Abra uma issue com o modelo **"Tenho a solução"**. Ele pede, nesta ordem:
1. **Qual falha:** o código e o nome no guia (ex.: "A9 — Função SECURITY DEFINER executável por quem não devia"), ou "nova".
2. **O problema** em uma ou duas frases.
3. **A solução passo a passo**, incluindo a ordem de publicação se importar (ex.: "primeiro a migration, depois as funções").
4. **O código** (SQL, TypeScript, configuração), se tiver.
5. **Como testar** que funcionou: o teste que qualquer um consegue repetir (ex.: "o visitante passa a receber o erro 42501").
6. **O que pode quebrar** e como reverter.
7. **Onde você testou** (stack, há quanto tempo em produção). Se for só uma ideia ainda não testada, diga isso: também é útil.

A gente transforma no formato do guia e dá o crédito para você.

**b) Mandar a solução pronta (pull request).** Edite o guia direto (passo 3.2 pelo site, ou item 4 pela linha de comando):
- **Falha que já existe e você tem um jeito melhor:** edite o item dela na Parte 4 do `GUIA_COMPLETO.md` (campos
  "Como corrigir", "Como confirmar", "Armadilha") e explique no pull request por que o seu jeito é melhor (mais
  simples, mais seguro, mais barato, cobre um caso que o atual não cobre).
- **Código reutilizável:** coloque em `referencias/pecas-de-codigo.md` (servidor/front) ou
  `referencias/padroes-correcao.sql` (banco), com um comentário dizendo o que resolve, e aponte no item da falha.
- **Outra stack** (Firebase, Prisma, Next.js…): acrescente uma subseção "Em <stack>" dentro do item da falha, sem apagar a versão Supabase.

**Dica para explicar bem:** pense em três perguntas que o leitor vai fazer: *"o que eu mudo?"*, *"como sei que
funcionou?"* e *"o que pode quebrar?"*. Se a sua explicação responde às três, está ótima.

---

## 4. Contribuindo pela linha de comando (git)

Para mudanças maiores (vários arquivos, scripts novos):

```bash
# 1. Faça um fork pelo site (botão "Fork" no topo do repositório) e clone a SUA cópia
git clone https://github.com/<seu-usuario>/auditoria-seguranca-supabase
cd auditoria-seguranca-supabase

# 2. Crie uma branch com um nome que diga o que é
git checkout -b falha-nova-bucket-publico

# 3. Faça as mudanças. Se mexeu em script, teste num projeto SEU:
#    node skills/auditoria-seguranca/scripts/teste-visitante.mjs ...
#    bash -n skills/auditoria-seguranca/scripts/*.sh     # confere a sintaxe dos .sh

# 4. Commit e push para a SUA cópia
git add -A
git commit -m "Falha nova: bucket público com fotos de documentos"
git push -u origin falha-nova-bucket-publico

# 5. Abra o pull request
gh pr create --fill          # com o GitHub CLI, ou pelo botão "Compare & pull request" no site
```

Para manter a sua cópia atualizada com a original:
```bash
git remote add original https://github.com/dmanske/auditoria-seguranca-supabase
git pull original main
```

---

## 5. Modelo para uma falha nova no guia

Use o mesmo formato das outras (Parte 4 do `GUIA_COMPLETO.md`) e coloque no grupo certo
(A banco, B edge functions, C dados públicos e links, D front, E negócio e pagamentos, F processo):

```markdown
#### X99. <Nome curto da falha>
- **Em palavras simples:** <o risco, como você explicaria para alguém que não programa>
- **Caso real:** <o que aconteceu, sem identificar o projeto>
- **Como achar:** <consulta SQL, comando, grep ou o que olhar no F12>
- **Como corrigir:** <o padrão da correção; código em referencias/ se for longo>
- **Como confirmar:** <o teste que prova que fechou (ex.: erro 42501, 401, resposta sem o campo)>
- **Armadilha:** <o que pode quebrar ou enganar ao corrigir>
```

Se a correção tem código reutilizável, acrescente em `referencias/pecas-de-codigo.md` (servidor/front) ou
`referencias/padroes-correcao.sql` (banco). Se tem uma consulta de diagnóstico, em `referencias/consultas.sql`.
Se vale uma linha no checklist final (Parte 8), acrescente também.

## 6. O que a gente olha num pull request

- Não tem dado real nem segredo (regra 1).
- A explicação "em palavras simples" está clara para leigo.
- O "como achar" e o "como confirmar" são verificáveis (alguém consegue repetir).
- Script novo: só lê por padrão, não imprime valores sensíveis, roda com Node 18+ ou bash, e explica o uso no começo do arquivo.
- Sem dependências pesadas novas.

## Licença

Ao contribuir, você concorda que a sua contribuição fica sob a licença MIT do repositório.
