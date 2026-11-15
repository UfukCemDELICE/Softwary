# V1 Deneme düzeltmeleri — Uygulama planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `docs/specs/V1.md`'deki AC-V1-01..09'u karşılamak: dal ayarları ve varsayılan taban, bayraksız `verify`'da `adr` ve `changes`, süreli muafiyetler, dürüst `doctor`, isteğe bağlı `CODEOWNERS`, dalı `UNSET` gelen CI şablonu, güncellenmiş `setup`, `implement` ve `review` skill'leri.

**Architecture:** Mevcut düzenin üstüne biner. Dal ayarları `commands.conf`'un ayar anahtarlarına (`SW_SETTING_KEYS`) eklenir; varsayılan tabanı tek bir yardımcı (`sw_default_base`, `src/lib/adr.sh`) çözer ve `verify`, `adr`, `changes`, `risk` onu kullanır. Muafiyetler yeni bir dosyada (`src/lib/waivers.sh`) ayrıştırılır; `verify` ve `doctor` onu kaynaklar. `install.sh` boş `waivers.conf`'u projeye ait dosya olarak kurar.

**Tech Stack:** POSIX `sh`, `git`, `jq`, `shellcheck`. Test düzeneği `tests/lib.sh` (`sh tests/run.sh`).

**Spec:** `docs/specs/V1.md` (approved). Bağlam: `docs/design.md` (v2), `docs/decisions.md` (D-01..D-51).

## Global Constraints

- Scriptler POSIX `sh`; ek bağımlılık yok; `shellcheck -s sh` temiz.
- Çıkış kodları `0/1/2`; paket içeriği İngilizce, `docs/` Türkçe.
- Her test `test_` ile başlar, üstündeki yorum kriter kimliğini taşır.
- Önce test yazılır, kırmızı görülür, sonra kod.
- Kararlar `docs/decisions.md`'ye "V1" başlığı altında D-52'den başlayarak yazılır.
- Dal `claude/zen-ramanujan-jy9sc6`; PR yalnızca istenince açılır.

## Kararlar (onayla birlikte decisions.md'ye girer)

İlkelerle verdiğim, spec'in "yapıcının takdiri"ne ya da boşluğuna düşen kararlar:

- **D-52 Dal ayarları:** `integration_branch` ve `production_branch` ayar anahtarıdır; değer `git check-ref-format --branch` ile geçerli bir dal adı olmalıdır (değilse `commands.conf` hatası, 2). `UNSET` ya da yok, "ayarlı değil" demektir. Şablon ikisini `UNSET` taşır. `verify --fast` dal ayarına bakmaz: commit hook'u dal ayarı yüzünden kilitlenmez (ilke: geri alınabilir olanda engelleme). `production_branch`'i V1'de hiçbir komut kullanmaz; yalnızca `doctor` denetler (V7 teslimi için yer tutar).
- **D-53 Varsayılan taban:** `--base` yoksa taban `integration_branch`'teki addır, `origin/` önekine geri düşülmez (tek doğru kaynak; CI PR'da tabanı açıkça verir). Commit varken o ref yoksa çıktı `--base`'i önerir, 2.
- **D-54 Commit'siz repo:** `HEAD` yoksa bayraksız `verify` `adr` ve `changes` satırlarında `SKIP (no commits yet)` yazar. Tek başına çalışan `adr` ve `changes` de aynı mesajla 0 verir (boş repoda ilk adım engellenmez). `risk` değişmez (dilimsiz bir değişiklik henüz yok). `--base` açıkça verilmiş ve commit yoksa 2 sürer.
- **D-55 Muafiyet biçimi:** `<anahtar> = <YYYY-MM-DD>: <gerekçe>`; `#` ve boş satırlar yok sayılır. Anahtar yalnızca `verify`'ın çalıştırdığı proje denetimleridir (`SW_VERIFY_KEYS`). Tarih takvimde geçerli olmalıdır (ay 01–12, artık yıl dahil gün sınırı). Muafiyet tarihin sonuna kadar geçerlidir; bugünün tarihi `date +%Y-%m-%d` (yerel saat) ile alınır ve dizge olarak karşılaştırılır. Testler 2000 ve 2999 yıllarını kullanır, saat kancası eklenmez.
- **D-56 Muafiyetin etki alanı:** Muafiyet `--fast`'te de uygulanır (aynı denetim iki modda farklı sonuç vermesin). Özet satırı `N passed, M failed, K skipped, W waived` olur. Ayarlanmamış ya da `NONE` olan bir denetimin muafiyeti satırı değiştirmez (`SKIP` kalır). `waivers.conf` yoksa muafiyet yoktur, hata değildir.
- **D-57 `doctor` satırları:** Yapılandırılmış komut anahtarı `PASS (configured, not run)`, `NONE` olan `SKIP (<gerekçe>)`; ikisi de sorun değildir. Etkin muafiyet `waiver <anahtar>` satırında `WAIVED (<gerekçe>, until <tarih>)` (sorun değil); süresi dolmuş muafiyet `FAIL (expired <tarih>: <gerekçe>)` (sorun: bayat yapılandırma). Commit varken `integration_branch`'in ref'i yoksa o da FAIL (verify'ın 2 vereceğini önceden söyler).
- **D-58 İş akışı:** Şablon `pull_request` ve `push` altında `branches: [UNSET]` taşır; `doctor` yorum dışındaki her `UNSET` satırını ayrı satırda bildirir (önceden yalnızca ilki).
- **D-59 Boş repoda `setup`:** Model çıkarılmaz; `setup`, `src_paths` dizinlerini `.gitkeep` ile oluşturur ve `doctor`'da yalnızca `model` satırı kalınca biter, sonraki adım olarak `discover` ve `architect`'i söyler.
- **D-60 Test düzeneği:** `setup_repo` `git init -b main` ile başlar; `conf_all` `integration_branch = main` ve `production_branch = master` yazar. Satır numarasına bağlı eski testler kayarsa güncellenir ve PR'da listelenir (D-47 gibi).

## Review Focus

Spec'in ima ettiği ama kriterlerin doğrudan sınamadığı girdiler; her birinin testi sahibi task'tadır:

1. Entegrasyon dalının kendisinde çalışan bayraksız `verify` (`HEAD` = taban): yalnızca commit'lenmemiş ve izlenmeyen değişiklikler sayılır, çökme yok (T2).
2. `waivers.conf`'ta `2026-02-29` (artık olmayan yıl), `2028-02-29` (geçerli), `2026-13-01`, `2026-1-01` (T3).
3. Gerekçede `:` geçmesi (`2999-01-01: tool X: broken`) — ilk `: ` ayırır (T3).
4. Pre-push hook'u artık `adr` ve `changes`'i çalıştırır; `hooks_test`'teki push senaryosu `src/` değişikliği olmadan geçmeye devam eder (T2).
5. `upgrade` var olan `waivers.conf`'u ezmez, yoksa oluşturur (T3).

---

### Task 1: Dal ayarları ve varsayılan taban (AC-V1-01)

**Files:** Modify `src/lib/config.sh` (`SW_SETTING_KEYS`, dal adı denetimi), `src/lib/adr.sh` (`sw_default_base NAME`), `src/lib/changes.sh`, `src/lib/risk.sh` (`main` sabiti yerine `sw_default_base`), `src/lib/doctor.sh`, `src/templates/commands.conf`, `tests/lib.sh` (D-60). Test: `tests/branches_test.sh` (yeni).

- [ ] `test_ac_v1_01_doctor_reports_each_missing_branch`: ikisi de yokken `doctor` `integration_branch FAIL (...)` ve `production_branch FAIL (...)` ayrı satırlarda, 2; yalnızca biri yokken yalnızca o satır.
- [ ] `test_ac_v1_01_invalid_branch_name`: `integration_branch = a..b` → `commands.conf` satır numarasıyla 2.
- [ ] `test_ac_v1_01_default_base_is_integration_branch`: `integration_branch = trunk`, `trunk`'tan dallanıp model değiştir → `adr`, `changes`, `risk` bayraksız `trunk`'a karşı sonuç verir (`main` yok); `--base` verilince o kullanılır.
- [ ] `test_ac_v1_01_unset_branch_exits_2`: ayar yokken bayraksız `adr`, `changes`, `risk 001`, `verify` 2 ve mesaj `integration_branch`'i adıyla anar; `--base` ile çalışırlar.
- [ ] `test_ac_v1_01_doctor_branch_ref_missing`: commit var, `integration_branch = trunk` ama dal yok → `doctor` FAIL (D-57).
- [ ] Kırmızıyı gör, uygula, yeşili gör, commit.

### Task 2: Bayraksız `verify`'da `adr` ve `changes` (AC-V1-02)

**Files:** Modify `src/lib/verify.sh`, `src/lib/adr.sh`, `src/lib/changes.sh` (D-54). Test: `tests/verify_test.sh`, `tests/hooks_test.sh` (gerekirse).

- [ ] `test_ac_v1_02_bare_verify_runs_adr_and_changes_after_trace`: satır sırası `sync model views trace adr changes`, sonra proje denetimleri.
- [ ] `test_ac_v1_02_bare_verify_gates_against_integration_branch`: dalda `src/` değişikliği dilimsiz → bayraksız `verify` 1, `changes FAIL`; model değişikliği ADR'siz → `adr FAIL`.
- [ ] `test_ac_v1_02_no_commits_yet`: commit'siz repoda `adr` ve `changes` satırları `SKIP (no commits yet)`, çıkış kodu proje denetimlerine göre; tek başına `adr` ve `changes` 0.
- [ ] `test_ac_v1_02_branch_missing_exits_2`: commit var, `integration_branch`'teki dal yok → bayraksız `verify` 2.
- [ ] `test_ac_v1_02_fast_skips_both`: `--fast` çıktısında `adr` ve `changes` yok; dal ayarı yokken de `--fast` çalışır (D-52).
- [ ] `test_ac_v1_02_on_integration_branch_itself`: `HEAD` = `main`, temiz ağaç → `adr` ve `changes` PASS (Review Focus 1).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 3: Muafiyetler (AC-V1-03, AC-V1-04)

**Files:** Create `src/lib/waivers.sh`, `src/templates/waivers.conf`, `tests/waivers_test.sh`. Modify `src/bin/softwary` (kaynakla), `src/lib/verify.sh`, `src/lib/doctor.sh`, `install.sh` (`owned` listesine `waivers.conf`).

- [ ] `test_ac_v1_03_active_waiver_waives_failure`: `security = false`, `security = 2999-12-31: CVE triage` → satır `WAIVED (CVE triage, until 2999-12-31)`, başka hata yoksa 0, özet `1 waived`.
- [ ] `test_ac_v1_03_expired_waiver_keeps_fail`: tarih `2000-01-01` → `FAIL` ve satırda `waiver expired 2000-01-01`, 1.
- [ ] `test_ac_v1_03_passing_check_with_waiver`: `security = true` → `PASS (waiver no longer needed)`.
- [ ] `test_ac_v1_03_waiver_applies_in_fast`: `lint` muafiyeti `--fast`'te de `WAIVED` (D-56).
- [ ] `test_ac_v1_04_invalid_waivers_exit_2_with_line`: bozuk satır, `2026-02-29`, `2026-13-01`, `2026-1-01`, boş gerekçe, yinelenen anahtar, tanınmayan anahtar (`deploy_check`), paket denetimi anahtarı (`trace`) → her biri `waivers.conf:<satır>:` ile, `verify` 2 (`--fast` dahil); `2028-02-29` ve gerekçede `:` geçerli.
- [ ] `test_ac_v1_04_doctor_lists_waivers`: bir etkin, bir süresi dolmuş muafiyet → iki ayrı satır (D-57), süresi dolan sorun sayılır; bozuk dosya satır numaralı FAIL.
- [ ] `test_ac_v1_04_install_and_upgrade_keep_waivers`: kurulum boş `waivers.conf` koyar; var olanı `install.sh` ve `upgrade` ezmez (Review Focus 5).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 4: Dürüst `doctor` ve isteğe bağlı `CODEOWNERS` (AC-V1-05, AC-V1-06)

**Files:** Modify `src/lib/doctor.sh`. Test: `tests/doctor_test.sh`, `tests/ci_test.sh`.

- [ ] `test_ac_v1_05_configured_not_run`: komut anahtarları `PASS (configured, not run)`; `NONE: reason` → `SKIP (reason)`; `UNSET` → FAIL (değişmez).
- [ ] `test_ac_v1_06_codeowners_optional`: `.github/CODEOWNERS` yokken `CODEOWNERS SKIP (optional)` ve başka sorun yoksa `doctor` 0.
- [ ] `test_ac_v1_06_codeowners_checked_when_present`: varken kapsama ve `UNSET` denetimleri sürer (mevcut `test_ac_m3_05_*` testleri bunu zaten sınar; eksik dosya beklentisi güncellenir).
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 5: CI şablonu (AC-V1-07)

**Files:** Modify `src/templates/github/softwary.yml`, `src/lib/doctor.sh` (D-58), `tests/lib.sh` (`add_ci` dalları da doldurur). Test: `tests/ci_test.sh`.

- [ ] `test_ac_v1_07_template_branches_unset`: şablonda `pull_request` ve `push` altında `branches: [UNSET]`; PR adımı `verify --base "origin/$BASE_REF"`, push adımı bayraksız `verify`.
- [ ] `test_ac_v1_07_doctor_reports_each_unset_line`: kopyalanmış şablonla `doctor` üç ayrı `workflow FAIL (... UNSET (line N))` satırı; doldurulunca PASS.
- [ ] `test_ac_m3_06_workflow_triggers_and_checkout` güncellenir (`branches: [main]` → `[UNSET]`); PR'da listelenir.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 6: Skill'ler (AC-V1-08)

**Files:** Modify `src/skills/setup/SKILL.md`, `src/skills/implement/SKILL.md`, `src/skills/review/SKILL.md`, `src/agents/implementer.md`, `src/agents/reviewer.md` (aynı kural). Test: `tests/skill_test.sh`.

- [ ] `test_ac_v1_08_setup_asks_branches_and_ci_toolchain`: `setup` `integration_branch`, `production_branch` ve CI'daki `Install tools` adımını anar.
- [ ] `test_ac_v1_08_setup_branch_protection`: dal korumasında CI'ı (`softwary` check) şart koşmayı söyler; "Require review from Code Owners"ı istemez, insan incelemesini şart koşmamayı söyler.
- [ ] `test_ac_v1_08_setup_empty_and_existing_repo`: boş repo: model çıkarmaz, sonraki adım `discover` ve `architect` (D-59); mevcut repo: taban çizgisi ADR'sine her bileşenin dayandığı yollar yazılır.
- [ ] `test_ac_v1_08_implement_fast_then_full_verify`: `implement` ve `implementer` yineleme sırasında `./softwary verify --fast`, `review`'a vermeden önce `./softwary verify`; `review` sabit `--base main` kullanmaz.
- [ ] 80 satır sınırı ve tanınan komut testleri (AC-M4-02) yeşil kalır.
- [ ] Kırmızı, uygula, yeşil, commit.

### Task 7: Bütünleşme (AC-V1-09)

- [ ] `sh tests/run.sh` tam çıktı; `shellcheck -s sh -x install.sh src/bin/softwary src/lib/*.sh src/targets/*.sh src/hooks/* src/templates/softwary tests/*.sh` temiz.
- [ ] Mutasyon denetimi: muafiyet tarih karşılaştırması, `no commits yet` dalı, varsayılan taban ve CODEOWNERS `SKIP` sed ile bozulup testin kızardığı görülür.
- [ ] Güncellenen eski testler ve gerekçeleri listelenir (beklenen: `ci_test` iş akışı dalı ve eksik CODEOWNERS, satır numarası kayan `config`/`doctor` testleri, `review` skill metni).
- [ ] `docs/decisions.md`'ye D-52..D-60; `docs/roadmap.md`'de V1 durum notu.
- [ ] AC → test tablosu raporlanır.

## AC → test eşlemesi

| AC | Testler |
| --- | --- |
| AC-V1-01 | `branches_test.sh`: `test_ac_v1_01_*` (5) |
| AC-V1-02 | `verify_test.sh`: `test_ac_v1_02_*` (6) |
| AC-V1-03 | `waivers_test.sh`: `test_ac_v1_03_*` (4) |
| AC-V1-04 | `waivers_test.sh`: `test_ac_v1_04_*` (3) |
| AC-V1-05 | `doctor_test.sh`: `test_ac_v1_05_configured_not_run` |
| AC-V1-06 | `ci_test.sh`: `test_ac_v1_06_*` (2) |
| AC-V1-07 | `ci_test.sh`: `test_ac_v1_07_*` (2) + güncellenen `test_ac_m3_06_*` |
| AC-V1-08 | `skill_test.sh`: `test_ac_v1_08_*` (4) |
| AC-V1-09 | `sh tests/run.sh` tamamı + `shellcheck` + güncellenen test listesi |
