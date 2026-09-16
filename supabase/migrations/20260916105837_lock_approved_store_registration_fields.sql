create or replace function public.update_my_store_settings(
  p_store_id uuid,
  p_name text,
  p_description text default null,
  p_category text default null,
  p_phone text default null,
  p_whatsapp text default null,
  p_email text default null,
  p_business_hours text default null,
  p_logo_url text default null,
  p_delivery_modes text[] default null,
  p_store_delivery_fee numeric default null
)
returns void
language plpgsql
security definer
set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v_modes text[];
  v_fee numeric;
begin
  if v_uid is null then raise exception 'authentication required'; end if;
  if not public.is_store_member(p_store_id) and not public.is_platform_admin() then raise exception 'not authorized'; end if;

  v_modes := coalesce(p_delivery_modes,array['pickup','smart_partner']::text[]);
  if cardinality(v_modes)=0 or exists(select 1 from unnest(v_modes) m where m not in ('pickup','store_delivery','smart_partner')) then
    raise exception 'invalid delivery mode';
  end if;

  select store_delivery_fee into v_fee from public.stores where id=p_store_id;
  if not found then raise exception 'store not found'; end if;
  v_fee := coalesce(p_store_delivery_fee,v_fee,8.00);
  if v_fee < 0 then raise exception 'invalid store delivery fee'; end if;

  update public.stores
  set
      name=case when approval_status='approved' then name else coalesce(nullif(trim(p_name),''),name) end,
      category=case when approval_status='approved' then category else coalesce(nullif(trim(p_category),''),category) end,
      phone=case when approval_status='approved' then phone else nullif(trim(p_phone),'') end,
      whatsapp=case when approval_status='approved' then whatsapp else nullif(trim(p_whatsapp),'') end,
      email=case when approval_status='approved' then email else nullif(trim(p_email),'') end,
      description=nullif(trim(p_description),''),
      business_hours=nullif(trim(p_business_hours),''),
      logo_url=nullif(trim(p_logo_url),''),
      delivery_modes=v_modes,
      store_delivery_fee=round(v_fee,2),
      updated_at=now()
  where id=p_store_id;

  insert into public.audit_logs(actor_user_id,actor_role,action,entity_type,entity_id,metadata)
  values(v_uid,'merchant','update_store_operational_settings','store',p_store_id::text,
         jsonb_build_object('delivery_modes',v_modes,'store_delivery_fee',round(v_fee,2),'business_hours',p_business_hours));
end
$function$;

revoke all on function public.update_my_store_settings(uuid,text,text,text,text,text,text,text,text,text[],numeric) from public,anon;
grant execute on function public.update_my_store_settings(uuid,text,text,text,text,text,text,text,text,text[],numeric) to authenticated;
