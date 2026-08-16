-- Adds a client-generated idempotency key to waste_ledger_events so a
-- retried insert after an ambiguous failure (e.g. the network drops after
-- the write succeeds but before the client sees the response) cannot
-- double-insert and double-fire the trg_increment_ledger_totals trigger.
--
-- Nullable, with a partial unique index (not NOT NULL / not a plain unique
-- constraint): existing rows have no key and are not backfilled with a
-- synthetic one; only new inserts going forward populate and are
-- constrained by it. See CLAUDE.md Roadmap item 27 for the full design.

alter table public.waste_ledger_events
  add column idempotency_key text;

create unique index waste_ledger_events_idempotency_key_uidx
  on public.waste_ledger_events (idempotency_key)
  where idempotency_key is not null;
