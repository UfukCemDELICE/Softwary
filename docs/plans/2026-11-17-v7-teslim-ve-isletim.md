# V7 Teslim ve işletim — Uygulama planı

**Goal:** `docs/specs/V7.md`'deki AC-V7-01..13'ü karşılamak: `ship` (prepare, check, pr), repro dilimi ve `repro` komutu, `drift` ve `architecture/drift.md`, `next`'in `ship` adımı, CI şablonu ve `ship`, `diagnose`, `maintain` skill'leri.

**Architecture:**
- Yeni mantık yeni dosyalarda:
  - `src/lib/ship.sh`: not üretimi, denetimi ve PR.
  - `src/lib/repro.sh`: geçici worktree, kopyalama, iki çalıştırma.
  - `src/lib/drift.sh`: öğe hesaplama, `drift.md` ayrıştırma.
- Var olan dosyalarda yalnızca çağrı ve küçük ekler:
  - `job.sh` (`sw_job_gate`: `guard`'dan sonra `repro`) ve `merge.sh` (birleştirmede `repro`);
  - `plan.sh` (`repro` alanı);
  - `guard.sh` (`SW_PROTECTED`'e `architecture/drift.md`);
  - `next.sh`, `doctor.sh`;
  - `src/templates/github/softwary.yml`.
- Entegrasyon ucunun denetimi `sw_queue_verify` (V4) ile yapılır, yeniden yazılmaz.
- Değişen dosya kümesi ve kapsamlı komut V6'nın `scoped.sh` yardımcılarıyla (`sw_scoped_list`, `sw_scoped_command`) kurulur.

**Tech Stack:** POSIX `sh`, `git`, `jq`, `gh` (sahte `gh` testlerde), `shellcheck`.

**Spec:** `docs/specs/V7.md` (approved). Bağlam:
- `docs/design.md` §3 İlke 1, 4 ve 10; §4, §5, §6.4, §6.5, §11.
- `docs/decisions.md`:
  - D-46 (`changes`), D-52 (dallar), D-84..D-87 (`guard`), D-98..D-112 (worktree, kuyruk, birleştirme, entegrasyon denetimi);
  - D-138..D-140 (kapsamlı denetim), D-144 (görünürlük), D-147 (fikstür), D-149 (`sw_rel`).

## Global Constraints

- Scriptler POSIX `sh`; yeni bağımlılık yok.
- `shellcheck -s sh -x` temiz; çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar, üstündeki yorum kriter kimliğini taşır; önce test, kırmızı, sonra kod.
- Paket içeriği ve fikstür stack'e özgü sözcük denetiminden geçer (AC-M0-09).
- Kararlar `docs/decisions.md`'ye "## V7" başlığı altında D-154'ten başlayarak; sapmalar kendi satırına.
- Dal `claude/zen-ramanujan-jy9sc6`; push ve PR'ı orkestratör yapar.
- softwary hiçbir yolda `deploy`'u çalıştırmaz ve üretim dalına push etmez ya da birleştirmez; bunu sınayan bir test olur (sahte `gh`'ın `pr merge` günlüğünde üretim PR'ı yoktur, `deploy` komutu bir işaret dosyası yazar ve dosya oluşmaz).

## Kararlar (decisions.md'ye girer)

- **D-154 Spec onayı:** V7 spec'i kullanıcı isteğiyle yazıldığı oturumda `approved` yapıldı (D-42, D-65, D-83, D-97, D-114, D-137).
- **D-155 Sürüm notu:** *insan onaylı (2026-11-17): not PR gövdesi ve durum kopyasıdır.*
  - **Yol:** `.softwary/state/releases/<sha7>.md`; üst satır `# Release <sha7>`, ardından `production: <sha>` ve `integration: <sha>` satırları.
  - **Bölüm sırası:** `## Range`, `## Specs`, `## Decisions`, `## Risk`, `## Waivers and findings`, `## Drift`, `## Observability`, `## Rollout`, `## Rollback`.
  - **Yeniden üretim:** hesaplanan bölümler her `prepare`'de yeniden yazılır. Yazılan üç bölüm, aynı dosya varsa ondan aynen taşınır (V5 `handoff`'taki `## Notes` taşımasıyla aynı yöntem).
  - **Hesaplanan bölümlerin kaynakları:**
    - `## Specs`: üretim ucundaki ve entegrasyon ucundaki dilim dosyalarının `status`'u karşılaştırılır (`git show <sha>:<yol>`). Entegrasyonda `done` olup üretimde `done` olmayanlar listelenir.
    - `## Decisions`: aralıkta eklenen ya da `status`'u değişen ADR'ler.
    - `## Risk`: aralıkta değişen her yol için `sw_path_tier`, en yüksek kademe ve R3 yollar.
    - `## Waivers and findings`: `sw_status_waivers`.
    - `## Drift`: `drift.md`'deki yürürlükteki kararlar.
- **D-156 `ship` denetimleri:**
  - **Uçlar:** dallar `sw_job_verify_base` gibi `origin/<ad>` öncelikli çözülür; `origin` varsa önce `git fetch`.
  - **Sıra:** dallar → var olma → ata ilişkisi (`git merge-base --is-ancestor`) → önde olma → `sw_queue_verify` → `drift` (1 ise `ship: drift has undecided or expired items (./softwary drift)`).
  - **Çıktı:** her ret tek satır `ship: ...`.
  - **`ship pr`:** `gh pr list --base <üretim> --head <entegrasyon> --state open --json number,url` ile açık PR'ı arar, sonra `gh pr create`. Sahte `gh` bu iki çağrıyı destekleyecek biçimde genişletilir (`tests/lib.sh`).
- **D-157 Repro kanıtı:** *insan onaylı (2026-11-17): kapı test önceliğini hesapla kanıtlar.*
  - **Alan:** dilim üst bilgisinde `repro` (boşlukla ayrılmış yollar).
  - **Komut:** `repro <iş> [--base <ref>]`. İş `NNN-S<n>`; taban verilmezse `integration_branch`. Dilim, `guard` gibi ortak atadaki sürümden okunur (D-84): iş kendi `repro`'sunu silerek kaçamaz. Tabanda dilim yoksa çalışma ağacındaki sürüm okunur.
  - **Taban çalıştırması:** ortak ata `git worktree add --detach` ile `.softwary/state/repro/<iş>`'e açılır ve orada `bootstrap` çalışır (`NONE` ise atlanır). Repro dosyaları işin `HEAD`'inden kopyalanır ve `test_files` (`{files}` = repro yolları) çalışır. Çıkış 0 değilse "fails on the base".
  - **İş çalıştırması:** işin çalışma ağacında aynı komut; çıkış 0 olmalı.
  - **Değişmemiş repro:** tabanla `HEAD` arasında değişmeyen repro yolu `is not changed by the job`.
  - **Günlükler:** `.softwary/state/logs/repro-<iş>-base.log` ve `-job.log`.
  - **Temizlik:** geçici worktree bir `trap` ile silinir; testte kalmadığı sınanır.
- **D-158 Kapı ve birleştirme:** `sw_job_gate`'te `guard` geçtikten sonra `sw_wt_softwary <iş> repro <iş> --base <taban>` çalışır:
  - 1 → `gate_fail "<ilk satır>"`, `verify` çalışmaz;
  - 2 → çıktı ve 2.

  `merge.sh`'nin yeniden hesaplanan koşullarına `guard`'ın yanına `repro` eklenir; sorun varsa `sw_merge_refuse`. Kararsız test yeniden denemesi (`verify` için olan) `repro`'ya uygulanmaz: tabanda geçen repro deterministik bir kanıt eksiğidir.
- **D-159 Drift:** *insan onaylı (2026-11-17): drift döngüyü değil `ship`'i durdurur.*
  - **Öğeler ve kaynakları:**
    - `uncovered`: `git ls-files` ile `src_paths` altındaki izlenen dosyalar; bir düğümün `metadata.paths` girdisine eşit ya da altında olmayan.
    - `missing`, `empty`, `planned-with-code`: düğüm `paths`'i ve `status`'u.
    - `unexercised <EX>`: `PRODUCT.md`'deki her `EX-F<n>-NN` için, spec'lerde ona bağlanan kriter kimlikleri (`plan.sh`'deki bağlantı ayrıştırması) ve bunlardan en az birinin `git grep` ile `test_paths` altında geçmesi.
  - **Satır biçimi:** `drift: <öğe>: <durum>`, sonra `drift: N item(s), M undecided`.
  - **`drift.md`:** şablon `src/templates/artifacts/drift.md`. Tabloda `Item` sütunu öğe metniyle birebir aynıdır (`uncovered app/x.sh`). `fix` kararı var olan bir spec numarası ister. Tarih ve gerekçe kuralı muafiyetlerinkiyle aynıdır (`sw_valid_date`).
  - **Koruma:** `SW_PROTECTED`'e `architecture/drift.md` eklenir.
  - **Model yoksa:** `drift: no model` ve 2.
- **D-160 `next`:** `none` dalında entegrasyon ucu üretim ucunun önündeyse (yerel ya da `origin` refleri, `fetch` yok: `next` yalnızca okur) `ship (<n> commits ahead of <üretim>)`. Üretim dalı ayarlı değil ya da yoksa `none` kalır.
- **D-161 CI şablonu:** `pull_request.branches: [UNSET, UNSET]`; `doctor`'un `UNSET` denetimi ikisini de yakalar. `setup` ikinci girdiye üretim dalını yazar. Mevcut projelerde iş akışı projeye aittir ve kendiliğinden değişmez; `upgrade` notu ve `setup` metni bunu söyler.
- **D-162 Skill'ler:** `src/skills/ship/SKILL.md`, `src/skills/diagnose/SKILL.md` ve `src/skills/maintain/SKILL.md`. `run` skill'i `next`'in `ship` adımını insana bildirir; kendisi `ship pr` açmaz. `plan` skill'ine repro alanı eklenir.
- **D-163 Test düzeneği:**
  - **`tests/lib.sh`:** sahte `gh`'a `pr list --base --head --state open` ve `pr create --base` desteği; `add_production` (`master` dalını ilk commit'ten açar ve `origin`'e iter); `add_repro_slice`.
  - **Uçtan uca test:** `tests/ship_e2e_test.sh`, V6 fikstürü üzerinde (`add_existing`, `existing_conf`, `add_existing_artifacts`).
  - **Fikstür:** `app/report.sh`'ye bilinen bir hata eklenir (ya da var olan bir hata kullanılır). Hata, `checks/test.sh` ile çalışan bir repro testiyle yeniden üretilir.

## Review Focus

1. `repro`'nun taban çalıştırması ana checkout'u ve işin worktree'sini kirletmemeli. Geçici worktree her çıkışta (hata dahil) silinmeli (T2).
2. `repro` dilimi ortak atadan okunmalı: işin kendi `repro` alanını silmesi ya da değiştirmesi kanıtı atlatmamalı (T2).
3. `ship prepare`'in yazılan bölümleri taşıması: aynı uçta yeniden çalışma insanın yazdığını silmemeli; uç değişince yeni dosya oluşmalı (T1).
4. `drift`'in `uncovered` hesabı `src_paths = .` ve iç içe düğüm yollarıyla doğru olmalı; üretilen dosyalar (`.claude/`, `.cursor/`, `.agents/`, `.codex/`, `architecture/views/`) ve `.softwary/` `src_paths` dışındaysa sayılmamalı (T3).
5. Hiçbir yol `deploy`'u çalıştırmamalı ya da üretim PR'ını birleştirmemeli (T5).
6. `next` hâlâ yalnızca okur: `fetch` yok (T4).

---

### Task 1: `ship prepare` ve `ship check` (AC-V7-01, 02, 03)

**Files:**
- Create: `src/lib/ship.sh`, `src/templates/artifacts/release.md` (gerekirse), `tests/ship_test.sh`.
- Modify: `src/bin/softwary` (source, `ship`, `help`), `tests/lib.sh` (`add_production`).

- [ ] `test_ac_v7_01_*`: her ret ayrı test (dallar, üretim yok, ayrışmış üretim, gönderilecek bir şey yok, kırmızı entegrasyon, drift); hiçbir dosya yazılmaz.
- [ ] `test_ac_v7_02_*`: bölümler ve hesaplanan içerik (iki `done` dilim, bir ADR, R3 yol, bir muafiyet); yazılan bölümlerin yeniden çalışmada korunması; uç değişince yeni dosya.
- [ ] `test_ac_v7_03_*`: `UNSET` bölüm, bayat not, temiz not.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 2: Repro dilimi ve `repro` (AC-V7-05, 06, 07)

**Files:**
- Create: `src/lib/repro.sh`, `tests/repro_test.sh`.
- Modify: `src/lib/plan.sh`, `src/lib/doctor.sh`, `src/lib/job.sh`, `src/lib/merge.sh`, `src/templates/artifacts/slice.md` (yorumda `repro`), `src/bin/softwary`, `tests/lib.sh` (`add_repro_slice`).

- [ ] `test_ac_v7_05_*`: `test_paths` dışı yol, `touches` dışı yol, `test_files` `UNSET`/`NONE`.
- [ ] `test_ac_v7_06_*`:
  - tabanda düşüp işte geçen → 0;
  - tabanda geçen → 1 ve satır;
  - işte düşen → 1;
  - değişmemiş repro → 1;
  - repro'suz dilim → `repro: none`;
  - geçici worktree kalmaz;
  - iş kendi dilimindeki `repro`'yu silince taban sürümü kullanılır.
- [ ] `test_ac_v7_07_gate_fails_on_repro`, `..._gate_passes`, `..._merge_recomputes`.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: Drift (AC-V7-08)

**Files:**
- Create: `src/lib/drift.sh`, `src/templates/artifacts/drift.md`, `tests/drift_test.sh`.
- Modify: `src/lib/guard.sh`, `src/bin/softwary`.

- [ ] `test_ac_v7_08_*`:
  - her öğe türü için ayrı test;
  - karar türleri (`accept`, `blueprint`, `fix <spec>`, var olmayan spec);
  - süresi dolmuş, bayat karar, geçersiz tarih, boş gerekçe;
  - `src_paths = .` ve iç içe düğüm yolları, üretilen dosyalar sayılmaz;
  - `drift.md` korunan yol;
  - `drift` `verify`'da yok.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: `ship pr`, `next`, CI şablonu (AC-V7-04, 09, 10)

**Files:**
- Modify: `src/lib/ship.sh`, `src/lib/next.sh`, `src/templates/github/softwary.yml`, `tests/lib.sh` (sahte `gh`), `tests/ci_test.sh`, `tests/next_test.sh`.

- [ ] `test_ac_v7_04_*`: PR açılır (taban, baş, başlık, gövde), olay günlüğünde `ship_pr`; açık PR varsa yeni PR yok; `ship check` kirliyse PR yok.
- [ ] `test_ac_v7_09_next_ship`, `..._no_production_stays_none`.
- [ ] `test_ac_v7_10_ci_pull_request_branches`. Eski CI testleri dal listesine göre güncellenir; gerekçesi PR'da.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: Skill'ler ve uçtan uca test (AC-V7-11, 12, 13)

**Files:**
- Create: `src/skills/ship/SKILL.md`, `src/skills/diagnose/SKILL.md`, `src/skills/maintain/SKILL.md`, `tests/ship_e2e_test.sh`.
- Modify: `src/skills/run/SKILL.md`, `src/skills/plan/SKILL.md`, `src/skills/setup/SKILL.md`, `tests/skill_test.sh`, `docs/decisions.md`, `docs/roadmap.md`, `docs/sources.md`, `docs/design.md` (§6.5 ve §11 yalnızca gerekiyorsa).

- [ ] `test_ac_v7_11_*`:
  - `ship` skill'i PR'ı birleştirmez ve `deploy`'u insana bırakır;
  - `diagnose` önce kırmızı testi yazar ve örneği olmayan davranışı insana gönderir;
  - `maintain` her öğe için karar sorar;
  - 80 satır; yalnızca `help` komutları;
  - üç araçta dağıtılır.
- [ ] `test_ac_v7_12_*`:
  1. Hata → repro dilimi → kapıda kanıt → birleşme.
  2. Tabanda da geçen repro → `gate_fail`.
  3. Kararsız drift → `ship prepare` 1; kararla → not.
  4. Not doldurulur → `ship check` → `ship pr` → üretime PR.
  5. `deploy` hiç çalışmadı, üretim PR'ı birleşmedi.
- [ ] Bütün suite, `shellcheck`, mutasyon denetimi (her yeni kural bir kez bozulur, ilgili test kırmızı; kararlara bir satır).
- [ ] `decisions.md` "## V7" (D-154..D-163, sapmalar, değişen eski testler), `roadmap.md` V7 notu, `sources.md` durum hücreleri (sistematik hata ayıklama, drift, teslim).
- [ ] Commit.

## AC → test eşlemesi

| AC | Test |
| --- | --- |
| AC-V7-01..03 | `ship_test.sh` |
| AC-V7-04 | `ship_test.sh` |
| AC-V7-05..07 | `repro_test.sh` |
| AC-V7-08 | `drift_test.sh` |
| AC-V7-09 | `next_test.sh` |
| AC-V7-10 | `ci_test.sh` |
| AC-V7-11 | `skill_test.sh` |
| AC-V7-12 | `ship_e2e_test.sh` |
| AC-V7-13 | bütün suite |
