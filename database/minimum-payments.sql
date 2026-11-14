alter table public.finance_items add column if not exists payment_history jsonb not null default '[]'::jsonb;
create or replace function public.finance_pay_minimum(p_item_id uuid)
returns public.finance_items
language plpgsql security invoker set search_path = '' as $$
declare
  item public.finance_items;
  payment_date date := (current_timestamp at time zone 'America/New_York')::date;
  billing_month text := to_char(payment_date, 'YYYY-MM');
  amount numeric;
begin
  select * into item from public.finance_items where id = p_item_id for update;
  if not found then raise exception 'Debt unavailable. Refresh your household connection.'; end if;
  if item.type <> 'debt' then raise exception 'Only debts can be marked paid.'; end if;
  if exists (select 1 from jsonb_array_elements(item.payment_history) p where p->>'month' = billing_month) then
    return item;
  end if;
  amount := least(round(item.balance,2), round(item.payment,2));
  if amount <= 0 then raise exception 'The debt must have a positive balance and minimum payment.'; end if;
  update public.finance_items set balance = balance - amount,
    payment_history = payment_history || jsonb_build_array(jsonb_build_object('month',billing_month,'date',payment_date,'amount',amount,'recordedAt',current_timestamp)),
    updated_at = clock_timestamp()
  where id = p_item_id returning * into item;
  return item;
end;
$$;
revoke all on function public.finance_pay_minimum(uuid) from public, anon;
grant execute on function public.finance_pay_minimum(uuid) to authenticated;
