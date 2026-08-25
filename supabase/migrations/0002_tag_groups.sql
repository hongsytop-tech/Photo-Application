-- 태그 분류 (0001 이후 추가)
--
-- 이미 0001 을 돌린 프로젝트에 덧붙이는 변경입니다. 통째로 다시 실행해도
-- 안전하도록 create/alter 모두 if not exists 를 씁니다.

-- 태그를 묶는 분류. 사진이 아니라 태그를 담습니다.
create table if not exists public.photo_tag_groups (
  user_id    uuid not null references auth.users (id) on delete cascade,
  id         text not null,
  name       text not null default '',
  sort_order integer not null default 0,
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, id)
);
alter table public.photo_tag_groups enable row level security;
drop policy if exists "photo_tag_groups_own" on public.photo_tag_groups;
create policy "photo_tag_groups_own" on public.photo_tag_groups
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 태그가 어느 분류에 속하는지. 빈 문자열이면 미분류입니다.
-- 분류를 몰랐던 예전 기기가 올린 태그도 이 기본값 덕에 그대로 미분류가 됩니다.
alter table public.photo_tag_defs
  add column if not exists group_id text not null default '';
