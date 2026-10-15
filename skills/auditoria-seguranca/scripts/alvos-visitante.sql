-- Lista o que o VISITANTE (papel anon) consegue alcançar: tabelas/views com SELECT, funções com EXECUTE
-- (exceto gatilhos) e todos os buckets. Saída usada por teste-visitante.mjs.
-- Uso:  supabase db query --linked -f alvos-visitante.sql > alvos.json
select 'tabela' as tipo, c.relname as nome, null::text as volatil, null::int as nargs, null::bool as definer
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r','v','m','f','p')
  and has_table_privilege('anon', c.oid, 'select')
union all
select 'funcao', p.proname, p.provolatile::text, p.pronargs::int, p.prosecdef
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')
  and p.prorettype <> 'trigger'::regtype
union all
select 'bucket', id, null, null, public from storage.buckets
order by 1, 2;
