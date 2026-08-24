-- 사진 메타데이터 동기화 스키마
--
-- 이 백엔드에는 **사진 파일이 절대 저장되지 않습니다.** 저장되는 것은 사진을
-- 가리키는 키(photo_key)와 사용자가 붙인 글자(메모·태그 이름·폴더 이름)뿐입니다.
--
-- 모든 테이블이 같은 규칙을 따릅니다:
--   (user_id + 자연키) 가 기본키, updated_ms 로 최신본 판별, deleted 로 tombstone.
-- 삭제를 실제 DELETE 로 하면 다른 기기의 오래된 사본이 다시 올라와 되살아나므로
-- 반드시 tombstone 으로 남깁니다.
--
-- RLS 는 전부 "본인 행만" 입니다. create policy 는 멱등하지 않아서
-- drop policy if exists 를 먼저 둡니다 (마이그레이션 재실행 안전).

-- 사진별 메모 ------------------------------------------------------------

create table if not exists public.photo_notes (
  user_id    uuid not null references auth.users (id) on delete cascade,
  photo_key text not null,
  body       text not null default '',
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, photo_key)
);

create index if not exists photo_notes_user_idx
  on public.photo_notes (user_id);

alter table public.photo_notes enable row level security;

drop policy if exists "photo_notes_select_own" on public.photo_notes;
create policy "photo_notes_select_own"
  on public.photo_notes for select
  using (auth.uid() = user_id);

drop policy if exists "photo_notes_insert_own" on public.photo_notes;
create policy "photo_notes_insert_own"
  on public.photo_notes for insert
  with check (auth.uid() = user_id);

drop policy if exists "photo_notes_update_own" on public.photo_notes;
create policy "photo_notes_update_own"
  on public.photo_notes for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "photo_notes_delete_own" on public.photo_notes;
create policy "photo_notes_delete_own"
  on public.photo_notes for delete
  using (auth.uid() = user_id);

-- 태그 사전 --------------------------------------------------------------

create table if not exists public.photo_tag_defs (
  user_id    uuid not null references auth.users (id) on delete cascade,
  id   text not null,
  name text not null default '',
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, id)
);

create index if not exists photo_tag_defs_user_idx
  on public.photo_tag_defs (user_id);

alter table public.photo_tag_defs enable row level security;

drop policy if exists "photo_tag_defs_select_own" on public.photo_tag_defs;
create policy "photo_tag_defs_select_own"
  on public.photo_tag_defs for select
  using (auth.uid() = user_id);

drop policy if exists "photo_tag_defs_insert_own" on public.photo_tag_defs;
create policy "photo_tag_defs_insert_own"
  on public.photo_tag_defs for insert
  with check (auth.uid() = user_id);

drop policy if exists "photo_tag_defs_update_own" on public.photo_tag_defs;
create policy "photo_tag_defs_update_own"
  on public.photo_tag_defs for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "photo_tag_defs_delete_own" on public.photo_tag_defs;
create policy "photo_tag_defs_delete_own"
  on public.photo_tag_defs for delete
  using (auth.uid() = user_id);

-- 사진 ↔ 태그 ------------------------------------------------------------

create table if not exists public.photo_tag_links (
  user_id    uuid not null references auth.users (id) on delete cascade,
  photo_key text not null,
  tag_id    text not null,
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, photo_key, tag_id)
);

create index if not exists photo_tag_links_user_idx
  on public.photo_tag_links (user_id, tag_id);

alter table public.photo_tag_links enable row level security;

drop policy if exists "photo_tag_links_select_own" on public.photo_tag_links;
create policy "photo_tag_links_select_own"
  on public.photo_tag_links for select
  using (auth.uid() = user_id);

drop policy if exists "photo_tag_links_insert_own" on public.photo_tag_links;
create policy "photo_tag_links_insert_own"
  on public.photo_tag_links for insert
  with check (auth.uid() = user_id);

drop policy if exists "photo_tag_links_update_own" on public.photo_tag_links;
create policy "photo_tag_links_update_own"
  on public.photo_tag_links for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "photo_tag_links_delete_own" on public.photo_tag_links;
create policy "photo_tag_links_delete_own"
  on public.photo_tag_links for delete
  using (auth.uid() = user_id);

-- 가상 폴더 --------------------------------------------------------------

create table if not exists public.photo_folders (
  user_id    uuid not null references auth.users (id) on delete cascade,
  id         text not null,
  name       text not null default '',
  sort_order integer not null default 0,
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, id)
);

create index if not exists photo_folders_user_idx
  on public.photo_folders (user_id);

alter table public.photo_folders enable row level security;

drop policy if exists "photo_folders_select_own" on public.photo_folders;
create policy "photo_folders_select_own"
  on public.photo_folders for select
  using (auth.uid() = user_id);

drop policy if exists "photo_folders_insert_own" on public.photo_folders;
create policy "photo_folders_insert_own"
  on public.photo_folders for insert
  with check (auth.uid() = user_id);

drop policy if exists "photo_folders_update_own" on public.photo_folders;
create policy "photo_folders_update_own"
  on public.photo_folders for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "photo_folders_delete_own" on public.photo_folders;
create policy "photo_folders_delete_own"
  on public.photo_folders for delete
  using (auth.uid() = user_id);

-- 사진 ↔ 가상 폴더 --------------------------------------------------------

create table if not exists public.photo_folder_items (
  user_id    uuid not null references auth.users (id) on delete cascade,
  folder_id text not null,
  photo_key text not null,
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, folder_id, photo_key)
);

create index if not exists photo_folder_items_user_idx
  on public.photo_folder_items (user_id, folder_id);

alter table public.photo_folder_items enable row level security;

drop policy if exists "photo_folder_items_select_own" on public.photo_folder_items;
create policy "photo_folder_items_select_own"
  on public.photo_folder_items for select
  using (auth.uid() = user_id);

drop policy if exists "photo_folder_items_insert_own" on public.photo_folder_items;
create policy "photo_folder_items_insert_own"
  on public.photo_folder_items for insert
  with check (auth.uid() = user_id);

drop policy if exists "photo_folder_items_update_own" on public.photo_folder_items;
create policy "photo_folder_items_update_own"
  on public.photo_folder_items for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "photo_folder_items_delete_own" on public.photo_folder_items;
create policy "photo_folder_items_delete_own"
  on public.photo_folder_items for delete
  using (auth.uid() = user_id);

-- 사진 신원 정보 ----------------------------------------------------------
-- photo_key 가 어떤 파일에서 유도됐는지를 남깁니다. 기기를 바꿨는데 키가
-- 어긋났을 때 사람이 대조해 볼 수 있는 최소한의 단서입니다. 메모·태그·폴더가
-- 붙은 사진의 것만 올라옵니다 (기기의 사진 전부가 아님).

create table if not exists public.photo_identities (
  user_id    uuid not null references auth.users (id) on delete cascade,
  photo_key  text not null,
  file_name  text not null default '',
  created_ms bigint not null default 0,
  width      integer not null default 0,
  height     integer not null default 0,
  updated_ms bigint  not null default 0,
  deleted    integer not null default 0,
  primary key (user_id, photo_key)
);

create index if not exists photo_identities_user_idx
  on public.photo_identities (user_id);

alter table public.photo_identities enable row level security;

drop policy if exists "photo_identities_select_own" on public.photo_identities;
create policy "photo_identities_select_own"
  on public.photo_identities for select
  using (auth.uid() = user_id);

drop policy if exists "photo_identities_insert_own" on public.photo_identities;
create policy "photo_identities_insert_own"
  on public.photo_identities for insert
  with check (auth.uid() = user_id);

drop policy if exists "photo_identities_update_own" on public.photo_identities;
create policy "photo_identities_update_own"
  on public.photo_identities for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "photo_identities_delete_own" on public.photo_identities;
create policy "photo_identities_delete_own"
  on public.photo_identities for delete
  using (auth.uid() = user_id);
