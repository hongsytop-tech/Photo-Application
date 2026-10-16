-- 폴더 트리 — photo_folders.parent_id
--
-- 폴더가 폴더를 품을 수 있게 되었습니다. 뿌리 폴더는 parent_id 가 빈
-- 문자열입니다. NULL 이 아니라 '' 인 이유: 동기화는 값이 없는 칸을 빼고
-- 넣어 테이블 기본값에 맡기는데, 뿌리를 NULL 로 두면 "아직 안 올라온 값"과
-- "뿌리"를 구분할 수 없습니다.
--
-- 이 파일을 아직 돌리지 않아도 앱은 깨지지 않습니다. 내려받기가 모르는 칸을
-- 빼고 넣으므로 parent_id 는 기본값('')으로 남고, 폴더는 전부 뿌리로 보입니다.
-- 다만 트리 구조는 이 마이그레이션을 돌리기 전까지 기기 간에 오가지 않습니다.
alter table public.photo_folders
  add column if not exists parent_id text not null default '';

create index if not exists photo_folders_parent_idx
  on public.photo_folders (user_id, parent_id);
