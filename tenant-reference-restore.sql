begin;
create or replace function family_private.check_tenant_ref() returns trigger language plpgsql security definer set search_path='' as $$declare target uuid;value text:=to_jsonb(new)->>TG_ARGV[1];begin
 if value is not null then execute format('select tenant_id from %s where %I::text=$1',TG_ARGV[0]::regclass,TG_ARGV[2])into target using value;
 if target is not null and target<>new.tenant_id then raise exception 'لا يمكن الربط بين كيانات مختلفة';end if;end if;return new;end$$;
do $$declare r record;begin
 for r in select c.conrelid,c.conname,format('%I.%I',n.nspname,p.relname)parent,l.attname local_col,f.attname ref_col from pg_constraint c join pg_class p on p.oid=c.confrelid join pg_namespace n on n.oid=p.relnamespace join pg_attribute l on l.attrelid=c.conrelid and l.attnum=c.conkey[1] join pg_attribute f on f.attrelid=c.confrelid and f.attnum=c.confkey[1] where c.contype='f' and array_length(c.conkey,1)=1 and n.nspname in('public','family_private') and p.relname not in('tenants','platform_admins') and c.connamespace in('public'::regnamespace,'family_private'::regnamespace)loop
 execute format('drop trigger if exists %I on %s','tenant_'||r.conname,r.conrelid::regclass);
 execute format('create trigger %I before insert or update on %s for each row execute function family_private.check_tenant_ref(%L,%L,%L)','tenant_'||r.conname,r.conrelid::regclass,r.parent,r.local_col,r.ref_col);
 end loop;
end$$;
commit;
