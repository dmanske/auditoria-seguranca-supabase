-- =====================================================================================================
-- Consultas de diagnóstico de segurança (Supabase / Postgres) — SÓ LEITURA
-- Rode no SQL Editor do Supabase ou com:  supabase db query --linked "<consulta>"
-- Cada seção diz o que procura e como ler o resultado. Numeração citada no GUIA_COMPLETO.md.
-- =====================================================================================================


-- §1. Tabelas SEM RLS (deveria voltar vazio) ------------------------------------------------------------
select c.relname as tabela
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p') and not c.relrowsecurity
order by 1;

-- §1b. Visão geral: toda tabela, se tem RLS e quantas policies
select c.relname as tabela, c.relrowsecurity as rls,
       (select count(*) from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname) as policies
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','p')
order by rls, policies, tabela;


-- §2. Policies para visitante/público SEM nenhuma condição real ---------------------------------------
--     Pega USING(true), IS NOT NULL e tudo que não depende de login, header ou permissão.
--     Ajuste a lista de funções "de permissão" do seu projeto na expressão regular.
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and ('anon' = any(roles) or 'public' = any(roles))
  and coalesce(qual, '')       !~ '(auth\.|request\.headers|user_has_permission|is_admin|is_equipe)'
  and coalesce(with_check, '') !~ '(auth\.|request\.headers|user_has_permission|is_admin|is_equipe)'
order by tablename, cmd;

-- §2a. Policies de ESCRITA abertas (INSERT/UPDATE/DELETE/ALL) para visitante
select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname in ('public','storage')
  and ('anon' = any(roles) or 'public' = any(roles))
  and cmd in ('INSERT','UPDATE','DELETE','ALL')
  and (coalesce(with_check,'true') in ('true','') or coalesce(qual,'true') in ('true',''))
order by schemaname, tablename;

-- §2b. Policies que só olham "tem login" (inclui bloqueado, sem permissão e conta criada por estranho)
select schemaname, tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname in ('public','storage')
  and (coalesce(qual,'') || ' ' || coalesce(with_check,'')) ~*
      '(auth\.role\(\)\s*=\s*''authenticated''|auth\.uid\(\)\s+is\s+not\s+null|^\s*true\s*$)'
order by schemaname, tablename;

-- §2c. Policies "disfarçadas": comparam se o token EXISTE, não se é o do chamador
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public' and qual ~* 'token[a-z_]*\s+is\s+not\s+null';

-- §2d. Policies de UPDATE sem WITH CHECK (permite reatribuir a linha a outro dono)
select tablename, policyname, roles, qual
from pg_policies
where schemaname = 'public' and cmd in ('UPDATE','ALL') and with_check is null;


-- §3. Funções SECURITY DEFINER executáveis por visitante ou por qualquer logado ------------------------
select p.oid::regprocedure as funcao,
       has_function_privilege('anon', p.oid, 'execute')          as anon_executa,
       has_function_privilege('authenticated', p.oid, 'execute') as logado_executa,
       p.prorettype::regtype                                       as retorna
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
order by anon_executa desc, 1;

-- §3b. Das acima, as que NÃO conferem quem chama no corpo (suspeitas principais)
--      Ajuste os nomes das suas funções de permissão na expressão regular.
select p.oid::regprocedure as funcao,
       has_function_privilege('anon', p.oid, 'execute') as anon_executa
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and p.prorettype <> 'trigger'::regtype
  and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))
  and p.prosrc !~* '(auth\.uid\(\)|auth\.role\(\)|is_equipe|user_has_permission|tem_alguma_permissao|is_admin)'
order by 2 desc, 1;

-- §3c. Funções que leem segredos (Vault) — NINGUÉM de fora pode executar
select p.oid::regprocedure as funcao,
       has_function_privilege('anon', p.oid, 'execute') as anon,
       has_function_privilege('authenticated', p.oid, 'execute') as logado
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosrc ~* '(vault\.|decrypted_secrets|secret|service_role)';

-- §3d. Funções perigosas conhecidas (SQL livre, gatilhos, cron)
select p.oid::regprocedure, has_function_privilege('anon', p.oid, 'execute') anon,
       has_function_privilege('authenticated', p.oid, 'execute') logado
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname ~* '(exec|query|sql|disable_trigger|enable_trigger|cron|delete_|drop_|truncate)';


-- §4. Grants de TABELA por papel (o padrão do Supabase dá ALL para anon e authenticated) ----------------
select grantee, privilege_type, count(*) as tabelas
from information_schema.role_table_grants
where table_schema = 'public' and grantee in ('anon','authenticated')
group by 1, 2 order by 1, 2;

-- §4b. Tabelas onde o visitante pode GRAVAR (privilégio, antes da RLS)
select table_name, string_agg(privilege_type, ', ' order by privilege_type) as privilegios
from information_schema.role_table_grants
where table_schema = 'public' and grantee = 'anon'
  and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE')
group by 1 order by 1;


-- §5. Privilégios PADRÃO (o que toda tabela/função nova recebe) ---------------------------------------
select defaclrole::regrole as dono, defaclnamespace::regnamespace as schema, defaclobjtype as tipo, defaclacl
from pg_default_acl;


-- §6. Storage: buckets públicos e policies --------------------------------------------------------------
select id, public, file_size_limit, allowed_mime_types from storage.buckets order by public desc, id;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by cmd, policyname;

-- §6b. Quantos arquivos e de que tipo em cada bucket público (sem mostrar nomes)
select bucket_id, count(*) as arquivos, string_agg(distinct coalesce(metadata->>'mimetype','?'), ', ') as tipos
from storage.objects
where bucket_id in (select id from storage.buckets where public)
group by 1 order by 2 desc;


-- §7. Views que o visitante/logado consultam SEM security_invoker (rodam como dono e furam a RLS) -----
select c.relname as view, c.relkind as tipo,
       has_table_privilege('anon', c.oid, 'select') as anon_le,
       coalesce(array_to_string(c.reloptions, ','), '-') as opcoes
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('v','m')
  and (has_table_privilege('anon', c.oid, 'select') or has_table_privilege('authenticated', c.oid, 'select'))
  and not coalesce(c.reloptions::text[] @> array['security_invoker=true'], false)
order by 3 desc, 1;


-- §8. Funções SECURITY DEFINER sem search_path fixo -----------------------------------------------------
select p.oid::regprocedure as funcao
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%')
order by 1;

-- §8b. Gerar os comandos de correção (revise antes de rodar; funções com extensões precisam de 'extensions')
select format('alter function %s set search_path = public, pg_temp;', p.oid::regprocedure)
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosecdef
  and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) c where c like 'search_path=%');


-- §9. Crons com chave escrita no comando (a chave fica legível no banco) -------------------------------
select jobname, schedule, left(command, 120) as inicio_do_comando
from cron.job
where command ~* '(bearer\s+ey|service_role|apikey)';


-- §10. SQL dinâmico (possível injeção) -----------------------------------------------------------------
select p.oid::regprocedure as funcao
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.prosrc ~* 'execute\s' ;
-- Leia cada uma: identificador com format('%I'), valor com USING; nunca concatenar texto do usuário.


-- §11. Token/segredo gravado em log (ajuste tabela e coluna) ------------------------------------------
-- select count(*) from public.<tabela_de_log> where <coluna_url> ~ '[?#](token|t|key|code)=';


-- §12. Policies que leem a tabela de papéis/permissões SEM conferir se o usuário está ativo ------------
--      Ajuste o nome da tabela de permissões e da coluna "ativo".
select schemaname, tablename, policyname
from pg_policies
where schemaname in ('public','storage')
  and (coalesce(qual,'') || coalesce(with_check,'')) like '%usuarios_permissoes%'
  and (coalesce(qual,'') || coalesce(with_check,'')) not like '%ativo%';


-- §13. Colunas sensíveis por nome (para saber onde olhar com cuidado) ----------------------------------
select table_name, column_name
from information_schema.columns
where table_schema = 'public'
  and column_name ~* '(cpf|rg|cnpj|telefone|celular|whats|email|nascimento|endereco|cep|senha|password|hash|token|secret|chave|pix|cartao|card)'
order by 1, 2;


-- §14. Quem usa uma função (antes de restringi-la): policies e outras funções -------------------------
-- select schemaname, tablename, policyname from pg_policies where qual ~ 'nome_da_funcao' or with_check ~ 'nome_da_funcao';
-- select p.oid::regprocedure from pg_proc p where p.prosrc ~ 'nome_da_funcao';


-- §15. Conferências pontuais ---------------------------------------------------------------------------
-- select has_function_privilege('authenticated', 'public.minha_funcao(uuid)', 'execute');
-- select has_table_privilege('anon', 'public.minha_tabela', 'select');
-- select pg_get_functiondef('public.minha_funcao(uuid)'::regprocedure);
-- select conname, pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.minha_tabela'::regclass;
