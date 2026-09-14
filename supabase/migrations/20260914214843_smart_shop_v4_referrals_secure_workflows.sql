alter table public.store_referrals
  add column if not exists admin_notes text,
  add column if not exists contacted_at timestamptz,
  add column if not exists reviewed_by uuid references auth.users(id) on delete set null;

create or replace function public.get_or_create_my_referral_code()
returns text language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_code text;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select code into v_code from public.referral_codes where owner_user_id=v_uid and active order by created_at limit 1;
 if v_code is null then
   loop
     v_code:='SMART-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
     begin insert into public.referral_codes(owner_user_id,code) values(v_uid,v_code); exit;
     exception when unique_violation then null; end;
   end loop;
 end if;
 return v_code;
end $$;

create or replace function public.claim_referral_code(p_code text)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_owner uuid; v_code_id uuid; v_id uuid;
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 select id,owner_user_id into v_code_id,v_owner from public.referral_codes
 where upper(code)=upper(trim(p_code)) and active limit 1;
 if v_code_id is null then raise exception 'INVALID_REFERRAL_CODE'; end if;
 if v_owner=v_uid then raise exception 'SELF_REFERRAL_NOT_ALLOWED'; end if;
 if exists(select 1 from public.referrals where referred_user_id=v_uid) then raise exception 'REFERRAL_ALREADY_CLAIMED'; end if;
 if exists(select 1 from public.orders where user_id=v_uid and status_code='delivered') then raise exception 'FIRST_ORDER_ALREADY_COMPLETED'; end if;
 insert into public.referrals(referrer_user_id,referred_user_id,referral_code_id,status)
 values(v_owner,v_uid,v_code_id,'registered') returning id into v_id;
 return v_id;
end $$;

create or replace function public.submit_store_referral(
 p_store_name text,p_contact_name text default null,p_phone_whatsapp text default null,
 p_category text default null,p_city text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid(); v_id uuid; v_name text:=trim(p_store_name); v_city text:=trim(p_city); v_phone text:=regexp_replace(coalesce(p_phone_whatsapp,''),'[^0-9]','','g');
begin
 if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
 if length(v_name)<2 then raise exception 'STORE_NAME_REQUIRED'; end if;
 if length(v_city)<2 then raise exception 'CITY_REQUIRED'; end if;
 if length(v_phone)<8 and length(trim(coalesce(p_contact_name,'')))<2 then raise exception 'CONTACT_REQUIRED'; end if;
 select id into v_id from public.store_referrals
 where status not in ('not_interested','duplicate')
 and ((v_phone<>'' and regexp_replace(coalesce(phone_whatsapp,''),'[^0-9]','','g')=v_phone)
      or (lower(trim(store_name))=lower(v_name) and lower(trim(city))=lower(v_city)))
 order by created_at desc limit 1;
 if v_id is not null then return v_id; end if;
 insert into public.store_referrals(referrer_user_id,store_name,contact_name,phone_whatsapp,category,city,notes)
 values(v_uid,v_name,nullif(trim(p_contact_name),''),nullif(trim(p_phone_whatsapp),''),nullif(trim(p_category),''),v_city,nullif(trim(p_notes),''))
 returning id into v_id;
 return v_id;
end $$;

create or replace function public.admin_update_store_referral(
 p_id uuid,p_status text,p_admin_notes text default null,p_converted_store_id uuid default null)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_uid uuid:=auth.uid();
begin
 if v_uid is null or not public.has_platform_role(array['master','admin','operations']) then raise exception 'FORBIDDEN'; end if;
 if p_status not in ('new','contacted','interested','onboarding','converted','not_interested','duplicate') then raise exception 'INVALID_STATUS'; end if;
 if p_status='converted' and p_converted_store_id is null then raise exception 'CONVERTED_STORE_REQUIRED'; end if;
 update public.store_referrals set status=p_status,admin_notes=nullif(trim(p_admin_notes),''),
   converted_store_id=case when p_status='converted' then p_converted_store_id else converted_store_id end,
   contacted_at=case when p_status in ('contacted','interested','onboarding','converted') then coalesce(contacted_at,now()) else contacted_at end,
   reviewed_by=v_uid,updated_at=now() where id=p_id;
 if not found then raise exception 'STORE_REFERRAL_NOT_FOUND'; end if;
 insert into public.audit_logs(actor_user_id,actor_role,action,entity_type,entity_id,metadata)
 values(v_uid,'operations','STORE_REFERRAL_STATUS_UPDATED','store_referral',p_id::text,jsonb_build_object('status',p_status));
end $$;

revoke all on public.referral_codes,public.referrals,public.store_referrals from anon;
revoke all on public.referral_codes,public.referrals,public.store_referrals from authenticated;
grant select on public.referral_codes,public.referrals,public.store_referrals to authenticated;

drop policy if exists "active referral codes can be looked up" on public.referral_codes;
drop policy if exists "users can create own referral codes" on public.referral_codes;
drop policy if exists "users can read own referral codes" on public.referral_codes;
drop policy if exists "referred user can register referral with valid code" on public.referrals;
drop policy if exists "users can read own referral activity" on public.referrals;
drop policy if exists "admins manage store referrals" on public.store_referrals;
drop policy if exists "users read own store referrals" on public.store_referrals;
drop policy if exists "users submit store referrals" on public.store_referrals;

create policy referral_codes_read on public.referral_codes for select to authenticated
using(owner_user_id=auth.uid() or public.has_platform_role(array['master','admin','operations']));
create policy referrals_read on public.referrals for select to authenticated
using(referrer_user_id=auth.uid() or referred_user_id=auth.uid() or public.has_platform_role(array['master','admin','operations']));
create policy store_referrals_read on public.store_referrals for select to authenticated
using(referrer_user_id=auth.uid() or public.has_platform_role(array['master','admin','operations']));

revoke all on function public.get_or_create_my_referral_code() from public,anon;
revoke all on function public.claim_referral_code(text) from public,anon;
revoke all on function public.submit_store_referral(text,text,text,text,text,text) from public,anon;
revoke all on function public.admin_update_store_referral(uuid,text,text,uuid) from public,anon;
grant execute on function public.get_or_create_my_referral_code() to authenticated;
grant execute on function public.claim_referral_code(text) to authenticated;
grant execute on function public.submit_store_referral(text,text,text,text,text,text) to authenticated;
grant execute on function public.admin_update_store_referral(uuid,text,text,uuid) to authenticated;
revoke all on function public.qualify_referral_on_delivered_order() from public,anon,authenticated;
